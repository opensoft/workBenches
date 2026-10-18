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

**Windows/WSL acceptance passed all 17 required live cases** on Eagle,
2026-10-18 UTC, at product commit
`3cf17527d94e43c429cced43f150b44d74e8c60d`. The native host was Windows 11 Pro
`10.0.26300.9711`, WSL `2.7.14.0`, Ubuntu `24.04.4`, Docker Desktop
`4.93.0 (240920)`, client/engine `29.8.1`, and Compose `5.5.1`. Native WSL
commands used a private home and disposable engine `28.5.2` for fixed-name
benches, preserving the existing workstation. This was real WSL acceptance,
with shared/build cache, rather than container-only platform evidence.

Coverage includes fresh frozen-source Codex/pyBench installation, existing
updates, ordinary Wave and Bash/Zsh startup, loading/queued cancellation, a
real failed npm update, component removal/reinstallation, Tools/Vault readiness,
and refusal to overwrite modified source. Fresh pyBench installation took
231.31 seconds; bench update took 146.75 seconds. Python reports `3.12.3` and
Codex `0.163.0`. All 104 original containers, 278 image/tag records, and 2,142
volumes remained present; all 16 original credential hashes and three shell/Git
hashes matched. Private project/credential/prompt witnesses also retained their
bytes, modes, and modification times. The eight assembly submodules stayed
clean at their recorded pins.

Release fixes correct the WSL Docker socket group, public helper-file modes,
unavailable Snap-daemon inventory, callback-broker cleanup, image depth, and
stale descendant reuse. A separate live migration retained the old 113/128-layer
bench/user images and successfully replaced them with 105/120-layer images,
then started the bench and passed its launch check. Bench exec checks confirmed
`brett` as `1000:1000`, Docker group `1001`, passwordless sudo, and the correct
project mount. Tools uses `1000:1000` plus socket group `1001`; Vault is healthy
as `1000:1000`, with op `2.40.0`, bw `2026.9.1`, and Azure CLI `2.91.0`.

The exact product commit passed the source-lock check, image-layer regression,
12 install-friction tests, all four Workstation Setup CI jobs, Release source
freeze, shared-image regression, project-command, OpenSpeckit, and CodeQL.
Docker Desktop and WSL were never restarted, global Docker configuration was
not changed, and original benches were not stopped. Earlier cold-install
timeouts and OverlayFS writeback waits remain recorded; running as root did
not resolve those storage waits. The successful fresh install used cached
builds. Eagle's broken higher-priority npm `10.9.3` was left unchanged; only the
private QA PATH selected distro npm `10.9.7` with Node `22.22.2`.
Exact commands, per-case timings, versions, failures, and limitations are in the
[Eagle QA record](docs/release-1.5.0.md#descendant-refresh-and-fresh-acceptance--2026-10-18-utc).
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
- Windows/WSL coverage uses an existing WSL 2/Desktop setup and cached builds;
  cold OS provisioning, every pinned bench, GPU workloads, and paid AI
  authorization are not certified. macOS remains unvalidated.
- pyBench's pip install reports Semgrep/OpenTelemetry dependency conflicts;
  Semgrep runtime behavior is outside the validated Python/Codex path.
- Private bench repositories require authorized GitHub access. HTTPS fallback
  does not bypass repository permissions.
- A Keycloak login does not automatically unlock other vaults or create AI
  provider tokens. Single-login recovery and the Flutter apps are deferred.
- Keycloak remains in the QA environment; production migration is deferred.
- Selecting an older source tag does not automatically downgrade installed
  tools, containers, or user data.
