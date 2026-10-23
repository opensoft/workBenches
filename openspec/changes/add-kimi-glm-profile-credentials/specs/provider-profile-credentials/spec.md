## ADDED Requirements

### Requirement: Independent provider accounts
Profiles SHALL support multiple personal/company Kimi Code and GLM accounts
using explicit provider-specific authentication, isolated runtime homes and
secret-free identity metadata. Linking an identity SHALL NOT authenticate it,
copy another account's credential, or grant company access.

#### Scenario: Two accounts in one company
- **GIVEN** two email identities and provider accounts within one company
- **WHEN** their Kimi or GLM profiles are created and launched
- **THEN** each uses a distinct home and selected credentials without changing the other or the native default account

### Requirement: Persistent provider homes
Selected profile homes SHALL persist across bench restart/recreation and host
reboot through approved shared-home mounts, with validated paths and owner-only
credential files. Setup and uninstall SHALL preserve existing homes by default.

#### Scenario: Recreate a bench
- **GIVEN** Kimi and GLM accounts have completed sign-in
- **WHEN** the bench is recreated with its approved persistent mounts
- **THEN** the same homes and credential material remain available without being baked into an image
- **AND** expired or revoked access is reported without a promise that reboot preserves provider authorization

### Requirement: Bounded credential custody
Recovery and company synchronization SHALL use versioned, provider-scoped
credential adapters with explicit consent, supported mode checks and exact
profile binding. Imports SHALL preserve unrelated records and local unsent changes.
Company use, publication and maintenance SHALL retain separate grants.

#### Scenario: Recover one GLM key
- **WHEN** an authorized user restores a selected GLM Coding Plan profile
- **THEN** only its Z.AI credential record is installed into that profile
- **AND** other OpenCode provider credentials and configuration remain intact

#### Scenario: An unqualified OAuth mode
- **WHEN** a Kimi OAuth mode has not been qualified for remote recovery or company refresh/sharing
- **THEN** local sign-in remains available but those remote operations remain explicitly unsupported
- **AND** company membership or a supplied email cannot enable them

### Requirement: Truthful status and recoverable changes
Status SHALL distinguish configured profiles, local credential presence, last
verified provider access, model entitlement, and synchronization freshness.
Concurrent publication, interrupted writes, stale versions and unavailable stores
SHALL reconcile through the existing durable recovery protocol without credential
logging, silent account switching or replay of an ambiguous refresh.

#### Scenario: Credential exists but verification fails
- **WHEN** a stored key is expired, denied, unreachable or not verifiable
- **THEN** the UI reports that condition separately from local presence
- **AND** no cached presence label claims authenticated access or a K3.1 entitlement

### Requirement: Preserved setup behavior and explicit model selection
Profile actions SHALL preserve queued component changes and wizard focus. CLI
installation and credential support SHALL remain separate capabilities. Kimi
model choices SHALL follow the current account's available models and shall not
silently replace an unavailable requested model.

#### Scenario: Add a Kimi account from the wizard
- **GIVEN** a bench installation is queued
- **WHEN** the user opens Profiles, signs in to a Kimi profile and returns
- **THEN** the queue and navigation state remain unchanged
- **AND** model selection is explicit and no inference request runs during rendering
