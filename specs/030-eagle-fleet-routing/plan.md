# Plan

1. Inventory repositories, active workflow sources, selectors, instructions and compatibility. Retain exact source blob/head metadata in a host-local manifest.
2. Prove a general rootless nested worker can use sudo, public package downloads, Docker actions, service-container ports and private workspace mounts without host exposure.
3. Implement bounded fleet scheduling and per-organization selected-repository groups. Preserve the existing midNet service until replacement is verified.
4. Prepare workflow routing patches and preserve platform matrix semantics. Handle swap/sysctl setup with namespace-compatible capability checks; do not drop tests.
5. Open and review routing PRs per repository, activate under policy and verify representative normal jobs across tool stacks. Do not dispatch production releases for acceptance.
6. Report completed routes and exact remaining platform/access/review blockers, with rollback data.

This is an existing single repository. No shape conversion is part of this change. Repository feature commands run inside the existing dotnet-bench; host API/controller operations use Windows PowerShell and the host credential context.