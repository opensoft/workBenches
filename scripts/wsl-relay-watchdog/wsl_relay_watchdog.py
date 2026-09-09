#!/usr/bin/env python3

from __future__ import annotations

import argparse
import dataclasses
import fcntl
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import re
import signal
import sys
import tempfile
import time
from typing import Callable, Iterable


VERSION = "1.0.0"
DEFAULT_CONFIG_PATH = Path("/etc/wsl-relay-watchdog.conf")
DEFAULT_RUN_DIR = Path("/run/wsl-relay-watchdog")
DEFAULT_LOG_DIR = Path("/var/log/wsl-relay-watchdog")
MANAGED_PROCESS_NAMES = {"Relay", "SessionLeader"}
NAMED_RELAY_PATTERN = re.compile(r"^Relay\([0-9]+\)$")


class WatchdogError(RuntimeError):
    pass


class ConfigError(WatchdogError):
    pass


@dataclasses.dataclass(frozen=True)
class Config:
    active: bool = False
    min_age_seconds: int = 300
    confirmations: int = 3
    interval_seconds: int = 30
    batch_limit: int = 32
    term_grace_seconds: int = 3
    log_max_bytes: int = 1_048_576
    log_backups: int = 3

    @classmethod
    def load(cls, path: Path) -> "Config":
        values: dict[str, str] = {}
        if path.exists():
            for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    raise ConfigError(f"{path}:{line_number}: expected KEY=VALUE")
                key, value = (part.strip() for part in line.split("=", 1))
                if key in values:
                    raise ConfigError(f"{path}:{line_number}: duplicate key {key}")
                values[key] = value

        allowed = {
            "ACTIVE",
            "MIN_AGE_SECONDS",
            "CONFIRMATIONS",
            "INTERVAL_SECONDS",
            "BATCH_LIMIT",
            "TERM_GRACE_SECONDS",
            "LOG_MAX_BYTES",
            "LOG_BACKUPS",
        }
        unknown = sorted(set(values) - allowed)
        if unknown:
            raise ConfigError(f"unsupported configuration keys: {', '.join(unknown)}")

        active = cls._parse_bool("ACTIVE", values.get("ACTIVE", "false"))
        config = cls(
            active=active,
            min_age_seconds=cls._parse_int(values, "MIN_AGE_SECONDS", 300, 60, 86_400),
            confirmations=cls._parse_int(values, "CONFIRMATIONS", 3, 3, 20),
            interval_seconds=cls._parse_int(values, "INTERVAL_SECONDS", 30, 5, 3_600),
            batch_limit=cls._parse_int(values, "BATCH_LIMIT", 32, 1, 128),
            term_grace_seconds=cls._parse_int(values, "TERM_GRACE_SECONDS", 3, 1, 30),
            log_max_bytes=cls._parse_int(values, "LOG_MAX_BYTES", 1_048_576, 65_536, 10_485_760),
            log_backups=cls._parse_int(values, "LOG_BACKUPS", 3, 1, 10),
        )
        return config

    @staticmethod
    def _parse_bool(key: str, value: str) -> bool:
        normalized = value.lower()
        if normalized == "true":
            return True
        if normalized == "false":
            return False
        raise ConfigError(f"{key} must be true or false")

    @staticmethod
    def _parse_int(values: dict[str, str], key: str, default: int, minimum: int, maximum: int) -> int:
        raw_value = values.get(key, str(default))
        if not re.fullmatch(r"[0-9]+", raw_value):
            raise ConfigError(f"{key} must be an integer between {minimum} and {maximum}")
        value = int(raw_value)
        if value < minimum or value > maximum:
            raise ConfigError(f"{key} must be between {minimum} and {maximum}")
        return value


@dataclasses.dataclass(frozen=True, order=True)
class ProcessIdentity:
    pid: int
    start_time_ticks: int


@dataclasses.dataclass(frozen=True)
class ProcessInfo:
    identity: ProcessIdentity
    parent_pid: int
    name: str
    command_line: tuple[str, ...] | None
    age_seconds: float
    child_count: int


