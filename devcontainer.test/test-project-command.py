"""Offline installer and legacy entrypoint regression tests."""
import hashlib
import importlib.util
import io
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
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
        (self.wb / "scripts").mkdir(exist_ok=True)
        (self.wb / "scripts/setup-project-command.py").write_bytes(
            (ROOT / "scripts/setup-project-command.py").read_bytes())
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
        self.assertEqual((self.bin / installer.PAYLOAD_NAME).read_bytes(), self.source.read_bytes())
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
        self.assertNotEqual(target.read_bytes(), self.source.read_bytes())
        self.assertEqual((self.bin / installer.PAYLOAD_NAME).read_bytes(), self.source.read_bytes())

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
        with patch.dict(os.environ, {"WORKBENCHES_SKIP_PROJECT_COMMAND": "1"}):
            self.assertEqual(installer.main([*self.args, "--remove"]), 0)
        self.assertFalse(target.exists())
        self.assertFalse((self.bin / installer.PAYLOAD_NAME).exists())
        self.assertFalse(owner.exists())
        target.write_text("unowned replacement")
        self.assertEqual(installer.main([*self.args, "--remove"]), 3)
        self.assertEqual(target.read_text(), "unowned replacement")

    def test_remove_missing_directory_does_not_create_it(self):
        missing = self.base / "missing-bin"
        self.assertEqual(installer.main([*self.args, "--bin-dir", str(missing), "--remove"]), 3)
        self.assertFalse(missing.exists())

    def test_remove_missing_target_does_not_require_write_or_create_lock(self):
        self.bin.mkdir()
        self.bin.chmod(0o555)
        try:
            self.assertEqual(installer.main([*self.args, "--remove"]), 3)
            self.assertFalse((self.bin / installer.LOCK_NAME).exists())
        finally:
            self.bin.chmod(0o755)

    def test_remove_owned_command_ignores_discovery_marker_state(self):
        self.assertEqual(self.install(), 0)
        marker = self.bin / ".workbenches-path"
        marker.chmod(0o444)
        self.assertEqual(installer.main([*self.args, "--remove"]), 0)
        self.assertTrue(marker.is_file())
        marker.chmod(0o644)

        self.assertEqual(self.install(), 0)
        marker.unlink()
        marker.symlink_to(self.base / "unrelated-discovery")
        self.assertEqual(installer.main([*self.args, "--remove"]), 0)
        self.assertTrue(marker.is_symlink())

    def test_invalid_owner_commit_is_never_trusted(self):
        self.assertEqual(self.install(), 0)
        owner = self.bin / ".workbenches-project.json"
        record = json.loads(owner.read_text())
        record["commit"] = "not-a-commit"
        owner.write_text(json.dumps(record))
        self.assertEqual(installer.main([*self.args, "--resolve-owned"]), 3)
        self.assertEqual(installer.main([*self.args, "--remove"]), 3)
        self.assertTrue((self.bin / "project").is_file())

    def test_self_authored_owner_marker_cannot_adopt_arbitrary_bytes(self):
        self.bin.mkdir()
        target = self.bin / "project"
        target.write_text('#!/usr/bin/env python3\nprint("untrusted")\n')
        target.chmod(0o755)
        payload = self.bin / installer.PAYLOAD_NAME
        payload.write_bytes(self.source.read_bytes())
        pin = json.loads(self.pin.read_text())
        (self.bin / ".workbenches-project.json").write_text(json.dumps({
            "schema_version": 1,
            "state": "owned",
            "repository": pin["repository"],
            "commit": pin["commit"],
            "sha256": pin["sha256"],
            "launcher_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        }))
        (self.bin / installer.LOCK_NAME).touch()
        self.assertEqual(installer.main([*self.args, "--resolve-owned"]), 3)
        self.assertEqual(installer.main([*self.args, "--exec-owned"]), 3)
        self.assertEqual(installer.main([*self.args, "--remove"]), 3)
        self.assertTrue(target.is_file())

    def test_remove_rechecks_target_before_unlink(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        real_owned_target = installer.owned_target
        checks = 0

        def replace_before_final_check(*args):
            nonlocal checks
            checks += 1
            if checks == 2:
                target.write_text("concurrent replacement")
            return real_owned_target(*args)

        with patch.object(installer, "owned_target", side_effect=replace_before_final_check):
            self.assertEqual(installer.main([*self.args, "--remove"]), 2)
        self.assertEqual(target.read_text(), "concurrent replacement")

    def test_partial_publish_failures_roll_back_owned_upgrade(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        marker = self.bin / ".workbenches-path"
        owner = self.bin / ".workbenches-project.json"
        payload = self.bin / installer.PAYLOAD_NAME
        original = {path: path.read_bytes() for path in (target, payload, marker, owner)}

        self.source.write_text('#!/usr/bin/env python3\nprint("updated")\n')
        pin = json.loads(self.pin.read_text())
        pin["trusted_previous"] = [{"commit": pin["commit"], "sha256": pin["sha256"]}]
        pin["commit"] = "b" * 40
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        real_replace = os.replace
        for fail_at in (2, 3, 4, 5):
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
        self.assertEqual(payload.read_bytes(), self.source.read_bytes())

    def test_install_rechecks_collision_after_staging(self):
        real_stage = installer.stage
        stage_count = 0
        target = self.bin / "project"

        def create_collision_after_staging(*args):
            nonlocal stage_count
            staged = real_stage(*args)
            stage_count += 1
            if stage_count == 4:
                target.write_text("concurrent unowned command")
            return staged

        with patch.object(installer, "stage", side_effect=create_collision_after_staging):
            self.assertEqual(self.install(), 2)
        self.assertEqual(target.read_text(), "concurrent unowned command")
        self.assertFalse((self.bin / ".workbenches-project.json").exists())

    def test_pending_owned_upgrade_recovers_after_interruption(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        payload = self.bin / installer.PAYLOAD_NAME
        owner = self.bin / ".workbenches-project.json"
        previous_digest = hashlib.sha256(payload.read_bytes()).hexdigest()
        previous_launcher_digest = hashlib.sha256(target.read_bytes()).hexdigest()
        self.source.write_text('#!/usr/bin/env python3\nprint("updated")\n')
        pin = json.loads(self.pin.read_text())
        pin["trusted_previous"] = [{"commit": pin["commit"], "sha256": pin["sha256"]}]
        previous_commit = pin["commit"]
        pin["commit"] = "b" * 40
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        launcher_data = installer.launcher_bytes(pin)
        owner.write_text(json.dumps({
            "schema_version": 1,
            "state": "pending",
            "repository": pin["repository"],
            "commit": pin["commit"],
            "sha256": pin["sha256"],
            "launcher_sha256": hashlib.sha256(launcher_data).hexdigest(),
            "previous_owned": True,
            "previous_commit": previous_commit,
            "previous_sha256": previous_digest,
            "previous_launcher_sha256": previous_launcher_digest,
        }))
        target.write_bytes(launcher_data)
        target.chmod(0o755)
        payload.write_bytes(self.source.read_bytes())
        payload.chmod(0o644)
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
        env = {**os.environ, "OPENREPOPROJECT_BIN_DIR": str(self.bin),
               "OPENREPOPROJECT_PIN": str(self.pin), "WORKBENCHES_ROOT": str(self.wb)}
        for command in ("onp", "new-project.sh"):
            result = subprocess.run(["bash", str(ROOT / "scripts" / command), "MyApp", "parent with spaces", "--yes"],
                                    env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), ["new", "MyApp", "parent with spaces", "--yes"])
        # The setup menu installs the self-verifying project launcher under the
        # compatibility name rather than trusting a sibling executable.
        (self.wb / "scripts").mkdir(exist_ok=True)
        for name in ("project", "setup-project-command.py"):
            (self.wb / "scripts" / name).write_bytes((ROOT / "scripts" / name).read_bytes())
        (self.wb / "config/openrepoproject-pin.json").write_bytes(self.pin.read_bytes())
        copied = self.bin / "onp"
        copied.write_bytes((self.bin / "project").read_bytes())
        copied.chmod(0o755)
        bypass_marker = self.base / "copied-new-project-ran"
        (self.bin / "new-project.sh").write_text(
            f'#!/usr/bin/env bash\nprintf ran > {str(bypass_marker)!r}\n')
        hostile_root = self.base / "hostile-workbenches"
        (hostile_root / "scripts").mkdir(parents=True)
        marker_bypass = self.base / "marker-project-ran"
        (hostile_root / "scripts/project").write_text(
            f'#!/usr/bin/env bash\nprintf ran > {str(marker_bypass)!r}\n')
        (self.bin / ".workbenches-path").write_text(str(hostile_root) + "\n")
        sibling_bypass = self.base / "sibling-project-ran"
        (self.bin / "project").write_text(
            f'#!/usr/bin/env python3\nfrom pathlib import Path\nPath({str(sibling_bypass)!r}).write_text("ran")\n')
        (self.bin / "project").chmod(0o755)
        copied_env = env.copy()
        copied_env.pop("WORKBENCHES_ROOT")
        result = subprocess.run([str(copied), "Copied", "parent with spaces"], env=copied_env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["new", "Copied", "parent with spaces"])
        self.assertFalse(bypass_marker.exists())
        self.assertFalse(marker_bypass.exists())
        self.assertFalse(sibling_bypass.exists())
        (self.bin / "project").write_bytes(copied.read_bytes())
        (self.bin / "project").chmod(0o755)
        self.source.write_text("#!/usr/bin/env python3\nimport sys\nsys.exit(19)\n")
        pin = json.loads(self.pin.read_text())
        pin["trusted_previous"] = [{"commit": pin["commit"], "sha256": pin["sha256"]}]
        pin["commit"] = "b" * 40
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        self.assertEqual(self.install(), 0)
        result = subprocess.run(["bash", str(ROOT / "scripts/onp"), "App"], env=env)
        self.assertEqual(result.returncode, 19)

    def test_forwarder_refuses_unowned_command_and_finds_owned_path_entry(self):
        self.bin.mkdir()
        target = self.bin / "project"
        executed = self.base / "executed"
        target.write_text(f'#!/usr/bin/env python3\nfrom pathlib import Path\nPath({str(executed)!r}).write_text("ran")\n')
        target.chmod(0o755)
        env = {**os.environ, "OPENREPOPROJECT_BIN_DIR": str(self.bin),
               "OPENREPOPROJECT_PIN": str(self.pin), "WORKBENCHES_ROOT": str(self.wb)}
        result = subprocess.run(["bash", str(ROOT / "scripts/project"), "new", "Unsafe"], env=env)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(executed.exists())

        target.unlink()
        self.assertEqual(self.install(), 0)
        target.chmod(0o555)
        (self.bin / ".workbenches-project.json").chmod(0o444)
        env.pop("OPENREPOPROJECT_BIN_DIR")
        env["PATH"] = str(self.bin) + os.pathsep + env["PATH"]
        result = subprocess.run(["bash", str(ROOT / "scripts/project"), "new", "FromPath"],
                                env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["new", "FromPath"])

    def test_direct_project_launch_verifies_the_separate_payload(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        self.assertNotIn(str(self.wb).encode(), target.read_bytes())
        self.assertNotIn(str(self.pin).encode(), target.read_bytes())
        result = subprocess.run([str(target), "direct", "argument with spaces"],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["direct", "argument with spaces"])

        payload = self.bin / installer.PAYLOAD_NAME
        malicious = self.base / "direct-malicious-ran"
        payload.write_text(
            f'#!/usr/bin/env python3\nfrom pathlib import Path\nPath({str(malicious)!r}).write_text("ran")\n')
        result = subprocess.run([str(target), "unsafe"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 3)
        self.assertIn("refused payload", result.stderr)
        self.assertFalse(malicious.exists())

    def test_checkout_and_pin_path_migration_preserves_ownership(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        launcher_before = target.read_bytes()
        moved_wb = self.base / "moved workBenches"
        (moved_wb / "config").mkdir(parents=True)
        (moved_wb / "config/bench-config.json").write_text('{"benches": {}}')
        moved_pin = self.base / "moved-pin.json"
        moved_pin.write_bytes(self.pin.read_bytes())
        moved_args = ["--pin", str(moved_pin), "--bin-dir", str(self.bin),
                      "--workbenches", str(moved_wb)]

        self.assertEqual(installer.main([*moved_args, "--resolve-owned"]), 0)
        self.assertEqual(installer.main([*moved_args, "--source", str(self.source)]), 0)
        self.assertEqual(target.read_bytes(), launcher_before)
        self.assertEqual((self.bin / ".workbenches-path").read_text().strip(), str(moved_wb))
        self.assertEqual(installer.main([*moved_args, "--remove"]), 0)

    def test_exec_owned_runs_verified_snapshot_if_path_is_replaced(self):
        self.source.write_text(
            '#!/usr/bin/env python3\n'
            'import hashlib, json, sys\n'
            'from pathlib import Path\n'
            'print(json.dumps({"args": sys.argv[1:], "digest": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}))\n'
        )
        pin = json.loads(self.pin.read_text())
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        self.assertEqual(self.install(), 0)
        expected_digest = hashlib.sha256(self.source.read_bytes()).hexdigest()
        target = self.bin / "project"
        malicious = self.base / "malicious-ran"
        real_owned_target_data = installer.owned_target_data

        def replace_after_verified_read(*args):
            data = real_owned_target_data(*args)
            target.write_text(
                f'#!/usr/bin/env python3\nfrom pathlib import Path\nPath({str(malicious)!r}).write_text("ran")\n')
            return data

        output = io.StringIO()
        with patch.object(installer, "owned_target_data", side_effect=replace_after_verified_read):
            with redirect_stdout(output):
                self.assertEqual(installer.main([*self.args, "--exec-owned", "--", "safe"]), 0)
        result = json.loads(output.getvalue())
        self.assertEqual(result["args"], ["safe"])
        self.assertEqual(result["digest"], expected_digest)
        self.assertFalse(malicious.exists())

    def test_setup_menu_helper_honors_project_install_skip(self):
        home = self.base / "menu-skip-home"
        env = {
            **os.environ,
            "HOME": str(home),
            "WORKBENCHES_SKIP_PROJECT_COMMAND": "1",
        }
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; install_onp_command', "_",
             str(ROOT / "scripts/setup-workbenches.sh")],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((home / ".local/bin/onp").exists())
        self.assertIn("onp installation skipped", result.stdout)

    def test_setup_menu_installs_verified_onp_in_configured_directory(self):
        self.assertEqual(self.install(), 0)
        home = self.base / "menu-custom-home"
        env = {
            **os.environ,
            "HOME": str(home),
            "OPENREPOPROJECT_BIN_DIR": str(self.bin),
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_ROOT": str(self.wb),
        }
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; install_onp_command', "_",
             str(ROOT / "scripts/setup-workbenches.sh")],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.bin / "onp").is_file())
        self.assertFalse((home / ".local/bin/onp").exists())
        invoked = subprocess.run([str(self.bin / "onp"), "Configured"], env=env,
                                 text=True, capture_output=True)
        self.assertEqual(invoked.returncode, 0, invoked.stderr)
        self.assertEqual(json.loads(invoked.stdout), ["new", "Configured"])

    def test_project_pin_rotation_refreshes_installer_owned_onp(self):
        self.assertEqual(self.install(), 0)
        onp = self.bin / "onp"
        onp.write_bytes((self.bin / "project").read_bytes())
        onp.chmod(0o755)
        old_pin = json.loads(self.pin.read_text())
        self.source.write_text('#!/usr/bin/env python3\nimport json, sys\nprint(json.dumps(["rotated", *sys.argv[1:]]))\n')
        new_pin = {
            **old_pin,
            "commit": "b" * 40,
            "sha256": hashlib.sha256(self.source.read_bytes()).hexdigest(),
            "trusted_previous": [{
                "commit": old_pin["commit"],
                "sha256": old_pin["sha256"],
            }],
        }
        self.pin.write_text(json.dumps(new_pin))
        self.assertEqual(self.install(), 0)
        self.assertEqual(onp.read_bytes(), (self.bin / "project").read_bytes())
        result = subprocess.run([str(onp), "Upgrade"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["rotated", "new", "Upgrade"])

    def test_exec_owned_releases_shared_lock_before_delegated_work(self):
        lock_path = self.bin / installer.LOCK_NAME
        self.source.write_text(
            '#!/usr/bin/env python3\n'
            'import fcntl, os\n'
            'fd = os.open(os.environ["PROJECT_TEST_LOCK"], os.O_RDWR)\n'
            'try:\n'
            '    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)\n'
            'finally:\n'
            '    os.close(fd)\n'
        )
        pin = json.loads(self.pin.read_text())
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        self.assertEqual(self.install(), 0)
        with patch.dict(os.environ, {"PROJECT_TEST_LOCK": str(lock_path)}):
            self.assertEqual(installer.main([*self.args, "--exec-owned"]), 0)

    def test_owned_resolution_waits_for_project_lock(self):
        self.assertEqual(self.install(), 0)
        lock = (self.bin / installer.LOCK_NAME).open("rb")
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        process = subprocess.Popen(
            [sys.executable, str(ROOT / "scripts/setup-project-command.py"),
             *self.args, "--resolve-owned"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            with self.assertRaises(subprocess.TimeoutExpired):
                process.wait(timeout=0.1)
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
            lock.close()
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, stderr)
        self.assertEqual(Path(stdout.strip()), self.bin / "project")

    @unittest.skipUnless(sys.platform.startswith("linux"),
                         "command installer requires Bash 4 associative arrays")
    def test_status_distinguishes_unowned_and_verified_project_commands(self):
        status_bin = self.base / ".local/bin"
        status_bin.mkdir(parents=True)
        target = status_bin / "project"
        target.write_text("unrelated project command")
        target.chmod(0o755)
        env = {**os.environ, "HOME": str(self.base), "OPENREPOPROJECT_PIN": str(self.pin),
               "WORKBENCHES_ROOT": str(self.wb)}
        command = ["bash", str(ROOT / "scripts/install-workbench-commands.sh"), "--status"]

        result = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("project              Create, inspect, diagnose and maintain projects (unowned or tampered)",
                      result.stdout)

        target.unlink()
        self.assertEqual(installer.main([
            "--pin", str(self.pin), "--bin-dir", str(status_bin),
            "--workbenches", str(ROOT), "--source", str(self.source),
        ]), 0)
        result = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("project              Create, inspect, diagnose and maintain projects", result.stdout)
        self.assertNotIn("projects (unowned or tampered)", result.stdout)

        shadow_bin = self.base / "shadow-bin"
        shadow_bin.mkdir()
        shadow = shadow_bin / "project"
        shadow.write_text('#!/bin/sh\nexit 0\n')
        shadow.chmod(0o755)
        env["PATH"] = str(shadow_bin) + os.pathsep + str(status_bin) + os.pathsep + os.environ["PATH"]
        result = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"Shadowed in PATH by {shadow}", result.stdout)

    @unittest.skipUnless(sys.platform.startswith("linux"),
                         "command installer requires Bash 4 associative arrays")
    def test_global_install_uses_verified_launcher_for_onp(self):
        home = self.base / "global-home"
        install_bin = home / ".local/bin"
        install_bin.mkdir(parents=True)
        self.assertEqual(installer.main([
            "--pin", str(self.pin), "--bin-dir", str(install_bin),
            "--workbenches", str(self.wb), "--source", str(self.source),
        ]), 0)
        env = {
            **os.environ,
            "HOME": str(home),
            "PATH": str(install_bin) + os.pathsep + os.environ["PATH"],
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_ROOT": str(self.wb),
        }
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/install-workbench-commands.sh"), "--install"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((install_bin / "onp").read_bytes(),
                         (install_bin / "project").read_bytes())
        invoked = subprocess.run([str(install_bin / "onp"), "Global"], env=env,
                                 text=True, capture_output=True)
        self.assertEqual(invoked.returncode, 0, invoked.stderr)
        self.assertEqual(json.loads(invoked.stdout), ["new", "Global"])

    @unittest.skipUnless(sys.platform.startswith("linux"),
                         "command installer requires Bash 4 associative arrays")
    def test_global_install_skip_omits_project_and_onp(self):
        home = self.base / "skip-home"
        install_bin = home / ".local/bin"
        install_bin.mkdir(parents=True)
        env = {
            **os.environ,
            "HOME": str(home),
            "PATH": str(install_bin) + os.pathsep + os.environ["PATH"],
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_SKIP_PROJECT_COMMAND": "1",
        }
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/install-workbench-commands.sh"), "--install"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((install_bin / "project").exists())
        self.assertFalse((install_bin / "onp").exists())
        self.assertIn("Project command was skipped", result.stdout)

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
        env = {**os.environ, "WORKBENCHES_ROOT": str(self.wb),
               "OPENREPOPROJECT_BIN_DIR": str(self.bin), "OPENREPOPROJECT_PIN": str(self.pin)}
        parent = self.base / "new projects"
        result = subprocess.run(["bash", str(ROOT / "scripts/onp"), "Example", str(parent), "--type", "test", "--yes"],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((parent / "Example/.project.json").read_text())["bench"], "testBench")


if __name__ == "__main__":
    unittest.main()
