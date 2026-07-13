# Layer 1a: Developer Base Image
# Extends Layer 0 with Python, Node.js LTS, dev tools, and spec CLIs
# Most AI CLIs are inherited from Layer 0 (workbench-base)
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

# Install Node.js development tools and cross-repo workflow CLIs.
RUN npm install -g \
    husky \
    @commitlint/cli \
    @commitlint/config-conventional \
    @withgraphite/graphite-cli@stable

# ========================================
# DEVELOPER TOOLS SETUP
# ========================================

# Verify Python and pip
RUN python3 --version && pip --version

# uv and most AI CLIs are inherited from Layer 0 (workbench-base)

# ========================================
# SPEC-DRIVEN DEVELOPMENT TOOLS
# ========================================

# Remove any inherited copies so Layer 1a is the clear owner of these tools.
RUN npm uninstall -g @fission-ai/openspec || true \
    && rm -f /usr/bin/openspec /usr/local/bin/openspec \
    && rm -rf /usr/lib/node_modules/@fission-ai/openspec /usr/local/lib/node_modules/@fission-ai/openspec \
    && uv tool uninstall specify-cli || true \
    && env UV_TOOL_BIN_DIR=/usr/local/bin UV_TOOL_DIR=/opt/uv/tools uv tool uninstall specify-cli || true \
    && rm -f /root/.local/bin/specify /usr/local/bin/specify \
    && rm -rf /root/.local/share/uv/tools/specify-cli /opt/uv/tools/specify-cli

# Install spec-driven CLIs only in developer benches, not every bench family.
RUN mkdir -p /opt/uv/tools /root/.local/share/uv \
    && UV_TOOL_BIN_DIR=/usr/local/bin UV_TOOL_DIR=/opt/uv/tools \
       uv tool install specify-cli --from git+https://github.com/github/spec-kit.git --python-preference system \
    && ln -sfn /opt/uv/tools /root/.local/share/uv/tools \
    || echo "spec-kit installation skipped (non-fatal)"

RUN npm install -g @fission-ai/openspec@latest \
    || echo "OpenSpec installation skipped (non-fatal)"

# Shared OpenSpec/Speckit project bootstrapper. Keep it with the spec-driven
# CLIs so every developer bench can initialize the same agent context files.
COPY files/openspeckit/setup-openspeckit /usr/local/bin/setup-openspeckit
RUN chmod 0755 /usr/local/bin/setup-openspeckit \
    && ln -sfn setup-openspeckit /usr/local/bin/setup-openspec-speckit-project

# OpenSpec Claude commands and skills live with the devBench OpenSpec CLI.
RUN mkdir -p /etc/skel/.claude/commands/opsx \
    && mkdir -p /etc/skel/.claude/skills/opsx-clarify \
    && mkdir -p /etc/skel/.claude/skills/opsx-analyze
COPY files/claude/commands/opsx/ /etc/skel/.claude/commands/opsx/
COPY files/claude/skills/opsx-clarify/ /etc/skel/.claude/skills/opsx-clarify/
COPY files/claude/skills/opsx-analyze/ /etc/skel/.claude/skills/opsx-analyze/

# Shared, project-agnostic Speckit worktree helpers for all developer benches.
COPY files/ct/ct-functions.zsh /usr/local/share/ct/ct-functions.zsh
COPY files/ct/claude/ /usr/local/share/ct/claude/
RUN chmod 0644 /usr/local/share/ct/ct-functions.zsh \
    && chmod 0755 /usr/local/share/ct/claude/speckit-dashboard.sh \
        /usr/local/share/ct/claude/speckit-dashboard-sync.sh \
        /usr/local/share/ct/claude/speckit-dash-toggle.sh \
    && chmod 0644 /usr/local/share/ct/claude/prompts/speckit-dashboard-full.md \
    && mkdir -p /etc/skel/.claude/prompts \
    && cp /usr/local/share/ct/claude/speckit-dashboard.sh /etc/skel/.claude/speckit-dashboard.sh \
    && cp /usr/local/share/ct/claude/speckit-dashboard-sync.sh /etc/skel/.claude/speckit-dashboard-sync.sh \
    && cp /usr/local/share/ct/claude/speckit-dash-toggle.sh /etc/skel/.claude/speckit-dash-toggle.sh \
    && cp /usr/local/share/ct/claude/prompts/speckit-dashboard-full.md /etc/skel/.claude/prompts/speckit-dashboard-full.md \
    && chmod 0755 /etc/skel/.claude/speckit-dashboard.sh \
        /etc/skel/.claude/speckit-dashboard-sync.sh \
        /etc/skel/.claude/speckit-dash-toggle.sh \
    && chmod 0644 /etc/skel/.claude/prompts/speckit-dashboard-full.md

# Speckit worktree bootstrap. This installs a stable command outside Speckit
# itself so generated Speckit files can be refreshed and the worktree workflow
# can be reapplied afterwards.
COPY files/speckit-worktree/templates /usr/local/share/speckit-worktree/templates
COPY files/speckit-worktree/speckit-worktree-enable /usr/local/bin/speckit-worktree-enable
RUN chmod 0755 /usr/local/bin/speckit-worktree-enable && \
    find /usr/local/share/speckit-worktree/templates -type f \( -name '*.sh' -o -name '*.zsh' -o -name '*.ps1' \) -exec chmod 0755 {} + && \
    find /usr/local/share/speckit-worktree/templates -type f ! \( -name '*.sh' -o -name '*.zsh' -o -name '*.ps1' \) -exec chmod 0644 {} +

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

# Container-safe SonarQube/SonarCloud environment. These helpers make auth
# usable without libsecret.
COPY files/sonarqube/sonarqube-cli-env.sh /usr/local/share/sonarqube/sonarqube-cli-env.sh
COPY files/sonarqube/sonar-env /usr/local/bin/sonar-env
RUN chmod 0644 /usr/local/share/sonarqube/sonarqube-cli-env.sh \
    && chmod 0755 /usr/local/bin/sonar-env \
    && ln -sfn /usr/local/share/sonarqube/sonarqube-cli-env.sh /etc/profile.d/sonarqube-cli.sh

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

# Source Speckit worktree helpers from global shell startup so they remain
# available even when benches mount a host ~/.zshrc over the generated one.
RUN printf '\n# DevBench Speckit worktree helpers\n[[ -f /usr/local/share/ct/ct-functions.zsh ]] && source /usr/local/share/ct/ct-functions.zsh\n' >> /etc/zsh/zshrc && \
    printf '\n# DevBench Speckit worktree helpers\n[ -f /usr/local/share/ct/ct-functions.zsh ] && . /usr/local/share/ct/ct-functions.zsh\n' >> /etc/bash.bashrc

# Source SonarQube CLI env defaults from global interactive shell startup.
RUN printf '\n# DevBench SonarQube CLI environment\n[ -f /usr/local/share/sonarqube/sonarqube-cli-env.sh ] && . /usr/local/share/sonarqube/sonarqube-cli-env.sh\n' >> /etc/zsh/zshrc && \
    printf '\n# DevBench SonarQube CLI environment\n[ -f /usr/local/share/sonarqube/sonarqube-cli-env.sh ] && . /usr/local/share/sonarqube/sonarqube-cli-env.sh\n' >> /etc/bash.bashrc

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
