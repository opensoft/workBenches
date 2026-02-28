#!/bin/bash
# Shared AI CLI Installation Script
# Version: 1.3.0
#
# This script installs all AI CLI tools for devcontainers.
# Source this from Dockerfiles to maintain a single source of truth.
#
# Installs:
#   - OpenCode (from Opensoft/opencode fork)
#   - oh-my-opencode plugin (from git: darrenhinde/oh-my-opencode)
#     Includes built-in agents: Sisyphus, oracle, librarian, explore, frontend, etc.
#   - Auth plugins (opencode-gemini-auth, opencode-openai-codex-auth)
#   - Other AI CLIs (Codex, Gemini, Copilot, etc.)
#   - Claude Code (via native installer, not npm)
#
# Note: OpenAgents agent files (openagent.md, opencoder.md) are copied via
#       Dockerfile, not installed by this script
#
# Usage in Dockerfile:
#   COPY --chown=$USERNAME:$USERNAME install-ai-clis.sh /tmp/
#   RUN bash /tmp/install-ai-clis.sh

set -e

# ========================================
# DEBUG AND TIMEOUT CONFIGURATION
# ========================================
DEBUG="${DEBUG:-1}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-120}"  # 2 minutes per command
BUN_OPERATIONS_TIMEOUT="${BUN_OPERATIONS_TIMEOUT:-180}"  # 3 minutes for bun ops

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        echo "[DEBUG $(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
    fi
}

