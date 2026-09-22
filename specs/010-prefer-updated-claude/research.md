# Research: Native Claude Code binary selection

- **Decision**: Scan `~/.local/share/claude/versions/` for executable three-component numeric filenames. **Rationale**: Anthropic's native updater installs binaries there, while this bench's compatibility symlink can point at a stale system copy. **Alternative**: Trust `command -v claude`; rejected because it currently resolves the stale image copy.
- **Decision**: Compare version components numerically in Bash rather than by modification time. **Rationale**: Highest installed version, not most recently touched file, is the requested contract. **Alternative**: `sort -V`; rejected for portability to macOS Bash environments.
- **Decision**: Do not run `claude update` during startup. **Rationale**: Native installations check for updates in the background; a synchronous check adds network delay and a failure mode. **Alternative**: Update before every launch; rejected by the fast-start choice.
