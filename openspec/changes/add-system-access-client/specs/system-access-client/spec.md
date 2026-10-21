## ADDED Requirements
### Requirement: Explicit identity and environment
The client SHALL require an explicit QA/prod environment and SHALL refuse disabled or missing enrollment without falling back to human credentials.
#### Scenario: Unenrolled agent
- **WHEN** an agent invokes login without an activated environment
- **THEN** the command exits with an enrollment refusal and creates no token.
### Requirement: Pinned shared distribution
The image SHALL install a source-attributed client wheel and hash-locked dependencies into an isolated runtime without credentials or grants.
#### Scenario: Altered artifact
- **WHEN** an artifact differs from the recorded hash
- **THEN** installation fails.
### Requirement: Discoverable system access
Agent instructions SHALL point to the capability and skill and SHALL distinguish authorization, certificate issuance and actual system login.
#### Scenario: Discovery before connection
- **WHEN** an agent needs a tenant-managed connection
- **THEN** it uses the explicit environment inventory and retains strict host verification.
