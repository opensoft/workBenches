## 1. Configuration baseline

- [x] 1.1 Capture the current OMO configuration and verify the qualified OpenAI and OmniRoute model identifiers
- [x] 1.2 Define the complete agent, category, fallback, and Anthropic-exclusion matrix

## 2. OMO roster implementation

- [x] 2.1 Update `~/.omo/omo.jsonc` with explicit primary and fallback assignments for every configurable OMO agent
- [x] 2.2 Add the specialized architecture, implementation, adversarial-review, security, testing, documentation, and strategy categories

## 3. Documentation

- [x] 3.1 Update `~/.config/opencode/TEAM-ROSTER.md` with the effective OMO agent and category roster
- [x] 3.2 Document the non-Anthropic fallback policy and unchanged profile/session boundaries

## 4. Validation

- [x] 4.1 Validate JSONC parsing, complete agent/category coverage, configured provider model IDs, and an empty Anthropic/Claude scan
- [x] 4.2 Run representative OpenAI, Qwen, GLM, DeepSeek, and Qwen Coder calls through `popencode max001`
- [x] 4.3 Record the consumer-level validation results in the roster documentation
