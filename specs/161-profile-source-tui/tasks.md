# Implementation tasks

- [X] T001 Add native host file selection/manual fallback and bounded local/HTTPS/selected-account GitHub sources with grant filtering.
- [X] T002 Add personal/company source panes, provider/profile review, conflict-safe import and saved-source refresh; integrate feature 160 cloud support.
- [X] T003 Keep company onboarding available despite default credentials, scope recovery to selected company/personal profiles and add failure/platform/PTY regressions.
- [X] T004 Wire declared regression suites, document actual support/remaining attended acceptance and verify affected setup/Tools boundaries.


Verification: 243 Python tests passed across profile sources (26), cloud imports
(33), Profiles (16), multiple identities (14), guided recovery (43), requirements
(18), async setup (8), service readiness (8), release versioning (13), release
automation (51) and Azure runtime (13). Four shell suites passed: Key Vault
restore/canonical-alias checks, selected AI recovery, cancellation and bench
status. The declared tools-runtime Compose service passed with the optional
Vault image smoke test disabled. Read-only GitHub catalog/grant qualification
passed; no production manifests or vault credentials were applied/read.

Remaining release acceptance: attended desktop dialogs on supported platforms,
real provider cloud consent with administrator app configuration, and approved
live Azure restore plus provider launch. These are not inferred from fixtures.
No stable release is published by this implementation.

Source-lock validation also passed in an isolated committed snapshot of the
implementation. The development checkout retains its prior cloudBench pin drift
and generated build state; it is not a frozen release candidate.
