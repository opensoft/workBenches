#!/usr/bin/env python3
"""Normalize an AI source to the provider-account/credential contract."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import tempfile


AUTH_TYPES = {
    "claude": "subscription_oauth",
    "openai": "workspace_access_token",
    "gemini": "subscription_oauth",
    "grok": "subscription_token",
    "glm": "subscription_token",
}


def atomic_json(path: pathlib.Path, payload: dict) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, indent=2)
            stream.write("\n")
        os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def normalize(source_path: pathlib.Path) -> dict:
    source = json.loads(source_path.read_text(encoding="utf-8"))
    owner = source["owner"]["id"]
    source["credentialContractVersion"] = 1
    for provider, profiles in source.get("profiles", {}).items():
        for profile in profiles:
            base = f"{owner}.{provider}.{profile['name']}"
            profile.setdefault("accountId", f"{base}.account")
            profile.setdefault("credentialId", f"{base}.credential")
            credential_ref = f"ai/secrets/{provider}/{profile['name']}.credentials.sops.yaml"
            secret_path = source_path.parents[1] / credential_ref
            authentication = profile.setdefault("authentication", {})
            authentication.setdefault("type", AUTH_TYPES.get(provider, "provider_token"))
            authentication["credentialRef"] = credential_ref
            authentication["escrowStatus"] = (
                "available" if secret_path.is_file() else "not-escrowed"
            )
    return source


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source_path = args.source.expanduser().resolve()
    original = json.loads(source_path.read_text(encoding="utf-8"))
    normalized = normalize(source_path)
    if args.check:
        if original != normalized:
            parser.exit(1, f"not normalized: {source_path}\n")
        print(f"Provider-account contract valid: {source_path}")
        return 0
    atomic_json(source_path, normalized)
    print(f"Normalized provider-account contract: {source_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
