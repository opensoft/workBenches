# Resolve candidate paths before launching release suites

GitHub Actions checks out the candidate under a relative `candidate` directory.
The runner passed relative helper paths into children whose cwd was already the
candidate, making ct-launchers look under candidate/candidate. Resolve the root
once before creating environment paths. Keep all Speckit cases required.

Regression: invoke the real CLI with a relative source checkout and have its
child read both helper files. Verify failure before the fix and success after.
Run the complete Speckit suite with relative paths and hosted fixtures on v1.6.