@dataclasses.dataclass(frozen=True)
class ScanResult:
    timestamp: float
    strict_candidates: tuple[ProcessInfo, ...]
    named_relays: tuple[ProcessInfo, ...]
    session_leaders: tuple[ProcessInfo, ...]
    inspection_errors: tuple[str, ...]


@dataclasses.dataclass(frozen=True)
class SignalDecision:
    identity: ProcessIdentity
    age_seconds: float | None
    decision: str
    term_sent: bool = False
    kill_sent: bool = False
    error: str | None = None


class ProcScanner:
    def __init__(self, proc_root: Path = Path("/proc"), clock_ticks: int | None = None) -> None:
        self.proc_root = proc_root
        self.clock_ticks = clock_ticks or int(os.sysconf("SC_CLK_TCK"))

    @staticmethod
    def _parse_stat(raw_stat: str) -> tuple[int, int]:
        close_paren = raw_stat.rfind(")")
        open_paren = raw_stat.find("(")
        if open_paren <= 0 or close_paren <= open_paren:
            raise ValueError("malformed stat process name")
        fields = raw_stat[close_paren + 1 :].strip().split()
        if len(fields) <= 19:
            raise ValueError("stat has too few fields")
        parent_pid = int(fields[1])
        start_time_ticks = int(fields[19])
        if parent_pid < 0 or start_time_ticks < 0:
            raise ValueError("stat contains negative identity values")
        return parent_pid, start_time_ticks

    @staticmethod
    def _parse_command_line(raw_command_line: bytes) -> tuple[str, ...]:
        if not raw_command_line:
            return ()
        if not raw_command_line.endswith(b"\0"):
            raise ValueError("cmdline is missing its procfs delimiter")
        parts = raw_command_line.split(b"\0")
        parts.pop()
        return tuple(part.decode("utf-8", errors="strict") for part in parts)

    def _uptime_seconds(self) -> float:
        raw_uptime = (self.proc_root / "uptime").read_text(encoding="ascii").split()
        if not raw_uptime:
            raise ValueError("uptime is empty")
        return float(raw_uptime[0])

    def read_identity(self, pid: int) -> ProcessIdentity | None:
        try:
            _, start_time_ticks = self._parse_stat(
                (self.proc_root / str(pid) / "stat").read_text(encoding="utf-8")
            )
            return ProcessIdentity(pid=pid, start_time_ticks=start_time_ticks)
        except (FileNotFoundError, PermissionError, OSError, UnicodeError, ValueError):
            return None

    def inspect_strict_candidate(
        self, identity: ProcessIdentity, min_age_seconds: int
    ) -> ProcessInfo | None:
        process_dir = self.proc_root / str(identity.pid)
        try:
            uptime_seconds = self._uptime_seconds()
            parent_pid, start_time_ticks = self._parse_stat(
                (process_dir / "stat").read_text(encoding="utf-8")
            )
            if start_time_ticks != identity.start_time_ticks:
                return None
            raw_name = (process_dir / "comm").read_bytes()
            if not raw_name.endswith(b"\n"):
                return None
            raw_name = raw_name[:-1]
            if b"\n" in raw_name or b"\r" in raw_name:
                return None
            name = raw_name.decode("utf-8", errors="strict")
            if name != "Relay":
                return None
            command_line = self._parse_command_line((process_dir / "cmdline").read_bytes())
            task_dirs = tuple(
                task_dir for task_dir in (process_dir / "task").iterdir() if task_dir.name.isdigit()
            )
            if not task_dirs:
                return None
            child_pids: set[int] = set()
            for task_dir in task_dirs:
                raw_children = (task_dir / "children").read_text(encoding="ascii").strip()
                if not raw_children:
                    continue
                task_child_pids = [int(child_pid) for child_pid in raw_children.split()]
                if any(child_pid <= 0 for child_pid in task_child_pids):
                    return None
                child_pids.update(task_child_pids)
            age_seconds = uptime_seconds - (start_time_ticks / self.clock_ticks)
            if age_seconds < min_age_seconds:
                return None
            candidate = ProcessInfo(
                identity=identity,
                parent_pid=parent_pid,
                name=name,
                command_line=command_line,
                age_seconds=age_seconds,
                child_count=len(child_pids),
            )
            if parent_pid != 1 or command_line != ("/init",) or candidate.child_count != 0:
                return None
            return candidate
        except (FileNotFoundError, PermissionError, OSError, UnicodeError, ValueError):
            return None

    def scan(self, min_age_seconds: int) -> ScanResult:
        timestamp = time.time()
        inspection_errors: list[str] = []
        try:
            uptime_seconds = self._uptime_seconds()
        except (FileNotFoundError, PermissionError, OSError, ValueError) as error:
            raise WatchdogError(f"cannot read procfs uptime: {error}") from error

        partial_records: dict[int, tuple[int, int, str, tuple[str, ...] | None, float, int]] = {}
        try:
            process_dirs = tuple(self.proc_root.iterdir())
        except OSError as error:
            raise WatchdogError(f"cannot enumerate {self.proc_root}: {error}") from error

        for process_dir in process_dirs:
            if not process_dir.name.isdigit():
                continue
            pid = int(process_dir.name)
            try:
                parent_pid, start_time_ticks = self._parse_stat(
                    (process_dir / "stat").read_text(encoding="utf-8")
                )
                raw_name = (process_dir / "comm").read_bytes()
                if not raw_name.endswith(b"\n"):
                    raise ValueError("comm is missing its procfs delimiter")
                raw_name = raw_name[:-1]
                if b"\n" in raw_name or b"\r" in raw_name:
                    raise ValueError("comm contains an embedded newline")
                name = raw_name.decode("utf-8", errors="strict")
                command_line = None
                child_count = 0
                if name == "Relay":
                    command_line = self._parse_command_line((process_dir / "cmdline").read_bytes())
                    task_dirs = tuple(
                        task_dir
                        for task_dir in (process_dir / "task").iterdir()
                        if task_dir.name.isdigit()
                    )
                    if not task_dirs:
                        raise ValueError("relay has no readable task entries")
                    child_pids: set[int] = set()
                    for task_dir in task_dirs:
                        raw_children = (task_dir / "children").read_text(encoding="ascii").strip()
                        if not raw_children:
                            continue
                        task_child_pids = [int(child_pid) for child_pid in raw_children.split()]
                        if any(child_pid <= 0 for child_pid in task_child_pids):
                            raise ValueError("children contains an invalid PID")
                        child_pids.update(task_child_pids)
                    child_count = len(child_pids)
                age_seconds = uptime_seconds - (start_time_ticks / self.clock_ticks)
                if age_seconds < 0:
                    raise ValueError("process start time is after uptime")
                partial_records[pid] = (
                    parent_pid,
                    start_time_ticks,
                    name,
                    command_line,
                    age_seconds,
                    child_count,
                )
            except (FileNotFoundError, PermissionError, OSError, UnicodeError, ValueError) as error:
                if len(inspection_errors) < 50:
                    inspection_errors.append(f"pid={pid}: {type(error).__name__}")

        strict_candidates: list[ProcessInfo] = []
        named_relays: list[ProcessInfo] = []
        session_leaders: list[ProcessInfo] = []
        for pid, (parent_pid, start_time_ticks, name, command_line, age_seconds, child_count) in partial_records.items():
            info = ProcessInfo(
                identity=ProcessIdentity(pid=pid, start_time_ticks=start_time_ticks),
                parent_pid=parent_pid,
                name=name,
                command_line=command_line,
                age_seconds=age_seconds,
                child_count=child_count,
            )
            if NAMED_RELAY_PATTERN.fullmatch(name):
                named_relays.append(info)
            elif name == "SessionLeader":
                session_leaders.append(info)
            elif (
                name == "Relay"
                and parent_pid == 1
                and command_line == ("/init",)
                and info.child_count == 0
                and age_seconds >= min_age_seconds
            ):
                strict_candidates.append(info)

        strict_candidates.sort(key=lambda item: (-item.age_seconds, item.identity.pid))
        named_relays.sort(key=lambda item: item.identity.pid)
        session_leaders.sort(key=lambda item: item.identity.pid)
        return ScanResult(
            timestamp=timestamp,
            strict_candidates=tuple(strict_candidates),
            named_relays=tuple(named_relays),
            session_leaders=tuple(session_leaders),
            inspection_errors=tuple(inspection_errors),
        )


