# Implementation and acceptance handoff

Status: planned 1.7 behavior; runtime tasks remain unchecked. Locate the linked
031 worktree with `git worktree list`, then explicitly select the feature:

```bash
export SPECIFY_FEATURE=031-kimi-glm-profile-credentials
export SPECIFY_FEATURE_DIRECTORY=specs/031-kimi-glm-profile-credentials
```

The inherited `.specify/feature.json` points at 018; use the selection above.
Read the proposal, spec, contract and tasks; integrate current 1.7 first.
Run project verification through declared development/test containers.

## Fixture acceptance

| Area | Required cases |
| --- | --- |
| Accounts | Personal and two companies; two identities in one company; duplicate names; rerun; conflicting ambient key |
| Sign-in | CLI present without authentication; missing CLI; native browser/device flow; cancel/back; selected home |
| Persistence | Host ownership; actual Wave/devcontainer/Compose mounts; restart/recreate; missing mount; uninstall preserves data |
| Projection | Selected credential only; unrelated keys/config retained; unknown schema/client/mode; size/path/symlink rejection |
| Recovery | Each enabled store; locked/offline; occupied profile; reviewed replacement; cross-profile/provider/tenant denial |
| Sync | Separate grants; concurrent writers; stale versions; interrupted install/publication; no loops; unsupported refresh denied |
| UI/model | Queue/focus retained; narrow rendering; presence versus verification; entitlement unavailable; K3.1 Pro thinking/max; no paid status probes |

Canary secrets must not occur in logs, arguments, metadata, images or artifacts.
Run focused and existing regression suites from `tasks.md`.

## Attended acceptance before enabling a mode

Use authorized disposable test accounts and existing infrastructure. Record exact
commit, client version, platform, mode, outcome, timestamp and cleanup without
credential values. No production credential sharing or cloud provisioning is implied.

1. Sign into distinct Kimi/GLM profiles and verify the intended provider account.
2. Verify entitled model selection and explicit unavailable-model handling.
3. Restart/recreate a bench and reboot each claimed platform; check persistent
   storage and provider access separately.
4. Test each recovery-enabled mode/store, occupied-profile refusal and offline retry.
5. Test company use/publish/maintain grants, denied tenant/account, concurrent
   update and crash reconciliation through the real broker/vault.
6. Qualify Kimi OAuth refresh ownership/rotation before enabling CPC work;
   otherwise record it as disabled and demonstrate supported local login.
7. Attach sanitized exact-head evidence and complete existing release gates.
   Fixture results cannot replace live provider acceptance.

See [research](research.md) and [the planned user guide](../../docs/kimi-glm-profile-credentials.md).
