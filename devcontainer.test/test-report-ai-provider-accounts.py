#!/usr/bin/env python3
"""Contract tests for the combined AI provider account report."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "scripts" / "report-ai-provider-accounts.py"
SPEC = importlib.util.spec_from_file_location("report_ai_provider_accounts", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def write_json(path: pathlib.Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def make_registry(
    base: pathlib.Path,
    owner: dict,
    prefix: str,
    *,
    escrow: bool = True,
    account_id: str | None = None,
    account_owner: dict | None = None,
    credential_ids: list[str] | None = None,
    account_extra: dict | None = None,
) -> pathlib.Path:
    root = base / prefix
    account_id = account_id or f"{prefix}.claude.account"
    credential_id = f"{prefix}.claude.credential"
    profile_name = f"{prefix}-profile"
    credential_ref = f"ai/secrets/claude/{profile_name}.credentials.sops.yaml"
    source = {
        "version": 1,
        "kind": "workbenches-ai-profile-source",
        "owner": owner,
        "profiles": {
            "claude": [
                {
                    "name": profile_name,
                    "email": f"{prefix}@example.test",
                    "family": prefix,
                    "aliases": [],
                    "plan": "team",
                    "workspace": prefix,
                    "status": "active",
                    "owner": owner,
                    "accountId": account_id,
                    "credentialId": credential_id,
                    "authentication": {
                        "type": "subscription_oauth",
                        "accountId": account_id,
                        "credentialRef": credential_ref,
                        "escrowStatus": "available" if escrow else "not-escrowed",
                    },
                }
            ]
        },
    }
    write_json(root / "ai" / "source.json", source)
    write_json(
        root / "ai" / "accounts" / "providers.json",
        {
            "schemaVersion": 1,
            "kind": "workbenches-ai-provider-catalog",
            "owner": owner,
            "providers": [
                {
                    "providerId": "anthropic",
                    "displayName": "Anthropic",
                    "profileProviderIds": ["claude"],
                    "products": ["claude", "claude-code"],
                }
            ],
        },
    )
    account = {
        "accountId": account_id,
        "owner": account_owner or owner,
        "providerId": "anthropic",
        "login": {"email": f"{prefix}@example.test"},
        "products": ["claude", "claude-code"],
        "subscription": {"plan": "team", "billingModel": "unknown"},
        "status": "active",
        "profileRefs": [{"provider": "claude", "name": profile_name}],
        "credentialIds": credential_ids or [credential_id],
        "verifiedAt": None,
        "notes": [],
    }
    account.update(account_extra or {})
    write_json(
        root / "ai" / "accounts" / "anthropic.json",
        {
            "schemaVersion": 1,
            "kind": "workbenches-ai-account-catalog",
            "owner": owner,
            "providerId": "anthropic",
            "accounts": [account],
        },
    )
    if owner["type"] == "tenant":
        write_json(
            root / "ai" / "vault" / "azure-key-vault.json",
            {
                "schemaVersion": 1,
                "kind": "opensoft-ai-credential-vault",
                "owner": owner,
                "tenantId": "tenant",
                "subscriptionId": "subscription",
                "vaultName": "kv-example",
                "entries": (
                    [
                        {
                            "provider": "claude",
                            "registryProvider": "claude",
                            "profile": profile_name,
                            "credentialId": credential_id,
                            "secretName": f"ai-credential-claude-{profile_name}",
                            "enabled": True,
                            "lifecycle": "active",
                        }
                    ]
                    if escrow
                    else []
                ),
            },
        )
    elif escrow:
        ciphertext = root.joinpath(*pathlib.PurePosixPath(credential_ref).parts)
        ciphertext.parent.mkdir(parents=True, exist_ok=True)
        ciphertext.write_text("sops: encrypted fixture\n", encoding="utf-8")
    return root


def codes(report: dict) -> set[str]:
    return {finding["code"] for finding in report["findings"]}


class AccountReportTests(unittest.TestCase):
    def test_valid_combined_registries(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = pathlib.Path(temporary)
            company = make_registry(base, {"type": "tenant", "id": "opensoft"}, "company")
            personal = make_registry(base, {"type": "user", "id": "brettheap"}, "personal")
            report = MODULE.combine([MODULE.load_registry(company), MODULE.load_registry(personal)])
            self.assertTrue(report["valid"])
            self.assertEqual(report["findings"], [])
            self.assertEqual(len(report["summary"]), 2)

    def test_cross_owner_duplicate_account_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = pathlib.Path(temporary)
            shared = "shared.anthropic.account"
            company = make_registry(base, {"type": "tenant", "id": "opensoft"}, "company", account_id=shared)
            personal = make_registry(base, {"type": "user", "id": "brettheap"}, "personal", account_id=shared)
            report = MODULE.combine([MODULE.load_registry(company), MODULE.load_registry(personal)])
            self.assertIn("duplicate-account", codes(report))

    def test_cross_owner_duplicate_credential_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = pathlib.Path(temporary)
            company = make_registry(base, {"type": "tenant", "id": "opensoft"}, "shared")
            personal = make_registry(base, {"type": "user", "id": "brettheap"}, "shared-personal")
            personal_source_path = personal / "ai" / "source.json"
            personal_source = json.loads(personal_source_path.read_text(encoding="utf-8"))
            personal_source["profiles"]["claude"][0]["credentialId"] = "shared.claude.credential"
            write_json(personal_source_path, personal_source)
            personal_accounts_path = personal / "ai" / "accounts" / "anthropic.json"
            personal_accounts = json.loads(personal_accounts_path.read_text(encoding="utf-8"))
            personal_accounts["accounts"][0]["credentialIds"] = ["shared.claude.credential"]
            write_json(personal_accounts_path, personal_accounts)
            report = MODULE.combine([MODULE.load_registry(company), MODULE.load_registry(personal)])
            self.assertIn("duplicate-credential", codes(report))

    def test_orphan_credential_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = make_registry(
                pathlib.Path(temporary),
                {"type": "user", "id": "brettheap"},
                "personal",
                credential_ids=["unknown.credential"],
            )
            report = MODULE.combine([MODULE.load_registry(root)])
            self.assertIn("orphan-credential-ref", codes(report))

    def test_inconsistent_account_owner_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = make_registry(
                pathlib.Path(temporary),
                {"type": "user", "id": "brettheap"},
                "personal",
                account_owner={"type": "tenant", "id": "opensoft"},
            )
            report = MODULE.combine([MODULE.load_registry(root)])
            self.assertIn("owner-mismatch", codes(report))

    def test_forbidden_secret_field_is_rejected_without_value_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = "sk-this-value-must-never-be-printed"
            root = make_registry(
                pathlib.Path(temporary),
                {"type": "user", "id": "brettheap"},
                "personal",
                account_extra={"apiKey": candidate},
            )
            report = MODULE.combine([MODULE.load_registry(root)])
            self.assertIn("forbidden-secret-field", codes(report))
            self.assertNotIn(candidate, json.dumps(report))

    def test_token_like_value_is_suppressed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            candidate = "eyJabcdefghijklmnop.eyJabcdefghijklmnop.abcdefghijklmnopqr"
            root = make_registry(
                pathlib.Path(temporary),
                {"type": "user", "id": "brettheap"},
                "personal",
                account_extra={"notes": [candidate]},
            )
            report = MODULE.combine([MODULE.load_registry(root)])
            self.assertIn("token-like-value", codes(report))
            self.assertNotIn(candidate, json.dumps(report))

    def test_active_missing_escrow_is_reported_and_strict_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = make_registry(
                pathlib.Path(temporary),
                {"type": "user", "id": "brettheap"},
                "personal",
                escrow=False,
            )
            report = MODULE.combine([MODULE.load_registry(root)])
            self.assertIn("missing-escrow", codes(report))
            output = io.StringIO()
            with mock.patch.object(sys, "argv", ["report", "--registry", str(root), "--strict"]):
                with contextlib.redirect_stdout(output):
                    self.assertEqual(MODULE.main(), 1)
            self.assertNotIn("sops: encrypted fixture", output.getvalue())

    def test_account_orphan_profile_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = make_registry(
                pathlib.Path(temporary),
                {"type": "user", "id": "brettheap"},
                "personal",
                account_extra={"profileRefs": [{"provider": "claude", "name": "missing-profile"}]},
            )
            report = MODULE.combine([MODULE.load_registry(root)])
            self.assertIn("orphan-profile-ref", codes(report))


if __name__ == "__main__":
    unittest.main()
