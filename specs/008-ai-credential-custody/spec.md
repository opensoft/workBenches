# Feature Specification: AI Credential Custody

**Feature Branch**: `008-ai-credential-custody`

**Created**: 2026-09-15

**Status**: Approved for implementation

**Input**: User description: "Document every Opensoft-owned team profile in Opensoft-Tenant and keep it durably in the Opensoft tenant Key Vault; document Brett-owned profiles in brettheap/AI-Credentials and keep their recovery independent and durable."

## User Scenarios & Testing

### User Story 1 - Recover an Opensoft profile from company custody (Priority: P1)

An authorized Opensoft operator preparing a new Linux workstation can discover every company-owned profile, identify its approved durable secret, and restore a selected valid credential without exposing the credential or overwriting an existing login accidentally.

**Why this priority**: Company profiles support shared engineering work and currently depend on workstation-local state plus an incompletely documented vault mapping.

**Independent Test**: Starting with an empty selected profile and an authorized, metadata-valid vault entry, restore the profile and confirm that exactly one protected credential file is installed and the selected CLI recognizes it.

**Acceptance Scenarios**:

1. **Given** an authorized operator, a registered company profile, and a matching durable secret, **When** the operator restores that profile, **Then** the exact approved secret generation is validated and installed at the canonical profile path.
2. **Given** a valid local credential already exists, **When** restore is run without replacement authorization, **Then** the local credential remains byte-for-byte unchanged.
3. **Given** the active tenant, vault, secret metadata, or payload does not match the registry, **When** restore is attempted, **Then** no local credential is created or replaced.

---

### User Story 2 - Audit complete Opensoft profile custody (Priority: P2)

An Opensoft administrator can compare company profile definitions, lifecycle states, and durable-store mappings and identify every missing, retired, duplicated, or mis-owned profile without retrieving secret values.

**Why this priority**: Recovery is trustworthy only when the registry and vault mapping cover the whole company-owned profile set.

**Independent Test**: Run metadata-only validation against a fixture containing complete, missing, duplicated, retired, and personal records and confirm that every discrepancy is classified without payload output.

**Acceptance Scenarios**:

1. **Given** an Opensoft-owned profile in a provider manifest, **When** no tenant registry record or durable-store mapping exists, **Then** validation reports the precise missing relationship.
2. **Given** a personal profile that uses an Opensoft email domain, **When** ownership validation runs, **Then** it remains excluded from the company vault requirement.
3. **Given** a retired profile, **When** its mapping is still enabled for active restoration, **Then** validation reports a lifecycle conflict.

---

### User Story 3 - Recover Brett-owned credentials independently (Priority: P3)

Brett can bootstrap a personal workstation and recover every escrowed personal profile without requiring access to the Opensoft Azure tenant, while clearly seeing which personal profiles still lack durable escrow.

**Why this priority**: Personal credentials must not become company-controlled merely because they are used alongside company profiles or use a company email address.

**Independent Test**: With company Azure access unavailable, restore an escrowed personal fixture using the personal registry and confirm that the coverage report identifies non-escrowed personal records.

**Acceptance Scenarios**:

1. **Given** personal encrypted escrow and Brett's recovery identity, **When** personal bootstrap runs, **Then** available personal credentials can be restored without Opensoft Azure access.
2. **Given** a personal credential has no escrow generation, **When** coverage is checked, **Then** the profile remains documented and is reported as requiring login and backup.
3. **Given** Opensoft provides optional secondary escrow, **When** it is documented, **Then** the registry still identifies Brett as owner and describes the company vault as secondary custody only.

---

### User Story 4 - Inventory model-hoster accounts across owners (Priority: P2)

An authorized operator can see how many accounts Brett and Opensoft have with each model hoster, distinguish subscriptions from local profiles and credentials, and identify broken or incomplete relationships without accessing secret values.

**Why this priority**: Provider account and subscription inventory is required for seat planning, billing decisions, lifecycle management, and reliable credential recovery; profile counts alone do not describe commercial accounts.

