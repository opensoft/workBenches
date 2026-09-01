## ADDED Requirements

### Requirement: Runtime-specific SonarQube MCP routing
The system SHALL allow a bench runtime to supply a SonarQube MCP URL that
overrides only the SonarQube server URL when Codex is launched through the
profile launcher. When no runtime value is supplied, the launcher SHALL preserve
the selected profile's configuration without adding this override.

#### Scenario: Bench runtime supplies a private service URL
- **WHEN** Codex is launched through `codex-profile` with a non-empty runtime SonarQube MCP URL
- **THEN** the launched Codex process receives exactly one configuration override for the SonarQube MCP server URL and retains its normal profile and authentication configuration

#### Scenario: Host runtime supplies no override
- **WHEN** Codex is launched through `codex-profile` without a runtime SonarQube MCP URL
- **THEN** the launched Codex process receives no SonarQube MCP URL override and continues to use the selected profile value

### Requirement: Private proxy reachability
The py-bench service SHALL retain its current default network and SHALL also join
the existing private shared-service network so that the SonarQube MCP proxy is
reachable by service name.

#### Scenario: Protocol initialization from py-bench
- **WHEN** py-bench sends a valid MCP `initialize` request to the proxy service name on the private shared network
- **THEN** the proxy responds successfully through the MCP protocol without publishing the token-injecting listener on all host interfaces

### Requirement: Host profile isolation
The runtime-specific configuration SHALL NOT mutate the bind-mounted shared host
profile, expose SonarQube tokens, or alter unrelated MCP server settings.

#### Scenario: Host and container use distinct routes
- **WHEN** the py-bench runtime override is active
- **THEN** Codex launched inside py-bench resolves SonarQube MCP to the private service URL while the shared host profile still contains its loopback URL

### Requirement: Restart and recreation durability
The py-bench SonarQube MCP route SHALL remain effective after both a container
restart and a source-driven container recreation.

#### Scenario: Container is restarted
- **WHEN** the configured py-bench container is stopped and started without recreation
- **THEN** private proxy DNS, MCP initialization, and launcher resolution continue to succeed

#### Scenario: Container is recreated
- **WHEN** py-bench is recreated from repository source using supported tooling
- **THEN** it rejoins both required networks, receives the runtime URL, and launches Codex with the private SonarQube MCP route
