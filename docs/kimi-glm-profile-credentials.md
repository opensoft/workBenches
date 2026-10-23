# Kimi and GLM profiles — planned for 1.7

**Status: specified, not implemented.** See [feature 031](../specs/031-kimi-glm-profile-credentials/spec.md)
and its [tasks](../specs/031-kimi-glm-profile-credentials/tasks.md).

## Current behavior

GLM uses `pglm`/`pzai` with isolated OpenCode homes. `pglm login PROFILE` selects
the matching Z.AI provider/plan and accepts its API key; `pglm PROFILE` launches it.
The dashboard currently provides sign-in guidance, not live key verification.
Kimi supports manual isolation with `KIMI_CODE_HOME` and `/login` for native OAuth
or a platform API key. Its workBenches composer, launcher, dashboard adapter and
standard persistent profile mount are missing. Neither provider yet has a
dedicated automatic recovery/company-sync adapter.

## Planned account workflow

Select an identity in Profiles → Personal or company → AI accounts, choose Kimi
Code or GLM and a named account, then sign in, verify, recover or launch explicitly.
Company/GitHub sign-in does not authenticate either provider. Metadata contains
names, emails and references, not secrets. Cancel preserves completed steps,
other identities and the component queue.

Planned Kimi commands:

```bash
pkimi list
pkimi login team01
pkimi status team01
pkimi team01
```

Each Kimi account gets a home under
`$HOME/.kimi-code-profiles/profiles/<profilePath>`. Existing GLM paths/aliases stay.
Importing a default Kimi login is explicit and never duplicates it into all
identities. Managed homes persist through bench recreation/reboot; uninstall
preserves them. Persistence cannot keep a killed process running or make a
revoked provider login valid.

## Credential custody and model choice

Recovery is opt-in using an existing configured vault. Export only the selected
credential projection, excluding sessions, plugins, other keys and unrelated
settings. Restore preserves occupied profiles by default; reviewed replacement
is backed up. Offline stores retain usable local credentials.

Company sync additionally requires exact broker grants and a qualified provider
mode. Membership or email is insufficient. API keys rotate through the provider/
administrator; Kimi OAuth sharing and CPC refresh stay disabled until qualified.

Status separates credential presence, last verified access, model entitlement and
sync freshness. No secrets are displayed or paid generation used for rendering.
Initial compatibility testing targets Kimi Code 2.3.1. Offer k3.1-pro with thinking/
max when entitled, preserve existing choices and start a new session on model
change. Unavailable requests are explicit, never silently substituted.

See [source research](../specs/031-kimi-glm-profile-credentials/research.md) and
[acceptance](../specs/031-kimi-glm-profile-credentials/quickstart.md).
