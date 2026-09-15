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
PAYLOAD_NAME = ".workbenches-project.payload"


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


def owned_target_data(target, payload, owner_marker, pin, expected_launcher_digests):
    if (not target.is_file() or target.is_symlink()
            or not payload.is_file() or payload.is_symlink()
            or not owner_marker.is_file() or owner_marker.is_symlink()):
        return None
    try:
        owner = json.loads(owner_marker.read_text())
    except (OSError, ValueError, TypeError):
        return None
    if (not isinstance(owner, dict)
            or owner.get("schema_version") != 1
            or owner.get("repository") != pin["repository"]):
        return None
    trusted_artifacts = {(pin["commit"], pin["sha256"])}
    trusted_artifacts.update(
        (item["commit"], item["sha256"])
        for item in pin.get("trusted_previous", [])
    )
    owner_artifact = (owner.get("commit", ""), owner.get("sha256", ""))
    allowed_digests = set()
    allowed_launcher_digests = set()
    if owner.get("state") == "pending":
        if owner_artifact != (pin["commit"], pin["sha256"]):
            return None
        allowed_digests.add(pin["sha256"])
        launcher_digest = owner.get("launcher_sha256", "")
        if re.fullmatch(r"[0-9a-f]{64}", launcher_digest) is None:
            return None
        allowed_launcher_digests.add(launcher_digest)
        previous_owned = owner.get("previous_owned")
        if not isinstance(previous_owned, bool):
            return None
        previous_commit = owner.get("previous_commit", "")
        previous_digest = owner.get("previous_sha256", "")
        previous_launcher_digest = owner.get("previous_launcher_sha256", "")
        if previous_owned:
            if ((previous_commit, previous_digest) not in trusted_artifacts
                    or re.fullmatch(r"[0-9a-f]{64}", previous_launcher_digest) is None):
                return None
            allowed_digests.add(previous_digest)
            allowed_launcher_digests.add(previous_launcher_digest)
        elif previous_commit or previous_digest or previous_launcher_digest:
            return None
    elif owner.get("state") in (None, "owned"):
        if owner_artifact not in trusted_artifacts:
            return None
        launcher_digest = owner.get("launcher_sha256", "")
        if re.fullmatch(r"[0-9a-f]{64}", launcher_digest) is None:
            return None
        allowed_digests.add(owner["sha256"])
        allowed_launcher_digests.add(launcher_digest)
    else:
        return None
    actual_launcher_digest = file_sha256(target)
    if (actual_launcher_digest not in expected_launcher_digests
            or actual_launcher_digest not in allowed_launcher_digests):
        return None
    data = payload.read_bytes()
    return data if hashlib.sha256(data).hexdigest() in allowed_digests else None


def owned_target(target, payload, owner_marker, pin, expected_launcher_digests):
    return owned_target_data(target, payload, owner_marker, pin,
                             expected_launcher_digests) is not None


