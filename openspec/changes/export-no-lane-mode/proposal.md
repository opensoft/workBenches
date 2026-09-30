## Why

The no-lane marker currently reaches a tmux relaunch but is missing from direct Claude launches. Hooks need the actual session's launch mode to let profile-only sessions work without lane checks.

## What Changes

- Export `CLAUDE_NO_LANE=1` for launches without a lane, including direct execution and bare fallback.
- Clear the inherited marker when an explicit lane launch is requested; explicit `--no-lane` continues to win.
- Keep profile hook settings shared between launch modes.

## Capabilities

### New Capabilities

- `claude-launch-lane-mode`: publish the session's lane mode to child hooks.

### Modified Capabilities

## Impact

`base-image/files/claude-profile`, launcher tests and documentation. Requires openRepoTools's marker-aware guard. Implementation handoff: `specs/017-export-no-lane-mode/`.
