# Spec Delta

## Purpose

Ensure every supported bench startup and distributed bench template reaps terminated orphan helpers consistently while preserving explicit control of live container replacement.

## ADDED Requirements

### Requirement: Canonical bench startup reaping

Canonical startup definitions for every supported bench, bench-based worker, distributed project template, tracked workspace example and bench test service SHALL enable runtime orphan reaping independently of the Wave-generated override.

#### Scenario: Non-Wave startup
- **WHEN** a user creates a bench through its declared Dev Containers or direct Compose configuration
- **THEN** the resulting bench service enables runtime orphan reaping

#### Scenario: Generated projects and optional workers
- **WHEN** a tracked bench template or optional bench-based worker is resolved
- **THEN** runtime orphan reaping is enabled for its bench-consuming services

### Requirement: Configuration validation preserves live work

Validation MUST reject absent or disabled reaping settings without starting services, replacing live containers or printing resolved credential values.

#### Scenario: Missing setting
- **WHEN** a bench startup definition omits or disables runtime reaping
- **THEN** automated configuration validation fails and identifies the affected file and service

#### Scenario: Existing containers
- **WHEN** source changes and configuration validation complete
- **THEN** existing live containers retain their identities and start times until a separately authorized replacement
