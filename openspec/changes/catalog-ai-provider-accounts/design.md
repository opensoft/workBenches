## Context

The private owner registries already contain profile-centric `ai/source.json` files with stable `accountId` and `credentialId` values. Opensoft credentials are mapped to Azure Key Vault metadata, while Brett credentials use private SOPS references. These structures answer how a launcher obtains a credential, but they do not independently model the commercial account with a model hoster, its subscription, or all profiles and credentials attached to that account.

The change spans two private repositories and the public workBenches tooling. Account metadata may include login addresses and subscription details and therefore remains private. Credential payloads must remain outside every account catalog and outside report output.

## Goals / Non-Goals

**Goals:**

- Establish one account-level catalog per owner repository.
- Normalize model hosters independently from product/launcher names.
- Link account, profile, and credential records with stable IDs.
- Produce a combined metadata-only inventory and validation result across authorized registries.
- Detect duplicates, orphans, ownership inconsistencies, and active credentials without durable escrow.

**Non-Goals:**

- Move, rotate, decrypt, upload, or restore any credential payload.
- Treat an email domain, profile name, or local path as proof of ownership.
- Make the public workBenches repository authoritative for private account metadata.
- Query provider billing APIs or infer plan entitlements from OAuth token claims.

## Decisions

### Keep canonical catalogs in the owner repositories

Each private repository gains `ai/accounts/providers.json` plus one `<provider-id>.json` file per hoster with accounts. Account records use the repository owner as an explicit boundary. A third canonical aggregate repository is rejected because it would duplicate ownership state and make personal recovery dependent on company infrastructure.

### Separate provider, account, profile, and credential identities

Provider IDs identify hosters such as `anthropic`, `openai`, `google`, `xai`, and `z-ai`. Account records use the existing stable `accountId`; they reference profile keys and credential IDs. Existing profile records keep `accountId` as their account reference, and their embedded authentication metadata gains the same account reference. This preserves compatibility while making both directions verifiable.

### Store only non-secret subscription metadata

Account records may contain login email, product names, declared plan, billing model when known, lifecycle, and verification date. They MUST NOT contain tokens, API keys, cookies, credential paths outside approved metadata references, secret values, or decoded claims. Unknown commercial facts remain `unknown` rather than inferred.

### Validate registries locally and compose reports at runtime

workBenches provides one command that accepts multiple explicitly authorized registry roots. It validates each root independently, then detects cross-owner duplicate account and credential IDs and produces a provider/owner summary. Generated reports are outputs, not another source of truth.

### Derive escrow state from existing metadata contracts

For Opensoft, enabled Azure Key Vault mappings establish configured durable coverage. For Brett, `available` SOPS metadata plus a safe regular ciphertext file establishes configured coverage. Active credentials without the appropriate configured durable reference are reported as missing escrow. The command never reads ciphertext or retrieves Azure secret values, so it does not claim live provider usability.

## Risks / Trade-offs

- **Catalog and profile metadata can drift** → The combined validator checks both directions and CI can run it whenever either private registry changes.
- **One commercial account may legitimately serve several profiles** → Account records allow multiple profile references and credential IDs; uniqueness applies to stable IDs, not a forced one-to-one count.
- **Configured escrow may be stale or unusable** → Reports say configured/declared escrow and explicitly avoid claiming live secret or provider validity.
- **Provider terminology changes** → `providers.json` holds stable internal IDs and display names separately from products/models.
- **Private repositories cannot be validated by public CI together** → The command supports individual validation and an authorized local combined run.

## Migration Plan

1. Add provider catalogs and account records generated from current profile metadata in each private repository.
2. Add account references to existing authentication metadata without changing credential locations.
3. Add the public schema, combined validator/report, and fixtures.
4. Run individual and combined validation and reconcile every reported orphan or duplicate.
5. Manage future hoster accounts in the owning private catalog before adding profiles or credentials.

Rollback removes the new account catalogs and account-reference fields; existing profile launchers and credential custody remain unchanged.

## Open Questions

None. Billing model and entitlement fields remain explicitly `unknown` until verified rather than blocking the catalog.
