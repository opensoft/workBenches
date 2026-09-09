from __future__ import annotations

import contextlib
import fcntl
import importlib.util
import io
import json
import logging
from pathlib import Path
import signal
import stat
import tempfile
import unittest


MODULE_DIR = Path(__file__).resolve().parents[1]


def load_module(name: str, path: Path):
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(specification)
    import sys

    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


watchdog = load_module("wsl_relay_watchdog", MODULE_DIR / "wsl_relay_watchdog.py")
installer = load_module("wsl_relay_watchdog_installer", MODULE_DIR / "install.py")


class ProcFixture:
    def __init__(self, root: Path, uptime_seconds: float = 1_000.0, clock_ticks: int = 100) -> None:
        self.root = root
        self.clock_ticks = clock_ticks
        self.root.mkdir(parents=True)
        (self.root / "uptime").write_text(f"{uptime_seconds} 0.0\n", encoding="ascii")

    def add_process(
        self,
        pid: int,
        name: str,
        parent_pid: int,
        start_time_ticks: int = 10_000,
        command_line: tuple[str, ...] = (),
    ) -> None:
        process_dir = self.root / str(pid)
        process_dir.mkdir()
        stat_fields = ["S", str(parent_pid), *(["0"] * 17), str(start_time_ticks), *(["0"] * 5)]
        (process_dir / "stat").write_text(
            f"{pid} ({name}) {' '.join(stat_fields)}\n",
            encoding="utf-8",
        )
        (process_dir / "comm").write_text(f"{name}\n", encoding="utf-8")
        command_bytes = b"\0".join(part.encode("utf-8") for part in command_line)
        if command_line:
            command_bytes += b"\0"
        (process_dir / "cmdline").write_bytes(command_bytes)
        task_dir = process_dir / "task" / str(pid)
        task_dir.mkdir(parents=True)
        (task_dir / "children").write_text("", encoding="ascii")
        parent_children = self.root / str(parent_pid) / "task" / str(parent_pid) / "children"
        if parent_children.exists():
            existing = parent_children.read_text(encoding="ascii").strip()
            parent_children.write_text(f"{existing} {pid}".strip(), encoding="ascii")

    def add_thread_children(self, pid: int, thread_id: int, child_pids: tuple[int, ...]) -> None:
        task_dir = self.root / str(pid) / "task" / str(thread_id)
        task_dir.mkdir(parents=True)
        task_dir.joinpath("children").write_text(
            " ".join(str(child_pid) for child_pid in child_pids),
            encoding="ascii",
        )


def process_info(pid: int, start_time_ticks: int = 100, age_seconds: float = 900.0):
    return watchdog.ProcessInfo(
        identity=watchdog.ProcessIdentity(pid, start_time_ticks),
        parent_pid=1,
        name="Relay",
        command_line=("/init",),
        age_seconds=age_seconds,
        child_count=0,
    )


def scan_result(*processes):
    return watchdog.ScanResult(
        timestamp=1.0,
        strict_candidates=tuple(processes),
        named_relays=(),
        session_leaders=(),
        inspection_errors=(),
    )


class SequenceScanner:
    def __init__(self, results):
        self.results = list(results)
        self.last_result = self.results[-1] if self.results else scan_result()

    def scan(self, _min_age_seconds):
        if self.results:
            self.last_result = self.results.pop(0)
        return self.last_result

    def inspect_strict_candidate(self, identity, min_age_seconds):
        result = self.scan(min_age_seconds)
        return next((candidate for candidate in result.strict_candidates if candidate.identity == identity), None)


