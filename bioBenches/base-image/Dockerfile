# Layer 1c: bioBench Base Image
# Extends Layer 0 with Miniconda + bioconda/conda-forge channels
# Used by ALL bio benches (geneBench, simBenches, etc.)
# USER-AGNOSTIC: No user creation — Layer 3 handles user setup

FROM workbench-base:latest

# Container version labels
LABEL layer="1c"
LABEL layer.name="biobench-base"
LABEL layer.version="2.0.0"
LABEL layer.description="Bio base with Miniconda, bioconda and conda-forge channels (user-agnostic)"

# Everything runs as root
USER root

# ========================================
# SYSTEM DEPENDENCIES
# ========================================

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    sudo \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# NODE.JS (for husky/commitlint)
# ========================================

RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Enable Corepack
RUN corepack enable || true

# Install Node.js development tools (husky, commitlint)
RUN npm install -g \
    husky \
    @commitlint/cli \
    @commitlint/config-conventional

# ========================================
# MINICONDA
# ========================================

ENV CONDA_DIR=/opt/conda

RUN curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/miniconda.sh \
    && bash /tmp/miniconda.sh -b -p ${CONDA_DIR} \
    && rm /tmp/miniconda.sh \
    && ${CONDA_DIR}/bin/conda clean -afy

ENV PATH="${CONDA_DIR}/bin:${PATH}"

# Accept ToS and configure channels for bioinformatics
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r \
    && conda config --system --prepend channels conda-forge \
    && conda config --system --prepend channels bioconda \
    && conda config --system --set channel_priority strict

# ========================================
# SHELL CONFIGURATION (into /etc/skel)
# ========================================

# Initialize conda for zsh and bash in /etc/skel
RUN conda init --system zsh && conda init --system bash

# Default command
CMD ["sleep", "infinity"]
