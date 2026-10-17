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
benches are not all certified by that run. Live Windows/WSL testing on Eagle
is still pending SSH authorization.
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
