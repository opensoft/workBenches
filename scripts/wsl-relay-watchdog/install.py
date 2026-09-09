#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time


MANAGED_BOOT_COMMAND = "/usr/local/sbin/wsl-relay-watchdog-boot"
ENGINE_PATH = "/usr/local/libexec/wsl-relay-watchdog/wsl_relay_watchdog.py"
COMMAND_PATH = "/usr/local/sbin/wsl-relay-watchdog"
BOOT_PATH = MANAGED_BOOT_COMMAND
CONFIG_PATH = "/etc/wsl-relay-watchdog.conf"
WSL_CONFIG_PATH = "/etc/wsl.conf"
STATE_DIR = "/var/lib/wsl-relay-watchdog"
STATE_PATH = f"{STATE_DIR}/install.json"
RUN_DIR = "/run/wsl-relay-watchdog"
LOG_DIR = "/var/log/wsl-relay-watchdog"


class InstallError(RuntimeError):
    pass


def rooted(root: Path, absolute_path: str) -> Path:
    return root / absolute_path.lstrip("/")


def atomic_write(path: Path, content: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(file_descriptor, "wb") as temporary_file:
            temporary_file.write(content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.chmod(temporary_name, mode)
        if os.geteuid() == 0:
            os.chown(temporary_name, 0, 0)
        os.replace(temporary_name, path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass


def ensure_regular_or_absent(path: Path) -> None:
    if path.is_symlink():
        raise InstallError(f"refusing symbolic link at managed path: {path}")
    if path.exists() and not path.is_file():
        raise InstallError(f"managed path is not a regular file: {path}")


def section_bounds(lines: list[str], section_name: str) -> tuple[int, int] | None:
    section_pattern = re.compile(r"^\s*\[([^]]+)\]\s*$")
    section_headers: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        match = section_pattern.match(line)
        if match:
            section_headers.append((index, match.group(1).strip().lower()))

    matching_indexes = [index for index, name in section_headers if name == section_name.lower()]
    if len(matching_indexes) > 1:
        raise InstallError(f"/etc/wsl.conf contains multiple [{section_name}] sections")
    if not matching_indexes:
        return None
    start = matching_indexes[0]
    end = next((index for index, _name in section_headers if index > start), len(lines))
    return start, end


def install_boot_command(content: str) -> tuple[str, bool]:
    lines = content.splitlines()
    bounds = section_bounds(lines, "boot")
    command_pattern = re.compile(r"^\s*command\s*=\s*(.*?)\s*$", re.IGNORECASE)
    if bounds is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend(["[boot]", f"command={MANAGED_BOOT_COMMAND}"])
        return "\n".join(lines) + "\n", True

    start, end = bounds
    command_indexes: list[int] = []
    command_values: list[str] = []
    for index in range(start + 1, end):
        match = command_pattern.match(lines[index])
        if match:
            command_indexes.append(index)
            command_values.append(match.group(1))
    if len(command_indexes) > 1:
        raise InstallError("/etc/wsl.conf contains multiple [boot] command values")
    if command_indexes:
        if command_values[0] != MANAGED_BOOT_COMMAND:
            raise InstallError(f"conflicting [boot] command: {command_values[0]}")
        return "\n".join(lines) + "\n", False

    lines.insert(start + 1, f"command={MANAGED_BOOT_COMMAND}")
    return "\n".join(lines) + "\n", False


def uninstall_boot_command(content: str, boot_section_created: bool) -> str:
    lines = content.splitlines()
    bounds = section_bounds(lines, "boot")
    if bounds is None:
        return "\n".join(lines) + ("\n" if lines else "")
    start, end = bounds
    command_pattern = re.compile(r"^\s*command\s*=\s*(.*?)\s*$", re.IGNORECASE)
    managed_indexes: list[int] = []
    conflicting_commands: list[str] = []
    for index in range(start + 1, end):
        match = command_pattern.match(lines[index])
        if not match:
            continue
        if match.group(1) == MANAGED_BOOT_COMMAND:
            managed_indexes.append(index)
        else:
            conflicting_commands.append(match.group(1))
    if conflicting_commands:
        raise InstallError(f"refusing to alter changed [boot] command: {conflicting_commands[0]}")
    if len(managed_indexes) > 1:
        raise InstallError("/etc/wsl.conf contains duplicate managed boot commands")
    if managed_indexes:
        del lines[managed_indexes[0]]

    if boot_section_created:
        bounds = section_bounds(lines, "boot")
        if bounds is not None:
            start, end = bounds
            if all(not line.strip() or line.lstrip().startswith("#") for line in lines[start + 1 : end]):
                del lines[start:end]
                while lines and not lines[-1].strip():
                    lines.pop()
    return "\n".join(lines) + ("\n" if lines else "")


def config_content(active: bool) -> bytes:
    return (
        "# Managed by workBenches wsl-relay-watchdog.\n"
        f"ACTIVE={'true' if active else 'false'}\n"
        "MIN_AGE_SECONDS=300\n"
        "CONFIRMATIONS=3\n"
        "INTERVAL_SECONDS=30\n"
        "BATCH_LIMIT=32\n"
        "TERM_GRACE_SECONDS=3\n"
        "LOG_MAX_BYTES=1048576\n"
        "LOG_BACKUPS=3\n"
    ).encode("utf-8")


def command_wrapper() -> bytes:
    return (
        "#!/bin/sh\n"
        "set -eu\n"
        f"exec /usr/bin/python3 {ENGINE_PATH} \"$@\"\n"
    ).encode("utf-8")


def boot_wrapper() -> bytes:
    return (
        "#!/bin/sh\n"
        "set -eu\n"
        "umask 027\n"
        f"/usr/bin/setsid --fork {COMMAND_PATH} daemon </dev/null >/dev/null 2>&1\n"
        "exit 0\n"
    ).encode("utf-8")


def read_start_time_ticks(pid: int, proc_root: Path = Path("/proc")) -> int | None:
    try:
        raw_stat = (proc_root / str(pid) / "stat").read_text(encoding="utf-8")
        close_paren = raw_stat.rfind(")")
        fields = raw_stat[close_paren + 1 :].strip().split()
        return int(fields[19])
    except (FileNotFoundError, PermissionError, OSError, ValueError, IndexError):
        return None


def verified_watchdog(identity: dict[str, object], proc_root: Path = Path("/proc")) -> bool:
    try:
        pid = int(identity["pid"])
        expected_start = int(identity["start_time_ticks"])
    except (KeyError, TypeError, ValueError):
        return False
    if read_start_time_ticks(pid, proc_root) != expected_start:
        return False
    try:
        command_line = (proc_root / str(pid) / "cmdline").read_bytes().split(b"\0")
    except (FileNotFoundError, PermissionError, OSError):
        return False
    decoded = [part.decode("utf-8", errors="replace") for part in command_line if part]
    return ENGINE_PATH in decoded and "daemon" in decoded


def watchdog_lock_is_held(root: Path) -> bool:
    lock_path = rooted(root, f"{RUN_DIR}/watchdog.lock")
    if not lock_path.exists():
        return False
    with lock_path.open("a+", encoding="utf-8") as lock_file:
        try:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    return False


def stop_watchdog(root: Path, timeout_seconds: float = 5.0) -> None:
    pid_path = rooted(root, f"{RUN_DIR}/watchdog.pid.json")
    if not pid_path.exists():
        if watchdog_lock_is_held(root):
            raise InstallError("watchdog lock is held but its identity file is missing")
        return
    try:
        identity = json.loads(pid_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InstallError(f"cannot read watchdog identity: {error}") from error
    pid = int(identity["pid"])
    current_start = read_start_time_ticks(pid)
    if current_start is None:
        if watchdog_lock_is_held(root):
            raise InstallError("watchdog lock is held but its recorded identity is stale")
        pid_path.unlink()
        return
    if root != Path("/"):
        return
    if not verified_watchdog(identity):
        raise InstallError("refusing to stop an unverified watchdog identity")
    try:
        pidfd = os.pidfd_open(pid)
    except (ProcessLookupError, PermissionError, OSError) as error:
        raise InstallError(f"cannot open watchdog pidfd: {type(error).__name__}") from error
    try:
        if not verified_watchdog(identity):
            raise InstallError("watchdog identity changed before stop")
        signal.pidfd_send_signal(pidfd, signal.SIGTERM, None, 0)
        deadline = time.monotonic() + timeout_seconds
        while time.monotonic() < deadline:
            if not verified_watchdog(identity) and not watchdog_lock_is_held(root):
                return
            time.sleep(0.1)
        if verified_watchdog(identity):
            try:
                signal.pidfd_send_signal(pidfd, signal.SIGKILL, None, 0)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + timeout_seconds
        while time.monotonic() < deadline:
            if not verified_watchdog(identity) and not watchdog_lock_is_held(root):
                return
            time.sleep(0.1)
        raise InstallError("watchdog did not release its singleton lock after termination")
    finally:
        os.close(pidfd)


def clear_runtime_status(root: Path) -> None:
    status_path = rooted(root, f"{RUN_DIR}/status.json")
    try:
        status_path.unlink()
    except FileNotFoundError:
        pass


def start_watchdog(root: Path, timeout_seconds: float = 10.0) -> dict[str, object] | None:
    if root != Path("/"):
        return None
    pid_path = rooted(root, f"{RUN_DIR}/watchdog.pid.json")
    status_path = rooted(root, f"{RUN_DIR}/status.json")
    clear_runtime_status(root)
    subprocess.run([BOOT_PATH], check=True)
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if pid_path.exists() and status_path.exists():
            try:
                identity = json.loads(pid_path.read_text(encoding="utf-8"))
                status = json.loads(status_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                time.sleep(0.1)
                continue
            if verified_watchdog(identity):
                return status
        time.sleep(0.1)
    raise InstallError("watchdog did not publish a verified running identity within 10 seconds")


def source_digest(source_path: Path) -> str:
    return hashlib.sha256(source_path.read_bytes()).hexdigest()


def content_digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def install(root: Path, source_path: Path, active: bool, start: bool) -> dict[str, object]:
    if root == Path("/") and os.geteuid() != 0:
        raise InstallError("installation into / requires root")
    if not source_path.is_file():
        raise InstallError(f"watchdog engine source is missing: {source_path}")
    if root == Path("/"):
        for prerequisite in ("/usr/bin/python3", "/usr/bin/setsid"):
            if not Path(prerequisite).is_file():
                raise InstallError(f"required executable is missing: {prerequisite}")

    managed_paths = [ENGINE_PATH, COMMAND_PATH, BOOT_PATH, CONFIG_PATH, WSL_CONFIG_PATH, STATE_PATH]
    for managed_path in managed_paths:
        ensure_regular_or_absent(rooted(root, managed_path))

    state_path = rooted(root, STATE_PATH)
    previous_state: dict[str, object] | None = None
    if state_path.exists():
        try:
            previous_state = json.loads(state_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise InstallError(f"cannot read existing install state: {error}") from error

    source_content = source_path.read_bytes()
    desired_content = {
        ENGINE_PATH: source_content,
        COMMAND_PATH: command_wrapper(),
        BOOT_PATH: boot_wrapper(),
        CONFIG_PATH: config_content(active),
    }
    if previous_state is None:
        for managed_path in desired_content:
            existing_path = rooted(root, managed_path)
            if existing_path.exists():
                raise InstallError(f"refusing unmanaged existing file: {existing_path}")
    else:
        recorded_digests = previous_state.get("managed_path_sha256", {})
        if not isinstance(recorded_digests, dict):
            raise InstallError("existing install state has invalid managed path digests")
        legacy_digests = {
            ENGINE_PATH: previous_state.get("engine_sha256"),
            COMMAND_PATH: content_digest(command_wrapper()),
            BOOT_PATH: content_digest(boot_wrapper()),
            CONFIG_PATH: content_digest(config_content(bool(previous_state.get("active", False)))),
        }
        for managed_path in desired_content:
            existing_path = rooted(root, managed_path)
            if not existing_path.exists():
                continue
            expected_digest = recorded_digests.get(managed_path, legacy_digests.get(managed_path))
            if not isinstance(expected_digest, str) or source_digest(existing_path) != expected_digest:
                raise InstallError(f"refusing modified managed file: {existing_path}")

    wsl_config_path = rooted(root, WSL_CONFIG_PATH)
    wsl_config_existed = wsl_config_path.exists()
    original_wsl_config = wsl_config_path.read_text(encoding="utf-8") if wsl_config_existed else ""
    updated_wsl_config, boot_section_created = install_boot_command(original_wsl_config)

    state_dir = rooted(root, STATE_DIR)
    backup_dir = state_dir / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_path: str | None = None
    if previous_state is not None:
        backup_path = previous_state.get("initial_wsl_config_backup")  # type: ignore[assignment]
        boot_section_created = bool(previous_state.get("boot_section_created", boot_section_created))
        wsl_config_existed = bool(previous_state.get("wsl_config_existed", True))
    else:
        timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        backup = backup_dir / f"wsl.conf.{timestamp}.bak"
        atomic_write(backup, original_wsl_config.encode("utf-8"), 0o600)
        backup_path = str(backup)

    for directory, mode in ((state_dir, 0o750), (rooted(root, RUN_DIR), 0o755), (rooted(root, LOG_DIR), 0o750)):
        directory.mkdir(parents=True, exist_ok=True)
        os.chmod(directory, mode)
        if os.geteuid() == 0:
            os.chown(directory, 0, 0)

    if start:
        stop_watchdog(root)
    atomic_write(rooted(root, ENGINE_PATH), desired_content[ENGINE_PATH], 0o755)
    atomic_write(rooted(root, COMMAND_PATH), desired_content[COMMAND_PATH], 0o755)
    atomic_write(rooted(root, BOOT_PATH), desired_content[BOOT_PATH], 0o755)
    atomic_write(rooted(root, CONFIG_PATH), desired_content[CONFIG_PATH], 0o644)
    atomic_write(wsl_config_path, updated_wsl_config.encode("utf-8"), 0o644)

    state: dict[str, object] = {
        "version": 1,
        "installed_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "active": active,
        "engine_sha256": source_digest(source_path),
        "managed_path_sha256": {
            managed_path: content_digest(content)
            for managed_path, content in desired_content.items()
        },
        "initial_wsl_config_backup": backup_path,
        "wsl_config_existed": wsl_config_existed,
        "boot_section_created": boot_section_created,
        "managed_boot_command": MANAGED_BOOT_COMMAND,
    }
    atomic_write(state_path, (json.dumps(state, indent=2, sort_keys=True) + "\n").encode("utf-8"), 0o600)
    status = start_watchdog(root) if start else None
    return {"installed": True, "active": active, "status": status, "state": state}


def uninstall(root: Path) -> dict[str, object]:
    if root == Path("/") and os.geteuid() != 0:
        raise InstallError("uninstallation from / requires root")
    state_path = rooted(root, STATE_PATH)
    if not state_path.exists():
        raise InstallError("watchdog install state is absent; refusing unmanaged removal")
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InstallError(f"cannot read install state: {error}") from error

    recorded_digests = state.get("managed_path_sha256", {})
    if not isinstance(recorded_digests, dict):
        raise InstallError("install state has invalid managed path digests")
    legacy_digests = {
        ENGINE_PATH: state.get("engine_sha256"),
        COMMAND_PATH: content_digest(command_wrapper()),
        BOOT_PATH: content_digest(boot_wrapper()),
        CONFIG_PATH: content_digest(config_content(bool(state.get("active", False)))),
    }
    for managed_path in (ENGINE_PATH, COMMAND_PATH, BOOT_PATH, CONFIG_PATH):
        target = rooted(root, managed_path)
        ensure_regular_or_absent(target)
        if not target.exists():
            continue
        expected_digest = recorded_digests.get(managed_path, legacy_digests.get(managed_path))
        if not isinstance(expected_digest, str) or source_digest(target) != expected_digest:
            raise InstallError(f"refusing removal of modified managed file: {target}")

    stop_watchdog(root)
    wsl_config_path = rooted(root, WSL_CONFIG_PATH)
    current_wsl_config = wsl_config_path.read_text(encoding="utf-8") if wsl_config_path.exists() else ""
    updated_wsl_config = uninstall_boot_command(
        current_wsl_config,
        boot_section_created=bool(state.get("boot_section_created", False)),
    )
    if not bool(state.get("wsl_config_existed", True)) and not updated_wsl_config:
        try:
            wsl_config_path.unlink()
        except FileNotFoundError:
            pass
    else:
        atomic_write(wsl_config_path, updated_wsl_config.encode("utf-8"), 0o644)

    for managed_path in (ENGINE_PATH, COMMAND_PATH, BOOT_PATH, CONFIG_PATH):
        target = rooted(root, managed_path)
        try:
            target.unlink()
        except FileNotFoundError:
            pass
    try:
        state_path.unlink()
    except FileNotFoundError:
        pass
    return {"uninstalled": True, "logs_retained": str(rooted(root, LOG_DIR))}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Install or remove the strict WSL relay watchdog")
    parser.add_argument("--root", type=Path, default=Path("/"), help=argparse.SUPPRESS)
    parser.add_argument(
        "--source",
        type=Path,
        default=Path(__file__).with_name("wsl_relay_watchdog.py"),
        help=argparse.SUPPRESS,
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    install_parser = subparsers.add_parser("install")
    mode_group = install_parser.add_mutually_exclusive_group(required=True)
    mode_group.add_argument("--active", action="store_true")
    mode_group.add_argument("--inactive", action="store_true")
    install_parser.add_argument("--no-start", action="store_true", help=argparse.SUPPRESS)
    subparsers.add_parser("uninstall")
    return parser


def main(argv: list[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    root = arguments.root.resolve()
    try:
        if arguments.command == "install":
            if arguments.no_start and root == Path("/"):
                raise InstallError("--no-start is limited to test roots")
            result = install(root, arguments.source.resolve(), arguments.active, not arguments.no_start)
        else:
            result = uninstall(root)
        json.dump(result, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0
    except (InstallError, OSError, subprocess.SubprocessError) as error:
        print(f"install-wsl-relay-watchdog: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
