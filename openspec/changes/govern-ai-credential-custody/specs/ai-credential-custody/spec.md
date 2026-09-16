## ADDED Requirements

### Requirement: Credential ownership is explicit
Every credential record MUST identify exactly one owner type and owner ID, and ownership MUST NOT be inferred from its email domain, profile name, workstation location, or current operator.

#### Scenario: Personal account uses a company email domain
- **WHEN** a Brett-owned subscription uses an `opensoft.one` login address
- **THEN** the record remains owned by `user/brettheap` and is excluded from the Opensoft canonical vault mapping

### Requirement: Tenant profiles are completely registered
The Opensoft tenant registry SHALL contain a non-secret record for every active, planned, disabled, or retired Opensoft-owned AI profile, including provider, canonical name, aliases, expected login, account ID, credential ID, lifecycle state, and durable-store reference.

#### Scenario: A team profile is added to workBenches
- **WHEN** an Opensoft-owned profile appears in a provider manifest
- **THEN** registry validation reports failure until the corresponding tenant record and durable-store mapping exist or the profile is explicitly classified as planned without a credential

### Requirement: Canonical durable stores follow ownership
Opensoft-owned credential payloads MUST use the approved Opensoft Azure Key Vault as canonical durable storage. Brett-owned credential payloads MUST use Brett-controlled escrow unless an explicit secondary-custody agreement says otherwise.

#### Scenario: Operator proposes a Brett prefix in the company vault
- **WHEN** a personal credential is mapped to an Opensoft vault solely by a `brett-*` secret name
- **THEN** validation rejects the mapping because naming is not an ownership boundary

### Requirement: Git contains no plaintext credentials
Registry repositories MUST contain only metadata, ciphertext produced by an approved encryption policy, and external-vault references; they MUST NOT contain plaintext OAuth tokens, API keys, browser cookies, or recovery private keys.

#### Scenario: Registry changes are reviewed
- **WHEN** a credential-registry change is validated
- **THEN** committed files contain no provider payload fields or plaintext recovery identity

### Requirement: Tenant SOPS status is unambiguous
Any Opensoft SOPS credential retained after Azure Key Vault becomes canonical MUST be explicitly classified as legacy disaster-recovery material or deprecated, and MUST NOT be represented as a second canonical source.

#### Scenario: Same credential exists in SOPS and Key Vault
- **WHEN** both stores contain a generation for one credential ID
- **THEN** documentation and metadata identify Key Vault as canonical and describe the SOPS copy's recovery-only lifecycle

### Requirement: Personal recovery remains independent
Brett-owned credential recovery MUST remain possible without access to the Opensoft Azure tenant unless Brett has explicitly selected an Opensoft-managed secondary escrow arrangement.

#### Scenario: Opensoft access is unavailable
- **WHEN** Brett bootstraps a personal workstation without Opensoft Azure access
- **THEN** available personal ciphertext can be restored using Brett's private registry and recovery identity

### Requirement: Reconciliation is secret-safe
Registry reconciliation MUST compare only metadata, file presence, sanitized credential structure, vault metadata, and version identifiers; it MUST NOT print or transmit credential values.

#### Scenario: Coverage report is generated
- **WHEN** an operator compares workstation, registry, and vault coverage
- **THEN** the report lists ownership and lifecycle discrepancies without token contents
