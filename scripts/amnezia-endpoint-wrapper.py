#!/usr/bin/env python3
"""Host-side Amnezia endpoint manifest wrapper for workBenches."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import random
import re
import shlex
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_MANIFEST_URL = (
    "https://fhnet.blob.core.windows.net/amnezia-manifest/endpoints.json"
)
DEFAULT_STATE_DIR = Path.home() / ".workbenches" / "amnezia-endpoint"
STATE_FILE = "state.json"
CACHE_FILE = "endpoints.json"
USER_AGENT = "workBenches-amnezia-endpoint/1.0"


class WrapperError(RuntimeError):
    """Expected user-facing wrapper error."""


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def utc_stamp() -> str:
    return utc_now().strftime("%Y%m%d%H%M%S")


def iso_now() -> str:
    return utc_now().replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso(value: str) -> dt.datetime | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def state_dir_from_args(args: argparse.Namespace) -> Path:
    return Path(
        args.state_dir
        or os.environ.get("AMNEZIA_ENDPOINT_STATE_DIR")
        or DEFAULT_STATE_DIR
    ).expanduser()


def manifest_url_from_args(args: argparse.Namespace) -> str:
    return args.manifest_url or os.environ.get(
        "AMNEZIA_ENDPOINT_MANIFEST_URL", DEFAULT_MANIFEST_URL
    )


def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise WrapperError(f"Could not read JSON from {path}: {exc}") from exc


def write_json_atomic(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=str(path.parent),
        delete=False,
    ) as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
        tmp_name = handle.name
    os.replace(tmp_name, path)


def load_state(state_dir: Path) -> dict[str, Any]:
    state = read_json(state_dir / STATE_FILE, {})
    if not isinstance(state, dict):
        raise WrapperError(f"State file must contain a JSON object: {state_dir / STATE_FILE}")
    state.setdefault("bad_until", {})
    return state


def save_state(state_dir: Path, state: dict[str, Any]) -> None:
    state["updated_at"] = iso_now()
    write_json_atomic(state_dir / STATE_FILE, state)


def fetch_url_json(url: str, timeout: float) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            charset = response.headers.get_content_charset() or "utf-8"
            body = response.read().decode(charset)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise WrapperError(f"Could not fetch manifest from {url}: {exc}") from exc

    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise WrapperError(f"Manifest response was not valid JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise WrapperError("Manifest response must be a JSON object")
    return payload


def load_manifest(args: argparse.Namespace, state_dir: Path) -> dict[str, Any]:
    cache_path = state_dir / CACHE_FILE
    if args.offline:
        manifest = read_json(cache_path, None)
        if manifest is None:
            raise WrapperError(f"No cached manifest found at {cache_path}")
        return validate_manifest(manifest)

    url = manifest_url_from_args(args)
    try:
        manifest = fetch_url_json(url, args.timeout)
        write_json_atomic(cache_path, manifest)
        return validate_manifest(manifest)
    except WrapperError as exc:
        if args.no_cache_fallback or not cache_path.exists():
            raise
        print(f"warning: {exc}; using cached manifest at {cache_path}", file=sys.stderr)
        return validate_manifest(read_json(cache_path, None))


def validate_manifest(manifest: Any) -> dict[str, Any]:
    if not isinstance(manifest, dict):
        raise WrapperError("Manifest must be a JSON object")

    vpn = manifest.get("vpn")
    if not isinstance(vpn, dict):
        raise WrapperError("Manifest is missing vpn object")

    active = vpn.get("active")
    if not isinstance(active, list):
        raise WrapperError("Manifest is missing vpn.active list")

    return manifest


def endpoint_host(endpoint: dict[str, Any]) -> str:
    host = endpoint.get("public_ip") or endpoint.get("host") or endpoint.get("ip")
    if not isinstance(host, str) or not host:
        raise WrapperError(f"Endpoint is missing public_ip/host: {endpoint}")
    return host


def endpoint_port(endpoint: dict[str, Any], manifest: dict[str, Any]) -> int:
    port = endpoint.get("port", manifest.get("vpn", {}).get("port"))
    try:
        port_int = int(port)
    except (TypeError, ValueError) as exc:
        raise WrapperError(f"Endpoint has invalid port: {endpoint}") from exc
    if port_int < 1 or port_int > 65535:
        raise WrapperError(f"Endpoint port is out of range: {port_int}")
    return port_int


def endpoint_protocol(endpoint: dict[str, Any], manifest: dict[str, Any]) -> str:
    protocol = endpoint.get("protocol", manifest.get("vpn", {}).get("protocol", "udp"))
    if not isinstance(protocol, str) or not protocol:
        return "udp"
    return protocol.lower()


def endpoint_key(endpoint: dict[str, Any]) -> str:
    return endpoint_host(endpoint)


def endpoint_string(endpoint: dict[str, Any], manifest: dict[str, Any]) -> str:
    return f"{endpoint_host(endpoint)}:{endpoint_port(endpoint, manifest)}"


def normalized_endpoint(endpoint: dict[str, Any], manifest: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(endpoint)
    normalized["host"] = endpoint_host(endpoint)
    normalized["port"] = endpoint_port(endpoint, manifest)
    normalized["protocol"] = endpoint_protocol(endpoint, manifest)
    normalized["endpoint"] = endpoint_string(endpoint, manifest)
    return normalized


def active_endpoints(
    manifest: dict[str, Any],
    state: dict[str, Any],
    include_bad: bool = False,
) -> list[dict[str, Any]]:
    raw_endpoints = manifest.get("vpn", {}).get("active", [])
    bad_until = state.get("bad_until", {})
    now = utc_now()
    endpoints: list[dict[str, Any]] = []

    for raw in raw_endpoints:
        if not isinstance(raw, dict):
            continue
        endpoint = normalized_endpoint(raw, manifest)
        blocked_until = parse_iso(str(bad_until.get(endpoint["host"], "")))
        endpoint["bad_until"] = (
            blocked_until.replace(microsecond=0).isoformat().replace("+00:00", "Z")
            if blocked_until and blocked_until > now
            else None
        )
        if endpoint["bad_until"] and not include_bad:
            continue
        endpoints.append(endpoint)

    return endpoints


def select_endpoint(
    endpoints: list[dict[str, Any]],
    state: dict[str, Any],
    strategy: str,
) -> dict[str, Any]:
    if not endpoints:
        raise WrapperError("No usable endpoints are available in the manifest")

    if strategy == "sticky":
        selected = state.get("selected", {})
        selected_host = selected.get("host") if isinstance(selected, dict) else None
        for endpoint in endpoints:
            if endpoint["host"] == selected_host:
                return endpoint
        return endpoints[0]

    if strategy == "first":
        return endpoints[0]

    if strategy == "random":
        return random.choice(endpoints)

    if strategy in {"round-robin", "next"}:
        last_host = state.get("round_robin_last_host")
        if not isinstance(last_host, str):
            return endpoints[0]
        for index, endpoint in enumerate(endpoints):
            if endpoint["host"] == last_host:
                return endpoints[(index + 1) % len(endpoints)]
        return endpoints[0]

    raise WrapperError(f"Unknown selection strategy: {strategy}")


def remember_selection(
    state: dict[str, Any],
    manifest: dict[str, Any],
    endpoint: dict[str, Any],
    strategy: str,
) -> None:
    state["manifest"] = {
        "schema": manifest.get("schema"),
        "version": manifest.get("version"),
        "generated_at": manifest.get("generated_at"),
    }
    state["selected"] = {
        "host": endpoint["host"],
        "port": endpoint["port"],
        "protocol": endpoint["protocol"],
        "endpoint": endpoint["endpoint"],
        "strategy": strategy,
        "selected_at": iso_now(),
    }
    if strategy in {"round-robin", "next"}:
        state["round_robin_last_host"] = endpoint["host"]


def shell_export(name: str, value: Any) -> str:
    return f"export {name}={shlex.quote(str(value))}"


def print_selected(
    endpoint: dict[str, Any],
    manifest: dict[str, Any],
    output_format: str,
) -> None:
    if output_format == "endpoint":
        print(endpoint["endpoint"])
    elif output_format == "host":
        print(endpoint["host"])
    elif output_format == "port":
        print(endpoint["port"])
    elif output_format == "config":
        print(f"Endpoint = {endpoint['endpoint']}")
    elif output_format == "env":
        print(shell_export("AMNEZIA_ENDPOINT", endpoint["endpoint"]))
        print(shell_export("AMNEZIA_ENDPOINT_HOST", endpoint["host"]))
        print(shell_export("AMNEZIA_ENDPOINT_PORT", endpoint["port"]))
        print(shell_export("AMNEZIA_ENDPOINT_PROTOCOL", endpoint["protocol"]))
    elif output_format == "json":
        print(
            json.dumps(
                {
                    "endpoint": endpoint,
                    "manifest": {
                        "schema": manifest.get("schema"),
                        "version": manifest.get("version"),
                        "generated_at": manifest.get("generated_at"),
                    },
                },
                indent=2,
                sort_keys=True,
            )
        )
    else:
        raise WrapperError(f"Unknown output format: {output_format}")


def print_endpoint_list(
    endpoints: list[dict[str, Any]],
    manifest: dict[str, Any],
    output_format: str,
) -> None:
    if output_format == "endpoints":
        for endpoint in endpoints:
            print(endpoint["endpoint"])
        return

    if output_format == "env":
        joined = ",".join(endpoint["endpoint"] for endpoint in endpoints)
        print(shell_export("AMNEZIA_ENDPOINTS", joined))
        return

    if output_format == "json":
        print(
            json.dumps(
                {
                    "manifest": {
                        "schema": manifest.get("schema"),
                        "version": manifest.get("version"),
                        "generated_at": manifest.get("generated_at"),
                    },
                    "endpoints": endpoints,
                },
                indent=2,
                sort_keys=True,
            )
        )
        return

    if output_format != "table":
        raise WrapperError(f"Unknown list output format: {output_format}")

    rows = [
        (
            endpoint.get("slot", ""),
            endpoint.get("resource_name", ""),
            endpoint["host"],
            str(endpoint["port"]),
            endpoint["protocol"],
            endpoint.get("bad_until") or "",
        )
        for endpoint in endpoints
    ]
    headers = ("slot", "resource", "host", "port", "proto", "bad_until")
    widths = [
        max(len(headers[index]), *(len(row[index]) for row in rows)) if rows else len(headers[index])
        for index in range(len(headers))
    ]
    print("  ".join(header.ljust(widths[index]) for index, header in enumerate(headers)))
    print("  ".join("-" * width for width in widths))
    for row in rows:
        print("  ".join(row[index].ljust(widths[index]) for index in range(len(headers))))


ENDPOINT_RE = re.compile(r"^(\s*Endpoint\s*=\s*)(\S+)(.*?)(\r?\n)?$")


def patch_config(path: Path, endpoint: dict[str, Any], backup: bool, patch_all: bool) -> int:
    if not path.exists():
        raise WrapperError(f"Config file does not exist: {path}")
    original = path.read_text(encoding="utf-8")
    lines = original.splitlines(keepends=True)
    patched = []
    count = 0

    for line in lines:
        match = ENDPOINT_RE.match(line)
        if match and (patch_all or count == 0):
            newline = match.group(4) or ""
            patched.append(f"{match.group(1)}{endpoint['endpoint']}{match.group(3)}{newline}")
            count += 1
        else:
            patched.append(line)

    if count == 0:
        raise WrapperError(f"No Endpoint line found in {path}")

    new_text = "".join(patched)
    if new_text == original:
        return count

    if backup:
        backup_path = path.with_name(f"{path.name}.bak-{utc_stamp()}")
        backup_path.write_text(original, encoding="utf-8")

    path.write_text(new_text, encoding="utf-8")
    return count


def command_refresh(args: argparse.Namespace) -> int:
    state_dir = state_dir_from_args(args)
    manifest = load_manifest(args, state_dir)
    print(
        json.dumps(
            {
                "cache": str(state_dir / CACHE_FILE),
                "schema": manifest.get("schema"),
                "version": manifest.get("version"),
                "generated_at": manifest.get("generated_at"),
                "endpoint_count": len(manifest.get("vpn", {}).get("active", [])),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


def command_list(args: argparse.Namespace) -> int:
    state_dir = state_dir_from_args(args)
    state = load_state(state_dir)
    manifest = load_manifest(args, state_dir)
    endpoints = active_endpoints(manifest, state, include_bad=args.include_bad)
    print_endpoint_list(endpoints, manifest, args.format)
    return 0


def command_select(args: argparse.Namespace) -> int:
    state_dir = state_dir_from_args(args)
    state = load_state(state_dir)
    manifest = load_manifest(args, state_dir)
    endpoints = active_endpoints(manifest, state, include_bad=False)
    endpoint = select_endpoint(endpoints, state, args.strategy)
    remember_selection(state, manifest, endpoint, args.strategy)
    save_state(state_dir, state)
    print_selected(endpoint, manifest, args.format)
    return 0


def command_patch(args: argparse.Namespace) -> int:
    state_dir = state_dir_from_args(args)
    state = load_state(state_dir)
    manifest = load_manifest(args, state_dir)
    endpoints = active_endpoints(manifest, state, include_bad=False)
    endpoint = select_endpoint(endpoints, state, args.strategy)
    remember_selection(state, manifest, endpoint, args.strategy)
    save_state(state_dir, state)

    count = patch_config(Path(args.config).expanduser(), endpoint, not args.no_backup, args.all)
    print(f"patched {count} Endpoint line(s) with {endpoint['endpoint']}")
    return 0


def endpoint_arg_host(value: str) -> str:
    if value.startswith("[") and "]" in value:
        return value[1 : value.index("]")]
    if ":" in value:
        return value.rsplit(":", 1)[0]
    return value


def command_mark_bad(args: argparse.Namespace) -> int:
    state_dir = state_dir_from_args(args)
    state = load_state(state_dir)
    host = endpoint_arg_host(args.endpoint)
    until = utc_now() + dt.timedelta(minutes=args.ttl_minutes)
    state.setdefault("bad_until", {})[host] = (
        until.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    )
    selected = state.get("selected")
    if isinstance(selected, dict) and selected.get("host") == host:
        state.pop("selected", None)
    save_state(state_dir, state)
    print(f"marked {host} bad until {state['bad_until'][host]}")
    return 0


def command_clear_bad(args: argparse.Namespace) -> int:
    state_dir = state_dir_from_args(args)
    state = load_state(state_dir)
    bad_until = state.setdefault("bad_until", {})
    if args.endpoint:
        host = endpoint_arg_host(args.endpoint)
        bad_until.pop(host, None)
        print(f"cleared bad marker for {host}")
    else:
        bad_until.clear()
        print("cleared all bad endpoint markers")
    save_state(state_dir, state)
    return 0


def command_state(args: argparse.Namespace) -> int:
    state_dir = state_dir_from_args(args)
    state = load_state(state_dir)
    print(json.dumps(state, indent=2, sort_keys=True))
    return 0


def command_clear_state(args: argparse.Namespace) -> int:
    state_dir = state_dir_from_args(args)
    state_path = state_dir / STATE_FILE
    cache_path = state_dir / CACHE_FILE
    removed = []
    for path in (state_path, cache_path):
        if path.exists():
            path.unlink()
            removed.append(str(path))
    print(json.dumps({"removed": removed}, indent=2, sort_keys=True))
    return 0


def add_manifest_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--manifest-url",
        help=f"manifest URL (default: {DEFAULT_MANIFEST_URL})",
    )
    parser.add_argument(
        "--state-dir",
        help=f"state/cache directory (default: {DEFAULT_STATE_DIR})",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=10.0,
        help="manifest fetch timeout in seconds",
    )
    parser.add_argument(
        "--offline",
        action="store_true",
        help="use only the cached manifest",
    )
    parser.add_argument(
        "--no-cache-fallback",
        action="store_true",
        help="fail instead of using the cache when fetch fails",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Fetch and apply the workBenches Amnezia endpoint manifest."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    refresh = subparsers.add_parser("refresh", help="fetch and cache the manifest")
    add_manifest_options(refresh)
    refresh.set_defaults(func=command_refresh)

    list_parser = subparsers.add_parser("list", help="list usable VPN endpoints")
    add_manifest_options(list_parser)
    list_parser.add_argument(
        "--format",
        choices=("table", "json", "env", "endpoints"),
        default="table",
    )
    list_parser.add_argument(
        "--include-bad",
        action="store_true",
        help="include locally marked-bad endpoints",
    )
    list_parser.set_defaults(func=command_list)

    select = subparsers.add_parser("select", help="select one usable VPN endpoint")
    add_manifest_options(select)
    select.add_argument(
        "--strategy",
        choices=("sticky", "first", "random", "round-robin", "next"),
        default="sticky",
    )
    select.add_argument(
        "--format",
        choices=("endpoint", "host", "port", "json", "env", "config"),
        default="endpoint",
    )
    select.set_defaults(func=command_select)

    patch = subparsers.add_parser(
        "patch",
        help="patch an exported WireGuard/Amnezia config Endpoint line",
    )
    add_manifest_options(patch)
    patch.add_argument("--config", required=True, help="config file to patch")
    patch.add_argument(
        "--strategy",
        choices=("sticky", "first", "random", "round-robin", "next"),
        default="sticky",
    )
    patch.add_argument(
        "--all",
        action="store_true",
        help="patch every Endpoint line instead of only the first one",
    )
    patch.add_argument(
        "--no-backup",
        action="store_true",
        help="do not write a timestamped .bak file before patching",
    )
    patch.set_defaults(func=command_patch)

    mark_bad = subparsers.add_parser(
        "mark-bad",
        help="locally suppress an endpoint while it appears blocked",
    )
    mark_bad.add_argument("endpoint", help="host, ip, or host:port")
    mark_bad.add_argument(
        "--ttl-minutes",
        type=int,
        default=60,
        help="minutes to suppress the endpoint",
    )
    mark_bad.add_argument("--state-dir", help=f"state directory (default: {DEFAULT_STATE_DIR})")
    mark_bad.set_defaults(func=command_mark_bad)

    clear_bad = subparsers.add_parser("clear-bad", help="clear local bad endpoint markers")
    clear_bad.add_argument("endpoint", nargs="?", help="optional host, ip, or host:port")
    clear_bad.add_argument("--state-dir", help=f"state directory (default: {DEFAULT_STATE_DIR})")
    clear_bad.set_defaults(func=command_clear_bad)

    state = subparsers.add_parser("state", help="show local wrapper state")
    state.add_argument("--state-dir", help=f"state directory (default: {DEFAULT_STATE_DIR})")
    state.set_defaults(func=command_state)

    clear_state = subparsers.add_parser("clear-state", help="delete local wrapper state/cache")
    clear_state.add_argument("--state-dir", help=f"state directory (default: {DEFAULT_STATE_DIR})")
    clear_state.set_defaults(func=command_clear_state)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except WrapperError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
