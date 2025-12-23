FROM ubuntu:24.04

# Container version labels for runtime identification
LABEL devcontainer.version="1.0.0"
LABEL devcontainer.template="bench-devcontainer-1.0.0"
LABEL devcontainer.description="Generic Bench Development Container"
LABEL devcontainer.created="2025-12-21T00:00:00Z"

# Switch to root to install system packages
USER root


# ========================================
# ROOT USER: TOOLING SETUP - System-wide development tools
# ========================================

# ROOT: Installing additional development tools (git, vim, nano, curl, wget, jq, networking tools, sudo, zsh, screen)
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    git \
    vim \
    nano \
    curl \
    wget \
    jq \
    iputils-ping \
    net-tools \
    sudo \
    zsh \
    screen \
    python3 \
    python3-pip \
python3-dev \
    python3-venv \
    openssh-client \
    cron \
    build-essential \
    mariadb-client \
    libmysqlclient-dev \
    libssl-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ROOT: Installing GPG for repository key management
RUN apt-get update && apt-get install -y gpg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ROOT: Installing GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages focal main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get -y install gh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ROOT: Installing Node.js LTS version
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
&& rm -rf /var/lib/apt/lists/*

# ROOT: Installing Python development tools (black, flake8, isort, pylint, pytest, ipython)
RUN pip install --break-system-packages \
    black \
    flake8 \
    isort \
    pylint \
    pytest \
    ipython

# ROOT: Enable corepack and activate Yarn (preferred)
RUN corepack enable && corepack prepare yarn@stable --activate || true


# ========================================
# ROOT USER: USER SETUP - Match host UID/GID
# ========================================

# Switching back to ROOT for user management
USER root

# Build arguments for user management
# These are passed from docker-compose.yml and match the host user
ARG USERNAME
ARG USER_UID
ARG USER_GID

# Remove any existing user/group with the target UID/GID and create new user
# This ensures we match the host user exactly, replacing the default 'frappe' user
RUN set -eux && \
    # Remove existing user with target UID if exists
    if getent passwd "$USER_UID" >/dev/null; then \
    existing_user=$(getent passwd "$USER_UID" | cut -d: -f1) && \
    userdel --force --remove $existing_user 2>/dev/null || true; \
    fi && \
    # Handle existing group with target GID
    if getent group "$USER_GID" >/dev/null; then \
    existing_group=$(getent group "$USER_GID" | cut -d: -f1) && \
    groupmod -n $USERNAME $existing_group 2>/dev/null || true; \
    else \
    groupadd --gid $USER_GID $USERNAME 2>/dev/null || true; \
    fi && \
    # Create new user if it doesn't exist
    if ! getent passwd "$USERNAME" >/dev/null; then \
    useradd --uid $USER_UID --gid $USERNAME -m -s /bin/zsh $USERNAME 2>/dev/null || true; \
    fi && \
    echo $USERNAME ALL=\(ALL\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME && \
    chmod 0440 /etc/sudoers.d/$USERNAME



# ========================================
# USERNAME USER: Verification of System Tools
# ========================================

# Switching to USERNAME for user-specific step
USER $USERNAME

# USERNAME: Verifying Python and pip installations
RUN python3 --version && pip --version


# ========================================
# USERNAME USER: Setup Credential Helper
# ========================================

# USERNAME: Configuring git to use gh CLI for credentials
RUN git config --global credential.helper gh



# ========================================
# USERNAME USER: AI SETUP - AI Tools, Spec-Kit, OpenSpec, Codex, Gemini, and Copilot
# ========================================

# USERNAME: Installing uv (fast Python package installer) to ~/.local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# USERNAME: Configuring npm to use user-local directory for global installs
RUN mkdir -p $HOME/.npm-global && \
    npm config set prefix $HOME/.npm-global

# USERNAME: Installing AI CLI tools from shared script
# This maintains a single source of truth for AI CLI installations across all bench types
# See: devcontainer-shared/install-ai-clis.sh for the full list of tools
COPY --chown=$USERNAME:$USERNAME ../devcontainer-shared/install-ai-clis.sh /tmp/
RUN bash /tmp/install-ai-clis.sh && rm /tmp/install-ai-clis.sh



# ========================================
# USERNAME USER: ZSH SETUP - Oh My Zsh and shell configuration
# ========================================

# USERNAME: Updating PATH for local bins in user's shell configs
RUN echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> ~/.bashrc && \
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc && \
    echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> ~/.zshrc && \
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.zshrc

# USERNAME: Installing Oh My Zsh for better developer experience
RUN curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh -s -- --unattended || \
    echo "Oh My Zsh installation failed, using default zsh"

# Install Oh My Zsh plugins
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/plugins/zsh-syntax-highlighting

# Override bash profile to run zsh instead of bash
RUN echo '# Force zsh when bash is requested' >> ~/.bash_profile && \
    echo 'if [ -n "$PS1" ] && [ -z "$ZSH_VERSION" ]; then' >> ~/.bash_profile && \
    echo '    exec /bin/zsh -l' >> ~/.bash_profile && \
    echo 'fi' >> ~/.bash_profile && \
    echo '' >> ~/.bash_profile && \
    echo '# Fallback: source bashrc if we somehow end up in bash' >> ~/.bash_profile && \
    echo '[ -f ~/.bashrc ] && source ~/.bashrc' >> ~/.bash_profile

# Safety command: Ensure the user shell is set to zsh
USER root
RUN chsh -s /bin/zsh $USERNAME



# ========================================
# USERNAME USER: WORKSPACE SETUP - Creating development workspace
# ========================================

# Create workspace directories with proper ownership
RUN mkdir -p /workspace/development && \
    chown -R $USERNAME:$USERNAME /workspace

# Switch back to user
USER $USERNAME

# Set working directory
WORKDIR /workspace

# Default command
CMD ["sleep", "infinity"]
