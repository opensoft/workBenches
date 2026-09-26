# Data Model: Remember Last Claude Profile

## Remembered Profile Record

Represents the most recent canonical profile accepted by a `run` launch.

| Field | Type | Rules |
|-------|------|-------|
| canonical profile name | single text line | Non-empty; no additional lines; must resolve through current profile metadata before use |

### File invariants

- Located under the selected Claude profiles home.
- Regular file only; symbolic links and other object types are rejected.
- Owner-readable and owner-writable only (`0600`).
- Replaced atomically from a temporary regular file in the same directory.
- Contains no token, email address, credential, lane, or transcript identifier.

### State transitions

```text
absent --valid explicit run--> valid canonical name
valid name --different valid run--> replacement canonical name
valid name --list/login/status/failure--> unchanged
valid name --profile removed--> stale (read produces an actionable error)
unsafe or malformed object --read--> rejected (no launch)
```

## Launch Mode

| Mode | Source | Lane resolution | Name guard |
|------|--------|-----------------|------------|
| profile-only | `pclaude` default or explicit no-lane | disabled | managed guard returns success |
| lane-aware | `lclaude` or explicit lane mode | existing precedence | managed guard enforces lane identity |

The mode marker is process state, not persistent profile data. It must survive only the child handoff for the launch that set it.
