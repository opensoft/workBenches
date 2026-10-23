# Source review and decisions — 2026-10-23

Reviewed workBenches wizard baseline `b8b1607`; these observations describe source,
not a live authentication certification.

| Existing source | Observation / design consequence |
| --- | --- |
| `scripts/compose-ai-profiles.py` and `scripts/setup-ai-profiles.sh` | Provider composition/application covers Claude, OpenAI, Gemini, Grok and GLM; Kimi requires an additive provider path. |
| `base-image/files/provider-profile` | GLM runs OpenCode with isolated XDG roots and supports pglm/pzai; preserve those accounts and paths. |
| `apps/credential-manager/credential_manager.py` | GLM currently returns sign-in guidance, not verified authentication; Kimi lacks an account adapter. Documentation must not imply automatic verification. |
| `scripts/profile_credentials.py`, `credential-container/credential_recovery.py` | Recovery/presence adapters currently cover Claude/Codex/Pi/OmniRoute, not Kimi/GLM. |
| `scripts/setup-bench-home.py`, `scripts/wave-container-shell.sh`, `docker-compose.mounts.yml` | Standard Kimi profile-home persistence is missing; update actual mount generation as well as the reference template. |
| `base-image/install-ai-clis.sh` | Installs @moonshot-ai/kimi-code@latest at build time; reusing an image does not prove its installed version. |
| `specs/027-company-credential-sync/spec.md` | Reuse grants, durable versions, writer coordination and mode qualification; company membership alone does not authorize credentials. |

Primary vendor sources checked on 2026-10-23:

- [Kimi CLI 2.3.1 release](https://github.com/MoonshotAI/kimi-code/releases/tag/%40moonshot-ai/kimi-code%402.3.1): latest release observed, published 2026-10-23. Treat it as the initial test target, not a proven minimum client version.
- [Kimi getting started](https://www.kimi.com/code/docs/en/kimi-code-cli/guides/getting-started.html): `/login` supports native OAuth device approval or a platform API key.
- [Kimi data locations](https://www.kimi.com/code/docs/en/kimi-code-cli/configuration/data-locations.html): KIMI_CODE_HOME relocates configuration, credentials and session data. This supports local account isolation, not an inference that OAuth sharing is permitted.
- [Kimi models](https://www.kimi.com/code/docs/en/kimi-code/models): k3.1-pro is available subject to plan entitlement, thinking cannot be disabled, and max is the default reasoning effort. Model selection does not come from installing the CLI.
- [Z.AI OpenCode integration](https://docs.z.ai/devpack/tool/opencode): select the matching Z.AI provider/plan and enter its API key. Account/endpoint modes must remain distinct.

Not established: stable non-secret account verification for every API-key mode,
Kimi OAuth remote recovery/sharing permission, exclusive refresh ownership, or
live compatibility across claimed platforms. Qualification tasks must resolve
these per mode; missing evidence keeps that operation disabled while preserving
supported local sign-in. No production credentials were read for this document.
