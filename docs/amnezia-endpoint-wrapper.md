# Amnezia Endpoint Wrapper

`scripts/amnezia-endpoint` is the host-side client wrapper for the Amnezia
endpoint manifest published by `sysBenches/cloudBench`.

The wrapper does not modify the Amnezia GUI application's private state. It
fetches the public endpoint manifest, stores a local cache/state file, selects a
usable endpoint, and can patch exported WireGuard/Amnezia-style configs by
replacing the `Endpoint = host:port` line.

## Manifest

Default manifest URL:

```text
https://amneziamanifest13bd.blob.core.windows.net/manifest/endpoints.json
```

Override it when needed:

```bash
AMNEZIA_ENDPOINT_MANIFEST_URL="https://example.invalid/endpoints.json" \
  scripts/amnezia-endpoint list
```

Local state and cache are stored on the host at:

```text
~/.workbenches/amnezia-endpoint/
```

Override that location with `AMNEZIA_ENDPOINT_STATE_DIR` or `--state-dir`.

## Common Commands

Fetch and cache the current manifest:

```bash
scripts/amnezia-endpoint refresh
```

List active endpoints:

```bash
scripts/amnezia-endpoint list
scripts/amnezia-endpoint list --format endpoints
scripts/amnezia-endpoint list --format json
```

Select one endpoint:

```bash
scripts/amnezia-endpoint select
scripts/amnezia-endpoint select --strategy round-robin
scripts/amnezia-endpoint select --strategy random --format env
```

Patch an exported config:

```bash
scripts/amnezia-endpoint patch --config ~/vpn/amnezia.conf
```

The patch command writes a timestamped backup next to the config before
changing it. Use `--no-backup` only for disposable generated config files.

If an endpoint appears blocked from a client location, suppress it locally and
select another one:

```bash
scripts/amnezia-endpoint mark-bad 20.237.253.33 --ttl-minutes 60
scripts/amnezia-endpoint select --strategy round-robin
```

Clear local state:

```bash
scripts/amnezia-endpoint clear-bad
scripts/amnezia-endpoint clear-state
```

## Bench Integration

Benches can source shell exports:

```bash
eval "$(workBenches/scripts/amnezia-endpoint select --format env)"
```

or consume the selected endpoint directly:

```bash
ENDPOINT="$(workBenches/scripts/amnezia-endpoint select --strategy sticky)"
```

When installed globally through `scripts/install-workbench-commands.sh --install`,
the command is available as:

```bash
amnezia-endpoint select --format env
```
