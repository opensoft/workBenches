#!/usr/bin/env python3
"""Validate tracked bench Compose configurations without starting containers."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


def bench_services(config):
    """Include bench images and Flutter's build-only app, not infrastructure."""
    for name, service in config.get("services", {}).items():
        image = service.get("image", "").split(":", 1)[0].rsplit("/", 1)[-1]
        if image.endswith(("-bench", "bench-base")) or (
            name == "app" and "build" in service
        ):
            yield name, service


def init_errors(config):
    return [name for name, service in bench_services(config) if service.get("init") is not True]


def tracked_files(root):
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        capture_output=True, check=True,
    )
    return [Path(path.decode()) for path in result.stdout.split(b"\0") if path]


def configurations(files):
    """Check full definitions, then each tracked overlay against its base."""
    bases = [path for path in files if path.name in (
        "docker-compose.yml", "docker-compose-with-adb.yml",
    )]
    for base in bases:
        yield [base]
    for overlay in files:
        if overlay.name in (
            "docker-compose.override.yml", "docker-compose.wslg.yml",
            "docker-compose.usermap.yml",
        ):
            base = overlay.with_name("docker-compose.yml")
            if base in bases:
                yield [base, overlay]


def check_root(root):
    root = root.resolve()
    repository = root.parent.name.removesuffix("-worktrees") if root.parent.name.endswith("-worktrees") else root.name
    failures = 0
    checked = 0
    for files in configurations(tracked_files(root)):
        command = ["docker", "compose", "--env-file", os.devnull]
        for path in files:
            command.extend(["-f", str(root / path)])
        command.extend([
            "config", "--no-interpolate", "--no-env-resolution",
            "--no-path-resolution", "--format", "json",
        ])
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        label = " + ".join(str(path) for path in files)
        # Never echo config/stderr: local overlays can contain credentials.
        if result.returncode:
            print(f"FAIL {repository}/{label}: Compose configuration rejected", file=sys.stderr)
            failures += 1
            continue
        config = json.loads(result.stdout)
        services = list(bench_services(config))
        checked += len(services)
        errors = init_errors(config)
        if errors:
            print(f"FAIL {repository}/{label}: init must be true for {', '.join(errors)}", file=sys.stderr)
            failures += len(errors)
    if not checked:
        print(f"FAIL {repository}: no tracked bench services found", file=sys.stderr)
        failures += 1
    print(f"{repository}: checked {checked} bench service configurations; {failures} failures")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("roots", nargs="+", type=Path, help="Repository checkout(s) to validate")
    args = parser.parse_args()
    try:
        return int(sum(check_root(root) for root in args.roots) != 0)
    except (OSError, subprocess.SubprocessError, ValueError):
        print("FAIL: configuration check could not complete; verify Git/Docker Compose and checkout paths", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
