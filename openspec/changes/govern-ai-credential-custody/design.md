## Context

workBenches currently backs selected Claude and Codex profile credentials to an Opensoft Azure Key Vault using a private workstation manifest. The live manifest names the tenant, subscription, vault, credential paths, and Azure secret names, but this mapping is not represented accurately in the Opensoft-Tenant registry. The open `agent/ai-credential-registry` branch instead treats SOPS files as primary and refers only generically to an external vault. Brett's private AI-Credentials repository already has a separate user-owned SOPS/age model, but not every personal credential is escrowed.

Credential payloads are high-sensitivity JSON documents. They must never appear in Git plaintext, process arguments, command output, telemetry, or chat. A restore must be safe on a fresh workstation with no local state registry, while preserving an existing valid login unless replacement is explicit.

## Goals / Non-Goals

**Goals:**

- Establish one unambiguous owner and one canonical durable store for each credential.
- Represent every Opensoft-owned profile and its non-secret Key Vault mapping in Opensoft-Tenant.
- Preserve Brett's personal ownership and recovery independence in AI-Credentials.
- Restore an exact Azure secret version atomically into an approved provider profile path.
- Validate Azure context, secret metadata, credential shape, ownership, permissions, and target containment before replacing any local credential.
- Produce useful status and audit output without credential material.
- Restore Opensoft's OmniRoute client credential without placing unrelated OpenCode provider credentials in company custody.

**Non-Goals:**

- Automating provider OAuth consent, mailbox approval, or browser login.
- Moving Brett-owned secrets into Opensoft custody.
- Treating email-domain membership as proof of credential ownership.
- Deleting historical Key Vault versions or SOPS ciphertext during the first migration.
- Restoring arbitrary files or providers that do not have a validated credential schema and approved profile root.

## Decisions

### 1. Ownership selects the registry and durable store

`owner.type=tenant, owner.id=opensoft` records live in Opensoft-Tenant and use the Opensoft Key Vault contract. `owner.type=user, owner.id=brettheap` records live in AI-Credentials and use Brett-controlled SOPS ciphertext plus a recovery identity held outside Git. Email domains are metadata only.

Alternative considered: keep every credential in one Opensoft vault with prefixes. Rejected because a secret-name prefix is not a custody boundary and makes personal recovery dependent on company administration and offboarding.

### 2. Opensoft Azure Key Vault is canonical; SOPS is explicitly secondary

For Opensoft-owned credentials, `kv-opensoft-aiprof-p01` is the canonical payload store. Opensoft-Tenant commits only metadata: Azure resource identity, secret-name mapping, credential ID, provider/profile ownership, state, and lifecycle policy. Existing SOPS files remain during migration but are classified as legacy disaster-recovery material until reconciled or retired.

Alternative considered: SOPS remains canonical and Key Vault is only a mirror. Rejected because the operational workflow already writes and verifies Key Vault generations and new-workstation restoration needs centrally authorized access without distributing the tenant age identity.

### 3. Brett personal custody remains split across GitHub and 1Password

AI-Credentials remains the personal metadata and ciphertext source. Its SOPS ciphertext is durable in a private GitHub repository, while the age recovery identity remains in Brett's 1Password. A future personal cloud vault may be added as secondary escrow, but an Opensoft-owned vault must be documented as company-managed secondary custody and must never silently become canonical.

### 4. Restore resolves and pins a concrete Azure version before download

The restore command queries secret metadata by configured name, validates the returned vault/name/version URI, content type, and management tags, then downloads by that exact version URI. It never downloads an unversioned value after validation. The exact URI is recorded locally for subsequent verification.

Alternative considered: restore only versions already present in the workstation state file. Rejected because a new workstation has no state file.

### 5. Restore is preserve-by-default and atomic

If the canonical target already exists, restore reports it as preserved and performs no Azure download unless `--force` is supplied. A restored payload is downloaded into a mode-0600 temporary file, validated for size and provider-specific JSON shape, and atomically renamed into a parent directory that is owner-controlled and not a symlink. No plaintext backup copy is left behind.

### 6. Restore targets are provider-contained

