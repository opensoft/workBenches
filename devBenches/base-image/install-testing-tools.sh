#!/bin/bash
# Generic Testing Tools Installation Script
# Version: 1.0.0
#
# Installs tech-stack-independent testing tools into the devbench-base image
# (Layer 1a) so all benches inherit them.
#
# NOTE: Browser binaries (Chromium) are NOT installed here.
#       Each bench's Layer 3 setup installs browsers as needed.
#
# Categories:
#   1. Browser Automation MCP Servers (npm) — no browsers, just the servers
#   2. API Testing (hurl, httpie, bruno)
#   3. Load / Performance Testing (k6, artillery, wrk)
#   4. Security / Vulnerability Scanning (semgrep, snyk)
#   5. Accessibility Testing (pa11y, axe-core)
#   6. Code Quality (shellcheck, hadolint, actionlint)
#   7. General Utilities (jq, yq, mkcert, websocat, json-server)
#   8. Contract / Mock Testing (pact, mockoon)
#
# Usage in Dockerfile:
#   COPY install-testing-tools.sh /tmp/
#   RUN bash /tmp/install-testing-tools.sh

set -e

# ========================================
# DEBUG AND TIMEOUT CONFIGURATION
# ========================================
DEBUG="${DEBUG:-1}"
COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-120}"  # 2 minutes per command

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

# Detect architecture for binary downloads
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_ALT="amd64"; ARCH_HURL="x86_64" ;;
    aarch64) ARCH_ALT="arm64"; ARCH_HURL="aarch64" ;;
    *)       ARCH_ALT="$ARCH"; ARCH_HURL="$ARCH" ;;
esac

log_info "=========================================="
log_info "Installing Generic Testing Tools"
log_info "=========================================="
log_info ""
log_info "Architecture: $ARCH ($ARCH_ALT)"
log_info ""

check_system_resources

# ========================================
# APT PACKAGES
# ========================================
log_info "Installing apt packages (jq, shellcheck, wrk)..."
if run_with_timeout "$COMMAND_TIMEOUT" "apt packages install" bash -c \
    'apt-get update && export DEBIAN_FRONTEND=noninteractive && apt-get -y install --no-install-recommends jq shellcheck wrk && apt-get clean && rm -rf /var/lib/apt/lists/*'; then
    log_info "  ✓ jq $(jq --version 2>/dev/null || echo 'installed')"
    log_info "  ✓ shellcheck $(shellcheck --version 2>/dev/null | head -2 | tail -1 || echo 'installed')"
    log_info "  ✓ wrk installed"
else
    log_error "apt packages installation failed (continuing)"
fi

# ========================================
# PIP PACKAGES
# ========================================
log_info "Installing pip packages (httpie, semgrep)..."

log_info "  Installing HTTPie..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "HTTPie pip install" pip install --break-system-packages httpie; then
    log_error "HTTPie installation failed (continuing)"
fi

log_info "  Installing Semgrep..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "Semgrep pip install" pip install --break-system-packages semgrep; then
    log_error "Semgrep installation failed (continuing)"
fi

# ========================================
# NPM GLOBAL PACKAGES
# ========================================
log_info "Installing npm global packages..."

# --- Browser Automation MCP Servers (no browsers) ---
log_info "  Installing Playwright MCP server..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "Playwright MCP npm install" npm install -g @playwright/mcp@latest; then
    log_error "Playwright MCP installation failed (continuing)"
fi

log_info "  Installing Chrome DevTools MCP server..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "Chrome DevTools MCP npm install" npm install -g chrome-devtools-mcp@latest; then
    log_error "Chrome DevTools MCP installation failed (continuing)"
fi

# --- API Testing ---
log_info "  Installing Bruno CLI..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "Bruno CLI npm install" npm install -g @usebruno/cli; then
    log_error "Bruno CLI installation failed (continuing)"
fi

# --- Load Testing ---
log_info "  Installing Artillery..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "Artillery npm install" npm install -g artillery; then
    log_error "Artillery installation failed (continuing)"
fi

# --- Security ---
log_info "  Installing Snyk CLI..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "Snyk npm install" npm install -g snyk; then
    log_error "Snyk CLI installation failed (continuing)"
fi

# --- Accessibility Testing ---
log_info "  Installing pa11y..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "pa11y npm install" npm install -g pa11y; then
    log_error "pa11y installation failed (continuing)"
