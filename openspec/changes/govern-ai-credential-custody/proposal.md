## Why

Opensoft-owned and Brett-owned AI profile credentials currently have overlapping SOPS and Azure Key Vault escrow conventions, while the live workstation mapping is more complete than either repository contract. A single ownership-aware custody model is needed so a new Linux workstation can recover only the credentials its operator is authorized to use without making workBenches or a workstation the source of truth.

## What Changes

- Make `opensoft/Opensoft-Tenant` the canonical metadata registry for every Opensoft-owned AI profile and Azure Key Vault the canonical durable store for its credential payloads.
- Keep `brettheap/AI-Credentials` as the canonical metadata and encrypted-escrow registry for Brett-owned profiles, with Brett-controlled recovery material outside Opensoft custody.
- Explicitly forbid inferring ownership from an email domain or mixing personal and tenant credentials in one vault merely by naming prefix.
- Add a versioned, non-secret Azure Key Vault contract that maps credential IDs to secret names and records lifecycle state without credential contents.
- Add a guarded workBenches restore operation that validates tenant, subscription, vault, local target ownership, file mode, JSON shape, and exact downloaded secret version before atomically materializing credentials.
- Treat the Opensoft-owned OmniRoute client credential as a standalone secret, restore it before interactive OpenCode authentication, and merge only the OmniRoute provider record into OpenCode's shared authentication file.
- Preserve existing valid local credentials unless an operator explicitly requests replacement, and keep all command output secret-safe.
- Reconcile documentation and validation so SOPS is either personal custody or an explicitly declared disaster-recovery copy, never an ambiguous competing primary for Opensoft credentials.

## Capabilities

### New Capabilities

- `ai-credential-custody`: Defines ownership, registry, durable-store, authorization, restore, audit, and lifecycle requirements for tenant-owned and person-owned AI credentials.
- `key-vault-profile-restore`: Provides a guarded, secret-safe restore workflow from an approved Azure Key Vault to isolated local provider profiles.

### Modified Capabilities

None.

## Impact

- `workBenches`: credential escrow CLI, manifest validation, tests, and account-management documentation.
- `workBenches` setup: best-effort authorized OmniRoute recovery precedes the OpenCode login prompt and falls back without exposing credential material.
- `opensoft/Opensoft-Tenant`: `ai/source.json`, Azure vault metadata, company credential documentation, and PR #1 registry contract.
- `brettheap/AI-Credentials`: personal ownership documentation, escrow coverage reporting, and optional secondary-custody policy.
- Azure: read-only restore access to `kv-opensoft-aiprof-p01`; no plaintext values enter Git, logs, command arguments, or chat.
- Operators: company and personal credentials use distinct authorities and recovery procedures even when login addresses share the `opensoft.one` domain.
