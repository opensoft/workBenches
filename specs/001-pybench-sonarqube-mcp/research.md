# Research: pyBench SonarQube MCP Routing

## Decision: Use a one-run Codex configuration override

Codex supports `-c` / `--config` for arbitrary one-run settings, dot notation
for nested keys, and TOML parsing for values. The launcher will therefore pass
`mcp_servers.sonarqube.url=<quoted-url>` only when the runtime environment value
is non-empty.

**Rationale**: This has higher precedence than profile files, affects only the
launched process, and uses the product's documented configuration contract.

**Alternatives considered**:

- Edit the bind-mounted profile: rejected because the same profile is used by
  host-side Codex and must retain its loopback URL.
- Generate a second container profile: rejected because it duplicates
  credentials/configuration and invites drift.
- Use a project-level config file: rejected because project trust and working
  directory would make behavior inconsistent across repositories.

## Decision: Encode the URL as a TOML basic string with `jq`

The launcher already requires `jq`. `jq -n --arg value "$value" '$value'`
produces a quoted, escaped string suitable for the Codex TOML value position.
The complete `key=value` is passed as one array argument.

**Rationale**: This handles quotes and backslashes without `eval`, shell
re-parsing, or custom escaping logic.

**Alternatives considered**:

- Pass the raw URL: rejected because an unusual but valid value could be parsed
  as a non-string or split incorrectly.
- Hand-written escaping: rejected because JSON/TOML basic-string escaping is
  easy to get subtly wrong.

## Decision: Attach py-bench to two networks

The service will remain on `py-bench_default` and also join the existing
external `devbench-shared` network.

**Rationale**: Docker service DNS then resolves `sonarqube-mcp-proxy` directly,
while the existing default-network MTU and isolation remain intact.

**Alternatives considered**:

- Publish the proxy on all host interfaces: rejected because the proxy injects
  a token and must remain private.
- Use host loopback or `host.docker.internal`: rejected because both are known
  to be unreachable from py-bench and do not provide service-name routing.
- Replace the default network: rejected because it would change unrelated bench
  connectivity and MTU behavior.

## Decision: Supply the URL through Compose with an overrideable default

pyBench Compose will define `CODEX_SONARQUBE_MCP_URL` with the private proxy URL
as its default while allowing normal Compose environment interpolation to
replace it.

**Rationale**: The runtime owns the routing decision; the shared launcher remains
generic and other runtimes are unchanged unless they opt in.

**Alternatives considered**:

- Hard-code the private URL in `codex-profile`: rejected because host and other
  bench executions use the same launcher.
- Rely only on a machine-local `.env`: rejected because the fix would not be
  reproducible from tracked source.

## Decision: Rebuild the layered launcher path and also reconcile live state

The source launcher is baked into Layer 0 and inherited by the dev and Python
layers. The active container can be updated by supported launcher reconciliation,
but the layered image chain must also be rebuilt for recreation paths that use
image contents directly.

**Rationale**: This covers both immediate recovery and source-driven durability.

**Alternatives considered**:

- Copy only into the running container: rejected because recreation loses it.
- Rebuild only the Python layer: rejected because the changed file originates in
  Layer 0 and a downstream rebuild alone can reuse the old parent content.

## Decision: Validate transport and configuration independently

The live checks cover Docker DNS, an HTTP MCP `initialize` request, and the
Codex-resolved server list separately.

**Rationale**: DNS proves network attachment, initialization proves proxy/backend
protocol behavior, and listing proves launcher configuration precedence. A
single success cannot mask a failure in another layer.

**Alternatives considered**:

- TCP-only probe: rejected because it does not prove MCP semantics.
- Codex listing only: rejected because a listed URL can still be unreachable.
