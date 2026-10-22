# Proposal

## Why

GitHub-hosted jobs are blocked by the billing cap across repositories. The midNet-only pilot does not meet the requirement: route all eligible GitHub-hosted jobs to Eagle while keeping platform coverage and deployment controls.

## What Changes

- Inventory all accessible organizations and personal repositories, active workflow files, runner selectors and requirements.
- Add fleet provisioning, explicit Eagle-only selectors and selected-repository organization groups. Existing specialized self-hosted queues stay specialized.
- Support disposable rootless Linux job environments with tool setup, sudo inside user namespaces, Docker actions and service containers, without exposing Eagle's host daemon or files.
- Queue compatible jobs on Eagle with bounded concurrency and resources. Preserve approval, permissions, tests and release triggers.
- Record Windows, macOS, ARM and hardware-dependent requirements explicitly. Never relabel unsupported platforms as Linux or remove their assertions.
- Prepare repository-specific routing PRs and verify actual normal jobs before activation claims.

## Capabilities

### New Capabilities

- `eagle-fleet-execution`: Fleet-wide compatible self-hosted routing, isolated execution, capacity and migration evidence.

### Modified Capabilities

None.

## Impact

Shared runtime/tooling in workBenches, the host-local Eagle controller, selected GitHub organization runner groups, workflow files across affected repositories and the implementation feature under specs/030-eagle-fleet-routing. Existing bench work and Docker/WSL uptime must be preserved.