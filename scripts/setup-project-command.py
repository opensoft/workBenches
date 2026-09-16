#!/usr/bin/env python3
"""Install the commit-pinned openRepoProject executable. Apache-2.0."""
import argparse
import ctypes
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
REMOVAL_JOURNAL_NAME = ".workbenches-project.remove.json"


def project_discovery_path():
    configured = os.environ.get(
        "WORKBENCHES_PROJECT_DISCOVERY_FILE",
        str(Path.home() / ".config/workbenches/project-bin"),
    )
    path = Path(configured).expanduser()
    if not path.is_absolute():
        raise ValueError("WORKBENCHES_PROJECT_DISCOVERY_FILE must be absolute")
    return path


def discovery_points_to(path, directory):
    return (path.is_file() and not path.is_symlink()
            and path.read_bytes() == (str(directory.resolve()) + "\n").encode())


def paths_alias(left, right):
    """Recognize lexical, symlink-parent, and existing hard-link aliases."""
    try:
        if left.resolve(strict=False) == right.resolve(strict=False):
            return True
    except (OSError, RuntimeError) as exc:
        raise ValueError(f"Refusing unresolvable path alias check: {left}") from exc
    try:
        return os.path.samefile(left, right)
    except (FileNotFoundError, OSError):
        return False


def require_unique_paths(paths, context):
    paths = list(paths)
    for index, path in enumerate(paths):
        for previous in paths[:index]:
            if paths_alias(path, previous):
                raise ValueError(
                    f"Refusing duplicate {context} destination: {path} aliases {previous}"
                )


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


def recoverable_fresh_pending(target, payload, owner_marker, pin,
                              launcher_digest):
    """Recognize a journal written before any fresh-install payload published."""
    if (target.exists() or target.is_symlink()
            or not owner_marker.is_file() or owner_marker.is_symlink()):
        return False
    if payload.exists() or payload.is_symlink():
        if (not payload.is_file() or payload.is_symlink()
                or hashlib.sha256(payload.read_bytes()).hexdigest() != pin["sha256"]):
            return False
    try:
        owner = json.loads(owner_marker.read_text())
    except (OSError, ValueError, TypeError):
        return False
    return (isinstance(owner, dict)
            and owner.get("schema_version") == 1
            and owner.get("state") == "pending"
            and owner.get("repository") == pin["repository"]
            and owner.get("commit") == pin["commit"]
            and owner.get("sha256") == pin["sha256"]
            and owner.get("launcher_sha256") == launcher_digest
            and owner.get("previous_owned") is False
            and owner.get("previous_commit", "") == ""
            and owner.get("previous_sha256", "") == ""
            and owner.get("previous_launcher_sha256", "") == "")


