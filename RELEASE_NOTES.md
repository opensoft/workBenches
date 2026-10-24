# workBenches 1.6.1

This patch retains the tested v1.6 setup and fixes private GitHub bench cloning
through the workstation's GitHub CLI credentials when Git runs inside Tools.
Existing SSH access and Git credential helpers remain in place. A retry also
finishes a previously interrupted bench submodule initialization.

All 12 bench source pins and the v1.6.0 identity/company workflows are retained.
The v1.7 guided wizard remains on its separate development branch. Company
identity-provider registration guidance is a v1.6.2 follow-up; this patch keeps
the existing administrator-enrollment and issuer/client-ID sign-in behavior.

Brett accepted the v1.6.1 candidate on Raven on 2026-10-24 and requested release
as tested. The private-auth fix at `e07ac4c` has passing Workstation Setup,
source-freeze and CodeQL CI and an exact-head Codex review without findings.
These results and manual acceptance do not certify unexecuted full native/live
provider gates. Publication evidence and any explicit owner-authorized release
exception must be recorded honestly; no missing live result is marked passed.

Company credential sharing requires explicit configuration and approved
provider modes. Unsupported modes remain disabled; existing credentials are
not automatically migrated or published.

See [the patch release notes](docs/release-1.6.1.md) and
[the release validation procedure](docs/release-automation.md).
