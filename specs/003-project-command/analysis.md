# Verification

Seven tests pass in py-bench with OPENREPOPROJECT_TEST_SOURCE naming the local
upstream executable. Six are standalone installation/forwarding tests; the
seventh installs the real CLI and creates a disposable project through onp.
CI runs standalone tests on Linux/macOS; the cross-repository test requires an
explicit source path and otherwise skips.

The real GitHub API installation was exercised against the published commit and
its SHA-256. Installed help, benches, status, doctor and update reports were
checked against local repositories. Bash parsing and git diff --check pass.
The OpenSpec change passes strict validation.

Merge dependency: land openRepoProject first and update the pin to its merged
main commit before landing this integration if squash merging changes identity.