def launcher_bytes(pin):
    """Build a checkout-independent PATH entry that verifies the pinned payload."""
    return (
        "#!/usr/bin/env python3\n"
        "import fcntl\n"
        "import hashlib\n"
        "import json\n"
        "import os\n"
        "from pathlib import Path\n"
        "import stat\n"
        "import sys\n"
        "import tempfile\n"
        f"EXPECTED_REPOSITORY = {pin['repository']!r}\n"
        f"EXPECTED_COMMIT = {pin['commit']!r}\n"
        f"EXPECTED_SHA256 = {pin['sha256']!r}\n"
        f"LOCK_NAME = {LOCK_NAME!r}\n"
        f"PAYLOAD_NAME = {PAYLOAD_NAME!r}\n"
        "\n"
        "def refuse(message):\n"
        "    print(f'project: {message}', file=sys.stderr)\n"
        "    raise SystemExit(3)\n"
        "\n"
        "def read_regular(path, limit):\n"
        "    flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0)\n"
        "    descriptor = os.open(path, flags)\n"
        "    try:\n"
        "        metadata = os.fstat(descriptor)\n"
        "        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > limit:\n"
        "            raise ValueError(f'non-regular or oversized file at {path}')\n"
        "        with os.fdopen(descriptor, 'rb', closefd=False) as stream:\n"
        "            return stream.read(limit + 1)\n"
        "    finally:\n"
        "        os.close(descriptor)\n"
        "\n"
        "directory = Path(__file__).resolve().parent\n"
        "lock_path = directory / LOCK_NAME\n"
        "try:\n"
        "    lock_descriptor = os.open(lock_path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))\n"
        "    if not stat.S_ISREG(os.fstat(lock_descriptor).st_mode):\n"
        "        refuse(f'refused non-regular lock at {lock_path}')\n"
        "    fcntl.flock(lock_descriptor, fcntl.LOCK_SH)\n"
        "    owner = json.loads(read_regular(directory / '.workbenches-project.json', 65536))\n"
        "    if (not isinstance(owner, dict)\n"
        "            or owner.get('schema_version') != 1\n"
        "            or owner.get('state') not in ('owned', 'pending')\n"
        "            or owner.get('repository') != EXPECTED_REPOSITORY\n"
        "            or owner.get('commit') != EXPECTED_COMMIT\n"
        "            or owner.get('sha256') != EXPECTED_SHA256):\n"
        "        refuse('refused unowned payload')\n"
        "    launcher = read_regular(Path(__file__), 2 * 1024 * 1024)\n"
        "    if hashlib.sha256(launcher).hexdigest() != owner.get('launcher_sha256'):\n"
        "        refuse('refused a tampered launcher')\n"
        "    data = read_regular(directory / PAYLOAD_NAME, 2 * 1024 * 1024)\n"
        "    if hashlib.sha256(data).hexdigest() != EXPECTED_SHA256:\n"
        "        refuse('refused payload with a mismatched digest')\n"
        "except (OSError, ValueError, TypeError, json.JSONDecodeError):\n"
        "    refuse('refused unreadable ownership state')\n"
        "finally:\n"
        "    if 'lock_descriptor' in locals():\n"
        "        os.close(lock_descriptor)\n"
        "\n"
        "if 'WORKBENCHES_ROOT' not in os.environ:\n"
        "    try:\n"
        "        marker = read_regular(directory / '.workbenches-path', 65536).decode().strip()\n"
        "        if marker:\n"
        "            os.environ['WORKBENCHES_ROOT'] = marker\n"
        "    except (OSError, UnicodeDecodeError, ValueError):\n"
        "        pass\n"
        "\n"
        "target = directory / 'project'\n"
        "code = compile(data, str(target), 'exec')\n"
        "command_args = sys.argv[1:]\n"
        "if Path(sys.argv[0]).name == 'onp':\n"
        "    command_args = ['new', *command_args]\n"
        "sys.argv = [str(target), *command_args]\n"
        "sys.path[0] = str(directory)\n"
        "with tempfile.TemporaryDirectory(prefix='workbenches-project-exec-') as snapshot_dir:\n"
        "    snapshot = Path(snapshot_dir) / 'project'\n"
        "    snapshot.write_bytes(data)\n"
        "    snapshot.chmod(0o400)\n"
        "    namespace = {'__name__': '__main__', '__file__': str(snapshot), "
        "'__package__': None, '__cached__': None}\n"
        "    exec(code, namespace)\n"
    ).encode()


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
    try:
        # The verified target path can be replaced by another process after it
        # is read. Keep __file__ on a private copy so code such as --version
        # cannot reopen and report bytes that were never ownership-checked.
        with tempfile.TemporaryDirectory(prefix="workbenches-project-exec-") as snapshot_dir:
            snapshot = Path(snapshot_dir) / "project"
            snapshot.write_bytes(data)
            snapshot.chmod(0o400)
            namespace = {
                "__name__": "__main__",
                "__file__": str(snapshot),
                "__package__": None,
                "__cached__": None,
            }
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
    parser.add_argument("--workbenches", type=Path, default=Path(os.environ.get(
        "WORKBENCHES_ROOT", ROOT)))
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
        trusted_previous = pin.get("trusted_previous", []) if isinstance(pin, dict) else None
        if (not isinstance(pin, dict) or pin.get("schema_version") != 1
                or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", pin.get("repository", ""))
                or not re.fullmatch(r"[0-9a-f]{40}", pin.get("commit", ""))
                or not re.fullmatch(r"[0-9a-f]{64}", pin.get("sha256", ""))
                or not isinstance(trusted_previous, list)
                or any(not isinstance(item, dict)
                       or re.fullmatch(r"[0-9a-f]{40}", item.get("commit", "")) is None
                       or re.fullmatch(r"[0-9a-f]{64}", item.get("sha256", "")) is None
                       for item in trusted_previous)):
            raise ValueError("Invalid openRepoProject pin")
        directory = args.bin_dir.expanduser()
        target, payload = directory / "project", directory / PAYLOAD_NAME
        marker = directory / ".workbenches-path"
        owner_marker = directory / ".workbenches-project.json"
        lock_path = directory / LOCK_NAME
        wb = args.workbenches.expanduser().resolve()
        launcher_data = launcher_bytes(pin)
        launcher_digest = hashlib.sha256(launcher_data).hexdigest()
        expected_launcher_digests = {launcher_digest}
        expected_launcher_digests.update(
            hashlib.sha256(launcher_bytes({
                "repository": pin["repository"],
                "commit": item["commit"],
                "sha256": item["sha256"],
            })).hexdigest()
            for item in trusted_previous
        )
        read_operation = args.resolve_owned or args.exec_owned
        if args.remove and not directory.exists():
            print(f"project: no install directory at {directory}", file=sys.stderr)
            return 3
        if args.remove and not target.exists() and not owner_marker.exists():
            print(f"project: no installer-owned command at {target}", file=sys.stderr)
            return 3
        if read_operation and not lock_path.is_file():
            print(f"project: refused unlocked command at {target}", file=sys.stderr)
            return 3
        if not read_operation:
            if directory.exists() and (not directory.is_dir() or not os.access(directory, os.W_OK)):
                raise ValueError(f"Unwritable install directory: {directory}")
            directory.mkdir(parents=True, exist_ok=True)
        lock_descriptor = acquire_project_lock(directory, exclusive=not read_operation)
        if args.resolve_owned:
            if owned_target(target, payload, owner_marker, pin,
                            expected_launcher_digests):
                print(target)
                return 0
            print(f"project: refused unowned command at {target}", file=sys.stderr)
            return 3
        if args.exec_owned:
            data = owned_target_data(target, payload, owner_marker, pin,
                                     expected_launcher_digests)
            if data is None:
                print(f"project: refused unowned command at {target}", file=sys.stderr)
                return 3
            command_args = args.command_args[1:] if args.command_args[:1] == ["--"] else args.command_args
            os.close(lock_descriptor)
            lock_descriptor = None
            return execute_project(data, target, command_args)
        if args.remove:
            if owned_target(target, payload, owner_marker, pin,
                            expected_launcher_digests):
                removal_state = (path_fingerprint(target), path_fingerprint(payload),
                                 path_fingerprint(owner_marker))
                if (not owned_target(target, payload, owner_marker, pin,
                                     expected_launcher_digests)
                        or removal_state != (path_fingerprint(target), path_fingerprint(payload),
                                             path_fingerprint(owner_marker))):
                    raise ValueError("Project command changed during removal; nothing removed")
                target.unlink()
                payload.unlink()
                owner_marker.unlink()
                print(f"project: removed installer-owned command from {target}")
                return 0
            print(f"project: preserved unowned command at {target}", file=sys.stderr)
            return 3
        if not (wb / "config/bench-config.json").is_file():
            raise ValueError(f"Not a workBenches checkout: {wb}")
        initial_install_state = (path_fingerprint(target), path_fingerprint(payload),
                                 path_fingerprint(owner_marker))
        target_digest = file_sha256(payload) if payload.is_file() and not payload.is_symlink() else ""
        target_owned = owned_target(target, payload, owner_marker, pin,
                                    expected_launcher_digests)
        previous_commit = ""
        previous_launcher_digest = ""
        if target_owned:
            trusted_artifacts = [pin, *pin.get("trusted_previous", [])]
            previous_commit = next(item["commit"] for item in trusted_artifacts
                                   if item["sha256"] == target_digest)
            previous_launcher_digest = file_sha256(target)
        install_artifacts_exist = any(path.exists() or path.is_symlink()
                                      for path in (target, payload, owner_marker))
        if install_artifacts_exist and not target_owned and not args.replace_existing:
            raise ValueError(
                f"Refusing to replace unowned project command: {target}; "
                "use --replace-existing after reviewing it"
            )
        if args.source:
            data = args.source.expanduser().read_bytes()
        elif payload.is_file() and hashlib.sha256(payload.read_bytes()).hexdigest() == pin["sha256"]:
            data = payload.read_bytes()
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
            "launcher_sha256": launcher_digest,
        }, sort_keys=True) + "\n").encode()
        pending_owner_data = (json.dumps({
            "schema_version": 1,
            "state": "pending",
            "repository": pin["repository"],
            "commit": pin["commit"],
            "sha256": pin["sha256"],
            "launcher_sha256": launcher_digest,
            "previous_owned": target_owned,
            "previous_commit": previous_commit,
            "previous_sha256": target_digest if target_owned else "",
            "previous_launcher_sha256": previous_launcher_digest,
        }, sort_keys=True) + "\n").encode()
        unchanged = (target.is_file() and target.read_bytes() == launcher_data
                     and target.stat().st_mode & 0o777 == 0o755
                     and payload.is_file() and payload.read_bytes() == data
                     and payload.stat().st_mode & 0o777 == 0o644)
        marker_same = marker.is_file() and marker.read_bytes() == marker_data
        owner_same = owner_marker.is_file() and owner_marker.read_bytes() == owner_data
        if not unchanged or not marker_same or not owner_same:
            directory.mkdir(parents=True, exist_ok=True)
            command_stage = stage(directory, launcher_data, 0o755)
            staged.append(command_stage)
            payload_stage = stage(directory, data, 0o644)
            staged.append(payload_stage)
            marker_stage = stage(directory, marker_data, 0o644)
            staged.append(marker_stage)
            owner_stage = stage(directory, owner_data, 0o644)
            staged.append(owner_stage)
            pending_owner_stage = stage(directory, pending_owner_data, 0o644)
            staged.append(pending_owner_stage)
            validate_target(target)
            validate_target(payload)
            validate_target(marker)
            validate_target(owner_marker)
            if initial_install_state != (path_fingerprint(target), path_fingerprint(payload),
                                         path_fingerprint(owner_marker)):
                raise ValueError("Project command changed during installation; nothing replaced")
            replace_transaction((
                (owner_marker, pending_owner_stage),
                (payload, payload_stage),
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
