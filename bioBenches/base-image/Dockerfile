# Layer 1: bioBench Base Image
# Extends Layer 0 with Miniconda + bioconda/conda-forge channels
# Used by ALL bio benches (geneBench, simBenches, etc.)

# Build arguments must be declared before FROM to use in FROM
ARG USERNAME=brett

FROM workbench-base:${USERNAME}

# Container version labels
LABEL layer="1"
LABEL layer.name="biobench-base"
LABEL layer.version="1.0.0"
LABEL layer.description="Bio base with Miniconda, bioconda and conda-forge channels"

USER root

# Build arguments
ARG USERNAME=brett

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
# USER SETUP
# ========================================

RUN set -eux && \
    if ! id -u "${USERNAME}" >/dev/null 2>&1; then \
        if getent passwd "1000" >/dev/null; then \
            existing_user=$(getent passwd "1000" | cut -d: -f1) && \
            userdel --force --remove $existing_user 2>/dev/null || true; \
        fi && \
        if getent group "1000" >/dev/null; then \
            existing_group=$(getent group "1000" | cut -d: -f1) && \
            groupmod -n ${USERNAME} $existing_group 2>/dev/null || true; \
        else \
            groupadd --gid 1000 "${USERNAME}" 2>/dev/null || true; \
        fi && \
        useradd --uid 1000 --gid "${USERNAME}" -m -s /bin/zsh "${USERNAME}" 2>/dev/null || true; \
    fi && \
    mkdir -p /etc/sudoers.d && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    chmod 0440 /etc/sudoers.d/${USERNAME}

# Make conda owned by user
RUN chown -R ${USERNAME}:${USERNAME} ${CONDA_DIR}

# ========================================
# SHELL CONFIGURATION
# ========================================

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Set up npm global directory
RUN mkdir -p $HOME/.npm-global \
    && npm config set prefix $HOME/.npm-global

ENV NPM_CONFIG_PREFIX=/home/${USERNAME}/.npm-global
ENV PATH="/home/${USERNAME}/.npm-global/bin:${PATH}"

# Install Node.js development tools (husky, commitlint)
RUN npm install -g \
    husky \
    @commitlint/cli \
    @commitlint/config-conventional

# Initialize conda for zsh and bash
RUN conda init zsh \
    && conda init bash

# Default command
CMD ["sleep", "infinity"]
