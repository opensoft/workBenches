## ADDED Requirements

### Requirement: Complete OMO agent coverage
The system SHALL assign an explicit primary model to every installed configurable OMO agent, including `build`, `plan`, `OpenCode-Builder`, `sisyphus`, `hephaestus`, `prometheus`, `metis`, `momus`, `atlas`, `sisyphus-junior`, `oracle`, `librarian`, `explore`, and `multimodal-looker`.

#### Scenario: OMO loads the agent roster
- **WHEN** the installed OMO plugin reads `~/.omo/omo.jsonc`
- **THEN** every configurable OMO agent resolves to an explicit primary model

### Requirement: Anthropic-free model policy
The system MUST NOT reference an Anthropic or Claude model in any OMO agent primary, category primary, fallback, or model-list field, and SHALL list `anthropic` in OMO's `disabled_providers` configuration so an implicit resolver chain cannot select it.

#### Scenario: Configuration is audited for prohibited models
- **WHEN** all model-bearing fields in `~/.omo/omo.jsonc` are inspected case-insensitively
- **THEN** no value contains `anthropic` or `claude` and the `anthropic` provider is explicitly disabled for OMO

### Requirement: Role-appropriate model selection
The system SHALL retain GPT-5.6 Sol or Terra for OMO agents with GPT-sensitive orchestration or review prompts, SHALL use GLM-5.3 for `sisyphus-junior`, and SHALL use qualified Qwen models for independent deep-analysis and large-context research roles.

#### Scenario: Prompt-sensitive core agents are resolved
- **WHEN** the primary assignments for Sisyphus, Hephaestus, Prometheus, Momus, and Atlas are inspected
- **THEN** they resolve to their designated GPT-5.6 Sol or Terra models and effort levels

#### Scenario: Independent supporting agents are resolved
- **WHEN** Metis, Oracle, Sisyphus Junior, Librarian, and Explore are inspected
- **THEN** their primary assignments provide Qwen, GLM, and OpenAI model-family diversity according to the design

### Requirement: Explicit resilient fallbacks
Every configured OMO agent and category SHALL declare at least one explicit fallback model, and every fallback SHALL be a locally configured non-Anthropic OpenAI or OmniRoute route.

#### Scenario: A primary provider is unavailable
- **WHEN** an agent's primary model cannot be used and OMO performs model fallback
- **THEN** the next configured route is an explicit OpenAI or OmniRoute model and is not an Anthropic model

### Requirement: Specialized task categories
The system SHALL provide explicit OMO categories for quick work, low- and high-depth general work, writing, artistry, visual engineering, deep reasoning, ultrabrain reasoning, architecture, implementation, adversarial review, security, testing, documentation, and strategy.

#### Scenario: A task is delegated by specialization
- **WHEN** an OMO task targets one of the configured category names
- **THEN** it resolves to the primary and fallback models selected for that specialization

### Requirement: Profile and session isolation is preserved
The change SHALL NOT modify OpenCode account credentials, the `popencode` profile selector, the last-profile pointer, provider endpoints, or project-shared session storage.

#### Scenario: User switches accounts after roster installation
- **WHEN** the user launches the same project with `popencode max001` or another configured profile
- **THEN** the new OMO roster is available while the existing profile selection and project session behavior remain unchanged

### Requirement: Consumer-level validation
The roster SHALL be validated by syntax inspection, prohibited-model scanning, model discovery, and representative runtime calls made through the profile-aware OpenCode consumer.

#### Scenario: Roster validation succeeds
- **WHEN** validation is run after the configuration change
- **THEN** the configuration parses, the prohibited-model scan is empty, configured routes are discoverable, and representative OpenAI, Qwen, GLM, DeepSeek, and Qwen Coder calls succeed or any upstream failure is reported exactly

### Requirement: Roster documentation
The system SHALL document each OMO agent and category primary model, its intended role, the fallback policy, and the validation result in the local OpenCode roster document.

#### Scenario: Operator reviews the installed team
- **WHEN** the operator opens `~/.config/opencode/TEAM-ROSTER.md`
- **THEN** the effective Anthropic-free OMO roster and its validation status are visible without reading the raw configuration
