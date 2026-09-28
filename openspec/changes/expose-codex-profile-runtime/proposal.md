## Why

Each Codex profile sets its own `CODEX_HOME`, but the installer-managed
standalone package cache currently exists only under the canonical user home.
Profile launches can therefore select an npm binary or fail to find the
app-server daemon package even when the supported standalone installation is
present.

## What Changes

- Prefer an explicit `CODEX_BIN`, then the installer-managed
  `$HOME/.local/bin/codex`, before falling back to a command found on `PATH`.
- Expose the canonical standalone package cache inside every profile-specific
  `CODEX_HOME` through a managed link.
- Add focused tests for binary precedence and profile-home package visibility.
- Preserve existing npm installations, credentials, sessions, and profile
  isolation.

## Capabilities

### New Capabilities

- `codex-profile-runtime`: Defines how profile-specific Codex homes resolve the supported standalone executable and package cache.

### Modified Capabilities

None.

## Impact

- `base-image/files/codex-profile`
- `scripts/setup-codex-profiles.sh`
- `devcontainer.test/test-codex-profile.sh`
- Existing profile directories gain a link to the canonical standalone package
  cache when that cache is installed; credentials and session data are not
  copied or rewritten.
