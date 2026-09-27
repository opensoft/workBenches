# Quickstart: Remembered Claude Profiles

## Establish or change the remembered profile

```bash
pclaude team01a
```

The launcher resolves aliases and remembers the canonical profile only for a valid run.

## Reopen it without a lane

```bash
pclaude
```

This never resolves or starts a lane. Use it for a profile-scoped Claude session.

## Reopen it with lane support

```bash
lclaude
```

This uses the same remembered profile and the existing lane resolution order.

## Override it

```bash
lclaude team02b
```

The explicit profile wins and becomes the remembered profile for both commands.

## Inspect without changing it

```bash
pclaude list
pclaude status team01a
```

List, login, and status actions do not change the remembered run profile.

## Verification

Validated in `py-bench` on 2026-09-26:

- Bash syntax and ShellCheck error-level gates passed for the launcher, wrappers, and changed tests.
- All nine `devcontainer.test/test-claude-profile*.sh` suites passed with zero failures.
- The remembered-profile suite covered canonical aliases, both bare wrappers, failed preflight, stale and unsafe state, permissions, and non-run stability.
- Strict OpenSpec validation and Speckit prerequisite/checklist validation passed.
