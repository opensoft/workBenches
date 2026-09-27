# Quickstart: Verify Codex profile runtime selection

From the feature worktree:

```bash
bash devcontainer.test/test-codex-profile.sh
bash -n base-image/files/codex-profile scripts/setup-codex-profiles.sh
git diff --check
```

The test uses temporary profile and executable fixtures. It does not read or rewrite real credentials, sessions, or package caches and does not restart a daemon or container.
