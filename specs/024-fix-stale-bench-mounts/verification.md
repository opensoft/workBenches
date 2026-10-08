# Verification: Stale Bench Mount Recovery

Date: 2026-10-08. All executable source tests ran as the bench user in the already-running cloud-bench, against the isolated feature worktree. Docker lifecycle calls in the test suites were mocked; neither suite replaced a real bench.

## Results

- Red regression: the new stale-bind fixture failed before implementation with `FAIL: stale bind failure was not explained`.
- Late-source red regression: removing the mock credential file during preparation originally still reached Compose and returned success; explicit error propagation from the Compose override writer now refuses that creation.
- Staged-metadata red regression: a Docker internal hashed source was initially treated as a missing host file. New fixtures require resolution to the declared original source, rejection of a missing original, and refusal of unresolved staging metadata before mutation.
- Green regression: `bash devcontainer.test/test-wave-container-shell.sh` passed after implementation, including missing/wrong-type sources, symlinks, unrelated errors, timeout status, changed sources, concurrent starts, cross-family diagnostics, ownership refusal, and bounded explicit repair.
- Related helpers: `bash devBenches/scripts/test-helper-safety.sh` passed after explicitly isolating its MCP registry and renderer context in its temporary fixture.
- Syntax: `bash -n scripts/wave-container-shell.sh devcontainer.test/test-wave-container-shell.sh devBenches/scripts/test-helper-safety.sh` passed.
- Governance: `openspec validate fix-stale-bench-mounts --strict` passed. The OpenSpec handoff intentionally links the single executable Speckit checklist rather than duplicating tasks.
- Patch hygiene: native Git `git diff --check` passed.
- Live metadata check: loaded only the new validation function definitions on the launcher's WSL host and validated every current py-bench bind, including internal staged metadata resolved to original sources. This read-only check did not run launcher preparation, creation, startup, or replacement.
- External review follow-up: added regressions for retained custom recovery options, stopped legacy containers without credential binds, every generated directory mount type, and custom effective Compose project names. The new custom-recovery fixture failed before the fixes; the full suites and actual bind/Wave host-source validation passed afterwards.
- CI prerequisite follow-up: the minimal Node integrity-test image lacked jq. Claude guard/version tests passed, but Wave metadata parsing refused the custom-Compose fixture. Added jq alongside zsh in that CI job; the existing host helper suite and live WSL host already have jq.
- Running-attach review follow-up: explicit Compose project resolution is skipped for normal already-running attaches. A regression with failed Compose rendering initially refused the attach, and now proves no rendering or replacement is attempted.
- Dev Container review follow-up: default Dev Container lifecycles now resolve their declared mount arrays through read-configuration, including JSONC and host-variable substitution. Staged dotNetBench/rustBench mount fixtures initially failed; added startup, stopped repair, and failed-metadata-read coverage. A real canonical dotNetBench configuration read returned 22 expanded mounts without running initialization or creating a container.
- Cache review follow-up: known Wave binds can be reconstructed from deterministic host/user mappings if a disposable overlay cache is absent. Added uncached startup, explicit repair, missing-original refusal, and unknown-target rejection fixtures; validation does not regenerate files.
- Final mapping/environment review follow-up: include generated agents/pi directories in the deterministic fallback and use the same bench-root env-file fallback for read-only bind rendering as for project resolution/creation. Added positive staged-directory and generic-layout fixtures; the directory fixture failed before the fix.

The helper suite initially failed on both this feature and unchanged main: when executed inside a bench, its MCP helper selected the mounted shared registry rather than the expected temporary HOME fixture. Explicit `WORKBENCHES_SHARED_MCP_HOME` and host rendering context now keep the test independent of the execution surface and prevent mock routing updates from reaching the real registry. No production MCP routing behavior was changed.

## Preserved runtime and source state

Read-only inspection before publication confirmed that py-bench retained container ID prefix `988cd7d35898`, was stopped, and had init enabled. cloud-bench retained ID prefix `4bd57d827ebc`, remained running, and had init enabled. No container, image, daemon, volume, or WSL restart was performed by this implementation.

The canonical checkout remained on base commit `6952c6f92b59f0923bb4d143feb6b66a99c677a9` with its eight unrelated pending bench gitlink changes preserved. They are not part of this feature. Installed Wave bench links point to the canonical shared launcher, not the isolated feature worktree.

## Publication and remaining boundary

The user approved opening and landing the tested source PR after checks and review pass. Publication must also update the canonical launcher used by Wave. CI and exact-head external review are verified during that publication; this file records the local implementation checks, not a claim that they have already completed remotely.

Recreating the stopped py-bench remains a separate explicit operation. The source fix provides diagnosis and the `--repair` recovery path; publishing it does not repair Docker Desktop's stored mapping in an existing container.
