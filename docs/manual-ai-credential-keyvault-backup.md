# Manual AI Credential Backup to Azure Key Vault

This runbook provides the interim operator path for backing up managed AI
profile credential bundles until openProfiler provides brokered backup and
restore.

## Security boundary

- Use a dedicated vault for each company/security boundary.
- Store each provider/profile bundle as a separate secret version.
- Never add credential values or real credential files to Git.
- Keep the local manifest and state registry owner-readable only (`0600`).
- Do not back up default homes, browser sessions, keyrings, legacy duplicates,
  or ambiguous folders.
- Treat a backup as a point-in-time snapshot. OAuth refresh-token rotation can
  make an older version unusable.

Azure Key Vault encrypts secret values at rest and Azure CLI sends them over
TLS. The interim tool uploads opaque credential files with `--file`; it never
prints token values. The future openProfiler broker should add managed identity,
private networking, rotation detection, and a reviewed portable encryption
format if cross-tenant escrow is required.

## Local manifest

Install a private manifest at:

```text
~/.config/workbenches/ai-credential-keyvault.json
```

Start from `config/ai-credential-keyvault.example.json`. The manifest contains
paths and secret identifiers, not token values, but it still exposes account
inventory and must remain private.

Each entry maps exactly one canonical source file to one Key Vault secret:

```json
{
  "provider": "claude",
  "profile": "team-001",
  "credentialPath": "~/.claude-profiles/profiles/opensoft/team/team-001/.credentials.json",
  "secretName": "ai-credential-claude-team-001",
  "enabled": true
}
```

## Audit and backup

Audit local files without contacting Azure:

```bash
scripts/backup-ai-profile-credentials-to-kv.sh audit
```

Upload every enabled entry and verify each exact new secret version:

```bash
scripts/backup-ai-profile-credentials-to-kv.sh backup
```

Limit either command to a provider or profile:

```bash
scripts/backup-ai-profile-credentials-to-kv.sh audit --provider claude
scripts/backup-ai-profile-credentials-to-kv.sh backup --profile team-008
```

Verify the exact versions recorded by the most recent successful backup:

```bash
scripts/backup-ai-profile-credentials-to-kv.sh verify
```

The default local state registry is:

```text
~/.local/state/workbenches/ai-credential-keyvault-backups.json
```

It contains no credentials or hashes. It records source paths, timestamps, and
the immutable Key Vault version URI used for restore verification.

## Restore guardrail

The tool intentionally does not automate restore. Before replacing a local
credential file:

1. Stop every process that uses the target profile.
2. Confirm the target provider, profile, company, and secret version.
3. Preserve the current local file as a separate protected recovery copy.
4. Download to a temporary owner-only file.
5. Validate the provider shape and install atomically with mode `0600`.
6. Start one profile process and verify account identity before wider use.

Never merge token fields between versions. Refresh-token families are coherent
credential bundles and must be restored as a unit.
