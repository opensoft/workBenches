# Research: AI Credential Custody

## Decision: Opensoft Azure Key Vault is canonical for company payloads

**Rationale**: Existing operations already create and byte-verify versioned secrets in `kv-opensoft-aiprof-p01`. Central Azure authorization avoids distributing the tenant age recovery identity to every workstation and supports exact-version read-back.

**Alternatives considered**: Keep SOPS canonical and Key Vault as a mirror; use workstation files as source of truth. Both were rejected because they either distribute tenant recovery keys or make one workstation's state authoritative.

## Decision: escrow OmniRoute independently from OpenCode shared auth

**Rationale**: OpenCode's shared `auth.json` can contain credentials owned by
different people and providers. The Opensoft vault therefore stores only the
validated OmniRoute `{type, key}` provider record. Bootstrap restores that
record through the same exact-version Key Vault controls and atomically merges
only `.omniroute`, preserving unrelated providers.

**Alternatives considered**: Store the complete OpenCode authentication file;
require a new interactive OmniRoute login on every workstation. The former
violates ownership isolation and the latter discards an approved durable
credential that can be recovered safely.

## Decision: Personal SOPS plus independently held recovery identity remains canonical

**Rationale**: The private AI-Credentials repository already separates encrypted payload durability from the recovery identity held in Brett's 1Password. This keeps personal recovery independent of Opensoft employment or tenant access.

**Alternatives considered**: Place personal secrets in the Opensoft team vault using a name prefix. Rejected because naming does not enforce custody and company administrators control the subscription.

## Decision: Restore latest metadata, then pin exact version

**Rationale**: A fresh workstation has no local state registry. Querying non-secret metadata by name obtains a versioned URI; validating and downloading that exact URI avoids a time-of-check/time-of-use change to an unversioned latest value.

**Alternatives considered**: Require a pre-populated state file; download by unversioned name. The former prevents bootstrap and the latter can retrieve a different generation after validation.

## Decision: Preserve local credentials unless `--force`

**Rationale**: A current provider login may be newer than escrow. Safe recovery should never replace it implicitly. Explicit replacement is auditable and can be limited to one provider/profile.

**Alternatives considered**: Compare token timestamps and auto-select. Rejected because provider formats differ and local expiry does not prove provider usability or generation preference.

## Decision: Test Azure behavior through a fake CLI

**Rationale**: Tests must cover metadata, version IDs, downloads, and failures without network access or real secret values. A fake CLI gives deterministic command-contract coverage and asserts that no secret appears in output.

**Alternatives considered**: Live Key Vault integration tests. Rejected for routine tests because they require authority, mutate state, cost latency, and risk handling real credentials.