class ProcScannerTests(unittest.TestCase):
    def test_targeted_revalidation_observes_new_child(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            proc_root = Path(temporary_directory) / "proc"
            fixture = ProcFixture(proc_root)
            fixture.add_process(10, "Relay", 1, command_line=("/init",))
            scanner = watchdog.ProcScanner(proc_root, clock_ticks=100)
            candidate = scanner.scan(min_age_seconds=300).strict_candidates[0]
            fixture.add_thread_children(10, 101, (14,))

            revalidated = scanner.inspect_strict_candidate(candidate.identity, min_age_seconds=300)

            self.assertIsNone(revalidated)

    def test_strict_classifier_preserves_protected_and_ambiguous_processes(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            proc_root = Path(temporary_directory) / "proc"
            fixture = ProcFixture(proc_root)
            fixture.add_process(10, "Relay", 1, command_line=("/init",))
            fixture.add_process(11, "Relay(200)", 20, command_line=("/init",))
            fixture.add_process(12, "SessionLeader", 1)
            fixture.add_process(13, "Relay", 1, command_line=("/init",))
            fixture.add_process(14, "bash", 13)
            fixture.add_process(15, "Relay", 1, command_line=("/init", "--extra"))
            fixture.add_process(16, "Relay", 1, start_time_ticks=95_000, command_line=("/init",))
            malformed_dir = proc_root / "17"
            malformed_dir.mkdir()
            (malformed_dir / "stat").write_text("malformed\n", encoding="utf-8")
            (malformed_dir / "comm").write_text("Relay\n", encoding="utf-8")

            result = watchdog.ProcScanner(proc_root, clock_ticks=100).scan(min_age_seconds=300)

            self.assertEqual([10], [item.identity.pid for item in result.strict_candidates])
            self.assertEqual([11], [item.identity.pid for item in result.named_relays])
            self.assertEqual([12], [item.identity.pid for item in result.session_leaders])
            self.assertTrue(any(error.startswith("pid=17:") for error in result.inspection_errors))

    def test_missing_relay_cmdline_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            proc_root = Path(temporary_directory) / "proc"
            fixture = ProcFixture(proc_root)
            fixture.add_process(10, "Relay", 1, command_line=("/init",))
            (proc_root / "10" / "cmdline").unlink()

            result = watchdog.ProcScanner(proc_root, clock_ticks=100).scan(min_age_seconds=300)

            self.assertEqual((), result.strict_candidates)
            self.assertTrue(any(error == "pid=10: FileNotFoundError" for error in result.inspection_errors))

    def test_truncated_relay_cmdline_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            proc_root = Path(temporary_directory) / "proc"
            fixture = ProcFixture(proc_root)
            fixture.add_process(10, "Relay", 1, command_line=("/init",))
            (proc_root / "10" / "cmdline").write_bytes(b"/init")

            result = watchdog.ProcScanner(proc_root, clock_ticks=100).scan(min_age_seconds=300)

            self.assertEqual((), result.strict_candidates)
            self.assertTrue(any(error == "pid=10: ValueError" for error in result.inspection_errors))

    def test_relay_child_owned_by_non_leader_thread_is_preserved(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            proc_root = Path(temporary_directory) / "proc"
            fixture = ProcFixture(proc_root)
            fixture.add_process(10, "Relay", 1, command_line=("/init",))
            fixture.add_thread_children(10, 101, (14,))

            result = watchdog.ProcScanner(proc_root, clock_ticks=100).scan(min_age_seconds=300)

            self.assertEqual((), result.strict_candidates)

    def test_relay_name_with_embedded_newline_is_never_strict(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            proc_root = Path(temporary_directory) / "proc"
            fixture = ProcFixture(proc_root)
            fixture.add_process(10, "Relay\n", 1, command_line=("/init",))

            result = watchdog.ProcScanner(proc_root, clock_ticks=100).scan(min_age_seconds=300)

            self.assertEqual((), result.strict_candidates)
            self.assertTrue(any(error.startswith("pid=10: ValueError") for error in result.inspection_errors))

    def test_relay_name_with_carriage_return_is_never_strict(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            proc_root = Path(temporary_directory) / "proc"
            fixture = ProcFixture(proc_root)
            fixture.add_process(10, "Relay\r", 1, command_line=("/init",))

            result = watchdog.ProcScanner(proc_root, clock_ticks=100).scan(min_age_seconds=300)

            self.assertEqual((), result.strict_candidates)
            self.assertTrue(any(error.startswith("pid=10: ValueError") for error in result.inspection_errors))


class ObservationTests(unittest.TestCase):
    def test_requires_consecutive_observations(self):
        tracker = watchdog.ObservationTracker()
        candidate = process_info(10, 100)
        self.assertEqual(1, tracker.update([candidate])[candidate.identity])
        self.assertEqual({}, tracker.update([]))
        self.assertEqual(1, tracker.update([candidate])[candidate.identity])

    def test_pid_reuse_does_not_inherit_count(self):
        tracker = watchdog.ObservationTracker()
        original = process_info(10, 100)
        reused = process_info(10, 200)
        tracker.update([original])
        tracker.update([original])
        counts = tracker.update([reused])
        self.assertEqual({reused.identity: 1}, counts)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.config = watchdog.Config(batch_limit=2, term_grace_seconds=1)

    def test_term_precedes_kill_after_two_revalidations(self):
        candidate = process_info(10)
        scanner = SequenceScanner([scan_result(candidate), scan_result(candidate)])
        signals = []
        engine = watchdog.CleanupEngine(
            scanner,
            self.config,
            open_pidfd=lambda pid: pid,
            send_pidfd_signal=lambda pidfd, signal_number: signals.append((pidfd, signal_number)),
            close_pidfd=lambda _pidfd: None,
            sleep=lambda _seconds: None,
        )

        decisions = engine.clean([candidate])

        self.assertEqual([(10, signal.SIGTERM), (10, signal.SIGKILL)], signals)
        self.assertTrue(decisions[0].term_sent)
        self.assertTrue(decisions[0].kill_sent)

    def test_pre_term_identity_change_sends_no_signal(self):
        candidate = process_info(10)
        scanner = SequenceScanner([scan_result(process_info(10, start_time_ticks=200))])
        signals = []
        engine = watchdog.CleanupEngine(
            scanner,
            self.config,
            open_pidfd=lambda pid: pid,
            send_pidfd_signal=lambda pidfd, signal_number: signals.append((pidfd, signal_number)),
            close_pidfd=lambda _pidfd: None,
            sleep=lambda _seconds: None,
        )

        decisions = engine.clean([candidate])

        self.assertEqual([], signals)
        self.assertEqual("preserved-pre-term-revalidation", decisions[0].decision)

    def test_post_term_predicate_change_prevents_kill(self):
        candidate = process_info(10)
        scanner = SequenceScanner([scan_result(candidate), scan_result()])
        signals = []
        engine = watchdog.CleanupEngine(
            scanner,
            self.config,
            open_pidfd=lambda pid: pid,
            send_pidfd_signal=lambda pidfd, signal_number: signals.append((pidfd, signal_number)),
            close_pidfd=lambda _pidfd: None,
            sleep=lambda _seconds: None,
        )

        decisions = engine.clean([candidate])

        self.assertEqual([(10, signal.SIGTERM)], signals)
        self.assertEqual("resolved-after-term", decisions[0].decision)
        self.assertFalse(decisions[0].kill_sent)

    def test_batch_limit_selects_oldest(self):
        candidates = [process_info(10, age_seconds=400), process_info(11, age_seconds=900), process_info(12, age_seconds=600)]
        scanner = SequenceScanner([scan_result(*candidates)])
        signals = []
        engine = watchdog.CleanupEngine(
            scanner,
            self.config,
            open_pidfd=lambda pid: pid,
            send_pidfd_signal=lambda pidfd, signal_number: signals.append((pidfd, signal_number)),
            close_pidfd=lambda _pidfd: None,
            sleep=lambda _seconds: None,
        )

        engine.clean(candidates)

        term_pids = [pid for pid, signal_number in signals if signal_number == signal.SIGTERM]
        self.assertEqual([11, 12], term_pids)


class ConfigTests(unittest.TestCase):
    def test_unknown_key_refuses_configuration(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            config_path = Path(temporary_directory) / "watchdog.conf"
            config_path.write_text("ACTIVE=true\nUNSAFE=yes\n", encoding="utf-8")
            with self.assertRaises(watchdog.ConfigError):
                watchdog.Config.load(config_path)

    def test_invalid_batch_limit_refuses_configuration(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            config_path = Path(temporary_directory) / "watchdog.conf"
            config_path.write_text("BATCH_LIMIT=0\n", encoding="utf-8")
            with self.assertRaises(watchdog.ConfigError):
                watchdog.Config.load(config_path)

    def test_confirmation_count_cannot_drop_below_three(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            config_path = Path(temporary_directory) / "watchdog.conf"
            config_path.write_text("CONFIRMATIONS=2\n", encoding="utf-8")
            with self.assertRaises(watchdog.ConfigError):
                watchdog.Config.load(config_path)

    def test_inactive_is_default(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            config = watchdog.Config.load(Path(temporary_directory) / "missing.conf")
            self.assertFalse(config.active)


class DaemonTests(unittest.TestCase):
    def test_existing_lock_prevents_duplicate_daemon(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            run_dir = Path(temporary_directory) / "run"
            log_dir = Path(temporary_directory) / "log"
            run_dir.mkdir()
            lock_file = (run_dir / "watchdog.lock").open("a+", encoding="utf-8")
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            daemon = watchdog.WatchdogDaemon(
                watchdog.Config(),
                SequenceScanner([scan_result()]),
                run_dir,
                log_dir,
                sleep=lambda _seconds: None,
            )

            self.assertEqual(0, daemon.run(max_cycles=1))
            self.assertFalse((run_dir / "status.json").exists())
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            lock_file.close()

    def test_rotating_log_is_bounded(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            log_dir = Path(temporary_directory)
            config = watchdog.Config(log_max_bytes=100, log_backups=2)
            logger = watchdog.configure_logger(log_dir, config)
            for index in range(50):
                logger.info("bounded-message-%d-xxxxxxxxxxxxxxxx", index)
            for handler in logger.handlers:
                handler.close()
            logger.handlers.clear()

            log_files = sorted(log_dir.glob("watchdog.log*"))
            self.assertLessEqual(len(log_files), 3)
            self.assertTrue(all(path.stat().st_size <= 200 for path in log_files))


class StatusTests(unittest.TestCase):
    def test_corrupt_status_file_reports_unavailable(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            run_dir = root / "run"
            run_dir.mkdir()
            run_dir.joinpath("status.json").write_text("{", encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                result = watchdog.main(
                    [
                        "--config",
                        str(root / "missing.conf"),
                        "--run-dir",
                        str(run_dir),
                        "status",
                    ]
                )

            payload = json.loads(output.getvalue())
            self.assertEqual(3, result)
            self.assertFalse(payload["running"])
            self.assertEqual("unavailable", payload["status"])

    def test_corrupt_identity_file_reports_not_running(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            run_dir = root / "run"
            run_dir.mkdir()
            run_dir.joinpath("status.json").write_text('{"health":"healthy"}', encoding="utf-8")
            run_dir.joinpath("watchdog.pid.json").write_text("{", encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                result = watchdog.main(
                    [
                        "--config",
                        str(root / "missing.conf"),
                        "--run-dir",
                        str(run_dir),
                        "status",
                    ]
                )

            payload = json.loads(output.getvalue())
            self.assertEqual(3, result)
            self.assertFalse(payload["running"])
            self.assertEqual("JSONDecodeError", payload["watchdog_identity_error"])


class InstallerTests(unittest.TestCase):
    def test_stale_identity_with_held_lock_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            run_dir = installer.rooted(root, installer.RUN_DIR)
            run_dir.mkdir(parents=True)
            run_dir.joinpath("watchdog.pid.json").write_text(
                '{"pid":2147483647,"start_time_ticks":1}\n', encoding="utf-8"
            )
            lock_file = (run_dir / "watchdog.lock").open("a+", encoding="utf-8")
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            try:
                with self.assertRaises(installer.InstallError):
                    installer.stop_watchdog(root)
            finally:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                lock_file.close()

    def test_startup_clears_stale_runtime_status(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            status_path = installer.rooted(root, f"{installer.RUN_DIR}/status.json")
            status_path.parent.mkdir(parents=True)
            status_path.write_text('{"mode":"stale"}\n', encoding="utf-8")

            installer.clear_runtime_status(root)

            self.assertFalse(status_path.exists())

    def test_missing_identity_with_held_lock_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            run_dir = installer.rooted(root, installer.RUN_DIR)
            run_dir.mkdir(parents=True)
            lock_file = (run_dir / "watchdog.lock").open("a+", encoding="utf-8")
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            try:
                with self.assertRaises(installer.InstallError):
                    installer.stop_watchdog(root)
            finally:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                lock_file.close()

    def test_uninstall_restores_absent_wsl_config_to_absence(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            installer.install(root, MODULE_DIR / "wsl_relay_watchdog.py", active=False, start=False)
            wsl_config = installer.rooted(root, installer.WSL_CONFIG_PATH)
            self.assertTrue(wsl_config.exists())

            installer.uninstall(root)

            self.assertFalse(wsl_config.exists())

    def test_boot_command_preserves_systemd_and_other_sections(self):
        original = "[boot]\nsystemd=false\n\n[interop]\nappendWindowsPath=false\n"
        updated, created = installer.install_boot_command(original)
        self.assertFalse(created)
        self.assertIn("systemd=false", updated)
        self.assertIn("appendWindowsPath=false", updated)
        self.assertIn(f"command={installer.MANAGED_BOOT_COMMAND}", updated)

    def test_conflicting_boot_command_is_refused(self):
        with self.assertRaises(installer.InstallError):
            installer.install_boot_command("[boot]\ncommand=service docker start\nsystemd=false\n")

    def test_duplicate_boot_sections_are_refused(self):
        duplicate = "[boot]\nsystemd=false\n\n[network]\ngenerateResolvConf=true\n\n[boot]\ncommand=service docker start\n"
        with self.assertRaises(installer.InstallError):
            installer.install_boot_command(duplicate)
        with self.assertRaises(installer.InstallError):
            installer.uninstall_boot_command(duplicate, boot_section_created=False)

    def test_install_and_uninstall_preserve_unrelated_configuration(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            etc_dir = root / "etc"
            etc_dir.mkdir()
            wsl_config = etc_dir / "wsl.conf"
            wsl_config.write_text(
                "[boot]\nsystemd=false\n\n[interop]\nappendWindowsPath=false\n",
                encoding="utf-8",
            )

            result = installer.install(root, MODULE_DIR / "wsl_relay_watchdog.py", active=False, start=False)

            self.assertTrue(result["installed"])
            self.assertIn("systemd=false", wsl_config.read_text(encoding="utf-8"))
            command_path = installer.rooted(root, installer.COMMAND_PATH)
            self.assertEqual(0o755, stat.S_IMODE(command_path.stat().st_mode))
            config_path = installer.rooted(root, installer.CONFIG_PATH)
            self.assertIn("ACTIVE=false", config_path.read_text(encoding="utf-8"))

            current = wsl_config.read_text(encoding="utf-8")
            wsl_config.write_text(current + "\n[network]\ngenerateResolvConf=true\n", encoding="utf-8")
            installer.uninstall(root)

            final_config = wsl_config.read_text(encoding="utf-8")
            self.assertIn("systemd=false", final_config)
            self.assertIn("generateResolvConf=true", final_config)
            self.assertNotIn(installer.MANAGED_BOOT_COMMAND, final_config)
            self.assertFalse(command_path.exists())

    def test_install_conflict_makes_no_managed_file_changes(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            etc_dir = root / "etc"
            etc_dir.mkdir()
            wsl_config = etc_dir / "wsl.conf"
            original = "[boot]\ncommand=service docker start\nsystemd=false\n"
            wsl_config.write_text(original, encoding="utf-8")

            with self.assertRaises(installer.InstallError):
                installer.install(root, MODULE_DIR / "wsl_relay_watchdog.py", active=False, start=False)

            self.assertEqual(original, wsl_config.read_text(encoding="utf-8"))
            self.assertFalse(installer.rooted(root, installer.ENGINE_PATH).exists())

    def test_first_install_refuses_unmanaged_reserved_file(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            etc_dir = root / "etc"
            etc_dir.mkdir()
            (etc_dir / "wsl.conf").write_text("[boot]\nsystemd=false\n", encoding="utf-8")
            command_path = installer.rooted(root, installer.COMMAND_PATH)
            command_path.parent.mkdir(parents=True)
            command_path.write_text("unmanaged\n", encoding="utf-8")

            with self.assertRaises(installer.InstallError):
                installer.install(root, MODULE_DIR / "wsl_relay_watchdog.py", active=False, start=False)

            self.assertEqual("unmanaged\n", command_path.read_text(encoding="utf-8"))

    def test_upgrade_refuses_modified_recorded_file(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            etc_dir = root / "etc"
            etc_dir.mkdir()
            (etc_dir / "wsl.conf").write_text("[boot]\nsystemd=false\n", encoding="utf-8")
            installer.install(root, MODULE_DIR / "wsl_relay_watchdog.py", active=False, start=False)
            command_path = installer.rooted(root, installer.COMMAND_PATH)
            command_path.write_text("modified\n", encoding="utf-8")

            with self.assertRaises(installer.InstallError):
                installer.install(root, MODULE_DIR / "wsl_relay_watchdog.py", active=False, start=False)

            with self.assertRaises(installer.InstallError):
                installer.uninstall(root)

            self.assertEqual("modified\n", command_path.read_text(encoding="utf-8"))

    def test_uninstall_refuses_changed_boot_command(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            etc_dir = root / "etc"
            etc_dir.mkdir()
            wsl_config = etc_dir / "wsl.conf"
            wsl_config.write_text("[boot]\nsystemd=false\n", encoding="utf-8")
            installer.install(root, MODULE_DIR / "wsl_relay_watchdog.py", active=False, start=False)
            wsl_config.write_text("[boot]\ncommand=changed-command\nsystemd=false\n", encoding="utf-8")

            with self.assertRaises(installer.InstallError):
                installer.uninstall(root)

            self.assertTrue(installer.rooted(root, installer.ENGINE_PATH).exists())


if __name__ == "__main__":
    unittest.main()
