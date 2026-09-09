## Purpose

Provide each personalized bench image with a Codex installation that its
runtime user can update without modifying the shared image baseline.

## ADDED Requirements

### Requirement: Layer 3 provides a user-owned Codex installation
The Layer 3 image SHALL install Codex into an npm prefix owned by its runtime
user and SHALL resolve `codex` from that prefix before any system-wide copy.

#### Scenario: Runtime user resolves the writable Codex copy
- **WHEN** a user starts a shell in a Layer 3 bench image
- **THEN** `command -v codex` resolves under that user's npm global prefix

### Requirement: The shared Codex baseline remains root-owned
The Layer 3 image SHALL NOT change ownership or permissions of the Codex
installation inherited from the shared base image.

#### Scenario: Updating Codex does not require writes to the shared prefix
- **WHEN** the runtime user updates the resolved Codex installation
- **THEN** npm writes only within the user's global npm prefix
