#!/usr/bin/env python3
"""Check option coverage and selected credential previews without secrets."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "plan-setup-credentials.py"
CATALOG = json.loads((ROOT / "config" / "credential-requirements.json").read_text())
SPEC = importlib.util.spec_from_file_location("credential_plan", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CredentialPlanTests(unittest.TestCase):
    def test_covers_live_bench_tui_submodule_and_base_image_options(self):
        options = CATALOG["options"]
        aliases = {alias for option in options.values() for alias in option["aliases"]}
        benches = json.loads((ROOT / "config" / "bench-config.json").read_text())["benches"]
        self.assertTrue(set(benches) <= set(options))
        tui = (ROOT / "scripts" / "interactive-setup.sh").read_text()
        for array in ("ai_items", "tool_items"):
            match = re.search(rf"{array}=\(\s*(.*?)\n    \)", tui, re.S)
            self.assertIsNotNone(match)
            names = re.findall(r'"([^"\n]+)"', match.group(1))
            self.assertTrue({name for name in names if not name.startswith("separator")} <= set(options))
        for path in re.findall(r"^\s*path = (.+)$", (ROOT / ".gitmodules").read_text(), re.M):
            self.assertIn(Path(path).name, options)
        contract = (ROOT / "base-image" / "ai-cli-contract.sh").read_text()
        match = re.search(r"WORKBENCHES_REQUIRED_AI_CLIS=\((.*?)\)", contract, re.S)
        self.assertIsNotNone(match)
        self.assertTrue(set(match.group(1).split()) <= set(options) | aliases)

    def test_catalog_references_and_aliases_are_valid(self):
        plan = MODULE.build_plan(CATALOG, list(CATALOG["options"]))
        referenced = {requirement["id"] for requirement in plan["additional"]}
        self.assertEqual(referenced, set(CATALOG["requirements"]))
        for requirement in plan["additional"]:
            self.assertIn(requirement["phase"], {"initialize", "use"})
            self.assertTrue(requirement["condition"])
            self.assertTrue(requirement["alternatives"])

    def test_selection_deduplicates_shared_needs_and_keeps_auth_alternatives(self):
        plan = MODULE.build_plan(CATALOG, ["bench_dotNetBench", "javaBench", "codex", "codex_cli"])
        self.assertEqual([option["id"] for option in plan["selectedOptions"]], ["dotNetBench", "javaBench", "codex_cli"])
        additional = {requirement["id"]: requirement for requirement in plan["additional"]}
        self.assertEqual(additional["sonar"]["neededBy"], ["dotNetBench", "javaBench"])
        self.assertEqual(len(additional["ai.codex"]["alternatives"]), 2)
        self.assertNotIn("azure", additional)
        self.assertNotIn("ai.claude", additional)

    def test_local_tools_have_no_unconditional_service_credentials(self):
        plan = MODULE.build_plan(CATALOG, ["spec_kit", "openspec", "herdr"])
        self.assertEqual(plan["additional"], [])
        for option in plan["selectedOptions"]:
            self.assertEqual(option["installCredentials"], [])
        site = MODULE.build_plan(CATALOG, ["frappeBench"])["additional"]
        self.assertEqual(next(item for item in site if item["id"] == "frappe-site")["phase"], "initialize")

    def test_cli_ignores_user_secret_files_and_environment_and_rejects_unknown_options(self):
        with tempfile.TemporaryDirectory() as temporary:
            secret = "credential-preview-must-not-read-this-value"
            fake_home = Path(temporary)
            (fake_home / ".codex").mkdir()
            (fake_home / ".codex" / "auth.json").write_text(secret)
            env = {**os.environ, "HOME": temporary, "OPENAI_API_KEY": secret, "BW_SESSION": secret}
            result = subprocess.run(["python3", str(SCRIPT), "--option", "codex_cli", "--json"], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(secret, result.stdout + result.stderr)
            self.assertEqual(json.loads(result.stdout)["mode"], "requirements-preview")
            result = subprocess.run(["python3", str(SCRIPT), "--option", "unknown"], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("Unknown option", result.stderr)
            self.assertEqual((fake_home / ".codex" / "auth.json").read_text(), secret)


if __name__ == "__main__":
    unittest.main()
