# Research: Wave Settings Defaults

## Decisions

- **Decision**: Treat existing settings as authoritative and apply defaults only
  to absent keys.
  **Rationale**: Both true and false can be deliberate user choices.
  **Alternatives considered**: Forcing repository values would be surprising and
  destructive.

- **Decision**: Resolve the Windows user profile when running in WSL.
  **Rationale**: The Windows-native Wave application does not consume an
  unrelated Linux config path.
  **Alternatives considered**: Hard-coded Windows usernames are not portable;
  Linux-only resolution gives false success under WSL.

- **Decision**: Parse and atomically replace JSON with Python.
  **Rationale**: Structured parsing detects malformed input, preserves unrelated
  keys, and avoids partial writes.
  **Alternatives considered**: Text substitution is unsafe for JSON and direct
  overwrite can truncate settings on failure.
