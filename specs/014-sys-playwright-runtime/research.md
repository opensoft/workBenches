# Research: Sys Playwright Runtime

## Decisions

- **Decision**: Use Playwright's supported `install --with-deps chromium` path.
  **Rationale**: It installs the complete dependency set for the pinned browser
  instead of relying on a partial hand-maintained library list.
  **Alternatives considered**: Installing only `libglib` fixed one symptom but
  did not guarantee the rest of Chromium's dependency closure.

- **Decision**: Keep browser binaries in `/ms-playwright`.
  **Rationale**: The immutable shared cache is inherited by every derived sys
  bench and does not depend on a particular user's home.
  **Alternatives considered**: Root and per-user caches make browser visibility
  depend on runtime identity and can be lost on profile recreation.

- **Decision**: Gate publication with `ldd` and a headless smoke launch.
  **Rationale**: File presence alone does not prove the browser is executable.
  **Alternatives considered**: Package-name assertions cannot detect indirect
  or upstream dependency changes.
