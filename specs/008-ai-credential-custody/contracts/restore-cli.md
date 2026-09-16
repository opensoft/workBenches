# Restore CLI Contract

## Command

```text
backup-ai-profile-credentials-to-kv.sh restore [options]
```

## Selection options

- `--provider NAME`: select one provider
- `--profile NAME`: select one canonical profile
- Both filters may be combined.

## Safety options

- `--force`: authorize replacement of an existing canonical credential for this invocation only
- Without `--force`, existing targets are preserved and not downloaded.

## Inputs

- Owner-only regular manifest file
- Azure CLI authority supplied out of band
- Enabled manifest entries matching optional filters

Supported credential schemas include Claude profile OAuth bundles, Codex
profile bundles, Pi profile objects, and the standalone OmniRoute OpenCode
provider record. The OmniRoute target is the owner-only workBenches credential
directory, not OpenCode's mixed-provider authentication file.

## Required checks

1. Manifest schema, owner, mode, and uniqueness
2. Azure subscription tenant and vault existence
3. Provider-specific target-root containment and non-symlink target chain
4. Secret metadata and concrete versioned URI
5. Content type and `company`, `provider`, `profile`, and `managedBy` tags
6. Downloaded size, JSON object, and provider credential structure
7. Atomic mode-0600 install
8. Exact version URI state record

After an OmniRoute restore, `opencode-omniroute-credential install` performs a
second validated atomic operation that changes only the `omniroute` member of
OpenCode's shared authentication object. An existing different member is
preserved unless that installer receives explicit replacement authorization.

## Output

Human-readable status lines contain only status, provider, profile, and version URI. The final line reports selected, passed, preserved, and failed counts. Credential values and decoded claims are forbidden.

## Exit status

- `0`: all selected entries restored or safely preserved
- `1`: one or more selected entries failed validation or materialization
- `2`: usage error
