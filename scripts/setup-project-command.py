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
                                    capture_output=True, timeout=60)
            if result.returncode == 0:
                return result.stdout
        except (OSError, subprocess.TimeoutExpired):
            pass
    url = f"https://raw.githubusercontent.com/{pin['repository']}/{pin['commit']}/project"
    with urllib.request.urlopen(url, timeout=30) as response:
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


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Offline source executable; must match the pin")
    parser.add_argument("--bin-dir", type=Path, default=Path(os.environ.get("OPENREPOPROJECT_BIN_DIR", str(Path.home() / ".local/bin"))))
    parser.add_argument("--pin", type=Path, default=ROOT / "config/openrepoproject-pin.json")
    parser.add_argument("--workbenches", type=Path, default=ROOT)
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
        validate_target(target)
        validate_target(marker)
        if directory.exists() and (not directory.is_dir() or not os.access(directory, os.W_OK)):
            raise ValueError(f"Unwritable install directory: {directory}")
        wb = args.workbenches.expanduser().resolve()
        if not (wb / "config/bench-config.json").is_file():
            raise ValueError(f"Not a workBenches checkout: {wb}")
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
        unchanged = target.is_file() and target.read_bytes() == data and target.stat().st_mode & 0o777 == 0o755
        marker_same = marker.is_file() and marker.read_bytes() == marker_data
        if not unchanged or not marker_same:
            directory.mkdir(parents=True, exist_ok=True)
            command_stage = stage(directory, data, 0o755)
            staged.append(command_stage)
            marker_stage = stage(directory, marker_data, 0o644)
            staged.append(marker_stage)
            validate_target(target)
            validate_target(marker)
            os.replace(marker_stage, marker)
            os.replace(command_stage, target)
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
