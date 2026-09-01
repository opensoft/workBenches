## ADDED Requirements

### Requirement: Native model availability is authoritative
The system SHALL enable the ZCode GLM-5.3 Max route only when the authenticated ZCode runtime advertises GLM-5.3, accepts the `max` reasoning variant, and completes a live prompt with that exact pair.

#### Scenario: GLM-5.3 with Max effort is available
- **WHEN** ZCode's authenticated catalog includes GLM-5.3, native selection reports thought level `max`, and a live prompt succeeds
- **THEN** the route is eligible for an end-to-end OmniRoute and OpenCode completion test

#### Scenario: Model or effort is unavailable
- **WHEN** ZCode omits GLM-5.3, rejects `variant: max`, or cannot complete a prompt with that pair
- **THEN** the system SHALL leave the OpenCode catalog and agent roster unchanged

### Requirement: Credentials remain owned by ZCode
The system SHALL use ZCode's protected user profile for Coding Plan authentication and SHALL NOT copy the credential into OmniRoute configuration.

#### Scenario: Successful Z.ai login
- **WHEN** the user completes the official ZCode OAuth flow
- **THEN** ZCode stores its own configuration and credential files with user-only permissions

### Requirement: Route identity is not inferred
The system SHALL distinguish the ZCode Coding Plan route from the separate Z.ai API-key route and SHALL report the model ID resolved by the consuming runtime.

#### Scenario: API route works while the ZCode bridge is unavailable
- **WHEN** `zai/glm-5.3` succeeds through the API-key provider but OmniRoute cannot establish its ZCode app-server session
- **THEN** the system SHALL report the API route separately and SHALL NOT claim the ZCode Max-effort route works in OpenCode
