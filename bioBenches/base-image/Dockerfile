# Layer 1c: Bioinformatics Base Image
# Extends Layer 0 with Miniconda, scientific Python, and bio libraries
# User-specific build (matches host UID/GID)
# Used by ALL bio benches (gentecBench, simBench, etc.)

# Build arguments must be declared before FROM to use in FROM
ARG USERNAME=brett

FROM workbench-base:${USERNAME}

# Container version labels
LABEL layer="1c"
LABEL layer.name="biobench-base"
LABEL layer.version="1.0.0"
LABEL layer.description="Bioinformatics base with Miniconda, scientific Python, and Jupyter"

# Switch to root for installation
USER root

# Build arguments
ARG USERNAME=brett

# ========================================
# SYSTEM LIBRARY DEPENDENCIES
# ========================================

# Libraries needed by many bioinformatics tools and native extensions
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    # HDF5 support (common bio data format)
    libhdf5-dev \
    # Compression libraries (BAM, gzipped FASTA, etc.)
    zlib1g-dev \
    libbz2-dev \
    liblzma-dev \
    # Network and parsing
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    # Build tools for compiling bio software
    cmake \
    gfortran \
    # Needed by many conda packages
    libgl1 \
    libglib2.0-0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# MINICONDA
# ========================================

ENV CONDA_DIR=/opt/conda
ENV PATH="${CONDA_DIR}/bin:${PATH}"

# Install Miniconda
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh \
    && bash /tmp/miniconda.sh -b -p ${CONDA_DIR} \
    && rm /tmp/miniconda.sh \
    && ${CONDA_DIR}/bin/conda clean -afy

# Configure channels (conda-forge + bioconda only, no defaults)
RUN conda config --system --remove channels defaults 2>/dev/null || true \
    && conda config --system --add channels bioconda \
    && conda config --system --add channels conda-forge \
    && conda config --system --set channel_priority strict

# Update conda base (using conda-forge only)
RUN conda update -n base -y -c conda-forge conda \
    && conda clean -afy

# ========================================
# CORE SCIENTIFIC PYTHON STACK
# ========================================

# Install foundational packages in the base conda environment
RUN conda install -n base -y \
    # Numerical / data fundamentals
    numpy \
    scipy \
    pandas \
    # Visualization
    matplotlib \
    seaborn \
    # Machine learning basics
    scikit-learn \
    # Core bioinformatics library
    biopython \
    # HDF5 data format
    h5py \
    && conda clean -afy

# ========================================
# JUPYTER
# ========================================

RUN conda install -n base -y \
    jupyter \
    jupyterlab \
    && conda clean -afy

# ========================================
# CONDA OWNERSHIP & USER SETUP
# ========================================

# Ensure the conda directory is owned by the user
RUN chown -R ${USERNAME}:${USERNAME} ${CONDA_DIR}

# ========================================
# SHELL INTEGRATION
# ========================================

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Initialize conda for both bash and zsh
RUN conda init bash \
    && conda init zsh

# ========================================
# WORKSPACE SETUP
# ========================================

USER root
RUN mkdir -p /workspace \
    && chown -R ${USERNAME}:${USERNAME} /workspace

USER ${USERNAME}
WORKDIR /workspace

# Default command
CMD ["sleep", "infinity"]
