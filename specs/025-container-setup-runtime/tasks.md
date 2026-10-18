# Tasks

- [x] Tools image, ownership checks, health, auto-start and scoped command shims.
- [x] Native-host discovery/actions and Docker-only bootstrap integration.
- [x] Docker/Tools/Vault Up/Down/Missing inventory and TUI actions.
- [x] Optional Vault runtime and existing provider-recovery integration.
- [x] Unit, real minimal-host/container/TUI checks and documentation.

Validation on Raven (Linux), 2026-10-15:

- All 20 regression suites passed, including existing cancellation, consent,
  application removal, credential mapping, Azure fallback, and project install.
- Declared `tools-runtime` service passed with Python/jq/Git/curl absent from
  the simulated host PATH: real command transport, native application removal,
  native bench setup/Compose adapter, readiness/restart, launcher P/Q, and Vault
  isolation. No selected bench was built or launched by these fixtures.
- Declared credential fixture passed Azure upload/download and cancellation plus
  six Bitwarden/1Password recovery/cancel scenarios; private files/sessions were
  absent after each job. All credentials were fake.
- Requirements layouts rendered at 60, 80 and 100 columns; the component column
  renderers remain byte-identical to the starting commit.
- Bash syntax, Python compilation, YAML parsing and `git diff --check` passed.
- macOS Docker Desktop and Windows/WSL need live workstation QA; Linux is the
  platform covered by this run.

Follow-up service buttons:

- [x] Shared Install/Start/Check labels in bootstrap and Requirements rows.
- [x] Immediate Enter/Space service actions, preserving component selections.
- [x] Vault Connect/browser approval, accurate signed-in state, and local sign-out.
- [x] Focused state/action, browser-origin, headless, and cancellation unit checks.
- [x] Real TUI Install/Connect/cancel/sign-in/sign-out acceptance and layout review.

Service-button validation:

- All 20 regression suites passed. Focused final checks passed 16 Requirements,
  14 Docker-prerequisite, and 13 account cases, including no duplicate Docker
  Install/Start permission question after the explicit action.
- The declared runtime service exercised a real Vault Install button and real
  terminal Ctrl+C during a fixture login, then successful fixture login and local
  sign-out. A queued bench remained selected and was never installed. No real
  Microsoft login or organization settings were changed by the tests.
- Rendered button states fit 60/80/100-column layouts. The three component
  column renderers remain unchanged.

Main-screen Vault action correction:

- [x] Show Vault’s current [V Install/Start/Connect/Sign out] action on the main
  status strip, rather than only on the Requirements page.
- [x] Wrap service summaries without dropping the action on narrow terminals.
- [x] Route V/v directly to the same action, preserving section, focus, and queued
  component selections; display connection/cancellation notices on the main UI.
- [x] 18 Requirements checks passed, including every Vault action at 36, 60,
  80, and 100 columns. Main-screen Connect/Sign out previews reviewed.
- [x] Declared runtime acceptance passed for main-screen V Install → Connect →
  Ctrl+C → sign in → sign out. Queued bench selection was preserved, and only
  test-created containers/network were removed. Account responses were fixtures.

Immediate-start follow-up:

- [x] First draw uses only Bash/OS metadata, with yellow blinking loading states.
- [x] Background atomic status/catalog import, one Tools inventory session, and
  responsive timed keyboard input; required actions are gated while unknown.
- [x] Preserve selections/focus; clean owned probes and private snapshots on Q.
- [x] Batched native tool checks, with cache cleared before mutation verification.
- [x] Stalled-Docker, no-discovery-during-render, and snapshot-preservation tests.
- [x] All 21 regression suites and the declared Tools runtime service passed,
  including main-screen Install/Connect/Ctrl+C/sign-in/sign-out with a queued
  bench preserved. Test-created containers and networks were removed.

Measured on Raven: first TUI 0.075 seconds, all checks ready 3.555 seconds.
The measurement opened setup, selected nothing, and exited with Q (130).

Redraw correction:

- [x] Buffer frames and write only changed lines; unchanged frames emit nothing.
  Keep the header stationary, erase shortened/removed rows, and repaint after
  external helpers or width changes. Remove the duplicate initial draw and
  suppress identical background status records.
- [x] Remove the extra block above the wordmark's f; review the rendered header.
- [x] Six async/render checks and all 21 regression suites passed. Declared Tools
  runtime acceptance passed for immediate startup, Q cancellation, and the full
  Vault Install/Connect/Ctrl+C/sign-in/sign-out flow with queued changes retained.
  Its terminal reader now checks the visible screen instead of assuming every
  update repeats unchanged rows.

After this correction, Raven's first TUI remained 0.075 seconds; readiness took
3.563 seconds. The measurement selected nothing and exited with Q (130).
