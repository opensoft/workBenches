# Layer 1a: Developer Base Image
# Extends Layer 0 with Python, Node.js LTS, and dev tools
# AI CLIs are inherited from Layer 0 (workbench-base)
# Used by ALL developer benches (Frappe, Flutter, .NET, etc.)
# USER-AGNOSTIC: No user creation — Layer 3 handles user setup

FROM workbench-base:latest

# Container version labels
LABEL layer="1"
LABEL layer.name="dev-bench-base"
LABEL layer.version="2.2.0"
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
