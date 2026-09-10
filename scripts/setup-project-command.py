#!/usr/bin/env python3
"""Install the commit-pinned openRepoProject executable. Apache-2.0."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


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


def owned_target(target, owner_marker, repository):
    if (not target.is_file() or target.is_symlink()
            or not owner_marker.is_file() or owner_marker.is_symlink()):
        return False
    try:
        owner = json.loads(owner_marker.read_text())
    except (OSError, ValueError, TypeError):
        return False
    if (not isinstance(owner, dict)
            or owner.get("schema_version") != 1
            or owner.get("repository") != repository
            or re.fullmatch(r"[0-9a-f]{64}", owner.get("sha256", "")) is None):
        return False
    allowed_digests = {owner["sha256"]}
    if owner.get("state") == "pending":
        previous_owned = owner.get("previous_owned")
        if not isinstance(previous_owned, bool):
            return False
        previous_digest = owner.get("previous_sha256", "")
        if previous_digest and re.fullmatch(r"[0-9a-f]{64}", previous_digest) is None:
            return False
        if previous_owned:
            if not previous_digest:
                return False
            allowed_digests.add(previous_digest)
        elif previous_digest:
            return False
    elif owner.get("state") not in (None, "owned"):
        return False
    return file_sha256(target) in allowed_digests


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
    parser.add_argument("--pin", type=Path, default=ROOT / "config/openrepoproject-pin.json")
    parser.add_argument("--workbenches", type=Path, default=ROOT)
    parser.add_argument("--replace-existing", action="store_true",
                        help="replace a non-workBenches project command after explicit approval")
    parser.add_argument("--remove", action="store_true",
                        help="remove only a project command owned by this installer")
    args = parser.parse_args(argv)
    if os.environ.get("WORKBENCHES_SKIP_PROJECT_COMMAND") == "1":
        print("project installation skipped by WORKBENCHES_SKIP_PROJECT_COMMAND=1")
        return 0
    staged = []
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
        validate_target(target)
        validate_target(marker)
        validate_target(owner_marker)
        if args.remove:
            if owned_target(target, owner_marker, pin["repository"]):
                target.unlink()
                owner_marker.unlink()
                print(f"project: removed installer-owned command from {target}")
                return 0
            print(f"project: preserved unowned command at {target}", file=sys.stderr)
            return 3
        if directory.exists() and (not directory.is_dir() or not os.access(directory, os.W_OK)):
            raise ValueError(f"Unwritable install directory: {directory}")
        wb = args.workbenches.expanduser().resolve()
        if not (wb / "config/bench-config.json").is_file():
            raise ValueError(f"Not a workBenches checkout: {wb}")
        target_digest = file_sha256(target) if target.is_file() else ""
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


if __name__ == "__main__":
    sys.exit(main())
