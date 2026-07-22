#!/bin/bash
# Shared AI CLI Installation Script
# Version: 2.0.5
#
# USER-AGNOSTIC: Runs as root, installs to system-wide paths.
# All npm globals go to /usr/local (default root prefix).
# Bun is expected at /opt/bun (set via BUN_INSTALL env in Dockerfile).
# OpenCode plugin goes to /opt/opencode.
# Claude Code goes to /usr/local/bin.
#
# Installs:
#   - OpenCode (installed from the official npm platform package)
#   - oh-my-opencode plugin (installed from the published npm package)
#     Includes built-in agents: Sisyphus, oracle, librarian, explore, frontend, etc.
#   - Auth plugins (opencode-gemini-auth, opencode-openai-codex-auth)
#   - Other AI CLIs (Codex, Gemini, Copilot, etc.)
#   - Google Antigravity CLI (agy), checksum-gated opt-in
#   - Claude Code (via native installer, not npm)
#
# Note: OpenAgents agent files (openagent.md, opencoder.md) are copied via
#       Dockerfile, not installed by this script
#
# Usage in Dockerfile:
#   COPY install-ai-clis.sh /tmp/
#   RUN bash /tmp/install-ai-clis.sh

set -e

# ========================================
# DEBUG AND TIMEOUT CONFIGURATION
# ========================================
DEBUG="${DEBUG:-1}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-300}"  # 5 minutes per general command
NPM_INSTALL_TIMEOUT="${NPM_INSTALL_TIMEOUT:-600}"  # 10 minutes for npm package installs
GIT_CLONE_TIMEOUT="${GIT_CLONE_TIMEOUT:-900}"  # 15 minutes for slow GitHub clones
RELEASE_DOWNLOAD_TIMEOUT="${RELEASE_DOWNLOAD_TIMEOUT:-3600}"  # 60 minutes for slow GitHub release assets
BUN_OPERATIONS_TIMEOUT="${BUN_OPERATIONS_TIMEOUT:-900}"  # 15 minutes for bun ops
UV_TOOL_INSTALL_TIMEOUT="${UV_TOOL_INSTALL_TIMEOUT:-3600}"  # 60 minutes for Python tool installs
INSTALL_ANTIGRAVITY_CLI="${INSTALL_ANTIGRAVITY_CLI:-0}"
ANTIGRAVITY_INSTALL_URL="${ANTIGRAVITY_INSTALL_URL:-https://antigravity.google/cli/install.sh}"
ANTIGRAVITY_INSTALL_SHA256="${ANTIGRAVITY_INSTALL_SHA256:-}"

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

ensure_system_uv_tool_paths() {
    mkdir -p "$SYSTEM_UV_TOOL_DIR" "$SYSTEM_UV_TOOL_BIN_DIR" /root/.local/share/uv
    ln -sfn "$SYSTEM_UV_TOOL_DIR" /root/.local/share/uv/tools
}

run_system_uv_tool_install() {
    local description="$1"
    shift

    ensure_system_uv_tool_paths
    run_with_timeout "$UV_TOOL_INSTALL_TIMEOUT" "$description" env \
        UV_TOOL_BIN_DIR="$SYSTEM_UV_TOOL_BIN_DIR" \
        UV_TOOL_DIR="$SYSTEM_UV_TOOL_DIR" \
        uv tool install "$@" --python-preference system
}

check_system_resources() {
    log_debug "Checking system resources..."
    log_debug "Memory: $(free -h | head -2)"
    log_debug "Disk: $(df -h / | tail -1)"
    log_debug "CPU: $(nproc) cores"
    log_debug "Available disk in /tmp: $(df -h /tmp | tail -1)"
}

resolve_claude_js_fallback_version() {
    if [ -n "${CLAUDE_CODE_JS_FALLBACK_VERSION:-}" ]; then
        printf '%s\n' "$CLAUDE_CODE_JS_FALLBACK_VERSION"
        return 0
    fi

    curl --http1.1 -fsSL --retry 2 --connect-timeout 10 --max-time 120 \
        https://registry.npmjs.org/@anthropic-ai%2fclaude-code \
        | jq -r '.versions | to_entries[] | select(.value.bin.claude == "cli.js") | .key' \
        | sort -V \
        | tail -1
}