**Independent Test**: Load isolated Brett and Opensoft fixture registries and confirm the report produces deterministic provider/owner counts while rejecting duplicate IDs, orphan references, ownership conflicts, forbidden secret metadata, and active credentials without configured escrow.

**Acceptance Scenarios**:

1. **Given** valid owner-specific account catalogs, **When** a combined report runs, **Then** it lists account, active-account, credential, configured-escrow, and missing-escrow counts by normalized provider and owner.
2. **Given** an account, profile, or credential relationship references a missing or differently owned record, **When** validation runs, **Then** it identifies the exact broken relationship and fails.
3. **Given** an account catalog contains a credential payload field or token-like value, **When** validation runs, **Then** it rejects the catalog without printing the candidate value.

---

### User Story 5 - Recover OpenCode's Opensoft OmniRoute access (Priority: P1)

An authorized Opensoft operator installing a new workstation receives the company OmniRoute client credential from Key Vault before setup asks for OpenCode authentication, without moving unrelated OpenCode credentials into company custody.

**Why this priority**: OpenCode's shared authentication file can hold several independently owned provider credentials. Escrowing the whole file is unsafe, while failing to restore OmniRoute causes unnecessary login prompts and an incomplete workstation.

**Independent Test**: Starting with an empty OpenCode authentication file and a fake Azure Key Vault containing only a valid OmniRoute provider record, run bootstrap recovery and confirm the record is installed, unrelated records are preserved on subsequent runs, and no key appears in output.

**Acceptance Scenarios**:

1. **Given** an empty workstation with authorized Key Vault access, **When** setup reaches OpenCode credential configuration, **Then** it restores the standalone OmniRoute provider record and does not ask for interactive login.
2. **Given** OpenCode authentication already contains unrelated providers, **When** OmniRoute is installed, **Then** every unrelated provider record remains semantically unchanged.
3. **Given** Azure or the registered secret is unavailable, **When** recovery is attempted, **Then** authentication remains unchanged and setup retains its ordinary login fallback.

### Edge Cases

- A manifest path contains traversal components or resolves through a symlink outside the provider profile root.
- The vault returns a secret with the expected name but tags for another provider, profile, company, or manager.
- The latest vault generation contains invalid JSON, an unsupported credential format, or exceeds the allowed size.
- A credential changes locally while backup is taking its stable snapshot.
- A restore succeeds but local state recording fails; the installed file must remain valid and the failure must be explicit.
- The same canonical profile name exists for multiple providers with separate account and credential IDs.
- A profile changes lifecycle state while an older durable secret version remains retained.

## Requirements

### Functional Requirements

