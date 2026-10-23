# workBenches 1.6.0

Final release preparation for the profile and company credential workflows
merged in [PR #167](https://github.com/opensoft/workBenches/pull/167).
Publication remains subject to the [release validation gate](release-automation.md).
The existing v1.6.0-rc.1 through rc.3 tags are unchanged.

## Included

- Multiple personal and company identities, reusable verified GitHub account
  links, and keyboard Profiles management with independent company sessions.
- Opt-in company credential discovery, versioned publication and recovery,
  workstation synchronization, and CPC health and refresh maintenance.
- Recovery of interrupted credential publication and local writes, retryable
  maintenance outages, and collision-safe profiles for multiple identities.
- Managed Claude launch synchronization before lane startup, retaining the
  managed credential lease in the launched session.
- The complete pinned openRepoTools payload, deferred prompt-hook installation
  and reconciliation, and Arch-family host-shell installation support.

All 12 bench source revisions remain identical to the tested candidate. This
release preparation changes version metadata and notes only; the guided wizard
and Harness/Tools catalog work continue separately in v1.7.

## Validation evidence

Brett tested the merged setup on Raven at
`5407ee97d7fb17a697c22ff1b7bad6d26f9a8afd` on 2026-10-23 and reported
“this passes test.” That acceptance covers the setup flow he exercised.

The integrated fixes passed 46 broker/client credential-sync tests without
skips, the Profiles and multi-identity regressions, and all 15 launcher suites.
[Main CI run 40017716135](https://github.com/opensoft/workBenches/actions/runs/40017716135)
passed the source, setup, launcher and estate CI suites. This was CI-mode
evidence, not a full protected release run. The final version-stamped commit
requires its own source-lock checks and release evidence.

Full native Arch/WSL, two-account browser authentication, company tenant
isolation, and approved live provider/broker/Key Vault/CPC acceptance remain
required by the publication gate. Fixture tests and manual setup acceptance
do not establish that these live cases passed.

## Credential deployment boundaries

Company synchronization and managed credential paths require explicit opt-in.
Opening Profiles does not migrate or publish existing credentials. The broker
enforces administrator-controlled use, publication and maintenance grants;
workstations and CPC call the broker rather than accessing Key Vault directly.
Company broker authorization failures do not fall back to direct-user vault
access. Unsupported provider modes and disabled examples remain disabled.

Hourly workstation metadata checks and weekly CPC health sweeps are defaults;
actual token refresh follows provider expiry and rotation requirements. These
cadences do not certify that a provider permits sharing an OAuth session.
Validate each approved provider mode before deploying it.

See [Profiles](profiles.md), [company credential synchronization](company-credential-sync.md),
and [the release process](releases.md) for configuration and installation.
