# Verification

Select `SPECIFY_FEATURE=033-company-connection-wizard` and
`SPECIFY_FEATURE_DIRECTORY=specs/033-company-connection-wizard`.
Run tasks' commands inside declared Tools/workstation test containers.

User walkthrough: add company → Sign in → import company setup or open admin
guide → review issuer/application ID → discovery check → confirm → optional
descriptor export → existing browser/device login. Decline/back/cancel must
preserve existing configuration, saved identities and queued software.

Test exported descriptors only with disposable fixtures or explicitly authorized
administration. Fixture success does not register a client or certify an actual
provider deployment. Record local/CI results separately from attended sign-in.

## Local evidence — 2026-10-24

Declared workstation test container: 19 company-connection, 15 account,
16 Profiles, 14 multi-identity, 10 release-version, 51 release-automation,
18 requirements, 6 async and 43 guided-flow cases passed (192 total).
Git-aware suites used the source worktree with its read-only common Git metadata;
async fixtures used writable disposable logs. No credentials were mounted.
OpenSpec strict validation passed in the declared developer bench image.

The setup manifest now includes company-connection and the Workstation Setup
workflow (`credential-recovery.yml`) watches its runtime/test paths. Release
metadata is development-only. Real Tools/native integration and PR review/CI
are recorded below when complete; fixture success is not live-provider sign-in.

Declared `tools-runtime` Compose service passed end to end with isolated test
image tags: native company browser/clipboard RPC, native GitHub verification,
Docker/host adapters, Tools restart, real initial TUI paint, all 11 Vault/Profile
button-flow stages with a disposable bench queue, and Vault health/restart/narrow
mounts. No running user bench or production credentials were used or changed.

The feature is based on the final 1.6.1 candidate. Integration must preserve the
separate stable-release sequence; this development version must not replace main
before the requested 1.6.0/1.6.1 publication is resolved. PR CI and exact-head
review are recorded below.

## PR acceptance

[PR #215](https://github.com/opensoft/workBenches/pull/215) implements
[issue #213](https://github.com/opensoft/workBenches/issues/213) for milestone
1.6.2. For implementation head `04882bcd3f53ca5eb4116aab3bc58dc149295391`:

- Exact-head Codex review completed with no findings on 2026-10-24.
- [Workstation Setup run 40118251848](https://github.com/opensoft/workBenches/actions/runs/40118251848)
  passed regression, Tools runtime, credential images and component lifecycle.
- [Release fixture run 40118251821](https://github.com/opensoft/workBenches/actions/runs/40118251821)
  passed source/setup/launcher/estate suites and its CI-mode evidence gate.
- [Broker/client/CPC run 40118251849](https://github.com/opensoft/workBenches/actions/runs/40118251849)
  and the source-freeze check passed.

This evidence closes T004's implementation acceptance. This final documentation
commit records the already-reviewed implementation; it changes no runtime.
Protected native/live release QA and attended provider registration/sign-in
remain outside fixture acceptance. No v1.6.2 stable release is authorized or
claimed here, and the PR stays stacked until the stable-release sequence resolves.