log_info() {
    echo "[INFO $(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[ERROR $(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

run_with_timeout() {
    local timeout="$1"
    local description="$2"
    shift 2
    
    log_debug "Running with timeout ${timeout}s: $description"
    log_debug "Command: $@"
    
    if timeout "$timeout" "$@"; then
        log_debug "✓ Completed successfully: $description"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "✗ Timeout ($timeout s) while: $description"
            log_error "Command that timed out: $@"
        else
            log_error "✗ Failed with exit code $exit_code while: $description"
        fi
        return $exit_code
    fi
}

check_system_resources() {
    log_debug "Checking system resources..."
    log_debug "Memory: $(free -h | head -2)"
    log_debug "Disk: $(df -h / | tail -1)"
    log_debug "CPU: $(nproc) cores"
    log_debug "Available disk in /tmp: $(df -h /tmp | tail -1)"
}

log_info "=========================================="
log_info "Installing AI CLI Tools"
log_info "=========================================="
log_info ""

check_system_resources

# Ensure npm global directory exists
log_debug "Creating npm global directory"
mkdir -p $HOME/.npm-global
run_with_timeout "$COMMAND_TIMEOUT" "npm config set prefix" npm config set prefix $HOME/.npm-global || true

# ========================================
# BUN RUNTIME (for OpenCode plugins)
# ========================================
log_info "Installing Bun runtime..."
if run_with_timeout "$COMMAND_TIMEOUT" "Bun runtime download and install" bash -c 'curl -fsSL https://bun.sh/install | bash'; then
    log_debug "Bun installation completed"
else
    log_error "Failed to download or install Bun. Continuing without Bun support."
fi

export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

log_debug "Verifying Bun installation"
if which bun >/dev/null 2>&1; then
    log_debug "Bun found at: $(which bun)"
    log_debug "Bun version: $(bun --version)"
else
    log_error "Bun not found in PATH after installation"
fi

log_info "Installing OpenSpec..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "OpenSpec npm install" npm install -g @fission-ai/openspec@latest; then
    log_error "OpenSpec installation failed (continuing)"
fi

log_info "Installing Claude Code CLI (native installer)..."
# Native installer is now the recommended method (npm is deprecated)
# Installs to ~/.local/bin/claude, auto-updates in background, no Node.js dependency
# Claude installer needs more time for download, use 5 minutes
if ! run_with_timeout "300" "Claude Code native install" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'; then
    log_error "Claude Code native installation failed (continuing)"
fi

log_info "Installing OpenAI Codex CLI..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "Codex npm install" npm install -g @openai/codex; then
    log_error "Codex installation failed (continuing)"
fi

log_info "Installing Google Gemini CLI..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "Gemini npm install" npm install -g @google/gemini-cli; then
    log_error "Gemini CLI installation failed (continuing)"
fi

log_info "Installing GitHub Copilot CLI..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "GitHub Copilot npm install" npm install -g @githubnext/github-copilot-cli; then
    log_error "GitHub Copilot installation failed (continuing)"
fi

log_info "Installing Grok CLI (xAI)..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "Grok npm install" npm install -g @xai-org/grok-cli; then
    log_error "Grok CLI not available via npm (skipping)"
fi

log_info "Installing OpenCode AI (from Opensoft fork)..."
# OpenCode: open source AI coding agent (https://github.com/Opensoft/opencode)
# Install from Opensoft fork instead of npm (sst version)
log_debug "Cloning OpenCode repository from Opensoft..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "OpenCode git clone" git clone --depth 1 https://github.com/Opensoft/opencode.git /tmp/opencode; then
    log_error "Failed to clone OpenCode repository (skipping OpenCode installation)"
else
    cd /tmp/opencode
    log_debug "Current directory: $(pwd)"
    log_debug "Directory contents: $(ls -la | head -20)"
    
    log_info "Running bun install for OpenCode..."
    if command -v bun >/dev/null 2>&1; then
        log_debug "Bun is available, using it for installation"
        if run_with_timeout "$BUN_OPERATIONS_TIMEOUT" "OpenCode bun install" bun install; then
            log_info "Building OpenCode..."
            if ! run_with_timeout "$BUN_OPERATIONS_TIMEOUT" "OpenCode bun build" bun run --cwd packages/opencode build; then
                log_error "OpenCode build failed"
            fi
        else
            log_error "OpenCode bun install timeout, trying npm fallback"
            if run_with_timeout "$COMMAND_TIMEOUT" "OpenCode npm install" npm install; then
                log_info "Building with npm..."
                run_with_timeout "$COMMAND_TIMEOUT" "OpenCode npm build" npm run --prefix packages/opencode build || log_error "npm build failed"
            fi
        fi
    else
        log_debug "Bun not available, using npm fallback"
        if run_with_timeout "$COMMAND_TIMEOUT" "OpenCode npm install" npm install; then
            log_info "Building with npm..."
            run_with_timeout "$COMMAND_TIMEOUT" "OpenCode npm build" npm run --prefix packages/opencode build || log_error "npm build failed"
        else
            log_error "OpenCode npm install failed"
        fi
    fi
    
    log_info "Installing OpenCode package globally..."
    if run_with_timeout "$COMMAND_TIMEOUT" "OpenCode npm install -g" npm install -g /tmp/opencode/packages/opencode; then
        # Replace the Node.js wrapper with a bash wrapper that directly calls the platform binary
        log_info "Creating OpenCode wrapper script..."
        rm -f $HOME/.npm-global/bin/opencode
        cat > $HOME/.npm-global/bin/opencode << 'EOF'
#!/bin/bash
# OpenCode wrapper - calls platform binary directly using absolute path
OPENCODE_BIN="$HOME/.npm-global/lib/node_modules/opencode/dist/opencode-linux-x64/bin/opencode"
if [ -x "$OPENCODE_BIN" ]; then
    exec "$OPENCODE_BIN" "$@"
else
    echo "Error: OpenCode platform binary not found at $OPENCODE_BIN"
    exit 1
fi
EOF
        chmod +x $HOME/.npm-global/bin/opencode
        log_debug "OpenCode wrapper created at $HOME/.npm-global/bin/opencode"
    else
        log_error "Failed to install OpenCode globally"
    fi
    
    cd -
fi

# ========================================
# OH-MY-OPENCODE (OMO) PLUGIN SETUP
# ========================================
# Note: OpenAgents agent files (openagent.md, opencoder.md) are provided
# via Dockerfile COPY step, not installed here
log_info "Installing oh-my-opencode plugin from git..."
# oh-my-opencode: OpenCode plugin from darrenhinde's fork (not published to npm)
# Using darrenhinde's fork which may include customizations for OpenAgents integration
# Install from GitHub repository
log_debug "Cloning oh-my-opencode..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "oh-my-opencode git clone" git clone --depth 1 https://github.com/darrenhinde/oh-my-opencode.git /tmp/oh-my-opencode; then
    log_error "Failed to clone oh-my-opencode (skipping oh-my-opencode installation)"
else
    cd /tmp/oh-my-opencode
    log_debug "Current directory: $(pwd)"
    log_debug "Directory contents: $(ls -la | head -20)"
    
    log_info "Building oh-my-opencode..."
    if command -v bun >/dev/null 2>&1; then
        log_debug "Using Bun for oh-my-opencode installation"
        if run_with_timeout "$BUN_OPERATIONS_TIMEOUT" "oh-my-opencode bun install" bun install; then
            if ! run_with_timeout "$BUN_OPERATIONS_TIMEOUT" "oh-my-opencode bun build" bun run build; then
                log_error "oh-my-opencode build failed"
            fi
        else
            log_error "oh-my-opencode bun install timeout, trying npm fallback"
            if run_with_timeout "$COMMAND_TIMEOUT" "oh-my-opencode npm install" npm install; then
                run_with_timeout "$COMMAND_TIMEOUT" "oh-my-opencode npm build" npm run build || log_error "npm build failed"
            else
                log_error "oh-my-opencode npm install failed"
            fi
        fi
    else
        log_debug "Using npm for oh-my-opencode installation"
        if run_with_timeout "$COMMAND_TIMEOUT" "oh-my-opencode npm install" npm install; then
            run_with_timeout "$COMMAND_TIMEOUT" "oh-my-opencode npm build" npm run build || log_error "npm build failed"
        else
            log_error "oh-my-opencode npm install failed"
        fi
    fi
    
    log_debug "Installing oh-my-opencode plugin..."
    mkdir -p $HOME/.opencode/plugin
    cp -r /tmp/oh-my-opencode $HOME/.opencode/plugin/oh-my-opencode
    cd $HOME/.opencode/plugin/oh-my-opencode
    
    log_debug "Running bun install in plugin directory..."
    if command -v bun >/dev/null 2>&1; then
        run_with_timeout "$BUN_OPERATIONS_TIMEOUT" "oh-my-opencode plugin bun install" bun install || log_error "Plugin bun install failed"
    else
        run_with_timeout "$COMMAND_TIMEOUT" "oh-my-opencode plugin npm install" npm install || log_error "Plugin npm install failed"
    fi
    cd -
    
    log_info "Installing auth plugins..."
    cd $HOME/.opencode/plugin
    if command -v bun >/dev/null 2>&1; then
        log_debug "Installing Gemini auth plugin via bun..."
        run_with_timeout "$COMMAND_TIMEOUT" "Gemini auth plugin" bun add opencode-gemini-auth@1.3.6 || log_error "Gemini auth plugin install failed"
        log_debug "Installing Codex auth plugin via bun..."
        run_with_timeout "$COMMAND_TIMEOUT" "Codex auth plugin" bun add opencode-openai-codex-auth@4.2.0 || log_error "Codex auth plugin install failed"
    else
        log_debug "Bun not available for auth plugins, skipping"
    fi
    cd -
fi

log_info "Installing Letta Code..."
# Letta Code: memory-first coding agent (https://github.com/letta-ai/letta-code)
if ! run_with_timeout "$COMMAND_TIMEOUT" "Letta Code npm install" npm install -g @letta-ai/letta-code; then
    log_error "Letta Code installation failed (continuing)"
fi

log_info "=========================================="
log_info "AI CLI Tools Installation Complete!"
log_info "=========================================="
log_info ""
log_info "Installed tools:"
log_info "  - OpenSpec"
log_info "  - Claude Code (claude) [native installer]"
log_info "  - OpenAI Codex (codex)"
log_info "  - Google Gemini (gemini)"
log_info "  - GitHub Copilot (copilot)"
log_info "  - Grok (grok)"
log_info "  - OpenCode (opencode)"
log_info "  - oh-my-opencode (darrenhinde fork with built-in agents)"
log_info "  - Letta Code (letta)"
log_info ""
log_info "Agent files (openagent.md, opencoder.md) provided via Dockerfile COPY"
log_info ""
log_info "Final system resource check:"
check_system_resources
log_info "Installation script completed at $(date '+%Y-%m-%d %H:%M:%S')"
