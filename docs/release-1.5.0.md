# v1.5.0 — Reliable workstation setup

Scope approved by Brett on 2026-10-15. This records the release contents and
acceptance criteria. Publication requires the validation gates below and an
annotated tag on the final tested commit.

## Approved scope

| Area | Release contents |
| --- | --- |
| Installation | Fresh clone with SSH preference and HTTPS fallback; guided Docker and Windows/WSL requirements. |
| Setup containers | Managed Tools and Vault containers with accurate Up, Down, and Missing states; Python, jq, Git, and curl run in Tools during setup. |
| Bench management | Install, update, and remove selected benches and tools while preserving projects and credentials. |
| Credentials | Optional Keycloak connection plus existing Azure Key Vault, Bitwarden/Vaultwarden, and 1Password recovery. Provider sign-in and unlock remain separate. |
| TUI | Immediate startup, background readiness checks, updates to changed lines, clear service actions, and reliable cancellation that preserves selections. |
| Releases | Visible product version, exact repository pins, frozen-source installation, annotated release tags, and release notes. |

The source-lock candidate records 12 repositories in
[`config/release-lock.json`](../config/release-lock.json). These pins identify
sources, not a certification that every bench has passed a complete install.
External package versions and mutable image references are not fully locked.

Only fixes needed to deliver or validate this scope enter the 1.5.0 candidate.
Any pin change requires review and validation of the revised candidate.

## Deferred

- One Microsoft/Keycloak approval recovering credentials without separate
  provider sign-ins; identity-to-credential-broker integration belongs in a
  later feature release. Optional Keycloak account login remains in 1.5.0.
- Flutter desktop/mobile apps.
- Additional vault providers.
- Production Keycloak migration.
- Complete package/image reproducibility.

## Release gates

Local development evidence already recorded:

- [x] Nine release/version checks passed, including execution through Tools.
- [x] All 21 setup regression suites passed.
- [x] Declared Tools runtime acceptance passed, including Vault
  Install/Connect/cancel/sign-in/sign-out with queued changes preserved.
- [x] First TUI paint measured at 0.077 seconds on Raven; readiness at
  3.563 seconds. The measurement selected nothing and exited with Q.

These results precede the release commit. The following remain required:

- [ ] Review and commit the candidate, including its version and source lock.
- [ ] Pass the Release source freeze and full Workstation Setup CI checks on
  the committed candidate; repeat on the final merge commit if it differs.
- [ ] Complete a fresh-workstation install using frozen-source mode.
- [ ] Complete existing-workstation upgrade, add/remove, and cancellation
  checks; confirm projects, existing credentials, and unrelated resources remain.
- [ ] Complete a real Keycloak login and a real recovery from a supported vault.
  Automated account/provider responses so far are fixtures.
- [ ] Complete live QA for every platform advertised as supported. Raven/Linux
  has development coverage; Windows/WSL and macOS still need live workstation QA.
- [ ] Prepare final release notes with the tested commit, validation evidence,
  platform coverage, and known limitations.

After these gates pass, follow [the release process](releases.md): merge the
approved candidate, validate the exact final commit, create the annotated
`v1.5.0` tag, wait for tag CI, and publish the release. Do not move a published
tag. Post-release fixes use `1.5.1`; compatible feature additions use `1.6.0`.
