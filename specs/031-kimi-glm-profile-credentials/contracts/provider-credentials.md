# Provider profile and credential contract

Status: planned additive 1.7 contract; no runtime support is claimed by this file.

## Names and launcher interface

| Concept | Kimi | GLM |
| --- | --- | --- |
| Normalized provider | `kimi-code` | `glm` (input aliases `zai`, `z.ai`) |
| Existing Harness row | `kimi_code` | Existing applicable harness/provider rows unchanged |
| Account manifest | `kimi-code-profiles.json` | `glm-profiles.json` unchanged |
| Profile base | `$KIMI_CODE_PROFILES_HOME`, default `$HOME/.kimi-code-profiles` | `$GLM_PROFILES_HOME`, default `$HOME/.glm-profiles` |
| Runtime home | `<base>/profiles/<profilePath>` | Existing `<base>/profiles/<profilePath>` |
| Launcher | `pkimi` (`kimi-profile` executable alias) | `pglm`, `pzai`, `glm-profile`, `zai-profile` retained |
| Child environment | `KIMI_CODE_HOME=<runtime home>` | Existing profile-local XDG config/data/cache/state |

Each launcher supports `list`, `path PROFILE`, `login PROFILE`, `status PROFILE`,
`logout PROFILE`, `run PROFILE [arguments]`, and shorthand `PROFILE [arguments]`.
Kimi login opens the CLI in that home and directs the user to `/login`; logout
uses its supported native operation, not deletion of the entire directory.
No vendor command or arbitrary metadata is evaluated as shell text.

Manifests retain names, email, family, aliases and safe relative profilePath;
Kimi gains an additive provider file. Optional credential binding records the
auth mode and secret reference, not a key/token. Existing GLM paths stay valid.
Provider/mode additions must be validated consistently across composer, normalizer,
dashboard, recovery, client and broker; old data round-trips without dropping
unrecognized entries, and incompatible readers refuse mutation explicitly.

## Authentication modes and projection

Use explicit modes: `kimi-oauth`, `kimi-api-key`, `glm-coding-plan-api-key`,
`glm-api-key`. A mode record includes the provider, supported client versions,
verification method, projection schema, permitted remote operations and expiry/
refresh behavior. Absent support is false/unsupported, not inferred from a token field.

A secret envelope has schema version, provider, auth mode, exact profile/account
binding and the adapter's minimal credential projection. Authority and grants are
resolved by the broker, not taken from client-supplied labels. The matching local
non-secret record stores version/hash, observation times and pending operation ID.

- Kimi API-key projection contains only the selected provider key and the minimum
  approved endpoint/provider binding needed to reconstruct it. Do not export an
  entire config.toml containing other providers or executable settings.
- Kimi OAuth projection is restricted to the selected native credential record's
  documented token/expiry/account fields. Freeze an explicit field allowlist from
  qualified client behavior before enabling recovery or sharing. Unknown layouts
  are unsupported; never archive all of `credentials/` or the full home.
- GLM projection contains only the selected Z.AI or Z.AI Coding Plan auth member,
  with its explicit plan/endpoint binding. Import merges only that member into
  the selected profile's OpenCode auth store. Other members and files are retained.
- Sessions, prompts, chat history, plugins, logs, SSH/GitHub/company tokens,
  third-party keys and project files never enter credential recovery payloads.
- Projection size is bounded at 64 KiB; unknown schema/mode/fields, malformed
  records, traversing/symlinked paths or a mismatching binding refuse before writes.

Files containing secrets are owned by the selected user with mode 0600, parent
directories 0700. Credentials are never command arguments or profile metadata.
Existing native Tools callback transport may use its private short-lived RPC
channel; requests and outputs are removed and excluded from diagnostics/artifacts.

## Persistence and migration

Bind the runtime profile bases from the host's managed home into benches at the
corresponding container user's home; resolve both paths at runtime. Persist Kimi
configuration, credential storage and session data locally. Vault/broker payloads
still contain only the credential projection, not a session/home backup.

No automatic import from default `~/.kimi-code`, legacy `~/.kimi`, another profile
or another company. Explicit import previews source/destination, checks ownership
and client format, backs up any approved replacement, and leaves the source intact.
Recreating/removing a container preserves host homes; deleting an account's data
is a separate explicit operation. Reboot storage persistence is not a guarantee
of resumed processes or perpetual provider authentication.

## Recovery, synchronization and status

Recovery mapping reuses the existing store enrollment and exact profile target.
Company mode reuses server-authorized profile IDs and use/publish/maintain grants.
Restore defaults to preserving a usable local record; explicit replacement backs
it up and atomically merges only the selected credential while coordinating native
writers. Reject another provider/mode/profile/tenant and unqualified remote modes.

Publication uses expected version and durable idempotency. Downloads preserve
unsent local changes; interrupted installs/publications reconcile on restart.
Missing files, partial writes and logout do not publish deletion. An unavailable
store leaves the prior local credential and reports freshness as unavailable.
Before managed launch, reconcile metadata under the existing lease protocol;
unmanaged profiles make no broker calls.

Expose separate profile/CLI readiness, local credential presence, last verified
access/account binding, requested model/entitlement, recovery eligibility,
company sync freshness/version, and actionable error. A local check does not
extend its verification timestamp. API-key rotation and native OAuth refresh are
different operations; CPC never refreshes an API key or an unqualified OAuth mode.