fi

log_info "  Installing axe-core CLI..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "axe-core CLI npm install" npm install -g @axe-core/cli; then
    log_error "axe-core CLI installation failed (continuing)"
fi

# --- Mock / Utility ---
log_info "  Installing json-server..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "json-server npm install" npm install -g json-server; then
    log_error "json-server installation failed (continuing)"
fi

log_info "  Installing Mockoon CLI..."
if ! run_with_timeout "$COMMAND_TIMEOUT" "Mockoon CLI npm install" npm install -g @mockoon/cli; then
    log_error "Mockoon CLI installation failed (continuing)"
fi

# ========================================
# BINARY INSTALLS (from GitHub Releases)
# ========================================
log_info "Installing binary tools from GitHub releases..."

# --- Hurl (HTTP request runner) ---
log_info "  Installing Hurl..."
HURL_VERSION="6.0.0"
if run_with_timeout "$COMMAND_TIMEOUT" "Hurl download" bash -c \
    "curl -fsSL https://github.com/Orange-OpenSource/hurl/releases/download/${HURL_VERSION}/hurl-${HURL_VERSION}-${ARCH_HURL}-unknown-linux-gnu.tar.gz | tar xz -C /tmp"; then
    cp /tmp/hurl-${HURL_VERSION}-${ARCH_HURL}-unknown-linux-gnu/bin/hurl /usr/local/bin/hurl
    cp /tmp/hurl-${HURL_VERSION}-${ARCH_HURL}-unknown-linux-gnu/bin/hurlfmt /usr/local/bin/hurlfmt
    chmod +x /usr/local/bin/hurl /usr/local/bin/hurlfmt
    rm -rf /tmp/hurl-*
    log_info "  ✓ Hurl $(hurl --version 2>/dev/null || echo $HURL_VERSION)"
else
    log_error "Hurl installation failed (continuing)"
fi

# --- k6 (load testing) ---
log_info "  Installing k6..."
K6_VERSION="v0.56.0"
if run_with_timeout "$COMMAND_TIMEOUT" "k6 download" bash -c \
    "curl -fsSL https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-${ARCH_ALT}.tar.gz | tar xz -C /tmp"; then
    cp /tmp/k6-${K6_VERSION}-linux-${ARCH_ALT}/k6 /usr/local/bin/k6
    chmod +x /usr/local/bin/k6
    rm -rf /tmp/k6-*
    log_info "  ✓ k6 $(k6 version 2>/dev/null || echo $K6_VERSION)"
else
    log_error "k6 installation failed (continuing)"
fi

# --- Hadolint (Dockerfile linter) ---
log_info "  Installing Hadolint..."
HADOLINT_VERSION="v2.12.0"
HADOLINT_ARCH="$ARCH"
if run_with_timeout "$COMMAND_TIMEOUT" "Hadolint download" bash -c \
    "curl -fsSL -o /usr/local/bin/hadolint https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-${HADOLINT_ARCH}"; then
    chmod +x /usr/local/bin/hadolint
    log_info "  ✓ Hadolint $(hadolint --version 2>/dev/null || echo $HADOLINT_VERSION)"
else
    log_error "Hadolint installation failed (continuing)"
fi

# --- actionlint (GitHub Actions linter) ---
log_info "  Installing actionlint..."
ACTIONLINT_VERSION="1.7.7"
if run_with_timeout "$COMMAND_TIMEOUT" "actionlint download" bash -c \
    "curl -fsSL https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${ARCH_ALT}.tar.gz | tar xz -C /tmp actionlint"; then
    mv /tmp/actionlint /usr/local/bin/actionlint
    chmod +x /usr/local/bin/actionlint
    log_info "  ✓ actionlint $(actionlint --version 2>/dev/null | head -1 || echo $ACTIONLINT_VERSION)"
else
    log_error "actionlint installation failed (continuing)"
fi

# --- yq (YAML processor) ---
log_info "  Installing yq..."
YQ_VERSION="v4.44.6"
if run_with_timeout "$COMMAND_TIMEOUT" "yq download" bash -c \
    "curl -fsSL -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH_ALT}"; then
    chmod +x /usr/local/bin/yq
    log_info "  ✓ yq $(yq --version 2>/dev/null || echo $YQ_VERSION)"
