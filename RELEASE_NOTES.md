# workBenches 1.6.0

This release adds multi-identity Profiles management and opt-in company
credential workflows, including broker-controlled discovery, publication,
recovery, workstation synchronization and CPC maintenance.

It also includes interrupted-write recovery, retryable maintenance outages,
collision-safe identity profiles, managed Claude lane startup synchronization,
the complete pinned openRepoTools payload, and Arch-family shell installation
support. All 12 bench source pins are retained. The v1.7 guided wizard remains
on its separate development branch.

Brett accepted the merged setup on Raven at `5407ee9` on 2026-10-23. Source,
setup, launcher and estate CI passed on that commit; broker/client fixtures
passed 46 tests without skips. These results do not certify the full native
and live authentication/provider release cases. Final publication still needs
the exact version-stamped commit's release evidence under the repository gate.

Company credential sharing requires explicit configuration and approved
provider modes. Unsupported modes remain disabled; existing credentials are
not automatically migrated or published.

See [the full release notes](docs/release-1.6.0.md) and
[the release validation procedure](docs/release-automation.md).
