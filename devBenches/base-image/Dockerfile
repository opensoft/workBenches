# Layer 1a: Developer Base Image
# Extends Layer 0 with Python, Node.js LTS, and dev tools
# AI CLIs are inherited from Layer 0 (workbench-base)
# Used by ALL developer benches (Frappe, Flutter, .NET, etc.)
# USER-AGNOSTIC: No user creation — Layer 3 handles user setup

FROM workbench-base:latest

# Container version labels
LABEL layer="1"
LABEL layer.name="dev-bench-base"
LABEL layer.version="2.3.1"
LABEL layer.description="Developer base with Python, Node.js LTS, dev tools, Playwright browsers, generic testing tools, and the Omnigent meta-harness (user-agnostic)"

# Everything runs as root
USER root

ARG YARN_VERSION=1.22.22

# Shared Playwright browser cache for all dev benches.
# Using a fixed path avoids per-user installs under ~/.cache/ms-playwright.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# ========================================
# PYTHON & NODE.JS
# ========================================

# Install Python and Node.js
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    # Add nodejs repository
    && curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Enable Corepack shims (requires root for /usr/bin)
RUN corepack enable || true

# Install Python development tools
RUN pip install --break-system-packages \
    black \
    flake8 \
    isort \
    pylint \
    pytest \
    ipython

# Install Node.js development tools (husky, commitlint)
RUN npm install -g \
    husky \
    @commitlint/cli \
    @commitlint/config-conventional

# ========================================
# DEVELOPER TOOLS SETUP
# ========================================

# Verify Python and pip
RUN python3 --version && pip --version

# uv, AI CLIs are inherited from Layer 0 (workbench-base)

# ========================================
# AI META-HARNESS (OMNIGENT)
# ========================================
# Omnigent wraps the Layer 0 codex/claude CLIs behind one CLI + web UI.
# Installed as a system-wide uv tool: executables land in /usr/local/bin (on
# PATH for every user) and the tool venv under /opt/uv-tools (readable by the
# Layer 3 non-root user, not root-only /root). The published wheel bundles the
# prebuilt web UI, so no npm build runs here. Prereqs (uv, Node 22, tmux,
# bubblewrap, codex, claude) are all inherited from Layer 0.
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install --python-preference system "omnigent==0.1.1" \
    && chmod -R a+rX /opt/uv-tools \
    && omnigent --version

# Install Grok CLI with xAI's native installer if the inherited base image does
# not already provide it. Install into /opt so the later non-root user can run it
# from zsh without relying on root's ~/.grok/bin.
RUN if ! command -v grok >/dev/null 2>&1; then \
        mkdir -p /opt/grok/bin \
        && bash -o pipefail -c 'curl -fsSL https://x.ai/cli/install.sh | GROK_BIN_DIR=/opt/grok/bin bash' \
        && mkdir -p /opt/grok/completions \
        && if [ -d /root/.grok/completions ]; then cp -a /root/.grok/completions/. /opt/grok/completions/; fi \
        && chmod -R a+rX /opt/grok \
        && ln -sf /opt/grok/bin/grok /usr/local/bin/grok \
        && if [ -x /opt/grok/bin/agent ]; then ln -sf /opt/grok/bin/agent /usr/local/bin/agent; fi; \
    fi

# System-wide Corepack cache
ENV COREPACK_HOME=/opt/corepack
RUN mkdir -p /opt/corepack && \
    corepack prepare "yarn@${YARN_VERSION}" --activate

# ========================================
# GENERIC TESTING TOOLS
# ========================================

# Install tech-stack-independent testing tools (MCP servers, API testing,
# load testing, security scanning, accessibility, code quality, utilities)
# and preload Chromium into the shared Playwright cache for all dev benches.
COPY install-testing-tools.sh /tmp/
RUN bash /tmp/install-testing-tools.sh && rm -f /tmp/install-testing-tools.sh

# ========================================
# ZSH PLUGINS (into /etc/skel)
# ========================================

# Install Oh My Zsh plugins into /etc/skel (oh-my-zsh itself is from Layer 0).
# Use Ubuntu packages instead of a GitHub `git clone`: the build network may
# route github.com through a VPN tunnel whose MTU breaks TLS during the clone,
# while the apt mirror is direct and reliable. Symlink the packaged scripts
# into the layout Oh My Zsh expects (<plugin>/<plugin>.plugin.zsh).
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    zsh-autosuggestions \
    zsh-syntax-highlighting \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /etc/skel/.oh-my-zsh/plugins/zsh-autosuggestions \
               /etc/skel/.oh-my-zsh/plugins/zsh-syntax-highlighting \
    && ln -sf /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
              /etc/skel/.oh-my-zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh \
    && ln -sf /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
              /etc/skel/.oh-my-zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh

# Ensure .zshrc exists (Layer 0 should provide it, but handle missing/stale cache)
RUN if [ ! -f /etc/skel/.zshrc ]; then \
        echo 'export ZSH="$HOME/.oh-my-zsh"' > /etc/skel/.zshrc && \
        echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> /etc/skel/.zshrc && \
        echo 'plugins=(git)' >> /etc/skel/.zshrc && \
        echo 'source $ZSH/oh-my-zsh.sh' >> /etc/skel/.zshrc; \
    fi

# Update /etc/skel/.zshrc to include plugins
RUN sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' /etc/skel/.zshrc

# Make Grok available in zsh and bash shells created from /etc/skel.
RUN if ! grep -q '/opt/grok/bin' /etc/skel/.zshrc; then \
        echo '' >> /etc/skel/.zshrc && \
        echo '# Grok CLI' >> /etc/skel/.zshrc && \
        echo 'export PATH="/opt/grok/bin:$HOME/.grok/bin:$PATH"' >> /etc/skel/.zshrc && \
        echo 'if [[ -d /opt/grok/completions/zsh ]]; then fpath=(/opt/grok/completions/zsh $fpath); fi' >> /etc/skel/.zshrc && \
        echo 'autoload -Uz compinit && compinit -C' >> /etc/skel/.zshrc; \
    fi && \
    if ! grep -q '/opt/grok/bin' /etc/skel/.bashrc; then \
        echo '' >> /etc/skel/.bashrc && \
        echo '# Grok CLI' >> /etc/skel/.bashrc && \
        echo 'export PATH="/opt/grok/bin:$HOME/.grok/bin:$PATH"' >> /etc/skel/.bashrc && \
        echo '[[ -r /opt/grok/completions/bash/grok.bash ]] && source /opt/grok/completions/bash/grok.bash' >> /etc/skel/.bashrc; \
    fi

# Add bash_profile to /etc/skel (force zsh when bash is requested)
RUN echo '# Force zsh when bash is requested' > /etc/skel/.bash_profile && \
    echo 'if [ -n "$PS1" ] && [ -z "$ZSH_VERSION" ]; then' >> /etc/skel/.bash_profile && \
    echo '    exec /bin/zsh -l' >> /etc/skel/.bash_profile && \
    echo 'fi' >> /etc/skel/.bash_profile && \
    echo '' >> /etc/skel/.bash_profile && \
    echo '# Fallback: source bashrc if we somehow end up in bash' >> /etc/skel/.bash_profile && \
    echo '[ -f ~/.bashrc ] && source ~/.bashrc' >> /etc/skel/.bash_profile

# Add git credential helper to /etc/skel/.gitconfig
RUN git config --system credential.helper gh

# Default command
CMD ["sleep", "infinity"]
