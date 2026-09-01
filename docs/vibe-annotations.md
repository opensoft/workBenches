# Vibe Annotations in workBenches

workBenches runs one shared Vibe Annotations MCP server for all language
benches. Do not start a separate server in each bench: the Windows Chromium
extension expects one local endpoint on port `3846`.

## Architecture

```text
Windows Chrome or Edge extension
  -> http://127.0.0.1:3846
  -> vibe-annotations container
  -> http://host.docker.internal:3846/mcp
  -> Codex and Claude profiles in cppBench, javaBench, pyBench, and the other
     language benches
```

The service stores its home under
`~/projects/.workbenches/vibe`. Inside the service and language benches this
resolves to `/workspace/projects/.workbenches/vibe`, so screenshot and reference
image paths returned by MCP are readable by Codex without adding another mount
to every bench.

## Install or repair

From the workBenches checkout on the WSL host:

```bash
scripts/ensure-vibe-annotations.sh
```

The installer builds the pinned server image, starts it with
`restart: unless-stopped`, binds port `3846` to host loopback only, and checks
the installed package version and health endpoint.

Management commands:

```bash
scripts/ensure-vibe-annotations.sh --status
scripts/ensure-vibe-annotations.sh --recreate
scripts/ensure-vibe-annotations.sh --stop
```

## Use from a bench

The standard `pcodex` and `pclaude` profile launchers load this MCP endpoint
from the Opensoft shared MCP registry when they run inside a container:

```text
http://host.docker.internal:3846/mcp
```

Start either harness normally through its profile launcher, then use `/mcp` to
verify `vibe-annotations` is connected. Ask the agent to `read my Vibe
Annotations` or `start watching Vibe Annotations`.

Bare `codex` does not receive the container-aware runtime override. When a
profile is intentionally not used, launch it with:

```bash
codex -c 'mcp_servers.vibe-annotations.url="http://host.docker.internal:3846/mcp"'
```

See `docs/shared-mcp-profiles.md` for the company-wide registry, cross-harness
translation, and MCP authentication boundaries.

## Browser extension

Install **Vibe Annotations - Visual Feedback for AI Coding Agents** from the
Chrome Web Store in the Windows-hosted Chromium browser. The extension talks
only to the loopback-published shared service; it does not connect directly to
individual benches.

Use distinct Windows browser origins or host ports for concurrently running
projects. Two different projects both presented as `http://localhost:3000`
cannot be reliably distinguished by URL-based annotation filtering.
