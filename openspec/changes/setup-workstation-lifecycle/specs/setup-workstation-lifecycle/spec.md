# Workstation lifecycle

## ADDED Requirements

### Requirement: Service selection pattern
Workstation SHALL keep the Requirements readiness heading, replace its duplicate service row with a blank row, and put all service information in Containers. Rows SHALL have left selection boxes and right installation/runtime status, including Installed · Up for running services. Space SHALL queue/unqueue install/start, D SHALL queue/unqueue uninstall, and Enter SHALL open Review. Loading or unverifiable rows SHALL not queue actions. V and G retain explicit account/profile shortcuts.

#### Scenario: Queue without effects
- **WHEN** Docker is Installed · Up and D is pressed
- **THEN** Docker uninstall is selected without running commands, and Review lists it with a dependency warning

### Requirement: Service apply ordering
Review Apply SHALL install selected prerequisites before other work and remove selected services only after successful component work. Every removal SHALL be preflighted before any service mutation. Service-only removal plans SHALL work when prerequisites are Down; missing required prerequisites SHALL permit Apply only when selected for install. Selection-only mode SHALL write a private plan and apply nothing. Service-only plans SHALL skip unrelated setup.

#### Scenario: Preserve running work
- **WHEN** a component step fails before queued Docker removal
- **THEN** Docker removal is not attempted

### Requirement: Guarded removal
Managed container removal SHALL validate role, uid and HOME labels and preserve images, volumes and credentials. Supported native Linux Engine removal SHALL preserve its data/config and avoid purge/autoremove. Unsupported Docker Desktop or in-distro WSL removal SHALL refuse before mutation and provide manual host instructions; it SHALL never unregister a distro, shut down/restart WSL, or claim removal completed.

#### Scenario: Foreign container
- **WHEN** a named Tools container belongs to another installation
- **THEN** stop/remove is refused and that container is untouched

### Requirement: Additive private plan
The schemaVersion-1 selection SHALL add wsl/docker/setup_tools/vault keys with install/uninstall actions only. Native writing SHALL atomically create mode-0600 JSON without following a caller's symlink. The root prerequisite reader SHALL reject malformed, duplicate, unknown or non-private generated plans before service mutation.

#### Scenario: Missing Docker
- **WHEN** Docker and Tools are missing and both are selected for install
- **THEN** the preview can save the plan without Python or Docker, and applying it installs prerequisites before component validation/work

Component plans retain required readiness. When prerequisites are missing, apply a service-only install plan first; then reopen setup for components. Mixed plans receive full Python/catalog validation before any selected service change.