def launcher_bytes(pin):
    """Build a checkout-independent PATH entry that verifies the pinned payload."""
    return (
        "#!/bin/sh\n"
        "'''exec' python3 -I \"$0\" \"$@\"\n"
        "' '''\n"
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
        "        refuse('refused a launcher that does not match its ownership record')\n"
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
        "with tempfile.TemporaryDirectory(prefix='workbenches-project-exec-') as snapshot_dir:\n"
        "    snapshot = Path(snapshot_dir) / 'project'\n"
        "    snapshot.write_bytes(data)\n"
        "    snapshot.chmod(0o400)\n"
        "    sys.path[0] = str(snapshot.parent)\n"
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


def trusted_launcher(path, expected_digests):
    """Return whether path is a regular executable produced by this installer."""
    return (path.is_file() and not path.is_symlink()
            and path.stat().st_mode & 0o777 == 0o755
            and file_sha256(path) in expected_digests)


def legacy_copied_onp_bytes(workbenches):
    """Exact historical scripts/onp bytes for this workBenches checkout."""
    root = str(workbenches)
    if any(character in root for character in ('"', "\n", "\r")):
        return b""
    return (
        "#!/bin/bash\n\n"
        "# onp (Opensoft New Project) - Command wrapper for workBenches new-project.sh\n"
        "# This script forwards all arguments to the new-project.sh script in the workBenches directory\n\n"
        "# Find the workBenches directory by locating this script's installation source\n"
        f'WORKBENCHES_DIR="{root}"\n\n'
        "# Check if the new-project.sh script exists\n"
        'if [ ! -f "$WORKBENCHES_DIR/scripts/new-project.sh" ]; then\n'
        '    echo "Error: workBenches new-project.sh not found at $WORKBENCHES_DIR/scripts/new-project.sh"\n'
        '    echo "Please ensure workBenches is properly installed."\n'
        "    exit 1\n"
        "fi\n\n"
        "# Execute new-project.sh with all forwarded arguments\n"
        'exec "$WORKBENCHES_DIR/scripts/new-project.sh" "$@"\n'
    ).encode()


def legacy_generated_onp_bytes(workbenches, include_bin_dir_export=True):
    """Exact onp wrapper emitted by either previous global-installer form."""
    root = str(workbenches)
    if any(character in root for character in ('"', "\n", "\r")):
        return b""
    template = r'''#!/bin/bash
# Opensoft New Project - Quick project creation command
# Auto-generated wrapper by workBenches installer

# Get the directory where this wrapper is located
WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

@BIN_DIR_EXPORT@# Try to find workBenches installation
WORKBENCHES_ROOT=""

# Check if we have a stored path
if [ -f "$WRAPPER_DIR/.workbenches-path" ]; then
    WORKBENCHES_ROOT="$(cat "$WRAPPER_DIR/.workbenches-path")"
fi

# Validate the stored path
if [ -z "$WORKBENCHES_ROOT" ] || [ ! -f "$WORKBENCHES_ROOT/scripts/onp" ]; then
    # Try to find workBenches in common locations
    SEARCH_PATHS=(
        "@WORKBENCHES_ROOT@"
        "$HOME/projects/workBenches"
        "$HOME/workBenches"
        "$HOME/Projects/workBenches"
        "$HOME/code/workBenches"
        "$HOME/development/workBenches"
    )
@INDENTED_BLANK@
    for path in "${SEARCH_PATHS[@]}"; do
        if [ -f "$path/scripts/onp" ]; then
            WORKBENCHES_ROOT="$path"
            # Store the found path for next time
            echo "$WORKBENCHES_ROOT" > "$WRAPPER_DIR/.workbenches-path"
            break
        fi
    done
fi

# Execute the actual command
if [ -n "$WORKBENCHES_ROOT" ] && [ -f "$WORKBENCHES_ROOT/scripts/onp" ]; then
    exec "$WORKBENCHES_ROOT/scripts/onp" "$@"
else
    echo "❌ Error: Could not locate workBenches installation"
    echo "Expected to find: workBenches/scripts/onp"
    echo ""
    echo "Please ensure workBenches is properly installed and try:"
    echo "  setup-workbenches --install-commands"
    exit 1
fi
'''
    bin_dir_export = '''# Legacy project creation must resolve the executable from the same directory
# selected by this installer, including /usr/local/bin.
if [ "onp" = "onp" ]; then
    export OPENREPOPROJECT_BIN_DIR="$WRAPPER_DIR"
fi

''' if include_bin_dir_export else ""
    return (template.replace("@WORKBENCHES_ROOT@", root)
            .replace("@BIN_DIR_EXPORT@", bin_dir_export)
            .replace("@INDENTED_BLANK@", "    ").encode())


def trusted_legacy_onp(path, workbenches):
    if (not path.is_file() or path.is_symlink()
            or path.stat().st_mode & 0o777 != 0o755):
        return False
    data = path.read_bytes()
    return bool(data) and data in {
        legacy_copied_onp_bytes(workbenches),
        legacy_generated_onp_bytes(workbenches),
        legacy_generated_onp_bytes(workbenches, include_bin_dir_export=False),
    }


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
    try:
        # The verified target path can be replaced by another process after it
        # is read. Keep __file__ on a private copy so code such as --version
        # cannot reopen and report bytes that were never ownership-checked.
        with tempfile.TemporaryDirectory(prefix="workbenches-project-exec-") as snapshot_dir:
            snapshot = Path(snapshot_dir) / "project"
            snapshot.write_bytes(data)
            snapshot.chmod(0o400)
            sys.path[0] = str(snapshot.parent)
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


def atomic_rename(left, right, linux_flags, mac_flags):
    """Invoke the platform atomic rename primitive with explicit flags."""
    libc = ctypes.CDLL(None, use_errno=True)
    left_bytes = os.fsencode(left)
    right_bytes = os.fsencode(right)
    if sys.platform.startswith("linux"):
        try:
            exchange = libc.renameat2
        except AttributeError as exc:
            raise OSError("renameat2 is unavailable on this Linux system") from exc
        exchange.argtypes = (ctypes.c_int, ctypes.c_char_p,
                             ctypes.c_int, ctypes.c_char_p, ctypes.c_uint)
        exchange.restype = ctypes.c_int
        result = exchange(-100, left_bytes, -100, right_bytes, linux_flags)
    elif sys.platform == "darwin":
        try:
            exchange = libc.renamex_np
        except AttributeError as exc:
            raise OSError("renamex_np is unavailable on this macOS system") from exc
        exchange.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint)
        exchange.restype = ctypes.c_int
        result = exchange(left_bytes, right_bytes, mac_flags)
    else:
        raise OSError("Atomic checked replacement is unsupported on this platform")
    if result != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def atomic_exchange(left, right):
    """Atomically exchange two existing paths on Linux or macOS."""
    atomic_rename(left, right, 2, 2)  # RENAME_EXCHANGE / RENAME_SWAP


