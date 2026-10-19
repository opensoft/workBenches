# Automated release validation and publication

The orchestration code lives on main, separately from product candidates. It
checks out the exact candidate in another directory and binds every result to
that commit, VERSION, release-lock digest, test-manifest digest, automation
commit, workflow run ID and attempt. Existing immutable tags are unchanged.

## Normal release operation

1. Prepare VERSION, source lock, fixes and release notes in the candidate PR.
2. Run **Release validation** from main, selecting the candidate branch/tag and
   `mode=fixtures` for an integration rehearsal, or `mode=release` for full QA:

   ```bash
   gh workflow run release-validation.yml --ref main \
     -f ref=release/1.6.0 -f mode=release
   ```

3. Resolve failed/blocked suites. The summary identifies missing native runners,
   missing QA configuration, incomplete live tests and failed cleanup. Never
   convert missing prerequisites into passed/skipped release tests.
4. Merge the approved final stable VERSION/lock/notes into main. A main push
   with a stable VERSION that has no tag automatically selects full release
   validation. Every later main commit before publication is tested again.
   Candidate-branch pushes select fixtures where the workflow is installed;
   older candidate branches without it use the dispatch command above.
5. After the full run succeeds on the current main commit, publish using:

   ```bash
   gh workflow run release-publish.yml --ref main \
     -f version=1.6.0 -f validation_run=THE_SUCCESSFUL_RUN_ID
   ```

   Publication automatically rechecks the GitHub run identity/conclusion and all
   downloaded evidence, verifies current main and exact VERSION, creates an
   annotated immutable tag, and publishes the release with a validation report.
   The publication environment can require a final reviewer approval. There are
   no manual test commands in the normal release path. Real MFA/browser approvals
   may still be attended checkpoints in the live adapters.

PRs affecting automation run its negative tests and a fast CI manifest. Main
pushes for an already tagged stable version run that same CI profile. Nightly
runs exercise the complete hosted fixtures; enable `WB_RELEASE_QA_NIGHTLY=true`
only after protected workers/live adapters are provisioned to include live QA.
No path filter can suppress a full release dispatch or new-version main run.
Release workflows explicitly disable Actions cache access (`cache-mode: none`),
including reusable suites, so candidate execution cannot poison main caches.

## What is required

`config/release-tests.json` is the reviewed source of required suites and cases.
It supports explicit release lines 1.5/1.6/1.7; unknown lines fail until the
manifest is updated. Ordinary Workstation Setup CI and release testing use the
same setup suite; required case lists cannot silently diverge.

Hosted suites cover source freezing, setup, launcher/estate regressions, Speckit,
image wiring, native Tools bridge, credential tooling, broker/CPC fixtures and
component lifecycle. The fresh-install suite uses the declared separate Docker
engine and a generated Vaultwarden account over verified HTTPS; it includes
repeat setup, cancellation, removal and preservation. Tests run against frozen
source. This does not freeze every external package/download or certify paid
provider sharing.

Full v1.6 QA additionally requires native Arch shell/install/rerun, native WSL2,
real two-account GitHub browser/clipboard/reuse, company sign-in/out/reconnect/
denial, and approved live provider/broker/Key Vault/CPC tests. v1.7 adds isolated
SSH and live device trust. v1.7-only cases are not required to publish v1.6.
MFA is not bypassed; an existing PAT is not a browser-login acceptance test.

Each hosted/native adapter must actually execute every required case. Live
adapters need deployment-specific users, tenant grants and a selected approved
provider mode. Until these are supplied, their evidence is explicitly **blocked**.
The initial implementation does not pretend to have provisioned these resources.

## Evidence and gate

Artifacts contain only allowlisted metadata and case outcomes, not raw subprocess
logs, passwords, tokens, cookies, device codes or browser profiles. Every required
suite must have exactly one report, every case must pass in order, cleanup must
pass, source/run/digests must match, and evidence must be under 24 hours old.
Partial job reruns are not a substitute for a new complete run: attempts must
match. Unknown reports and extra adapter fields are rejected. The report's
`publishable` field is false for both CI and fixtures, even when everything passes.

