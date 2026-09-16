## 1. Governance and Handoff

- [x] 1.1 Ratify the ownership, canonical-store, migration, and restore decisions in this change.
- [x] 1.2 Hand implementation to Speckit feature `008-ai-credential-custody` without duplicating its executable task list here.

## 2. Cross-Repository Acceptance

- [x] 2.1 Verify Opensoft-Tenant represents all company-owned profiles and the non-secret Azure Key Vault contract.
- [x] 2.2 Verify AI-Credentials preserves Brett-owned custody and reports incomplete personal escrow without moving secrets into company custody.
- [x] 2.3 Verify workBenches implements and tests preserve-by-default, exact-version, atomic, secret-safe restore.
- [x] 2.4 Record any live credential or vault operation that remains intentionally unexecuted after code and metadata validation.
- [x] 2.5 Verify the Opensoft registry and Key Vault contain a standalone OmniRoute/OpenCode credential mapping without unrelated provider credentials.
- [x] 2.6 Verify workstation setup attempts guarded OmniRoute recovery before interactive OpenCode login and preserves the fallback on unavailable authority.