def atomic_move_noreplace(source, destination):
    """Atomically move source only when destination does not exist."""
    atomic_rename(source, destination, 1, 4)  # RENAME_NOREPLACE / RENAME_EXCL


def preserve_staged_collision(source):
    """Move unexpected staged bytes to a private diagnostic path."""
    descriptor, name = tempfile.mkstemp(prefix=".project-collision-",
                                        dir=source.parent)
    os.close(descriptor)
    collision = Path(name)
    os.replace(source, collision)
    return collision


def atomic_checked_quarantine(path, expected_state):
    """Move path aside atomically and return it only when identity matches."""
    descriptor, name = tempfile.mkstemp(prefix=".project-remove-", dir=path.parent)
    os.close(descriptor)
    quarantine = Path(name)
    quarantine.unlink()
    atomic_move_noreplace(path, quarantine)
    try:
        if path_fingerprint(quarantine) != expected_state:
            try:
                atomic_move_noreplace(quarantine, path)
            except OSError as exc:
                raise ValueError(
                    f"Refusing concurrent removal at {path}; preserved replacement at {quarantine}"
                ) from exc
            raise ValueError(f"Refusing concurrent removal at {path}")
    except BaseException:
        if quarantine.exists() and not path.exists():
            atomic_move_noreplace(quarantine, path)
        raise
    return quarantine


def atomic_checked_unlink(path, expected_state):
    """Quarantine path atomically and delete only the expected file."""
    quarantine = atomic_checked_quarantine(path, expected_state)
    try:
        quarantine.unlink()
    except BaseException:
        if quarantine.exists() and not path.exists():
            atomic_move_noreplace(quarantine, path)
        raise


def remove_owned_discovery_pointer(discovery, directory, expected_state=None):
    """Best-effort removal of only the pointer owned by this install directory."""
    if not discovery_points_to(discovery, directory):
        return
    current_state = path_fingerprint(discovery)
    if expected_state is not None and current_state != expected_state:
        print(
            "project: removed owned command; preserved changed discovery "
            f"pointer at {discovery}",
            file=sys.stderr,
        )
        return
    if (not discovery_points_to(discovery, directory)
            or current_state != path_fingerprint(discovery)):
        print(
            "project: removed owned command; preserved changed discovery "
            f"pointer at {discovery}",
            file=sys.stderr,
        )
        return
    try:
        atomic_checked_unlink(discovery, current_state)
    except (OSError, ValueError) as exc:
        print(
            "project: removed owned command; preserved discovery "
            f"pointer at {discovery}: {exc}",
            file=sys.stderr,
        )


