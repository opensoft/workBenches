#!/usr/bin/env python3
"""Consolidate portable Codex profile history into company state families."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path


DIRECTORIES = ("sessions", "archived_sessions")
JSONL_FILES = ("history.jsonl", "session_index.jsonl")
FAMILY_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def family_for(profile: dict) -> str:
    family = profile.get("family")
    if not isinstance(family, str) or not FAMILY_PATTERN.fullmatch(family):
        raise ValueError(f"invalid or missing profile family: {family!r}")
    return family


def hash_file(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def atomic_text(path: Path, content: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def jsonl_records(path: Path) -> list[tuple[str, str]]:
    if not path.is_file():
        return []
    records = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"invalid JSONL at {path}:{number}: {error}") from error
        canonical = json.dumps(value, sort_keys=True, separators=(",", ":"))
        records.append((canonical, line))
    return records


def replace_with_link(source: Path, destination: Path, backup: Path) -> None:
    if source.is_symlink():
        source.unlink()
    elif source.exists():
        backup.parent.mkdir(parents=True, exist_ok=True)
        os.replace(source, backup)
    relative = os.path.relpath(destination, source.parent)
    temporary = source.parent / f".{source.name}.state-migration"
    temporary.symlink_to(relative)
    os.replace(temporary, source)


def merge_directories(
    profiles: list[tuple[Path, dict]], state_root: Path, backup_root: Path, report: dict
) -> None:
    for profile_dir, profile in profiles:
        family = family_for(profile)
        for name in DIRECTORIES:
            source_root = profile_dir / name
            target_root = state_root / family / name
            target_root.mkdir(parents=True, exist_ok=True)
            if source_root.is_dir() and not source_root.is_symlink():
                for source in sorted(source_root.rglob("*")):
                    if not source.is_file():
                        continue
                    relative = source.relative_to(source_root)
                    target = target_root / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if not target.exists():
                        try:
                            os.link(source, target)
                            report["sessions_hardlinked"] += 1
                        except OSError:
                            shutil.copy2(source, target)
                            report["sessions_copied"] += 1
                    elif hash_file(source) == hash_file(target):
                        report["sessions_identical"] += 1
                    else:
                        conflict = target.with_name(
                            f"{target.name}.migrated-{profile['name']}-{hash_file(source)[:12]}"
                        )
                        if not conflict.exists():
                            shutil.copy2(source, conflict)
                            report["session_conflicts"].append(str(conflict))
            backup = backup_root / "profile-state" / profile_dir.relative_to(state_root.parent / "profiles") / name
            replace_with_link(source_root, target_root, backup)
            report["links_repointed"] += 1


def merge_jsonl(
    profiles: list[tuple[Path, dict]],
    families: list[str],
    state_root: Path,
    backup_root: Path,
    report: dict,
) -> None:
    for family in families:
        family_profiles = [(path, profile) for path, profile in profiles if family_for(profile) == family]
        for name in JSONL_FILES:
            target = state_root / family / name
            target.parent.mkdir(parents=True, exist_ok=True)
            sources = [path / name for path, _ in family_profiles]
            seen: set[str] = set()
            lines: list[str] = []
            for source in [target, *sources]:
                if source.is_symlink():
                    continue
                for canonical, line in jsonl_records(source):
                    if canonical not in seen:
                        seen.add(canonical)
                        lines.append(line)
            atomic_text(target, "".join(f"{line}\n" for line in lines))
            report[f"{family}_{name}_records"] = len(lines)
            for profile_dir, _ in family_profiles:
                source = profile_dir / name
                backup = (
                    backup_root
                    / "profile-state"
                    / profile_dir.relative_to(state_root.parent / "profiles")
                    / name
                )
                replace_with_link(source, target, backup)
                report["links_repointed"] += 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, default=Path.home() / ".chatgpt-profiles")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    base = args.base.expanduser().resolve()
    profile_root = base / "profiles"
    state_root = base / "state"
    profiles = []
    for metadata in sorted(profile_root.rglob(".profile.json")):
        profile = json.loads(metadata.read_text(encoding="utf-8"))
        profiles.append((metadata.parent, profile))
    if not profiles:
        parser.error(f"no Codex profiles found under {profile_root}")
    families = sorted({family_for(profile) for _, profile in profiles})
    if not args.apply:
        print(f"Ready to consolidate {len(profiles)} Codex profile directories")
        return 0

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_root = base / "migration-backups" / f"state-consolidation-{timestamp}"
    backup_root.mkdir(parents=True)
    for family in families:
        family_root = state_root / family
        for name in DIRECTORIES:
            (family_root / name).mkdir(parents=True, exist_ok=True)
        for name in JSONL_FILES:
            path = family_root / name
            if not path.exists():
                atomic_text(path, "")

    report = {
        "timestamp": timestamp,
        "profiles": len(profiles),
        "sessions_hardlinked": 0,
        "sessions_copied": 0,
        "sessions_identical": 0,
        "session_conflicts": [],
        "links_repointed": 0,
        "metadata_updated": 0,
    }
    merge_directories(profiles, state_root, backup_root, report)
    merge_jsonl(profiles, families, state_root, backup_root, report)
    for profile_dir, profile in profiles:
        family = family_for(profile)
        if profile.get("family") != family:
            profile["family"] = family
            atomic_text(profile_dir / ".profile.json", json.dumps(profile, indent=2) + "\n")
            report["metadata_updated"] += 1
    atomic_text(backup_root / "report.json", json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print(f"Migration backup: {backup_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
