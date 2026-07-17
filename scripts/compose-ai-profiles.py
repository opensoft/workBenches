#!/usr/bin/env python3
"""Compose authorized tenant and personal AI profile sources for workBenches."""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import pathlib
import tempfile
from typing import Any


PROVIDERS = {"claude": "claude-profiles.json", "openai": "openai-profiles.json"}
SOURCE_KIND = "workbenches-ai-profile-source"


class ProfileError(ValueError):
    pass


def read_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ProfileError(f"missing JSON file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ProfileError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ProfileError(f"expected a JSON object in {path}")
    return value


def source_file(value: str) -> pathlib.Path:
    path = pathlib.Path(value).expanduser().resolve()
    return path / "source.json" if path.is_dir() else path


def validate_profile(profile: Any, provider: str, source: pathlib.Path) -> dict[str, Any]:
    if not isinstance(profile, dict):
        raise ProfileError(f"{source}: {provider} profile must be an object")
    result = dict(profile)
    for field in ("name", "email", "family"):
        if not isinstance(result.get(field), str) or not result[field].strip():
            raise ProfileError(f"{source}: {provider} profile has invalid {field}")
    aliases = result.get("aliases", [])
    if aliases is None:
        aliases = []
    if not isinstance(aliases, list) or any(not isinstance(alias, str) or not alias for alias in aliases):
        raise ProfileError(f"{source}: {provider} profile {result['name']} has invalid aliases")
    result["aliases"] = aliases
    return result


def allowed_names(source: pathlib.Path, owner_type: str, user: str, provider: str) -> list[str]:
    if owner_type == "user":
        return ["*"]
    if owner_type == "product":
        return []
    grant_path = source.parent / "grants" / "users" / f"{user}.json"
    if not grant_path.exists():
        return []
    grant = read_json(grant_path)
    if grant.get("version") != 1 or grant.get("user") != user:
        raise ProfileError(f"invalid user grant: {grant_path}")
    patterns = grant.get("profiles", {}).get(provider, [])
    if not isinstance(patterns, list) or any(not isinstance(pattern, str) for pattern in patterns):
        raise ProfileError(f"invalid {provider} patterns in {grant_path}")
    return patterns


def is_allowed(name: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in patterns)


def atomic_json(path: pathlib.Path, payload: dict[str, Any]) -> None:
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


def compose(sources: list[str], user: str) -> dict[str, list[dict[str, Any]]]:
    output: dict[str, list[dict[str, Any]]] = {provider: [] for provider in PROVIDERS}
    names: dict[str, set[str]] = {provider: set() for provider in PROVIDERS}
    aliases: dict[str, set[str]] = {provider: set() for provider in PROVIDERS}
    seen_user_source = False

    for value in sources:
        path = source_file(value)
        source = read_json(path)
        if source.get("version") != 1 or source.get("kind") != SOURCE_KIND:
            raise ProfileError(f"unsupported source contract: {path}")
        owner = source.get("owner")
        if not isinstance(owner, dict) or owner.get("type") not in {"tenant", "user", "product"}:
            raise ProfileError(f"invalid owner in {path}")
        owner_type = owner["type"]
        owner_id = owner.get("id")
        if not isinstance(owner_id, str) or not owner_id:
            raise ProfileError(f"invalid owner ID in {path}")
        if owner_type == "user":
            if owner_id != user:
                raise ProfileError(f"user source {path} belongs to {owner_id}, not {user}")
            if seen_user_source:
                raise ProfileError("only one user profile source may be composed")
            seen_user_source = True

        profiles = source.get("profiles", {})
        if not isinstance(profiles, dict):
            raise ProfileError(f"invalid profiles object in {path}")
        for provider in PROVIDERS:
            provider_profiles = profiles.get(provider, [])
            if not isinstance(provider_profiles, list):
                raise ProfileError(f"invalid {provider} profiles in {path}")
            patterns = allowed_names(path, owner_type, user, provider)
            for raw_profile in provider_profiles:
                profile = validate_profile(raw_profile, provider, path)
                name = profile["name"]
                if not is_allowed(name, patterns):
                    continue
                if name in names[provider]:
                    raise ProfileError(f"duplicate {provider} profile name: {name}")
                collisions = {name, *profile["aliases"]} & (names[provider] | aliases[provider])
                if collisions:
                    joined = ", ".join(sorted(collisions))
                    raise ProfileError(f"duplicate {provider} name or alias: {joined}")
                names[provider].add(name)
                aliases[provider].update(profile["aliases"])
                output[provider].append(profile)

    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user", required=True, help="GitHub user whose grants are applied")
    parser.add_argument("--source", action="append", required=True, help="Source directory or source.json")
    parser.add_argument("--output-dir", type=pathlib.Path, help="Write launcher manifests to this directory")
    parser.add_argument("--check", action="store_true", help="Validate and summarize without writing")
    args = parser.parse_args()

    try:
        profiles = compose(args.source, args.user)
        if not args.check:
            if args.output_dir is None:
                parser.error("--output-dir is required unless --check is used")
            output_dir = args.output_dir.expanduser().resolve()
            for provider, filename in PROVIDERS.items():
                atomic_json(output_dir / filename, {"version": 1, "profiles": profiles[provider]})
        print(
            "AI profile composition valid: "
            + ", ".join(f"{provider}={len(profiles[provider])}" for provider in PROVIDERS)
        )
        return 0
    except ProfileError as exc:
        parser.exit(1, f"error: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
