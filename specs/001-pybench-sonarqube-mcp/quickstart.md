# Validation Quickstart

Run repository and Docker commands from the workBenches devcontainer or its
declared host-side launcher path, as appropriate.

## Static checks

```bash
bash -n base-image/files/codex-profile
devcontainer.test/test-codex-profile.sh
docker compose \
  -f devBenches/pyBench/.devcontainer/docker-compose.yml \
  config
```

Confirm the rendered py-bench service has both networks and the runtime URL.

## Reconcile and inspect

```bash
scripts/wave-container-shell.sh --check py-bench
docker inspect py-bench --format '{{json .NetworkSettings.Networks}}'
docker inspect py-bench --format '{{range .Config.Env}}{{println .}}{{end}}'
```

Do not print or inspect SonarQube token values.

## Protocol and Codex checks

From py-bench, resolve `sonarqube-mcp-proxy`, then send a JSON-RPC
`initialize` request with `Content-Type: application/json` and
`Accept: application/json, text/event-stream` to the private MCP URL. Record the
HTTP status only and verify it is 200.

Then run:

```bash
codex-profile run max-002 mcp list
```

Verify the SonarQube row shows the private proxy service URL.

On the host-side checkout, assert that the shared profile still includes its
loopback MCP URL. Do not display the rest of the profile.

## Lifecycle checks

1. Restart py-bench and repeat DNS, protocol, Codex listing, and host-profile
   assertions.
2. Recreate py-bench through the Dev Containers CLI or the repository's supported
   Wave/Compose tooling.
3. Repeat the assertions and inspect both network memberships.
4. Confirm the proxy has no host-wide published port.

## Layered image durability

Rebuild Layer 0, the development base, pyBench Layer 2, and the user Layer 3 in
dependency order when a recreation path can rely on image contents without
running the launcher reconciliation step.

## Validation Evidence

### Test-first baseline

- 2026-07-27: `devcontainer.test/test-codex-profile.sh` failed because the
  expected `mcp_servers.sonarqube.url` override was absent.
- 2026-07-27: `devBenches/pyBench/tests/test-devcontainer-config.sh` failed
  because py-bench did not supply the private runtime URL.
- Both failures occurred before launcher or Compose implementation changes and
  contained no credential values.

### Implementation and live reconciliation

- The running `py-bench` retained `py-bench_default` and was connected to
  `devbench-shared`. The source and installed `codex-profile` hashes matched.
- `sonarqube-mcp-proxy` resolved to its private Docker address from the running
  container.
- A JSON-RPC MCP `initialize` request from the running container returned HTTP
  200.
- With the Compose-provided runtime value supplied to the pre-existing
  container process, `codex-profile run max-002 mcp list` reported
  `http://sonarqube-mcp-proxy:64130/mcp` for only the SonarQube server.

The pre-existing live container was intentionally not replaced during the
validation session because that session itself ran inside the container. A
source-driven py-bench validation instance was therefore used for the disruptive
restart and recreation checks below. The live container still requires its
normal full devcontainer recreation to acquire the new Compose environment
without an explicit one-process injection.

### Security invariants

- The shared host profile still contained
  `http://127.0.0.1:64130/mcp` and did not contain the Docker service URL.
- The proxy remained published only on `127.0.0.1:64130` and attached only to
  `devbench-shared`.
- No token value was read or printed during validation.

### Lifecycle durability

- A py-bench service created from the tracked Compose source joined both
  `py-bench_default` and `devbench-shared`, received
  `CODEX_SONARQUBE_MCP_URL=http://sonarqube-mcp-proxy:64130/mcp`, resolved the
  proxy, returned HTTP 200 for MCP initialization, and listed the private URL
  through `codex-profile`.
- After an actual container restart, the container ID was unchanged and all
  network, environment, protocol, and launcher checks passed again.
- After `docker compose up --force-recreate`, the container ID changed and all
  checks passed again. The temporary validation container and volume were then
  removed.

### Build and repository tests

- Rebuilt successfully, in dependency order:
  `workbench-base:latest`, `dev-bench-base:latest`, `py-bench:latest`, and
  `py-bench:brett`.
- `bash -n` and ShellCheck passed for the changed shell sources.
- The focused launcher and pyBench Compose tests passed.
- The launcher test passed against the launcher baked into
  `workbench-base:latest`.
- The relevant full devcontainer suite passed 44 of 44 checks in the rebuilt
  `py-bench:brett` runtime context.
