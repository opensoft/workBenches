#!/usr/bin/env python3
"""Regression checks for the public multi-harness account manager."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
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
        self.assertEqual(MANAGER.canonical_provider("gemini"), "gemini")
        self.assertEqual(MANAGER.canonical_provider("zai"), "glm")

    def test_direct_workstation_config_directory_is_supported(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            (config / "claude-profiles.json").write_text(
                json.dumps({
                    "version": 1,
                    "profiles": [{
                        "name": "work-example",
                        "family": "work-example",
                        "email": "user@example.org",
                    }],
                })
            )
            accounts = MANAGER.load_accounts(config)

        self.assertEqual(
            [(account.provider, account.name) for account in accounts],
            [("claude", "work-example")],
        )

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

    def test_codex_example_provides_work_and_personal_profiles(self):
        data = json.loads(
            (REPO / "config/openai-profiles.example.json").read_text()
        )
        profiles = {(profile["name"], profile["family"]) for profile in data["profiles"]}
        self.assertIn(("work-chatgpt-1", "work"), profiles)
        self.assertIn(("personal-chatgpt-1", "personal"), profiles)

    def test_codex_profile_setup_and_alias_isolate_codex_home(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as directory:
            root = Path(directory)
            home = root / "home"
            codex_home = home / ".codex"
            config = root / "config"
            capture = root / "capture"
            codex_home.mkdir(parents=True)
            config.mkdir()
            capture.mkdir()
            (codex_home / "config.toml").write_text(
                'model = "gpt-5.5"\n\n[tui]\nstatus_line = ["model-name"]\n'
            )
            manifest = config / "openai-profiles.json"
            manifest.write_text(json.dumps({
                "version": 1,
                "profiles": [{
                    "name": "work-chatgpt-1",
                    "family": "work",
                    "email": "user@company.example",
                    "aliases": ["work1"],
                }],
            }))
            fake_codex = root / "codex"
            fake_codex.write_text(
                '#!/bin/sh\n'
                'printf "%s\\n" "$CODEX_HOME" > "$CAPTURE_DIR/home"\n'
                'printf "%s\\n" "$@" > "$CAPTURE_DIR/args"\n'
            )
            fake_codex.chmod(0o755)
            env = {
                **os.environ,
                "HOME": str(home),
                "XDG_CONFIG_HOME": str(root / "xdg"),
                "CODEX_BIN": str(fake_codex),
                "CODEX_PROFILES_MANIFEST": str(manifest),
                "CODEX_PROFILES_HOME": str(home / ".chatgpt-profiles"),
                "CAPTURE_DIR": str(capture),
            }
            subprocess.run(
                [str(REPO / "scripts/setup-codex-profiles.sh")],
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                [str(REPO / "scripts/codex-profile"), "status", "work1"],
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )

            profile = home / ".chatgpt-profiles/profiles/work-chatgpt-1"
            profile_config = (profile / "config.toml").read_text()
            self.assertEqual((capture / "home").read_text().strip(), str(profile))
            self.assertIn('forced_login_method = "chatgpt"', profile_config)
            self.assertIn('cli_auth_credentials_store = "file"', profile_config)
            self.assertEqual(
                (capture / "args").read_text().splitlines()[-2:],
                ["login", "status"],
            )
            self.assertEqual(profile.stat().st_mode & 0o777, 0o700)
            self.assertEqual((profile / ".profile.json").stat().st_mode & 0o777, 0o600)

    def test_public_account_surface_has_no_private_identifiers(self):
        targets = [
            REPO / "apps/credential-manager",
            REPO / "config/ai-harness-accounts.example.json",
            REPO / "config/claude-profiles.example.json",
            REPO / "config/openai-profiles.example.json",
            REPO / "docs/ai-harness-account-management.md",
            REPO / "docs/ai-credentials-management.md",
            REPO / "docs/claude-multi-account-profiles.md",
            REPO / "docs/codex-multi-account-profiles.md",
            REPO / "scripts/claude-profile",
            REPO / "scripts/codex-profile",
            REPO / "scripts/setup-claude-profiles.sh",
            REPO / "scripts/setup-codex-profiles.sh",
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
