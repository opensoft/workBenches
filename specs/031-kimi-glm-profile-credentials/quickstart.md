# Implementation and acceptance handoff

Status: planned 1.7 behavior; all runtime tasks remain unchecked. Brett approved
the Codex/Astra revisions on 2026-10-24; see [review](review-2026-10-24.md).

Locate the linked 031 worktree and explicitly select the feature:

```bash
export SPECIFY_FEATURE=031-kimi-glm-profile-credentials
export SPECIFY_FEATURE_DIRECTORY=specs/031-kimi-glm-profile-credentials
```

The inherited `.specify/feature.json` points at 018; do not rewrite it as a
documentation side effect. Read the governing proposal/spec/contract/tasks.
Integrate current 1.7/032 interfaces before dependent work. Run checks in declared
development/test containers, not against host credentials.

## Concrete acceptance matrix

T000 creates the capability/evidence matrix before dependent enablement. Each
case records exact executable/package/version and native layout, provider/
endpoint/region, authMode, syncPolicy, operation, store, claimed platform and
expected outcome (supported, unsupported or deferred). No wildcard cell can
qualify a different mode/store/platform; disabled outcomes get negative tests.

The [plan's minimum M2 rows](plan.md#minimum-17-retrieval-acceptance) are required
for the combined retrieval claim: Kimi Platform API key and GLM Coding Plan API
key through existing Azure Key Vault on each claimed native Linux/WSL runtime.
Other modes/stores need their own evidence. All recovery stores get synthetic
adapter tests even when an attended enablement row is deferred.

| Boundary | Required cases |
| --- | --- |
| Accounts | Personal/two companies; two identities in one company; duplicate names; rerun; owned-profile enrollment; immutable IDs; personal/default-root denial (including custom locations); permitted owned company profiles in custom roots |
| Routing | Selected native member and endpoint; Kimi KIMI_MODEL_* and api_key_env, custom Authorization and OAuth/API endpoints; OpenCode project/custom/inline precedence; both GLM members present |
| Login | Direct terminal versus real Tools/dashboard terminal/PTY; missing/unsupported CLI; browser/device approval; live key entry without logs; cancel/back/cleanup/completion; queue/focus return |
| Control plane | Real GLM before-launch/after-login sync uses original config and same lease despite child XDG changes |
| Client/installers | Current/legacy package identity; managed/external PATH shadowing; explicit binary; update/rollback/layout drift; auto-update ownership; uninstall fallback |
| Migration/persistence | Legacy OAuth not copied; duplicate legacy-name cross-identity rejection; actual Wave/devcontainer/Compose mounts; ownership; restart/recreate/reboot; uninstall retains homes |
| Projection | Native TOML/JSON; selected member only; unknown versions/schema/fields; bounded size; path/symlink checks; unrelated secrets excluded |
| Real sync | Unrelated provider edit during download; selected-record conflict/logout; backing revision versus projection hash; native writer coordination/quiescence; crash after merge/before baseline |
| Recovery | Every supported store adapter; locked/offline retry; fresh profile; occupied refusal; reviewed backup/replacement; cross-profile/provider/tenant denial |
| Company | Owned profile/broker binding; qualified identity evidence; separate grants; authMode versus syncPolicy; concurrent versions; no pending-operation replay loops; unsupported OAuth refresh denied |
| Packaging | Shared adapter imports inside both recovery and broker images; actual runtime invocation smoke |
| Observations/model | Empty named profiles versus default login; fingerprint/endpoint/account/client invalidation; safe verification; explicit max/thinking; endpoint IDs/alias resolution and substitution detection |
| Release | Expected repository/SHA/trusted workflow and required nonempty cases; unrelated green run rejected; M1/M2/M3 reported separately |

Canary secrets must not occur in logs, arguments, metadata, images or artifacts.
Run every focused and affected existing verify command in [tasks.md](tasks.md).
New suite/module names in tasks are implementation outputs, not existing tests
claimed to pass by this document.

## Attended acceptance before enabling an operation

Use authorized disposable accounts and existing infrastructure. Record commit,
actual client/package/version, native layout, platform, mode, endpoint, store,
operation, outcome, verification time and cleanup without secret values.
No production sharing or cloud provisioning is implied.

1. Complete M1 direct-terminal and real UI login, identity isolation, native
   cancellation, migration and persistent mount/lifecycle checks.
2. Qualify each required M2 round trip, selected account/endpoint launch, conflict
   refusal and outage retry. Preserve unrelated records during real native use.
   If a required row fails, explicitly defer retrieval and label M1 local-only.
3. Qualify M3 separately through the actual broker/vault: binding evidence,
   use/publish/maintain, denied tenant/account, real-client concurrency and crash
   recovery. Personal recovery success is not company-sharing evidence.
4. Keep OAuth remote operations disabled until exact eligibility, supported
   rotation and native-client concurrent-writer/refresh behavior are proven.
5. Verify entitled model/effort explicitly. The current K3.1 Pro default is high;
   our requested max must be configured. A fallback response is not success.
6. Run both-image packaging/import checks and the integrated matrix. Attach
   sanitized exact-head evidence and preserve existing review/release gates.

Fixtures do not replace attended provider acceptance. No runtime task is
completed by approving this handoff. See [research](research.md) and the
[user guide](../../docs/kimi-glm-profile-credentials.md).
