# Layer 1: Developer Base Image
# Extends Layer 0 with Python, Node.js, AI CLIs
# User-specific build (matches host UID/GID)
# Used by ALL developer benches (Frappe, Flutter, .NET, etc.)

# Build arguments must be declared before FROM to use in FROM
ARG USERNAME=brett

FROM workbench-base:${USERNAME}

# Container version labels
LABEL layer="1"
LABEL layer.name="devbench-base"
LABEL layer.version="1.0.0"
LABEL layer.description="Developer base with Python, Node.js, and AI tools"

# Switch to root for installation
USER root

# Build arguments
ARG USERNAME=brett

# OpenCode plugin versions
ARG OC_OMO_VERSION=latest
ARG OC_CODEX_AUTH_VERSION=4.2.0
ARG YARN_VERSION=1.22.22

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

# ========================================
# DEVELOPER TOOLS SETUP
# ========================================
# User is already set up in Layer 0

USER $USERNAME
WORKDIR /home/$USERNAME

# Verify Python and pip
RUN python3 --version && pip --version

# Configure git credential helper
RUN git config --global credential.helper gh

# Install uv (fast Python package installer)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Configure npm for user-local global installs
RUN mkdir -p $HOME/.npm-global && \
    npm config set prefix $HOME/.npm-global

# Ensure npm globals are available for non-interactive shells
ENV NPM_CONFIG_PREFIX=/home/$USERNAME/.npm-global
ENV PATH="/home/$USERNAME/.npm-global/bin:/home/$USERNAME/.local/bin:/home/$USERNAME/.cargo/bin:${PATH}"

# Use a user-scoped Corepack cache to avoid runtime prompts
ENV COREPACK_HOME=/home/$USERNAME/.corepack
RUN corepack prepare "yarn@${YARN_VERSION}" --activate

# ========================================
# AI CLI TOOLS
# ========================================

# Copy and run AI CLI installation script
COPY --chown=$USERNAME:$USERNAME install-ai-clis.sh /tmp/
RUN bash /tmp/install-ai-clis.sh && rm /tmp/install-ai-clis.sh

# Configure OpenCode with full OMO setup
# Create user config directory structure
RUN mkdir -p /home/$USERNAME/.config/opencode/agent/core \
    && mkdir -p /home/$USERNAME/.config/opencode/context/skills

# Copy OpenCode configuration files
COPY --chown=$USERNAME:$USERNAME files/opencode/opencode.json /home/$USERNAME/.config/opencode/
COPY --chown=$USERNAME:$USERNAME files/opencode/oh-my-opencode.json /home/$USERNAME/.config/opencode/

# Copy agent files (primary agents for Tab completion)
COPY --chown=$USERNAME:$USERNAME files/opencode/agent/ /home/$USERNAME/.config/opencode/agent/

# Copy context/skills (agent skill contexts)
COPY --chown=$USERNAME:$USERNAME files/opencode/context/ /home/$USERNAME/.config/opencode/context/

# Create system-wide template for new users (needs root)
USER root
RUN mkdir -p /etc/skel/.config/opencode/agent/core \
    && mkdir -p /etc/skel/.config/opencode/context/skills
COPY --chown=root:root files/opencode/opencode.json /etc/skel/.config/opencode/
COPY --chown=root:root files/opencode/oh-my-opencode.json /etc/skel/.config/opencode/
COPY --chown=root:root files/opencode/agent/ /etc/skel/.config/opencode/agent/
COPY --chown=root:root files/opencode/context/ /etc/skel/.config/opencode/context/
USER $USERNAME

# Pre-fetch OpenCode plugins (optional, speeds up first run)
# Run a simple OpenCode command to trigger plugin installation
RUN opencode --version || echo "OpenCode plugin pre-fetch skipped (non-fatal)"

# ========================================
# ZSH SETUP
# ========================================

# Update PATH for local bins (including bun for OpenCode plugins)
RUN echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"' >> ~/.bashrc && \
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc && \
    echo 'export BUN_INSTALL="$HOME/.bun"' >> ~/.bashrc && \
    echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"' >> ~/.zshrc && \
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.zshrc && \
    echo 'export BUN_INSTALL="$HOME/.bun"' >> ~/.zshrc

# Install Oh My Zsh
RUN curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh -s -- --unattended || \
    echo "Oh My Zsh installation failed, using default zsh"

# Install Oh My Zsh plugins
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/plugins/zsh-syntax-highlighting

# Force zsh when bash is requested
RUN echo '# Force zsh when bash is requested' >> ~/.bash_profile && \
    echo 'if [ -n "$PS1" ] && [ -z "$ZSH_VERSION" ]; then' >> ~/.bash_profile && \
    echo '    exec /bin/zsh -l' >> ~/.bash_profile && \
    echo 'fi' >> ~/.bash_profile && \
    echo '' >> ~/.bash_profile && \
    echo '# Fallback: source bashrc if we somehow end up in bash' >> ~/.bash_profile && \
    echo '[ -f ~/.bashrc ] && source ~/.bashrc' >> ~/.bash_profile

# Set zsh as default shell
USER root
RUN chsh -s /bin/zsh $USERNAME

# ========================================
# WORKSPACE SETUP
# ========================================

# Create workspace directory
RUN mkdir -p /workspace && \
    chown -R $USERNAME:$USERNAME /workspace

USER $USERNAME
WORKDIR /workspace

# Default command
CMD ["sleep", "infinity"]
