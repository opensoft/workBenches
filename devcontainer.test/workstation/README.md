# Merge acceptance

Use a unique Compose project so the disposable Docker engine and volumes cannot
collide with an earlier run. The engine has no host Docker socket or home mount.
The workstation uses a fresh home, public bootstrap and anonymous HTTPS fallback.
It installs a CLI, signs in to a real temporary Vaultwarden over verified HTTPS,
recovers a generated invalid AI key, installs and opens pyBench, and checks
repeat setup, cancellation, refusal and a real npm network failure.
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
