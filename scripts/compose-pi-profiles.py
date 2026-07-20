#!/usr/bin/env python3
"""Compose Pi harness profiles from canonical provider manifests."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import tempfile


PROVIDERS = ("claude", "openai", "gemini", "grok", "glm")
IDENTITY_FIELDS = ("email", "family", "aliases")


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
    normalized = {
        "email": raw["email"],
        "family": raw["family"],
        "aliases": sorted(raw.get("aliases") or []),
    }
    existing = profiles.get(raw["name"])
    if existing is None:
        profiles[raw["name"]] = {"name": raw["name"], **normalized, "providers": [provider]}
        return
    if any(existing[field] != normalized[field] for field in IDENTITY_FIELDS):
        raise ValueError(f"provider identity mismatch for Pi profile {raw['name']}")
    if provider not in existing["providers"]:
        existing["providers"].append(provider)


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
        for metadata in sorted(root.glob("*/.profile.json")):
            add_profile(profiles, provider, json.loads(metadata.read_text(encoding="utf-8")), metadata)
    return [profiles[name] for name in sorted(profiles)]


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
        if not args.check:
            if args.output is None:
                parser.error("--output is required unless --check is used")
            atomic_json(args.output.expanduser().resolve(), {"version": 1, "profiles": result})
        print(f"Pi profile composition valid: profiles={len(result)}")
        return 0
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        parser.exit(1, f"error: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
