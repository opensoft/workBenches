# Unattended QA token renewal and live GitHub membership

Move the verified QA session lifecycle into a main-only scheduled workflow using
Azure OIDC workload identity. Restrict data-plane access to the two named test
session secrets; serialize refresh writers and never emit credential values.
Prove live immutable identity, actual refresh/writeback and exact organization
team allow/deny decisions. Unit tests cover rotation intent, failure/nonreplay,
identity/scope validation and pagination/isolation.

This is one required component of the full automated test system. It does not
replace the github-live UI adapter or certify company/provider/native acceptance.
No readiness bypass or fabricated release attestation is added.
