#!/usr/bin/env python3
"""Validate tracked bench Compose configurations without starting containers."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


BASE_STEMS = ("docker-compose", "compose", "docker-compose-with-adb",
              "docker-compose.usermap", "compose.usermap")
OVERLAY_STEMS = ("docker-compose.override", "docker-compose.wslg", "docker-compose.usermap",
                 "compose.override", "compose.wslg", "compose.usermap")


def jsonc(text):
    """Preserve quoted strings while removing JSONC comments/trailing commas."""
    string = r'"(?:\\.|[^"\\])*"'
    text = re.sub("(" + string + r")|/\*.*?\*/|//[^\r\n]*",
                  lambda match: match.group(1) or "", text, flags=re.S)
    text = re.sub("(" + string + r")|,\s*([}\]])",
                  lambda match: match.group(1) or match.group(2), text, flags=re.S)
    return json.loads(text)


def validate_declared_compose_files(root, files):
    """Reject selectors the fixed-name source audit cannot actually validate."""
    for source in files:
        if source.name not in ("devcontainer.json", ".devcontainer.json"):
            continue
        config = jsonc((root / source).read_text())
        if not isinstance(config, dict):
            raise ValueError("Invalid Dev Container declaration")
        references = config.get("dockerComposeFile", [])
        if isinstance(references, str):
            references = [references]
        if not isinstance(references, list):
            raise ValueError("Invalid Compose selector")
        for reference in references:
            if not isinstance(reference, str) or "://" in reference:
                raise ValueError("Unsupported Compose selector")
            reference = reference.replace("${localWorkspaceFolder}", str(root))
            target = (root / source.parent / reference).resolve().relative_to(root)
            if target not in files:
                # Generated/personal overlays are outside tracked-source checks.
                ignored = subprocess.run(
                    ["git", "-C", str(root), "check-ignore", "--quiet", "--", str(target)],
                    capture_output=True, shell=False,
                )
                if ignored.returncode == 0:
                    continue
                raise ValueError("Untracked Compose selector")
            if target.suffix not in (".yml", ".yaml") or target.stem not in BASE_STEMS + OVERLAY_STEMS:
                raise ValueError("Unsupported Compose filename; extend the checker explicitly")


def bench_services(config):
    """Include bench images and Flutter's build-only app, not infrastructure."""
    for name, service in config.get("services", {}).items():
        image = service.get("image", "").split(":", 1)[0].rsplit("/", 1)[-1]
        build = service.get("build", {})
        base_image = build.get("args", {}).get("BASE_IMAGE", "") if isinstance(build, dict) else ""
        if image.endswith(("-bench", "bench-base")) or base_image.startswith("gentec-bench:") or (
            name == "app" and "build" in service
        ):
            yield name, service


def init_errors(config):
    return [name for name, service in bench_services(config) if service.get("init") is not True]


def tracked_files(root):
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        capture_output=True, check=True, shell=False,
    )
    return [Path(path.decode()) for path in result.stdout.split(b"\0") if path]


def configurations(files):
    """Check full definitions, then each tracked overlay against its base."""
    bases = [path for path in files if path.suffix in (".yml", ".yaml") and path.stem in BASE_STEMS]
    for base in bases:
        yield [base]
    for overlay in files:
        if overlay.suffix in (".yml", ".yaml") and overlay.stem in OVERLAY_STEMS:
            base_stem = "compose" if overlay.stem.startswith("compose.") else "docker-compose"
            for base in bases:
                if base.parent == overlay.parent and base.stem == base_stem:
                    yield [base, overlay]


def check_root(root):
    root = root.resolve()
    repository = root.parent.name.removesuffix("-worktrees") if root.parent.name.endswith("-worktrees") else root.name
    failures = 0
    checked = 0
    tracked = tracked_files(root)
    validate_declared_compose_files(root, tracked)
    for files in configurations(tracked):
        with tempfile.TemporaryDirectory(prefix="bench-init-") as temporary:
            stage = Path(temporary)
            arguments = ["--env-file", os.devnull, "--profile", "*"]
            # Compose 2 still stats required env files with --no-env-resolution.
            # Stage only the tracked YAML and empty fixtures, never real env files.
            for path in files:
                target = stage / path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root / path, target)
                for parent in (target.parent, *target.parent.parents):
                    if not parent.is_relative_to(stage):
                        break
                    (parent / ".env").touch()
                arguments.extend(["-f", str(target)])
            arguments.extend([
                "config", "--no-env-resolution",
                "--no-path-resolution", "--format", "json",
            ])
            environment = {
                "PATH": os.environ.get("PATH", ""), "HOME": str(stage),
                "USER": "bench-check", "COMPOSE_PROJECT_NAME": "bench-init-check",
                "PROJECT_NAME": "bench-init-check", "WORKSPACE_NAME": "bench-init-check",
            }
            if "SYSTEMROOT" in os.environ:
                environment["SYSTEMROOT"] = os.environ["SYSTEMROOT"]
            result = subprocess.run(["docker", "compose", *arguments],
                                    capture_output=True, text=True, timeout=30, shell=False,
                                    env=environment, cwd=stage / files[0].parent)
        label = " + ".join(str(path) for path in files)
        # Never echo config/stderr: local overlays can contain credentials.
        if result.returncode:
            print(f"FAIL {repository}/{label}: Compose configuration rejected", file=sys.stderr)
            failures += 1
            continue
        config = json.loads(result.stdout)
        services = list(bench_services(config))
        if not services:
            # Frappe declares its non-bench dependencies as a separate stack.
            # Do not exempt canonical/template variants merely for using Redis.
            infrastructure = config.get("services", {})
            if files == [Path("infrastructure/docker-compose.yml")] and infrastructure and all(
                service.get("image", "").split(":", 1)[0].rsplit("/", 1)[-1] in ("mariadb", "redis")
                for service in infrastructure.values()
            ):
                continue
            print(f"FAIL {repository}/{label}: no bench services found", file=sys.stderr)
            failures += 1
            continue
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
        print("FAIL: configuration check could not complete; verify Git/Docker Compose, checkout paths and supported Compose selectors", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
