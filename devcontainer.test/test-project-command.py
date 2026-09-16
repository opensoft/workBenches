"""Offline installer and legacy entrypoint regression tests."""
import hashlib
import importlib.util
import io
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("project_installer", ROOT / "scripts/setup-project-command.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
TEST_BASH = os.environ.get("WORKBENCHES_TEST_BASH", "bash")
MODERN_BASH = subprocess.run(
    [TEST_BASH, "-c", 'test "${BASH_VERSINFO[0]}" -ge 4'],
    check=False, capture_output=True).returncode == 0


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.discovery = self.base / "state/project-bin"
        environment = patch.dict(os.environ, {
            "WORKBENCHES_PROJECT_DISCOVERY_FILE": str(self.discovery),
        })
        environment.start()
        self.addCleanup(environment.stop)
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
        self.assertEqual(self.discovery.read_text().strip(), str(self.bin.resolve()))

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
        self.assertEqual(installer.main([
            *self.args, "--source", str(self.source), "--install-onp",
        ]), 0)
        target = self.bin / "project"
        onp = self.bin / "onp"
        owner = self.bin / ".workbenches-project.json"
        self.assertTrue(owner.is_file())
        self.assertTrue(onp.is_file())
        with patch.dict(os.environ, {"WORKBENCHES_SKIP_PROJECT_COMMAND": "1"}):
            self.assertEqual(installer.main([*self.args, "--remove"]), 0)
        self.assertFalse(target.exists())
        self.assertFalse(onp.exists())
        self.assertFalse((self.bin / installer.PAYLOAD_NAME).exists())
        self.assertFalse(owner.exists())
        self.assertFalse(self.discovery.exists())
        target.write_text("unowned replacement")
        self.assertEqual(installer.main([*self.args, "--remove"]), 3)
        self.assertEqual(target.read_text(), "unowned replacement")

    def test_optional_discovery_removal_failure_does_not_block_core_removal(self):
        self.assertEqual(self.install(), 0)
        real_unlink = installer.atomic_checked_unlink

        def refuse_discovery(path, expected_state):
            if Path(path) == self.discovery:
                raise PermissionError("simulated read-only discovery directory")
            return real_unlink(path, expected_state)

        errors = io.StringIO()
        with patch.object(installer, "atomic_checked_unlink",
                          side_effect=refuse_discovery), redirect_stderr(errors):
            self.assertEqual(installer.main([*self.args, "--remove"]), 0)
        self.assertFalse((self.bin / "project").exists())
        self.assertFalse((self.bin / installer.PAYLOAD_NAME).exists())
        self.assertFalse((self.bin / ".workbenches-project.json").exists())
        self.assertTrue(self.discovery.is_file())
        self.assertIn("preserved discovery pointer", errors.getvalue())

    def test_known_legacy_onp_variants_migrate_but_collisions_do_not(self):
        historical = installer.legacy_copied_onp_bytes(self.wb)
        self.assertEqual(historical, installer.legacy_copied_onp_bytes(ROOT))
        self.assertIn(b'WORKBENCHES_DIR="/home/brett/projects/workBenches"', historical)
        for legacy_bytes in (
                historical,
                installer.legacy_generated_onp_bytes(self.wb),
                installer.legacy_generated_onp_bytes(
                    self.wb, include_bin_dir_export=False)):
            with self.subTest(legacy=hashlib.sha256(legacy_bytes).hexdigest()):
                self.bin.mkdir(exist_ok=True)
                onp = self.bin / "onp"
                onp.write_bytes(legacy_bytes)
                onp.chmod(0o755)
                self.assertEqual(installer.main([
                    *self.args, "--source", str(self.source), "--install-onp",
                ]), 0)
                self.assertEqual(onp.read_bytes(), (self.bin / "project").read_bytes())
                self.assertEqual(installer.main([*self.args, "--remove"]), 0)

        self.bin.mkdir(exist_ok=True)
        onp = self.bin / "onp"
        onp.write_text("#!/bin/bash\necho user-owned\n")
        onp.chmod(0o755)
        self.assertEqual(installer.main([
            *self.args, "--source", str(self.source), "--install-onp",
        ]), 2)
        self.assertEqual(onp.read_text(), "#!/bin/bash\necho user-owned\n")
        onp.unlink()
        target = self.base / "elsewhere"
        target.write_bytes(installer.legacy_copied_onp_bytes(self.wb))
        target.chmod(0o755)
        onp.symlink_to(target)
        self.assertEqual(installer.main([
            *self.args, "--source", str(self.source), "--install-onp",
        ]), 2)
        self.assertTrue(onp.is_symlink())

    def test_relative_bin_and_discovery_aliases_are_rejected_before_writes(self):
        self.assertEqual(installer.main([
            "--pin", str(self.pin), "--bin-dir", "relative/bin",
            "--workbenches", str(self.wb), "--source", str(self.source),
        ]), 2)
        self.assertFalse(Path("relative/bin/project").exists())

        aliased_discovery = self.bin / "project"
        with patch.dict(os.environ, {
                "WORKBENCHES_PROJECT_DISCOVERY_FILE": str(aliased_discovery)}):
            self.assertEqual(self.install(), 2)
        self.assertFalse(self.bin.exists())

    def test_install_preserves_unowned_discovery_pointer(self):
        self.discovery.parent.mkdir(parents=True)
        self.discovery.write_text("unrelated user data\n")
        self.assertEqual(self.install(), 2)
        self.assertEqual(self.discovery.read_text(), "unrelated user data\n")
        self.assertFalse((self.bin / "project").exists())

    def test_preexisting_private_lock_mode_and_contents_are_preserved(self):
        self.bin.mkdir()
        lock = self.bin / installer.LOCK_NAME
        lock.write_text("private lock contents")
        lock.chmod(0o600)
        self.assertEqual(self.install(), 0)
        self.assertEqual(lock.read_text(), "private lock contents")
        self.assertEqual(lock.stat().st_mode & 0o777, 0o600)

    def test_duplicate_transaction_destinations_fail_closed(self):
        self.bin.mkdir()
        target = self.bin / "owned"
        target.write_text("owned")
        target.chmod(0o644)
        state = installer.path_fingerprint(target)
        journal = self.bin / installer.REMOVAL_JOURNAL_NAME
        with self.assertRaises(ValueError):
            installer.remove_transaction([(target, state), (target, state)], journal)
        self.assertEqual(target.read_text(), "owned")
        self.assertFalse(journal.exists())

    def test_removal_journal_rejects_truncated_file_fingerprint(self):
        self.bin.mkdir()
        target = self.bin / "owned"
        quarantine = self.bin / ".project-remove-test"
        backup = self.bin / ".project-remove-backup-test"
        journal = self.bin / installer.REMOVAL_JOURNAL_NAME
        journal.write_text(json.dumps({
            "schema_version": 1,
            "state": "committed",
            "entries": [{
                "path": str(target),
                "quarantine": str(quarantine),
                "backup": str(backup),
                "fingerprint": ["file"],
            }],
        }))
        with self.assertRaises(ValueError):
            installer.read_removal_journal(journal, [target])
        quarantine.write_text("untrusted")
        self.assertFalse(installer.recovery_copy_matches(
            quarantine, ("file",)))

    @unittest.skipUnless(hasattr(signal, "SIGKILL"), "SIGKILL is unavailable")
    def test_sigkill_during_quarantine_is_recovered_and_removal_resumes(self):
        self.assertEqual(installer.main([
            *self.args, "--source", str(self.source), "--install-onp",
        ]), 0)
        driver = f'''import importlib.util, os, signal
from pathlib import Path
spec = importlib.util.spec_from_file_location("crash_installer", {str(ROOT / "scripts/setup-project-command.py")!r})
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
real_move = module.atomic_move_noreplace
def crash_after_first_quarantine(source, destination):
    real_move(source, destination)
    name = Path(destination).name
    if name.startswith(".project-remove-") and not name.startswith(".project-remove-backup-"):
        os.kill(os.getpid(), signal.SIGKILL)
module.atomic_move_noreplace = crash_after_first_quarantine
raise SystemExit(module.main({[*self.args, "--remove"]!r}))
'''
        crashed = subprocess.run([sys.executable, "-c", driver], env=os.environ.copy())
        self.assertEqual(crashed.returncode, -signal.SIGKILL)
        journal = self.bin / installer.REMOVAL_JOURNAL_NAME
        self.assertTrue(journal.is_file())
        self.assertEqual(installer.main([*self.args, "--resolve-owned"]), 3)
        self.assertEqual(installer.main([*self.args, "--remove"]), 0)
        for path in (
                self.bin / "project", self.bin / installer.PAYLOAD_NAME,
                self.bin / ".workbenches-project.json", self.bin / "onp", journal):
            self.assertFalse(path.exists() or path.is_symlink())
        self.assertEqual(list(self.bin.glob(".project-remove-*")), [])

    def test_remove_preserves_unowned_project_and_removes_owned_onp(self):
        self.assertEqual(installer.main([
            *self.args, "--source", str(self.source), "--install-onp",
        ]), 0)
        target = self.bin / "project"
        onp = self.bin / "onp"
        target.write_text("unowned project collision")
        target.chmod(0o755)
        self.assertEqual(installer.main([*self.args, "--remove"]), 0)
        self.assertEqual(target.read_text(), "unowned project collision")
        self.assertFalse(onp.exists())

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

    def test_remove_unowned_command_does_not_require_directory_write_access(self):
        self.bin.mkdir()
        target = self.bin / "project"
        target.write_text("unowned command")
        target.chmod(0o755)
        self.bin.chmod(0o555)
        try:
            self.assertEqual(installer.main([*self.args, "--remove"]), 3)
            self.assertEqual(target.read_text(), "unowned command")
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
            if checks == 3:
                target.write_text("concurrent replacement")
            return real_owned_target(*args)

        with patch.object(installer, "owned_target", side_effect=replace_before_final_check):
            self.assertEqual(installer.main([*self.args, "--remove"]), 2)
        self.assertEqual(target.read_text(), "concurrent replacement")

    def test_remove_quarantines_and_restores_concurrent_target(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        real_move = installer.atomic_move_noreplace
        collision_created = False

        def replace_before_quarantine(source, destination):
            nonlocal collision_created
            if Path(source) == target and not collision_created:
                target.write_text("concurrent replacement")
                target.chmod(0o755)
                collision_created = True
            return real_move(source, destination)

        with patch.object(installer, "atomic_move_noreplace",
                          side_effect=replace_before_quarantine):
            self.assertEqual(installer.main([*self.args, "--remove"]), 2)
        self.assertTrue(collision_created)
        self.assertEqual(target.read_text(), "concurrent replacement")
        self.assertTrue((self.bin / installer.PAYLOAD_NAME).is_file())
        self.assertTrue((self.bin / ".workbenches-project.json").is_file())

    def test_grouped_remove_restores_earlier_quarantines_on_failure(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        payload = self.bin / installer.PAYLOAD_NAME
        owner = self.bin / ".workbenches-project.json"
        original_target = target.read_bytes()
        real_move = installer.atomic_move_noreplace
        collision_created = False

        def replace_payload_before_quarantine(source, destination):
            nonlocal collision_created
            if Path(source) == payload and not collision_created:
                payload.write_text("concurrent payload replacement")
                collision_created = True
            return real_move(source, destination)

        with patch.object(installer, "atomic_move_noreplace",
                          side_effect=replace_payload_before_quarantine):
            self.assertEqual(installer.main([*self.args, "--remove"]), 2)
        self.assertTrue(collision_created)
        self.assertEqual(target.read_bytes(), original_target)
        self.assertEqual(payload.read_text(), "concurrent payload replacement")
        self.assertTrue(owner.is_file())
        self.assertEqual(list(self.bin.glob(".project-remove-*")), [])

    def test_grouped_remove_resumes_committed_cleanup_after_failure(self):
        self.assertEqual(self.install(), 0)
        paths = [
            self.bin / "project",
            self.bin / installer.PAYLOAD_NAME,
            self.bin / ".workbenches-project.json",
            self.discovery,
        ]
        original = {path: path.read_bytes() for path in paths}
        real_unlink = Path.unlink
        delete_count = 0

        def fail_second_quarantine_delete(path, *args, **kwargs):
            nonlocal delete_count
            if (path.name.startswith(".project-remove-")
                    and not path.name.startswith(".project-remove-backup-")
                    and path.exists() and path.stat().st_size > 0):
                delete_count += 1
                if delete_count == 2:
                    raise OSError("simulated quarantine deletion failure")
            return real_unlink(path, *args, **kwargs)

        with patch.object(Path, "unlink", new=fail_second_quarantine_delete):
            self.assertEqual(installer.main([*self.args, "--remove"]), 0)
        self.assertGreaterEqual(delete_count, 2)
        for path in paths[:-1]:
            self.assertFalse(path.exists())
        self.assertTrue((self.bin / installer.REMOVAL_JOURNAL_NAME).is_file())
        self.assertEqual(self.discovery.read_bytes(), original[self.discovery])
        resolved = io.StringIO()
        with redirect_stdout(resolved):
            self.assertEqual(installer.main([
                *self.args, "--resolve-removal-pending",
            ]), 0)
        self.assertEqual(Path(resolved.getvalue().strip()), self.bin.resolve())
        self.assertEqual(installer.main([*self.args, "--remove"]), 0)
        self.assertFalse((self.bin / installer.REMOVAL_JOURNAL_NAME).exists())
        self.assertFalse(self.discovery.exists())
        self.assertEqual(list(self.bin.glob(".project-remove-*")), [])
        self.assertEqual(list(self.discovery.parent.glob(".project-remove-*")), [])

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
        real_publish = installer.atomic_checked_replace
        for fail_at in (2, 3, 4, 5):
            with self.subTest(fail_at=fail_at):
                for path, data in original.items():
                    path.write_bytes(data)
                target.chmod(0o755)
                publish_count = 0

                def fail_publish(source, destination, expected_state):
                    nonlocal publish_count
                    publish_count += 1
                    if publish_count == fail_at:
                        raise OSError("simulated publication failure")
                    return real_publish(source, destination, expected_state)

                with patch.object(installer, "atomic_checked_replace",
                                  side_effect=fail_publish):
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

    def test_missing_target_collision_at_publication_is_preserved(self):
        target = self.bin / "project"
        real_link = installer.os.link
        collision_created = False

        def create_collision_before_link(source, destination, *args, **kwargs):
            nonlocal collision_created
            if Path(destination) == target and not collision_created:
                target.write_text("concurrent unowned command")
                collision_created = True
            return real_link(source, destination, *args, **kwargs)

        with patch.object(installer.os, "link", side_effect=create_collision_before_link):
            self.assertEqual(self.install(), 2)
        self.assertTrue(collision_created)
        self.assertEqual(target.read_text(), "concurrent unowned command")
        self.assertFalse((self.bin / ".workbenches-project.json").exists())

    def test_failed_stage_unlink_rolls_back_new_publication(self):
        owner = self.bin / ".workbenches-project.json"
        real_unlink = Path.unlink
        failure_injected = False

        def fail_staged_unlink(path, *args, **kwargs):
            nonlocal failure_injected
            if (not failure_injected and path.name.startswith(".project-install-")
                    and owner.is_file()):
                failure_injected = True
                raise OSError("simulated staged unlink failure")
            return real_unlink(path, *args, **kwargs)

        with patch.object(Path, "unlink", new=fail_staged_unlink):
            self.assertEqual(self.install(), 2)
        self.assertTrue(failure_injected)
        self.assertFalse((self.bin / "project").exists())
        self.assertFalse((self.bin / installer.PAYLOAD_NAME).exists())
        self.assertFalse(owner.exists())

    def test_owned_target_replacement_at_publication_is_preserved(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        self.source.write_text('#!/usr/bin/env python3\nprint("updated")\n')
        pin = json.loads(self.pin.read_text())
        pin["trusted_previous"] = [{"commit": pin["commit"], "sha256": pin["sha256"]}]
        pin["commit"] = "b" * 40
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        real_exchange = installer.atomic_exchange
        collision_created = False

        def replace_before_exchange(left, right):
            nonlocal collision_created
            if Path(right) == target and not collision_created:
                target.write_text("concurrent unowned command")
                target.chmod(0o755)
                collision_created = True
            return real_exchange(left, right)

        with patch.object(installer, "atomic_exchange", side_effect=replace_before_exchange):
            self.assertEqual(self.install(), 2)
        self.assertTrue(collision_created)
        self.assertEqual(target.read_text(), "concurrent unowned command")
        self.assertEqual(installer.main([*self.args, "--resolve-owned"]), 3)

    def test_published_destination_fingerprint_is_checked(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        original_target = target.read_bytes()
        self.source.write_text('#!/usr/bin/env python3\nprint("updated")\n')
        pin = json.loads(self.pin.read_text())
        pin["trusted_previous"] = [{"commit": pin["commit"], "sha256": pin["sha256"]}]
        pin["commit"] = "b" * 40
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        real_exchange = installer.atomic_exchange
        replacement_injected = False

        def replace_after_target_exchange(left, right):
            nonlocal replacement_injected
            real_exchange(left, right)
            if Path(right) == target and not replacement_injected:
                right.write_text("concurrent published replacement")
                right.chmod(0o755)
                replacement_injected = True

        with patch.object(installer, "atomic_exchange",
                          side_effect=replace_after_target_exchange):
            self.assertEqual(self.install(), 2)
        self.assertTrue(replacement_injected)
        self.assertEqual(target.read_bytes(), original_target)
        collisions = list(self.bin.glob(".project-collision-*"))
        self.assertEqual(len(collisions), 1)
        self.assertEqual(collisions[0].read_text(),
                         "concurrent published replacement")

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

    def test_pending_owner_rejects_mixed_launcher_payload_generations(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        payload = self.bin / installer.PAYLOAD_NAME
        owner = self.bin / ".workbenches-project.json"
        previous_payload = payload.read_bytes()
        previous_digest = hashlib.sha256(previous_payload).hexdigest()
        previous_launcher_digest = hashlib.sha256(target.read_bytes()).hexdigest()
        previous_commit = json.loads(self.pin.read_text())["commit"]

        self.source.write_text('#!/usr/bin/env python3\nprint("updated")\n')
        pin = json.loads(self.pin.read_text())
        pin["trusted_previous"] = [{
            "commit": previous_commit,
            "sha256": previous_digest,
        }]
        pin["commit"] = "b" * 40
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        new_launcher = installer.launcher_bytes(pin)
        target.write_bytes(new_launcher)
        target.chmod(0o755)
        payload.write_bytes(previous_payload)
        owner.write_text(json.dumps({
            "schema_version": 1,
            "state": "pending",
            "repository": pin["repository"],
            "commit": pin["commit"],
            "sha256": pin["sha256"],
            "launcher_sha256": hashlib.sha256(new_launcher).hexdigest(),
            "previous_owned": True,
            "previous_commit": previous_commit,
            "previous_sha256": previous_digest,
            "previous_launcher_sha256": previous_launcher_digest,
        }))
        self.assertEqual(installer.main([*self.args, "--resolve-owned"]), 3)

    def test_fresh_pending_journal_recovers_without_replace_override(self):
        self.bin.mkdir()
        pin = json.loads(self.pin.read_text())
        launcher_digest = hashlib.sha256(installer.launcher_bytes(pin)).hexdigest()
        owner = self.bin / ".workbenches-project.json"
        owner.write_text(json.dumps({
            "schema_version": 1,
            "state": "pending",
            "repository": pin["repository"],
            "commit": pin["commit"],
            "sha256": pin["sha256"],
            "launcher_sha256": launcher_digest,
            "previous_owned": False,
            "previous_commit": "",
            "previous_sha256": "",
            "previous_launcher_sha256": "",
        }))
        self.assertEqual(self.install(), 0)
        self.assertTrue((self.bin / "project").is_file())
        self.assertEqual(json.loads(owner.read_text())["state"], "owned")

    def test_fresh_pending_with_published_payload_recovers(self):
        self.bin.mkdir()
        pin = json.loads(self.pin.read_text())
        owner = self.bin / ".workbenches-project.json"
        owner.write_text(json.dumps({
            "schema_version": 1,
            "state": "pending",
            "repository": pin["repository"],
            "commit": pin["commit"],
            "sha256": pin["sha256"],
            "launcher_sha256": hashlib.sha256(
                installer.launcher_bytes(pin)).hexdigest(),
            "previous_owned": False,
            "previous_commit": "",
            "previous_sha256": "",
            "previous_launcher_sha256": "",
        }))
        payload = self.bin / installer.PAYLOAD_NAME
        payload.write_bytes(self.source.read_bytes())
        payload.chmod(0o644)
        self.assertEqual(self.install(), 0)
        self.assertTrue((self.bin / "project").is_file())
        self.assertEqual(json.loads(owner.read_text())["state"], "owned")

    def test_interrupted_unowned_replacement_is_not_adopted_or_removed(self):
        self.bin.mkdir()
        target = self.bin / "project"
        target.write_text("unowned project command")
        original = target.read_bytes()
        real_publish = installer.atomic_checked_replace
        publish_count = 0

        def interrupt_after_publish(source, destination, expected_state):
            nonlocal publish_count
            publish_count += 1
            result = real_publish(source, destination, expected_state)
            if publish_count == 1:
                raise KeyboardInterrupt("simulated interruption")
            return result

        with patch.object(installer, "atomic_checked_replace",
                          side_effect=interrupt_after_publish):
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

    def test_matching_symlink_is_not_accepted_by_replace_fast_path(self):
        self.assertEqual(self.install(), 0)
        target = self.bin / "project"
        external = self.base / "matching-launcher"
        external.write_bytes(target.read_bytes())
        external.chmod(0o755)
        target.unlink()
        target.symlink_to(external)
        self.assertEqual(installer.main([
            *self.args, "--source", str(self.source), "--replace-existing",
        ]), 2)
        self.assertTrue(target.is_symlink())

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

        env["PATH"] = os.environ["PATH"]
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/project"), "new", "FromDiscovery"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["new", "FromDiscovery"])

    def test_forwarder_expands_tilde_and_rejects_relative_configuration(self):
        home = self.base / "forwarder-home"
        tilde_bin = home / "commands"
        self.assertEqual(installer.main([
            *self.args, "--bin-dir", str(tilde_bin), "--source", str(self.source),
        ]), 0)
        env = {
            **os.environ,
            "HOME": str(home),
            "OPENREPOPROJECT_BIN_DIR": "~/commands",
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_ROOT": str(self.wb),
        }
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/project"), "FromTilde"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["FromTilde"])

        env["OPENREPOPROJECT_BIN_DIR"] = "relative/bin"
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/project"), "unsafe"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("OPENREPOPROJECT_BIN_DIR must be an absolute path", result.stderr)

        env.pop("OPENREPOPROJECT_BIN_DIR")
        env["WORKBENCHES_PROJECT_DISCOVERY_FILE"] = "relative/discovery"
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/project"), "unsafe"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("WORKBENCHES_PROJECT_DISCOVERY_FILE must be an absolute path",
                      result.stderr)

        tilde_discovery = home / ".state/project-bin"
        tilde_discovery.parent.mkdir(parents=True)
        tilde_discovery.write_text(str(tilde_bin) + "\n")
        env["WORKBENCHES_PROJECT_DISCOVERY_FILE"] = "~/.state/project-bin"
        env["PATH"] = os.environ["PATH"]
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/project"), "FromDiscoveryTilde"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["FromDiscoveryTilde"])

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

    def test_checkout_forwarder_isolates_ownership_probe_from_pythonpath(self):
        self.assertEqual(self.install(), 0)
        hostile = self.base / "hostile-pythonpath"
        hostile.mkdir()
        marker = self.base / "pythonpath-import-ran"
        (hostile / "ctypes.py").write_text(
            "from pathlib import Path\n"
            f"Path({str(marker)!r}).write_text('ran')\n"
            "raise RuntimeError('loaded hostile ctypes')\n"
        )
        env = {
            **os.environ,
            "OPENREPOPROJECT_BIN_DIR": str(self.bin),
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_ROOT": str(self.wb),
            "PYTHONPATH": str(hostile),
        }
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/project"), "safe"],
            env=env, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["safe"])
        self.assertFalse(marker.exists())

    def test_installed_launcher_rejects_python_older_than_3_10(self):
        self.assertEqual(self.install(), 0)
        fake_bin = self.base / "old-python-bin"
        fake_bin.mkdir()
        executed = self.base / "old-python-executed-launcher"
        fake_python = fake_bin / "python3"
        fake_python.write_text(
            "#!/bin/sh\n"
            "if [ \"$1\" = -c ]; then exit 1; fi\n"
            f"printf ran > {str(executed)!r}\n"
            "exit 99\n"
        )
        fake_python.chmod(0o755)
        env = {**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"]}
        result = subprocess.run(
            [str(self.bin / "project")], env=env, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 3)
        self.assertIn("Python 3.10 or newer is required", result.stderr)
        self.assertFalse(executed.exists())

    def test_verified_execution_does_not_import_from_install_directory(self):
        self.source.write_text(
            '#!/usr/bin/env python3\n'
            'import json, shlex\n'
            'print(json.dumps(shlex.split("safe import")))\n'
        )
        pin = json.loads(self.pin.read_text())
        pin["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(pin))
        self.assertEqual(self.install(), 0)

        malicious = self.base / "install-directory-import-ran"
        (self.bin / "json.py").write_text(
            'from pathlib import Path\n'
            f'Path({str(malicious)!r}).write_text("ran")\n'
            'raise RuntimeError("loaded unverified launcher-directory module")\n'
        )
        (self.bin / "shlex.py").write_text(
            'from pathlib import Path\n'
            f'Path({str(malicious)!r}).write_text("ran")\n'
            'raise RuntimeError("loaded unverified install-directory module")\n'
        )

        target = self.bin / "project"
        direct = subprocess.run([str(target)], text=True, capture_output=True)
        self.assertEqual(direct.returncode, 0, direct.stderr)
        self.assertEqual(json.loads(direct.stdout), ["safe", "import"])
        self.assertFalse(malicious.exists())

        delegated = subprocess.run(
            [sys.executable, str(ROOT / "scripts/setup-project-command.py"),
             *self.args, "--exec-owned"],
            text=True, capture_output=True)
        self.assertEqual(delegated.returncode, 0, delegated.stderr)
        self.assertEqual(json.loads(delegated.stdout), ["safe", "import"])
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

    def test_setup_dependency_preflight_requires_python3(self):
        command = (
            'source "$1"; '
            'command() { '
            'if [ "$1" = "-v" ] && [ "$2" = "python3" ]; then return 1; fi; '
            'builtin command "$@"; '
            '}; '
            'check_dependencies'
        )
        result = subprocess.run(
            ["bash", "-c", command, "_", str(ROOT / "scripts/setup-workbenches.sh")],
            input="n\n", text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("python3", result.stdout)
        self.assertIn("Missing required dependencies", result.stdout)

    def test_setup_dependency_preflight_skips_python_when_project_is_disabled(self):
        command = (
            'source "$1"; '
            'command() { '
            'if [ "$1" = "-v" ] && [ "$2" = "python3" ]; then return 1; fi; '
            'builtin command "$@"; '
            '}; '
            'WORKBENCHES_SKIP_PROJECT_COMMAND=1 check_dependencies'
        )
        result = subprocess.run(
            ["bash", "-c", command, "_", str(ROOT / "scripts/setup-workbenches.sh")],
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("project command installation skipped", result.stdout)
        self.assertNotIn("Missing required dependencies: python3", result.stdout)

    def test_shared_installer_rejects_old_python3(self):
        errors = io.StringIO()
        with patch.object(installer.sys, "version_info", (3, 9, 18)), \
                redirect_stderr(errors):
            self.assertEqual(installer.main(self.args), 2)
        self.assertIn("Python 3.10 or newer is required", errors.getvalue())

    def test_setup_dependency_preflight_rejects_old_python3(self):
        mock_bin = self.base / "old-python-bin"
        mock_bin.mkdir()
        python = mock_bin / "python3"
        python.write_text(
            '#!/bin/sh\n'
            'if [ "${1:-}" = "--version" ]; then echo "Python 3.9.18"; exit 0; fi\n'
            'if [ "${1:-}" = "-c" ]; then exit 1; fi\n'
            'exit 1\n'
        )
        python.chmod(0o755)
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; check_dependencies', "_",
             str(ROOT / "scripts/setup-workbenches.sh")],
            env={**os.environ, "PATH": str(mock_bin) + os.pathsep + os.environ["PATH"]},
            text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported (version: 3.9.18; requires 3.10+)", result.stdout)
        self.assertIn("Python 3.10 or newer is required", result.stdout)

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

    def test_setup_menu_expands_tilde_in_configured_directory(self):
        home = self.base / "menu-tilde-home"
        tilde_bin = home / "bin"
        self.assertEqual(installer.main([
            *self.args, "--bin-dir", str(tilde_bin),
            "--source", str(self.source),
        ]), 0)
        env = {
            **os.environ,
            "HOME": str(home),
            "OPENREPOPROJECT_BIN_DIR": "~/bin",
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_ROOT": str(self.wb),
        }
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; install_onp_command', "_",
             str(ROOT / "scripts/setup-workbenches.sh")],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((tilde_bin / "onp").is_file())
        self.assertIn(str(tilde_bin / "onp"), result.stdout)

    def test_setup_menu_rejects_relative_configured_directory(self):
        env = {
            **os.environ,
            "OPENREPOPROJECT_BIN_DIR": "relative/bin",
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_ROOT": str(self.wb),
        }
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; install_onp_command', "_",
             str(ROOT / "scripts/setup-workbenches.sh")],
            env=env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("OPENREPOPROJECT_BIN_DIR must be an absolute path", result.stdout)

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

    def test_clean_reinstall_refreshes_trusted_orphaned_onp(self):
        self.assertEqual(installer.main([
            *self.args, "--source", str(self.source), "--install-onp",
        ]), 0)
        onp = self.bin / "onp"
        old_onp = onp.read_bytes()
        self.assertEqual(installer.main([*self.args, "--remove"]), 0)
        self.assertFalse(onp.exists())

        # Recreate the orphan left by installers from before --remove managed
        # the compatibility launcher, then rotate to a pin that trusts it.
        onp.write_bytes(old_onp)
        onp.chmod(0o755)
        old_pin = json.loads(self.pin.read_text())
        self.source.write_text(
            '#!/usr/bin/env python3\nimport json, sys\n'
            'print(json.dumps(["rotated", *sys.argv[1:]]))\n')
        self.pin.write_text(json.dumps({
            **old_pin,
            "commit": "b" * 40,
            "sha256": hashlib.sha256(self.source.read_bytes()).hexdigest(),
            "trusted_previous": [{
                "commit": old_pin["commit"],
                "sha256": old_pin["sha256"],
            }],
        }))
        self.assertEqual(self.install(), 0)
        self.assertEqual(onp.read_bytes(), (self.bin / "project").read_bytes())
        result = subprocess.run([str(onp), "Reinstall"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["rotated", "new", "Reinstall"])

    def test_install_onp_refuses_symlink_collision(self):
        self.bin.mkdir()
        external = self.base / "external-onp-target"
        external.write_text("external command")
        onp = self.bin / "onp"
        onp.symlink_to(external)
        self.assertEqual(installer.main([
            *self.args, "--source", str(self.source), "--install-onp",
        ]), 2)
        self.assertTrue(onp.is_symlink())
        self.assertEqual(external.read_text(), "external command")
        self.assertFalse((self.bin / "project").exists())

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

    @unittest.skipUnless(MODERN_BASH,
                         "command installer requires Bash 4 associative arrays")
    def test_status_distinguishes_unowned_and_verified_project_commands(self):
        status_bin = self.base / ".local/bin"
        status_bin.mkdir(parents=True)
        target = status_bin / "project"
        target.write_text("unrelated project command")
        target.chmod(0o755)
        onp = status_bin / "onp"
        onp.write_text("unrelated compatibility command")
        onp.chmod(0o755)
        env = {**os.environ, "HOME": str(self.base), "OPENREPOPROJECT_PIN": str(self.pin),
               "WORKBENCHES_ROOT": str(self.wb)}
        command = [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"), "--status"]

        result = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("project              Create, inspect, diagnose and maintain projects (unowned or tampered)",
                      result.stdout)
        self.assertIn("onp                  Opensoft New Project - Quick project creation command (unowned or tampered)",
                      result.stdout)

        target.unlink()
        onp.unlink()
        self.assertEqual(installer.main([
            "--pin", str(self.pin), "--bin-dir", str(status_bin),
            "--workbenches", str(ROOT), "--source", str(self.source), "--install-onp",
        ]), 0)
        result = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("project              Create, inspect, diagnose and maintain projects", result.stdout)
        self.assertIn("onp                  Opensoft New Project - Quick project creation command", result.stdout)
        self.assertNotIn("projects (unowned or tampered)", result.stdout)

        onp.write_text("tampered compatibility command")
        onp.chmod(0o755)
        result = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("onp                  Opensoft New Project - Quick project creation command (unowned or tampered)",
                      result.stdout)

        shadow_bin = self.base / "shadow-bin"
        shadow_bin.mkdir()
        shadow = shadow_bin / "project"
        shadow.write_text('#!/bin/sh\nexit 0\n')
        shadow.chmod(0o755)
        env["PATH"] = str(shadow_bin) + os.pathsep + str(status_bin) + os.pathsep + os.environ["PATH"]
        result = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"Shadowed in PATH by {shadow}", result.stdout)

    def test_onp_resolution_requires_matching_owned_project_generation(self):
        self.assertEqual(installer.main([
            *self.args, "--source", str(self.source), "--install-onp",
        ]), 0)
        onp = self.bin / "onp"
        old_onp = onp.read_bytes()
        previous = json.loads(self.pin.read_text())
        self.source.write_text('#!/usr/bin/env python3\nprint("updated")\n')
        current = dict(previous)
        current["trusted_previous"] = [{
            "commit": previous["commit"],
            "sha256": previous["sha256"],
        }]
        current["commit"] = "b" * 40
        current["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
        self.pin.write_text(json.dumps(current))
        self.assertEqual(self.install(), 0)
        onp.write_bytes(old_onp)
        onp.chmod(0o755)
        self.assertEqual(installer.main([
            *self.args, "--resolve-onp-owned",
        ]), 3)

    @unittest.skipUnless(MODERN_BASH,
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
            [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"), "--install"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((install_bin / "onp").read_bytes(),
                         (install_bin / "project").read_bytes())
        invoked = subprocess.run([str(install_bin / "onp"), "Global"], env=env,
                                 text=True, capture_output=True)
        self.assertEqual(invoked.returncode, 0, invoked.stderr)
        self.assertEqual(json.loads(invoked.stdout), ["new", "Global"])

    @unittest.skipUnless(MODERN_BASH,
                         "command installer requires Bash 4 associative arrays")
    def test_global_install_honors_configured_directory(self):
        self.assertEqual(self.install(), 0)
        home = self.base / "custom-global-home"
        env = {
            **os.environ,
            "HOME": str(home),
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "OPENREPOPROJECT_BIN_DIR": str(self.bin),
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_ROOT": str(self.wb),
        }
        result = subprocess.run(
            [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"), "--install"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.bin / "project").is_file())
        self.assertTrue((self.bin / "onp").is_file())
        self.assertFalse((home / ".local/bin/project").exists())

    @unittest.skipUnless(MODERN_BASH,
                         "command installer requires Bash 4 associative arrays")
    def test_global_default_prefers_and_creates_user_local_bin(self):
        home = self.base / "default-local-home"
        home.mkdir()
        env = {
            **os.environ,
            "HOME": str(home),
            "WORKBENCHES_SKIP_PROJECT_COMMAND": "1",
        }
        env.pop("OPENREPOPROJECT_BIN_DIR", None)
        result = subprocess.run(
            [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"), "--install"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((home / ".local/bin/launchBench").is_file())

    @unittest.skipUnless(MODERN_BASH,
                         "command installer requires Bash 4 associative arrays")
    def test_global_profile_update_shell_quotes_custom_path(self):
        home = self.base / "quoted-path-home"
        home.mkdir()
        profile = home / ".bashrc"
        profile.write_text("")
        install_bin = self.base / "bin'$(touch PWNED)'"
        env = {
            **os.environ,
            "HOME": str(home),
            "PATH": os.environ["PATH"],
            "OPENREPOPROJECT_BIN_DIR": str(install_bin),
            "WORKBENCHES_SKIP_PROJECT_COMMAND": "1",
            "SHELL": "/bin/bash",
        }
        result = subprocess.run(
            [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"), "--install"],
            env=env, cwd=self.base, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(str(install_bin) + ':$PATH', profile.read_text())
        sourced = subprocess.run(
            [TEST_BASH, "-c", 'source "$HOME/.bashrc"; printf "%s" "$PATH"'],
            env=env, cwd=self.base, text=True, capture_output=True)
        self.assertEqual(sourced.returncode, 0, sourced.stderr)
        self.assertFalse((self.base / "PWNED").exists())
        self.assertEqual(sourced.stdout.split(os.pathsep)[0], str(install_bin))

    @unittest.skipUnless(MODERN_BASH,
                         "command installer requires Bash 4 associative arrays")
    def test_global_wrapper_publication_failure_is_nonzero(self):
        home = self.base / "wrapper-failure-home"
        install_bin = home / "bin"
        (install_bin / "launchBench").mkdir(parents=True)
        env = {
            **os.environ,
            "HOME": str(home),
            "PATH": str(install_bin) + os.pathsep + os.environ["PATH"],
            "OPENREPOPROJECT_BIN_DIR": str(install_bin),
            "WORKBENCHES_SKIP_PROJECT_COMMAND": "1",
        }
        result = subprocess.run(
            [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"), "--install"],
            env=env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("One or more command wrappers could not be installed", result.stdout)

    @unittest.skipUnless(MODERN_BASH,
                         "command installer requires Bash 4 associative arrays")
    def test_status_and_uninstall_use_owned_persisted_custom_location(self):
        custom_bin = self.base / "persisted-custom-bin"
        self.assertEqual(installer.main([
            *self.args, "--bin-dir", str(custom_bin), "--source", str(self.source),
            "--install-onp",
        ]), 0)
        home = self.base / "persisted-home"
        home.mkdir()
        env = {
            **os.environ,
            "HOME": str(home),
            "PATH": os.environ["PATH"],
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_ROOT": str(self.wb),
            "WORKBENCHES_PROJECT_DISCOVERY_FILE": str(self.discovery),
        }
        env.pop("OPENREPOPROJECT_BIN_DIR", None)
        command = [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh")]
        status = subprocess.run([*command, "--status"], env=env,
                                text=True, capture_output=True)
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertIn(f"{custom_bin}:", status.stdout)
        self.assertIn("project              Create, inspect, diagnose", status.stdout)

        fake_bin = self.base / "persisted-fake-bin"
        fake_bin.mkdir()
        fake_python = fake_bin / "python3"
        fake_python.write_text(
            '#!/bin/bash\n'
            'previous=""\n'
            'selected=""\n'
            'for argument in "$@"; do\n'
            '  [ "$previous" = "--bin-dir" ] && selected="$argument"\n'
            '  previous="$argument"\n'
            'done\n'
            'if [ "$selected" = "$CUSTOM_BIN" ]; then\n'
            '  exec "$REAL_PYTHON" "$@"\n'
            'fi\n'
            'exit 3\n'
        )
        fake_python.chmod(0o755)
        fake_rm = fake_bin / "rm"
        fake_rm.write_text("#!/bin/bash\nexit 0\n")
        fake_rm.chmod(0o755)
        env.update({
            "PATH": str(fake_bin) + os.pathsep + "/usr/bin:/bin",
            "CUSTOM_BIN": str(custom_bin),
            "REAL_PYTHON": sys.executable,
        })
        removed = subprocess.run([*command, "--uninstall"], env=env,
                                 text=True, capture_output=True)
        self.assertEqual(removed.returncode, 0, removed.stderr)
        self.assertFalse((custom_bin / "project").exists())
        self.assertFalse((custom_bin / "onp").exists())

    @unittest.skipUnless(MODERN_BASH,
                         "command installer requires Bash 4 associative arrays")
    def test_global_uninstall_resumes_persisted_pending_removal(self):
        custom_bin = self.base / "pending-custom-bin"
        self.assertEqual(installer.main([
            *self.args, "--bin-dir", str(custom_bin), "--source", str(self.source),
        ]), 0)
        real_unlink = Path.unlink
        failed = False

        def leave_committed_cleanup(path, *args, **kwargs):
            nonlocal failed
            if (not failed and path.name.startswith(".project-remove-")
                    and not path.name.startswith(".project-remove-backup-")
                    and path.exists() and path.stat().st_size > 0):
                failed = True
                raise OSError("simulated cleanup interruption")
            return real_unlink(path, *args, **kwargs)

        with patch.object(Path, "unlink", new=leave_committed_cleanup):
            self.assertEqual(installer.main([
                *self.args, "--bin-dir", str(custom_bin), "--remove",
            ]), 0)
        self.assertTrue(failed)
        self.assertTrue((custom_bin / installer.REMOVAL_JOURNAL_NAME).is_file())
        self.assertTrue(self.discovery.is_file())

        env = {
            **os.environ,
            "HOME": str(self.base / "pending-home"),
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_ROOT": str(self.wb),
            "WORKBENCHES_PROJECT_DISCOVERY_FILE": str(self.discovery),
        }
        env.pop("OPENREPOPROJECT_BIN_DIR", None)
        result = subprocess.run(
            [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"),
             "--uninstall"],
            env=env, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((custom_bin / installer.REMOVAL_JOURNAL_NAME).exists())
        self.assertFalse(self.discovery.exists())

    @unittest.skipUnless(MODERN_BASH,
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
            [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"), "--install"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((install_bin / "project").exists())
        self.assertFalse((install_bin / "onp").exists())
        self.assertIn("Project command was skipped", result.stdout)

    @unittest.skipUnless(MODERN_BASH,
                         "command installer requires Bash 4 associative arrays")
    def test_global_skip_preserves_owned_project_without_claiming_onp(self):
        home = self.base / "skip-existing-home"
        install_bin = home / ".local/bin"
        install_bin.mkdir(parents=True)
        self.assertEqual(installer.main([
            "--pin", str(self.pin), "--bin-dir", str(install_bin),
            "--workbenches", str(ROOT), "--source", str(self.source),
        ]), 0)
        env = {
            **os.environ,
            "HOME": str(home),
            "PATH": str(install_bin) + os.pathsep + os.environ["PATH"],
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_SKIP_PROJECT_COMMAND": "1",
        }
        result = subprocess.run(
            [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"), "--install"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((install_bin / "project").is_file())
        self.assertFalse((install_bin / "onp").exists())
        self.assertNotIn("Installed: onp", result.stdout)

    @unittest.skipUnless(MODERN_BASH,
                         "command installer requires Bash 4 associative arrays")
    def test_global_skip_creates_configured_wrapper_directory(self):
        home = self.base / "custom-skip-home"
        install_bin = home / "configured/bin"
        fake_bin = self.base / "skip-fake-bin"
        fake_bin.mkdir()
        python_invoked = self.base / "skip-python-invoked"
        fake_python = fake_bin / "python3"
        fake_python.write_text(
            '#!/usr/bin/env bash\n'
            'printf invoked > "$PYTHON_INVOKED"\n'
            'exit 99\n'
        )
        fake_python.chmod(0o755)
        env = {
            **os.environ,
            "HOME": str(home),
            "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
            "OPENREPOPROJECT_BIN_DIR": str(install_bin),
            "OPENREPOPROJECT_PIN": str(self.pin),
            "WORKBENCHES_SKIP_PROJECT_COMMAND": "1",
            "PYTHON_INVOKED": str(python_invoked),
        }
        result = subprocess.run(
            [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"), "--install"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(install_bin.is_dir())
        self.assertFalse((install_bin / "project").exists())
        self.assertFalse((install_bin / "onp").exists())
        self.assertEqual((install_bin / ".workbenches-path").read_text().strip(), str(ROOT))
        self.assertFalse(python_invoked.exists())

    @unittest.skipUnless(MODERN_BASH,
                         "command installer requires Bash 4 associative arrays")
    def test_global_uninstall_never_generically_removes_onp(self):
        home = self.base / "uninstall-home"
        install_bin = home / ".local/bin"
        install_bin.mkdir(parents=True)
        onp = install_bin / "onp"
        onp.write_text("unowned compatibility command")
        onp.chmod(0o755)
        fake_bin = self.base / "fake-bin"
        fake_bin.mkdir()
        remove_log = self.base / "remove.log"
        fake_python = fake_bin / "python3"
        fake_python.write_text("#!/usr/bin/env bash\nexit 3\n")
        fake_python.chmod(0o755)
        fake_rm = fake_bin / "rm"
        fake_rm.write_text(
            '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$REMOVE_LOG"\n')
        fake_rm.chmod(0o755)
        env = {
            **os.environ,
            "HOME": str(home),
            "PATH": str(fake_bin) + os.pathsep + "/usr/bin:/bin",
            "REMOVE_LOG": str(remove_log),
        }
        result = subprocess.run(
            [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"), "--uninstall"],
            env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(onp.is_file())
        self.assertFalse(remove_log.exists(),
                         remove_log.read_text() if remove_log.exists() else "")

    @unittest.skipUnless(MODERN_BASH,
                         "command installer requires Bash 4 associative arrays")
    def test_global_uninstall_propagates_project_removal_failure(self):
        home = self.base / "failed-uninstall-home"
        (home / ".local/bin").mkdir(parents=True)
        fake_bin = self.base / "failed-uninstall-bin"
        fake_bin.mkdir()
        fake_python = fake_bin / "python3"
        fake_python.write_text("#!/usr/bin/env bash\nexit 2\n")
        fake_python.chmod(0o755)
        env = {
            **os.environ,
            "HOME": str(home),
            "PATH": str(fake_bin) + os.pathsep + "/usr/bin:/bin",
        }
        result = subprocess.run(
            [TEST_BASH, str(ROOT / "scripts/install-workbench-commands.sh"), "--uninstall"],
            env=env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not be removed", result.stdout)
        self.assertNotIn("uninstalled successfully", result.stdout)

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
