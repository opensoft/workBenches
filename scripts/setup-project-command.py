#!/usr/bin/env python3
"""Install the commit-pinned openRepoProject executable. Apache-2.0."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCK_NAME = ".workbenches-project.lock"


def validate_target(path):
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError(f"Refusing non-regular target: {path}")
    if path.exists() and (not os.access(path, os.W_OK) or not path.stat().st_mode & 0o222):
        raise ValueError(f"Refusing read-only target: {path}")


def fetch(pin):
    resource = f"repos/{pin['repository']}/contents/project?ref={pin['commit']}"
    if shutil.which("gh"):
        try:
            result = subprocess.run(["gh", "api", resource, "-H", "Accept: application/vnd.github.raw"],
                                    capture_output=True, timeout=20)
            if result.returncode == 0:
                return result.stdout
        except (OSError, subprocess.TimeoutExpired):
            pass
    url = f"https://raw.githubusercontent.com/{pin['repository']}/{pin['commit']}/project"
    with urllib.request.urlopen(url, timeout=15) as response:
        return response.read(2 * 1024 * 1024)


def stage(directory, data, mode):
    descriptor, name = tempfile.mkstemp(prefix=".project-install-", dir=directory)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
        os.chmod(name, mode)
    except BaseException:
        Path(name).unlink(missing_ok=True)
        raise
    return Path(name)


def file_sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def owned_target_data(target, owner_marker, repository):
    if (not target.is_file() or target.is_symlink()
            or not owner_marker.is_file() or owner_marker.is_symlink()):
        return None
    try:
        owner = json.loads(owner_marker.read_text())
    except (OSError, ValueError, TypeError):
        return None
    if (not isinstance(owner, dict)
            or owner.get("schema_version") != 1
            or owner.get("repository") != repository
            or re.fullmatch(r"[0-9a-f]{40}", owner.get("commit", "")) is None
            or re.fullmatch(r"[0-9a-f]{64}", owner.get("sha256", "")) is None):
        return None
    allowed_digests = {owner["sha256"]}
    if owner.get("state") == "pending":
        previous_owned = owner.get("previous_owned")
        if not isinstance(previous_owned, bool):
            return None
        previous_digest = owner.get("previous_sha256", "")
        if previous_digest and re.fullmatch(r"[0-9a-f]{64}", previous_digest) is None:
            return None
        if previous_owned:
            if not previous_digest:
                return None
            allowed_digests.add(previous_digest)
        elif previous_digest:
            return None
    elif owner.get("state") not in (None, "owned"):
        return None
    data = target.read_bytes()
    return data if hashlib.sha256(data).hexdigest() in allowed_digests else None


def owned_target(target, owner_marker, repository):
    return owned_target_data(target, owner_marker, repository) is not None


def path_fingerprint(path):
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return ("missing",)
    if not stat.S_ISREG(metadata.st_mode):
        return ("other", metadata.st_dev, metadata.st_ino, metadata.st_mode)
    return ("file", metadata.st_dev, metadata.st_ino, metadata.st_mode,
            hashlib.sha256(path.read_bytes()).hexdigest())


def acquire_project_lock(directory, exclusive):
    lock_path = directory / LOCK_NAME
    flags = os.O_RDONLY
    if exclusive:
        flags = os.O_RDWR | os.O_CREAT
    flags |= getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(lock_path, flags, 0o644)
    if not stat.S_ISREG(os.fstat(descriptor).st_mode):
        os.close(descriptor)
        raise ValueError(f"Refusing non-regular project lock: {lock_path}")
    if exclusive:
        os.fchmod(descriptor, 0o644)
    fcntl.flock(descriptor, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
    return descriptor


def execute_project(data, target, command_args):
    code = compile(data, str(target), "exec")
    original_argv = sys.argv
    original_path0 = sys.path[0]
    sys.argv = [str(target), *command_args]
    sys.path[0] = str(target.parent)
    namespace = {
        "__name__": "__main__",
        "__file__": str(target),
        "__package__": None,
        "__cached__": None,
    }
    try:
        exec(code, namespace)
    finally:
        sys.argv = original_argv
        sys.path[0] = original_path0
    return 0


def replace_transaction(replacements, staged):
    """Replace related files and roll back any completed step on failure."""
    backups = {}
    replaced = []
    for destination, _source in replacements:
        if destination in backups:
            continue
        if destination.is_file():
            backup = stage(destination.parent, destination.read_bytes(),
                           destination.stat().st_mode & 0o777)
            staged.append(backup)
            backups[destination] = backup
        else:
            backups[destination] = None
    try:
        for destination, source in replacements:
            os.replace(source, destination)
            replaced.append(destination)
    except OSError:
        for destination in reversed(replaced):
            backup = backups[destination]
            if backup is None:
                destination.unlink(missing_ok=True)
            else:
                os.replace(backup, destination)
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Offline source executable; must match the pin")
    parser.add_argument("--bin-dir", type=Path, default=Path(os.environ.get("OPENREPOPROJECT_BIN_DIR", str(Path.home() / ".local/bin"))))
    parser.add_argument("--pin", type=Path, default=Path(os.environ.get(
        "OPENREPOPROJECT_PIN", ROOT / "config/openrepoproject-pin.json")))
    parser.add_argument("--workbenches", type=Path, default=ROOT)
    parser.add_argument("--replace-existing", action="store_true",
                        help="replace a non-workBenches project command after explicit approval")
    operation = parser.add_mutually_exclusive_group()
    operation.add_argument("--remove", action="store_true",
                        help="remove only a project command owned by this installer")
    operation.add_argument("--resolve-owned", action="store_true",
                           help="print the command path only when installer ownership verifies")
    operation.add_argument("--exec-owned", action="store_true",
                           help="verify and execute the owned command while holding a shared lock")
    parser.add_argument("command_args", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if (os.environ.get("WORKBENCHES_SKIP_PROJECT_COMMAND") == "1"
            and not args.resolve_owned and not args.exec_owned and not args.remove):
        print("project installation skipped by WORKBENCHES_SKIP_PROJECT_COMMAND=1")
        return 0
    staged = []
    lock_descriptor = None
    try:
        pin = json.loads(args.pin.read_text())
        if (not isinstance(pin, dict) or pin.get("schema_version") != 1
                or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", pin.get("repository", ""))
                or not re.fullmatch(r"[0-9a-f]{40}", pin.get("commit", ""))
                or not re.fullmatch(r"[0-9a-f]{64}", pin.get("sha256", ""))):
            raise ValueError("Invalid openRepoProject pin")
        directory = args.bin_dir.expanduser()
        target, marker = directory / "project", directory / ".workbenches-path"
        owner_marker = directory / ".workbenches-project.json"
        lock_path = directory / LOCK_NAME
        read_operation = args.resolve_owned or args.exec_owned
        if read_operation and not lock_path.is_file():
            print(f"project: refused unlocked command at {target}", file=sys.stderr)
            return 3
        if not read_operation:
            if directory.exists() and (not directory.is_dir() or not os.access(directory, os.W_OK)):
                raise ValueError(f"Unwritable install directory: {directory}")
            directory.mkdir(parents=True, exist_ok=True)
        lock_descriptor = acquire_project_lock(directory, exclusive=not read_operation)
        if args.resolve_owned:
            if owned_target(target, owner_marker, pin["repository"]):
                print(target)
                return 0
            print(f"project: refused unowned command at {target}", file=sys.stderr)
            return 3
        if args.exec_owned:
            data = owned_target_data(target, owner_marker, pin["repository"])
            if data is None:
                print(f"project: refused unowned command at {target}", file=sys.stderr)
                return 3
            command_args = args.command_args[1:] if args.command_args[:1] == ["--"] else args.command_args
            return execute_project(data, target, command_args)
        validate_target(target)
        validate_target(marker)
        validate_target(owner_marker)
        if args.remove:
            if owned_target(target, owner_marker, pin["repository"]):
                removal_state = (path_fingerprint(target), path_fingerprint(owner_marker))
                if (not owned_target(target, owner_marker, pin["repository"])
                        or removal_state != (path_fingerprint(target), path_fingerprint(owner_marker))):
                    raise ValueError("Project command changed during removal; nothing removed")
                target.unlink()
                owner_marker.unlink()
                print(f"project: removed installer-owned command from {target}")
                return 0
            print(f"project: preserved unowned command at {target}", file=sys.stderr)
            return 3
        wb = args.workbenches.expanduser().resolve()
        if not (wb / "config/bench-config.json").is_file():
            raise ValueError(f"Not a workBenches checkout: {wb}")
        initial_install_state = (path_fingerprint(target), path_fingerprint(owner_marker))
        target_digest = file_sha256(target) if target.is_file() and not target.is_symlink() else ""
        target_owned = owned_target(target, owner_marker, pin["repository"])
        if target_digest and not target_owned and not args.replace_existing:
            raise ValueError(
                f"Refusing to replace unowned project command: {target}; "
                "use --replace-existing after reviewing it"
            )
        if args.source:
            data = args.source.expanduser().read_bytes()
        elif target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == pin["sha256"]:
            data = target.read_bytes()
        else:
            data = fetch(pin)
        if hashlib.sha256(data).hexdigest() != pin["sha256"]:
            raise ValueError("Downloaded/local project does not match the pinned SHA-256; nothing installed")
        if not data.startswith(b"#!/usr/bin/env python3\n"):
            raise ValueError("Pinned artifact is not a Python project executable")
        compile(data, "project", "exec")
        marker_data = (str(wb) + "\n").encode()
        owner_data = (json.dumps({
            "schema_version": 1,
            "state": "owned",
            "repository": pin["repository"],
            "commit": pin["commit"],
            "sha256": pin["sha256"],
        }, sort_keys=True) + "\n").encode()
        pending_owner_data = (json.dumps({
            "schema_version": 1,
            "state": "pending",
            "repository": pin["repository"],
            "commit": pin["commit"],
            "sha256": pin["sha256"],
            "previous_owned": target_owned,
            "previous_sha256": target_digest if target_owned else "",
        }, sort_keys=True) + "\n").encode()
        unchanged = target.is_file() and target.read_bytes() == data and target.stat().st_mode & 0o777 == 0o755
        marker_same = marker.is_file() and marker.read_bytes() == marker_data
        owner_same = owner_marker.is_file() and owner_marker.read_bytes() == owner_data
        if not unchanged or not marker_same or not owner_same:
            directory.mkdir(parents=True, exist_ok=True)
            command_stage = stage(directory, data, 0o755)
            staged.append(command_stage)
            marker_stage = stage(directory, marker_data, 0o644)
            staged.append(marker_stage)
            owner_stage = stage(directory, owner_data, 0o644)
            staged.append(owner_stage)
            pending_owner_stage = stage(directory, pending_owner_data, 0o644)
            staged.append(pending_owner_stage)
            validate_target(target)
            validate_target(marker)
            validate_target(owner_marker)
            if initial_install_state != (path_fingerprint(target), path_fingerprint(owner_marker)):
                raise ValueError("Project command changed during installation; nothing replaced")
            replace_transaction((
                (owner_marker, pending_owner_stage),
                (target, command_stage),
                (marker, marker_stage),
                (owner_marker, owner_stage),
            ), staged)
        print(f"project: {'already installed' if unchanged and marker_same else 'installed'} at {target}")
        print(f"Source: {pin['repository']} @ {pin['commit']}")
        if str(directory.resolve()) not in os.environ.get("PATH", "").split(os.pathsep):
            print(f"Add {directory} to PATH to run project from anywhere.")
        return 0
    except (OSError, ValueError, TypeError, SyntaxError, urllib.error.URLError) as exc:
        print(f"project install refused: {exc}", file=sys.stderr)
        return 2
    finally:
        for path in staged:
            path.unlink(missing_ok=True)
        if lock_descriptor is not None:
            os.close(lock_descriptor)


if __name__ == "__main__":
    sys.exit(main())