else
    log_error "yq installation failed (continuing)"
fi

# --- mkcert (local HTTPS certs) ---
log_info "  Installing mkcert..."
MKCERT_VERSION="v1.4.4"
if run_with_timeout "$COMMAND_TIMEOUT" "mkcert download" bash -c \
    "curl -fsSL -o /usr/local/bin/mkcert https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VERSION}/mkcert-${MKCERT_VERSION}-linux-${ARCH_ALT}"; then
    chmod +x /usr/local/bin/mkcert
    log_info "  ✓ mkcert $(mkcert --version 2>/dev/null || echo $MKCERT_VERSION)"
else
    log_error "mkcert installation failed (continuing)"
fi

# --- websocat (WebSocket testing) ---
log_info "  Installing websocat..."
WEBSOCAT_VERSION="v1.13.0"
WEBSOCAT_ARCH="$ARCH"
if run_with_timeout "$COMMAND_TIMEOUT" "websocat download" bash -c \
    "curl -fsSL -o /usr/local/bin/websocat https://github.com/vi/websocat/releases/download/${WEBSOCAT_VERSION}/websocat.${WEBSOCAT_ARCH}-unknown-linux-musl"; then
    chmod +x /usr/local/bin/websocat
    log_info "  ✓ websocat $(websocat --version 2>/dev/null || echo $WEBSOCAT_VERSION)"
else
    log_error "websocat installation failed (continuing)"
fi

# --- Pact CLI (contract testing) ---
log_info "  Installing Pact CLI..."
PACT_VERSION="2.4.7"
if run_with_timeout "$COMMAND_TIMEOUT" "Pact CLI download" bash -c \
    "curl -fsSL https://github.com/pact-foundation/pact-ruby-standalone/releases/download/v${PACT_VERSION}/pact-${PACT_VERSION}-linux-${ARCH_HURL}.tar.gz | tar xz -C /opt"; then
    # Pact extracts to /opt/pact — symlink binaries
    for bin in /opt/pact/bin/*; do
        ln -sf "$bin" "/usr/local/bin/$(basename "$bin")" 2>/dev/null || true
    done
    log_info "  ✓ Pact CLI $PACT_VERSION"
else
    log_error "Pact CLI installation failed (continuing)"
fi

# ========================================
# CLEANUP
# ========================================
log_info "Cleaning up temporary files..."
rm -rf /tmp/hurl-* /tmp/k6-* /tmp/actionlint* 2>/dev/null || true

# ========================================
# SUMMARY
# ========================================
log_info ""
log_info "=========================================="
log_info "Generic Testing Tools Installation Complete!"
log_info "=========================================="
log_info ""
log_info "Installed tools:"
log_info "  Browser Automation MCP:"
log_info "    - Playwright MCP (@playwright/mcp)"
log_info "    - Chrome DevTools MCP (chrome-devtools-mcp)"
log_info "  API Testing:"
log_info "    - Hurl (hurl)"
log_info "    - HTTPie (http/https)"
log_info "    - Bruno CLI (bru)"
log_info "  Load / Performance Testing:"
log_info "    - k6"
log_info "    - Artillery (artillery)"
log_info "    - wrk"
log_info "  Security / Vulnerability Scanning:"
log_info "    - Semgrep (semgrep)"
log_info "    - Snyk CLI (snyk)"
log_info "  Accessibility Testing:"
log_info "    - pa11y"
log_info "    - axe-core CLI (axe)"
log_info "  Code Quality:"
log_info "    - ShellCheck (shellcheck)"
log_info "    - Hadolint (hadolint)"
log_info "    - actionlint"
log_info "  General Utilities:"
log_info "    - jq"
log_info "    - yq"
log_info "    - mkcert"
log_info "    - websocat"
log_info "    - json-server"
log_info "  Contract / Mock Testing:"
log_info "    - Pact CLI (pact)"
log_info "    - Mockoon CLI (mockoon-cli)"
log_info ""
log_info "NOTE: Browser binaries (Chromium) are NOT installed."
log_info "      Each bench's Layer 3 setup should run:"
log_info "        npx playwright install --with-deps chromium"
log_info ""
log_info "Final system resource check:"
check_system_resources
log_info "Installation script completed at $(date '+%Y-%m-%d %H:%M:%S')"
