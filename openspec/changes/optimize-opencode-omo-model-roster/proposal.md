## Why

The current Oh My OpenCode roster routes every agent through OpenAI even though the local OpenCode installation now has qualified OmniRoute access to Qwen, GLM, and DeepSeek models. The roster should use each model where its strengths and OMO prompt compatibility fit the role, while guaranteeing that no Anthropic model is selected as either a primary or fallback.

## What Changes

- Assign every built-in OMO agent a deliberate primary model based on its job and model-family prompt compatibility.
- Add explicit non-Anthropic fallback routes using the available OpenAI, Qwen, GLM, and DeepSeek models.
- Expand the OMO category roster so implementation, architecture, review, testing, documentation, and security work can be routed intentionally.
- Preserve the existing profile-aware OpenCode account switching and project-shared session behavior.
- Document the effective roster and validate the configured model routes through the profile-aware OpenCode consumer.

## Capabilities

### New Capabilities

- `omo-model-roster`: Defines the supported OMO agent and category assignments, fallback policy, Anthropic exclusion rule, and runtime-validation expectations.

### Modified Capabilities

None.

## Impact

- Updates the machine-wide OMO configuration at `~/.omo/omo.jsonc`.
- Updates the local OpenCode roster documentation at `~/.config/opencode/TEAM-ROSTER.md`.
- Adds an OpenSpec change package under `openspec/changes/optimize-opencode-omo-model-roster/`.
- Does not change stored OpenAI logins, OmniRoute API keys, provider endpoints, or project session storage.
