# Merge acceptance

Use a unique Compose project so the disposable Docker engine and volumes cannot
collide with an earlier run. The engine has no host Docker socket or home mount.
The workstation uses a fresh home, public bootstrap and anonymous HTTPS fallback.
It installs a CLI, signs in to a real temporary Vaultwarden over verified HTTPS,
recovers a generated invalid AI key, installs and opens pyBench, and checks
repeat setup, cancellation, guarded checkout removal and a real npm network failure.
Default CLI installation needs only the TUI action and preserves custom shell
settings. AI accounts is explicitly selected for recovery after installation.
Native bench setup must include Wave mounts at first creation. The acceptance
check uses ordinary `--check` without repair, and simple Vaultwarden recovery
requires at most eight responses when an assistant is selected with AI accounts. Ordinary launches preserve live containers.
The only clone modification adds trust for the private test CA to the credential
image. No TLS verification is disabled. Hosted MFA/SSO and paid AI authorization
still require separate test accounts and are not claimed by this test.

```bash
export WORKBENCHES_ACCEPTANCE_REF=your-branch
export WORKBENCHES_ACCEPTANCE_SHA=$(git rev-parse HEAD)
mkdir -p artifacts/workstation-acceptance
docker compose -p workbenches-acceptance-test -f devcontainer.test/docker-compose.yml \
  --profile workstation-acceptance up --build --abort-on-container-exit \
  --exit-code-from workstation-acceptance acceptance-engine workstation-acceptance
docker compose -p workbenches-acceptance-test -f devcontainer.test/docker-compose.yml \
  --profile workstation-acceptance down --volumes
```

For a cold public-image benchmark, also export
`WORKBENCHES_ACCEPTANCE_REQUIRE_PUBLIC=1` before creating a fresh project. This
requires an empty shared-image cache and verified downloads of both shared
images, rejects local-build fallback, and records their digests in
`public-images.json`. `results.json` records elapsed time for each install case.

Run the npm 12 CI environment locally through the same declared bench:

```bash
docker compose -f devcontainer.test/docker-compose.yml --profile merge-validation \
  run --build --rm --no-deps npm-integrity
```

Reports are under `artifacts/workstation-acceptance`. They record the tested SHA
and omit generated passwords, session tokens and AI test values. Run against the
final PR head after updating it with `main`; require all GitHub checks on that
head, review the diff, then mark the PR ready and merge. Delete only this test's
Compose project/volumes after testing.

## Real Windows/WSL acceptance

`test-wsl-workstation-acceptance.py` drives the real WSL host's setup TUI. It
requires WSL 2, a separate QA home/clean checkout, frozen-source mode, private
npm prefix, uniquely named helpers, and a disposable engine socket. The native
PTY driver needs host Python only for QA; product setup still runs its Python
in Tools. A Linux workstation container alone cannot satisfy this gate.

First inspect Windows/WSL versions, Docker Desktop's selected Linux engine,
shells, Git, and the socket's owner/group/mode. Exercise native Windows's WSL
guidance separately. If elevation, Desktop UI, or browser approval is necessary,
request manual interaction. Never restart Desktop, change global Docker
configuration, or reuse an engineer's home as part of this test.

Use `bootstrap.sh --branch REF --directory "$HOME/projects/workBenches"` with
an isolated `HOME`; set `GIT_CONFIG_GLOBAL=/dev/null` and
`GIT_CONFIG_NOSYSTEM=1`. To require anonymous HTTPS fallback, set
`GIT_SSH_COMMAND=false` for bootstrap. Initialize all recorded submodules and
verify the intended SHA. Keep reports outside the checkout. Set these variables
only in the QA shell (all paths derive from a private `QA_ROOT`):

```bash
export HOME="$QA_ROOT/home" USER="$(id -un)"
export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share" TMPDIR="$HOME/tmp"
export AGENT_PROTOCOL_ROOT="$HOME/.agents"
export NPM_CONFIG_USERCONFIG="$HOME/.npmrc" npm_config_prefix="$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
export WORKBENCHES_FROZEN=1 WORKBENCHES_WSL_ACCEPTANCE=1
export WORKBENCHES_SKIP_WAVE_WIDGETS=1 WORKBENCHES_SKIP_ESTATE_COMMANDS=1
export WORKBENCHES_SKIP_WORKSPACE_REPO=1 WORKBENCHES_SKIP_PROJECT_COMMAND=1
export WORKBENCHES_TOOLS_CONTAINER="$QA_PROJECT-tools"
export WORKBENCHES_VAULT_CONTAINER="$QA_PROJECT-vault"
export WORKBENCHES_SERVICES_NETWORK="$QA_PROJECT-services"
export WORKBENCHES_TOOLS_IMAGE="workbenches/tools:$QA_PROJECT"
export WORKBENCHES_VAULT_IMAGE="workbenches/vault:$QA_PROJECT"
unset CODEX_HOME CLAUDE_CONFIG_DIR SSH_AUTH_SOCK GH_TOKEN GITHUB_TOKEN
unset OPENAI_API_KEY ANTHROPIC_API_KEY DOCKER_CONTEXT WORKBENCHES_DOCKER_ENDPOINT
```

Use a unique `QA_PROJECT` containing `qa`. Create the directories before starting
the helper. Remove inherited provider-specific home/config/token variables from
the QA shell as well; do not copy real credentials. Windows executable paths may
be added to this shell's PATH if WSL disables Windows PATH import.

Start the declared `acceptance-engine` service with a private Compose override
that bind-mounts `$HOME` and `$QA_ROOT/socket` at their original absolute paths,
also mounting the socket directory at `/var/run`. For WSL GUI mounts, include
`/mnt/wslg` and `/usr/lib/wsl` read-only. These are host-local override files,
never committed machine paths. The engine must have no host Docker socket or
real home mount. Shared base images may be imported into this engine as a cache;
record whether the run used cached or freshly downloaded images.

```bash
python3 "$HOME/projects/workBenches/devcontainer.test/test-wsl-workstation-acceptance.py" \
  --repo "$HOME/projects/workBenches" --report "$QA_ROOT/report" \
  --sha "$WORKBENCHES_ACCEPTANCE_SHA" --engine "unix://$QA_ROOT/socket/docker.sock"
```

`--phase desktop` runs Tools, actual CLI install/update/cancel/failure/removal,
host Bash/Zsh startup, and managed Vault readiness on Desktop. `--phase bench`
can continue on the empty disposable engine after the desktop phase, testing
actual pyBench installation, Bash/Zsh/Wave startup, update, removal, and frozen
source refusal with local work. The all-phase default runs both. Every selected
row must finish inventory before the test submits it; exit zero alone cannot
establish that a component was installed. Assertions check actual artifacts.

The phase report records failures and cases not run, and never reports the full
gate complete for a partial phase. Project/credential/prompt witnesses, original
Desktop resource IDs/images/volumes, and source-lock bytes are checked. Retain
separate before/after hashes for the real workstation's inventoried credentials
and shell/Git files. Publish only sanitized commands/results and exact tested
commits in the release checklist; local PTY logs remain private. Clean up only
the named QA project, helpers, images, and volumes after reviewing the report.
