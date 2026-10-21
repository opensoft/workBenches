# Dedicated release QA workers

Hosted fresh-install jobs provision 8 GiB of swap on their disposable runners for
large SDK-image exports. Failed commands record their actual numeric exit code,
available memory/swap and the change in the kernel OOM-kill counter. A signal exit
alone does not prove OOM. Optional encrypted fixture diagnosis also captures the
failed command's output before its private log is deleted; plaintext is never
uploaded. Native worker capacity and native results remain separate evidence.
The one-use Arch controller allocates 16 GiB RAM and provisions 8 GiB swap only
inside the new disposable guest after verifying its reset marker. It requires
another 2 GiB of available host headroom before starting. The small persistent
broker-provisioning VM keeps its existing 4 GiB default. This matches the RAM of
the passing hosted fixtures: Arch v7 exhausted its former 8 GiB RAM and 8.5 GiB
total guest swap during SDK export, despite the Docker Go memory target. The
retained kernel report identified the containerized dockerd, with 2.7 GiB resident
and 8.5 GiB swapped memory; the memory target is not a hard process limit.
Arch v4's retained serial
log confirmed a kernel OOM kill of dockerd with the old 4 GiB/512 MiB profile.

Full hosted runs from main prepare compatible public base/developer images before
starting fixtures. The publisher accepts only current main or the exact current
protected canonical release head, rechecks that source before running its code,
and reuses existing verified images. Candidate image provenance uses the candidate
SHA, independently of the automation SHA. PR/CI and unprotected candidate runs do
not receive publishing permissions; their fixture path retains local builds.

Do not install a runner on Brett's normal Raven/Eagle account. The repository is
public: an unrestricted self-hosted runner can execute an attacker's PR even if
our own workflow avoids it. Before any worker starts, an organization administrator
must configure a runner group restricted to this repository and the selected
workflow `opensoft/workBenches/.github/workflows/release-qa-suite.yml@refs/heads/main`.
The `release-qa` environment must allow deployments from main only. Candidate
release branches must also be protected by the organization's reviewed-change
policy before privileged testing is enabled. Preflight permits the current main
commit or the exact current commit of the protected canonical release branch;
the mere existence of a protected branch cannot authorize a different source
SHA. It blocks unprotected, unrelated and stale candidate commits. Branch-creation
and administrator bypass permissions remain restricted to trusted release owners. If your GitHub
plan cannot enforce this boundary, keep these jobs in a private controller repo;
do not substitute an unrestricted public-repository runner.

## Provisioner contract

Prepare golden VM images for native Arch and Windows/WSL2. A Linux cloud QA worker
and a headed browser QA worker can be separate disposable images. Register an
up-to-date ephemeral runner with `self-hosted,Linux,workbenches-qa` and the relevant
capability label `arch`, `wsl2`, `desktop`, or `cloud`. The WSL agent runs inside the
QA distribution with GUI/native callback support. Start the runner with umask 022 so public Git checkouts have their declared
read permissions (credential/state files still use explicit private modes).
Register only after restoring a
fresh snapshot and creating a new reset ID. The provisioner must destroy/reset the
VM/disk after job completion or cancellation; ephemeral runner registration alone
does not reset the operating system. No production home or Docker socket is
mounted. Native tests use a separate disposable Docker engine.

The release preflight checks online, nonbusy runner labels using a token with
repository runner-inventory read permission. It reports blocked suites when
workers/configuration are absent. Live jobs run serially so small pools can reset
between jobs. A queue watchdog cancels the validation run if no QA job progresses
for ten minutes; publication cannot use a cancelled run. A provisioner must bring
up replacement ephemeral workers within that budget.

Each image has:

- A dedicated ordinary QA user, clean PATH, Docker, Git, Python for QA driving,
  Node/npm and the prerequisite shell/runtime tools. Product setup still uses
  Tools where native Python is absent. Arch's image permits passwordless sudo
  for selected shell-install tests; it has no personal account data.
- Root-owned `/etc/workbenches/disposable-qa-id`, not writable by the QA user,
  containing the provisioner's unique reset ID.
- Root-owned `/etc/workbenches/release-qa.json`, not writable by the QA user.
  It includes `enabled: true`, `disposable: true`, the matching `resetId`, and
  approved adapter entries for this worker's capabilities.
- For native workers, `/etc/workbenches/native-qa.json` with `kind: arch` or
  `kind: wsl`, and `cleanPath` containing only the golden image's tool paths.
  The runner must not rely on a production/global Codex install.

Install `native-adapter` as `/opt/workbenches/qa-native`, root-owned mode 755.
Compute its SHA-256. Configuration shape (replace the digest and reset ID):

```json
{
  "enabled": true,
  "disposable": true,
  "resetId": "provisioner-generated-boot-id",
  "adapters": {
    "arch-native": {
      "argv": ["/opt/workbenches/qa-native"],
      "sha256": "64-hex-digest-of-the-installed-wrapper"
    }
  }
}
```

