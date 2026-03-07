# Layer 1b: Admin/DevOps Base Image
# Extends Layer 0 with sysadmin and DevOps tools
# Used by ALL admin benches (cloudAdmin, etc.)
# USER-AGNOSTIC: No user creation — Layer 3 handles user setup

FROM workbench-base:latest

# Container version labels
LABEL layer="1b"
LABEL layer.name="adminbench-base"
LABEL layer.version="2.0.0"
LABEL layer.description="Admin/DevOps base with Infrastructure and Cloud tools (user-agnostic)"

# Everything runs as root
USER root

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

# Copy and run admin tools installation script (as root)
COPY install-admin-tools.sh /tmp/
RUN bash /tmp/install-admin-tools.sh && rm /tmp/install-admin-tools.sh

# ========================================
# SHELL CONFIG FOR ADMIN
# ========================================

# Add admin tool paths to /etc/skel shell configs
RUN echo 'export PATH="/usr/local/bin:$PATH"' >> /etc/skel/.zshrc && \
    echo 'export PATH="/usr/local/bin:$PATH"' >> /etc/skel/.bashrc

# Default command
CMD ["sleep", "infinity"]