install_claude_js_fallback() {
    local fallback_version

    fallback_version="$(resolve_claude_js_fallback_version)"
    if [ -z "$fallback_version" ]; then
        log_error "Could not resolve a JS-based Claude Code fallback version"
        return 1
    fi

    log_info "Installing Claude Code JS fallback ${fallback_version}..."
    rm -f /usr/local/bin/claude /usr/bin/claude
    hash -r || true
    run_with_timeout "$NPM_INSTALL_TIMEOUT" "Claude Code JS fallback npm install" \
        npm install -g "@anthropic-ai/claude-code@${fallback_version}"
}

ensure_claude_runnable() {
    if command -v claude >/dev/null 2>&1 && claude --version >/dev/null 2>&1; then
        log_info "Claude Code runnable check passed: $(claude --version)"
        return 0
    fi

    log_error "Claude Code native binary failed runnable check; falling back to JS package"
    if install_claude_js_fallback && command -v claude >/dev/null 2>&1 && claude --version >/dev/null 2>&1; then
        log_info "Claude Code fallback runnable check passed: $(claude --version)"
        return 0
    fi

    log_error "Claude Code fallback did not produce a runnable claude CLI"
    return 1
}

log_info "=========================================="
log_info "Installing AI CLI Tools"
log_info "=========================================="
log_info ""

check_system_resources

# ========================================
# SYSTEM PATH SETUP
# ========================================
# npm globals install to /usr/local by default when running as root
# Bun is pre-installed at /opt/bun by Dockerfile

export BUN_INSTALL="${BUN_INSTALL:-/opt/bun}"
export PATH="/opt/bun/bin:$PATH"
SYSTEM_UV_TOOL_DIR="${SYSTEM_UV_TOOL_DIR:-/opt/uv/tools}"
SYSTEM_UV_TOOL_BIN_DIR="${SYSTEM_UV_TOOL_BIN_DIR:-/usr/local/bin}"

log_debug "Verifying Bun installation"
if which bun >/dev/null 2>&1; then
    log_debug "Bun found at: $(which bun)"
    log_debug "Bun version: $(bun --version)"
else
    log_error "Bun not found in PATH (expected at /opt/bun/bin)"
fi

log_info "Installing Claude Code CLI (native installer)..."
# Native installer downloads to $HOME/.claude/downloads/ then runs 'claude install'
# which places a launcher in ~/.local/bin/. Since we run as root, we need to
# find the binary and copy it to /usr/local/bin ourselves.
# Claude installer needs more time for download, use 5 minutes
run_with_timeout "300" "Claude Code native install" bash -c 'curl -fsSL https://claude.ai/install.sh | bash' || true

# Find the claude binary wherever the installer put it and copy to /usr/local/bin
CLAUDE_BIN=""
if [ -f "$HOME/.local/bin/claude" ]; then
    CLAUDE_BIN="$HOME/.local/bin/claude"
elif ls $HOME/.claude/downloads/claude-*-linux-* 2>/dev/null; then
    # Installer downloaded but 'claude install' failed — grab the binary directly
    CLAUDE_BIN=$(ls -t $HOME/.claude/downloads/claude-*-linux-* 2>/dev/null | head -1)
fi

if [ -n "$CLAUDE_BIN" ] && [ -f "$CLAUDE_BIN" ]; then
    cp "$CLAUDE_BIN" /usr/local/bin/claude
    chmod +x /usr/local/bin/claude
    log_info "Claude Code installed to /usr/local/bin/claude"
    # Clean up downloads
    rm -rf "$HOME/.claude/downloads"
else
    log_error "Claude Code binary not found after installation (continuing)"
fi

ensure_claude_runnable || true

log_info "Installing OpenAI Codex CLI..."
if ! run_with_timeout "$NPM_INSTALL_TIMEOUT" "Codex npm install" npm install -g @openai/codex@latest; then
    log_error "Codex installation failed (continuing)"
fi

log_info "Installing Google Gemini CLI..."
if ! run_with_timeout "$NPM_INSTALL_TIMEOUT" "Gemini npm install" npm install -g @google/gemini-cli; then
    log_error "Gemini CLI installation failed (continuing)"
fi

