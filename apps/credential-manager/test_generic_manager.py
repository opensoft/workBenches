#!/usr/bin/env python3
"""Regression checks for the public multi-harness account manager."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


APP_DIR = Path(__file__).resolve().parent
REPO = APP_DIR.parents[1]
MODULE_PATH = APP_DIR / "credential_manager.py"
SPEC = importlib.util.spec_from_file_location("credential_manager_under_test", MODULE_PATH)
assert SPEC and SPEC.loader
MANAGER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MANAGER
SPEC.loader.exec_module(MANAGER)


class GenericManagerTest(unittest.TestCase):
    def test_example_loads_all_supported_harnesses(self):
        example = REPO / "config/ai-harness-accounts.example.json"
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config"
            config.mkdir()
            (config / "ai-harness-accounts.json").write_text(example.read_text())
            accounts = MANAGER.load_accounts(Path(directory))

        self.assertEqual(
            sorted(account.provider for account in accounts),
            ["abacus", "antigravity", "chatgpt", "claude", "grok"],
        )

    def test_legacy_provider_names_are_normalized(self):
        self.assertEqual(MANAGER.canonical_provider("openai"), "chatgpt")
        self.assertEqual(MANAGER.canonical_provider("codex"), "chatgpt")
        self.assertEqual(MANAGER.canonical_provider("gemini"), "antigravity")

    def test_example_contains_no_secret_values(self):
        data = json.loads(
            (REPO / "config/ai-harness-accounts.example.json").read_text()
        )
        forbidden_fields = {
            "apikey",
            "api_key",
            "accesstoken",
            "access_token",
            "refreshtoken",
            "refresh_token",
            "sessionkey",
        }
        for account in data["accounts"]:
            self.assertTrue(forbidden_fields.isdisjoint(key.lower() for key in account))

    def test_claude_example_provides_work_and_personal_profiles(self):
        data = json.loads(
            (REPO / "config/claude-profiles.example.json").read_text()
        )
        profiles = {(profile["name"], profile["family"]) for profile in data["profiles"]}
        self.assertIn(("work", "work"), profiles)
        self.assertIn(("personal", "personal"), profiles)

    def test_public_account_surface_has_no_private_identifiers(self):
        targets = [
            REPO / "apps/credential-manager",
            REPO / "config/ai-harness-accounts.example.json",
            REPO / "config/claude-profiles.example.json",
            REPO / "docs/ai-harness-account-management.md",
            REPO / "docs/ai-credentials-management.md",
            REPO / "docs/claude-multi-account-profiles.md",
            REPO / "scripts/claude-profile",
            REPO / "scripts/setup-claude-profiles.sh",
            REPO / "sysBenches/cloudBench/devcontainer.example",
        ]
        forbidden = (
            "br" + "ett",
            "open" + "soft",
            "far" + "heap",
            "med" + "x",
        )
        violations: list[str] = []
        for target in targets:
            files = [target] if target.is_file() else target.rglob("*")
            for path in files:
                if not path.is_file() or "__pycache__" in path.parts:
                    continue
                text = path.read_text(errors="ignore").lower()
                for identifier in forbidden:
                    if identifier in text:
                        violations.append(f"{path.relative_to(REPO)}: {identifier}")
        self.assertEqual(violations, [])


if __name__ == "__main__":
    unittest.main()
