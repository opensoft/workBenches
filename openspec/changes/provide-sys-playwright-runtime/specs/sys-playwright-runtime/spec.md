## ADDED Requirements

### Requirement: Sys images provide a shared Chromium runtime
The shared sys-bench image SHALL install a pinned Playwright Chromium browser
in an image-owned location available to every derived sys bench.

#### Scenario: Derived sys bench launches Chromium
- **WHEN** a derived sys-bench image starts a headless Chromium process
- **THEN** the browser executable resolves from the inherited shared cache without a per-user browser download

### Requirement: Chromium dependencies are complete at build time
The sys-bench image build SHALL install Chromium's supported Linux runtime
dependencies and SHALL fail when any browser shared library is unresolved.

#### Scenario: Browser dependency is missing
- **WHEN** the installed Chromium executable reports an unresolved shared library
- **THEN** the sys-bench base image build exits unsuccessfully before publishing the image

#### Scenario: Dependency closure is complete
- **WHEN** all supported runtime packages are installed
- **THEN** the Chromium executable reports zero unresolved shared libraries

### Requirement: Browser provisioning does not activate running benches
Building the shared or derived sys images SHALL NOT be represented as updating
an already-running sys bench.

#### Scenario: New image is built while a bench runs
- **WHEN** a refreshed sys image succeeds while an existing bench container is running
- **THEN** the running container remains untouched until separately authorized recreation
