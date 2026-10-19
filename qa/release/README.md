# Dedicated release QA workers

Do not install a runner on Brett's normal Raven/Eagle account. The repository is
public: an unrestricted self-hosted runner can execute an attacker's PR even if
our own workflow avoids it. Before any worker starts, an organization administrator
must configure a runner group restricted to this repository and the selected
workflow `opensoft/workBenches/.github/workflows/release-qa-suite.yml@refs/heads/main`.
The `release-qa` environment must allow deployments from main only. Candidate
release branches must also be protected by the organization's reviewed-change
policy before privileged testing is enabled. Preflight permits current main or
a protected release branch; it blocks unprotected candidate refs. Branch-creation
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
