# Layer 1a: Developer Base Image
# Extends Layer 0 with Python, Node.js LTS, dev tools, and spec CLIs
# Most AI CLIs are inherited from Layer 0 (workbench-base)
# Used by ALL developer benches (Frappe, Flutter, .NET, etc.)
# USER-AGNOSTIC: No user creation — Layer 3 handles user setup

FROM workbench-base:latest

# Container version labels
LABEL layer="1"
LABEL layer.name="dev-bench-base"
LABEL layer.version="2.2.3"
LABEL layer.description="Developer base with Python, Node.js LTS, dev tools, Playwright browsers, and generic testing tools (user-agnostic)"

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

# Shared, project-agnostic Speckit worktree helpers for all developer benches.
COPY files/ct/ct-functions.zsh /usr/local/share/ct/ct-functions.zsh
RUN chmod 0644 /usr/local/share/ct/ct-functions.zsh

# Speckit worktree bootstrap. This installs a stable command outside Speckit
# itself so generated Speckit files can be refreshed and the worktree workflow
# can be reapplied afterwards.
COPY files/speckit-worktree/templates /usr/local/share/speckit-worktree/templates
COPY files/speckit-worktree/speckit-worktree-enable /usr/local/bin/speckit-worktree-enable
RUN chmod 0755 /usr/local/bin/speckit-worktree-enable && \
    find /usr/local/share/speckit-worktree/templates -type f \( -name '*.sh' -o -name '*.zsh' -o -name '*.ps1' \) -exec chmod 0755 {} + && \
    find /usr/local/share/speckit-worktree/templates -type f ! \( -name '*.sh' -o -name '*.zsh' -o -name '*.ps1' \) -exec chmod 0644 {} +

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

# SonarQube CLI is required by all devBench-derived containers. The generic
# tool installer is best-effort for many tools, so make this one explicit.
ARG SONARQUBE_CLI_VERSION=0.10.0.1266
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64) sonar_platform="linux-x86-64" ;; \
        aarch64|arm64) sonar_platform="linux-arm64" ;; \
        *) echo "Unsupported architecture for SonarQube CLI: $arch" >&2; exit 1 ;; \
    esac; \
    if ! command -v sonar >/dev/null 2>&1; then \
        curl --fail --silent --show-error --location --retry 5 --retry-delay 10 --connect-timeout 30 --max-time 900 \
            -o /usr/local/bin/sonar \
            "https://binaries.sonarsource.com/Distribution/sonarqube-cli/${SONARQUBE_CLI_VERSION}/linux/sonarqube-cli-${SONARQUBE_CLI_VERSION}-${sonar_platform}.exe"; \
        chmod 0755 /usr/local/bin/sonar; \
    fi; \
    sonar --version

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

# Install Oh My Zsh plugins into /etc/skel (oh-my-zsh itself is from Layer 0)
RUN git clone https://github.com/zsh-users/zsh-autosuggestions /etc/skel/.oh-my-zsh/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting /etc/skel/.oh-my-zsh/plugins/zsh-syntax-highlighting

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
