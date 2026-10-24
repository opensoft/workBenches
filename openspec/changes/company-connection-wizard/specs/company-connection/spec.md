## ADDED Requirements

### Requirement: Guided first company connection
An unconfigured company sign-in SHALL offer enrollment import first,
administrator registration guidance, existing application settings and Back.
Configured sign-in SHALL retain its current direct device-flow behavior.

#### Scenario: Employee already has company setup
- **WHEN** the employee chooses an administrator enrollment file/link
- **THEN** the wizard reviews its issuer/application identity before saving
- **AND** no administrator registration is required for that employee

### Requirement: Accurate registration guidance
The wizard SHALL distinguish Client ID from personal/company IDs and explain
once-per-organization registration. Guidance SHALL state the supported public
client/device-flow settings, issuer format, scopes and no embedded client secret.
Browser/clipboard actions SHALL be native and explicit with a visible fallback.

#### Scenario: Administrator needs a registration
- **WHEN** the administrator opens the Keycloak registration guide
- **THEN** it supplies the required settings and a same-provider admin link
- **AND** the wizard neither creates a client nor asks for administrator secrets

### Requirement: Reviewed validation and safe enrollment
Discovery SHALL validate issuer equality and same-origin HTTPS required endpoints
without starting authorization. Settings SHALL be saved only after confirmation.
Exports SHALL contain only non-secret allowlisted fields, use private atomic
storage and refuse unsafe/occupied destinations. Import SHALL refuse redirects,
oversize input, malformed settings and secret-bearing/unrecognized fields.

#### Scenario: Discovery succeeds before sign-in
- **WHEN** the issuer advertises valid device/token/userinfo endpoints
- **THEN** the wizard reports discovery checked and client registration still unverified
- **AND** only the existing device flow can establish successful sign-in

### Requirement: Preserved isolation and cancellation
Back, cancel and failure SHALL preserve existing companies, personal identity,
sessions, queued installs and configuration. Company sign-in SHALL remain
separate from broker/vault grants and AI-provider credentials.

#### Scenario: Cancel setup for another company
- **WHEN** a user cancels configuration before confirmation
- **THEN** no new settings/session is written and another company's files remain unchanged
