# Acceptance and qualification

Open setup → Profiles → Personal/company or an identity → **F Manifest files**.
Choose local JSON or Connect OneDrive/Google Drive. Cloud login runs from the
Tools image with a temporary callback. Select a provider manifest, review the
resulting account names/emails, confirm and test a repeat pull. Profile setup is
separate from AI credential recovery. Follow docs/cloud-profile-import.md for
Google app configuration and supported path/file formats.

Use declared workstation test containers for the task commands and Compose
tools-runtime for the real daemon/native boundary. Use private image tags when
testing locally, preserving user Tools/Vault containers and production tags.
Fixtures never open a real provider account or inspect real credentials.

Local evidence: 33 cloud-focused, 16 Profiles, 14 multi-identity,
18 requirements, 8 async and 51 release-automation tests passed (140 cases).
The initial real Tools suite passed Rclone shim/version, native browser callback,
host-loopback-only relay, runtime lifecycle, real TUI and all 11 Vault/Profile
queue/cancellation stages. The stronger actual-Rclone test also passed: the
temporary login container used native browser RPC, its real Microsoft consent
redirect requested read-only scope, a synthetic denied-consent callback completed
the real Rclone flow, and pending config/container cleanup preserved old state.
It made no real provider request or account login. Actual local Claude/Codex
launcher materialization preserved synthetic default credentials and created no
profile credentials. Strict OpenSpec and whitespace checks pass. Exact-head PR
review/CI remain T004 acceptance work; no live provider qualification is claimed.

Review follow-up reserves profile paths, legacy migration locations, orphan
homes and future family directories as well as case-insensitive launcher names/
aliases. Tests cover the wrong-account reuse cases and preserve credential
canaries. Remote input remains bounded to 1 MiB; the composed local aggregate
has a separate 8 MiB read/write limit, checked before replacement. A compact
2,000-profile source can be re-imported after its pretty local copy exceeds
the remote-input bound. Subprocess audit comments were reviewed against fixed
argv construction, validated inputs and a literal-shell-syntax regression.

## PR acceptance — 2026-10-25

[PR #230](https://github.com/opensoft/workBenches/pull/230), stacked on #215,
implements the bounded Tools connector. Final implementation head
`922ab07701f30bd402e2a8be4b40ad5024eda50c` passed:

- [Workstation Setup](https://github.com/opensoft/workBenches/actions/runs/40228335252):
  regression, actual Tools/runtime OAuth boundary, credential images and lifecycle.
- [Release fixtures](https://github.com/opensoft/workBenches/actions/runs/40228335256):
  source, setup, launchers, estate and CI-mode evidence gate.
- [Broker/client/CPC](https://github.com/opensoft/workBenches/actions/runs/40228335183).
- Exact-head Codex review completed with no further findings; the credential-home,
  case-insensitive alias and aggregate-size findings are fixed and their review
  threads resolved. Subprocess audit threads have explicit boundary analysis and
  a literal-argument regression; no unresolved review thread remains.

This documentation-only acceptance commit changes no runtime. All four tasks are
complete. No stable release or user Tools/Vault replacement was performed.
Google OAuth app configuration and attended successful Microsoft/Google consent,
file pull and launch qualification remain deployment prerequisites; synthetic
denial and local launcher tests are not live provider acceptance.
