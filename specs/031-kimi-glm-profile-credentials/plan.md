# Implementation Plan: Kimi and GLM profile credentials

Branch `031-kimi-glm-profile-credentials` · target 1.7. Original plan 2026-10-23;
all Codex/Astra review revisions approved by Brett Heap on 2026-10-24.
[Specification](spec.md) · [approved review](review-2026-10-24.md).
Documentation only: runtime tasks and live qualification remain pending.

## Dependencies and delivery milestones

Integrate current 029 wizard/026 identity/027 broker contracts and reconcile
feature 032's managed installer interface before dependent runtime work. Use this
feature worktree and declared Tools/test containers; preserve the 1.6 line and
other worktrees. No source pins, live credentials or cloud resources change here.

Deliver in this order:

1. **M1 — Local profiles, login and persistence:** isolated homes, actual client
   identification, selected routing, native terminal handoff, factual status,
   safe migration and real workstation/bench persistence. M1 does not claim
   remote recovery or company sharing.
2. **M2 — Qualified personal credential retrieval:** projection-aware recovery,
   scoped enrollment, conflict-safe merges and the minimum live rows below.
   Personal recovery eligibility does not authorize company publication.
3. **M3 — Qualified company synchronization:** immutable local/broker binding,
   separate use/publish/maintain grants, stable workBenches control-plane paths,
   projection-aware durable sync and qualified CPC operations. Shared Kimi OAuth
   and CPC refresh remain disabled until separately qualified.

The single executable checklist is [tasks.md](tasks.md). These are separate
release outcomes; finishing M1 does not count as delivering M2 or M3.

## Qualification before dependent implementation

T000 records an operation-level matrix for the exact executable/package/version,
native credential layout/member, provider/region/endpoint, authentication mode,
verification/account-binding evidence, store and claimed platform.

- Freeze native location/field allowlists, projection, verification and merge
  behavior before enabling recovery. Unknown client/layout is unsupported.
- Establish independent provider-account binding before company publication;
  email, membership or a typed path is not proof. Missing evidence blocks that
  operation without relabeling personal recovery as company sharing.
- Define routing override rejection/review and exact provider/model/endpoint
  confirmation after login and before launch. No paid status probes.
- Establish native writer coordination. If an advisory lock cannot coordinate a
  native writer, defer installation to a qualified quiescent window or conflict.
- Resolve actual client identity/update behavior on each workstation and bench,
  including legacy Kimi, self-updates and external installs.

Qualification is evidence, not an inference from token/account field names.
Kimi Code 2.3.1 is the initial target, not a permanent pin or proven minimum;
qualify any newer actual client instead of trusting a stale installer receipt.

## Minimum 1.7 retrieval acceptance

The initial named retrieval target is the existing Azure Key Vault recovery path,
using existing authorized infrastructure and disposable test accounts. These
rows are acceptance targets, not implemented/qualified support claims.

| Milestone | Provider/authentication mode | Store | Required evidence |
| --- | --- | --- | --- |
| M2 required | Kimi Platform API key, exact qualified region/endpoint | Azure Key Vault | Attended fresh named-profile restore and selected launch; occupied-target refusal; outage retry; unrelated TOML fields retained |
| M2 required | GLM Z.AI Coding Plan API key | Azure Key Vault | Attended selected native-member restore and selected plan/endpoint launch; occupied-target refusal; outage retry; other OpenCode members retained |
| Independently qualified | GLM standard API key and other store combinations | Azure Key Vault, Bitwarden or 1Password as applicable | Same per-mode/store live evidence before enabled/support claims; all stores still receive synthetic fixtures |
| Disabled until qualified | Kimi OAuth remote recovery, company sharing and CPC refresh | Any | Native-format, eligibility, account-binding and supported rotation/concurrent-writer evidence per operation |

Required M2 rows cover native Linux and WSL Linux workstation/bench execution
before those platforms are claimed. Use existing infrastructure; tests do not
authorize provisioning or production account copying. An unqualified required
row blocks the combined retrieval claim. Record M1 as local-only and defer M2
explicitly rather than passing with an empty enabled set.
M3 requires its own per-mode grants/binding/live-broker gate; M2 cannot satisfy it.

## Runtime architecture

- **Metadata:** additive Kimi manifest; preserve GLM aliases/paths. Separate
  `authMode`, `syncPolicy` and `projectionSchemaVersion`. Legacy broker
  `mode` remains policy; version/migrate explicitly and reject incompatible
  mutations.
- **Login/launch:** validate effective routing, native member and client identity.
  Wizard/dashboard login needs a real terminal/PTY with cancellation, cleanup,
  completion detection and saved UI return. File RPC and closed stdin are not
  interactive transport. Direct-terminal and UI login are separate checks.
  GLM standard/Coding Plan dispatch must target or verify the selected member.
- **Control plane:** derive workBenches config/company/lease roots in the parent;
  apply GLM XDG and Kimi home changes only to the vendor child. Before-launch and
  after-login sync use the same original roots and lease.
- **Adapters:** `inspect → extract → validate → fingerprint → merge/install`.
  Publish/hash only the selected projection; track backing-file revision
  separately. Preserve unrelated records, coordinate native writers and retain
  durable pending-operation/install/baseline reconciliation. Recovery and the
  real sync client share adapters packaged in both runtime images.
- **Recovery:** exact owned profile/member enrollment, private bounded envelopes,
  explicit backed-up replacement, offline preservation and safe crash recovery.
- **Company:** select validated local profiles rather than arbitrary JSON paths.
  Bind immutable local ID/provider/auth mode/member/broker ID; exclude personal/default roots,
  including their custom locations; allow validated company profiles in custom roots. Reuse grants/version/idempotency; unrelated native
  file edits never become selected-credential publications.
- **Persistence/installers:** update actual shared mount consumers without
  implicit bench-repository edits. Pre-create host-owned sources. Consume 032
  verified package identity and actual runtime observations. Managed updates
  belong to workBenches; prevent vendor auto-install bypass. Do not silently
  rewrite external installation policy. Requalify after version/layout/PATH/
  executable changes and preserve credentials.
- **UI/model:** separate presence, verified access/account, entitlement and
  freshness. Bind observations to credential fingerprint/endpoint/account/client.
  Explicitly set and verify `max`; K3.1 Pro's current vendor default is `high`.
  Validate native model IDs/aliases and detect substitution. Preserve queue/focus;
  a default login cannot qualify an empty named profile.

## Implementation owners and validation

T001/T002 own metadata and launchers; T002A owns interactive transport and the
Tools/dashboard boundary; T003 owns mount/032 compatibility; T004 owns projection
adapters and image packaging; T005 owns recovery; T006 owns company enrollment/
client/broker/CPC; T007 owns personal-recovery UI/model observations and T007B
owns company UI after T006; T008 owns the concrete
acceptance matrix and exact-head CI gate; T009 reconciles docs; T010 records
attended milestone outcomes. T000 qualifies dependent operations first.

Run named focused and affected existing suites in declared containers. Include
real sync-client merge/crash tests, terminal handoff/cancellation, default versus
named-profile readiness, cross-identity legacy-copy rejection and image import
smokes. Use synthetic secret canaries; no secret arguments/logs/layers/artifacts.
Fixture success cannot replace attended provider acceptance.

Before release, validate expected repository/SHA/trusted workflow and every
required case for each claimed milestone/platform. An unrelated green run ID is
not evidence. Preserve exact-head review and existing publication gates.
Governed areas remain config/schema, credential custody/broker, company sync,
native callbacks, launcher/home mounts, OpenSpec and CI. The constitution remains
a template; global workflow and these concrete gates apply.
