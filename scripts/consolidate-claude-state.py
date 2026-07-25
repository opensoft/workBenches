#!/usr/bin/env python3
"""Consolidate legacy OpenSoft Claude state families without losing data."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path


SOURCE_FAMILIES = ("opensoft-team", "opensoft-max", "xfactory")
STATE_LINKS = ("history.jsonl", "projects", "file-history", "plans", "tasks", "todos")


def digest(path: Path) -> str:
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


def history_records(path: Path) -> list[tuple[str, str]]:
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


def merge_history(target: Path, sources: list[Path]) -> tuple[int, int]:
    existing = history_records(target)
    seen = {canonical for canonical, _ in existing}
    lines = [line for _, line in existing]
    added = 0
    for source in sources:
        for canonical, line in history_records(source):
            if canonical not in seen:
                seen.add(canonical)
                lines.append(line)
                added += 1
    atomic_text(target, "".join(f"{line}\n" for line in lines))
    return len(lines), added


def merge_memory(target: Path, source: Path, family: str) -> bool:
    source_hash = digest(source)
    marker = f"<!-- workBenches-state-merge:{family}:{source_hash} -->"
    target_text = target.read_text(encoding="utf-8")
    if marker in target_text:
        return False
    source_text = source.read_text(encoding="utf-8")
    combined = f"{target_text.rstrip()}\n\n{marker}\n\n{source_text.lstrip()}"
    if not combined.endswith("\n"):
        combined += "\n"
    atomic_text(target, combined, target.stat().st_mode & 0o777)
    return True


def merge_tree(source_root: Path, target_root: Path, family: str, report: dict) -> None:
    for source in sorted(source_root.rglob("*")):
        relative = source.relative_to(source_root)
        if relative == Path("history.jsonl"):
            continue
        target = target_root / relative
        if source.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            try:
                os.link(source, target)
                report["hardlinked"] += 1
            except OSError:
                shutil.copy2(source, target)
                report["copied"] += 1
            continue
        if digest(source) == digest(target):
            report["identical"] += 1
            continue
        if relative.name == "MEMORY.md" and relative.parent.name == "memory":
            if merge_memory(target, source, family):
                report["memory_files_merged"] += 1
            continue
        conflict = target.with_name(f"{target.name}.migrated-from-{family}-{digest(source)[:12]}")
        if not conflict.exists():
            shutil.copy2(source, conflict)
            report["conflicts_preserved"].append(str(conflict))


def repoint_profiles(profile_root: Path, state_root: Path, report: dict) -> None:
    target_state = state_root / "opensoft"
    for metadata in profile_root.rglob(".profile.json"):
        try:
            profile = json.loads(metadata.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            raise ValueError(f"invalid profile metadata: {metadata}: {error}") from error
        if not str(profile.get("email", "")).lower().endswith("@opensoft.one"):
            continue
        if profile.get("family") != "opensoft":
            profile["family"] = "opensoft"
            atomic_text(metadata, json.dumps(profile, indent=2) + "\n", 0o600)
            report["metadata_updated"] += 1
        profile_dir = metadata.parent
        for name in STATE_LINKS:
            link = profile_dir / name
            if not link.is_symlink():
                continue
            destination = target_state / name
            relative = os.path.relpath(destination, profile_dir)
            temporary = profile_dir / f".{name}.state-migration"
            temporary.symlink_to(relative)
            os.replace(temporary, link)
            report["links_repointed"] += 1


def backup_collisions(state_root: Path, backup_root: Path) -> None:
    target_root = state_root / "opensoft"
    collision_root = backup_root / "opensoft-collision-targets"
    for source_family in SOURCE_FAMILIES:
        source_root = state_root / source_family
        for source in source_root.rglob("*"):
            if not source.is_file():
                continue
            relative = source.relative_to(source_root)
            target = target_root / relative
            if target.is_file() and digest(source) != digest(target):
                backup = collision_root / relative
                if not backup.exists():
                    backup.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(target, backup)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, default=Path.home() / ".claude-profiles")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    base = args.base.expanduser().resolve()
    state_root = base / "state"
    profile_root = base / "profiles"
    target_root = state_root / "opensoft"
    sources = [state_root / family for family in SOURCE_FAMILIES]
    missing = [str(path) for path in [target_root, *sources] if not path.is_dir()]
    if missing:
        parser.error(f"missing state directories: {', '.join(missing)}")
    if not args.apply:
        print("Ready to consolidate:", ", ".join(SOURCE_FAMILIES), "-> opensoft")
        return 0

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_root = base / "migration-backups" / f"state-consolidation-{timestamp}"
    backup_root.mkdir(parents=True)
    report = {
        "timestamp": timestamp,
        "sources": list(SOURCE_FAMILIES),
        "hardlinked": 0,
        "copied": 0,
        "identical": 0,
        "memory_files_merged": 0,
        "conflicts_preserved": [],
        "metadata_updated": 0,
        "links_repointed": 0,
    }

    backup_collisions(state_root, backup_root)
    history_paths = [source / "history.jsonl" for source in sources]
    total, added = merge_history(target_root / "history.jsonl", history_paths)
    report["history_records"] = total
    report["history_records_added"] = added
    for family, source in zip(SOURCE_FAMILIES, sources):
        merge_tree(source, target_root, family, report)

    repoint_profiles(profile_root, state_root, report)
    total, added_after_cutover = merge_history(target_root / "history.jsonl", history_paths)
    report["history_records"] = total
    report["history_records_added_after_cutover"] = added_after_cutover

    retired = backup_root / "retired-state"
    retired.mkdir()
    for source in sources:
        os.replace(source, retired / source.name)
    atomic_text(backup_root / "report.json", json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print(f"Retired source state: {retired}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
