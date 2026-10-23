# Implementation Plan: Kimi and GLM profile credentials

Branch `031-kimi-glm-profile-credentials` · 2026-10-23 · [Specification](spec.md).
Target 1.7. Documentation complete; runtime tasks remain unchecked.

## Approach and dependencies

Build on feature 029's six-step wizard and the existing 026 identity/027 broker
contracts. Land the documentation as a separate 1.7 scope addition; implement in
this feature worktree after reviewing integration with the current 1.7 head.
Do not backport the new provider schemas to the 1.6 release as a documentation side effect.

Use Bash launchers, Python metadata/adapters, jq and the declared Tools/test
containers. Native vendor sign-in uses the existing workstation callback boundary.
Secret stores remain the configured Azure Key Vault, Bitwarden or 1Password
adapters; company clients use the broker and never acquire vault service authority.
Use existing mount generation rather than editing separate bench repositories
or advancing submodule pins implicitly.

The project constitution is still the unfilled template. Apply global workflow
rules and these concrete gates: explicit account binding, owner-only paths,
backward-compatible manifests, no secret diagnostics, no provider requests from
rendering, and fixture evidence separated from attended live acceptance.

## Delivery sequence

1. Add explicit `kimi-code` composition/identity metadata, validated profile paths
   and mode declarations. Preserve existing GLM schemas and paths; version any
   changed recovery envelope and reject unknown versions before mutation.
2. Add the Kimi launcher and profile provisioning; retain GLM launcher behavior.
   Test environment isolation, explicit account selection, cancellation, default
   home preservation and same-scope identity collisions before UI integration.
3. Extend shared runtime installation and all standard home/mount consumers.
   Pre-create bind sources as the host user. Persist Kimi profiles and GLM roots
   through Wave/devcontainer/Compose paths; never copy credentials into images.
4. Implement bounded projection/merge adapters. Qualify the exact native formats
   and enumerate permitted secret fields before enabling each remote mode.
5. Extend recovery enrollment/status and the existing broker/CPC mode registry.
   Reuse durable conflict/idempotency and writer coordination rather than a
   separate synchronization algorithm. Keep unsafe/unqualified modes disabled.
6. Add Profiles/dashboard login/check/recovery actions and honest status labels.
   Missing CLI is a prerequisite state; a credential adapter is not a Harness
   installer and does not add component selection keys.
7. Wire fixtures and native/live cases into current 1.7 CI/release automation,
   refresh docs from tested behavior and record exact version/mode/platform evidence.

## Provider eligibility at specification time

| Mode | Local operation | Remote recovery/company use | Automated maintenance |
| --- | --- | --- | --- |
| Kimi native OAuth | Isolated vendor login; native refresh | Individually qualify recovery; company sharing disabled initially | CPC refresh disabled until supported rotation/concurrency is proven |
| Kimi API key | Explicit selected provider/account | Planned adapter; qualify ownership and grants before enablement | Health/expiry if supported; provider/admin rotation |
| GLM Coding Plan API key | Existing isolated OpenCode login | Planned scoped Z.AI adapter; qualify account/plan binding and grants | Health/expiry if supported; provider/admin rotation |
| GLM standard API key | Explicitly distinct from Coding Plan | Separate qualified endpoint/mode binding | No invented OAuth refresh |

None of the planned remote modes is certified by these docs. Missing independent
account validation blocks company publication for that mode; never substitute an
entered email as proof. Record supported evidence or an explicit disabled result.

## Expected implementation owners

- Metadata/UI: `scripts/compose-ai-profiles.py`, `scripts/onboard-ai-profiles.py`,
  `scripts/setup-ai-profiles.sh`, `scripts/setup-profiles.py`,
  `apps/credential-manager/`, provider manifests/examples and credential planning.
- Runtime: new `base-image/files/kimi-profile` and `scripts/setup-kimi-profiles.sh`,
  existing `base-image/files/provider-profile`, image launcher wiring,
  `scripts/setup-bench-home.py`, `scripts/wave-container-shell.sh`, mount docs/template.
- Credentials: `credential-container/`, `scripts/profile_credentials.py`,
  recovery/backup helpers, `scripts/credential_sync_client.py`, `scripts/company_sync.py`,
  broker `core.py`, `oauth_adapter.py`, `cpc.py` and their declared Docker images.
- Tests: focused Kimi/GLM profile and credential adapter suites, existing setup,
  provider-profile, recovery, broker, Tools-runtime and lifecycle suites; 1.7 CI.

## Governed invariants

- `config/` — provider identities, metadata/credential contracts and release test declarations.
- `credential-container/`, `credential-broker/` — credential formats, grants and custody boundaries.
- `scripts/credential_sync_client.py`, `scripts/company_sync.py` — durable publication and safe synchronization.
- `base-image/files/`, `scripts/wave-container-shell.sh`, `scripts/setup-bench-home.py` — selected account runtime and persistent storage isolation.
- `openspec/`, `.github/workflows/` and source pins remain governed globally.

## Validation and landing

Run project checks in declared containers. Focused tests must fail against the
missing behavior before production changes. Use synthetic secrets for fixtures;
the native boundary is exercised without reading production token contents.
Test CLI-present/no-login separately from authenticated access.

The [quickstart](quickstart.md) defines attended acceptance and evidence. Before
release, rebase/integrate with current 1.7 and its release automation; add required
provider cases rather than treating old generic suites as new coverage. Report
unsupported modes explicitly, require exact-head review/CI and preserve the
existing release publication gate. Do not deploy billable services from tests.
