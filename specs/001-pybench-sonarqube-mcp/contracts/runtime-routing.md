# Runtime Routing Contracts

## `CODEX_SONARQUBE_MCP_URL`

- **Producer**: A runtime such as py-bench.
- **Consumer**: `codex-profile`.
- **Type**: Optional string.
- **Activation**: Non-empty after normal environment expansion.
- **Effect**: Add exactly two launcher arguments:
  `-c` and `mcp_servers.sonarqube.url=<TOML-quoted-value>`.
- **Absent/empty behavior**: Add no SonarQube URL configuration argument.
- **Security**: The value is a route only. Credentials must not be included,
  read, logged, or forwarded by this contract.

The runtime override is additive to the launcher's existing authentication
configuration and precedes the selected profile for that one process. All
user-supplied Codex arguments remain in their original order after launcher
configuration arguments.

## pyBench Compose Contract

- The `py-bench` service belongs to both `default` and `devbench-shared`.
- `default` retains the explicit `py-bench_default` name and MTU option.
- `devbench-shared` is declared external and is never created as a
  project-scoped replacement.
- The service environment supplies the runtime URL with the private proxy URL as
  its tracked default and supports a normal Compose interpolation override.
- No proxy port mapping is introduced.

## Validation Contract

The change is acceptable only when all of these independent observations hold:

1. The proxy service name resolves from py-bench.
2. A valid MCP `initialize` request from py-bench returns HTTP 200.
3. Codex MCP listing through `codex-profile` shows the private service URL.
4. The shared host profile still contains its loopback MCP URL.
5. Docker inspection shows py-bench on both networks and no public proxy binding.
6. Items 1–4 still pass after restart and again after recreation.