if [ "$INSTALL_ANTIGRAVITY_CLI" = "1" ] || [ "$INSTALL_ANTIGRAVITY_CLI" = "true" ]; then
    log_info "Installing Google Antigravity CLI..."
    if [ -z "$ANTIGRAVITY_INSTALL_SHA256" ]; then
        log_error "Antigravity install requested but ANTIGRAVITY_INSTALL_SHA256 is not set (skipping)"
    else
        antigravity_installer="$(mktemp)"
        if run_with_timeout "120" "Antigravity installer download" \
            curl -fsSL "$ANTIGRAVITY_INSTALL_URL" -o "$antigravity_installer" &&
           printf '%s  %s\n' "$ANTIGRAVITY_INSTALL_SHA256" "$antigravity_installer" | sha256sum -c - >/dev/null 2>&1 &&
           run_with_timeout "300" "Antigravity CLI install" bash "$antigravity_installer" --skip-aliases --skip-path; then
            if [ -x "$HOME/.local/bin/agy" ] && [ ! -x /usr/local/bin/agy ]; then
                cp "$HOME/.local/bin/agy" /usr/local/bin/agy
                chmod +x /usr/local/bin/agy
            fi
            log_info "Antigravity CLI installed to $(command -v agy || printf '/usr/local/bin/agy')"
        else
            log_error "Antigravity CLI installation failed or checksum verification failed (continuing)"
        fi
        rm -f "$antigravity_installer"
    fi
else
    log_info "Skipping Google Antigravity CLI install; set INSTALL_ANTIGRAVITY_CLI=1 and ANTIGRAVITY_INSTALL_SHA256 to enable"
fi

log_info "Installing GitHub Copilot CLI..."
if ! run_with_timeout "$NPM_INSTALL_TIMEOUT" "GitHub Copilot npm install" npm install -g @github/copilot; then
    log_error "GitHub Copilot installation failed (continuing)"
fi

log_info "Installing Grok CLI (xAI)..."
mkdir -p /opt/grok/bin
if run_with_timeout "$COMMAND_TIMEOUT" "Grok native install" bash -o pipefail -c \
    'curl -fsSL https://x.ai/cli/install.sh | GROK_BIN_DIR=/opt/grok/bin bash'; then
    mkdir -p /opt/grok/completions
    if [ -d "$HOME/.grok/completions" ]; then
        cp -a "$HOME/.grok/completions/." /opt/grok/completions/
    fi
    chmod -R a+rX /opt/grok
    ln -sfn /opt/grok/bin/grok /usr/local/bin/grok
    if [ -x /opt/grok/bin/agent ]; then
        ln -sfn /opt/grok/bin/agent /usr/local/bin/agent
    fi
else
    log_error "Grok CLI native installation failed (continuing)"
fi

install_opencode_release() {
    local opencode_version="${OPENCODE_VERSION:-latest}"
    local opencode_arch
    local opencode_url
    local opencode_dir="/tmp/opencode-release"
    local opencode_bin

    case "$(uname -m)" in
        x86_64|amd64)
            opencode_arch="x64"
            ;;
        aarch64|arm64)
            opencode_arch="arm64"
            ;;
        *)
            log_error "Unsupported OpenCode release architecture: $(uname -m)"
            return 1
            ;;
    esac

    if [ "$opencode_version" = "latest" ]; then
        opencode_version=$(curl --http1.1 -fsSL --retry 3 --connect-timeout 10 --speed-time 20 --speed-limit 1024 --max-time 60 \
            https://registry.npmjs.org/opencode-ai/latest | jq -r '.version // empty')
    fi

    if [ -z "$opencode_version" ] || [ "$opencode_version" = "null" ]; then
        log_error "Could not resolve latest OpenCode release version"
        return 1
    fi

    opencode_url="https://registry.npmjs.org/opencode-linux-${opencode_arch}/-/opencode-linux-${opencode_arch}-${opencode_version}.tgz"
    rm -rf "$opencode_dir"
    mkdir -p "$opencode_dir"

    if ! run_with_timeout "$RELEASE_DOWNLOAD_TIMEOUT" "OpenCode release download" \
        curl --http1.1 -fsSL --retry 2 --connect-timeout 10 --speed-time 20 --speed-limit 1024 \
            -o "$opencode_dir/opencode.tgz" "$opencode_url"; then
        return 1
    fi

    if ! tar -xzf "$opencode_dir/opencode.tgz" -C "$opencode_dir"; then
        log_error "Failed to extract OpenCode npm platform archive"
        return 1
    fi

    opencode_bin=$(find "$opencode_dir" -type f -name opencode -perm /111 2>/dev/null | head -1)
    if [ -z "$opencode_bin" ] || [ ! -x "$opencode_bin" ]; then
        log_error "OpenCode binary not found in release archive"
        return 1
    fi

    install -m 0755 "$opencode_bin" /usr/local/bin/opencode
    log_info "OpenCode ${opencode_version} installed to /usr/local/bin/opencode from npm platform package"
}

