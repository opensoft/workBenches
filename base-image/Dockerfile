# Layer 0: System Base Image
# Ubuntu 24.04 with system tools only
# Used by ALL benches (Frappe, Flutter, .NET, etc.)
# Build once, use everywhere

FROM ubuntu:24.04

# Container version labels
LABEL layer="0"
LABEL layer.name="workbench-base"
LABEL layer.version="1.1.0"
LABEL layer.description="System base for all workBenches"

# Switch to root for system package installation
USER root

# Build arguments for user customization
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000

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
# USER SETUP - Match host user
# ========================================

# Remove existing user/group with target UID/GID and create new user
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
    fi

# ========================================
# ZSH CONFIGURATION
# ========================================

# Install Oh-My-Zsh for the user
USER $USERNAME
WORKDIR /home/$USERNAME

RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Configure zsh with modern tools
RUN echo 'eval "$(zoxide init zsh)"' >> ~/.zshrc \
    && echo 'alias cat="batcat"' >> ~/.zshrc \
    && echo 'alias ls="ls --color=auto"' >> ~/.zshrc \
    && echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc \
    && echo 'eval "$(zoxide init bash)"' >> ~/.bashrc

# Add zoxide to default bash profile for future users
USER root
RUN echo 'eval "$(zoxide init bash)"' >> /etc/skel/.bashrc
USER $USERNAME

# Default command
CMD ["sleep", "infinity"]
