## ADDED Requirements

### Requirement: Versioned personal and company sources
v1.6.2 SHALL associate file and GitHub repository manifest sources with the
selected personal or company scope and retain a stable source/connection record.
File sources SHALL include local JSON and supported hosted file links. Imports
SHALL validate and review metadata before merging local launcher manifests.

#### Scenario: Import another company's manifest
- **WHEN** the user imports an authorized source for a selected company
- **THEN** the imported profiles retain that company's association
- **AND** existing personal and other-company profiles and credentials are preserved

### Requirement: Browser-only remote authorization and remembered connections
Private remote source authentication SHALL use the system browser and the source
provider's supported OAuth permissions. Supported renewal material SHALL remain
in protected provider storage, separate from manifests and exported metadata.
Selecting a company or signing into Keycloak SHALL NOT by itself grant access
to GitHub, Microsoft/Google files or AI credentials.

#### Scenario: Return to a saved private source
- **WHEN** the user returns after restarting the workstation
- **THEN** import uses the saved locator and explicitly linked provider connection
- **AND** valid access is reused or renewed where permitted
- **AND** denied/revoked access requires browser sign-in without losing local profiles

### Requirement: Local and public file access
Local files SHALL use existing filesystem permissions without an artificial web
login. Public HTTPS files SHALL not require a provider login. Unsupported private
URLs SHALL report the missing connector rather than request a pasted secret.

#### Scenario: Import a local manifest
- **WHEN** the user selects a readable local JSON manifest
- **THEN** validation and review occur on this workstation without a remote service

### Requirement: Explicit source account and preserved imports
Source reads SHALL use the selected verified connection rather than silently
substitute an ambient account. Failure, cancellation, malformed input and naming
conflicts SHALL preserve prior local manifests, credentials and unrelated scopes.

#### Scenario: Two linked GitHub accounts have different repository permissions
- **WHEN** the selected source account lacks access to the requested repository
- **THEN** setup reports the access problem without trying another account silently
- **AND** the last successful local configuration is retained

### Requirement: Workstation networking deferred to v1.8
v1.6.2 workstation import SHALL be local only. Remote-workstation discovery or
import through internet/Tailscale services SHALL be deferred to a workBenches
service integration targeted for v1.8.

#### Scenario: Select a remote workstation source in v1.6.2
- **WHEN** source setup presents supported import methods
- **THEN** it exposes file/repository sources and local workstation access
- **AND** it does not advertise an implemented peer-workstation service
