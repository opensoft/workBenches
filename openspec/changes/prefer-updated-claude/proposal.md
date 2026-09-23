## Why

Claude profile launches can keep using the image's older `/usr/local/bin/claude` even after the native updater installs a newer version for the container user. This hides models that require a newer Claude Code CLI and makes profile swaps appear to downgrade the client.

## What Changes

- Prefer the newest executable native Claude Code version already installed for the current user when starting a profile session.
- Preserve an explicit `CLAUDE_BIN` override and fall back to the existing PATH behavior when no native version is available.
- Do not make a network update check part of session startup; allow Claude Code's native background updater to install future versions.

## Capabilities

### New Capabilities

- `claude-profile-binary-selection`: Defines which installed Claude Code executable profile and lane launches use.

### Modified Capabilities

None.

## Impact

The shared `claude-profile` launcher and its focused regression tests change. No running session, image-managed CLI baseline, profile model setting, or deployment is changed by this source edit.
