# Verification

Run `bash devcontainer.test/test-claude-profile-effort.sh` in the owning bench. Run existing `test-claude-profile-*.sh` suites and the lane-default suite through both pclaude and lclaude. Fixtures must use temporary HOME, manifest, profile root, and mock binaries.

After an installed launcher is byte-verified against tested source, new `pclaude PROFILE` launches receive xhigh; `pclaude PROFILE --effort max` retains max. Existing sessions are untouched. Source landing and persistent image rebuild are separate from narrow live installation.
