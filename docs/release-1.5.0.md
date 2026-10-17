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

- [x] Ten release/version checks passed, including frozen removal with local work.
- [x] All 21 setup regression suites passed.
- [x] Declared Tools runtime acceptance passed, including Vault
  Install/Connect/cancel/sign-in/sign-out with queued changes preserved.
- [x] First TUI paint measured at 0.077 seconds on Raven; readiness at
  3.563 seconds. The measurement selected nothing and exited with Q.
- [x] Release QA found and fixed a Tools loopback readiness error: Vibe
  Annotations is queried from its own container with a bounded HTTP request.
  Six focused readiness checks plus actual status and new-service startup
  checks passed in the isolated workstation engine.
- [x] Fresh-install QA found and fixed a native-command timeout that stopped
  bench builds after 30 seconds, and an isolated-Python import failure in project
  setup. Declared Tools runtime acceptance passed, including a 31-second native
  command, a short-deadline cancellation, and isolated-Python host discovery.

These results precede the release commit. The following remain required:

- [x] Review and commit the candidate, including its version and source lock.
  Candidate PR: [#157](https://github.com/opensoft/workBenches/pull/157).
- [x] Pass the Release source freeze and full Workstation Setup CI checks on
  candidate `c880e04`; the PR also passed project-command, OpenSpeckit,
  shared-image regression, and CodeQL checks.
- [ ] Repeat required CI checks on the final merge commit.
- [x] Complete a fresh-workstation install using frozen-source mode.
  All 11 declared workstation acceptance cases passed on `c880e04`, using a
  fresh home and anonymous HTTPS clone in an isolated Docker engine with cached
  shared base images. The pyBench build/install took 77.31 seconds; its Python,
  Codex, and Wave shell startup checks passed. This validates the selected
  pyBench/Codex path, not every repository in the source lock.
- [x] Complete existing-workstation upgrade, add/remove, and cancellation
  checks; confirm projects, existing credentials, and unrelated resources remain.
  Acceptance covered repeat setup, CLI update, failed CLI update, and bench
  removal with local source work. Credentials, shared images, and source pins
  were preserved; the separate component lifecycle acceptance also passed.
- [x] Complete real Vaultwarden recovery using the actual server and Bitwarden
  CLI with verified TLS, a generated test account, and a generated nonbillable
  AI credential. The private profile received the expected credential bytes.
- [x] Complete a real QA Keycloak login. On Raven/Linux, 2026-10-17, the
  account helper on candidate `f7614da` completed real browser device approval
  against the OpenSoft QA realm, confirmed identity through userinfo, and
  reported signed in. Local sign-out reported sign in; a second real browser
  approval completed reconnect and restored signed-in status. This covers the
  account helper flow; no new TUI acceptance run was performed.
- [ ] Complete live QA for every platform advertised as supported. Raven/Linux
  has development coverage; Windows/WSL QA on Eagle is blocked by live Docker
  operations (see below).
  No Mac is available: macOS must be identified as
  unvalidated in 1.5.0 rather than advertised as a validated platform.
- [ ] Prepare final release notes with the tested commit, validation evidence,
  platform coverage, and known limitations.
- [x] Protect version tags against updates/deletion: active repository ruleset
  **Immutable workBenches releases**, covering `refs/tags/v*` without bypass actors.

After these gates pass, follow [the release process](releases.md): merge the
approved candidate, validate the exact final commit, create the annotated
`v1.5.0` tag, wait for tag CI, and publish the release. Do not move a published
tag. Post-release fixes use `1.5.1`; compatible feature additions use `1.6.0`.

## Eagle Windows/WSL acceptance — 2026-10-17

Initial candidate: `0367f1b70749b346762f57067bb0ad9e1599c3d9`.
Fix candidate tested by the focused checks:
`fa7cd5a29c977a0a6f97c04a4e5fa7f849f5ccd9`.
The Windows/WSL release gate remains **open** until the live cases below pass.

### Environment and isolation

- Eagle: Windows 11 Pro `10.0.26300.9711`, Windows PowerShell
  `5.1.26100.9711`, Windows Git `2.51.0.windows.2`, Git Bash `5.2.37`.
- WSL `2.7.14.0`, Ubuntu-24.04 running as WSL 2, Ubuntu `24.04.4 LTS`,
  kernel `6.18.33.2-microsoft-standard-WSL2`; Bash `5.2.21`, Zsh `5.9`,
  Linux Git `2.43.0`, Node `22.22.2`, npm `10.9.7`.
- Docker Desktop `4.93.0 (240920)`, Linux engine/client `29.8.1`,
  Compose `5.5.1`, selected context `default` with a local Unix socket.
  Windows executable interop works; Windows PATH import is disabled, so
  Windows system executable directories were added only to the QA environment.
- A private temporary QA home/checkout/cache and unique `workbenches-eagle150-*`
  helper names isolate workstation data. Existing pyBench, cloudBench and
  Docker Desktop Kubernetes resources were left running. No global Docker
  configuration or Windows execution policy was changed.
- The declared `acceptance-engine` service also started in the unique
  `workbenches-eagle150-wsl` Compose project (Docker `28.5.2`). A local override
  exposes only the QA home/socket and WSL runtime mounts at their original
  paths, allowing bench commands to execute on the real WSL host against that
  disposable engine. A container-only run is not Windows/WSL certification.

### Commands and results

Environment inspection used `wsl.exe --version`, `wsl.exe --list --verbose`,
PowerShell `Get-CimInstance Win32_OperatingSystem` and `Get-Command`, Git/shell
version commands, `docker version`, `docker compose version`, `docker context
show`, and read-only Docker resource inventories. Windows executables were
invoked using their WSL-mounted system paths.

The existing clean checkout was fetched and switched to
`codex/tui-silver-requirements-2026-10-14`; `git submodule update --init
--recursive` retained all eight recorded pins. The separate QA checkout used:

```bash
bash bootstrap.sh --branch codex/tui-silver-requirements-2026-10-14 \
  --directory "$QA_HOME/projects/workBenches"
bash bootstrap.sh --submodules "$QA_HOME/projects/workBenches"
git -C "$QA_HOME/projects/workBenches" submodule init
WORKBENCHES_FROZEN=1 bash setup.sh --version
bash scripts/manage-setup-services.sh start tools
bash scripts/manage-setup-services.sh start vault
```

The bootstrap used configured SSH access. The explicit `submodule init`
persisted registrations after the bootstrap's command-scoped transport choices;
every populated submodule matched its gitlink. Version output was
`workBenches v1.5.0`. Setup invocations use `WORKBENCHES_FROZEN=1`, isolated
XDG/npm paths and the documented optional integration skip flags.

| Check | Evidence/result |
| --- | --- |
| Actual native Windows guard | Git Bash sourced `scripts/lib/setup-prerequisites.sh` and ran `ensure_setup_platform` through PowerShell `-NoProfile -Command`. Exit 1, with WSL 2/Ubuntu guidance; no installation/elevation was requested. |
| Live WSL first screen and cancellation | Real WSL `bash setup.sh`, driven through the existing acceptance suite's PTY helper: Windows/WSL header and WSL 2/Docker Up observed. Q during loading exited 130 in 0.49 seconds. |
| Initial Tools startup | **Failed on `0367f1b`**: container health passed, but its Docker client received socket permission denied. The mounted socket was `root:1001`, mode 0660; the helper only had supplemental group 0. |
| Socket fix and migration | `423c023` detects the actual Linux socket GID on Docker Desktop/WSL, retains macOS's VM group behavior, and advances the runtime fingerprint so owned helpers are recreated. The old QA helper stopped. Replacement creation selected group 1001, but did not finish; live access verification remains blocked. |
| Source freeze and focused regression | **Passed on `fa7cd5a`** in the existing declared pyBench: source-lock check, 10 release/version tests, 6 service tests, 18 requirements tests, 6 async tests, 14 Docker prerequisite tests, and Bash syntax validation. |
| Fresh frozen install / Tools and Vault readiness | **Blocked**: replacement helper creation and Vault image preparation did not complete. |
| Selected pyBench/Codex install and shell startup | **Not run**: disposable engine base-image loading was incomplete; the existing fixed-name `py-bench` was preserved. |
| Existing-install update, add/remove, cancellation with queued changes, preservation | **Not run** through the live lifecycle; loading-screen cancellation alone does not establish these cases. |
| Existing workstation preservation during this attempt | All original container IDs, image tags/IDs and volume names remained present. All 16 inventoried credential files and the three inventoried shell/Git configuration files retained their hashes. All original submodules remained clean at recorded commits. This is evidence for this attempt, not the unexecuted lifecycle cases. |

Focused checks ran with `docker exec --user "$USER" --workdir
"$BENCH_REPO_ROOT" py-bench bash -ec '…'`, using these commands in order:

```bash
git rev-parse HEAD
python3 scripts/release-workbenches.py check
python3 devcontainer.test/test-release-version.py
python3 devcontainer.test/test-setup-services.py
python3 devcontainer.test/test-setup-requirements.py
python3 devcontainer.test/test-setup-async.py
python3 devcontainer.test/test-docker-prerequisite.py
bash -n scripts/lib/tools-container.sh
```

Initial regression attempts through the declared `npm-integrity` test service
found test fixtures assuming Linux's two requirement rows, fixed row indices,
and a non-WSL package-manager host. These fixtures now respect WSL's third row
or explicitly model native Linux. Running interactive fixtures against the
service's read-only source mount also produced log-write errors; the passing
focused run used the writable declared pyBench checkout.

### Blocker and outstanding live work

Docker Desktop create/stop/image operations took several minutes under existing
workload. An initial 120-second PTY-driver deadline expired during first-use
Tools preparation; it is not a passed install. A QA-only `stop --time 10` took
over four minutes, and a fresh corrected helper create remained pending for
over six minutes. The Vault build did not complete. These observations establish
the blocking operations, not their underlying cause. A read-only Dashboard
inspection was requested; no engine restart or interruption of existing
workloads was authorized or performed.

The declared workstation image was built with:

```bash
docker compose -p workbenches-eagle150-acceptance \
  -f devcontainer.test/docker-compose.yml --profile workstation-acceptance \
  build workstation-acceptance
docker compose -p workbenches-eagle150-wsl \
  -f devcontainer.test/docker-compose.yml -f "$QA_ROOT/wsl-engine.yml" \
  --profile workstation-acceptance up -d --wait acceptance-engine
docker image save workbench-base:latest dev-bench-base:latest | \
  DOCKER_HOST="unix://$QA_ROOT/socket/docker.sock" docker image load
```

Only `workbench-base:latest` finished loading. The QA-only import was canceled
after roughly twelve minutes, followed by cancellation of the pending helper,
Vault-build and duplicate regression clients. No full workstation acceptance
success is claimed. Resume with a responsive Docker engine and repeat the
blocked live cases on the then-current exact branch commit. Windows/WSL must
not be marked validated from the focused tests alone.

Cleanup removed the QA helper containers and `workbenches-eagle150-services`
network. Project-scoped `docker compose down --volumes --remove-orphans`
attempts for the WSL engine and regression projects exceeded 45-second
deadlines. A bounded QA-only force-removal attempt followed. At the last
inventory, these task-owned resources still needed cleanup:

- `workbenches-eagle150-wsl-acceptance-engine-1` and
  `workbenches-eagle150-regression-npm-integrity-run-ff1b77d6fece` containers;
- `workbenches-eagle150-wsl_default` and
  `workbenches-eagle150-regression_default` networks;
- `workbenches-eagle150-wsl_acceptance-{data,home,tmp}` volumes.

QA logs and isolated checkout/home were retained locally. The newly built
`workbenches/tools:eagle150-qa` and declared `workbenches-test:workstation`
images were also retained; original image tags were unchanged. Resume cleanup
using only those QA project names after Docker responds normally. The existing
configured Windows/WSL path was inspected; cold OS provisioning, WSL conversion,
Docker Desktop installation/elevation and its settings UI were not exercised.

### Tools retry at 20:15–20:17 UTC

Retested source `9eb94deab50a098530bb544937a97f671e495d99`. Eagle still
reported host user `brett` as UID/GID `1000:1000`, with Docker socket group
`1001` and mode 0660. Docker inspection now showed the earlier corrected
helper create had eventually completed: `workbenches-eagle150-fixed-tools`
was **Created**, configured with user `1000:1000` and supplementary group
`1001`. Its name resolves to `brett` through the managed identity mount;
the container had not successfully started.

`timeout 60 bash scripts/manage-setup-services.sh start tools`, targeting that
isolated helper, expired with exit 124. The pending operation was Docker's
`container start`; the helper remained Created. No in-container Docker access
success is claimed.

Two minimal probes used the already built Tools image, no network, a read-only
root, dropped capabilities and only the Docker socket bind. Both commands
began with `id` and would then query `docker info --format "Engine={{.ID}}"`;
the mapped-user probe also checked socket metadata. They used these identities:

| Probe | Docker identity arguments | Result |
| --- | --- | --- |
| Mapped user/socket group | `--user 1000:1000 --group-add 1001` | `docker run --rm` exceeded 30 seconds, exit 124; no `id` output. |
| Root comparison | `--user 0:0` | Same 30-second timeout, exit 124; no `id` output. |

This establishes that the observed startup stall also occurs for a minimal
root invocation. It does not establish the Docker backend's underlying cause
or complete live validation of the socket-group fix. Original workstation
containers were not stopped or reconfigured.

Late completion of earlier requests changed the retained-resource inventory:
the old disposable engine and earlier regression container disappeared, while
the two QA Tools containers and
`workbenches-eagle150-regression-npm-integrity-run-d79fa8ea5088` appeared in
Created state. The retry probe names are
`workbenches-eagle150-socket-probe-2016` and
`workbenches-eagle150-root-probe-2017`; they had not appeared in inventory when
their clients timed out. Cleanup must account for delayed server-side request
completion even after client cancellation, using only this run's QA names.
The retry's QA-only removal command also exceeded its 10-second deadline,
although it reported removal of the old Tools and remaining regression
container. Its final inventory still showed
`workbenches-eagle150-fixed-tools` in Created state.

### Docker diagnosis and recovered Tools startup, 20:19–20:26 UTC

Docker Desktop was running and partly responsive, with an intermittent failure
in its container-storage lifecycle. `_ping` returned HTTP 200 in 0.042 seconds;
inspection of the existing pyBench returned HTTP 200 in 0.017 seconds, and
`docker exec` in that bench succeeded. The native Windows Desktop CLI reported
`running`. Inspection of the affected QA container also stalled through the
native Windows client, so this was not isolated to the WSL Docker CLI.

Current resource checks did not show capacity exhaustion: about 47 GiB was
available inside WSL, Docker's data filesystem had about 240 GiB free, Windows
had about 13 GiB free memory, and sampled physical-disk queues were zero. Both
Windows physical disks reported SSD/Healthy/OK. These samples do not establish
conditions during every earlier stall.

Local daemon Go stack dumps identified new-container requests inside
`createContainerVolumesOS` / `prepareInitLayer`, through containerd snapshot
handling and `unix.Unmount`. A contemporaneous kernel trace showed a dockerd
thread in uninterruptible sleep, with this call chain:

```text
wb_wait_for_completion
__writeback_inodes_sb_nr
writeback_inodes_sb
sync_filesystem
ovl_sync_fs
generic_shutdown_super
cleanup_mnt
```

This identifies a filesystem-writeback wait while unmounting OverlayFS snapshots
as the observed blocking mechanism. It does not identify the cause of that
writeback delay or prove a specific upstream bug. Diagnostic stack collection
was local; no diagnostics were uploaded and no daemon configuration was changed.
See Docker's [daemon log and stack-dump guidance](https://docs.docker.com/engine/daemon/logs/).

A separate cached BusyBox image reproduced the delay, excluding a failure
specific to the Tools image: a 15-second run timed out, while a subsequent
single run with a 60-second budget succeeded. API-proxy timestamps show its
create request took 16.93 seconds before the container could start. Thus the
failure was intermittent/severe latency, rather than every new container being
permanently unable to start.

The previously created mapped-user socket probe then completed with exit 0 in
11 seconds and reported UID/GID `1000:1000`, groups `1000,1001`, socket ownership
`0:1001` with mode 0660, and the same engine ID as the host.

Finally, the declared service manager created and started a fresh full helper,
`workbenches-eagle150-diagnosis-tools`, from the clean `9eb94de` QA checkout.
Startup succeeded in **21 seconds**, status was **Up**, and in-container `id`
reported `uid=1000(brett) gid=1000(brett) groups=1000(brett),1001`. Its Docker
client reached host engine `65893114-1581-418d-a1ac-d479a9fcddad`. This **passes
live verification of the socket-group fix** and the original version-only health
check. A subsequent functional check exposed the packaging issue below, so that
first success did not establish complete Tools functionality. No Docker Desktop
restart or global settings change was needed for the recovered Docker access.

### Helper permissions follow-up — `81bde3b`

The protected QA checkout was created under `umask 077`: its public helper
source files had mode 0600. Docker preserved those permissions when copying the
files into root-owned image locations. Consequently, the mapped user could
reach Docker but could not import the host callback helper. Component inventory
became `needs check`; a subsequent TUI script exited without installing Codex,
and its postcondition correctly failed. This was a separate image-packaging
failure, not evidence of another Docker daemon failure or a passed CLI install.

Candidate `81bde3b36e90ad15d8ab526aa7fb03de63becba5` explicitly normalizes public
helper directories to 0755, the Tools command bridge to 0755, and public Python
modules to 0644 in Tools and all credential-image stages. Tools health now
checks bridge readability/executability and imports the callback module; Vault
health invokes its Python helper's help path. Private runtime credentials and
host checkout permissions are unchanged.

The final Tools image was rebuilt from that same restrictive checkout through
`scripts/manage-setup-services.sh start tools`. Live checks **passed** as
`brett` (`1000:1000`, supplementary group `1001`): directory/file access,
helper import, Docker engine identity, a real callback executing WSL `id`,
and an actual `npm --version` invocation through the bridge. These checks
establish functional Tools readiness on Eagle. All 40 focused tests also
passed on `81bde3b`: 10 release/version, 6 service, and 24 credential-recovery
tests, executed in the existing declared pyBench.

The credential core image was built through the declared `credential-1password`
Compose service, with a private override selecting target `core` and a QA-only
image tag. Running its actual Python helper with `--help` as UID/GID 1000:1000,
read-only root and dropped capabilities **passed**. This verifies module access
from the restrictive checkout; it does not certify the provider images or
managed Vault startup. The selected native callback resolved Node `22.22.2`
and npm `10.9.3`; the latter differs from the separately inspected distro npm
`10.9.7`. A further application-status probe exceeded its 30-second budget, so
no later CLI installation or lifecycle success is claimed.

After diagnosis, the temporary BusyBox/root probes and credential-test network
were removed. The retained helper is `workbenches-eagle150-diagnosis-tools`
(Up/healthy, isolated QA home). The three previously listed
`workbenches-eagle150-wsl_acceptance-{data,home,tmp}` volumes remain available
for cleanup or continued isolated QA. All original container IDs remained
present, and the inventoried original credential and shell/Git hashes still
matched. No original bench was stopped and no Docker/WSL restart was performed.

Full Vault readiness, the selected pyBench path, CLI installation/lifecycle,
and the remaining complete workstation acceptance cases still require execution.

### Full native WSL test implementation and continuation

Product candidate for the completed attempts: `76555991d8ea40d51009687fbc22ba7cd39b4748`.
These attempts did not complete the Windows/WSL gate. Driver/documentation
commits through `a0ad2a3` did not change that product runtime; the image-depth
fix below requires a new live candidate and acceptance run.

Completed native host cases on this product commit:

| Case | Result | Seconds |
| --- | --- | ---: |
| Tools readiness | Passed | 1.70 |
| Loading-screen cancellation | Passed, exit 130 | 0.53 |
| Empty selection | Passed | 31.19 |
| Codex install | Passed | 146.31 |
| Codex update | Passed | 115.56 |
| Queued cancellation | Passed | 21.81 |
| Deliberately failed update | Passed, actual npm failure preserved installation | 318.34 |
| Codex removal | Passed | 150.68 |
| Codex reinstall | Passed | 147.30 |
| Host Bash/Zsh startup | Passed | 1.48 |
| Managed Vault readiness | Passed, healthy service already started below | 1.11 |
| Preservation after cold-install timeout | Passed | 9.48 |

The separate bench phase has not yet completed; no bench lifecycle result is
inferred from these host checks.

The cold bench attempt failed after `3605.41` seconds: the 3600-second PTY
deadline expired and its five-second process-exit grace also elapsed. Layer 0
had completed, but developer-base Layer 1 was still at step 45 of 60. The
aggregate report recorded 12 passed cases, one failed `bench-install`, and four
not run: bench shells, update, removal, and frozen local-work refusal. The
underlying wait/download cannot be attributed solely to storage at that last
step; earlier storage waits were captured separately above and below.

The complete `16,886,977`-byte transcript was copied from RAM to the ordinary
report directory after its writer exited. Its report and failed aggregate were
archived before retrying. QA-only container removal then completed, leaving
the same disposable engine empty while retaining completed images/build cache.
A second bench-phase run started at `22:50Z`, using the same clean product
commit and the corrected driver; its result remains pending. Neither Desktop
nor the disposable engine was restarted for this retry. Original credential
and shell/Git hash checks still matched, and all eight QA submodule pins
remained clean before retrying.

The declared native driver is
`devcontainer.test/test-wsl-workstation-acceptance.py`, documented in
`devcontainer.test/workstation/README.md`. It refuses container-only execution,
root execution, the real user's home, an unexpected source SHA, an existing CLI
on the fresh-install path, and a non-isolated bench engine. It waits for the
selected row's actual visible status, verifies installed artifacts, and records
failed/not-run cases. Resume requires matching source and Desktop engine
identity; project, credential, and prompt hashes/modes/mtimes are preserved.

```bash
# QA-only HOME/XDG/TMPDIR/npm prefix and resource names, as documented in the
# native acceptance guide; the prepared checkout is clean at TESTED_SHA.
export TESTED_SHA=76555991d8ea40d51009687fbc22ba7cd39b4748
export WORKBENCHES_FROZEN=1 WORKBENCHES_WSL_ACCEPTANCE=1
python3 "$DRIVER_ROOT/devcontainer.test/test-wsl-workstation-acceptance.py" \
  --repo "$QA_CHECKOUT" --report "$QA_ROOT/report/native-wsl" \
  --sha "$TESTED_SHA" --engine "unix://$QA_ROOT/socket/docker.sock"
# Following a driver-only correction, preserve matching completed assertions:
# add --resume to the same command.
```

The bench engine uses the declared `acceptance-engine` service and a private
Compose override retaining real WSL home/socket and GUI runtime paths. It runs
Docker `28.5.2` inside Docker Desktop; the native host client and Desktop engine
are `29.8.1`. Both shared base images and the public Tools image were imported
as cache. This exercises actual WSL-native scripts, callbacks, mount paths, and
shells while keeping the original fixed-name `py-bench` untouched.

Additional findings and checks:

- WSL has a Snap client but no active Snap daemon. Repeated package probes
  delayed inventory. `209ecf8` probes the Snap inventory once with a two-second
  deadline. The 24 component tests passed, including unavailable-daemon and
  exact package ownership cases.
- A native callback broker remained alive after its command finished, blocking
  a status refresh. `7655599` closes the session and bounds broker cleanup,
  including forced termination of an unresponsive owned broker. Seven service
  tests passed, including a broker that ignores TERM; the subsequent live
  frozen CLI install completed without manual broker intervention.
- All 20 setup regression suites passed after correcting the guided-flow
  fixtures' WSL requirement count and isolating their mocked status refreshes.
  All 43 guided-flow checks and 10 release/version checks passed. The clean
  candidate's source-lock check also passed.
- Eagle's higher-priority npm `10.9.3` is broken: a registry query fails inside
  its `cacache` dependency with `Class extends value undefined`. The distro npm
  `10.9.7` successfully queried the public registry. A symlink only in the QA
  prefix selected that working copy; neither original installation was changed.
  Node is `22.22.2`; the installed host Codex reports `0.163.0`.
- Full Vault startup succeeded as UID/GID `1000:1000`, with provider versions
  `op 2.40.0`, `bw 2026.9.1`, and Azure CLI `2.91.0`. Its actual helper `--help`
  and provider version commands passed as the mapped user. The build began at
  `21:05:22Z`; container creation was recorded at `21:12:37Z`, and startup at
  `21:24:37Z`. The twelve-minute creation delay is the observed filesystem
  stall, not a credential or user/group failure.
- The shared-image import eventually completed. The user explicitly requested
  continued testing without restarting Docker Desktop. No Desktop/WSL restart,
  global Docker configuration change, or interruption of an original bench
  was performed.

The first negative npm update encountered a real TCP SYN timeout on WSL rather
than an immediate localhost refusal; setup correctly returned failure. Setting
npm's fetch timeout alone did not bound that connection attempt. The driver now
reserves a non-listening ephemeral port for the deliberately broken registry;
a real native npm query failed with exit 1 in 0.40 seconds using this fixture.
Test credentials are generated invalid values, and no paid AI authorization is
claimed.

The bench isolation fixture initially put its home below `/tmp`. DinD's startup
tmpfs hid those bind mounts despite their presence in Docker inspection. The
private home was copied below the user's cache, and only the disposable engine
was recreated, retaining its data volume and shared-image cache. The native
home/socket paths were then verified inside it. The driver and its guide now
reject the hidden-mount arrangement. A separate diagnostic startup briefly
raced the acceptance worker's QA network creation; those QA-only resources were
reset, and the bench test was restarted serially. Neither interrupted attempt
was counted as passed.

The native run also exposed excessive QA transcript I/O: the PTY helper rewrote
its entire growing log for every BuildKit terminal frame, producing about
29 GB of writes for a roughly 6 MB transcript. The helper now limits interim
report writes to once per five seconds and still saves the complete redacted
transcript on exit. The native driver requests plain BuildKit output. A
30-frame PTY smoke check in the declared pyBench verified that the complete
final transcript is retained. For the already-running cold build, only its
private QA transcript was moved to a RAM-backed report location; it will be
copied back after the writer exits. This avoids added QA disk traffic; it does
not establish the cause of Docker's earlier filesystem stalls, which predated
this native build run.

At `22:19:59Z`, the cold build again waited in the disposable engine's actual
kernel stack: `wb_wait_for_completion → sync_filesystem → ovl_sync_fs →
cleanup_mnt`. The outer Desktop `_ping` simultaneously returned HTTP 200 in
0.012 seconds. The installer process had already exited, distinguishing this
wait from an ongoing package download. The layer eventually completed and
the build advanced; the trace establishes the filesystem wait, not its root
cause. Read-only diagnosis used `docker exec` to inspect the QA daemon's
`/proc/PID/task/*/stack` and `curl --unix-socket` for the API ping. No restart
was performed.

Capacity inspection at `22:33Z` reported 208.5 GiB free in the QA engine's
backing filesystem (89% used), WSL `MemAvailable` of `45,809,520 kB`,
and Windows volume free space of 1.06 TB on C: and 757 GB on D:. Commands were
`df -h /var/lib/docker`, reads of `/proc/meminfo` and `/proc/pressure/io`, and
PowerShell `Get-Volume | Select-Object DriveLetter,SizeRemaining,Size`.
These observations do not show an exhausted filesystem or memory condition;
they do not certify storage hardware health.

On QA-driver commit `635f55d382b744a931ac1c8cbc94d32d544ce33a`, the
[Workstation Setup workflow](https://github.com/opensoft/workBenches/actions/runs/39074612502)
passed all four jobs: regression, Tools runtime, credential images, and
component lifecycle. Release source freeze, shared workstation images,
project-command, and OpenSpeckit checks also passed on that head. These CI
results remain separate from the pending real WSL bench acceptance.

The cache-assisted retry confirmed cached developer-base steps through 45 and
advanced beyond the first attempt. At `23:09Z`, its installer process had
exited while the native build client still waited. The QA daemon's read-only
`/debug/pprof/goroutine?debug=2` trace showed BuildKit blocked in
`overlay2.Driver.Put → unix.Unmount`; the blocked kernel thread was in
`sync_inodes_sb → sync_filesystem → ovl_sync_fs → cleanup_mnt`. This confirms
another backend filesystem wait after the transcript-I/O fix, rather than a
mapped-user permission error or a pending vendor download. The trace does not
identify the underlying cause. The source-lock check also passed on the clean
QA-evidence commit `e4edb25542cc12241abdfed631a77c8a4d7d53c1`.

At `23:16Z`, the native Windows guard was repeated against the clean product
commit `7655599` using actual Git Bash `bash.exe --noprofile --norc`, with the
QA checkout's path obtained from `wslpath -m`. Its command sourced
`scripts/lib/setup-prerequisites.sh` and invoked `ensure_setup_platform` with
stdin redirected from `/dev/null`. It passed: exit 1, explicit WSL 2/Linux
container prerequisites, and the Administrator PowerShell
`wsl --install -d Ubuntu` guidance. This noninteractive check did not request
elevation or install/reconfigure WSL; existing WSL provisioning is a prerequisite
for the live workstation run.

Two read-only samples of the backing device's `/sys/class/block/sde/stat`
at `23:19:34Z` and `23:20:23Z` recorded 63,693 completed writes and 1,629.70 MiB
written over 49 seconds (33.26 MiB/s), with 96.9% I/O busy time. These counters
show ongoing device I/O while the build waits for filesystem synchronization;
they do not establish a complete I/O stop, physical-disk saturation, or hardware
failure. The raw numeric samples remain in the private QA report.

### Image-depth failure and release fix

The cache-assisted bench attempt returned exit 1 after `3225.86` seconds.
Both images built successfully, but actual container creation failed with
`Error response from daemon: max depth exceeded`. Final preservation passed
in `9.09` seconds; the aggregate retained 12 passed cases, one failed install,
and four not-run dependent cases. The failed report/build log were archived.

Read-only `docker image inspect --format '{{len .RootFS.Layers}}' IMAGE`
measured:

| Image | Filesystem layers |
| --- | ---: |
| `workbench-base:latest` | 48 |
| `dev-bench-base:latest` | 107 |
| `py-bench:latest` | 113 |
| `py-bench:brett` | 128 |

Docker's [overlay2 implementation](https://github.com/moby/moby/blob/v28.5.2/daemon/graphdriver/overlay2/overlay.go#L60)
limits the lower-layer stack; container creation needs additional layers beyond
the image. This is a separate deterministic recipe defect, not a user/group
permission error or an inference from the slow filesystem operations.

The fix combines the developer base's final nine configuration operations into
one RUN layer, preserving their order and retaining the expensive earlier build
cache. Its source fingerprint changes automatically. The expected personalized
pyBench depth drops by eight layers, from 128 to 120; live confirmation and the
complete native rerun remain required. A new CI regression limits the common
developer-stack recipes to 114 filesystem-layer instructions, leaving room for
the upstream image, bench-specific layer, and container creation. The test
failed before the fix (121) and passed after it (113). The merged shell block
passed `/bin/sh -n`; 10 release/version checks and 11 install-friction checks
also passed in the declared pyBench.

The independent `--phase guard` driver mode can verify frozen-source refusal
after a blocked bench attempt without building images. Removal assertions now
also require both selected pyBench image tags to be absent. These driver
changes passed Python compilation and CLI help validation; live checks remain
required before they contribute passing evidence.

The pyBench package installer also emitted OpenTelemetry dependency conflicts:
Semgrep `1.181.0` requires the `1.37` series, while its later package installation
selected `1.45.1`. This was not the container-create failure. Semgrep operation
is not certified by the selected Python/Codex acceptance path; these mutable
package dependencies remain a limitation to record separately.