- **FR-001**: Every Opensoft-owned AI profile MUST have one canonical tenant registry record containing ownership, provider, profile identity, expected login metadata, lifecycle state, account ID, and credential ID.
- **FR-002**: Every active Opensoft credential MUST have one enabled non-secret mapping to an approved Opensoft durable secret name.
- **FR-003**: The system MUST distinguish profile definition, local runtime credential, and durable escrow generation as separate states.
- **FR-004**: Ownership MUST NOT be inferred from email domain, profile naming, local path, or current operator.
- **FR-005**: Brett-owned profile metadata and ciphertext MUST remain in Brett's private credential registry and MUST be recoverable independently of Opensoft Azure access.
- **FR-006**: Company-managed secondary custody of a personal credential MUST be explicit and MUST NOT silently become its canonical personal store.
- **FR-007**: Restore MUST verify Azure tenant, subscription, vault, secret name, version identity, provider/profile metadata, and credential format before installation.
- **FR-008**: Restore MUST preserve existing credentials unless replacement is explicitly authorized for that invocation.
- **FR-009**: Restore MUST constrain every target to its provider profile root and reject unsafe symlinks or traversal.
- **FR-010**: Restored credentials MUST be installed atomically as owner-only regular files.
- **FR-011**: Backup, verify, restore, and reconciliation MUST never print credential payloads or decoded token claims.
- **FR-012**: Batch operations MUST report selected, successful, preserved, missing, and failed counts with non-secret reasons.
- **FR-013**: Opensoft SOPS copies retained after migration MUST be explicitly classified as legacy disaster-recovery material rather than a second canonical source.
- **FR-014**: Validation MUST detect registry gaps, duplicate profile or secret mappings, ownership collisions, and lifecycle conflicts using metadata only.
- **FR-015**: Live credential and vault mutations MUST remain separate from code and metadata implementation and receive direct read-back verification.
- **FR-016**: Each owner registry MUST maintain an account-level catalog that distinguishes normalized model hosters from products, profiles, and credential generations.
- **FR-017**: Account catalogs MUST record stable account identity, explicit ownership, login identity, lifecycle, subscription plan, billing model or `unknown`, profile references, and credential IDs without credential values.
- **FR-018**: Existing profile and credential metadata MUST reference an account that exists in the same owner registry.
- **FR-019**: A combined metadata-only report MUST detect duplicate account and credential IDs, orphan relationships, ownership inconsistencies, forbidden secret metadata, and missing active escrow.
- **FR-020**: Combined reporting MUST support deterministic human-readable and machine-readable output without Azure, SOPS, or provider credential access.
- **FR-021**: The Opensoft OmniRoute client credential MUST be escrowed as a standalone provider record and MUST NOT include the complete mixed-provider OpenCode authentication file.
- **FR-022**: Workstation setup MUST attempt guarded OmniRoute recovery before offering OpenCode interactive authentication.
- **FR-023**: Installing the recovered OmniRoute record MUST preserve unrelated OpenCode provider records and use owner-only, atomic file replacement.
- **FR-024**: Failed or unavailable bootstrap recovery MUST leave authentication unchanged and retain the interactive login fallback.

### Key Entities

- **Profile Record**: Non-secret identity and lifecycle metadata for one provider account.
- **Credential Record**: Stable credential ID and authentication contract owned by exactly one tenant or person.
- **Durable Secret Mapping**: Non-secret relationship between a credential record and a vault/secret name.
- **Credential Generation**: One immutable version of an encrypted or vault-held credential payload.
- **Local Materialization**: The protected runtime credential file used by a provider launcher.
- **Custody Policy**: Rules identifying the canonical store, recovery authority, optional secondary escrow, and lifecycle.
- **Provider Definition**: Stable model-hoster identity and its mapped product/profile provider IDs.
- **Provider Account**: One owner-controlled commercial or personal relationship with a model hoster, including subscription metadata and references to profiles and credentials.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Metadata validation accounts for 100% of documented Opensoft-owned profiles as active, planned, disabled, or retired and reports zero silent omissions.
- **SC-002**: A new authorized workstation can restore one selected company credential in a single command without credential values appearing in terminal output or logs.
- **SC-003**: In all overwrite, malformed-payload, wrong-authority, and unsafe-path tests, 100% of pre-existing local credentials remain unchanged.
- **SC-004**: Every Brett-owned profile is documented, and the personal coverage report identifies 100% of profiles lacking durable escrow.
- **SC-005**: Company recovery documentation names one canonical durable store, and personal recovery documentation remains usable without Opensoft Azure access.
- **SC-006**: Automated tests cover successful restore, preserve-by-default, explicit replacement, authority mismatch, metadata mismatch, invalid payload, and unsafe target paths.
- **SC-007**: One command reports 100% of cataloged Brett and Opensoft accounts grouped by normalized provider and owner without accessing credential payloads.
- **SC-008**: Fixture tests detect 100% of required duplicate, orphan, ownership, secret-metadata, and missing-escrow failure classes.
- **SC-009**: A fresh-workstation fixture restores OmniRoute access without exposing the key, and mixed-auth fixtures retain 100% of unrelated provider records.

## Assumptions

- The existing Opensoft Azure Key Vault remains the approved canonical company store.
- Azure authorization is provided out of band and is not acquired by the restore command.
- Existing historical secret versions and SOPS ciphertext are retained during migration.
- Brett's private GitHub credential repository and 1Password recovery identity remain available for personal recovery.
- Initial restore support is limited to provider credential formats with explicit structural validators.
- Live batch restoration is not required to accept the code and metadata implementation; it follows a tested single-profile canary.