build_opencode_from_source() {
    log_debug "Cloning OpenCode repository from upstream..."
    if ! run_with_timeout "$GIT_CLONE_TIMEOUT" "OpenCode git clone" git -c http.version=HTTP/1.1 clone --depth 1 --single-branch --no-tags --filter=blob:none https://github.com/anomalyco/opencode.git /tmp/opencode; then
        log_error "Failed to clone OpenCode repository"
        return 1
    fi

    cd /tmp/opencode
    log_debug "Current directory: $(pwd)"
    log_debug "Directory contents: $(ls -la | head -20)"
    
    log_info "Running bun install for OpenCode..."
    OPENCODE_BUILD_TIMEOUT=900  # 15 minutes for single-target compile
    if command -v bun >/dev/null 2>&1; then
        log_debug "Bun is available, using it for installation"
        case "$(uname -m)" in
            x86_64|amd64)
                OPENCODE_BUN_CPU="x64"
                ;;
            aarch64|arm64)
                OPENCODE_BUN_CPU="arm64"
                ;;
            armv7l|armv6l)
                OPENCODE_BUN_CPU="arm"
                ;;
            *)
                OPENCODE_BUN_CPU="$(uname -m)"
                ;;
        esac
        log_debug "Installing the OpenCode CLI and app workspaces for linux/${OPENCODE_BUN_CPU}"
        if run_with_timeout "$BUN_OPERATIONS_TIMEOUT" "OpenCode bun install" \
            bun install \
                --filter=./packages/opencode \
                --filter=./packages/app \
                --os=linux \
                --cpu="${OPENCODE_BUN_CPU}"; then
            log_info "Building OpenCode for linux/${OPENCODE_BUN_CPU}..."
            # --single builds only for the current platform instead of all 8+ targets
            if ! run_with_timeout "$OPENCODE_BUILD_TIMEOUT" "OpenCode bun build --single" bun run --cwd packages/opencode build --single; then
                log_error "OpenCode build failed"
            fi
        else
            log_error "OpenCode bun install failed (continuing)"
        fi
    else
        log_error "Bun not available, cannot build OpenCode (requires bun)"
    fi
    
    # Find the compiled binary and install it directly
    OPENCODE_BIN=$(find /tmp/opencode/packages/opencode/dist -name "opencode" -type f -executable 2>/dev/null | head -1)
    if [ -n "$OPENCODE_BIN" ] && [ -x "$OPENCODE_BIN" ]; then
        cp "$OPENCODE_BIN" /usr/local/bin/opencode
        chmod +x /usr/local/bin/opencode
        log_info "OpenCode installed to /usr/local/bin/opencode"
    else
        log_error "OpenCode binary not found after build (continuing)"
    fi
    
    cd -
}

log_info "Installing OpenCode AI..."
# OpenCode: open source AI coding agent (https://github.com/anomalyco/opencode).
# Prefer official release binaries; fall back to source build only if needed.
if ! install_opencode_release; then
    log_error "OpenCode release install failed, falling back to source build"
    build_opencode_from_source || log_error "OpenCode source build failed"
fi

