# Shared MCP servers for AI profiles

workBenches keeps provider credentials, MCP OAuth grants, sessions, and history
isolated per profile. MCP server definitions can be shared by company family.

The default shared family is `opensoft`. Its protected registry is stored at:

```text
~/projects/.workbenches/mcp/opensoft/registry.json
```

Inside a bench, the same physical directory is visible at:

```text
/workspace/projects/.workbenches/mcp/opensoft
```

Registry files are owner-only and are not part of a Git repository.

## Add and remove servers

Use either profile launcher. A successful profile-level add is imported into
the family registry and rendered for both Codex and Claude:

```bash
pcodex team001 mcp add example --url https://example.com/mcp
pclaude team002 mcp add --transport http example https://example.com/mcp
```

For Claude, the launcher supplies `--scope user` when no scope is given. An
explicit `--scope local` or `--scope project` remains local/project-scoped and
is not promoted to the company registry.

Removing a shared server through either launcher removes it for both harnesses:

```bash
pcodex team001 mcp remove example
pclaude team002 mcp remove example
```

Inspect definition metadata without printing credential values:

```bash
workbenches-mcp-sync list opensoft
```

## Runtime behavior

- Every Opensoft `pcodex` launch converts the registry into Codex configuration
  overrides for that process.
- Every Opensoft `pclaude` launch atomically materializes the registry's MCP
  definitions into that profile before starting Claude.
- Definitions added through either launcher therefore become available to both
  harnesses and every profile in the family on their next launch.
- Existing sessions must reconnect through `/mcp` or be resumed in a new CLI
  process before they see a changed definition.
- Personal, Medx, and other families use separate registries and do not inherit
  Opensoft definitions unless explicitly enabled.

## Authentication boundary

The registry shares server definitions, not provider or MCP OAuth sessions.
When an MCP server requires OAuth, each Claude or Codex profile completes its
own MCP login. This prevents one AI account's refresh token or provider session
from being copied into another account.

Environment references such as `${MCP_TOKEN}` are portable between the two
harnesses. Literal headers and stdio environment values are retained in the
owner-only registry, but environment references or a credential broker are
preferred. Never commit the generated registry.

Portable server names and environment/header keys use letters, digits,
underscores, and hyphens. HTTP, SSE, and stdio definitions are accepted;
runtime support still depends on the client and server versions. A stdio
command must exist in every bench where either harness will launch it.

Claude.ai-managed connectors are account services rather than local MCP
definitions and are not copied. Interactive additions made inside a running
TUI are not promoted automatically; use the launcher-level `mcp add` command.