Use `wsl-native` on WSL. The wrapper runs the exact trusted automation checkout,
not a stale installed test script. The bundled adapter creates a private HOME,
clones the exact candidate, starts the declared isolated Docker engine, runs the
native acceptance driver, checks its complete case list, and removes its helpers,
engine and volumes. Arch also exercises shell setup and rerun. It refuses an
ordinary desktop/container, root user, incorrect marker, or incomplete acceptance.
The adapter's stdout contains only the allowlisted result envelope; raw logs and
browser/device codes never enter public artifacts.

## Live adapters and initial provisioning

Live test accounts and an approved provider mode are not created by repository
code. The `github-live`, `company-live`, `provider-live` and v1.7 `device-live`
adapters are deliberately blocked until administrator-managed test implementations
are installed and pinned in this configuration. An adapter receives a JSON request
on stdin with `source`, `run`, `suite`, `requiredCases`, `root`, and `resetId`.
Its JSON stdout must have exactly `source`, `run`, `suite`, `cases`, `cleanup`,
`resetId`, and `status`. Every required case must be present and passed, in order,
with successful cleanup. Returning exit 0 alone is insufficient. This interface
is not permission to install an adapter which merely asserts success: adapter
code must be reviewed, pinned and exercise the real boundary it certifies.

Provision:

1. Two designated GitHub QA user identities for personal/work selection, reuse,
   reauthentication and cancellation. They need no production memberships or
   repository write permissions. Store login/recovery factors only in the private
   QA credential store. Fixture jobs have no GitHub user credentials. MFA/browser
   approval remains attended when the provider requires it; do not replace a
   browser device-flow test with an existing PAT and call it equivalent.
2. Two QA company contexts, authorized and denied test users, and broker-audience
   OIDC configuration. Exercise company sign-in/out/reconnect, expired sessions,
   denied users and cross-tenant denial. Service/client credentials are not proof
   of a user's delegated Microsoft browser sign-in.
3. A QA broker and isolated Key Vault with broker-only managed-identity access.
   Choose an explicitly approved provider mode before installing its live test
   adapter. Validate publication/recovery/conflicts/offline/login-required/CPC
   refresh and tenant denial using dedicated nonproduction profiles. Unsupported
   sharing modes remain disabled; fictional fixtures cannot satisfy this gate.
4. In v1.7, provision two independently identified device endpoints and verify
   directional consent, wrong-owner/reverse denial, strict host trust and revocation.

An attended flow can pause its adapter while an operator completes browser/MFA
approval, then automatically verify the resulting identity and behavior. It must
finish inside the job timeout and still produce exact-commit evidence. There is no
unchecked manual attestation upload or boolean to bypass these required cases.

After worker/adapter readiness is verified, set the `release-qa` environment's
`WB_QA_CONFIGURED=true`, provide `RELEASE_RUNNER_INVENTORY_TOKEN` (runner-inventory
read only), and optionally enable repository variable `WB_RELEASE_QA_NIGHTLY=true`.
Keep credentials out of repository files, command arguments, recordings and
artifact logs. The environment variables contain only readiness/path settings;
the workers' protected local store holds actual browser/provider credentials.

## Preparing an isolated Arch image on a KVM host

`prepare-arch-vm.py` prepares a stopped golden image without registering a runner.
It requires QEMU/KVM, SSH, Python and GNU cp on the provisioner host. It does not
install host packages, alter desktop settings, mount a host home/socket in the VM,
or write to the global SSH configuration. State must be a new private directory.
The guest receives a separate QA key and root-owned native adapter configuration.
SSH is pinned from the VM's private serial channel; verification is never disabled.

