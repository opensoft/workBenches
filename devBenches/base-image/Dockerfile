# Layer 1a: Developer Base Image
# Extends Layer 0 with Python, Node.js LTS, and dev tools
# AI CLIs are inherited from Layer 0 (workbench-base)
# Used by ALL developer benches (Frappe, Flutter, .NET, etc.)

# Build arguments must be declared before FROM to use in FROM
ARG USERNAME=brett

FROM workbench-base:${USERNAME}

# Container version labels
LABEL layer="1"
LABEL layer.name="devbench-base"
LABEL layer.version="1.2.0"
LABEL layer.description="Developer base with Python, Node.js LTS, and dev tools"

# Switch to root for installation
USER root

# Build arguments
ARG USERNAME=brett

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

# uv, npm-global, and AI CLIs are inherited from Layer 0 (workbench-base)

# Use a user-scoped Corepack cache to avoid runtime prompts
ENV COREPACK_HOME=/home/$USERNAME/.corepack
RUN corepack prepare "yarn@${YARN_VERSION}" --activate

# AI CLIs and OpenCode config are inherited from Layer 0

# ========================================
# ZSH SETUP
# ========================================

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
