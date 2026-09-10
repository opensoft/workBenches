# Distribution plan

Use a Python installer for portable checksum validation, GitHub API/raw fetching,
and atomic replacement. Resolve the workBenches checkout at runtime; store its
path only in the existing host-local .workbenches-path convention. Keep the
executable standalone; PyYAML is required for YAML estate inspection and provided
by dev-bench-base. Fixture tests cover install, forwarding, drift and refusals.
