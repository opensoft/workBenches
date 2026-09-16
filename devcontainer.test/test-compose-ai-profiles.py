#!/usr/bin/env python3
"""Focused credential-reference tests for compose-ai-profiles.py."""

from __future__ import annotations

import importlib.util
import pathlib
import tempfile
import unittest


MODULE_PATH = pathlib.Path(__file__).parents[1] / "scripts" / "compose-ai-profiles.py"
SPEC = importlib.util.spec_from_file_location("compose_ai_profiles", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CredentialReferenceTests(unittest.TestCase):
    def profile(self, provider: str, name: str, reference: str) -> dict:
        return {
            "name": name,
            "email": f"{name}@opensoft.one",
            "family": "opensoft",
            "aliases": [],
            "authentication": {
                "type": "subscription_oauth",
                "credentialRef": reference,
                "escrowStatus": "available",
            },
        }

    def validate(self, provider: str, name: str, reference: str) -> dict:
        with tempfile.TemporaryDirectory() as temporary:
            source = pathlib.Path(temporary) / "ai" / "source.json"
            return MODULE.validate_profile(self.profile(provider, name, reference), provider, source)

    def test_accepts_matching_azure_claude_reference(self) -> None:
        result = self.validate(
            "claude",
            "team-001",
            "azure-key-vault://kv-opensoft-aiprof-p01/ai-credential-claude-team-001",
        )
        self.assertEqual(result["name"], "team-001")

    def test_accepts_openai_registry_to_codex_runtime_mapping(self) -> None:
        self.validate(
            "openai",
            "team-001",
            "azure-key-vault://kv-opensoft-aiprof-p01/ai-credential-codex-team-001",
        )

    def test_rejects_wrong_profile_in_azure_reference(self) -> None:
        with self.assertRaisesRegex(MODULE.ProfileError, "mismatched Azure credentialRef"):
            self.validate(
                "claude",
                "team-001",
                "azure-key-vault://kv-opensoft-aiprof-p01/ai-credential-claude-team-002",
            )

    def test_rejects_wrong_runtime_provider(self) -> None:
        with self.assertRaisesRegex(MODULE.ProfileError, "mismatched Azure credentialRef"):
            self.validate(
                "openai",
                "team-001",
                "azure-key-vault://kv-opensoft-aiprof-p01/ai-credential-claude-team-001",
            )

    def test_keeps_support_for_personal_sops_reference(self) -> None:
        self.validate(
            "claude",
            "brett-team-01",
            "ai/secrets/claude/brett-team-01.credentials.sops.yaml",
        )


if __name__ == "__main__":
    unittest.main()