class ObservationTracker:
    def __init__(self) -> None:
        self._counts: dict[ProcessIdentity, int] = {}

    def update(self, candidates: Iterable[ProcessInfo]) -> dict[ProcessIdentity, int]:
        next_counts: dict[ProcessIdentity, int] = {}
        for candidate in candidates:
            identity = candidate.identity
            next_counts[identity] = self._counts.get(identity, 0) + 1
        self._counts = next_counts
        return dict(self._counts)


class CleanupEngine:
    def __init__(
        self,
        scanner: ProcScanner,
        config: Config,
        open_pidfd: Callable[[int], int] = os.pidfd_open,
        send_pidfd_signal: Callable[[int, int], None] | None = None,
        close_pidfd: Callable[[int], None] = os.close,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        self.scanner = scanner
        self.config = config
        self.open_pidfd = open_pidfd
        self.send_pidfd_signal = send_pidfd_signal or (
            lambda pidfd, signal_number: signal.pidfd_send_signal(pidfd, signal_number, None, 0)
        )
        self.close_pidfd = close_pidfd
        self.sleep = sleep

    def _revalidate(self, identity: ProcessIdentity) -> tuple[ProcessInfo | None, tuple[str, ...]]:
        return self.scanner.inspect_strict_candidate(identity, self.config.min_age_seconds), ()

    def clean(self, eligible: Iterable[ProcessInfo]) -> tuple[SignalDecision, ...]:
        ordered = sorted(eligible, key=lambda item: (-item.age_seconds, item.identity.pid))
        decisions: list[SignalDecision] = []
        for original in ordered[: self.config.batch_limit]:
            identity = original.identity
            try:
                pidfd = self.open_pidfd(identity.pid)
            except (ProcessLookupError, PermissionError, OSError) as error:
                decisions.append(
                    SignalDecision(
                        identity=identity,
                        age_seconds=None,
                        decision="pidfd-open-error",
                        error=type(error).__name__,
                    )
                )
                continue
            try:
                current, _ = self._revalidate(identity)
                if current is None:
                    decisions.append(
                        SignalDecision(identity=identity, age_seconds=None, decision="preserved-pre-term-revalidation")
                    )
                    continue
                try:
                    self.send_pidfd_signal(pidfd, signal.SIGTERM)
                except ProcessLookupError:
                    decisions.append(
                        SignalDecision(identity=identity, age_seconds=current.age_seconds, decision="resolved-before-term")
                    )
                    continue
                except (PermissionError, OSError) as error:
                    decisions.append(
                        SignalDecision(
                            identity=identity,
                            age_seconds=current.age_seconds,
                            decision="term-error",
                            error=type(error).__name__,
                        )
                    )
                    continue

                self.sleep(self.config.term_grace_seconds)
                survivor, _ = self._revalidate(identity)
                if survivor is None:
                    decisions.append(
                        SignalDecision(
                            identity=identity,
                            age_seconds=current.age_seconds,
                            decision="resolved-after-term",
                            term_sent=True,
                        )
                    )
                    continue
                try:
                    self.send_pidfd_signal(pidfd, signal.SIGKILL)
                    decisions.append(
                        SignalDecision(
                            identity=identity,
                            age_seconds=survivor.age_seconds,
                            decision="kill-sent",
                            term_sent=True,
                            kill_sent=True,
                        )
                    )
                except ProcessLookupError:
                    decisions.append(
                        SignalDecision(
                            identity=identity,
                            age_seconds=survivor.age_seconds,
                            decision="resolved-before-kill",
                            term_sent=True,
                        )
                    )
                except (PermissionError, OSError) as error:
                    decisions.append(
                        SignalDecision(
                            identity=identity,
                            age_seconds=survivor.age_seconds,
                            decision="kill-error",
                            term_sent=True,
                            error=type(error).__name__,
                        )
                    )
            finally:
                self.close_pidfd(pidfd)
        return tuple(decisions)


def atomic_write_json(path: Path, payload: dict[str, object], mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as temporary_file:
            json.dump(payload, temporary_file, sort_keys=True)
            temporary_file.write("\n")
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.chmod(temporary_name, mode)
        os.replace(temporary_name, path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass


def configure_logger(log_dir: Path, config: Config) -> logging.Logger:
    log_dir.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("wsl-relay-watchdog")
    logger.handlers.clear()
    logger.setLevel(logging.INFO)
    handler = RotatingFileHandler(
        log_dir / "watchdog.log",
        maxBytes=config.log_max_bytes,
        backupCount=config.log_backups,
        encoding="utf-8",
    )
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logger.addHandler(handler)
    logger.propagate = False
    return logger


def process_summary(process: ProcessInfo) -> dict[str, object]:
    return {
        "pid": process.identity.pid,
        "start_time_ticks": process.identity.start_time_ticks,
        "age_seconds": round(process.age_seconds, 3),
    }


class WatchdogDaemon:
    def __init__(
        self,
        config: Config,
        scanner: ProcScanner,
        run_dir: Path,
        log_dir: Path,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        self.config = config
        self.scanner = scanner
        self.run_dir = run_dir
        self.log_dir = log_dir
        self.sleep = sleep
        self.tracker = ObservationTracker()
        self.cleanup_engine = CleanupEngine(scanner, config, sleep=sleep)
        self.stop_requested = False
        self.logger: logging.Logger | None = None

    def _request_stop(self, _signal_number: int, _frame: object) -> None:
        self.stop_requested = True

    def _write_process_identity(self) -> None:
        identity = self.scanner.read_identity(os.getpid())
        if identity is None:
            raise WatchdogError("cannot verify watchdog process identity")
        atomic_write_json(
            self.run_dir / "watchdog.pid.json",
            {
                "pid": identity.pid,
                "start_time_ticks": identity.start_time_ticks,
                "version": VERSION,
            },
            mode=0o644,
        )

    def _log_decision(self, decision: SignalDecision) -> None:
        if self.logger is None:
            return
        self.logger.info(
            "pid=%d start_time_ticks=%d age_seconds=%s decision=%s term_sent=%s kill_sent=%s error=%s",
            decision.identity.pid,
            decision.identity.start_time_ticks,
            "unknown" if decision.age_seconds is None else f"{decision.age_seconds:.3f}",
            decision.decision,
            str(decision.term_sent).lower(),
            str(decision.kill_sent).lower(),
            decision.error or "none",
        )

    def run_cycle(self) -> dict[str, object]:
        scan_result = self.scanner.scan(self.config.min_age_seconds)
        observations = self.tracker.update(scan_result.strict_candidates)
        eligible = tuple(
            process
            for process in scan_result.strict_candidates
            if observations.get(process.identity, 0) >= self.config.confirmations
        )
        decisions: tuple[SignalDecision, ...] = ()
        if self.config.active:
            decisions = self.cleanup_engine.clean(eligible)
            for decision in decisions:
                self._log_decision(decision)

        term_sent = sum(1 for decision in decisions if decision.term_sent)
        kill_sent = sum(1 for decision in decisions if decision.kill_sent)
        signal_errors = sum(1 for decision in decisions if decision.error is not None)
        now = time.time()
        status: dict[str, object] = {
            "version": VERSION,
            "timestamp": now,
            "mode": "active" if self.config.active else "inactive",
            "strict_candidates": len(scan_result.strict_candidates),
            "confirmed_candidates": len(eligible),
            "protected_named_relays": len(scan_result.named_relays),
            "protected_session_leaders": len(scan_result.session_leaders),
            "term_sent": term_sent,
            "kill_sent": kill_sent,
            "inspection_errors": len(scan_result.inspection_errors),
            "signal_errors": signal_errors,
            "next_scan_time": now + self.config.interval_seconds,
        }
        atomic_write_json(self.run_dir / "status.json", status)
        if self.logger is not None:
            self.logger.info(
                "cycle mode=%s strict=%d confirmed=%d named_relays=%d session_leaders=%d term_sent=%d kill_sent=%d inspection_errors=%d signal_errors=%d",
                status["mode"],
                status["strict_candidates"],
                status["confirmed_candidates"],
                status["protected_named_relays"],
                status["protected_session_leaders"],
                term_sent,
                kill_sent,
                status["inspection_errors"],
                signal_errors,
            )
        return status

    def run(self, max_cycles: int | None = None) -> int:
        if self.config.active and os.geteuid() != 0:
            raise WatchdogError("active daemon mode requires root")
        self.run_dir.mkdir(parents=True, exist_ok=True)
        lock_file = (self.run_dir / "watchdog.lock").open("a+", encoding="utf-8")
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            lock_file.close()
            return 0

        os.umask(0o027)
        self.logger = configure_logger(self.log_dir, self.config)
        self._write_process_identity()
        signal.signal(signal.SIGTERM, self._request_stop)
        signal.signal(signal.SIGINT, self._request_stop)
        cycles = 0
        try:
            while not self.stop_requested:
                self.run_cycle()
                cycles += 1
                if max_cycles is not None and cycles >= max_cycles:
                    break
                self.sleep(self.config.interval_seconds)
        finally:
            try:
                (self.run_dir / "watchdog.pid.json").unlink()
            except FileNotFoundError:
                pass
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            lock_file.close()
        return 0


def scan_payload(scan_result: ScanResult, config: Config) -> dict[str, object]:
    return {
        "version": VERSION,
        "timestamp": scan_result.timestamp,
        "mode": "scan",
        "active_configuration": config.active,
        "minimum_age_seconds": config.min_age_seconds,
        "strict_count": len(scan_result.strict_candidates),
        "strict_candidates": [process_summary(process) for process in scan_result.strict_candidates],
        "protected_named_relay_count": len(scan_result.named_relays),
        "protected_named_relays": [process_summary(process) for process in scan_result.named_relays],
        "protected_session_leader_count": len(scan_result.session_leaders),
        "protected_session_leaders": [process_summary(process) for process in scan_result.session_leaders],
        "inspection_errors": list(scan_result.inspection_errors),
    }


def print_json(payload: object) -> None:
    json.dump(payload, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Strict WSL orphan relay watchdog")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG_PATH)
    parser.add_argument("--proc-root", type=Path, default=Path("/proc"))
    parser.add_argument("--run-dir", type=Path, default=DEFAULT_RUN_DIR)
    parser.add_argument("--log-dir", type=Path, default=DEFAULT_LOG_DIR)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("scan", help="inspect live processes without signaling")
    subparsers.add_parser("status", help="show the most recent daemon status")
    daemon_parser = subparsers.add_parser("daemon", help="run the singleton monitoring daemon")
    daemon_parser.add_argument("--max-cycles", type=int, help=argparse.SUPPRESS)
    run_once_parser = subparsers.add_parser("run-once", help="confirm and clean one bounded batch")
    run_once_parser.add_argument("--active", action="store_true", help="explicitly permit signaling")
    subparsers.add_parser("validate-config", help="validate configuration without scanning")
    return parser


def run_once(config: Config, scanner: ProcScanner, active_confirmation: bool) -> int:
    if not config.active or not active_confirmation:
        raise WatchdogError("run-once signaling requires ACTIVE=true and --active")
    if os.geteuid() != 0:
        raise WatchdogError("active run-once mode requires root")
    tracker = ObservationTracker()
    latest_scan: ScanResult | None = None
    counts: dict[ProcessIdentity, int] = {}
    for observation_number in range(config.confirmations):
        latest_scan = scanner.scan(config.min_age_seconds)
        counts = tracker.update(latest_scan.strict_candidates)
        if observation_number + 1 < config.confirmations:
            time.sleep(config.interval_seconds)
    assert latest_scan is not None
    eligible = [
        process
        for process in latest_scan.strict_candidates
        if counts.get(process.identity, 0) >= config.confirmations
    ]
    decisions = CleanupEngine(scanner, config).clean(eligible)
    print_json(
        {
            "mode": "active-run-once",
            "strict_candidates": len(latest_scan.strict_candidates),
            "confirmed_candidates": len(eligible),
            "term_sent": sum(1 for decision in decisions if decision.term_sent),
            "kill_sent": sum(1 for decision in decisions if decision.kill_sent),
            "decisions": [dataclasses.asdict(decision) for decision in decisions],
        }
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    arguments = parser.parse_args(argv)
    try:
        config = None if arguments.command == "status" else Config.load(arguments.config)
        signaling_enabled = config is not None and config.active and (
            arguments.command == "daemon"
            or (arguments.command == "run-once" and getattr(arguments, "active", False))
        )
        if signaling_enabled and arguments.proc_root != Path("/proc"):
            raise WatchdogError("custom --proc-root is permitted only in non-signaling modes")
        scanner = ProcScanner(arguments.proc_root)
        if arguments.command == "validate-config":
            assert config is not None
            print_json({"valid": True, "active": config.active, "version": VERSION})
            return 0
        if arguments.command == "scan":
            assert config is not None
            print_json(scan_payload(scanner.scan(config.min_age_seconds), config))
            return 0
        if arguments.command == "status":
            status_path = arguments.run_dir / "status.json"
            if not status_path.exists():
                print_json({"running": False, "status": "unavailable"})
                return 3
            try:
                status_payload = json.loads(status_path.read_text(encoding="utf-8"))
                if not isinstance(status_payload, dict):
                    raise ValueError("status payload is not an object")
            except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
                print_json(
                    {
                        "running": False,
                        "status": "unavailable",
                        "status_error": type(error).__name__,
                    }
                )
                return 3
            pid_path = arguments.run_dir / "watchdog.pid.json"
            running = False
            if pid_path.exists():
                try:
                    identity_payload = json.loads(pid_path.read_text(encoding="utf-8"))
                    if not isinstance(identity_payload, dict):
                        raise ValueError("identity payload is not an object")
                    expected_identity = ProcessIdentity(
                        pid=int(identity_payload["pid"]),
                        start_time_ticks=int(identity_payload["start_time_ticks"]),
                    )
                    if expected_identity.pid <= 0 or expected_identity.start_time_ticks < 0:
                        raise ValueError("identity values are out of range")
                    running = scanner.read_identity(expected_identity.pid) == expected_identity
                    status_payload["watchdog_identity"] = dataclasses.asdict(expected_identity)
                except (OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
                    status_payload["watchdog_identity_error"] = type(error).__name__
            status_payload["running"] = running
            print_json(status_payload)
            return 0 if running else 3
        if arguments.command == "run-once":
            assert config is not None
            return run_once(config, scanner, arguments.active)
        if arguments.command == "daemon":
            assert config is not None
            daemon = WatchdogDaemon(config, scanner, arguments.run_dir, arguments.log_dir)
            return daemon.run(max_cycles=arguments.max_cycles)
        parser.error(f"unsupported command: {arguments.command}")
    except (ConfigError, WatchdogError) as error:
        print(f"wsl-relay-watchdog: {error}", file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
