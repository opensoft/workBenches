# THE BIG HEAVY FULL LOADED GO DEVTOOL MONSTER - Ubuntu 24.04 Edition
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
        echo "🚀 THE BIG HEAVY FULL LOADED GO DEVTOOL MONSTER"; \
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

# Phase 2b: Install Go from official repository
RUN apt-get update && apt-get install -y \
    golang-go \
    && rm -rf /var/lib/apt/lists/*

# Install latest Go version manually (1.22+)
RUN GO_VERSION="1.22.0" && \
    wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz && \
    rm -rf /usr/local/go && \
    tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz && \
    rm go${GO_VERSION}.linux-amd64.tar.gz

# Set Go environment variables
ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/go
ENV GOBIN=/go/bin
ENV PATH=$PATH:$GOBIN

# Phase 2c: Node.js from NodeSource (includes npm)
RUN apt-get update && apt-get install -y \
    nodejs \
    && rm -rf /var/lib/apt/lists/*

# Phase 2d: Other languages and runtimes
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

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

# Phase 2n: System utilities
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

# Install Oh My Zsh with fallback
RUN (curl -fsSL --retry 3 --user-agent "Mozilla/5.0" \
    https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh -s -- --unattended) || \
    (echo "⚠️  Oh My Zsh script failed, using git clone fallback..." && \
     git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh && \
     cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc) || \
    echo "❌ Oh My Zsh installation failed completely, skipping..."

# Install Zsh plugins
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${HOME}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

# Ensure we're root for global installs
USER root

# Install Node.js global packages
RUN npm install -g \
    typescript \
    ts-node \
    nodemon \
    eslint \
    prettier \
    http-server

# ========================================
# PHASE 6: GO TOOL EXTRAVAGANZA
# ========================================

# Install Go development tools
RUN go install golang.org/x/tools/gopls@latest && \
    go install github.com/go-delve/delve/cmd/dlv@latest && \
    go install honnef.co/go/tools/cmd/staticcheck@latest && \
    go install golang.org/x/lint/golint@latest && \
    go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest && \
    go install golang.org/x/tools/cmd/goimports@latest && \
    go install github.com/fatih/gomodifytags@latest && \
    go install github.com/cweill/gotests/...@latest && \
    go install github.com/josharian/impl@latest && \
    go install github.com/haya14busa/goplay/cmd/goplay@latest && \
    go install github.com/go-playground/validator/v10@latest && \
    go install github.com/swaggo/swag/cmd/swag@latest && \
    go install github.com/cosmtrek/air@latest && \
    go install github.com/goreleaser/goreleaser@latest && \
    go install github.com/kisielk/errcheck@latest && \
    go install mvdan.cc/gofumpt@latest && \
    go install github.com/segmentio/golines@latest && \
    go install github.com/google/wire/cmd/wire@latest && \
    go install github.com/google/ko@latest && \
    go install github.com/rakyll/hey@latest && \
    go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest && \
    go install google.golang.org/protobuf/cmd/protoc-gen-go@latest && \
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# Install additional Go utilities
RUN go install github.com/mikefarah/yq/v4@latest && \
    go install github.com/tektoncd/cli/cmd/tkn@latest && \
    go install sigs.k8s.io/kind@latest

# ========================================
# PHASE 7: SHELL AND ENVIRONMENT SETUP
# ========================================

# Switch back to root for final setup
USER root

# Add Go tools to system PATH
ENV PATH="${PATH}:/home/${USERNAME}/go/bin:${GOBIN}:/home/${USERNAME}/.local/bin"

# Set default user
USER ${USERNAME}

# Keep container running
CMD ["sleep", "infinity"]
