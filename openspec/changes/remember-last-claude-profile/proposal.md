# Proposal

## Why

Operators repeatedly switch among many Claude profiles, but `pclaude` and `lclaude` currently require the profile name on every launch. This makes ordinary restarts unnecessarily error-prone and leaves profile-only launches exposed to a lane-name guard that should apply only to lane-aware sessions.

## What Changes

- Remember the canonical profile used by each successful Claude run launch.
- Make bare `pclaude` run the remembered profile without resolving or starting a lane.
- Make bare `lclaude` run the same remembered profile with normal lane resolution.
- Keep explicit profile selection and existing subcommands compatible.
- Return a clear, non-interactive error when no remembered profile is available.
- Make the lane-name guard inert for profile-only `pclaude` processes while preserving it for `lclaude` and explicit lane launches.

## Capabilities

### New Capabilities

- `claude-profile-launching`: Defines remembered-profile selection and the separation between profile-only and lane-aware Claude launches.

### Modified Capabilities

None.

## Impact

- Affects the shared `pclaude`, `lclaude`, and `claude-profile` launch path, its installed profile runtime hooks, focused shell tests, and operator documentation.
- Adds one non-secret, user-scoped state record containing only the canonical profile name.
- Does not change profile credentials, Claude session storage, lane records, or Key Vault custody.
