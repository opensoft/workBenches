# Quickstart: Verify profile binary selection

1. Run the focused launcher test in the declared test bench with `devcontainer.test/test-claude-profile-binary-selection.sh` against the worktree launcher.
2. Confirm fixtures covering stale PATH, `2.1.9` versus `2.1.10`, invalid or non-executable entries, `CLAUDE_BIN`, no native directory, and lane handoff all pass.
3. Confirm no fixture update command ran and `bash -n` accepts the launcher and test.
4. Deploy only through the normal workBenches image or bench synchronization path; do not treat a source edit as a running-container update.