def fsync_directory(directory):
    descriptor = os.open(directory, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def removal_journal_data(state, entries):
    return (json.dumps({
        "schema_version": 1,
        "state": state,
        "entries": [
            {
                "path": str(path),
                "quarantine": str(quarantine),
                "backup": str(backup),
                "fingerprint": list(expected_state),
            }
            for path, quarantine, backup, expected_state in entries
        ],
    }, sort_keys=True) + "\n").encode()


def write_removal_journal(journal, state, entries, replace=False):
    staged_journal = stage(journal.parent, removal_journal_data(state, entries), 0o600)
    descriptor = os.open(staged_journal, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    try:
        if replace:
            if not journal.is_file() or journal.is_symlink():
                raise ValueError(f"Refusing invalid removal journal: {journal}")
            os.replace(staged_journal, journal)
        else:
            os.link(staged_journal, journal, follow_symlinks=False)
            staged_journal.unlink()
        fsync_directory(journal.parent)
    finally:
        staged_journal.unlink(missing_ok=True)


def read_removal_journal(journal, allowed_paths):
    descriptor = None
    try:
        descriptor = os.open(journal, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 65536:
            raise ValueError(f"Refusing invalid removal journal: {journal}")
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            record = json.loads(stream.read(65537))
    except (OSError, ValueError, TypeError) as exc:
        raise ValueError(f"Refusing unreadable removal journal: {journal}") from exc
    finally:
        if descriptor is not None:
            os.close(descriptor)
    if (not isinstance(record, dict) or record.get("schema_version") != 1
            or record.get("state") not in ("prepared", "committed")
            or not isinstance(record.get("entries"), list)
            or not record["entries"]):
        raise ValueError(f"Refusing malformed removal journal: {journal}")
    allowed = {str(path): path for path in allowed_paths}
    entries = []
    for item in record["entries"]:
        if not isinstance(item, dict) or set(item) != {
                "path", "quarantine", "backup", "fingerprint"}:
            raise ValueError(f"Refusing malformed removal journal: {journal}")
        path = allowed.get(item["path"])
        quarantine = Path(item["quarantine"])
        backup = Path(item["backup"])
        fingerprint = item["fingerprint"]
        if (path is None or quarantine.parent != path.parent
                or backup.parent != path.parent
                or not quarantine.name.startswith(".project-remove-")
                or quarantine.name.startswith(".project-remove-backup-")
                or not backup.name.startswith(".project-remove-backup-")
                or not isinstance(fingerprint, list)
                or not fingerprint or fingerprint[0] != "file"):
            raise ValueError(f"Refusing unauthorized removal journal entry: {journal}")
        entries.append((path, quarantine, backup, tuple(fingerprint)))
    require_unique_paths((entry[0] for entry in entries), "journal")
    require_unique_paths((entry[1] for entry in entries), "journal quarantine")
    require_unique_paths((entry[2] for entry in entries), "journal backup")
    return record["state"], entries


def cleanup_removal_copy(path, expected_state):
    state = path_fingerprint(path)
    if state == ("missing",):
        return
    if not recovery_copy_matches(path, expected_state):
        raise ValueError(f"Refusing changed removal recovery file: {path}")
    path.unlink()


def recovery_copy_matches(path, expected_state):
    """Match copied recovery bytes without requiring the original inode."""
    state = path_fingerprint(path)
    return (state[:1] == ("file",) and expected_state[:1] == ("file",)
            and state[3:] == expected_state[3:])


def recover_removal_journal(journal, allowed_paths):
    """Restore a prepared transaction or finish cleanup of a committed one."""
    if not journal.exists() and not journal.is_symlink():
        return None
    state, entries = read_removal_journal(journal, allowed_paths)
    if state == "prepared":
        changed_targets = []
        for path, quarantine, backup, expected_state in reversed(entries):
            current = path_fingerprint(path)
            if current == expected_state:
                continue
            if current != ("missing",):
                changed_targets.append(path)
                continue
            source = quarantine if recovery_copy_matches(
                quarantine, expected_state) else backup
            if not recovery_copy_matches(source, expected_state):
                raise ValueError(f"Missing authenticated recovery copy for {path}")
            atomic_move_noreplace(source, path)
        for _path, quarantine, backup, expected_state in entries:
            cleanup_removal_copy(quarantine, expected_state)
            cleanup_removal_copy(backup, expected_state)
        result = "restored"
    else:
        for path, _quarantine, _backup, _expected_state in entries:
            if path_fingerprint(path) != ("missing",):
                raise ValueError(f"Committed removal target reappeared: {path}")
        for _path, quarantine, backup, expected_state in entries:
            cleanup_removal_copy(quarantine, expected_state)
            cleanup_removal_copy(backup, expected_state)
        result = "committed"
    journal.unlink()
    fsync_directory(journal.parent)
    if state == "prepared" and changed_targets:
        changed = ", ".join(str(path) for path in changed_targets)
        raise ValueError(f"Preserved changed removal target during recovery: {changed}")
    return result


def reserve_removal_path(directory, prefix):
    descriptor, name = tempfile.mkstemp(prefix=prefix, dir=directory)
    os.close(descriptor)
    path = Path(name)
    path.unlink()
    return path


def create_removal_backup(path, backup, expected_state):
    """Copy verified bytes through no-follow descriptors into a fresh inode."""
    source_descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        metadata = os.fstat(source_descriptor)
        if (not stat.S_ISREG(metadata.st_mode)
                or ("file", metadata.st_dev, metadata.st_ino, metadata.st_mode)
                != expected_state[:4]):
            raise ValueError(f"Removal target changed before backup: {path}")
        chunks = []
        digest = hashlib.sha256()
        while True:
            chunk = os.read(source_descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
            digest.update(chunk)
        if digest.hexdigest() != expected_state[4]:
            raise ValueError(f"Removal target changed during backup: {path}")
    finally:
        os.close(source_descriptor)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    backup_descriptor = None
    try:
        backup_descriptor = os.open(backup, flags, expected_state[3] & 0o7777)
        for chunk in chunks:
            view = memoryview(chunk)
            while view:
                written = os.write(backup_descriptor, view)
                view = view[written:]
        os.fchmod(backup_descriptor, expected_state[3] & 0o7777)
        os.fsync(backup_descriptor)
    except BaseException:
        backup.unlink(missing_ok=True)
        raise
    finally:
        if backup_descriptor is not None:
            os.close(backup_descriptor)


def remove_transaction(removals, journal):
    """Journal a recoverable all-or-nothing removal across process death."""
    require_unique_paths((path for path, _state in removals), "removal")
    if journal.exists() or journal.is_symlink():
        raise ValueError(f"Removal recovery is already pending at {journal}")
    entries = []
    try:
        for path, expected_state in removals:
            if path_fingerprint(path) != expected_state:
                raise ValueError(f"Removal target changed before journaling: {path}")
            quarantine = reserve_removal_path(path.parent, ".project-remove-")
            backup = reserve_removal_path(path.parent, ".project-remove-backup-")
            create_removal_backup(path, backup, expected_state)
            entries.append((path, quarantine, backup, expected_state))
            if not recovery_copy_matches(backup, expected_state):
                raise ValueError(f"Refusing unauthenticated removal backup: {backup}")
        write_removal_journal(journal, "prepared", entries)
        for path, quarantine, _backup, expected_state in entries:
            if path_fingerprint(path) != expected_state:
                raise ValueError(f"Removal target changed before quarantine: {path}")
            atomic_move_noreplace(path, quarantine)
            if path_fingerprint(quarantine) != expected_state:
                if path_fingerprint(path) == ("missing",):
                    atomic_move_noreplace(quarantine, path)
                raise ValueError(f"Removal target changed during quarantine: {path}")
        write_removal_journal(journal, "committed", entries, replace=True)
    except BaseException:
        if journal.exists() and not journal.is_symlink():
            recover_removal_journal(journal, (path for path, _state in removals))
        else:
            for _path, quarantine, backup, expected_state in entries:
                cleanup_removal_copy(quarantine, expected_state)
                cleanup_removal_copy(backup, expected_state)
        raise
    try:
        recover_removal_journal(journal, (path for path, _state in removals))
    except (OSError, ValueError) as exc:
        print(f"project: removal committed; recovery cleanup remains at {journal}: {exc}",
              file=sys.stderr)


def atomic_checked_replace(source, destination, expected_state):
    """Publish source only if destination still has its expected identity."""
    published_state = path_fingerprint(source)
    if expected_state == ("missing",):
        try:
            os.link(source, destination, follow_symlinks=False)
        except FileExistsError as exc:
            raise ValueError(f"Refusing concurrent collision at {destination}") from exc
        try:
            source.unlink()
        except OSError:
            atomic_checked_unlink(destination, published_state)
            raise
        return None, published_state
    if expected_state[:1] != ("file",):
        raise ValueError(f"Refusing non-regular replacement at {destination}")
    atomic_exchange(source, destination)
    if (path_fingerprint(source) != expected_state
            or path_fingerprint(destination) != published_state):
        atomic_exchange(source, destination)
        collision = preserve_staged_collision(source)
        if path_fingerprint(destination) != expected_state:
            raise ValueError(
                f"Refusing concurrent replacement at {destination}; "
                f"original identity could not be restored and staged bytes remain at {collision}"
            )
        raise ValueError(
            f"Refusing concurrent replacement at {destination}; "
            f"preserved unexpected staged bytes at {collision}"
        )
    return source, published_state


def replace_transaction(replacements, staged, expected_states):
    """Publish related files with identity checks and roll back on failure."""
    require_unique_paths((destination for destination, _source in replacements),
                         "replacement")
    backups = {}
    replaced = []
    current_states = dict(expected_states)
    try:
        for destination, source in replacements:
            backup, published_state = atomic_checked_replace(
                source, destination, current_states[destination])
            if destination not in backups:
                backups[destination] = backup
            current_states[destination] = published_state
            replaced.append(destination)
    except (OSError, ValueError):
        restored = set()
        for destination in reversed(replaced):
            if destination in restored:
                continue
            restored.add(destination)
            backup = backups[destination]
            if backup is None:
                if path_fingerprint(destination) == current_states[destination]:
                    atomic_checked_unlink(destination, current_states[destination])
            else:
                atomic_checked_replace(backup, destination,
                                       current_states[destination])
        raise


def main(argv=None):
    if sys.version_info < (3, 10):
        print(
            "project install refused: Python 3.10 or newer is required",
            file=sys.stderr,
        )
        return 2
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Offline source executable; must match the pin")
    parser.add_argument("--bin-dir", type=Path, default=Path(os.environ.get("OPENREPOPROJECT_BIN_DIR", str(Path.home() / ".local/bin"))))
    parser.add_argument("--pin", type=Path, default=Path(os.environ.get(
        "OPENREPOPROJECT_PIN", ROOT / "config/openrepoproject-pin.json")))
    parser.add_argument("--workbenches", type=Path, default=Path(os.environ.get(
        "WORKBENCHES_ROOT", ROOT)))
    parser.add_argument("--replace-existing", action="store_true",
                        help="replace a non-workBenches project command after explicit approval")
    parser.add_argument("--install-onp", action="store_true",
                        help="install the verified project launcher under the onp compatibility name")
    operation = parser.add_mutually_exclusive_group()
    operation.add_argument("--remove", action="store_true",
                        help="remove only a project command owned by this installer")
    operation.add_argument("--resolve-owned", action="store_true",
                           help="print the command path only when installer ownership verifies")
    operation.add_argument("--resolve-onp-owned", action="store_true",
                           help="print the onp path only when its trusted launcher verifies")
    operation.add_argument("--exec-owned", action="store_true",
                           help="verify and execute the owned command while holding a shared lock")
    parser.add_argument("command_args", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if (os.environ.get("WORKBENCHES_SKIP_PROJECT_COMMAND") == "1"
            and not args.resolve_owned and not args.resolve_onp_owned
            and not args.exec_owned and not args.remove):
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
        if not directory.is_absolute():
            raise ValueError("OPENREPOPROJECT_BIN_DIR/--bin-dir must be absolute")
        directory = directory.resolve(strict=False)
        target, payload = directory / "project", directory / PAYLOAD_NAME
        onp = directory / "onp"
        marker = directory / ".workbenches-path"
        owner_marker = directory / ".workbenches-project.json"
        lock_path = directory / LOCK_NAME
        removal_journal = directory / REMOVAL_JOURNAL_NAME
        discovery = project_discovery_path()
        managed_paths = (target, payload, onp, marker, owner_marker,
                         lock_path, removal_journal)
        removable_paths = (target, payload, owner_marker, onp)
        for managed_path in managed_paths:
            if paths_alias(discovery, managed_path):
                raise ValueError(
                    f"Project discovery pointer aliases managed artifact: {managed_path}"
                )
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
        read_operation = args.resolve_owned or args.resolve_onp_owned or args.exec_owned
        if args.remove and not directory.exists():
            print(f"project: no install directory at {directory}", file=sys.stderr)
            return 3
        if args.remove:
            if not lock_path.is_file():
                print(f"project: no installer-owned command at {target}", file=sys.stderr)
                return 3
            if not removal_journal.exists() and not removal_journal.is_symlink():
                preliminary_lock = acquire_project_lock(directory, exclusive=False)
                try:
                    preliminarily_owned = owned_target(
                        target, payload, owner_marker, pin, expected_launcher_digests)
                    preliminary_onp_owned = trusted_launcher(
                        onp, expected_launcher_digests)
                finally:
                    os.close(preliminary_lock)
                if not preliminarily_owned and not preliminary_onp_owned:
                    print(f"project: preserved unowned command at {target}", file=sys.stderr)
                    return 3
        if read_operation and not lock_path.is_file():
            print(f"project: refused unlocked command at {target}", file=sys.stderr)
            return 3
        if not read_operation:
            if directory.exists() and (not directory.is_dir() or not os.access(directory, os.W_OK)):
                raise ValueError(f"Unwritable install directory: {directory}")
            directory.mkdir(parents=True, exist_ok=True)
        lock_descriptor = acquire_project_lock(directory, exclusive=not read_operation)
        if read_operation and (removal_journal.exists() or removal_journal.is_symlink()):
            print(f"project: refused command with pending removal recovery at {removal_journal}",
                  file=sys.stderr)
            return 3
        recovery_result = None
        if not read_operation:
            recovery_result = recover_removal_journal(
                removal_journal, removable_paths)
            if args.remove and recovery_result == "committed":
                remove_owned_discovery_pointer(discovery, directory)
                print(f"project: completed interrupted removal from {target}")
                return 0
        onp_owned = trusted_launcher(onp, expected_launcher_digests)
        if args.resolve_owned:
            if owned_target(target, payload, owner_marker, pin,
                            expected_launcher_digests):
                print(target)
                return 0
            print(f"project: refused unowned command at {target}", file=sys.stderr)
            return 3
        if args.resolve_onp_owned:
            if onp_owned:
                print(onp)
                return 0
            print(f"project: refused unowned compatibility command at {onp}", file=sys.stderr)
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
                onp_state = path_fingerprint(onp) if onp_owned else None
                discovery_owned = discovery_points_to(discovery, directory)
                discovery_state = (path_fingerprint(discovery)
                                   if discovery_owned else None)
                if (not owned_target(target, payload, owner_marker, pin,
                                     expected_launcher_digests)
                        or removal_state != (path_fingerprint(target), path_fingerprint(payload),
                                             path_fingerprint(owner_marker))
                        or (onp_owned and (not trusted_launcher(
                            onp, expected_launcher_digests)
                            or onp_state != path_fingerprint(onp)))
                        or (discovery_owned and (
                            not discovery_points_to(discovery, directory)
                            or discovery_state != path_fingerprint(discovery)))):
                    raise ValueError("Project command changed during removal; nothing removed")
                removals = [
                    (target, removal_state[0]),
                    (payload, removal_state[1]),
                    (owner_marker, removal_state[2]),
                ]
                if onp_owned:
                    removals.append((onp, onp_state))
                remove_transaction(removals, removal_journal)
                if discovery_owned:
                    remove_owned_discovery_pointer(
                        discovery, directory, discovery_state)
                print(f"project: removed installer-owned command from {target}")
                return 0
            if onp_owned:
                onp_state = path_fingerprint(onp)
                if (not trusted_launcher(onp, expected_launcher_digests)
                        or onp_state != path_fingerprint(onp)):
                    raise ValueError("onp changed during removal; nothing removed")
                remove_transaction([(onp, onp_state)], removal_journal)
                print(f"project: removed installer-owned compatibility command from {onp}")
                return 0
            print(f"project: preserved unowned command at {target}", file=sys.stderr)
            return 3
        if not (wb / "config/bench-config.json").is_file():
            raise ValueError(f"Not a workBenches checkout: {wb}")
        initial_install_state = (path_fingerprint(target), path_fingerprint(payload),
                                 path_fingerprint(owner_marker), path_fingerprint(marker))
        initial_onp_state = path_fingerprint(onp)
        initial_discovery_state = path_fingerprint(discovery)
        target_digest = file_sha256(payload) if payload.is_file() and not payload.is_symlink() else ""
        target_owned = owned_target(target, payload, owner_marker, pin,
                                    expected_launcher_digests)
        onp_exists = onp.exists() or onp.is_symlink()
        legacy_onp_owned = trusted_legacy_onp(onp, wb)
        if args.install_onp and onp_exists and not onp_owned and not legacy_onp_owned:
            raise ValueError(f"Refusing to replace unowned onp command: {onp}")
        manage_onp = onp_owned or legacy_onp_owned or args.install_onp
        previous_commit = ""
        previous_launcher_digest = ""
        if target_owned:
            trusted_artifacts = [pin, *pin.get("trusted_previous", [])]
            previous_commit = next(item["commit"] for item in trusted_artifacts
                                   if item["sha256"] == target_digest)
            previous_launcher_digest = file_sha256(target)
        install_artifacts_exist = any(path.exists() or path.is_symlink()
                                      for path in (target, payload, owner_marker))
        recoverable_pending = recoverable_fresh_pending(
            target, payload, owner_marker, pin, launcher_digest)
        if (install_artifacts_exist and not target_owned
                and not recoverable_pending and not args.replace_existing):
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
        discovery_data = (str(directory.resolve()) + "\n").encode()
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
        unchanged = (target.is_file() and not target.is_symlink()
                     and target.read_bytes() == launcher_data
                     and target.stat().st_mode & 0o777 == 0o755
                     and payload.is_file() and not payload.is_symlink()
                     and payload.read_bytes() == data
                     and payload.stat().st_mode & 0o777 == 0o644)
        onp_same = (not manage_onp or (onp_owned and not onp.is_symlink()
                                      and onp.read_bytes() == launcher_data))
        marker_same = (marker.is_file() and not marker.is_symlink()
                       and marker.read_bytes() == marker_data)
        owner_same = (owner_marker.is_file() and not owner_marker.is_symlink()
                      and owner_marker.read_bytes() == owner_data)
        discovery_same = discovery_points_to(discovery, directory)
        if (not unchanged or not onp_same or not marker_same or not owner_same
                or not discovery_same):
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
            discovery_stage = None
            if not discovery_same:
                discovery.parent.mkdir(parents=True, exist_ok=True)
                validate_target(discovery)
                discovery_stage = stage(discovery.parent, discovery_data, 0o644)
                staged.append(discovery_stage)
            onp_stage = None
            if not onp_same:
                onp_stage = stage(directory, launcher_data, 0o755)
                staged.append(onp_stage)
            validate_target(target)
            validate_target(payload)
            validate_target(marker)
            validate_target(owner_marker)
            if onp_stage is not None:
                validate_target(onp)
            if initial_install_state != (path_fingerprint(target), path_fingerprint(payload),
                                         path_fingerprint(owner_marker), path_fingerprint(marker)):
                raise ValueError("Project command changed during installation; nothing replaced")
            if onp_stage is not None and initial_onp_state != path_fingerprint(onp):
                raise ValueError("onp changed during project installation; nothing replaced")
            if (discovery_stage is not None
                    and initial_discovery_state != path_fingerprint(discovery)):
                raise ValueError("Project discovery pointer changed during installation; nothing replaced")
            replacements = [
                (payload, payload_stage),
                (target, command_stage),
            ]
            if onp_stage is not None:
                replacements.append((onp, onp_stage))
            replacements.append((marker, marker_stage))
            if discovery_stage is not None:
                replacements.append((discovery, discovery_stage))
            expected_states = {
                target: initial_install_state[0],
                payload: initial_install_state[1],
                marker: initial_install_state[3],
            }
            if onp_stage is not None:
                expected_states[onp] = initial_onp_state
            if discovery_stage is not None:
                expected_states[discovery] = initial_discovery_state
            pending_backup, pending_state = atomic_checked_replace(
                pending_owner_stage, owner_marker, initial_install_state[2])
            replacements.append((owner_marker, owner_stage))
            expected_states[owner_marker] = pending_state
            try:
                replace_transaction(replacements, staged, expected_states)
            except (OSError, ValueError):
                if pending_backup is None:
                    atomic_checked_unlink(owner_marker, pending_state)
                else:
                    atomic_checked_replace(pending_backup, owner_marker,
                                           pending_state)
                raise
        fully_unchanged = (unchanged and onp_same and marker_same
                           and owner_same and discovery_same)
        print(f"project: {'already installed' if fully_unchanged else 'installed'} at {target}")
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