# ========================================
# OH-MY-OPENCODE (OMO) PLUGIN SETUP
# ========================================
# Note: OpenAgents agent files (openagent.md, opencoder.md) are provided
# via Dockerfile COPY step, not installed here
install_oh_my_opencode_package() {
    local tmp_dir metadata version tarball_url omo_arch platform_package platform_metadata platform_tarball_url plugin_src shared_skills_src wrapper_src bin_name

    tmp_dir="$(mktemp -d)"
    log_debug "Resolving latest oh-my-opencode package metadata..."
    if ! metadata="$(curl --http1.1 -fsSL --retry 2 --connect-timeout 10 --max-time 60 https://registry.npmjs.org/oh-my-opencode/latest)"; then
        log_error "Failed to resolve oh-my-opencode npm metadata"
        rm -rf "$tmp_dir"
        return 1
    fi

    version="$(printf '%s' "$metadata" | jq -r '.version')"
    tarball_url="$(printf '%s' "$metadata" | jq -r '.dist.tarball')"
    if [ -z "$version" ] || [ "$version" = "null" ] || [ -z "$tarball_url" ] || [ "$tarball_url" = "null" ]; then
        log_error "Invalid oh-my-opencode npm metadata"
        rm -rf "$tmp_dir"
        return 1
    fi

    case "$(uname -m)" in
        x86_64|amd64)
            omo_arch="x64"
            ;;
        aarch64|arm64)
            omo_arch="arm64"
            ;;
        *)
            log_error "Unsupported oh-my-opencode architecture: $(uname -m)"
            rm -rf "$tmp_dir"
            return 1
            ;;
    esac

    platform_package="oh-my-opencode-linux-${omo_arch}"
    if ! platform_metadata="$(curl --http1.1 -fsSL --retry 2 --connect-timeout 10 --max-time 60 "https://registry.npmjs.org/${platform_package}/${version}")"; then
        log_error "Failed to resolve ${platform_package} ${version} npm metadata"
        rm -rf "$tmp_dir"
        return 1
    fi

    platform_tarball_url="$(printf '%s' "$platform_metadata" | jq -r '.dist.tarball')"
    if [ -z "$platform_tarball_url" ] || [ "$platform_tarball_url" = "null" ]; then
        log_error "Invalid ${platform_package} npm metadata"
        rm -rf "$tmp_dir"
        return 1
    fi

    log_info "Installing oh-my-opencode ${version} from npm tarballs..."
    mkdir -p "$tmp_dir/main" "$tmp_dir/platform"

    if ! run_with_timeout "$RELEASE_DOWNLOAD_TIMEOUT" "oh-my-opencode package download" curl --http1.1 -fsSL --retry 2 --connect-timeout 10 --speed-time 20 --speed-limit 1024 -o "$tmp_dir/oh-my-opencode.tgz" "$tarball_url"; then
        log_error "Failed to download oh-my-opencode package tarball"
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! run_with_timeout "$RELEASE_DOWNLOAD_TIMEOUT" "oh-my-opencode platform package download" curl --http1.1 -fsSL --retry 2 --connect-timeout 10 --speed-time 20 --speed-limit 1024 -o "$tmp_dir/oh-my-opencode-platform.tgz" "$platform_tarball_url"; then
        log_error "Failed to download ${platform_package} package tarball"
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! tar -xzf "$tmp_dir/oh-my-opencode.tgz" -C "$tmp_dir/main"; then
        log_error "Failed to extract oh-my-opencode package tarball"
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! tar -xzf "$tmp_dir/oh-my-opencode-platform.tgz" -C "$tmp_dir/platform"; then
        log_error "Failed to extract ${platform_package} package tarball"
        rm -rf "$tmp_dir"
        return 1
    fi

    plugin_src="$tmp_dir/main/package/packages/omo-codex/plugin"
    shared_skills_src="$tmp_dir/main/package/packages/shared-skills"
    wrapper_src="$tmp_dir/platform/package/bin/oh-my-opencode.js"
    if [ ! -d "$plugin_src" ] || [ ! -d "$shared_skills_src" ] || [ ! -f "$wrapper_src" ]; then
        log_error "oh-my-opencode package is missing expected plugin payload"
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf /opt/oh-my-opencode
    mkdir -p /opt/oh-my-opencode
    cp -a "$tmp_dir/main/package"/. /opt/oh-my-opencode/
    install -m 0755 "$wrapper_src" /opt/oh-my-opencode/oh-my-opencode-wrapper.js

    for bin_name in oh-my-opencode oh-my-openagent omo lazycodex lazycodex-ai; do
        cat > "/usr/local/bin/$bin_name" <<'EOF'
#!/bin/sh
export OMO_WRAPPER_PACKAGE_ROOT="${OMO_WRAPPER_PACKAGE_ROOT:-/opt/oh-my-opencode}"
export OMO_INVOCATION_NAME="${0##*/}"
exec node /opt/oh-my-opencode/oh-my-opencode-wrapper.js "$@"
EOF
        chmod 0755 "/usr/local/bin/$bin_name"
    done

    log_debug "Installing oh-my-opencode plugin payload..."
    rm -rf /opt/opencode/plugin/oh-my-opencode /opt/opencode/shared-skills
    mkdir -p /opt/opencode/plugin/oh-my-opencode /opt/opencode/shared-skills /opt/opencode/plugin/oh-my-opencode/node_modules/@oh-my-opencode
    cp -a "$plugin_src"/. /opt/opencode/plugin/oh-my-opencode/
    cp -a "$shared_skills_src"/. /opt/opencode/shared-skills/
    ln -sfn /opt/opencode/shared-skills /opt/opencode/plugin/oh-my-opencode/node_modules/@oh-my-opencode/shared-skills

    rm -rf "$tmp_dir"
}

