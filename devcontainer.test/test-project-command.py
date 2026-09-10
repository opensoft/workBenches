"""Offline installer and legacy entrypoint regression tests."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("project_installer", ROOT / "scripts/setup-project-command.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.bin = self.base / "bin"
        self.wb = self.base / "work benches"
        (self.wb / "config").mkdir(parents=True)
        (self.wb / "config/bench-config.json").write_text('{"benches": {}}')
        self.source = self.base / "project"
        self.source.write_text('#!/usr/bin/env python3\nimport json, sys\nprint(json.dumps(sys.argv[1:]))\n')
        self.pin = self.base / "pin.json"
        self.pin.write_text(json.dumps({"schema_version": 1, "repository": "test/example",
            "commit": "a" * 40, "sha256": hashlib.sha256(self.source.read_bytes()).hexdigest()}))
        self.args = ["--pin", str(self.pin), "--bin-dir", str(self.bin),
                     "--workbenches", str(self.wb)]

    def install(self):
        return installer.main([*self.args, "--source", str(self.source)])

    def test_install_idempotent_mode_and_marker(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        before = target.stat().st_mtime_ns
        self.assertEqual(self.install(), 0)
        self.assertEqual(target.stat().st_mtime_ns, before)
        self.assertEqual(target.stat().st_mode & 0o777, 0o755)
        self.assertEqual((self.bin / ".workbenches-path").read_text().strip(), str(self.wb))

    def test_corrupt_source_leaves_installed_command_unchanged(self):
        self.assertEqual(self.install(), 0)
        original = (self.bin / "project").read_bytes()
        self.source.write_text("corrupt")
        self.assertEqual(self.install(), 2)
        self.assertEqual((self.bin / "project").read_bytes(), original)

    def test_unowned_command_requires_explicit_replacement(self):
        self.bin.mkdir()
        target = self.bin / "project"
        target.write_text("other project command")
        self.assertEqual(self.install(), 2)
        self.assertEqual(target.read_text(), "other project command")
        self.assertEqual(installer.main([*self.args, "--source", str(self.source),
                                         "--replace-existing"]), 0)
        self.assertEqual(target.read_bytes(), self.source.read_bytes())

    def test_matching_unowned_command_is_not_silently_adopted(self):
        self.bin.mkdir()
        target = self.bin / "project"
        target.write_bytes(self.source.read_bytes())
        target.chmod(0o755)
        self.assertEqual(self.install(), 2)
        self.assertFalse((self.bin / ".workbenches-project.json").exists())
        self.assertEqual(target.read_bytes(), self.source.read_bytes())

    def test_remove_preserves_unowned_and_removes_owned_command(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        owner = self.bin / ".workbenches-project.json"
        self.assertTrue(owner.is_file())
        self.assertEqual(installer.main([*self.args, "--remove"]), 0)
        self.assertFalse(target.exists())
        self.assertFalse(owner.exists())
        target.write_text("unowned replacement")
        self.assertEqual(installer.main([*self.args, "--remove"]), 3)
        self.assertEqual(target.read_text(), "unowned replacement")

    def test_partial_publish_failures_roll_back_owned_upgrade(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        marker = self.bin / ".workbenches-path"
        owner = self.bin / ".workbenches-project.json"
        original = {path: path.read_bytes() for path in (target, marker, owner)}

        self.source.write_text('#!/usr/bin/env python3\nprint("updated")\n')
        pin = json.loads(self.pin.read_text())
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        real_replace = os.replace
        for fail_at in (2, 3, 4):
            with self.subTest(fail_at=fail_at):
                for path, data in original.items():
                    path.write_bytes(data)
                target.chmod(0o755)
                replace_count = 0

                def fail_replace(source, destination):
                    nonlocal replace_count
                    replace_count += 1
                    if replace_count == fail_at:
                        raise OSError("simulated publication failure")
                    return real_replace(source, destination)

                with patch.object(installer.os, "replace", side_effect=fail_replace):
                    self.assertEqual(self.install(), 2)
                for path, data in original.items():
                    self.assertEqual(path.read_bytes(), data)
        self.assertEqual(self.install(), 0)
        self.assertEqual(target.read_bytes(), self.source.read_bytes())

    def test_pending_owned_upgrade_recovers_after_interruption(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        owner = self.bin / ".workbenches-project.json"
        previous_digest = hashlib.sha256(target.read_bytes()).hexdigest()
        self.source.write_text('#!/usr/bin/env python3\nprint("updated")\n')
        pin = json.loads(self.pin.read_text())
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        owner.write_text(json.dumps({
            "schema_version": 1,
            "state": "pending",
            "repository": pin["repository"],
            "commit": pin["commit"],
            "sha256": pin["sha256"],
            "previous_owned": True,
            "previous_sha256": previous_digest,
        }))
        target.write_bytes(self.source.read_bytes())
        target.chmod(0o755)
        self.assertEqual(self.install(), 0)
        self.assertEqual(json.loads(owner.read_text())["state"], "owned")

    def test_interrupted_unowned_replacement_is_not_adopted_or_removed(self):
        self.bin.mkdir()
        target = self.bin / "project"
        target.write_text("unowned project command")
        original = target.read_bytes()
        real_replace = os.replace
        replace_count = 0

        def interrupt_after_replace(source, destination):
            nonlocal replace_count
            replace_count += 1
            real_replace(source, destination)
            if replace_count == 1:
                raise KeyboardInterrupt("simulated interruption")

        with patch.object(installer.os, "replace", side_effect=interrupt_after_replace):
            with self.assertRaises(KeyboardInterrupt):
                installer.main([*self.args, "--source", str(self.source),
                                "--replace-existing"])
        owner = json.loads((self.bin / ".workbenches-project.json").read_text())
        self.assertEqual(owner["state"], "pending")
        self.assertFalse(owner["previous_owned"])
        self.assertEqual(owner["previous_sha256"], "")
        self.assertEqual(installer.main([*self.args, "--remove"]), 3)
        self.assertEqual(target.read_bytes(), original)

    def test_symlink_directory_and_readonly_refuse(self):
        self.bin.mkdir()
        target = self.bin / "project"
        target.symlink_to(self.source)
        self.assertEqual(self.install(), 2)
        target.unlink()
        target.mkdir()
        self.assertEqual(self.install(), 2)
        target.rmdir()
        target.write_text("keep")
        target.chmod(0o444)
        self.assertEqual(self.install(), 2)
        target.chmod(0o644)
        self.assertEqual(target.read_text(), "keep")

    def test_fetch_failure_and_bad_digest_preserve_existing(self):
        self.bin.mkdir()
        target = self.bin / "project"
        target.write_text("old command")
        with patch.object(installer, "fetch", side_effect=OSError("offline")):
            self.assertEqual(installer.main([*self.args, "--replace-existing"]), 2)
        with patch.object(installer, "fetch", return_value=b"incorrect"):
            self.assertEqual(installer.main([*self.args, "--replace-existing"]), 2)
        self.assertEqual(target.read_text(), "old command")

    def test_api_fetch_uses_pinned_commit_and_precedes_raw(self):
        pin = json.loads(self.pin.read_text())
        result = subprocess.CompletedProcess([], 0, self.source.read_bytes(), b"")
        with patch.object(installer.shutil, "which", return_value="gh"), patch.object(installer.subprocess, "run", return_value=result) as run, patch.object(installer.urllib.request, "urlopen") as raw:
            self.assertEqual(installer.fetch(pin), self.source.read_bytes())
            self.assertIn("?ref=" + "a" * 40, run.call_args.args[0][2])
            self.assertEqual(run.call_args.kwargs["timeout"], 20)
            raw.assert_not_called()

    def test_raw_fetch_fallback_is_bounded(self):
        pin = json.loads(self.pin.read_text())
        with patch.object(installer.shutil, "which", return_value=None), \
                patch.object(installer.urllib.request, "urlopen") as raw:
            raw.return_value.__enter__.return_value.read.return_value = self.source.read_bytes()
            self.assertEqual(installer.fetch(pin), self.source.read_bytes())
            self.assertEqual(raw.call_args.kwargs["timeout"], 15)

    def test_forwarders_preserve_legacy_argv_and_exit_code(self):
        self.assertEqual(self.install(), 0)
        env = {**os.environ, "OPENREPOPROJECT_BIN_DIR": str(self.bin), "WORKBENCHES_ROOT": str(self.wb)}
        for command in ("onp", "new-project.sh"):
            result = subprocess.run(["bash", str(ROOT / "scripts" / command), "MyApp", "parent with spaces", "--yes"],
                                    env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), ["new", "MyApp", "parent with spaces", "--yes"])
        # The older setup menu copies onp directly into the bin directory.
        copied = self.bin / "onp"
        copied.write_bytes((ROOT / "scripts/onp").read_bytes())
        result = subprocess.run(["bash", str(copied), "Copied", "parent with spaces"], env=env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["new", "Copied", "parent with spaces"])
        (self.bin / "project").write_text("import sys\nsys.exit(19)\n")
        result = subprocess.run(["bash", str(ROOT / "scripts/onp"), "App"], env=env)
        self.assertEqual(result.returncode, 19)

    @unittest.skipUnless(os.environ.get("OPENREPOPROJECT_TEST_SOURCE"), "Set OPENREPOPROJECT_TEST_SOURCE for cross-repository integration")
    def test_real_cli_install_and_legacy_creation(self):
        self.source.write_bytes(Path(os.environ["OPENREPOPROJECT_TEST_SOURCE"]).read_bytes())
        pin = json.loads(self.pin.read_text())
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        generator = self.wb / "devBenches/testBench/new.sh"
        generator.parent.mkdir(parents=True)
        generator.write_text('#!/bin/bash\nmkdir -p "$2/$1"\n')
        (self.wb / "config/bench-config.json").write_text(json.dumps({"benches": {"testBench": {
            "path": "devBenches/testBench", "project_scripts": [{"name": "test", "script": "new.sh"}]}}}))
        self.assertEqual(self.install(), 0)
        env = {**os.environ, "WORKBENCHES_ROOT": str(self.wb), "OPENREPOPROJECT_BIN_DIR": str(self.bin)}
        parent = self.base / "new projects"
        result = subprocess.run(["bash", str(ROOT / "scripts/onp"), "Example", str(parent), "--type", "test", "--yes"],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((parent / "Example/.project.json").read_text())["bench"], "testBench")


if __name__ == "__main__":
    unittest.main()
