# Design decisions

Original scope: 2026-10-23. All Codex/Astra review refinements approved by Brett
Heap on 2026-10-24; see the feature's `review-2026-10-24.md` authority record.
These are planned contracts, not implemented or qualified runtime behavior.

1. Reuse identities, provider manifests, stores and the company broker. No
   second vault/identity database. Use one operation-level capability registry
   for actual client/layout/mode/endpoint/operation/store/platform evidence.
2. Add normalized `kimi-code`, its manifest and `pkimi`; retain GLM aliases
   and paths. Preserve compatibility rather than unconditional GLM Coding Plan
   dispatch. Resolve the exact native member, account and mode for every action.
3. Keep runtime homes isolated and persistent. Snapshot workBenches config/company/
   lease roots in the parent and change Kimi/XDG environment only for the vendor
   child. Actual before-launch/after-login sync must share the original roots.
4. Add native interactive terminal/PTY transport for wizard/dashboard sign-in.
   Existing noninteractive Tools callbacks and closed dashboard stdin cannot
   supply the live TUI. Preserve selected environment and UI/queue return, with
   cancellation, cleanup, completion detection and no secret transcript logging.
5. Define `inspect/extract/validate/fingerprint/merge-install` adapters. Export
   only selected credentials; track projection hashes separately from backing
   revisions. Preserve unrelated TOML/JSON records under qualified native writer
   coordination. Real sync uses these operations, retaining durable pending/
   install/baseline reconciliation. Package adapters in recovery and broker images.
6. Separate `authMode`, `syncPolicy` and projection version. Existing broker
   mode remains portable/broker-refresh policy through explicit migration.
   Select an owned local profile and derive its member rather than accepting
   arbitrary paths; bind immutable local/provider/auth-mode/broker IDs. Exclude
   personal/default roots, including their custom locations. Missing independent account evidence blocks
   company publication.
7. Validate effective routing: actual native provider, endpoint, credential
   source, model/alias and Kimi/OpenCode override precedence. Reject conflicting
   routes or require separately reviewed binding; directory isolation alone is
   insufficient. Do not log secret-bearing override values.
8. Integrate 032 verified installation identity/readiness plus actual executable
   and runtime version on each workstation/bench. Distinguish legacy/external
   Kimi and validate overrides. WorkBenches owns updates for its managed payload;
   prevent vendor self-update bypass and requalify drift. Leave external update
   policy untouched unless explicitly reviewed.
9. Import is explicit and reviewed. Vendor legacy migration does not carry OAuth;
   keep OAuth mode login-required, assess imported API-key modes normally, and prevent duplicate legacy-name import from copying
   credentials across identities. Never copy default homes into all accounts.
10. Bind verification to credential fingerprint/endpoint/account/client. Separate
    presence, verified access, entitlement and freshness. A default login does
    not qualify empty named profiles. No paid status probes or browser discovery
    from rendering.
11. Kimi 2.3.1 is an initial target, not a permanent pin. K3.1 Pro default effort
    observed on 2026-10-24 is high; configure/verify requested max explicitly.
    Validate endpoint IDs/local aliases and detect substitution; start a new
    session for model changes and preserve existing choices.
12. Deliver M1 local profiles/login/persistence, M2 qualified personal retrieval,
    then M3 company sync. The plan names minimum Kimi API-key and GLM Coding Plan
    API-key Azure Key Vault retrieval rows; zero enabled modes is local-only,
    not retrieval success. Other combinations need their own evidence.
13. Personal recovery and company sharing are independent opt-ins and gates.
    Keep unqualified Kimi OAuth remote custody/sharing/CPC refresh disabled;
    local login is first-class without certifying shared subscription tokens.
    Never replay an ambiguous rotating refresh or infer eligibility from fields.
14. Run the explicit matrix and affected suites through actual Tools/dashboard,
    sync and runtime-image boundaries. Check expected repository/commit/trusted
    workflow and every claimed live case; an unrelated green run is insufficient.
    Preserve existing exact-head review and publication gates.

Detailed schema, adapter and migration interfaces live in the Speckit contract;
the sole executable checklist is Speckit `tasks.md`. This revision deploys no
broker/vault and grants no new credential authority.
