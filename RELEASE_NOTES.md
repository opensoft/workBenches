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
- Developer-base configuration steps share a filesystem layer so personalized
  benches leave room for Docker's container layers.
- Selected bench setup rebuilds through its declared image builder, refreshing
  cached bench images when the shared family base changes.

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

Live Windows/WSL QA is continuing on Eagle (Windows 11 Pro
`10.0.26300.9711`, WSL `2.7.14.0`, Ubuntu `24.04.4`, Docker Desktop `4.93.0`,
engine `29.8.1`). On product commit
`76555991d8ea40d51009687fbc22ba7cd39b4748`, the native WSL test passed Tools
readiness, loading cancellation, an empty selection, real Codex installation,
update, queued cancellation, failed-update handling, removal, reinstallation,
host Bash/Zsh startup, and full managed Vault readiness. Codex reports `0.163.0`.
The selected pyBench's cold-install attempt exceeded its one-hour QA deadline;
final preservation checks passed, giving 12 passed cases, one timed-out install,
and four dependent cases not run. The cache-assisted retry built the selected
images but failed container creation with `max depth exceeded`: the personalized
image had 128 filesystem layers. The recipe fix removes eight configuration
layers and has passed its regression check. A fresh full native acceptance run
on `fdbb5940d40b92f42d5499c8364a415b7ae7ffb4` passed all eleven host cases but
exposed stale descendant-image reuse. The native runtime now refreshes the
declared bench image before startup; live migration and fresh acceptance remain
required. **The Windows/WSL gate remains open** until bench installation,
startup, update, removal, and the local-work guard pass.

Release fixes correct the WSL Docker socket group, public helper-file modes,
unavailable Snap-daemon inventory, and callback-broker cleanup. Tools runs as
the mapped user (`1000:1000`) with supplementary socket group `1001`; running
as root did not resolve the separate Docker storage stalls. Full Vault now
starts successfully as the mapped user, with `op 2.40.0`, `bw 2026.9.1`, and
Azure CLI `2.91.0`. All 20 setup regression suites passed, and the subsequent
clean QA-driver commit `e3f2ea3` passed the source-lock check and 41 focused
release, service, and component checks.

Docker intermittently waits in OverlayFS unmount filesystem writeback while
its API and existing containers remain responsive. Vault creation alone took
twelve minutes; the pyBench test fell back to a cold local shared-image build.
Testing continues without restarting Docker Desktop or WSL, changing global
Docker configuration, or stopping original benches. Eagle's higher-priority
npm `10.9.3` is broken; only the QA prefix selects the working distro npm
`10.9.7`. Original credential and shell/Git hashes matched after the completed
host lifecycle cases; final checks follow the bench cases.
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
