# Prompt for Eagle Codex

Prepare and run the real WSL2 release QA suite for `opensoft/workBenches`.
Read local AGENTS.md, qa/release/README.md, docs/release-automation.md and
scripts/release-qa-native.py before acting. Preserve Brett's daily Windows/WSL
environment, repositories, credentials, containers and all existing distributions.
Do not publish a release or move an existing tag.

Fetch current main and release/1.6.0, inspect changes, and record their exact SHAs.
At preparation time main was 24729e2 (Team001 QA bootstrap) and release/1.6.0 was
e1ca09c (PTY drain diagnostics). These are discovery hints, not substitutes for
checking current refs. Native controller PR #186 supplies the separate shell-test
HOME fix and safe native failure metadata; use its reviewed merged version once
available. Automation source and candidate source are separate identities.

First inventory Windows virtualization/WSL2 and available disk/memory. Use a new,
clearly named disposable QA distribution or VM, with its own ordinary QA user.
Do not install a runner in Brett's account or default distribution. Provision
Docker/Compose/Buildx, Git, Python, Node/npm, shell prerequisites and WSLg support
inside the QA environment. Use native WSL2 Docker plus the declared disposable
acceptance engine; do not attach tests to Brett's Docker Desktop engine or mount
his home/socket. Refuse WSL1, a Linux container impersonating WSL, or missing GUI
support. A Raven Arch run does not certify WSL.

Install the root-owned native-adapter wrapper at /opt/workbenches/qa-native and
pin its SHA-256 in root-owned /etc/workbenches/release-qa.json. Generate a new reset
ID per fresh job; place it in the root-owned disposable-qa-id marker and matching
config. Set native-qa.json kind=wsl and a clean PATH. Follow the exact guide's
ownership and schema checks. Stage immutable candidate and trusted automation
checkouts without importing personal credentials or a global Codex installation.

Run release-validation.py run --suite wsl-native with that config and exact source
SHA, WB_AUTOMATION_ROOT and WB_AUTOMATION_SHA. Execute every required desktop,
bench, services, guard, preservation and cleanup case. Preserve metadata-only
evidence with both exact SHAs; keep diagnostic transcripts private. Never generate
a passed report by hand or import a local report into the publication gate. A
failed attempt must be diagnosed, fixed and rerun from a fresh/reset QA instance.

Before any public-repository runner registration, verify the organization group
workbenches-release-qa is restricted to repository opensoft/workBenches only and
workflow opensoft/workBenches/.github/workflows/release-qa-suite.yml@refs/heads/main,
with allows_public_repositories=true and restricted_to_workflows=true. Verify the
release-qa environment allows main only. Missing permission or unsupported policy
blocks registration; never substitute an unrestricted group. Only ephemeral
single-job runners are allowed, with self-hosted,Linux,workbenches-qa,wsl2 labels.
Destroy/reset the guest disk after each job, including cancellation/failure; use
narrow runner-inventory access and never store an operator org-admin token in CI.

Keep WB_QA_CONFIGURED=false until all required workers, live adapters and reset
lifecycle are verified. The GitHub QA accounts already exist as
Opensoft-Test-User-1 and Opensoft-Test-User-2 in Opensoft-Testing; only User 1 belongs
to workbenches-qa-allowed. Renewable sessions are in the dedicated QA vault and
their unattended renewal/team checks already run on main. Do not recreate users,
request passwords in chat, or claim those API checks prove browser/device-flow
acceptance. Company OIDC identities/broker configuration still need provisioning.

Claude/Codex use Team-001@opensoft.one profile Team001, with independent QA logins.
DeepSeek and GLM slots remain pending the user's setup. Do not copy subscription
refresh tokens into public Actions jobs or use production backup sessions. Real
account-auth coordination belongs in private infrastructure; consult the current
provider QA guide. These live suites are separate from WSL-native acceptance.

Report exact automation/candidate SHAs, every executed case/result, guest reset
and cleanup evidence, and any remaining prerequisite. Stop unneeded QA helpers.
If organization access is missing, complete local isolated WSL acceptance first
and report registration as blocked without weakening its policy.
