# THE BIG HEAVY FLUTTER DEVELOPMENT MONSTER - Ubuntu 24.04 Edition
FROM ubuntu:24.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

USER root

# Accept build arguments for username, UID, and GID from docker-compose
ARG USERNAME
ARG USER_UID
ARG USER_GID
ARG DEBUG=false

# Set DEBUG as an environment variable for runtime
ENV DEBUG=${DEBUG}

# In debug mode, show these values
RUN if [ "$DEBUG" = "true" ]; then \
        echo "🚀 THE BIG HEAVY FLUTTER DEVELOPMENT MONSTER"; \
        echo "the passed arg USERNAME= ${USERNAME}"; \
        echo "the passed arg USER_UID= ${USER_UID}"; \
        echo "the passed arg USER_GID= ${USER_GID}"; \
        echo "the passed env DEBUG= ${DEBUG}"; \
    fi

# Always log the resolved values for debugging
RUN echo "Resolved USERNAME=${USERNAME}, USER_UID=${USER_UID}, USER_GID=${USER_GID}, DEBUG=${DEBUG}"

# ========================================
# PHASE 1: SYSTEM FOUNDATION & REPOSITORIES
# ========================================

# Update and install essential system packages
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    curl \
    wget \
    gpg \
    && rm -rf /var/lib/apt/lists/*

# Add Microsoft repository for .NET
RUN wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb

# Add Node.js 20.x repository
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash -

# Add Docker repository
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Add Kubernetes repository
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg \
    && echo 'deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

# Add Azure CLI repository
RUN curl -sLS https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null \
    && echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/azure-cli.list

# Add PostgreSQL repository for latest version
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" | tee /etc/apt/sources.list.d/postgresql.list

# ========================================
# PHASE 2: THE MONSTER PACKAGE INSTALLATION (SPLIT INTO CHUNKS)
# ========================================

# Phase 2a: Core development tools
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    autoconf \
    automake \
    libtool \
    make \
    gcc \
    g++ \
    gdb \
    valgrind \
    clang \
    llvm \
    && rm -rf /var/lib/apt/lists/*

# Phase 2b: .NET SDK and runtime (for polyglot development)
RUN apt-get update && apt-get install -y \
    dotnet-sdk-8.0 \
    dotnet-runtime-8.0 \
    aspnetcore-runtime-8.0 \
    && rm -rf /var/lib/apt/lists/*

# Phase 2b2: Flutter/Android prerequisites
RUN apt-get update && apt-get install -y \
    libglu1-mesa \
    android-tools-adb \
    android-tools-fastboot \
    && rm -rf /var/lib/apt/lists/*

# Phase 2c: Node.js from NodeSource (includes npm)
RUN apt-get update && apt-get install -y \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

# Phase 2c2: Other languages and runtimes
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    golang-go \
    ruby \
    ruby-dev \
    && rm -rf /var/lib/apt/lists/*

# Phase 2d: Java JDK (for Android development)
RUN apt-get update && apt-get install -y \
    openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*

# Phase 2d2: Android SDK installation
RUN mkdir -p /opt/android-sdk \
    && wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/cmdtools.zip \
    && unzip -q /tmp/cmdtools.zip -d /opt/android-sdk \
    && rm /tmp/cmdtools.zip \
    && mv /opt/android-sdk/cmdline-tools /opt/android-sdk/cmdline-tools-temp \
    && mkdir -p /opt/android-sdk/cmdline-tools/latest \
    && mv /opt/android-sdk/cmdline-tools-temp/* /opt/android-sdk/cmdline-tools/latest/ \
    && rmdir /opt/android-sdk/cmdline-tools-temp \
    && chown -R root:root /opt/android-sdk \
    && chmod -R 755 /opt/android-sdk

# Set Android SDK environment variables
ENV ANDROID_HOME="/opt/android-sdk"
ENV ANDROID_SDK_ROOT="/opt/android-sdk"
ENV PATH="$PATH:/opt/android-sdk/platform-tools:/opt/android-sdk/emulator:/opt/android-sdk/cmdline-tools/latest/bin"

# Install essential Android SDK components
RUN yes | /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --licenses \
    && /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager \
    "platform-tools" \
    "emulator" \
    "cmake;3.22.1" \
    "ndk;27.0.12077973" \
    "build-tools;33.0.0" \
    "build-tools;34.0.0" \
    "platforms;android-30" \
    "platforms;android-31" \
    "platforms;android-32" \
    "platforms;android-33" \
    "platforms;android-34" \
    "platforms;android-35" \
    "platforms;android-36" \
    "system-images;android-34;google_apis;x86_64" \
    && chmod -R 755 /opt/android-sdk

# Phase 2e: Shell and terminal tools
RUN apt-get update && apt-get install -y \
    zsh \
    fish \
    tmux \
    screen \
    htop \
    neofetch \
    tree \
    && rm -rf /var/lib/apt/lists/*

# Phase 2f: Text editors and processing tools
RUN apt-get update && apt-get install -y \
    vim \
    neovim \
    nano \
    emacs-nox \
    jq \
    xmlstarlet \
    ripgrep \
    fd-find \
    fzf \
    bat \
    && rm -rf /var/lib/apt/lists/*

# Phase 2g: Network tools
RUN apt-get update && apt-get install -y \
    net-tools \
    nmap \
    netcat-openbsd \
    telnet \
    dnsutils \
    traceroute \
    httpie \
    && rm -rf /var/lib/apt/lists/*

# Phase 2h: Archive tools
RUN apt-get update && apt-get install -y \
    unzip \
    zip \
    p7zip-full \
    tar \
    gzip \
    bzip2 \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Phase 2i: Version control
RUN apt-get update && apt-get install -y \
    git \
    git-lfs \
    subversion \
    mercurial \
    && rm -rf /var/lib/apt/lists/*

# Phase 2j: Database clients
RUN apt-get update && apt-get install -y \
    postgresql-client \
    mysql-client \
    sqlite3 \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

# Phase 2k: Docker and container tools
RUN apt-get update && apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Phase 2l: Cloud tools
RUN apt-get update && apt-get install -y \
    kubectl \
    azure-cli \
    && rm -rf /var/lib/apt/lists/*

# Phase 2m: Security and SSH tools
RUN apt-get update && apt-get install -y \
    gnupg2 \
    pass \
    openssh-client \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Phase 2n: System utilities (more, which, and stat are built-in coreutils)
RUN apt-get update && apt-get install -y \
    sudo \
    less \
    rsync \
    lsof \
    strace \
    ltrace \
    file \
    plocate \
    && rm -rf /var/lib/apt/lists/*

# Phase 2o: Media tools
RUN apt-get update && apt-get install -y \
    imagemagick \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Phase 2p: Documentation tools
RUN apt-get update && apt-get install -y \
    pandoc \
    texlive-latex-base \
    texlive-latex-extra \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# PHASE 2.5: MODERN ALTERNATIVES (MANUAL INSTALLS)
# ========================================

# Install btop (newer htop alternative)
RUN apt-get update && apt-get install -y btop || echo "btop not available in repos, skipping" \
    && rm -rf /var/lib/apt/lists/*

# Install exa (modern ls alternative) 
RUN apt-get update && apt-get install -y exa || echo "exa not available in repos, skipping" \
    && rm -rf /var/lib/apt/lists/*

# Install yq (YAML processor)
RUN apt-get update && apt-get install -y yq || echo "yq not available in repos, skipping" \
    && rm -rf /var/lib/apt/lists/*

# Install tcpdump, wireshark tools (may need special handling)
RUN apt-get update && apt-get install -y tcpdump wireshark-common tshark || echo "Some network tools not available, skipping" \
    && rm -rf /var/lib/apt/lists/*

# Install starship (modern shell prompt) with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://starship.rs/install.sh | sh -s -- -y) || \
    (echo "⚠️  Starship script failed, using direct download fallback..." && \
     STARSHIP_VERSION="1.16.0" && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-x86_64-unknown-linux-gnu.tar.gz | tar -xzC /tmp && \
     mv /tmp/starship /usr/local/bin/ && \
     chmod +x /usr/local/bin/starship) || \
    echo "❌ Starship installation failed completely, skipping..."

# Install zoxide (smart cd command) with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash) || \
    (echo "⚠️  Zoxide script failed, using direct download fallback..." && \
     ZOXIDE_VERSION="0.9.2" && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz | tar -xzC /tmp && \
     mv /tmp/zoxide /usr/local/bin/ && \
     chmod +x /usr/local/bin/zoxide) || \
    echo "❌ Zoxide installation failed completely, skipping..."

# ========================================
# PHASE 3: USER MANAGEMENT (Your Special Sauce)
# ========================================

# Remove container image user and group if they conflict with the host user
RUN if grep -q ":${USER_UID}:" /etc/passwd; then \
      userdel --force -r $(grep ":${USER_UID}:" /etc/passwd | cut -d: -f1); \
    fi && \
    if [ "$DEBUG" = "true" ]; then \
        echo "User with UID ${USER_UID} deleted if it existed."; \
    fi && \
    if grep -q ":${USER_GID}:" /etc/group; then \
      groupdel $(grep ":${USER_GID}:" /etc/group | cut -d: -f1); \
    fi && \
    if [ "$DEBUG" = "true" ]; then \
        echo "Group with GID ${USER_GID} deleted if it existed."; \
    fi

# Create the user and group to match the host user
RUN set -eux && \
    if [ "$DEBUG" = "true" ]; then \
        echo "Creating group if it does not exist..."; \
    fi && \
    if ! getent group "${USER_GID}" >/dev/null; then \
        groupadd --gid "${USER_GID}" "${USERNAME}" || (echo "Error: Failed to create group with GID ${USER_GID}" && exit 1); \
    else \
        if [ "$DEBUG" = "true" ]; then \
            echo "Group with GID ${USER_GID} already exists."; \
        fi; \
    fi && \
    if [ "$DEBUG" = "true" ]; then \
        echo "Creating user if it does not exist..."; \
    fi && \
    if ! id -u "${USERNAME}" >/dev/null 2>&1; then \
        useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/zsh "${USERNAME}" || (echo "Error: Failed to create user ${USERNAME} with UID ${USER_UID} and GID ${USER_GID}" && exit 1); \
    else \
        if [ "$DEBUG" = "true" ]; then \
            echo "User ${USERNAME} already exists."; \
        fi; \
    fi && \
    if [ "$DEBUG" = "true" ]; then \
        echo "Adding user to important groups..."; \
    fi && \
    usermod -aG sudo,docker,www-data "${USERNAME}" && \
    SUDO_FILE="/etc/sudoers.d/${USERNAME}" && \
    SUDO_LINE="${USERNAME} ALL=(ALL) NOPASSWD:ALL" && \
    touch "${SUDO_FILE}" && \
    grep -qF -- "${SUDO_LINE}" "${SUDO_FILE}" || echo "${SUDO_LINE}" >> "${SUDO_FILE}" && \
    chmod 0440 "${SUDO_FILE}" && \
    if [ "$DEBUG" = "true" ]; then \
        echo "Verifying user creation..."; \
    fi && \
    getent passwd "${USERNAME}" || (echo "Error: User ${USERNAME} was not created!" && exit 1)

# ========================================
# PHASE 4: EXTERNAL TOOL INSTALLATIONS
# ========================================

# Rust removed - belongs in C++/systems programming container

# Install Bun (fast JavaScript runtime) with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://bun.sh/install | bash && \
    mv /root/.bun/bin/bun /usr/local/bin/) || \
    (echo "⚠️  Bun script failed, using direct download fallback..." && \
     BUN_VERSION="1.0.11" && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-x64.zip -o bun.zip && \
     unzip bun.zip && mv bun-linux-x64/bun /usr/local/bin/ && rm -rf bun.zip bun-linux-x64 && \
     chmod +x /usr/local/bin/bun) || \
    echo "❌ Bun installation failed completely, skipping..."

# Install Deno with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://deno.land/x/install/install.sh | sh && \
    mv /root/.deno/bin/deno /usr/local/bin/) || \
    (echo "⚠️  Deno script failed, using direct download fallback..." && \
     DENO_VERSION="1.38.3" && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-x86_64-unknown-linux-gnu.zip -o deno.zip && \
     unzip deno.zip && mv deno /usr/local/bin/ && rm deno.zip && \
     chmod +x /usr/local/bin/deno) || \
    echo "❌ Deno installation failed completely, skipping..."

# Install GitHub CLI with fallback
RUN (curl -fsSL --retry 3 --retry-delay 2 --user-agent "Mozilla/5.0" \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install gh -y) || \
    (echo "⚠️  GitHub CLI repo failed (rate limit/network), using direct download fallback..." && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://github.com/cli/cli/releases/latest/download/gh_linux_amd64.tar.gz | tar -xzC /tmp && \
     mv /tmp/gh_*/bin/gh /usr/local/bin/ && \
     chmod +x /usr/local/bin/gh) || \
    echo "❌ GitHub CLI installation failed completely, skipping..." \
    && rm -rf /var/lib/apt/lists/*

# Install Helm with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash) || \
    (echo "⚠️  Helm script failed, using direct download fallback..." && \
     HELM_VERSION="3.13.0" && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz | tar -xzC /tmp && \
     mv /tmp/linux-amd64/helm /usr/local/bin/ && \
     chmod +x /usr/local/bin/helm) || \
    echo "❌ Helm installation failed completely, skipping..."

# Install Terraform with fallback
RUN (curl -fsSL --retry 3 --retry-delay 2 --user-agent "Mozilla/5.0" \
    https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install terraform -y) || \
    (echo "⚠️  Terraform repo failed, using direct download fallback..." && \
     TERRAFORM_VERSION="1.6.0" && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o terraform.zip && \
     unzip terraform.zip && mv terraform /usr/local/bin/ && rm terraform.zip && \
     chmod +x /usr/local/bin/terraform) || \
    echo "❌ Terraform installation failed completely, skipping..." \
    && rm -rf /var/lib/apt/lists/*

# Install Pulumi with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://get.pulumi.com | sh && \
    mv /root/.pulumi/bin/pulumi /usr/local/bin/) || \
    (echo "⚠️  Pulumi script failed, using direct download fallback..." && \
     PULUMI_VERSION="3.92.0" && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://github.com/pulumi/pulumi/releases/download/v${PULUMI_VERSION}/pulumi-v${PULUMI_VERSION}-linux-x64.tar.gz | tar -xzC /tmp && \
     mv /tmp/pulumi/pulumi /usr/local/bin/ && \
     chmod +x /usr/local/bin/pulumi) || \
    echo "❌ Pulumi installation failed completely, skipping..."

# Install Dapr CLI with fallback
RUN (wget -q --retry-connrefused --tries=3 --user-agent="Mozilla/5.0" \
    https://raw.githubusercontent.com/dapr/cli/master/install/install.sh -O - | /bin/bash) || \
    (echo "⚠️  Dapr script failed, using direct download fallback..." && \
     DAPR_VERSION="1.12.0" && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://github.com/dapr/cli/releases/download/v${DAPR_VERSION}/dapr_linux_amd64.tar.gz | tar -xzC /tmp && \
     mv /tmp/dapr /usr/local/bin/ && \
     chmod +x /usr/local/bin/dapr) || \
    echo "❌ Dapr CLI installation failed completely, skipping..."

# Install Tilt (for Kubernetes development) with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash) || \
    (echo "⚠️  Tilt script failed, using direct download fallback..." && \
     TILT_VERSION="0.33.6" && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://github.com/tilt-dev/tilt/releases/download/v${TILT_VERSION}/tilt.${TILT_VERSION}.linux.x86_64.tar.gz | tar -xzC /tmp && \
     mv /tmp/tilt /usr/local/bin/ && \
     chmod +x /usr/local/bin/tilt) || \
    echo "❌ Tilt installation failed completely, skipping..."

# Install k6 (load testing) with fallback
RUN (gpg -k \
    && gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 \
    && echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | tee /etc/apt/sources.list.d/k6.list \
    && apt-get update && apt-get install k6 -y) || \
    (echo "⚠️  k6 repo failed, using direct download fallback..." && \
     K6_VERSION="0.46.0" && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://github.com/grafana/k6/releases/download/v${K6_VERSION}/k6-v${K6_VERSION}-linux-amd64.tar.gz | tar -xzC /tmp && \
     mv /tmp/k6-v${K6_VERSION}-linux-amd64/k6 /usr/local/bin/ && \
     chmod +x /usr/local/bin/k6) || \
    echo "❌ k6 installation failed completely, skipping..." \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# PHASE 5: USER-SPECIFIC INSTALLATIONS
# ========================================

# Switch to user for user-specific installations
USER ${USERNAME}

# Set up home directory
WORKDIR /home/${USERNAME}

# Install Oh My Zsh (Phase 5 Test 1 - ENABLED) with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh -s -- --unattended) || \
    (echo "⚠️  Oh My Zsh script failed, using git clone fallback..." && \
     git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh && \
     cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc) || \
    echo "❌ Oh My Zsh installation failed completely, skipping..."

# Install Zsh plugins (Phase 5 Test 2 - ENABLED)
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${HOME}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

# Rust tools removed - belongs in C++/systems programming container

# Ensure we're root for global installs
USER root

# Install Node.js global packages (Phase 5 Test 5 - COMPLETE: 15 tools - All Batches)
RUN npm install -g \
    typescript \
    ts-node \
    nodemon \
    pm2 \
    eslint \
    prettier \
    vite \
    http-server \
    json-server \
    create-react-app \
    @angular/cli \
    @vue/cli \
    webpack \
    webpack-cli \
    @playwright/test

# Install Python packages (disabled)
# RUN python3 -m venv /opt/venv && \
#     /opt/venv/bin/pip install --no-cache-dir \
#     jupyter \
#     jupyterlab \
#     numpy \
#     pandas \
#     matplotlib \
#     seaborn \
#     requests \
#     flask \
#     fastapi \
#     uvicorn \
#     pytest \
#     black \
#     flake8 \
#     mypy \
#     poetry \
#     pipenv

# ========================================
# PHASE 6: FLUTTER ECOSYSTEM
# ========================================

# Install Flutter SDK
ENV FLUTTER_HOME="/opt/flutter"
ENV PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$PATH"

# Install Flutter with fallback
RUN (git clone https://github.com/flutter/flutter.git $FLUTTER_HOME \
    && cd $FLUTTER_HOME \
    && git checkout stable \
    && $FLUTTER_HOME/bin/flutter config --no-analytics) || \
    (echo "⚠️  Flutter git clone failed, using direct download fallback..." && \
     FLUTTER_VERSION="3.16.5" && \
     curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
     https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz | tar -xJC /opt \
     && $FLUTTER_HOME/bin/flutter config --no-analytics) || \
    echo "❌ Flutter installation failed completely, skipping..."

# Install Flutter/Dart-specific tools with fallback
RUN $FLUTTER_HOME/bin/dart pub global activate fvm || echo "❌ FVM installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate very_good_cli || echo "❌ Very Good CLI installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate mason_cli || echo "❌ Mason CLI installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate flutterfire_cli || echo "❌ FlutterFire CLI installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate dart_code_metrics || echo "❌ Dart Code Metrics installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate build_runner || echo "❌ Build Runner installation failed, skipping..."

# Install additional essential Flutter development tools
RUN $FLUTTER_HOME/bin/dart pub global activate flutter_gen || echo "❌ Flutter Gen installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate flutter_launcher_icons || echo "❌ Flutter Launcher Icons installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate flutter_native_splash || echo "❌ Flutter Native Splash installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate intl_utils || echo "❌ Intl Utils installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate rename || echo "❌ Rename tool installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate get_cli || echo "❌ GetX CLI installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate bloc_cli || echo "❌ Bloc CLI installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate patrol_cli || echo "❌ Patrol CLI installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate melos || echo "❌ Melos installation failed, skipping..."
RUN $FLUTTER_HOME/bin/dart pub global activate alchemist || echo "❌ Alchemist installation failed, skipping..."

# Note: Golden Toolkit is typically added as a dev dependency in pubspec.yaml
# Alchemist provides CLI support for Golden Toolkit workflows

# Install Firebase CLI with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://firebase.tools/bin/linux/latest | bash) || \
    (echo "⚠️  Firebase CLI script failed, using npm fallback..." && \
     npm install -g firebase-tools) || \
    echo "❌ Firebase CLI installation failed completely, skipping..."

# Install additional mobile development tools
RUN apt-get update && apt-get install -y \
    gradle \
    && rm -rf /var/lib/apt/lists/*

# Install Fastlane (mobile deployment automation) with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://raw.githubusercontent.com/fastlane/fastlane/master/install | bash -s -- -b /usr/local/bin) || \
    echo "❌ Fastlane installation failed, skipping..."

# Install CocoaPods for iOS development with fallback
RUN (gem install cocoapods) || \
    echo "❌ CocoaPods installation failed, skipping..."

# Install Sentry CLI for error tracking with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://sentry.io/get-cli/ | bash) || \
    (echo "⚠️  Sentry CLI script failed, using npm fallback..." && \
     npm install -g @sentry/cli) || \
    echo "❌ Sentry CLI installation failed completely, skipping..."

# Install Shorebird for code push updates with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh | bash) || \
    echo "❌ Shorebird installation failed, skipping..."

# Install Figma CLI for design workflow with fallback
RUN (npm install -g @figma/figma-api) || \
    echo "❌ Figma CLI installation failed, skipping..."

# Install Figma Desktop App with fallbacks
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://api.github.com/repos/Figma-Linux/figma-linux/releases/latest | jq -r '.assets[] | select(.name | contains("linux") and contains(".deb")) | .browser_download_url' | xargs wget -q -O figma.deb \
    && dpkg -i figma.deb || apt-get install -f -y \
    && rm figma.deb) || \
    echo "❌ Figma Desktop installation failed, skipping..."

# ========================================
# PHASE 7: SHELL AND ENVIRONMENT SETUP
# ========================================

# Set up shell configuration (disabled)
# RUN echo 'export PATH="$PATH:/home/'${USERNAME}'/.dotnet/tools"' >> ~/.zshrc \
#     && echo 'export PATH="$PATH:/home/'${USERNAME}'/.cargo/bin"' >> ~/.zshrc \
#     && echo 'export PATH="$PATH:/home/'${USERNAME}'/.local/bin"' >> ~/.zshrc \
#     && echo 'plugins=(git dotnet docker docker-compose kubectl helm azure npm node python terraform zsh-autosuggestions zsh-syntax-highlighting)' >> ~/.zshrc

# Add useful aliases (disabled)
# RUN echo '# .NET aliases' >> ~/.zshrc \
#     && echo 'alias dn="dotnet"' >> ~/.zshrc \
#     && echo 'alias dnr="dotnet run"' >> ~/.zshrc \
#     && echo 'alias dnb="dotnet build"' >> ~/.zshrc \
#     && echo 'alias dnt="dotnet test"' >> ~/.zshrc \
#     && echo 'alias dnw="dotnet watch"' >> ~/.zshrc \
#     && echo 'alias dnc="dotnet clean"' >> ~/.zshrc \
#     && echo 'alias dnp="dotnet publish"' >> ~/.zshrc \
#     && echo 'alias dna="dotnet add"' >> ~/.zshrc \
#     && echo 'alias dnrm="dotnet remove"' >> ~/.zshrc \
#     && echo 'alias dnrs="dotnet restore"' >> ~/.zshrc \
#     && echo 'alias dnnew="dotnet new"' >> ~/.zshrc \
#     && echo 'alias dnef="dotnet ef"' >> ~/.zshrc \
#     && echo '# Docker aliases' >> ~/.zshrc \
#     && echo 'alias d="docker"' >> ~/.zshrc \
#     && echo 'alias dc="docker-compose"' >> ~/.zshrc \
#     && echo 'alias dps="docker ps"' >> ~/.zshrc \
#     && echo 'alias di="docker images"' >> ~/.zshrc \
#     && echo '# Kubernetes aliases' >> ~/.zshrc \
#     && echo 'alias k="kubectl"' >> ~/.zshrc \
#     && echo 'alias kgp="kubectl get pods"' >> ~/.zshrc \
#     && echo 'alias kgs="kubectl get services"' >> ~/.zshrc \
#     && echo 'alias kgd="kubectl get deployments"' >> ~/.zshrc \
#     && echo '# Modern CLI aliases' >> ~/.zshrc \
#     && echo 'alias ll="exa -la"' >> ~/.zshrc \
#     && echo 'alias la="exa -la"' >> ~/.zshrc \
#     && echo 'alias ls="exa"' >> ~/.zshrc \
#     && echo 'alias cat="batcat"' >> ~/.zshrc \
#     && echo 'alias find="fd"' >> ~/.zshrc \
#     && echo 'alias grep="rg"' >> ~/.zshrc \
#     && echo 'alias cd="z"' >> ~/.zshrc
#     && echo 'alias cd="z"' >> ~/.zshrc

# Create common project directories (disabled)
# RUN mkdir -p ~/workspace/{src,tests,docs,scripts,tools,docker,kubernetes,terraform}

# Switch back to root for final setup
USER root

# Add Flutter, Android, and development tools to system PATH and set environment variables
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV FLUTTER_HOME="/opt/flutter"
ENV ANDROID_HOME="/opt/android-sdk"
ENV ANDROID_SDK_ROOT="/opt/android-sdk"
ENV PATH="/opt/venv/bin:${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator:${ANDROID_HOME}/cmdline-tools/latest/bin:${PATH}:/home/${USERNAME}/.dotnet/tools:/home/${USERNAME}/.local/bin:/home/${USERNAME}/.pub-cache/bin"

# Set ownership for Flutter and add user shell configuration
RUN chown -R ${USERNAME}:${USERNAME} $FLUTTER_HOME

# Create Android SDK mount point and compatibility directories for the user
RUN mkdir -p /home/${USERNAME}/Android/Sdk/platform-tools \
    && ln -sf /opt/android-sdk/platform-tools/adb /home/${USERNAME}/Android/Sdk/platform-tools/adb \
    && ln -sf /opt/android-sdk/platform-tools/fastboot /home/${USERNAME}/Android/Sdk/platform-tools/fastboot \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/Android/Sdk

# Set default user
USER ${USERNAME}

# Add Flutter and Android environment to user shells
RUN echo "export FLUTTER_HOME=\"/opt/flutter\"" >> /home/${USERNAME}/.bashrc \
    && echo "export ANDROID_HOME=\"/opt/android-sdk\"" >> /home/${USERNAME}/.bashrc \
    && echo "export ANDROID_SDK_ROOT=\"/opt/android-sdk\"" >> /home/${USERNAME}/.bashrc \
    && echo "export PATH=\"\$FLUTTER_HOME/bin:\$FLUTTER_HOME/bin/cache/dart-sdk/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH:/home/${USERNAME}/.pub-cache/bin\"" >> /home/${USERNAME}/.bashrc \
    && echo "export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037" >> /home/${USERNAME}/.bashrc \
    && echo "export FLUTTER_HOME=\"/opt/flutter\"" >> /home/${USERNAME}/.zshrc \
    && echo "export ANDROID_HOME=\"/opt/android-sdk\"" >> /home/${USERNAME}/.zshrc \
    && echo "export ANDROID_SDK_ROOT=\"/opt/android-sdk\"" >> /home/${USERNAME}/.zshrc \
    && echo "export PATH=\"\$FLUTTER_HOME/bin:\$FLUTTER_HOME/bin/cache/dart-sdk/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH:/home/${USERNAME}/.pub-cache/bin\"" >> /home/${USERNAME}/.zshrc \
    && echo "export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037" >> /home/${USERNAME}/.zshrc

# Pre-download Flutter dependencies and accept Android licenses
RUN flutter doctor --android-licenses || true \
    && flutter precache || true

# Set workdir for Flutter development
WORKDIR /workspace

# Keep container running
CMD ["sleep", "infinity"]

