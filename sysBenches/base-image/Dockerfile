# Layer 1b: Sys/DevOps Base Image
# Extends Layer 0 with sysadmin and DevOps tools
# Used by ALL sys benches (cloudBench, opsBench, etc.)
# USER-AGNOSTIC: No user creation — Layer 3 handles user setup

FROM workbench-base:latest

# Container version labels
LABEL layer="1b"
LABEL layer.name="sys-bench-base"
LABEL layer.version="2.0.0"
LABEL layer.description="Sys/DevOps base with infrastructure and cloud tools (user-agnostic)"

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
    # Network diagnostics
    nmap \
    dnsutils \
    netcat-openbsd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# ADMIN/DEVOPS TOOLS
# ========================================

# Copy and run admin tools installation script (as root)
COPY install-admin-tools.sh /tmp/
RUN bash /tmp/install-admin-tools.sh && rm /tmp/install-admin-tools.sh

# Sys benches inherit AI CLIs from Layer 0. Fail fast here if the base layer
# is stale so downstream benches do not build without the expected tools.
RUN command -v claude >/dev/null \
    && command -v codex >/dev/null \
    && command -v gemini >/dev/null \
    && command -v opencode >/dev/null \
    || (echo "Missing inherited AI CLIs from workbench-base:latest. Rebuild Layer 0, then rebuild sys-bench-base." >&2 && exit 1)

# ========================================
# SHELL CONFIG FOR ADMIN
# ========================================

# Add admin tool paths to /etc/skel shell configs
RUN echo 'export PATH="/usr/local/bin:$PATH"' >> /etc/skel/.zshrc && \
    echo 'export PATH="/usr/local/bin:$PATH"' >> /etc/skel/.bashrc

# Default command
CMD ["sleep", "infinity"]
