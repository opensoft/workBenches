## Context

OpenCode loads Oh My OpenCode (OMO) from the machine-wide configuration at `~/.omo/omo.jsonc`. That roster currently assigns all agents and categories to OpenAI models. The same OpenCode consumer now exposes qualified custom-provider routes for Qwen3.8 Max, Qwen3.8 Flash, Qwen3 Coder Plus, GLM-5.3, and DeepSeek V4 Pro through OmniRoute.

OMO does not treat every agent as a generic prompt. Hephaestus, Momus, Sisyphus, Sisyphus Junior, and Atlas contain model-family-sensitive prompt selection. Therefore, primary assignments must consider prompt compatibility in addition to benchmark strength. The user's hard policy is that the effective OMO roster must contain no Anthropic primary or fallback models.

## Goals / Non-Goals

**Goals:**

- Use the strongest qualified model for each OMO role while preserving model-family prompt compatibility.
- Introduce Qwen, GLM, and DeepSeek where they add useful capability or independent review perspective.
- Give every configured agent and category an explicit non-Anthropic fallback path.
- Add named categories for architecture, implementation, adversarial review, security, testing, documentation, and strategy.
- Validate configuration syntax, Anthropic exclusion, model resolution, and representative runtime calls through `popencode`.

**Non-Goals:**

- Changing OpenAI account credentials, OmniRoute secrets, provider endpoints, or the shared session database.
- Adding Anthropic as an emergency fallback.
- Replacing OMO's built-in agent prompts or inventing a parallel agent framework.
- Claiming visual-model support for OmniRoute routes that have only been qualified for text.

## Decisions

### Use OpenAI for prompt-sensitive orchestration

The primary orchestrators remain on the OpenAI family: Sisyphus, Hephaestus, Prometheus, Atlas, Build, Plan, and OpenCode-Builder use GPT-5.6 Sol; Momus uses GPT-5.6 Terra. This aligns the most consequential tool-using agents with their GPT-aware OMO prompts. GPT-5.6 Sol is used at `high` or `xhigh` effort according to task depth.

Alternative considered: move all planners and builders to Qwen3.8 Max. This would increase model diversity but discard known GPT-specific prompt routing in several core agents, so Qwen is used for independent analysis and fallbacks instead.

### Use independent model families for analysis and execution

The supporting agents are deliberately heterogeneous:

| OMO agent | Primary model | Purpose |
|---|---|---|
| `metis` | `omniroute/alibaba-sg/qwen3.8-max` | Requirements and plan gap analysis |
| `oracle` | `omniroute/alibaba-sg/qwen3.8-max` | Architecture and deep technical consultation |
| `sisyphus-junior` | `omniroute/zai-glm-5.3` | Focused implementation with an OMO GLM-specific prompt path |
| `librarian` | `omniroute/alibaba-us/qwen3.8-flash` | Large-context research and documentation lookup |
| `explore` | `openai/gpt-5.6-luna` | Fast repository exploration |
| `multimodal-looker` | `openai/gpt-5.6-terra` | Stable text-and-image inspection |

DeepSeek is assigned to an explicit `adversarial-review` category, while Qwen3 Coder Plus is assigned to `implementation`. This gives the team independent code-review and coding perspectives without forcing a less-compatible model into a prompt-sensitive core agent.

Alternative considered: use one strongest model for every support role. This would reduce routing complexity but eliminate the independent perspectives the user wants for architecture, strategy, and code review.

### Make the fallback policy explicit and Anthropic-free

Each agent and category receives an ordered `fallback_models` list containing only qualified OpenAI or OmniRoute model IDs. OpenAI primaries generally fall back to Qwen3.8 Max and another OpenAI tier. OmniRoute primaries generally fall back to an OpenAI model and a second qualified OmniRoute family. The OMO-level `disabled_providers` list also blocks `anthropic`, preventing the resolver from selecting it from a hardcoded implicit chain after explicit choices are exhausted. This makes the no-Anthropic policy both inspectable and enforced.

Alternative considered: rely on OMO's implicit model-resolution chain. That is rejected because the effective emergency route would be harder to audit against the Anthropic prohibition.

### Preserve profile and session behavior

Only `~/.omo/omo.jsonc` and roster documentation change. The `popencode` launcher, profile credentials, last-profile pointer, OpenCode provider catalog, and project-derived shared session database remain untouched.

## Risks / Trade-offs

- [OmniRoute model is catalogued but an upstream entitlement changes] -> Keep explicit cross-provider fallbacks and run representative calls through the consuming `popencode` profile.
- [A fallback model receives a prompt optimized for the primary family] -> Keep core prompt-sensitive agents on OpenAI and use cross-family fallbacks only for availability recovery.
- [Custom category names are not selected automatically by a particular workflow] -> Document the names so they can be targeted explicitly with delegated tasks.
- [Configuration passes syntax validation but OMO ignores an unsupported field] -> Validate loaded agent/category resolution through OpenCode in addition to parsing the file.
- [No Anthropic fallback reduces resilience during simultaneous OpenAI and OmniRoute outages] -> This is an intentional policy trade-off; use multiple non-Anthropic providers and model families.

## Migration Plan

1. Save the current `~/.omo/omo.jsonc` content for a simple file-level rollback.
2. Replace the agent and category assignments with the designed roster and explicit fallback lists.
3. Scan every model-bearing field for Anthropic or Claude identifiers; the result must be empty.
4. Parse/load the configuration through the installed OpenCode/OMO consumer.
5. Run representative OpenAI, Qwen, GLM, DeepSeek, and Qwen Coder calls through `popencode max001`.
6. Update `TEAM-ROSTER.md` with the effective OMO matrix and validation evidence.

Rollback consists of restoring the prior `~/.omo/omo.jsonc`; credential and session state require no rollback because they are not modified.

## Open Questions

None. The available routes, account behavior, and Anthropic exclusion policy are already known.
