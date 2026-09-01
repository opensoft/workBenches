## Context

The shared Codex profile is bind-mounted into py-bench and intentionally points
SonarQube MCP at host loopback. That address works for host-side Codex but cannot
reach the private proxy from py-bench. The proxy and backend already share the
external `devbench-shared` network, while py-bench currently joins only
`py-bench_default`. The proxy injects the Sonar token, so its listener must remain
private and credentials must never move into launcher arguments or logs.

The solution crosses the workBenches launcher/image source and the pyBench
submodule's Compose source. The active container must be reconciled after both
sources change, and the layered image chain must eventually contain the updated
launcher for recreation paths that do not run the Wave launcher repair step.

## Goals / Non-Goals

**Goals:**

- Preserve the host profile's loopback URL.
- Give py-bench private DNS and protocol reachability to the existing proxy.
- Override only the SonarQube MCP URL when `codex-profile` launches Codex in a
  runtime that supplies an override.
- Keep the behavior configurable and absent by default for other runtimes.
- Make restart and recreation behavior testable and durable.

**Non-Goals:**

- Publishing the proxy to all host interfaces.
- Moving or exposing SonarQube tokens.
- Replacing the shared SonarQube MCP services.
- Changing unrelated MCP servers or Codex authentication settings.

## Decisions

1. **Use dual Docker network attachment.** py-bench remains on
   `py-bench_default` and additionally joins the pre-existing external
   `devbench-shared` network. This preserves current bench isolation and MTU
   behavior while enabling Docker DNS for the proxy. Publishing the proxy or
   using a host gateway was rejected because it broadens exposure or repeats the
   unreachable path.

2. **Supply a runtime-specific environment variable from Compose.** py-bench
   sets `CODEX_SONARQUBE_MCP_URL` to the proxy service URL, with Compose
   interpolation allowing an operator override. The shared profile stays
   host-oriented, and other benches receive no behavior change unless they opt
   in.

3. **Translate the variable in `codex-profile`.** When non-empty, the launcher
   passes one Codex `-c` override for `mcp_servers.sonarqube.url`. The URL is
   encoded as a TOML-compatible quoted string and passed as an argument, not
   evaluated by a shell. Editing the bind-mounted profile or generating a
   second profile was rejected because either breaks host behavior or creates
   configuration drift.

4. **Validate at unit, configuration, and protocol levels.** A fake Codex binary
   verifies launcher argument construction, Compose rendering verifies dual
   networks and environment injection, and a real MCP `initialize` request plus
   `codex-profile ... mcp list` verifies the live route.

## Risks / Trade-offs

- **External network missing during recreation** → The existing devcontainer
  initialize command runs the shared SonarQube service bootstrap, which creates
  `devbench-shared` before Compose starts py-bench.
- **Launcher source updated but old image reused** → Reconcile the active
  launcher through supported tooling and rebuild the layered image chain for
  recreation paths that rely only on images.
- **Configuration override is malformed** → Encode the value with `jq` and cover
  quoting in a focused launcher test.
- **Compose recreation disrupts active sessions** → Perform one controlled
  recreation after tests are ready, then repeat checks after a separate restart.

## Migration Plan

1. Land launcher tests and the conditional configuration override.
2. Add the pyBench environment value and external network attachment.
3. Render and test Compose configuration before changing the live container.
4. Rebuild or reconcile the launcher installation and recreate py-bench.
5. Run DNS, MCP protocol, Codex listing, host-profile, and security-boundary
   checks; restart and repeat.
6. Roll back by reverting both source changes and recreating py-bench. The shared
   profile and proxy configuration require no rollback.

## Open Questions

None.
