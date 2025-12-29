#!/bin/bash
# Shared AI CLI Installation Script
# Version: 1.1.0
#
# This script installs all AI CLI tools for devcontainers.
# Source this from Dockerfiles to maintain a single source of truth.
#
# Usage in Dockerfile:
#   COPY --chown=$USERNAME:$USERNAME devcontainer-shared/install-ai-clis.sh /tmp/
#   RUN bash /tmp/install-ai-clis.sh

set -e

echo "========================================="
echo "Installing AI CLI Tools"
echo "========================================="

# Ensure npm global directory exists
mkdir -p $HOME/.npm-global
npm config set prefix $HOME/.npm-global

# ========================================
# BUN RUNTIME (for OpenCode plugins)
# ========================================
echo "Installing Bun runtime..."
curl -fsSL https://bun.sh/install | bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

echo "Installing OpenSpec..."
npm install -g @fission-ai/openspec@latest

echo "Installing Claude Code CLI..."
npm install -g @anthropic-ai/claude-code

echo "Installing OpenAI Codex CLI..."
npm install -g @openai/codex

echo "Installing Google Gemini CLI..."
npm install -g @google/gemini-cli

echo "Installing GitHub Copilot CLI..."
npm install -g @githubnext/github-copilot-cli

echo "Installing Grok CLI (xAI)..."
npm install -g @xai-org/grok-cli || echo "Grok CLI not yet available via npm, manual install required"

echo "Installing OpenCode AI (from Opensoft fork)..."
# OpenCode: open source AI coding agent (https://github.com/Opensoft/opencode)
# Install from Opensoft fork instead of npm (sst version)
git clone --depth 1 https://github.com/Opensoft/opencode.git /tmp/opencode
cd /tmp/opencode
bun install
bun run --cwd packages/opencode build
npm link -g --prefix $HOME/.npm-global /tmp/opencode/packages/opencode
cd -

echo "Installing OpenAgents for OpenCode..."
# OpenAgents: agent pack for OpenCode (https://github.com/darrenhinde/OpenAgents)
# Use a profile to avoid interactive prompt during Docker build
curl -fsSL https://raw.githubusercontent.com/darrenhinde/OpenAgents/main/install.sh | bash -s essential

# ========================================
# OH-MY-OPENCODE (OMO) PLUGIN SETUP
# ========================================
echo "Pre-installing OpenCode plugins via Bun..."
# OpenCode uses ~/.opencode/plugin for plugins
mkdir -p $HOME/.opencode/plugin

# Install OMO and auth plugins (these are the plugins declared in opencode.json)
cd $HOME/.opencode/plugin
bun add oh-my-opencode@latest 2>/dev/null || echo "OMO plugin install deferred to first run"
bun add opencode-gemini-auth@1.3.6 2>/dev/null || echo "Gemini auth plugin install deferred"
bun add opencode-openai-codex-auth@4.2.0 2>/dev/null || echo "Codex auth plugin install deferred"
cd -

echo "Installing Letta Code..."
# Letta Code: memory-first coding agent (https://github.com/letta-ai/letta-code)
npm install -g @letta-ai/letta-code

echo "========================================="
echo "AI CLI Tools Installation Complete!"
echo "========================================="
echo ""
echo "Installed tools:"
echo "  - OpenSpec"
echo "  - Claude Code (claude)"
echo "  - OpenAI Codex (codex)"
echo "  - Google Gemini (gemini)"
echo "  - GitHub Copilot (copilot)"
echo "  - Grok (grok)"
echo "  - OpenCode (opencode) + OMO plugins"
echo "  - Letta Code (letta)"
echo ""
