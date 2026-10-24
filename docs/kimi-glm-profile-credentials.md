# Kimi and GLM profiles — planned for 1.7

**Status: approved specification, not implemented.** Brett approved all Codex/
Astra review changes on 2026-10-24. See [feature 031](../specs/031-kimi-glm-profile-credentials/spec.md),
[approved review](../specs/031-kimi-glm-profile-credentials/review-2026-10-24.md)
and its sole [runtime task list](../specs/031-kimi-glm-profile-credentials/tasks.md).

## Current behavior

GLM has `pglm`/`pzai` and profile-local OpenCode XDG roots, but currently always
instructs Coding Plan and dispatches generic OpenCode auth commands. The planned
revision preserves aliases/paths while targeting or verifying the actual selected
standard/Coding Plan member. Dashboard guidance is not live key verification.

Kimi can be manually isolated with `KIMI_CODE_HOME` and its native `/login`.
Its composed profiles, launcher, standard persistent mounts and Kimi/GLM recovery/
company adapters are not supplied by these documentation changes.

## Approved delivery order

1. **Local profiles/login/persistence (M1):** named isolated homes, correct client
   and routing, native interactive sign-in from the wizard/dashboard, honest
   status, migration boundaries and retained homes after bench recreation/reboot.
2. **Qualified personal credential retrieval (M2):** restore only the selected
   credential from an existing store without losing other config/provider keys.
3. **Qualified company synchronization (M3):** independently authorized owned
   profile/broker binding, separate use/publish/maintain grants and safe versioned
   synchronization. Company membership alone does not grant a provider account.

The initial required retrieval tests are Kimi Platform API-key and GLM Coding
Plan API-key recovery through existing Azure Key Vault on each claimed native
Linux/WSL runtime. Other stores/modes need their own qualification. These are
acceptance targets, not current support claims. If required recovery cannot be
qualified, label the release local-only and explicitly defer retrieval; an empty
enabled-mode list cannot satisfy the retrieval milestone.

## Planned account workflow

Select an identity → AI accounts → Kimi Code or GLM → named profile. Login opens
a native interactive terminal under that selected profile and returns to the
wizard/dashboard after completion or cancellation. Entered keys/transcripts are
not diagnostic logs. Company/GitHub sign-in does not authenticate the provider.

```bash
pkimi list
pkimi login team01
pkimi status team01
pkimi team01
```

Kimi homes use `$HOME/.kimi-code-profiles/profiles/<profilePath>`; GLM paths stay.
Validate the effective account/provider/endpoint, not just its directory. Reject
conflicting model/header/API/config overrides. Keep workBenches company settings
outside vendor child XDG changes so launch synchronization still finds them.

Feature 032 installs the CLI; 031 validates the actual executable/package/version
for credential operations. Managed updates remain workBenches-owned and runtime
changes need requalification. Legacy configuration/history migration does not
copy OAuth logins. Importing defaults is reviewed and does not duplicate one
credential into every identity.

## Credential recovery and status

Export a minimal versioned projection, never the full Kimi home/TOML or mixed
OpenCode auth file. Restore merges the selected member, preserves unrelated
fields, detects selected-record races and coordinates native writers or waits
for a safe quiescent window. Occupied destinations are preserved unless a
reviewed backed-up replacement is requested. Offline stores retain local data.

Company enrollment derives the selected target from validated owned metadata,
not an arbitrary path. Personal/default roots remain outside company publication, including their custom
locations. Validated company profiles may use a configured custom profile root. Authentication mode and synchronization policy are separate facts.
Keep unqualified Kimi OAuth recovery/sharing/CPC refresh disabled; API-key
rotation is not OAuth refresh. Personal recovery does not qualify company sharing.

Status separates presence, fingerprint/account/endpoint/client-bound verified
access, model entitlement and sync freshness. Changing a key/endpoint invalidates
old verification. Default credentials cannot authenticate empty named profiles.
No secrets are displayed or paid generation used as a status probe.

Kimi Code 2.3.1 remains the initial compatibility target. For entitled K3.1 Pro,
explicitly configure and verify thinking/max: the observed vendor default is
high. Validate endpoint IDs/local aliases and report fallback/substitution.
Preserve existing model choices and start a new session for model changes.

Persistent homes survive bench restart/recreation and host reboot; persistence
does not keep killed processes running or make revoked logins valid. Uninstall
preserves homes by default. See [acceptance](../specs/031-kimi-glm-profile-credentials/quickstart.md)
for the real native/WSL, store, sync and runtime-image evidence required.
