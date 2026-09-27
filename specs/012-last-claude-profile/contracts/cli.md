# CLI Contract

## Profile-only launcher

```text
pclaude [PROFILE] [CLAUDE_ARGS...]
```

- With `PROFILE`, resolves that explicit name or alias, remembers its canonical name after preflight, and launches without a lane.
- Without `PROFILE`, resolves the remembered canonical name and launches without a lane.
- Explicit lane options retain existing compatibility and opt into lane-aware behavior.

## Lane-aware launcher

```text
lclaude [PROFILE] [CLAUDE_ARGS...]
```

- With `PROFILE`, resolves that explicit name or alias, remembers its canonical name after preflight, and launches with normal lane resolution.
- Without `PROFILE`, resolves the remembered canonical name and launches with normal lane resolution.

## Existing actions

```text
pclaude list
pclaude login PROFILE [ARGS...]
pclaude status PROFILE [ARGS...]
pclaude run [PROFILE] [CLAUDE_ARGS...]
pclaude run -- CLAUDE_ARGS...
```

- `list`, `login`, and `status` never change remembered selection.
- `run` may omit `PROFILE`; other profile-requiring actions may not.
- Use `run --` when an omitted profile is followed by a positional Claude
  subcommand; this keeps invalid explicit profile names fail-closed.
- Explicit profiles always override remembered selection.

## Error contract

- Missing state: nonzero exit, no Claude launch, guidance to run `pclaude PROFILE` or `lclaude PROFILE`.
- Stale state: nonzero exit, names the remembered canonical profile, no Claude launch.
- Unsafe/malformed state: nonzero exit, names the state path and reason, no Claude launch.
- Invalid explicit profile: existing unknown-profile exit and diagnostic remain unchanged.
