# Proposal

## Why

Starting a Claude profile currently attempts to resolve and take a lane by default. This makes an ordinary profile launch depend on lane state and can present a lane picker when the operator only wants a profile session. Give operators separate, predictable commands for profile-only and lane-aware launches.

## What Changes

- **BREAKING:** `pclaude <profile>` starts a profile without implicit lane lookup, picker, or `lane-start` handoff.
- Add `lclaude <profile>` as the lane-aware entry point with the current lane resolution, restart, and refusal behavior.
- Preserve explicit `pclaude --lane <lane> <profile>` as a migration compatibility path.
- Route lane handoff and restart instructions through `lclaude`, and update the installed commands, tests, and documentation across workBenches and openRepoTools.
- Amend the lane collision protocol's launcher contract to name `lclaude` for lane restarts.

## Capabilities

### New Capabilities

- `claude-profile-lane-entrypoints`: Defines profile-only and lane-aware Claude launches, including compatibility and restart behavior.

### Modified Capabilities

None.

## Impact

The Claude profile launcher, host and image command installation, lane picker and handoff tooling, usage guard instructions, regression tests, and lane protocol text change. Existing callers that rely on bare `pclaude` to resume a lane must use `lclaude`.
