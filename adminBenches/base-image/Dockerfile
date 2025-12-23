# Layer 1b: Admin/DevOps Base Image
# Extends Layer 0 with sysadmin and DevOps tools
# User-specific build (matches host UID/GID)
# Used by ALL admin benches (cloudAdmin, etc.)

# Build arguments must be declared before FROM to use in FROM
ARG USERNAME=brett

FROM workbench-base:${USERNAME}

# Container version labels
LABEL layer="1b"
LABEL layer.name="adminbench-base"
LABEL layer.version="1.0.0"
LABEL layer.description="Admin/DevOps base with Infrastructure and Cloud tools"

# Switch to root for installation
USER root

# Build arguments
ARG USERNAME=brett

# ========================================
# SYSTEM PACKAGES FOR ADMIN TOOLS
# ========================================

# Install dependencies needed for admin/DevOps tools
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    # For unzipping tool downloads
    unzip \
    # Python for ansible and cloud CLIs
    python3 \
    python3-pip \
    # For Azure CLI
    apt-transport-https \
    lsb-release \
    gnupg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# ADMIN/DEVOPS TOOLS
# ========================================
# User is already set up in Layer 0
# Install tools as root, then switch to user

# Copy and run admin tools installation script (as root)
COPY install-admin-tools.sh /tmp/
RUN bash /tmp/install-admin-tools.sh && rm /tmp/install-admin-tools.sh

# ========================================
# ZSH SETUP FOR ADMIN
# ========================================

# Add admin tool paths to shell
RUN echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc && \
    echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc

# ========================================
# WORKSPACE SETUP
# ========================================

USER root
RUN mkdir -p /workspace && \
    chown -R $USERNAME:$USERNAME /workspace

USER $USERNAME
WORKDIR /workspace

# Default command
CMD ["sleep", "infinity"]
