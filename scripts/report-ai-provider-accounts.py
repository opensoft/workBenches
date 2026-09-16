#!/usr/bin/env python3
"""Validate and summarize owner-specific AI provider account registries.

This command reads metadata only. It never opens provider credential files,
decrypts SOPS ciphertext, or retrieves an Azure Key Vault secret value.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from collections import defaultdict
from typing import Any


SOURCE_KIND = "workbenches-ai-profile-source"
PROVIDER_KIND = "workbenches-ai-provider-catalog"
ACCOUNT_KIND = "workbenches-ai-account-catalog"
OWNER_TYPES = {"tenant", "user", "product"}
LIFECYCLES = {"active", "planned", "disabled", "retired"}
FORBIDDEN_KEYS = {
    "accesstoken",
    "refreshtoken",
    "apikey",
    "secretvalue",
    "password",
    "cookie",
    "privatekey",
    "credentialpath",
}
TOKEN_PATTERNS = (
    re.compile(r"^Bearer\s+", re.IGNORECASE),
    re.compile(r"^sk-[A-Za-z0-9_-]{12,}$"),
    re.compile(r"^[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}$"),
)
PROVIDER_DOCUMENT_KEYS = {"schemaVersion", "kind", "owner", "providers"}
PROVIDER_KEYS = {"providerId", "displayName", "profileProviderIds", "products"}
ACCOUNT_DOCUMENT_KEYS = {"schemaVersion", "kind", "owner", "providerId", "accounts"}
ACCOUNT_KEYS = {
    "accountId",
    "owner",
    "providerId",
    "login",
    "products",
    "subscription",
    "status",
    "profileRefs",
    "credentialIds",
    "verifiedAt",
    "notes",
}


class ReportError(ValueError):
    pass


def read_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ReportError(f"missing JSON file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ReportError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ReportError(f"expected JSON object: {path}")
    return value


def normalize_owner(value: object, context: str) -> tuple[str, str]:
    if not isinstance(value, dict):
        raise ReportError(f"{context}: owner must be an object")
    owner_type = value.get("type")
    owner_id = value.get("id")
    if owner_type not in OWNER_TYPES or not isinstance(owner_id, str) or not owner_id:
        raise ReportError(f"{context}: invalid owner")
    return owner_type, owner_id


def owner_label(owner: tuple[str, str]) -> str:
    return f"{owner[0]}/{owner[1]}"


def registry_root(value: str) -> pathlib.Path:
    path = pathlib.Path(value).expanduser().resolve()
    if (path / "ai" / "source.json").is_file():
        return path
    if path.name == "ai" and (path / "source.json").is_file():
        return path.parent
    raise ReportError(f"registry root lacks ai/source.json: {path}")


def add_finding(
    findings: list[dict[str, str]],
    severity: str,
    code: str,
    registry: str,
    subject: str,
    message: str,
) -> None:
    findings.append(
        {
            "severity": severity,
            "code": code,
            "registry": registry,
            "subject": subject,
            "message": message,
        }
    )


def normalized_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def scan_for_secret_metadata(
    value: object,
    findings: list[dict[str, str]],
    registry: str,
    subject: str,
) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if normalized_key(str(key)) in FORBIDDEN_KEYS:
                add_finding(
                    findings,
                    "error",
                    "forbidden-secret-field",
                    registry,
                    subject,
                    f"account metadata contains forbidden field {key!r}",
                )
            scan_for_secret_metadata(child, findings, registry, subject)
    elif isinstance(value, list):
        for child in value:
            scan_for_secret_metadata(child, findings, registry, subject)
    elif isinstance(value, str) and any(pattern.search(value) for pattern in TOKEN_PATTERNS):
        add_finding(
            findings,
            "error",
            "token-like-value",
            registry,
            subject,
            "account metadata contains a token-like value; value suppressed",
        )


def validate_keys(
    value: dict[str, Any],
    expected: set[str],
    findings: list[dict[str, str]],
    registry: str,
    subject: str,
) -> None:
    for key in sorted(expected - value.keys()):
        add_finding(findings, "error", "missing-field", registry, subject, f"required field {key!r} is missing")
    for key in sorted(value.keys() - expected):
        add_finding(findings, "error", "unexpected-field", registry, subject, f"field {key!r} is not allowed")


def safe_personal_ciphertext(root: pathlib.Path, provider: str, reference: object) -> bool:
    if not isinstance(reference, str) or not reference:
        return False
    pure = pathlib.PurePosixPath(reference)
    expected = pathlib.PurePosixPath("ai/secrets") / provider
    if pure.is_absolute() or ".." in pure.parts or expected not in pure.parents:
        return False
    path = root.joinpath(*pure.parts)
    return path.is_file() and not path.is_symlink()


def load_registry(root: pathlib.Path) -> dict[str, Any]:
    source_path = root / "ai" / "source.json"
    accounts_dir = root / "ai" / "accounts"
    source = read_json(source_path)
    if source.get("kind") != SOURCE_KIND:
        raise ReportError(f"unsupported profile source: {source_path}")
    owner = normalize_owner(source.get("owner"), str(source_path))
    registry = owner_label(owner)
    findings: list[dict[str, str]] = []

    provider_document = read_json(accounts_dir / "providers.json")
    if provider_document.get("kind") != PROVIDER_KIND or provider_document.get("schemaVersion") != 1:
        raise ReportError(f"unsupported provider catalog: {accounts_dir / 'providers.json'}")
    validate_keys(provider_document, PROVIDER_DOCUMENT_KEYS, findings, registry, "providers.json")
    if normalize_owner(provider_document.get("owner"), str(accounts_dir / "providers.json")) != owner:
        add_finding(findings, "error", "owner-mismatch", registry, "providers.json", "provider catalog owner differs from registry owner")
    scan_for_secret_metadata(provider_document, findings, registry, "providers.json")

    providers: dict[str, dict[str, Any]] = {}
    profile_provider_to_hoster: dict[str, str] = {}
    raw_providers = provider_document.get("providers")
    if not isinstance(raw_providers, list):
        raise ReportError(f"{accounts_dir / 'providers.json'}: providers must be an array")
    for provider in raw_providers:
        if not isinstance(provider, dict):
            raise ReportError(f"{accounts_dir / 'providers.json'}: provider must be an object")
        provider_id = provider.get("providerId")
        if not isinstance(provider_id, str) or not provider_id:
            raise ReportError(f"{accounts_dir / 'providers.json'}: invalid providerId")
        validate_keys(provider, PROVIDER_KEYS, findings, registry, provider_id)
        if provider_id in providers:
            add_finding(findings, "error", "duplicate-provider", registry, provider_id, "provider ID is duplicated")
            continue
        providers[provider_id] = provider
        if not isinstance(provider.get("displayName"), str) or not provider.get("displayName"):
            add_finding(findings, "error", "invalid-provider", registry, provider_id, "provider displayName must be non-empty")
        if not isinstance(provider.get("products"), list) or any(
            not isinstance(value, str) or not value for value in provider.get("products", [])
        ):
            add_finding(findings, "error", "invalid-provider", registry, provider_id, "provider products must be strings")
        source_ids = provider.get("profileProviderIds")
        if not isinstance(source_ids, list) or not source_ids:
            add_finding(findings, "error", "invalid-provider", registry, provider_id, "profileProviderIds must be a non-empty array")
            continue
        for source_id in source_ids:
            if source_id in profile_provider_to_hoster and profile_provider_to_hoster[source_id] != provider_id:
                add_finding(findings, "error", "duplicate-profile-provider", registry, str(source_id), "profile provider maps to multiple hosters")
            profile_provider_to_hoster[str(source_id)] = provider_id

    accounts: dict[str, dict[str, Any]] = {}
    account_documents = sorted(
        path for path in accounts_dir.glob("*.json") if path.name != "providers.json"
    )
    if not account_documents:
        raise ReportError(f"no account catalogs found in {accounts_dir}")
    for path in account_documents:
        document = read_json(path)
        if document.get("kind") != ACCOUNT_KIND or document.get("schemaVersion") != 1:
            raise ReportError(f"unsupported account catalog: {path}")
        validate_keys(document, ACCOUNT_DOCUMENT_KEYS, findings, registry, path.name)
        if normalize_owner(document.get("owner"), str(path)) != owner:
            add_finding(findings, "error", "owner-mismatch", registry, path.name, "account catalog owner differs from registry owner")
        provider_id = document.get("providerId")
        if provider_id not in providers:
            add_finding(findings, "error", "unknown-provider", registry, path.name, "account catalog references an unknown provider")
        scan_for_secret_metadata(document, findings, registry, path.name)
        rows = document.get("accounts")
        if not isinstance(rows, list):
            raise ReportError(f"{path}: accounts must be an array")
        for account in rows:
            if not isinstance(account, dict):
                raise ReportError(f"{path}: account must be an object")
            account_id = account.get("accountId")
            if not isinstance(account_id, str) or not account_id:
                raise ReportError(f"{path}: invalid accountId")
            validate_keys(account, ACCOUNT_KEYS, findings, registry, account_id)
            if account_id in accounts:
                add_finding(findings, "error", "duplicate-account", registry, account_id, "account ID is duplicated in registry")
                continue
            accounts[account_id] = account
            if normalize_owner(account.get("owner"), f"{path}:{account_id}") != owner:
                add_finding(findings, "error", "owner-mismatch", registry, account_id, "account owner differs from registry owner")
            if account.get("providerId") != provider_id:
                add_finding(findings, "error", "provider-mismatch", registry, account_id, "account provider differs from containing catalog")
            if account.get("status") not in LIFECYCLES:
                add_finding(findings, "error", "invalid-lifecycle", registry, account_id, "account has an invalid lifecycle")
            login = account.get("login")
            if not isinstance(login, dict) or set(login) != {"email"} or not isinstance(login.get("email"), str) or not login.get("email"):
                add_finding(findings, "error", "invalid-login", registry, account_id, "account login must contain one non-empty email")
            subscription = account.get("subscription")
            if (
                not isinstance(subscription, dict)
                or set(subscription) != {"plan", "billingModel"}
                or not isinstance(subscription.get("plan"), str)
                or not subscription.get("plan")
                or subscription.get("billingModel") not in {"subscription", "pay-as-you-go", "free", "unknown"}
            ):
                add_finding(findings, "error", "invalid-subscription", registry, account_id, "account subscription metadata is invalid")
            if not isinstance(account.get("products"), list) or any(not isinstance(value, str) or not value for value in account.get("products", [])):
                add_finding(findings, "error", "invalid-products", registry, account_id, "account products must be strings")
            if not isinstance(account.get("profileRefs"), list) or not account.get("profileRefs"):
                add_finding(findings, "error", "invalid-profile-ref", registry, account_id, "account must reference at least one profile")
            if not isinstance(account.get("credentialIds"), list) or not account.get("credentialIds"):
                add_finding(findings, "error", "invalid-credential-ref", registry, account_id, "account must reference at least one credential")
            if not isinstance(account.get("notes"), list) or any(not isinstance(value, str) for value in account.get("notes", [])):
                add_finding(findings, "error", "invalid-notes", registry, account_id, "account notes must be strings")

    profiles: dict[tuple[str, str], dict[str, Any]] = {}
    credentials: dict[str, tuple[str, str]] = {}
    profiles_object = source.get("profiles")
    if not isinstance(profiles_object, dict):
        raise ReportError(f"{source_path}: profiles must be an object")
    for profile_provider, rows in profiles_object.items():
        if not isinstance(rows, list):
            raise ReportError(f"{source_path}: profiles.{profile_provider} must be an array")
        if profile_provider not in profile_provider_to_hoster:
            add_finding(findings, "error", "unknown-profile-provider", registry, profile_provider, "profile provider has no hoster mapping")
        for profile in rows:
            if not isinstance(profile, dict):
                raise ReportError(f"{source_path}: profile must be an object")
            name = profile.get("name")
            if not isinstance(name, str) or not name:
                raise ReportError(f"{source_path}: invalid profile name")
            key = (profile_provider, name)
            subject = f"{profile_provider}/{name}"
            if key in profiles:
                add_finding(findings, "error", "duplicate-profile", registry, subject, "profile key is duplicated")
                continue
            profiles[key] = profile
            if normalize_owner(profile.get("owner"), f"{source_path}:{subject}") != owner:
                add_finding(findings, "error", "owner-mismatch", registry, subject, "profile owner differs from registry owner")
            credential_id = profile.get("credentialId")
            if not isinstance(credential_id, str) or not credential_id:
                add_finding(findings, "error", "missing-credential-id", registry, subject, "profile lacks credentialId")
            elif credential_id in credentials:
                add_finding(findings, "error", "duplicate-credential", registry, credential_id, "credential ID is duplicated in registry")
            else:
                credentials[credential_id] = key

    vault_entries: dict[tuple[str, str], dict[str, Any]] = {}
    vault_path = root / "ai" / "vault" / "azure-key-vault.json"
    if vault_path.is_file():
        vault = read_json(vault_path)
        for entry in vault.get("entries", []):
            if not isinstance(entry, dict):
                continue
            registry_provider = entry.get("registryProvider") or entry.get("provider")
            vault_entries[(str(registry_provider), str(entry.get("profile")))] = entry

    escrow: dict[str, bool] = {}
    for key, profile in profiles.items():
        profile_provider, name = key
        subject = f"{profile_provider}/{name}"
        account_id = profile.get("accountId")
        account = accounts.get(str(account_id))
        if account is None:
            add_finding(findings, "error", "orphan-account-ref", registry, subject, f"profile references unknown account {account_id!r}")
        else:
            expected_hoster = profile_provider_to_hoster.get(profile_provider)
            if account.get("providerId") != expected_hoster:
                add_finding(findings, "error", "provider-mismatch", registry, subject, "profile and account resolve to different hosters")
            profile_refs = account.get("profileRefs")
            expected_ref = {"provider": profile_provider, "name": name}
            if not isinstance(profile_refs, list) or expected_ref not in profile_refs:
                add_finding(findings, "error", "orphan-profile-ref", registry, subject, "account does not reference profile")
            credential_ids = account.get("credentialIds")
            if not isinstance(credential_ids, list) or profile.get("credentialId") not in credential_ids:
                add_finding(findings, "error", "orphan-credential-ref", registry, subject, "account does not reference profile credential")
            login = account.get("login")
            if not isinstance(login, dict) or login.get("email") != profile.get("email"):
                add_finding(findings, "error", "login-mismatch", registry, subject, "account and profile login identities differ")

        authentication = profile.get("authentication")
        if not isinstance(authentication, dict):
            authentication = {}
        if authentication.get("accountId") != account_id:
            add_finding(findings, "error", "orphan-credential-account-ref", registry, subject, "credential metadata does not reference the profile account")

        credential_id = profile.get("credentialId")
        configured = False
        if owner[0] == "tenant":
            entry = vault_entries.get(key)
            configured = bool(
                entry
                and entry.get("enabled") is True
                and entry.get("credentialId") == credential_id
                and authentication.get("escrowStatus") == "available"
            )
        elif owner[0] == "user":
            configured = bool(
                authentication.get("escrowStatus") == "available"
                and safe_personal_ciphertext(root, profile_provider, authentication.get("credentialRef"))
            )
        escrow[str(credential_id)] = configured
        if profile.get("status") == "active" and not configured:
            add_finding(findings, "warning", "missing-escrow", registry, subject, "active credential lacks configured durable escrow")

    for account_id, account in accounts.items():
        profile_refs = account.get("profileRefs")
        for reference in profile_refs if isinstance(profile_refs, list) else []:
            if not isinstance(reference, dict):
                add_finding(findings, "error", "invalid-profile-ref", registry, account_id, "account profile reference is not an object")
                continue
            key = (str(reference.get("provider")), str(reference.get("name")))
            if key not in profiles:
                add_finding(findings, "error", "orphan-profile-ref", registry, account_id, f"account references unknown profile {key[0]}/{key[1]}")
        credential_ids = account.get("credentialIds")
        for credential_id in credential_ids if isinstance(credential_ids, list) else []:
            if credential_id not in credentials:
                add_finding(findings, "error", "orphan-credential-ref", registry, account_id, f"account references unknown credential {credential_id!r}")

    return {
        "root": str(root),
        "registry": registry,
        "owner": owner,
        "providers": providers,
        "accounts": accounts,
        "profiles": profiles,
        "credentials": credentials,
        "escrow": escrow,
        "findings": findings,
    }


def combine(registries: list[dict[str, Any]]) -> dict[str, Any]:
    findings = [finding for registry in registries for finding in registry["findings"]]
    provider_definitions: dict[str, tuple[dict[str, Any], str]] = {}
    account_owners: dict[str, str] = {}
    credential_owners: dict[str, str] = {}
    summary: dict[tuple[str, str], dict[str, Any]] = {}

    for registry in registries:
        registry_name = registry["registry"]
        for provider_id, definition in registry["providers"].items():
            prior = provider_definitions.get(provider_id)
            normalized = json.loads(json.dumps(definition, sort_keys=True))
            if prior and prior[0] != normalized:
                add_finding(findings, "error", "provider-conflict", registry_name, provider_id, f"provider definition conflicts with {prior[1]}")
            else:
                provider_definitions[provider_id] = (normalized, registry_name)
        for account_id in registry["accounts"]:
            if account_id in account_owners:
                add_finding(findings, "error", "duplicate-account", registry_name, account_id, f"account ID also exists in {account_owners[account_id]}")
            else:
                account_owners[account_id] = registry_name
        for credential_id in registry["credentials"]:
            if credential_id in credential_owners:
                add_finding(findings, "error", "duplicate-credential", registry_name, credential_id, f"credential ID also exists in {credential_owners[credential_id]}")
            else:
                credential_owners[credential_id] = registry_name

        owner = registry_name
        for account in registry["accounts"].values():
            provider_id = str(account.get("providerId"))
            key = (provider_id, owner)
            row = summary.setdefault(
                key,
                {
                    "providerId": provider_id,
                    "provider": registry["providers"].get(provider_id, {}).get("displayName", provider_id),
                    "owner": owner,
                    "accounts": 0,
                    "activeAccounts": 0,
                    "credentials": 0,
                    "configuredEscrow": 0,
                    "missingEscrow": 0,
                },
            )
            row["accounts"] += 1
            if account.get("status") == "active":
                row["activeAccounts"] += 1
            raw_credential_ids = account.get("credentialIds")
            credential_ids = raw_credential_ids if isinstance(raw_credential_ids, list) else []
            row["credentials"] += len(set(str(value) for value in credential_ids))
            for credential_id in set(str(value) for value in credential_ids):
                if registry["escrow"].get(credential_id) is True:
                    row["configuredEscrow"] += 1
                elif account.get("status") == "active":
                    row["missingEscrow"] += 1

    findings.sort(key=lambda item: (item["severity"], item["code"], item["registry"], item["subject"]))
    return {
        "schemaVersion": 1,
        "registries": [
            {"owner": registry["registry"], "root": registry["root"]}
            for registry in registries
        ],
        "summary": [summary[key] for key in sorted(summary)],
        "findings": findings,
        "valid": not any(finding["severity"] == "error" for finding in findings),
    }


def print_human(report: dict[str, Any]) -> None:
    headers = (
        "Provider",
        "Owner",
        "Accounts",
        "Active",
        "Credentials",
        "Escrowed",
        "Missing",
    )
    rows = [
        (
            row["provider"],
            row["owner"],
            str(row["accounts"]),
            str(row["activeAccounts"]),
            str(row["credentials"]),
            str(row["configuredEscrow"]),
            str(row["missingEscrow"]),
        )
        for row in report["summary"]
    ]
    widths = [
        max(len(headers[index]), *(len(row[index]) for row in rows)) if rows else len(headers[index])
        for index in range(len(headers))
    ]
    print("  ".join(headers[index].ljust(widths[index]) for index in range(len(headers))))
    print("  ".join("-" * width for width in widths))
    for row in rows:
        print("  ".join(row[index].ljust(widths[index]) for index in range(len(headers))))
    for finding in report["findings"]:
        print(
            f"{finding['severity'].upper():7} {finding['code']} "
            f"{finding['registry']} {finding['subject']}: {finding['message']}"
        )
    errors = sum(finding["severity"] == "error" for finding in report["findings"])
    warnings = sum(finding["severity"] == "warning" for finding in report["findings"])
    print(f"Summary: registries={len(report['registries'])} rows={len(rows)} errors={errors} warnings={warnings}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", action="append", required=True, help="Private registry root containing ai/source.json")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    parser.add_argument("--strict", action="store_true", help="Fail on missing active escrow as well as validation errors")
    args = parser.parse_args()

    try:
        roots = [registry_root(value) for value in args.registry]
        if len(set(roots)) != len(roots):
            raise ReportError("the same registry root was supplied more than once")
        report = combine([load_registry(root) for root in roots])
    except ReportError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if args.json:
        json.dump(report, sys.stdout, indent=2, ensure_ascii=False)
        sys.stdout.write("\n")
    else:
        print_human(report)
    errors = any(finding["severity"] == "error" for finding in report["findings"])
    missing = any(finding["code"] == "missing-escrow" for finding in report["findings"])
    return 1 if errors or (args.strict and missing) else 0


if __name__ == "__main__":
    raise SystemExit(main())
