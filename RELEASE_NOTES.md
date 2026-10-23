# workBenches 1.6.0-rc.1 — Frozen release candidate

Frozen on 2026-10-19 for testing. This is not the stable/latest product release.
v1.5.0 remains stable. Company credential sharing and new provider modes are not
activated by this release preparation.

## Included

- Multiple personal/company identities and reusable verified GitHub account links.
- Keyboard Profiles management and independent company sign-in sessions.
- Opt-in company credential broker/client, versioned publication, workstation
  synchronization, and CPC maintenance.
- Stable setup/launcher and release-validation fixes through main `5880c09`.

Feature input is `edefc67c340603a783876cdf1b424b3d9f1093db`. The integrated
candidate retains all 12 existing bench repository source pins. No existing
workstation checkout, credential, or running bench is replaced by this freeze.

## Validation boundary

Fixture and regression tests do not establish real provider approval. Real
GitHub/company browser authentication, workstation acceptance of the new Profiles
flows, supported provider-mode validation, and live managed-identity Key Vault
deployment remain gates for stable 1.6.0. Examples and unsupported modes remain
disabled. The exact candidate's test/CI evidence must be recorded separately
from earlier implementation tests.

See [candidate scope and gates](docs/release-1.6.0-rc.1.md) and
[the release process](docs/releases.md). Published tags are immutable. A stable
1.6.0 tag requires its own final reviewed and validated commit.
