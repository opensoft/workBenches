#!/usr/bin/env python3
"""Compose Pi harness profiles from canonical provider manifests."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import tempfile


PROVIDERS = ("claude", "openai", "gemini", "grok", "glm")
IDENTITY_FIELDS = ("email", "family", "aliases", "profilePath")


def atomic_json(path: pathlib.Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, indent=2)
            stream.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def add_profile(profiles: dict[str, dict], provider: str, raw: dict, source: pathlib.Path) -> None:
    if not isinstance(raw, dict) or any(not raw.get(field) for field in ("name", "email", "family")):
        raise ValueError(f"invalid {provider} profile in {source}")
    aliases = raw.get("aliases") or []
    if not isinstance(aliases, list) or any(
        not isinstance(alias, str) or not alias.strip() for alias in aliases
    ):
        raise ValueError(f"invalid aliases for {provider} profile in {source}")
    normalized = {
        "email": raw["email"],
        "family": raw["family"],
        "aliases": sorted(aliases, key=str.casefold),
        "profilePath": raw.get("profilePath", raw["name"]),
    }
    existing = profiles.get(raw["name"])
    if existing is None:
        profiles[raw["name"]] = {"name": raw["name"], **normalized, "providers": [provider]}
        return
    if any(existing[field] != normalized[field] for field in IDENTITY_FIELDS):
        raise ValueError(f"provider identity mismatch for Pi profile {raw['name']}")
    if provider not in existing["providers"]:
        existing["providers"].append(provider)


def validate_namespace(profiles: list[dict]) -> None:
    owners: dict[str, str] = {}
    for profile in profiles:
        name = profile["name"]
        for token in [name, *profile.get("aliases", [])]:
            normalized = token.casefold()
            owner = owners.get(normalized)
            if owner is not None and owner != name:
                raise ValueError(
                    f"ambiguous Pi profile name or alias {token!r}: {owner!r} and {name!r}"
                )
            owners[normalized] = name


def compose(config_dir: pathlib.Path, profile_roots: dict[str, pathlib.Path] | None = None) -> list[dict]:
    profiles: dict[str, dict] = {}
    for provider in PROVIDERS:
        manifest = config_dir / f"{provider}-profiles.json"
        if not manifest.exists():
            continue
        payload = json.loads(manifest.read_text(encoding="utf-8"))
        if payload.get("version") != 1 or not isinstance(payload.get("profiles"), list):
            raise ValueError(f"invalid profile manifest: {manifest}")
        for raw in payload["profiles"]:
            add_profile(profiles, provider, raw, manifest)
    for provider, root in (profile_roots or {}).items():
        if provider not in PROVIDERS or not root.exists():
            continue
        selected: dict[str, tuple[int, pathlib.Path, dict]] = {}
        for metadata in sorted(root.rglob(".profile.json")):
            raw = json.loads(metadata.read_text(encoding="utf-8"))
            relative_profile = metadata.parent.relative_to(root)
            depth = len(relative_profile.parts)
            score = depth + (100 if raw.get("profilePath") else 0)
            current = selected.get(raw.get("name", ""))
            if current is None or score > current[0]:
                selected[raw.get("name", "")] = (score, metadata, raw)
        for _, metadata, raw in selected.values():
            add_profile(profiles, provider, raw, metadata)
    result = [profiles[name] for name in sorted(profiles, key=str.casefold)]
    validate_namespace(result)
    return result


def compose_families(config_dir: pathlib.Path, profiles: list[dict]) -> list[str]:
    families = {profile["family"] for profile in profiles}
    for provider in PROVIDERS:
        manifest = config_dir / f"{provider}-profiles.json"
        if not manifest.exists():
            continue
        payload = json.loads(manifest.read_text(encoding="utf-8"))
        declared = payload.get("families", [])
        if not isinstance(declared, list) or any(
            not isinstance(family, str) or not family for family in declared
        ):
            raise ValueError(f"invalid family inventory: {manifest}")
        families.update(declared)
    return sorted(families)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-dir", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--profile-root", action="append", default=[], metavar="PROVIDER=PATH")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        profile_roots = {}
        for value in args.profile_root:
            provider, separator, path = value.partition("=")
            if not separator or provider not in PROVIDERS:
                raise ValueError(f"invalid --profile-root: {value}")
            profile_roots[provider] = pathlib.Path(path).expanduser().resolve()
        result = compose(args.config_dir.expanduser().resolve(), profile_roots)
        families = compose_families(args.config_dir.expanduser().resolve(), result)
        if not args.check:
            if args.output is None:
                parser.error("--output is required unless --check is used")
            atomic_json(
                args.output.expanduser().resolve(),
                {"version": 1, "families": families, "profiles": result},
            )
        print(f"Pi profile composition valid: profiles={len(result)}")
        return 0
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        parser.exit(1, f"error: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
