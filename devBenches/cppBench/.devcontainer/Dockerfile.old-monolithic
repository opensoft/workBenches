# Heavy C++ Development Environment
# Based on Ubuntu 22.04 with comprehensive C++ toolchain
FROM ubuntu:22.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Set timezone
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Create development user
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Update and install system dependencies
RUN apt-get update && apt-get install -y \
    # Essential build tools
    build-essential \
    cmake \
    ninja-build \
    make \
    autotools-dev \
    automake \
    autoconf \
    libtool \
    pkg-config \
    # Modern C++ compilers
    gcc-12 \
    g++-12 \
    clang-15 \
    clang++-15 \
    clang-tools-15 \
    clang-tidy-15 \
    clang-format-15 \
    # LLVM tools
    llvm-15 \
    llvm-15-dev \
    # Debuggers and profilers
    gdb \
    valgrind \
    strace \
    ltrace \
    # Static analysis tools
    cppcheck \
    vera++ \
    # Documentation tools
    doxygen \
    graphviz \
    # Version control
    git \
    git-lfs \
    # Network tools
    curl \
    wget \
    # Text editors and utilities
    vim \
    nano \
    tree \
    htop \
    # Python for scripting and tools
    python3 \
    python3-pip \
    # Development libraries
    libssl-dev \
    libcurl4-openssl-dev \
    libboost-all-dev \
    libeigen3-dev \
    libgtest-dev \
    libgmock-dev \
    # Compression and archiving
    zip \
    unzip \
    tar \
    gzip \
    # Additional utilities
    jq \
    bat \
    fd-find \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Install vcpkg (C++ package manager)
RUN git clone https://github.com/Microsoft/vcpkg.git /opt/vcpkg \
    && cd /opt/vcpkg \
    && ./bootstrap-vcpkg.sh \
    && ln -s /opt/vcpkg/vcpkg /usr/local/bin/vcpkg

# Install Conan (Alternative C++ package manager)
RUN pip3 install conan

# Install additional modern C++ tools
RUN pip3 install \
    conan \
    pre-commit \
    cpplint \
    cmake-format \
    cmakelang

# Set up alternatives for compilers
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100 \
    && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-15 100 \
    && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-15 100

# Create user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && rm -rf /var/lib/apt/lists/*

# Set up development workspace
RUN mkdir -p /workspace \
    && chown -R $USERNAME:$USERNAME /workspace \
    && chmod -R 755 /workspace

# Configure git (will be overridden by user)
RUN git config --system user.name "Developer" \
    && git config --system user.email "developer@example.com" \
    && git config --system init.defaultBranch main

# Set up environment variables
ENV VCPKG_ROOT=/opt/vcpkg
ENV PATH="$VCPKG_ROOT:$PATH"
ENV CC=/usr/bin/gcc-12
ENV CXX=/usr/bin/g++-12

# Create common project directories
RUN mkdir -p /workspace/projects \
    && mkdir -p /workspace/builds \
    && mkdir -p /workspace/install \
    && mkdir -p /workspace/tests \
    && chown -R $USERNAME:$USERNAME /workspace

# Switch to development user
USER $USERNAME

# Set up user-specific configurations
RUN echo 'alias ll="ls -alF"' >> ~/.bashrc \
    && echo 'alias la="ls -A"' >> ~/.bashrc \
    && echo 'alias l="ls -CF"' >> ~/.bashrc \
    && echo 'export PATH="$PATH:/opt/vcpkg"' >> ~/.bashrc \
    && echo 'export VCPKG_ROOT=/opt/vcpkg' >> ~/.bashrc

# Set working directory
WORKDIR /workspace

# Expose common development ports
EXPOSE 8000 8080 3000 5000 9090

# Default command
CMD ["/bin/bash"]