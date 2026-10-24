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

### Requirement: Interactive native login handoff
Wizard/dashboard sign-in SHALL provide a native terminal/PTY with the selected
profile environment, live input, cancellation, process cleanup, completion
detection and return to saved navigation/queue. Noninteractive file callbacks
or closed stdin SHALL NOT qualify this path. Secret input/transcripts SHALL NOT
be recorded in diagnostic logs or RPC arguments.

#### Scenario: Cancel Kimi login through Tools
- **WHEN** a user starts Kimi login from the wizard through Tools and cancels in its native terminal
- **THEN** child processes are cleaned up and the wizard resumes its saved focus and queued changes
- **AND** entered secrets do not appear in logs and no authentication success is inferred

### Requirement: Projection-aware synchronization
Recovery and the actual sync client SHALL use inspect/extract/validate/
fingerprint/merge-install adapters for qualified native layouts. Projection
fingerprints SHALL be distinct from backing-file revisions. Atomic installation
SHALL preserve unrelated records and reject selected-record conflicts under
qualified native-writer coordination; a broker/advisory lock alone is insufficient.

#### Scenario: Unrelated OpenCode login changes during download
- **WHEN** another native provider member changes while a GLM credential is downloading
- **THEN** the GLM restore retains that change and publishes only the selected projection
- **AND** a changed selected member causes a conflict rather than overwrite

#### Scenario: Crash after merged installation
- **WHEN** execution stops after merge/install and before the local baseline is persisted
- **THEN** durable reconciliation completes or reports conflict without duplicate publication or unrelated-data loss

### Requirement: Owned binding and stable control plane
Company enrollment SHALL select an owned metadata profile, derive its native
target/member and bind immutable local/provider/auth-mode/broker IDs using
qualified account evidence. Personal/default roots, including their custom locations, SHALL be excluded; validated company profiles in custom roots SHALL remain eligible.
Authentication mode, synchronization policy and projection schema version SHALL
be separate fields with explicit backward compatibility. Vendor child XDG
changes SHALL NOT redefine workBenches company configuration or lease roots.

#### Scenario: GLM launch uses its isolated XDG home
- **WHEN** a managed GLM profile runs with profile-local XDG directories
- **THEN** before-launch and after-login sync use the original company configuration and same lease
- **AND** the selected native provider member is verified against its declared mode and endpoint

### Requirement: Effective account routing and qualified clients
Launch/login/logout/status SHALL target or verify the selected native account,
provider member, mode and endpoint despite Kimi/OpenCode override precedence.
The actual executable/package/runtime SHALL be qualified with feature 032
installation evidence; a command name, version string or stale receipt alone is
insufficient. Managed self-updates SHALL NOT bypass workBenches update ownership.

#### Scenario: An external legacy Kimi shadows the managed client
- **WHEN** PATH resolution or an executable override selects a different package or unqualified version
- **THEN** affected credential operations report an actionable unsupported state without modifying stored credentials
- **AND** upgrades, rollbacks or layout changes invalidate stale qualification

#### Scenario: Legacy configuration is migrated
- **WHEN** native legacy migration imports configuration/history without OAuth tokens
- **THEN** a selected OAuth mode remains login-required while API-key imports receive normal selected-mode presence/verification assessment
- **AND** a legacy-name collision cannot copy credentials into another identity

### Requirement: Bound observations and explicit model effort
Verification SHALL be bound to selected projection fingerprint, endpoint, account
and client identity/version; changes SHALL invalidate it. K3.1 Pro max effort
SHALL be explicitly configured/verified rather than inferred from the high
vendor default. Native endpoint IDs and aliases SHALL be validated, and observed
model substitution SHALL NOT count as requested-model success.

#### Scenario: A different credential replaces the verified one
- **WHEN** key rotation or an account/endpoint switch changes the binding
- **THEN** old verification is stale even if a credential file remains present
- **AND** a default login does not authenticate an empty named profile

### Requirement: Nonempty milestone evidence and runtime packaging
M1 local profiles/login/persistence, M2 qualified personal retrieval and M3
company synchronization SHALL have separate outcomes. The plan's named minimum
M2 rows SHALL pass on every claimed platform before a combined retrieval claim.
Real Tools/dashboard and sync boundaries, affected existing suites, and shared
adapter imports in both runtime images SHALL be verified. Exact-head evidence
SHALL match repository, commit, trusted workflow and required cases.

#### Scenario: All remote modes are disabled
- **WHEN** local profiles work but no required recovery row is qualified
- **THEN** only M1 can be accepted and retrieval is explicitly deferred
- **AND** neither personal recovery nor a green unrelated run qualifies company sharing
