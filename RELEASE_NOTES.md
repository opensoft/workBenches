# workBenches 1.5.0 — Reliable workstation setup

Draft: publication is pending the remaining gates in
[`docs/release-1.5.0.md`](docs/release-1.5.0.md).

## Changes

- Setup displays the TUI immediately and checks requirements in the background.
  Updates replace changed lines without clearing the whole screen.
- Docker, Tools, and Vault show Up, Down, or Missing, with state-dependent
  Install, Start, Check, Connect, and Sign out actions.
- Python, jq, Git, and curl run in the managed Tools container during setup.
  Application detection and explicit installation/removal still target the host.
- Optional Keycloak browser approval preserves queued selections; account login
  remains separate from provider vault authorization and unlock.
- Azure Key Vault, Bitwarden/Vaultwarden, and 1Password recovery use managed
  credential-access tooling with private, temporary per-job sessions.
- Install/update/removal and cancellation preserve projects, existing
  credentials, local source work, and unrelated Docker resources.
- Version reporting, a 12-repository source lock, and annotated release tags
  establish frozen-source deployments beginning at v1.5.0. Frozen installation
  refuses to overwrite selected modified checkouts; removal preserves local work.
- GitHub cloning prefers configured SSH access and falls back to HTTPS.
- Shared-service readiness checks correctly locate Vibe Annotations while
  setup runs through Tools, avoiding a false unhealthy-service warning.
- Native installers honor their requested timeouts, including long bench builds;
  project setup can use the host-command bridge from isolated Python.
- Tools uses the actual Docker socket group on Windows/WSL Docker Desktop;
  existing managed helpers are recreated to apply the corrected access group.

## Validation and platforms

The candidate's Release source freeze, Workstation Setup, shared-image
regression, project-command, OpenSpeckit, and CodeQL checks are available on
[release PR #157](https://github.com/opensoft/workBenches/pull/157).

Linux development validation includes 10 release/version checks, 21 setup
regression suites, and declared container/runtime/lifecycle acceptance. All 11
frozen workstation acceptance cases passed on `c880e04`, with a fresh home and
anonymous HTTPS clone using cached shared base images in an isolated engine.
The selected pyBench/Codex path passed installation, startup, update, cancellation,
and removal checks with local work and credentials preserved. Other pinned
benches are not all certified by that run.

Live Windows/WSL QA was attempted on Eagle (Windows 11 Pro
`10.0.26300.9711`, WSL `2.7.14.0`, Ubuntu `24.04.4`, Docker Desktop `4.93.0`,
engine `29.8.1`). Candidate `0367f1b` exposed a Docker socket-group permission
failure in Tools. The fix candidate `fa7cd5a29c977a0a6f97c04a4e5fa7f849f5ccd9`
passed the source-lock check and 54 focused tests in the declared pyBench.
Native Windows WSL guidance and real WSL loading-screen cancellation passed;
the latter exited 130 in 0.49 seconds. Full frozen installation, helper
readiness, selected pyBench/Codex startup and live update/removal/preservation
are **blocked** by Docker helper creation and image preparation that did not
complete. Existing container IDs, image tags, volumes, inventoried credentials
and shell/Git configuration were preserved during this attempt.
**The Windows/WSL gate is still open.**
QA-only engine/regression cleanup also exceeded bounded deadlines; the retained
resource names are listed in the QA record for later cleanup.
A subsequent retry on `9eb94de` confirmed the corrected helper identity
`1000:1000` plus socket group `1001`, but startup exceeded 60 seconds.
Minimal mapped-user and root probes both timed out before producing `id`
output; changing to root did not resolve the observed startup stall.
Further diagnosis located the stalls in OverlayFS unmount filesystem writeback.
Docker's API and existing benches remained available. A later fresh full Tools
helper **passed** startup and Docker access in 21 seconds as `brett`
(`1000:1000`, supplementary socket group `1001`), without a Docker restart.
This verifies the socket-group fix live; full Windows/WSL acceptance remains open.
Functional follow-up found that a private checkout's 0600 source modes made
root-owned helper files unreadable to the mapped user. Tools and credential
images now normalize public code permissions and check helper access in their
health probes. On `81bde3b`, rebuilt Tools passed Docker access, Python import,
the real WSL callback and npm bridge; 40 focused checks passed. The CLI install
attempt before this fix made no selection because inventory was blocked, so
CLI and full workstation lifecycle acceptance are still pending.
Exact commands, versions, failures and remaining cases are recorded in the
[Eagle QA record](docs/release-1.5.0.md#eagle-windowswsl-acceptance--2026-10-17).
The real Vaultwarden server/CLI recovery test passed with verified TLS and a
generated, nonbillable test credential; no production credential was required.
Real Keycloak browser approval, local sign-out, and reconnect passed on
Raven/Linux on 2026-10-17 using the account helper at `f7614da` against the
OpenSoft QA realm. Both approvals confirmed identity through userinfo and
reported signed in; local sign-out cleared the workstation session.

macOS is **unvalidated for 1.5.0**: no Mac is available for live workstation QA.
Existing macOS code paths remain present, but this release does not claim a
validated macOS installation.

## Installation

After v1.5.0 is published, install the tagged version using the commands in the
[release guide](docs/releases.md#install-a-published-release). Initial bootstrap
needs Git and a download method; Docker and a host Bash/OS environment remain
prerequisites. The four setup tools then run in Tools. First-use image preparation
can take several minutes while the TUI stays available.

## Known limitations

- Source revisions are frozen; external package managers, vendor installers,
  separately fetched integrations, and mutable image references are not all
  pinned. This is not a byte-identical workstation snapshot.
- Private bench repositories require authorized GitHub access. HTTPS fallback
  does not bypass repository permissions.
- A Keycloak login does not automatically unlock other vaults or create AI
  provider tokens. Single-login recovery and the Flutter apps are deferred.
- Keycloak remains in the QA environment; production migration is deferred.
- Selecting an older source tag does not automatically downgrade installed
  tools, containers, or user data.
