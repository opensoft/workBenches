## Why

Claude Opus 5.5 ignores the legacy top-level user effort setting and can start at medium despite profiles retaining xhigh. The user approved adding a startup fallback when no explicit effort is supplied.

## What Changes

- Add `--effort xhigh` to conversation launches through the shared pclaude/lclaude launcher when no CLI or environment effort override exists.
- Preserve explicit effort arguments, inherited and profile environment overrides, profile settings, and non-conversation commands.
- Add isolated argument-level regression coverage and document precedence.

## Capabilities

### New Capabilities

- `claude-startup-effort`: Explicit startup effort fallback and override preservation.

### Modified Capabilities

None.

## Impact

Shared `base-image/files/claude-profile`, launcher tests, and multi-account documentation. No authentication changes, profile-wide rewrite, provider requests, or running-session changes. Execution is governed by `specs/020-default-claude-effort/tasks.md`.
