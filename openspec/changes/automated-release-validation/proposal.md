# Automated release validation

Implement one commit-bound release pipeline on main, separate from product
candidate branches. Reuse declared fixture tests; require native Arch/WSL and
live identity/provider evidence for full release validation. Missing prerequisites
must produce blocked evidence, never success. Fixtures are not live acceptance.

Two GitHub QA user accounts exercise independent login/reuse. They contain no
production organization access. Fixture tests do not use GitHub identities.
MFA and provider eligibility are not bypassed to make automation unattended.

Deliverables: version-aware test manifest, runner/evidence CLI, reusable suite
workflow, orchestrator, publication guard, native runner/adapter contracts,
provisioning guide and negative gate tests. Dedicated VMs, QA accounts, protected
configuration and workflow-write credentials are deployment prerequisites.
