## ADDED Requirements

### Requirement: Restore validates Azure authority
Before reading any secret, the restore workflow MUST verify that the selected subscription belongs to the manifest tenant and that the configured vault resolves in that subscription.

#### Scenario: Azure tenant differs from manifest
- **WHEN** the active Azure authority reports a tenant different from the manifest tenant
- **THEN** restore stops before querying or downloading any secret value

### Requirement: Restore pins a concrete secret version
The restore workflow MUST resolve secret metadata to a versioned Azure secret URI, validate that the URI belongs to the configured vault and expected secret name, and download only that exact version.

#### Scenario: Latest approved version is restored
- **WHEN** a configured secret has valid metadata and a concrete version URI
- **THEN** the workflow downloads by that URI and records the same URI in local state

### Requirement: Restore verifies secret metadata
The restore workflow MUST verify provider, profile, company, manager, content type, and secret-name metadata before materializing a payload.

#### Scenario: Secret tags identify another profile
- **WHEN** the configured secret's tags do not match the selected provider and profile
- **THEN** restore rejects the secret without changing the local credential

### Requirement: Restore validates credential payloads
A downloaded payload MUST be a bounded-size JSON object matching the selected provider's credential schema before it can become a local credential.

#### Scenario: Malformed payload is downloaded
- **WHEN** Azure returns invalid JSON, an empty payload, an oversized payload, or missing required provider fields
- **THEN** restore deletes the temporary payload and leaves the target unchanged

### Requirement: Restore is target-contained
The canonical credential path MUST resolve beneath the provider's approved profile root, and neither the target nor its parent chain may redirect through an unsafe symlink.

#### Scenario: Manifest attempts path traversal
- **WHEN** a credential path escapes the approved provider profile root
- **THEN** restore rejects the entry before retrieving the secret

### Requirement: Existing credentials are preserved by default
Restore MUST leave an existing canonical credential unchanged unless the operator explicitly selects replacement for that invocation.

#### Scenario: Credential already exists
- **WHEN** restore is run without replacement authorization and the configured target exists
- **THEN** the workflow reports the target as preserved and does not download or overwrite its payload

### Requirement: Materialization is atomic and owner-only
Restore MUST create an owner-controlled profile directory, stage the validated payload with mode `0600`, and atomically install it without leaving a plaintext recovery copy.

#### Scenario: Successful restore to an empty profile
- **WHEN** all authority, metadata, path, and payload checks pass
- **THEN** exactly one mode-0600 regular credential file appears at the canonical target

### Requirement: Output is secret-safe
Restore output MUST be limited to provider, profile, status, and version identifiers and MUST never include credential values or decoded claims.

#### Scenario: Batch restore completes with mixed results
- **WHEN** some entries restore, some are preserved, and some fail validation
- **THEN** the summary reports counts and non-secret reasons without exposing any payload content

### Requirement: Shared authentication restores only the owned provider record
When one application authentication file contains provider records with different owners, restore MUST escrow and validate the selected provider record independently and MUST NOT place the complete mixed-provider file in one owner's durable store.

#### Scenario: OmniRoute recovery targets OpenCode
- **WHEN** the Opensoft-owned OmniRoute credential is recovered for OpenCode
- **THEN** only the validated `omniroute` provider record is added to OpenCode authentication and all unrelated provider records remain unchanged

### Requirement: Setup recovers before prompting
Workstation setup MUST attempt a registered, authorized, preserve-by-default credential recovery before offering interactive authentication, and MUST retain the interactive fallback when recovery is unavailable or rejected.

#### Scenario: Fresh workstation has Key Vault access
- **WHEN** OpenCode has no OmniRoute provider record and the selected Opensoft registry exposes a valid mapped secret
- **THEN** setup restores and installs the OmniRoute record without launching provider OAuth or printing the key

#### Scenario: Azure authority is unavailable
- **WHEN** setup cannot validate the configured Azure tenant, subscription, vault, or secret
- **THEN** it leaves local authentication unchanged, reports a sanitized recovery status, and continues to the interactive login choice
