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
