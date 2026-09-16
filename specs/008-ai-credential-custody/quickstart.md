# Quickstart: AI Credential Custody

## Validate the implementation with fixtures

```bash
cd /path/to/workBenches-feature-worktree
bash devcontainer.test/test-ai-credential-keyvault.sh
```

The test uses an isolated home directory and a fake Azure CLI. It must not contact Azure or print fixture credential values.

## Audit a real workstation mapping

```bash
scripts/backup-ai-profile-credentials-to-kv.sh audit \
  --provider claude \
  --profile team-001
```

## Canary restore on an authorized workstation

Only after metadata tests and a live read-only Azure preflight pass:

```bash
scripts/backup-ai-profile-credentials-to-kv.sh restore \
  --provider claude \
  --profile <approved-missing-profile>
```

Do not add `--force` unless replacing the exact profile was separately authorized and its current local state was inspected.

## Verify after restore

```bash
pclaude status <profile>
```

Then perform a minimal sanitized provider request. Local structural validity alone does not prove current provider entitlement.

## Intentionally deferred live operations

This implementation does not upload, replace, or restore a live credential.
The registry reconciliation consumes the existing private workstation mapping
as non-secret configuration only. A live `backup`, `verify`, or `restore`
requires a separately selected canary profile, a currently authenticated Azure
identity with the narrow Key Vault role, and exact-version read-back. Do not
infer live secret usability from metadata validation alone.
