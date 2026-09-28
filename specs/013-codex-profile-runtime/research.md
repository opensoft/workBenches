# Research: Codex Profile Runtime

## Decisions

- **Decision**: Resolve executables in the order explicit `CODEX_BIN`, official standalone command, then normal `PATH`.
  **Rationale**: Explicit caller intent remains authoritative while the supported standalone installation is preferred over a possibly older npm package.
  **Alternatives considered**: Always use `PATH` would keep the mismatch; removing npm Codex would be destructive and outside scope.

- **Decision**: Link the canonical standalone package cache into each profile.
  **Rationale**: The daemon resolves packages relative to profile-specific `CODEX_HOME`; one link preserves a single installer-owned payload.
  **Alternatives considered**: Copying the cache duplicates large files and introduces version drift; sharing all of `.codex` would break profile isolation.

- **Decision**: Add the link only when the canonical cache exists.
  **Rationale**: Machines using only a normal-path Codex installation remain compatible.
  **Alternatives considered**: Creating an empty placeholder could mask a missing installer and produce a less actionable runtime failure.