log_info "Installing oh-my-opencode package and plugin..."
if ! install_oh_my_opencode_package; then
    log_error "Failed to install oh-my-opencode"
else
    log_info "Installing auth plugins..."
    cd /opt/opencode/plugin
    if command -v bun >/dev/null 2>&1; then
        log_debug "Installing Gemini auth plugin via bun..."
        run_with_timeout "$COMMAND_TIMEOUT" "Gemini auth plugin" bun add opencode-gemini-auth@1.4.15 || log_error "Gemini auth plugin install failed"
        log_debug "Installing Codex auth plugin via bun..."
        run_with_timeout "$COMMAND_TIMEOUT" "Codex auth plugin" bun add opencode-openai-codex-auth@4.4.0 || log_error "Codex auth plugin install failed"
    else
        log_debug "Bun not available for auth plugins, skipping"
    fi
    cd -

    # Also create symlink in /etc/skel so users get plugin dir
    mkdir -p /etc/skel/.opencode
    ln -sf /opt/opencode/plugin /etc/skel/.opencode/plugin
fi

log_info "Installing Letta Code..."
# Letta Code: memory-first coding agent (https://github.com/letta-ai/letta-code)
if ! run_with_timeout "$NPM_INSTALL_TIMEOUT" "Letta Code npm install" npm install -g @letta-ai/letta-code@latest; then
    log_error "Letta Code installation failed (continuing)"
fi

log_info "Installing NotebookLM tools..."
# notebooklm-py: Python CLI + API for NotebookLM (notebooklm command)
# Base install only — no browser deps needed in container; auth mounted from host
if run_system_uv_tool_install "notebooklm-py install" notebooklm-py; then
    log_info "notebooklm-py CLI installed (notebooklm)"
else
    log_error "notebooklm-py installation failed (continuing)"
fi

# notebooklm-mcp-cli: MCP server + nlm CLI for AI agent integration
# Auth is done on the host (requires browser); tokens mounted into container
# Install into a shared uv tools directory instead of root's home so bench
# users can execute the launchers from /usr/local/bin.
if run_system_uv_tool_install "NotebookLM MCP CLI install" notebooklm-mcp-cli; then
    log_info "NotebookLM MCP CLI installed (nlm, notebooklm-mcp)"
else
    log_error "NotebookLM MCP CLI installation failed (continuing)"
fi

log_info "=========================================="
log_info "AI CLI Tools Installation Complete!"
log_info "=========================================="
log_info ""

required_clis=(claude codex gemini copilot opencode omo letta notebooklm nlm)
missing_clis=()
for cli in "${required_clis[@]}"; do
    if ! command -v "$cli" >/dev/null 2>&1; then
        missing_clis+=("$cli")
    fi
done

if command -v claude >/dev/null 2>&1 && ! claude --version >/dev/null 2>&1; then
    missing_clis+=("claude(runnable)")
fi

if [ "${#missing_clis[@]}" -gt 0 ]; then
    log_error "Missing required AI CLIs after installation: ${missing_clis[*]}"
    exit 1
fi

log_info "Installed tools:"
log_info "  - Claude Code (claude) [native installer]"
log_info "  - OpenAI Codex (codex)"
log_info "  - Google Gemini (gemini)"
if command -v agy >/dev/null 2>&1; then
    log_info "  - Google Antigravity CLI (agy)"
else
    log_info "  - Google Antigravity CLI (agy) [checksum-gated opt-in, skipped]"
fi
log_info "  - GitHub Copilot CLI (copilot)"
if command -v grok >/dev/null 2>&1; then
    log_info "  - Grok CLI (grok)"
else
    log_info "  - Grok CLI (grok) [install skipped or failed]"
fi
log_info "  - OpenCode (opencode)"
log_info "  - oh-my-opencode (omo)"
log_info "  - Letta Code (letta)"
log_info "  - NotebookLM CLI (notebooklm) [auth via host browser]"
log_info "  - NotebookLM MCP CLI (nlm) [auth via host browser]"
log_info ""
log_info "Agent files (openagent.md, opencoder.md) provided via Dockerfile COPY"
log_info ""
log_info "Final system resource check:"
check_system_resources
log_info "Installation script completed at $(date '+%Y-%m-%d %H:%M:%S')"
