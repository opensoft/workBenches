## ADDED Requirements

### Requirement: Owner-specific account catalog
Each private credential repository MUST maintain an `ai/accounts/` catalog containing only accounts owned by that repository's declared owner.

#### Scenario: Company and personal accounts remain separated
- **WHEN** the Opensoft and Brett account catalogs are loaded
- **THEN** every account owner matches its containing registry and no email domain or profile name overrides that ownership

### Requirement: Stable account identity and subscription metadata
Every account record MUST contain a globally stable account ID, explicit owner, normalized provider ID, login identity, lifecycle, subscription plan, billing model or `unknown`, profile references, and credential IDs.

#### Scenario: Account inventory answers hoster counts
- **WHEN** account records are grouped by provider and owner
- **THEN** the resulting counts identify the number and lifecycle of accounts for each model hoster without counting local aliases as separate accounts

### Requirement: Account references from profiles and credentials
Every profile and credential record MUST reference an account ID that exists in the same owner registry, and each account MUST reference only existing profiles and credentials owned by that registry.

#### Scenario: Orphan relationship is rejected
- **WHEN** a profile or credential references an unknown account, or an account references an unknown profile or credential
- **THEN** validation reports the exact orphan relationship and returns a failing result

### Requirement: Secret-free account metadata
Account catalogs MUST NOT contain credential payloads, access tokens, refresh tokens, API-key values, cookies, private keys, decoded claims, or unrestricted local credential paths.

#### Scenario: Secret-like catalog field is rejected
- **WHEN** an account catalog contains a forbidden payload key or token-like value
- **THEN** validation rejects the catalog without echoing the candidate value

### Requirement: Provider normalization
Each account MUST reference a provider defined in `providers.json`, and each provider definition MUST map the private registry's profile-provider IDs to a stable model-hoster ID.

#### Scenario: Product and hoster names are distinguished
- **WHEN** a Claude profile and a GLM profile are cataloged
- **THEN** they resolve to the `anthropic` and `z-ai` hoster IDs respectively while preserving their product/profile provider names
