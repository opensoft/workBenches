## ADDED Requirements

### Requirement: Bounded Tools Rclone connector
Tools SHALL contain a version/digest-pinned Rclone with native browser callbacks.
Personal/company file import SHALL support local provider manifests and browsing
connected OneDrive/Google Drive folders, saved per-scope sources and repeat pulls.
OAuth configuration SHALL remain private and persistent on the local workstation.
Browser callback publication SHALL be host-loopback-only and temporary. Import
SHALL preview resulting names and preserve existing matching profiles/credentials.

#### Scenario: Denied cloud browser consent
- **WHEN** the user declines the provider's authorization request
- **THEN** the temporary login container and callback listener are removed
- **AND** previous connections, manifests and credentials remain unchanged

#### Scenario: Pull a selected provider manifest again
- **WHEN** the user selects a saved cloud-file source under a personal/company scope
- **THEN** Tools reads the file using that scope's private Rclone connection
- **AND** review precedes merging new metadata and creating isolated local launchers
- **AND** import neither uploads files nor authenticates an AI-provider account

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


### Requirement: Company source pane and native local-file selection
The company Profiles view SHALL expose a source pane with the current source,
connection, last successful import and profile counts. It SHALL offer local-file,
file-URL, GitHub-repository and saved-source refresh actions with visible keyboard
navigation and a narrow-terminal layout.

Local-file selection SHALL offer an explicit native open-file dialog when the
local desktop supports it and a manual-path option when it does not. Container
execution SHALL route selection to the local host through a bounded host action.
Selection SHALL NOT import automatically. Validation and a company-scoped review
SHALL precede confirmed metadata application; credentials remain separate.

#### Scenario: Select a manifest in the local desktop dialog
- **WHEN** the engineer chooses a local file for the selected company
- **THEN** the native dialog returns a host file for bounded validation and review
- **AND** the source is saved only after a confirmed successful import

#### Scenario: Native dialog is cancelled or unavailable
- **WHEN** the engineer cancels the dialog or native integration is unavailable
- **THEN** cancellation preserves saved state and unavailable integration offers manual path entry
- **AND** terminal keyboard mode and navigation are restored

#### Scenario: Enter a private hosted-file URL
- **WHEN** the engineer enters a supported private HTTPS source
- **THEN** the pane uses an explicitly selected provider browser connection
- **AND** authorization and validation results appear before import confirmation