Download the pinned official image from
https://fastly.mirror.pkgbuild.com/images/v20261015.611680/Arch-Linux-x86_64-cloudimg-20261015.611680.qcow2
and verify its signed checksum using the CI key published in the
[official Arch Boxes README](https://github.com/archlinux/arch-boxes#releases).
The image SHA-256 is pinned in the preparer. The signing primary key is
`1B9A16984A4E8CB448712D2AE0B78BF4326C6F8F` (signing subkey
`656E4C5AC1CC3B86E539D97E343635A6859A9174`).

```bash
python3 qa/release/prepare-arch-vm.py --image /private/verified-arch.qcow2 \
  --state "$HOME/.cache/workbenches-release-qa/arch-golden-UNIQUE"
```

The preparer copies the image, expands only that private disk to 80 GiB using
QMP, installs QA tools, reboots into the upgraded Arch kernel, verifies Docker,
Buildx and root disk capacity, and powers off. `prepared.json` is written only
after successful validation and shutdown. Failed attempts are stopped and retain
private diagnostics; they never become ready workers. Its HTTP metadata server
is loopback-only and is stopped on completion/failure.

Copy/reset the golden disk for each job; never run acceptance jobs on the golden
disk itself. The per-job controller must assign a new instance/reset ID, recreate
host keys and root-owned matching markers/configuration, register an ephemeral
runner into the restricted group, and destroy the job disk on any outcome.
This image preparation is not a replacement for that controller, organization
policy, live adapters or QA identities, and does not enable `WB_QA_CONFIGURED`.

## One-use native Arch acceptance controller

`run-native-arch.py` uses a validated stopped golden disk but creates a separate
job disk, reset ID and both SSH identities for each execution. It transfers exact
candidate/automation git commits by bundle, runs the root-pinned native adapter,
and records its exact-source JSON report. No local report upload can become a
release pass; release jobs must still execute the approved adapter under the
protected workflow. Failed disks stay private for investigation. Passing jobs
stop the VM and remove their disk/operator key. No GitHub runner is registered.

```sh
python3 qa/release/run-native-arch.py --golden /private/arch-golden \
  --state /private/new-native-job --candidate /path/to/candidate-git \
  --automation /path/to/trusted-automation-git
```

The shell installer and workstation preservation scenarios use separate private
homes so that intentional shell configuration does not overwrite another test's
custom-settings fixture. Their existing assertions remain enabled. The preserved
Raven provisioning VM has its release marker removed and must not be substituted
for this fresh per-job lifecycle.

## Optional encrypted fixture failure diagnosis

Public release evidence remains allowlisted metadata only. For fresh-install
fixtures, an operator may set repository variable `OPENBENCHES_QA_FAILURE_CERT_PEM`
to a public X.509 encryption certificate. Before cleanup, the trusted automation
can envelope the latest private setup log and bench transcript with OpenSSL CMS
AES-256-GCM and upload only `fresh-install-debug.cms` as a separate diagnostic
artifact, retained for two days. Plaintext temporary copies are deleted. Invalid
certificates, unavailable encryption, and command failures never cause plaintext
upload. The decryption key is never installed in CI. These files are not release
attestations and contain only disposable fixture diagnostics, not live QA logs.

For the initial investigation, the private key is protected on Raven under its QA
cache and escrowed as `qa-fixture-diagnostics-private-key` in `kv-openbenches-qa`.
Neither the scheduled session coordinator nor the broker workload identity has
access to that secret. Rotate/remove the public certificate variable after the
investigation. Decrypt only in private local storage and do not publish decrypted
logs. OpenSSL CMS authenticated decryption rejects tampered envelopes.

Native fixture failures use the same optional public certificate. Before removing
the private test HOME, the adapter encrypts the failed driver's output, last setup
log, bench transcript and driver case results into `arch-native-debug.cms` or
`wsl-native-debug.cms`. Only an allowlisted failed-case identifier and ciphertext
descriptor enter public evidence. The protected workflow uploads ciphertext as a
separate two-day diagnostic artifact; absence or encryption failure never falls
back to plaintext. This applies to disposable native fixtures, not live QA logs.

For a local one-use Arch run, pass
`--diagnostic-certificate /private/public-certificate.pem`. The controller forwards
only the public X.509 certificate, retrieves any ciphertext before stopping the
VM, and keeps it in the private job-state directory. The decryption key stays on
the operator host/in the dedicated vault. A failed VM's retained disk does not
preserve its deleted test HOME, so collect this envelope before disposal when
investigating failures. The controller's outer wait follows the manifest's native
suite timeout plus shutdown margin rather than imposing a shorter fixed limit.

## Team001 provider QA sessions

`config/qa-provider-slots.json` records the four requested provider slots without
credentials. Claude and Codex use `Team-001@opensoft.one`, profile `Team001`.
DeepSeek and GLM reserve that same profile but remain pending user configuration;
select and verify their API model identifiers and free-tier limits at setup time.
Each provider has independent credentials and results. Pending slots do not count
as passed provider coverage.

Bootstrap a separate QA session through each official native CLI on Raven:

```bash
python3 qa/release/provision-provider-qa.py --provider claude
python3 qa/release/provision-provider-qa.py --provider codex
```

Complete the browser/MFA consent once as Team001. Paste any authorization code
only into the local native login terminal. The helper uses private isolated
HOME/config directories, checks the selected account, expiry and presence of a
refresh token, then stores the
result in `kv-openbenches-qa` as `qa-claude-team001-session` or
`qa-codex-team001-session`. It never imports or rotates the expired production
backup session. Vault bootstrap uses the operator's existing Azure CLI session;
this is not proof of workload-identity access or a successful provider request.
`--collect-existing-login` is only for collecting an official CLI login already
started in that helper's private directory. Never copy an arbitrary credential
file into it. Login status/cache presence alone does not prove server validity.

Run account-auth automation only from trusted private infrastructure. The
[official Codex CI/CD auth guidance](https://learn.chatgpt.com/docs/auth/ci-cd-auth)
requires one machine or serialized job stream per credential copy, persistence of
native CLI token updates, and excludes this workflow in public repositories.
The public Actions workflow added here runs only synthetic bootstrap contract
tests. A private coordinator must own the real login cache, run the provider's
native validation/refresh, persist changed credentials after each invocation, and
stop for reauthentication on revocation. Do not fan out a refresh token to
concurrent workers or claim that the generic RFC 7662 adapter supports these
subscription sessions.

Neither bootstrap nor a successful native prompt alone satisfies `provider-live`:
the release gate still requires the approved mode, managed-identity KV path,
publish/recover/conflict/offline/login-required/CPC refresh/tenant denial and
cleanup cases against the exact release source. Those cases remain incomplete
until their real adapters and identities are provisioned and observed.
