## Why

The shared bench images and account adapter do not yet expose several supported
AI coding tools, and a few existing installer/profile integrations have drifted
from their current upstream behavior. Refreshing the image-managed baseline
keeps every bench consistent while retaining explicit ownership and command-name
boundaries.

## What Changes

- Add image-managed installers and command verification for Kimi Code, Qwen
  Code, the Z.AI configuration helper, DeepSeek Harness, Amp, Aider, OpenHands,
  Cursor CLI, and MiniMax Code.
- Extend the account adapter and operator documentation for Qwen, Kimi Code,
  and MiniMax profiles.
- Refresh the Herdr installer checksum and the NotebookLM MCP launcher
  reconciliation.
- Use the current Claude Fable 5.1 profile default and prevent a containerized
  profile launcher from rewriting the host's native Claude compatibility link.

## Capabilities

### New Capabilities

- `shared-ai-cli-tooling`: Defines how supported AI CLIs are installed,
  verified, named, and exposed through shared workBench images and profile
  selection.

### Modified Capabilities

None.

## Impact

- Affects the shared Layer 0 and legacy devBench AI CLI installation scripts,
  profile launchers, adapter routing, operator documentation, and image refresh
  marker.
- Adds upstream package and native-installer dependencies to image builds.
- Does not mutate running benches; rebuilt images require a separate managed
  container recreation before they become live.
