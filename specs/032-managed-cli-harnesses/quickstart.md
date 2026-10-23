# Verification

Run through the declared workstation test service, from this feature checkout:

```sh
docker compose -p workbenches-harness-test -f devcontainer.test/docker-compose.yml \
  --profile merge-validation run --rm --no-deps -T --entrypoint bash npm-integrity -ec '
  python3 devcontainer.test/test-managed-harnesses.py
  python3 devcontainer.test/test-managed-harness-ui.py
  python3 devcontainer.test/test-managed-harness-targets.py
  python3 devcontainer.test/test-tool-catalog.py
  python3 devcontainer.test/test-setup-components.py
  python3 devcontainer.test/test-setup-wizard.py
  python3 devcontainer.test/test-setup-wizard-layout.py
  python3 devcontainer.test/test-cli-filters.py
  python3 devcontainer.test/test-image-layer-budget.py
  bash devcontainer.test/test-ensure-layer3-freshness.sh
  '
```

For suites that inspect Git metadata, mount the owning checkout's Git directory
at the path recorded by the linked worktree. Create the ignored logs directory
before read-only setup tests. Do not run fixtures against real account stores.

Manual preview: start `./setup.sh --select-only`, choose one formerly manual CLI,
queue a bench install/update, and inspect Review's exact target names. Cancel
before Apply for a no-change preview. A separate disposable smoke can perform
public installs; do not launch paid prompts to verify an executable.

Public smoke (network enabled, temporary home; no paid prompts):

```sh
docker compose -p workbenches-harness-smoke -f devcontainer.test/docker-compose.yml \
  --profile merge-validation run --rm --no-deps -T --entrypoint python3 npm-integrity \
  devcontainer.test/smoke-managed-harnesses.py --key kimi_code --key qwen_cli
```

The optional `--docker-recreation` smoke needs the declared `tools-runtime`
service and `WORKBENCHES_DOCKER_GID` set to the local socket's group. It creates
private fixture tags/containers, exercises exact bench binding, and removes only
those resources. It never uses real catalog bench names.
