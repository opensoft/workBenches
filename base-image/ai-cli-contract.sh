#!/usr/bin/env bash

# Shared command contract installed by Layer 0 and verified in rebuilt bench
# images. Keep this as the single production source of required CLI names.
readonly WORKBENCHES_REQUIRED_AI_CLIS=(
    claude codex gemini pi herdr copilot opencode omo letta notebooklm nlm
    kimi qwen aider openhands amp cursor-agent
)
