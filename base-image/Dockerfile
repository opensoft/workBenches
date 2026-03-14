# Layer 0: System Base Image
# Ubuntu 24.04 with system tools and AI coding CLIs
# Used by ALL benches (Frappe, Flutter, .NET, Bio, Admin, etc.)
# Build once, use everywhere
# USER-AGNOSTIC: No user creation — Layer 3 handles user setup

FROM ubuntu:24.04

# Container version labels
LABEL layer="0"
LABEL layer.name="workbench-base"
LABEL layer.version="2.0.0"
LABEL layer.description="System base with AI CLIs for all workBenches (user-agnostic)"

# Everything runs as root — no user in this layer
USER root

# ========================================
# SYSTEM PACKAGES
# ========================================

# Install core system tools
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    # Version control
    git \
    # Editors
    vim \
    neovim \
    nano \
    # Network tools
    curl \
    wget \
    iputils-ping \
    net-tools \
    # Utilities
    jq \
    ripgrep \
    fd-find \
    unzip \
    zsh \
    tmux \
    screen \
    openssh-client \
    cron \
    fzf \
    bat \
    sudo \
    # Build tools
    build-essential \
    pkg-config \
    # GPG for repository keys
    gpg \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Provide fd alias for Ubuntu's fdfind
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd

# ========================================
# GITHUB CLI
# ========================================

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages focal main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get -y install gh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# MODERN CLI UTILITIES
# ========================================

# Install yq (YAML processor)
RUN YQ_VERSION=$(curl -s https://api.github.com/repos/mikefarah/yq/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/') \
    && curl -L "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Install zoxide (smarter cd) - install to /usr/local/bin
RUN curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash -s -- --bin-dir /usr/local/bin

# Install tldr (simplified man pages) - using npm version
RUN apt-get update && apt-get install -y npm \
    && npm install -g tldr \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# UV (system-wide)
# ========================================

# Install uv to /usr/local/bin (system-wide)
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# Install spec-kit system-wide
RUN uv tool install specify-cli --from git+https://github.com/github/spec-kit.git --python-preference system \
    || echo "spec-kit installation skipped (non-fatal)"

# ========================================
# BUN RUNTIME (system-wide at /opt/bun)
# ========================================

ENV BUN_INSTALL=/opt/bun
RUN curl -fsSL https://bun.sh/install | bash \
    && chmod -R a+rx /opt/bun
ENV PATH="/opt/bun/bin:${PATH}"

# ========================================
# AI CLI TOOLS (installed as root to system paths)
# ========================================

# Copy and run AI CLI installation script
COPY install-ai-clis.sh /tmp/
RUN bash /tmp/install-ai-clis.sh && rm /tmp/install-ai-clis.sh

# ========================================
# ZSH CONFIGURATION (into /etc/skel for future users)
# ========================================

# Install Oh-My-Zsh into /etc/skel
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && mv /root/.oh-my-zsh /etc/skel/.oh-my-zsh \
    && rm -f /root/.zshrc

# Install Powerlevel10k theme
RUN git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /etc/skel/.oh-my-zsh/custom/themes/powerlevel10k

# Create /etc/skel/.zshrc template
RUN echo 'export ZSH="$HOME/.oh-my-zsh"' > /etc/skel/.zshrc && \
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> /etc/skel/.zshrc && \
    echo 'plugins=(git)' >> /etc/skel/.zshrc && \
    echo 'source $ZSH/oh-my-zsh.sh' >> /etc/skel/.zshrc && \
    echo '' >> /etc/skel/.zshrc && \
    echo '# Modern CLI tools' >> /etc/skel/.zshrc && \
    echo 'eval "$(zoxide init zsh)"' >> /etc/skel/.zshrc && \
    echo 'alias cat="batcat"' >> /etc/skel/.zshrc && \
    echo 'alias ls="ls --color=auto"' >> /etc/skel/.zshrc && \
    echo 'export PATH="$HOME/.local/bin:/opt/bun/bin:$PATH"' >> /etc/skel/.zshrc && \
    echo '' >> /etc/skel/.zshrc && \
    echo '# Powerlevel10k instant prompt' >> /etc/skel/.zshrc && \
    echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> /etc/skel/.zshrc

# Create /etc/skel/.bashrc template
RUN echo 'eval "$(zoxide init bash)"' >> /etc/skel/.bashrc && \
    echo 'export PATH="$HOME/.local/bin:/opt/bun/bin:$PATH"' >> /etc/skel/.bashrc

# ========================================
# OPENCODE CONFIGURATION (into /etc/skel)
# ========================================

RUN mkdir -p /etc/skel/.config/opencode/agent/core \
    && mkdir -p /etc/skel/.config/opencode/context/skills
COPY files/opencode/opencode.json /etc/skel/.config/opencode/
COPY files/opencode/oh-my-opencode.json /etc/skel/.config/opencode/
COPY files/opencode/agent/ /etc/skel/.config/opencode/agent/
COPY files/opencode/context/ /etc/skel/.config/opencode/context/

# ========================================
# OPSX COMMANDS & SKILLS (Claude Code, into /etc/skel)
# ========================================
# Upgraded OpenSpec workflows with agent team orchestration.
# Uses opsx-* / opsx: prefix — openspec init/update won't overwrite these.

RUN mkdir -p /etc/skel/.claude/commands/opsx \
    && mkdir -p /etc/skel/.claude/skills/opsx-clarify \
    && mkdir -p /etc/skel/.claude/skills/opsx-analyze
COPY files/claude/commands/opsx/ /etc/skel/.claude/commands/opsx/
COPY files/claude/skills/opsx-clarify/ /etc/skel/.claude/skills/opsx-clarify/
COPY files/claude/skills/opsx-analyze/ /etc/skel/.claude/skills/opsx-analyze/

# ========================================
# SPECKIT SKILLS (Claude Code, into /etc/skel)
# ========================================
# Agent-team-enhanced Speckit workflows. Each skill upgrades the corresponding
# project-level /speckit.* command with parallel specialist agents.
# Uses speckit-* prefix — speckit init/update won't overwrite these.

RUN mkdir -p /etc/skel/.claude/skills/speckit-specify \
    && mkdir -p /etc/skel/.claude/skills/speckit-clarify \
    && mkdir -p /etc/skel/.claude/skills/speckit-plan \
    && mkdir -p /etc/skel/.claude/skills/speckit-tasks \
    && mkdir -p /etc/skel/.claude/skills/speckit-analyze \
    && mkdir -p /etc/skel/.claude/skills/speckit-implement
COPY files/claude/skills/speckit-specify/ /etc/skel/.claude/skills/speckit-specify/
COPY files/claude/skills/speckit-clarify/ /etc/skel/.claude/skills/speckit-clarify/
COPY files/claude/skills/speckit-plan/ /etc/skel/.claude/skills/speckit-plan/
COPY files/claude/skills/speckit-tasks/ /etc/skel/.claude/skills/speckit-tasks/
COPY files/claude/skills/speckit-analyze/ /etc/skel/.claude/skills/speckit-analyze/
COPY files/claude/skills/speckit-implement/ /etc/skel/.claude/skills/speckit-implement/

# ========================================
# WORKSPACE DIRECTORY
# ========================================

RUN mkdir -p /workspace

# Default command
CMD ["sleep", "infinity"]
