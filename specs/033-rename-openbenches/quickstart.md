# Quickstart: staged rename verification

All repository commands run from the feature worktree unless noted. Use the declared Tools/dev-bench/container surfaces. Do not use real credentials or publish images for these checks.

## 1. Governance and focused checks

```bash
openspec validate rename-workbenches-to-openbenches --strict --no-interactive
bash scripts/tools-command.sh python3 devcontainer.test/test-openbenches-contract.py
bash scripts/tools-command.sh python3 devcontainer.test/test-install-friction.py
bash scripts/tools-command.sh python3 devcontainer.test/test-git-transport.py
bash scripts/tools-command.sh python3 devcontainer.test/test-project-command.py
bash scripts/tools-command.sh python3 devcontainer.test/test-release-version.py
bash scripts/tools-command.sh python3 devcontainer.test/test-profile-multi-identity.py
bash scripts/tools-command.sh python3 devBenches/base-image/update-upstream.py check
bash devcontainer.test/test-base-image-dockerfile.sh
bash devcontainer.test/test-shared-mcp-profiles.sh
git diff --check
```

## 2. Compatibility matrix

Use synthetic HOME/checkout fixtures and verify:

- old checkout only, new checkout only, both present, and explicit root override;
- old/new/equal/conflicting environment pairs, Tools forwarding, and mixed-version lane handoff;
- old/new command aliases and unrelated command-collision preservation;
- old/new/both config roots with no profile duplication or credential merging;
- one credential-sync agent, lock, and lease root;
- native/WSL openProfiler manifest fallback using synthetic files only;
- old GHCR manifests and labels, new source labels, and rejection of unapproved registries.

## 3. Declared acceptance runners

Run the Tools-runtime, credential-sync, component-lifecycle, and disposable workstation-acceptance profiles in `devcontainer.test/docker-compose.yml` using the repository's documented commands. Execute separate cases:

1. fresh canonical `openBenches` installation;
2. existing legacy checkout/configuration upgrade;
3. frozen installation for each supported release line.

## 4. Dependent gates

- openRepoProject: `python3 -m unittest discover -s tests -v` in the Python workBench.
- openRepoTools: focused shell suites and its normal CI suite of record.
- openRepoKit: `make validate`, `python3 code/openRepoKit verify`, and `python3 -m unittest discover -s code/tests -v` from its assembly root.
- openProfiler: documented frontend/core tests in an approved environment plus native/WSL synthetic fallback fixtures.
- All five bench `bench-init.yml` workflows after their checkout-repository update.

## 5. Cutover and release gates

Before the GitHub rename, verify target availability, quiet QA/release activity, dependent readiness, and explicit admin approval. Afterward verify old/new Git URLs, raw bootstrap and release-asset URLs, old issue links, rulesets, environments, and direct-reference updates. Do not recreate the old repository name.

Require full Release validation on the exact final head and applicable protected release-mode QA for the first `openBenches` release. Publish only the approved tested commit, regenerate the source lock with release tooling, and never retag or edit old releases.
