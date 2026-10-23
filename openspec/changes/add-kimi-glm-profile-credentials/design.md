# Design decisions

1. Reuse the existing identity tree, provider manifests, native login boundary,
   credential stores and company broker. Do not create a second vault or identity
   database. Provider-specific behavior belongs in adapters.
2. Use `kimi-code` for the normalized credential/provider ID, matching the account
   inventory documentation; `kimi_code` remains the existing Harness catalog ID.
   `kimi-code-profiles.json`, `KIMI_CODE_PROFILES_HOME` and `pkimi` are the new
   public profile interfaces. Preserve `glm`, `pglm`, `pzai` and existing GLM paths.
3. Store each Kimi runtime under a persistent profile home and set
   `KIMI_CODE_HOME` only for its child process. Existing default `~/.kimi-code`
   is never silently imported, reset, or copied to another account. Explicit
   import must review the destination and reject collisions or unsafe paths.
4. Credential export is a minimal, versioned provider projection, not a home
   archive. GLM export includes only the selected Z.AI auth record; Kimi export
   includes only the selected supported credential mode. Config keys unrelated
   to authentication, other providers, sessions, plugins, logs, MCP secrets and
   project files are excluded. Import merges safely and preserves unrelated data.
5. Recovery and company publication are separate opt-ins. Personal OAuth can
   work locally without becoming eligible for company sharing. A provider-mode
   table records validation, recovery, sharing and refresh eligibility. The
   conservative default is unsupported for any unqualified remote operation.
6. Reuse company profile grants, exact identity binding, version comparison,
   durable idempotency, launch synchronization and writer coordination. A local
   logout is not a request to delete a broker credential. Never replay a possibly
   consumed rotating refresh token after an ambiguous operation.
7. Kimi CLI 2.3.1 is the initial compatibility target observed on 2026-10-23,
   not a verified minimum or a permanent version pin. Capture the actual tested
   client/package identity. Offer `k3.1-pro` when entitled; preserve existing
   model choices, keep thinking enabled and start a new session on model change.
8. UI status separates facts. A file or `auth list` result is local presence,
   not verified access or account ownership. Verification uses documented safe
   provider mechanisms; unsupported identity checks remain explicitly unverified.
   No paid inference or browser flow runs just from rendering or background inventory.

Detailed interfaces, migration rules and evidence gates live in the linked
Speckit contract and plan. This proposal does not qualify shared Kimi OAuth,
provision a broker/vault or grant company members new permissions.
