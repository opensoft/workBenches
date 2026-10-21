## Why
Agents need a discoverable, attributed connection tool that cannot borrow a human identity or bypass tenant target policy.
## What Changes
- Install the tenant-owned, hash-pinned bench-access client in the shared base image.
- Advertise a disabled-by-default capability and provide an agent discovery skill.
- Preserve active containers and existing GitHub SSH configuration.
## Capabilities
### New Capabilities
- `system-access-client`: explicit-environment, wallet-backed tenant connection discovery.
### Modified Capabilities
None.
## Impact
Shared base image, packaged client, AGENTS pointer and one skill. Source owner: opensoft/Opensoft-Tenant, infra/smallstep. Approved by Brett Heap on 2026-10-15 with no agent grants. Implementation checklist is handed off to the feature folder; installation is not enrollment.
