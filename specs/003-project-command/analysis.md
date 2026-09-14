# Verification

Twenty-nine focused installation and forwarding tests pass locally when
OPENREPOPROJECT_TEST_SOURCE names the local upstream executable. The
cross-repository case installs the real CLI and creates a disposable project
through onp. CI runs the standalone tests on Linux/macOS; that integration case
requires the explicit source path and otherwise skips.

The real GitHub API installation was exercised against the published commit and
its SHA-256. Installed help, benches, status, doctor and update reports were
checked against local repositories. Bash parsing and git diff --check pass.
The OpenSpec change passes strict validation.

Merge dependency: land openRepoProject first and update the pin to its merged
main commit before landing this integration if squash merging changes identity.
