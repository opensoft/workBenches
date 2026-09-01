## Why

Codex started through `codex-profile` inside py-bench inherits the host-oriented
SonarQube MCP URL, but the host loopback and host gateway are not reachable from
that container. The failure must be corrected without changing the shared host
profile or exposing the token-injecting proxy beyond its private Docker network.

## What Changes

- Attach py-bench to the existing external `devbench-shared` network in addition
  to its current default network.
- Supply a py-bench-specific SonarQube MCP URL through a configurable runtime
  environment variable.
- Teach the shared `codex-profile` launcher to translate that variable into a
  single Codex configuration override for the SonarQube MCP server URL.
- Add launcher and devcontainer regression coverage plus live restart and
  recreation validation.
- Keep the shared host profile on its loopback URL and keep the proxy private.

## Capabilities

### New Capabilities

- `container-runtime-mcp-routing`: Runtime-specific MCP routing for a bench
  container without mutating shared host profile configuration.

### Modified Capabilities

None.

## Impact

The change affects the shared `codex-profile` launcher and its tests in
workBenches, the pyBench submodule's Compose network/environment configuration,
the layered workbench images that install the launcher, and the live py-bench
container. It does not change SonarQube credentials, proxy publication, or the
host-side Codex profile.
