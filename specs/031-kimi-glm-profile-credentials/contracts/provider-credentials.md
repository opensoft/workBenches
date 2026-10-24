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

## Approved review: interactive native login

Wizard/dashboard actions need a native terminal/PTY handoff, not file-based Tools
RPC or a detached process with closed stdin. Pass a validated selected-profile
reference and resolve its environment at the native boundary. Support live input,
cancel/back, bounded process cleanup, completion detection and return to saved
UI/queue state. Do not capture secret input or terminal transcripts in logs/RPC
arguments. The existing callback remains suitable for bounded noninteractive
operations. Direct-terminal and wizard/dashboard login have separate acceptance.

## Typed binding and policy

The versioned mapping distinguishes these fields:

| Field | Meaning |
| --- | --- |
| `provider` | Normalized `kimi-code` or `glm` |
| `authMode` | One of the four explicit authentication modes above |
| `syncPolicy` | Existing `portable` or `broker-refresh` policy; never an authentication-mode name |
| `projectionSchemaVersion` | Selected-secret envelope/adapter version |
| `localProfileId` / `brokerProfileId` | Immutable owned local profile and server-authorized binding |
| `nativeProviderId` / `endpoint` | Qualified exact native member, protocol and endpoint binding |

Enrollment selects a profile from validated identity metadata and derives the
target/member; an arbitrary path is not ownership evidence. Bind the provider
account using the mode's qualified evidence. Missing independent binding evidence
blocks company publication. Exclude personal/default homes, including their configured custom
locations, from publication; allow validated company profiles in custom roots. New readers preserve older records. Legacy broker
`mode` remains synchronization policy for existing records and migrates
explicitly to the versioned representation; never reuse it for authentication
mode strings. Unsupported/incompatible readers refuse mutation without dropping
records.

## Effective routing and control-plane paths

Validate the actual executable/package/version and effective provider, account,
mode, endpoint, credential source and model before execution. Kimi overrides
include `KIMI_MODEL_*`, provider `api_key_env` references, custom Authorization
headers and OAuth/API endpoint overrides. Ordinary shell `KIMI_API_KEY` alone
does not provide Kimi Code authentication. OpenCode project, custom and inline
configuration can override profile-global settings. Reject conflicting routing
or require a separately reviewed binding; do not send the selected credential
to another endpoint or log override values. GLM login/status/logout targets or
verifies the requested standard/Coding Plan member, including when both exist.

Resolve workBenches config, company identity and lease roots before applying
profile XDG roots to the vendor child only. Before-launch and after-login sync
must use the same original configuration and lease. Vendor runtime
`XDG_CONFIG_HOME` must not redefine the workBenches control plane.

## Projection-aware adapter interface

Adapters implement `inspect`, `extract`, `validate`, `fingerprint` and
`merge/install` for a qualified client identity/version, provider and auth mode.

- `inspect` identifies the native selected location/member/layout.
- `extract` returns only the bounded selected-secret projection.
- `validate` checks format, binding, endpoint and operation eligibility before
  mutation.
- `fingerprint` covers only the projection and drives dirty detection,
  publication versions and verification invalidation. A separate backing-file
  revision detects native file changes; unrelated provider edits do not become
  GLM publications.
- `merge/install` rereads the destination, preserves unrelated TOML/JSON fields,
  rejects a changed selected credential and installs atomically under qualified
  writer coordination. Preserve unrelated edits made during a download.

A workBenches advisory lease does not control an unmodified native writer.
Without a qualified coordination protocol, defer restore to a quiescent window
or report conflict. Persist pending-operation and install/baseline state so a
crash after merge but before baseline persistence reconciles safely. Selected
member logout/partial writes do not publish deletion or silently sign a user in.

The real sync client must call these operations rather than parse, hash, publish
and replace the entire native file. Recovery and broker images must package and
import any shared adapter module; isolated unit success is insufficient.

## Installer, update and migration compatibility

Feature 032 owns managed installation; feature 031 consumes verified executable/
package identity and checks actual runtime version/layout on each workstation or
bench. Kimi Code and Python Kimi remain distinct even when an external `kimi`
shadows a managed launcher. Explicit executable overrides receive the same
validation; a stale receipt or version string alone is not qualification.

Managed installations use workBenches-owned explicit updates: prevent Kimi's
default automatic installation from modifying or bypassing that managed payload.
Do not silently rewrite external-install update policy. Runtime/layout/PATH
drift invalidates affected adapter eligibility and verification until
requalification; preserve local credentials and supported local-login guidance.
Test upgrades, rollbacks and uninstall revealing another executable.

Vendor legacy migration can import config/history but does not migrate OAuth
tokens. A selected OAuth mode therefore remains login-required; imported API-key
modes receive normal selected-mode presence/verification assessment. Reject legacy-name collisions that
would copy one identity's credential into another identity's home.

## Bound verification and model observations

Bind verification to the projection fingerprint, effective endpoint, account and
client identity/version. Rotation or routing changes invalidate the observation;
default login cannot satisfy a different empty named profile.

K3.1 Pro's observed default effort is `high`; explicitly set and verify the
requested `max`. Resolve local aliases against selected-endpoint model IDs and
report observed substitution, including typo-driven fallback. Model entitlement
and native version remain independent facts. Paid generation is not a status
probe.
