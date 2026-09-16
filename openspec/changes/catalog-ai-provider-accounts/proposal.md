## Why

The current registries describe launcher profiles and credential custody, but they do not provide a canonical account-level view of each model hoster relationship. Operators therefore cannot reliably answer how many Anthropic, OpenAI, Z.ai, Alibaba, or other provider accounts exist, who owns them, which subscriptions they use, or whether every account is connected to an appropriate profile and durable credential.

## What Changes

- Add metadata-only `ai/accounts/` catalogs to the private Opensoft and Brett credential repositories.
- Represent provider accounts separately from local profiles and credential generations, with explicit owner, provider, login identity, subscription, lifecycle, stable account ID, profile references, and credential references.
- Reference account records from the existing profile registries using stable account IDs.
- Keep all credential values exclusively in the existing Azure Key Vault or SOPS custody paths; account catalogs contain no secret values.
- Add a workBenches validator/report that combines multiple authorized owner registries, summarizes accounts by provider and owner, and reports duplicate IDs, orphan account/profile/credential references, missing escrow, and inconsistent ownership.
- Add fixture tests and documentation for the cross-registry contract.

## Capabilities

### New Capabilities

- `ai-provider-account-catalog`: Owner-specific private catalogs describe model-hoster accounts, subscription relationships, and stable references without credential payloads.
- `ai-account-inventory-report`: A metadata-only workBenches command validates and summarizes multiple authorized account, profile, and credential registries.

### Modified Capabilities

None.

## Impact

- Private repositories: `opensoft/Opensoft-Tenant` and `brettheap/AI-Credentials` gain `ai/accounts/` metadata and documentation.
- Public repository: workBenches gains a schema contract, combined validator/report, and isolated tests.
- Existing `ai/source.json` profile records gain stable links to account catalog records.
- Existing Azure Key Vault and SOPS payload locations remain unchanged; no live secret mutation is part of this change.
