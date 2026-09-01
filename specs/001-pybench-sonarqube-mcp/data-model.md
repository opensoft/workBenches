# Configuration Model: pyBench SonarQube MCP Routing

This feature introduces no application database entities. Its durable state is
the following small configuration model.

## Runtime MCP Override

| Field | Meaning | Validation |
|---|---|---|
| Environment key | Runtime-owned input consumed by the profile launcher | Exactly `CODEX_SONARQUBE_MCP_URL` |
| Server key | Codex MCP entry to override | Exactly `sonarqube` |
| URL | Streamable HTTP MCP endpoint for the current runtime | Non-empty string to activate; empty/unset means no override |
| Scope | Lifetime of the override | One launched Codex process |

Relationship: pyBench supplies the Runtime MCP Override; `codex-profile`
translates it; Codex resolves it above the bind-mounted profile for that process.

## Bench Network Attachment

| Field | Meaning | Validation |
|---|---|---|
| Default network | Existing bench-local network | Remains `py-bench_default` |
| Shared network | Existing private service network | External and named `devbench-shared` |
| Proxy identity | DNS name resolved on the shared network | `sonarqube-mcp-proxy` |

Relationship: py-bench joins both networks. The proxy and backend remain owned by
the shared service stack and already join the shared network.

## Host Profile Invariant

| Field | Meaning | Validation |
|---|---|---|
| Profile | Shared selected Codex profile | Bind-mounted, not rewritten |
| SonarQube URL | Route used by host-side Codex | Remains the host loopback MCP URL |
| Credentials | Existing profile authentication state | Unchanged |

## State Transitions

```text
tracked sources updated
  -> Compose renders dual networks + runtime override
  -> layered image contains updated launcher
  -> py-bench is recreated
  -> Docker DNS resolves proxy
  -> launcher adds one-run SonarQube URL override
  -> Codex lists and initializes the private MCP endpoint
```

Restart transitions skip source rendering and recreation but retain the same
container networks and environment. Recreation must reproduce the full state
from tracked sources.
