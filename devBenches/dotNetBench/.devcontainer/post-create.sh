#!/bin/bash

echo "🚀 Setting up .NET DevBench environment..."

# Update package lists
sudo apt update

# Install additional development tools
sudo apt install -y \
    curl \
    wget \
    unzip \
    zip \
    tree \
    jq \
    httpie \
    htop \
    neofetch \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    libssl-dev \
    sqlite3 \
    postgresql-client \
    redis-tools \
    net-tools \
    nmap \
    telnet \
    netcat \
    dnsutils \
    vim \
    nano \
    tmux \
    screen \
    fish \
    zoxide \
    ripgrep \
    fd-find \
    bat \
    exa \
    fzf

# Install .NET global tools
echo "📦 Installing .NET global tools..."
dotnet tool install --global dotnet-ef
dotnet tool install --global dotnet-aspnet-codegenerator
dotnet tool install --global Microsoft.Web.LibraryManager.Cli
dotnet tool install --global dotnet-reportgenerator-globaltool
dotnet tool install --global dotnet-stryker
dotnet tool install --global dotnet-outdated-tool
dotnet tool install --global GitVersion.Tool
dotnet tool install --global Microsoft.Tye --version "0.11.0-alpha.22111.1"
dotnet tool install --global dotnet-format
dotnet tool install --global dotnet-trace
dotnet tool install --global dotnet-dump
dotnet tool install --global dotnet-counters
dotnet tool install --global dotnet-monitor
dotnet tool install --global Microsoft.dotnet-httprepl
dotnet tool install --global PowerShell
dotnet tool install --global Swashbuckle.AspNetCore.Cli
dotnet tool install --global dotnet-sonarscanner
dotnet tool install --global coverlet.console

# Install additional package managers and tools
echo "📦 Installing additional package managers..."

# Install Chocolatey alternative for Linux (Homebrew)
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.zshrc
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Install k6 for load testing
if command -v brew &> /dev/null; then
    brew install k6
fi

# Install kubectl
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
fi

# Install Helm
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Install Dapr CLI
if ! command -v dapr &> /dev/null; then
    wget -q https://raw.githubusercontent.com/dapr/cli/master/install/install.sh -O - | /bin/bash
fi

# Install Pulumi
if ! command -v pulumi &> /dev/null; then
    curl -fsSL https://get.pulumi.com | sh
    echo 'export PATH=$PATH:$HOME/.pulumi/bin' >> ~/.zshrc
fi

# Install Bun (alternative to npm)
if ! command -v bun &> /dev/null; then
    curl -fsSL https://bun.sh/install | bash
    echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.zshrc
fi

# Install Rust and Cargo (for additional tooling)
if ! command -v rustc &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
    echo 'source ~/.cargo/env' >> ~/.zshrc
fi

# Install additional Rust tools
if command -v cargo &> /dev/null; then
    cargo install tokei      # Code statistics
    cargo install hyperfine  # Benchmarking tool
    cargo install just       # Command runner
    cargo install starship   # Cross-shell prompt
fi

# Configure Starship prompt
if command -v starship &> /dev/null; then
    echo 'eval "$(starship init zsh)"' >> ~/.zshrc
fi

# Install Oh My Zsh plugins
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Update .zshrc with useful plugins
sed -i 's/plugins=(git)/plugins=(git dotnet docker docker-compose kubectl helm azure npm node python terraform zsh-autosuggestions zsh-syntax-highlighting)/g' ~/.zshrc

# Create useful aliases
cat >> ~/.zshrc << 'EOF'

# Custom aliases for .NET development
alias ll='exa -la'
alias la='exa -la'
alias ls='exa'
alias cat='batcat'
alias find='fd'
alias grep='rg'
alias dn='dotnet'
alias dnr='dotnet run'
alias dnb='dotnet build'
alias dnt='dotnet test'
alias dnw='dotnet watch'
alias dnc='dotnet clean'
alias dnp='dotnet publish'
alias dna='dotnet add'
alias dnrm='dotnet remove'
alias dnrs='dotnet restore'
alias dnnew='dotnet new'
alias dnef='dotnet ef'

# Docker aliases
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias di='docker images'
alias dex='docker exec -it'

# Kubernetes aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias kdd='kubectl describe deployment'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gco='git checkout'
alias gb='git branch'
alias gd='git diff'
alias glog='git log --oneline --graph --decorate'

EOF

# Install .NET workload for various platforms
echo "🔧 Installing .NET workloads..."
dotnet workload install blazor
dotnet workload install maui
dotnet workload install android
dotnet workload install ios
dotnet workload install maccatalyst
dotnet workload install tvos
dotnet workload install macos
dotnet workload install wasm-tools

# Create common project structure directories
mkdir -p ~/workspace/{src,tests,docs,scripts,tools}

# Set up Git configuration template
git config --global init.defaultBranch main
git config --global pull.rebase false

echo "✅ .NET DevBench environment setup complete!"
echo "🎉 Available tools:"
echo "   - .NET SDK with all workloads"
echo "   - Docker & Docker Compose"
echo "   - Kubernetes tools (kubectl, helm)"
echo "   - Azure CLI & PowerShell"
echo "   - Node.js, Python, Rust"
echo "   - Git, GitHub CLI"
echo "   - Modern shell tools (exa, bat, ripgrep, fd, fzf)"
echo "   - Load testing (k6)"
echo "   - Infrastructure as Code (Terraform, Pulumi)"
echo "   - Microservices tools (Dapr)"
echo "   - And much more!"