The `evidence-gate` job collects all reports and checks worker/job conclusions too.
Missing/offline/busy runner prerequisites generate blocked reports before queuing
live work. A watchdog cancels a stalled protected-runner queue after ten minutes
without an active QA job. Interrupted/cancelled runs cannot publish. Snapshot
reset/VM destruction remains the provisioner's responsibility on any outcome.

A local report or arbitrary uploaded JSON cannot authorize publication. The
publisher downloads artifacts only from this repository's completed successful
Release validation workflow on main, checks the exact current main commit/run
attempt, and reruns the strict gate. Its default CLI mode validates without writes.
An existing tag is never moved/deleted: a matching tag created by an interrupted
publication can resume with the same evidence; conflicting tags are refused.
Published releases are not rewritten and existing drafts require separate review.

GitHub's current immutable tag rule blocks updates/deletion, but still permits
creation by other authorized actors. The automated path enforces this gate; it
does not remove an administrator's ability to create a tag/release manually.
To enforce publication organization-wide, restrict creation of stable `v*` tags
to the approved publisher identity using a separate tag-creation ruleset, keeping
the no-update/no-delete rule. Review existing publisher identities first; this
setup does not silently revoke their access or alter the immutable rule.

## One-time GitHub setup

Workflows must first be merged to main before normal dispatch is available.
Writing `.github/workflows/*` requires an OAuth credential with `workflow` scope
(or an appropriate GitHub App/fine-grained credential). Repository administration
is separately needed for environments and runner inventory.

Inspect and create dedicated environments:

```bash
python3 scripts/setup-release-automation.py inspect --version 1.6.0
python3 scripts/setup-release-automation.py configure --version 1.6.0
# Optional: require an explicit final publication reviewer for newly created envs.
# python3 scripts/setup-release-automation.py configure --reviewer YOUR_GITHUB_LOGIN
```

The helper creates only missing `release-qa` and `release-publish` environments,
restricts them to main, and initializes missing readiness/path variables. It
preserves existing environment protections and never creates runners, users or
cloud resources. For an existing environment, inspect/set the policy in GitHub;
a later --reviewer invocation does not overwrite it. QA starts disabled.

Before registering any public-repository self-hosted workers, enforce the
organization runner-group/workflow restrictions in
[the QA worker guide](../qa/release/README.md). An unrestricted self-hosted runner
on a public repo is not an acceptable substitute. Apply the reviewed-change
branch policy to candidate release branches before enabling privileged tests;
preflight blocks an unprotected candidate. Current main is already protected. Configure protected inventory
read access, approved local adapters and test accounts, then set
`release-qa` environment variable `WB_QA_CONFIGURED=true`. The preflight inventory
credential needs only repository runner inventory read access; the normal suite
jobs have read-only repository permission. Only the isolated publication job has
contents-write permission, and the queue watchdog's actions-write job restricts its cancellation code to its own run.

For initial deployment, provision two designated GitHub QA identities, two QA
company contexts and authorized/denied users, a QA broker/Key Vault deployment,
and an approved provider mode. Do not use Brett's production tokens/accounts.
Detailed native image prerequisites, adapter protocol, reset contract and live
acceptance requirements are in the worker guide. A repository change cannot
create or complete MFA enrollment for those user identities.

## Developer verification

```bash
python3 devcontainer.test/test-release-automation.py
python3 scripts/release-validation.py plan --root /clean/candidate --mode release --ref release/1.6.0
python3 scripts/release-validation.py run --root /clean/candidate --suite setup --reports /private/evidence
python3 scripts/release-validation.py gate --root /clean/candidate --mode release --reports /private/evidence
```

The last command must fail when required native/live evidence is missing. Raw
command output stays in private temporary files and is removed; for diagnosing a
fixture failure, rerun the named command directly in its declared QA environment.
Do not upload unreviewed diagnostic output or generated credentials.

References: [reusable workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows),
[default-branch dispatch](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow),
[self-hosted runner security](https://docs.github.com/en/actions/reference/security/secure-use),
[environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).