Claude targets must resolve beneath `${CLAUDE_PROFILES_HOME:-$HOME/.claude-profiles}/profiles`; Codex targets beneath `${CODEX_PROFILES_HOME:-$HOME/.chatgpt-profiles}/profiles`; Pi targets beneath `${PI_PROFILES_HOME:-$HOME/.pi-profiles}/profiles`. The manifest may use `~/...` paths but cannot escape its approved root, traverse symlinks, or target the root itself.

### 7. Registry reconciliation is generated from metadata, not credentials

Reconciliation tooling consumes provider profile manifests and the non-secret Key Vault mapping. It never reads token values. It reports profiles missing from the tenant registry, mappings missing from Key Vault metadata, retired profiles still enabled, and ownership collisions with the personal registry.

### 8. OmniRoute is escrowed as a standalone OpenCode provider record

The OmniRoute client credential is Opensoft-owned. Its canonical Key Vault payload contains only the OpenCode provider record `{type, key}` and never the complete OpenCode `auth.json`. Restore first materializes that bounded credential beneath the owner-only workBenches credential directory, then atomically adds or updates only the `omniroute` member of OpenCode's shared authentication object. Existing OpenAI, Anthropic, Google, GitHub Copilot, or other provider records are preserved.

On workstation setup, recovery is best effort and precedes the interactive OpenCode login prompt. A valid existing OmniRoute record wins without Azure access. Otherwise setup discovers the selected private registry's non-secret Key Vault contract, validates Azure authority and the exact secret version through the guarded restore command, and installs the provider record. Missing Azure CLI, missing login/RBAC, absent mapping, or validation failure produces a sanitized reason and leaves the ordinary login prompt available.

Alternative considered: back up and restore `~/.local/share/opencode/auth.json` as one company secret. Rejected because the file can contain credentials owned by different people and providers, and company custody of the whole file would violate the ownership boundary.

## Risks / Trade-offs

- **Registry and vault drift** → Add deterministic validation that compares canonical profile/credential IDs and secret names without reading payloads.
- **A malicious manifest redirects restore outside profile storage** → Require owner-only regular manifests, provider-specific target roots, non-symlink parents, and resolved containment.
- **Latest secret version is malformed or mis-tagged** → Validate metadata and provider JSON before any target replacement; allow an exact version URI in future without weakening validation.
- **Two primary copies remain during migration** → Mark tenant SOPS explicitly `legacy-dr` and do not delete it until Key Vault coverage and restore have been independently verified.
- **Personal recovery depends on two external services** → Keep encrypted Git history and the recovery identity in separate providers; document an optional secondary Brett-controlled recovery copy.
- **`--force` can replace a working login** → Require an explicit flag, download and validate first, and atomically replace only the exact configured target.
- **Shared OpenCode auth contains mixed ownership** → Escrow only the OmniRoute provider record and merge by provider key while preserving every unrelated record.
- **Bootstrap recovery is unavailable** → Treat recovery as best effort and retain the interactive login fallback; never weaken authority or payload validation to suppress the prompt.

## Migration Plan

1. Add the non-secret Opensoft Azure Key Vault contract and update the registry documentation on `agent/ai-credential-registry`.
2. Reconcile Opensoft-owned profile metadata against the current provider manifests and Key Vault mapping; do not copy payloads into Git.
3. Add and test workBenches `restore` with a fake Azure CLI before any live restore.
4. Validate the live vault context and metadata using cloudBench without retrieving values into logs.
5. Restore one disposable or explicitly selected missing profile and perform sanitized status/provider verification before enabling batch use.
6. Complete Brett-owned SOPS coverage from valid local credentials only after confirming the personal recovery identity and encrypted round-trip.
7. Retain existing SOPS and Key Vault versions through the transition; rollback is selecting the prior local credential or exact prior vault version, not deleting history.
8. Register and back up the standalone OmniRoute provider record, then verify a fake-Azure fresh-workstation restore and one authorized live Key Vault read-back.

## Open Questions

- Whether Opensoft tenant SOPS files will be retained permanently as disaster recovery or retired after Key Vault restore is proven.
- Whether Brett wants an additional personally controlled cloud vault beyond private GitHub SOPS plus 1Password.
