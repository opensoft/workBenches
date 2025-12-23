# Layer 0: System Base Image
# Ubuntu 24.04 with system tools only
# Used by ALL benches (Frappe, Flutter, .NET, etc.)
# Build once, use everywhere

FROM ubuntu:24.04

# Container version labels
LABEL layer="0"
LABEL layer.name="workbench-base"
LABEL layer.version="1.0.0"
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
    nano \
    # Network tools
    curl \
    wget \
    iputils-ping \
    net-tools \
    # Utilities
    jq \
    zsh \
    screen \
    openssh-client \
    cron \
    # Build tools
    build-essential \
    pkg-config \
    # GPG for repository keys
    gpg \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# GITHUB CLI
# ========================================

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages focal main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get -y install gh \
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
        useradd --uid $USER_UID --gid $USERNAME -m -s /bin/bash $USERNAME 2>/dev/null || true; \
    fi

USER $USERNAME
WORKDIR /home/$USERNAME

# Default command
CMD ["sleep", "infinity"]
