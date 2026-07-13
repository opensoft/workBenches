# syntax=docker/dockerfile:1.7
# Layer 0: System Base Image
# Ubuntu 24.04 with system tools and AI coding CLIs
# Used by ALL benches (Frappe, Flutter, .NET, Bio, Admin, etc.)
# Build once, use everywhere
# USER-AGNOSTIC: No user creation — Layer 3 handles user setup

FROM ubuntu:24.04

# Container version labels
LABEL layer="0"
LABEL layer.name="workbench-base"
LABEL layer.version="2.0.3"
LABEL layer.description="System base with AI CLIs for all workBenches (user-agnostic)"

# Everything runs as root — no user in this layer
USER root

# ========================================
# SYSTEM PACKAGES
# ========================================

# Install core system tools
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    # Version control
    git \
    # Editors
    vim \
    neovim \
    nano \
    # Network tools
    curl \
    wget \
    iputils-ping \
    net-tools \
    # Utilities
    jq \
    ripgrep \
    fd-find \
    unzip \
    zsh \
    tmux \
    screen \
    openssh-client \
    cron \
    fzf \
    bat \
    sudo \
    # Sandbox runtime used by Codex; without this, Codex falls back to its
    # bundled bubblewrap and prints a startup warning.
    bubblewrap \
    # Build tools
    build-essential \
    pkg-config \
    # GPG for repository keys
    gpg \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Provide fd alias for Ubuntu's fdfind
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd

# ========================================
# GITHUB CLI
# ========================================

ARG GH_VERSION=2.96.0
RUN set -eux; \
    gh_version="${GH_VERSION}"; \
    if [ "$gh_version" = "latest" ]; then \
        gh_version="$(curl --http1.1 -fsSL --retry 3 --connect-timeout 10 --speed-time 20 --speed-limit 1024 --max-time 60 https://api.github.com/repos/cli/cli/releases/latest | jq -r '.tag_name // empty' | sed 's/^v//')"; \
    fi; \
    if [ -z "$gh_version" ] || [ "$gh_version" = "null" ]; then \
        gh_version="2.96.0"; \
    fi; \
    case "$(dpkg --print-architecture)" in \
        amd64) gh_arch="amd64" ;; \
        arm64) gh_arch="arm64" ;; \
        armhf) gh_arch="armv6" ;; \
        386) gh_arch="386" ;; \
        *) echo "Unsupported architecture for GitHub CLI: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    gh_url="https://github.com/cli/cli/releases/download/v${gh_version}/gh_${gh_version}_linux_${gh_arch}.tar.gz"; \
    timeout 900s wget -q --https-only --timeout=30 --tries=3 --waitretry=2 -O /tmp/gh.tar.gz "$gh_url" \
        || curl --http1.1 -fL --retry 2 --connect-timeout 10 --speed-time 20 --speed-limit 1024 --max-time 90 -o /tmp/gh.tar.gz "$gh_url"; \
    tar -xzf /tmp/gh.tar.gz -C /tmp; \
    install -m 0755 "/tmp/gh_${gh_version}_linux_${gh_arch}/bin/gh" /usr/local/bin/gh; \
    rm -rf /tmp/gh.tar.gz "/tmp/gh_${gh_version}_linux_${gh_arch}"

# ========================================
# DOCKER CLI & COMPOSE
# ========================================

# Install the Docker client only. Benches talk to the host daemon via a
# mounted docker.sock; they do not run dockerd inside the container.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# MODERN CLI UTILITIES
# ========================================

# Install yq (YAML processor)
RUN YQ_VERSION=$(curl --retry 5 --retry-all-errors --connect-timeout 30 -fsSL https://api.github.com/repos/mikefarah/yq/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/') \
    && curl --retry 5 --retry-all-errors --connect-timeout 30 -fL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Install zoxide (smarter cd) - install to /usr/local/bin
RUN curl --retry 5 --retry-all-errors --connect-timeout 30 -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash -s -- --bin-dir /usr/local/bin

# Install Node.js 24 LTS for modern AI CLI builds and npm-based tools.
RUN apt-get update \
    && export DEBIAN_FRONTEND=noninteractive \
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable || true

# Install npm itself and tldr (simplified man pages) from npm's latest dist-tags.
RUN npm install -g npm@latest tldr \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# UV (system-wide)
# ========================================

# Install uv to /usr/local/bin (system-wide)
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# Ensure spec-driven CLIs are not inherited from cached Layer 0 state.
RUN npm uninstall -g @fission-ai/openspec || true \
    && rm -f /usr/bin/openspec /usr/local/bin/openspec \
    && rm -rf /usr/lib/node_modules/@fission-ai/openspec /usr/local/lib/node_modules/@fission-ai/openspec \
    && uv tool uninstall specify-cli || true \
    && env UV_TOOL_BIN_DIR=/usr/local/bin UV_TOOL_DIR=/opt/uv/tools uv tool uninstall specify-cli || true \
    && rm -f /root/.local/bin/specify /usr/local/bin/specify \
    && rm -rf /root/.local/share/uv/tools/specify-cli /opt/uv/tools/specify-cli

# ========================================
# BUN RUNTIME (system-wide at /opt/bun)
# ========================================

ARG BUN_VERSION=1.3.14
ENV BUN_INSTALL=/opt/bun
RUN curl -fsSL https://bun.sh/install | BUN_VERSION=${BUN_VERSION} bash \
    && chmod -R a+rx /opt/bun
ENV PATH="/opt/bun/bin:${PATH}"

# ========================================
# AI CLI TOOLS (installed as root to system paths)
# ========================================

# Copy and run AI CLI installation script
COPY install-ai-clis.sh /tmp/
ARG AI_CLI_REFRESH=2026-07-12
RUN echo "AI CLI refresh marker: ${AI_CLI_REFRESH}"
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.npm \
    bash /tmp/install-ai-clis.sh && rm /tmp/install-ai-clis.sh

# Multi-account Claude launcher. Credential profiles are host state mounted at
# ~/.claude-profiles; only the provider-neutral launcher belongs in the image.
COPY files/claude-profile /usr/local/bin/claude-profile
COPY files/claude-statusline-command.sh /usr/local/share/workbenches/claude/statusline-command.sh
RUN chmod 0755 /usr/local/bin/claude-profile \
    /usr/local/share/workbenches/claude/statusline-command.sh \
    && ln -sfn claude-profile /usr/local/bin/pclaude \
    && mkdir -p /etc/skel/.local/bin \
    && ln -sfn /usr/local/bin/claude /etc/skel/.local/bin/claude

# ========================================
# ZSH CONFIGURATION (into /etc/skel for future users)
# ========================================

# Install Oh-My-Zsh into /etc/skel from a bounded tarball download.
RUN mkdir -p /etc/skel/.oh-my-zsh \
    && timeout 1800s curl --http1.1 -fL --retry 2 --connect-timeout 10 --speed-time 20 --speed-limit 1024 --max-time 1200 \
        -o /tmp/ohmyzsh.tar.gz https://github.com/ohmyzsh/ohmyzsh/archive/refs/heads/master.tar.gz \
    && tar -xzf /tmp/ohmyzsh.tar.gz -C /etc/skel/.oh-my-zsh --strip-components=1 \
    && rm -f /tmp/ohmyzsh.tar.gz /root/.zshrc

# Install Powerlevel10k theme from a bounded tarball download.
RUN mkdir -p /etc/skel/.oh-my-zsh/custom/themes/powerlevel10k \
    && timeout 1800s curl --http1.1 -fL --retry 2 --connect-timeout 10 --speed-time 20 --speed-limit 1024 --max-time 1200 \
        -o /tmp/powerlevel10k.tar.gz https://github.com/romkatv/powerlevel10k/archive/refs/heads/master.tar.gz \
    && tar -xzf /tmp/powerlevel10k.tar.gz -C /etc/skel/.oh-my-zsh/custom/themes/powerlevel10k --strip-components=1 \
    && rm -f /tmp/powerlevel10k.tar.gz

# Overlay latest upstream binaries for CLI tools where Ubuntu apt lags.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) nvim_arch="x86_64"; fzf_arch="amd64"; jq_arch="amd64" ;; \
        arm64) nvim_arch="arm64"; fzf_arch="arm64"; jq_arch="arm64" ;; \
        *) echo "Unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    nvim_tag="$(curl --http1.1 -fsSL --retry 2 --connect-timeout 10 --max-time 120 https://api.github.com/repos/neovim/neovim/releases/latest | jq -r '.tag_name')"; \
    timeout 3600s curl --http1.1 -fL --retry 2 --connect-timeout 10 --speed-time 20 --speed-limit 1024 --max-time 3600 \
        -o /tmp/nvim.tar.gz "https://github.com/neovim/neovim/releases/download/${nvim_tag}/nvim-linux-${nvim_arch}.tar.gz"; \
    rm -rf /opt/nvim; \
    tar -xzf /tmp/nvim.tar.gz -C /opt; \
    mv "/opt/nvim-linux-${nvim_arch}" /opt/nvim; \
    ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim; \
    fzf_tag="$(curl --http1.1 -fsSL --retry 2 --connect-timeout 10 --max-time 120 https://api.github.com/repos/junegunn/fzf/releases/latest | jq -r '.tag_name')"; \
    fzf_version="${fzf_tag#v}"; \
    timeout 3600s curl --http1.1 -fL --retry 2 --connect-timeout 10 --speed-time 20 --speed-limit 1024 --max-time 3600 \
        -o /tmp/fzf.tar.gz "https://github.com/junegunn/fzf/releases/download/${fzf_tag}/fzf-${fzf_version}-linux_${fzf_arch}.tar.gz"; \
    tar -xzf /tmp/fzf.tar.gz -C /tmp; \
    install -m 0755 /tmp/fzf /usr/local/bin/fzf; \
    jq_tag="$(curl --http1.1 -fsSL --retry 2 --connect-timeout 10 --max-time 120 https://api.github.com/repos/jqlang/jq/releases/latest | jq -r '.tag_name')"; \
    timeout 3600s curl --http1.1 -fL --retry 2 --connect-timeout 10 --speed-time 20 --speed-limit 1024 --max-time 3600 \
        -o /usr/local/bin/jq "https://github.com/jqlang/jq/releases/download/${jq_tag}/jq-linux-${jq_arch}"; \
    chmod 0755 /usr/local/bin/jq; \
    rm -f /tmp/nvim.tar.gz /tmp/fzf.tar.gz /tmp/fzf

# Create /etc/skel/.zshrc template
RUN echo 'export ZSH="$HOME/.oh-my-zsh"' > /etc/skel/.zshrc && \
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> /etc/skel/.zshrc && \
    echo 'plugins=(git)' >> /etc/skel/.zshrc && \
    echo 'source $ZSH/oh-my-zsh.sh' >> /etc/skel/.zshrc && \
    echo '' >> /etc/skel/.zshrc && \
    echo '# Modern CLI tools' >> /etc/skel/.zshrc && \
    echo 'eval "$(zoxide init zsh)"' >> /etc/skel/.zshrc && \
    echo 'alias cat="batcat"' >> /etc/skel/.zshrc && \
    echo 'alias ls="ls --color=auto"' >> /etc/skel/.zshrc && \
    echo 'export PATH="/opt/grok/bin:$HOME/.local/bin:/opt/bun/bin:$PATH"' >> /etc/skel/.zshrc && \
    echo 'fpath=(/opt/grok/completions/zsh $fpath)' >> /etc/skel/.zshrc && \
    echo 'autoload -Uz compinit && compinit -C' >> /etc/skel/.zshrc && \
    echo '' >> /etc/skel/.zshrc && \
    echo '# Powerlevel10k instant prompt' >> /etc/skel/.zshrc && \
    echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> /etc/skel/.zshrc

# Create /etc/skel/.bashrc template
RUN echo 'eval "$(zoxide init bash)"' >> /etc/skel/.bashrc && \
    echo 'export PATH="/opt/grok/bin:$HOME/.local/bin:/opt/bun/bin:$PATH"' >> /etc/skel/.bashrc && \
    echo '[[ -r /opt/grok/completions/bash/grok.bash ]] && source /opt/grok/completions/bash/grok.bash' >> /etc/skel/.bashrc

# Provide AI helpers system-wide so all benches inherit them even when
# a workspace does not mount a host shell profile.
RUN cat <<'EOF' >> /etc/zsh/zshrc

# WorkBench AI helpers
_yolo_shell_quote() {
  local quoted="" arg

  for arg in "$@"; do
    quoted="${quoted} $(printf '%q' "$arg")"
  done

  printf '%s\n' "${quoted# }"
}

unalias yolo 2>/dev/null || true
yolo() {
  local session_name command_string prompt_file
  local -a prompt_args

  if ! command -v claude >/dev/null 2>&1; then
    echo "yolo: Claude CLI not found on PATH" >&2
    return 1
  fi

  if ! command -v tmux >/dev/null 2>&1; then
    echo "yolo: tmux not found on PATH" >&2
    return 1
  fi

  prompt_file=""
  for candidate_prompt_file in \
    "$HOME/.claude/prompts/speckit-dashboard-full.md" \
    "/usr/local/share/ct/claude/prompts/speckit-dashboard-full.md" \
    "$HOME/.claude/prompts/speckit-dashboard-bootstrap.md"; do
    if [ -r "$candidate_prompt_file" ]; then
      prompt_file="$candidate_prompt_file"
      break
    fi
  done
  prompt_args=()
  if [ -n "$prompt_file" ]; then
    prompt_args=(--append-system-prompt-file "$prompt_file")
  fi

  if [ -n "${TMUX:-}" ]; then
    claude --dangerously-skip-permissions --teammate-mode tmux "${prompt_args[@]}" "$@"
    return $?
  fi

  session_name="yolo-$(date +%Y%m%d%H%M%S)-$$"
  command_string=$(_yolo_shell_quote \
    claude \
    --dangerously-skip-permissions \
    --teammate-mode tmux \
    "${prompt_args[@]}" \
    "$@") || return 1

  tmux new-session -d -s "$session_name" -c "$PWD" "exec $command_string" || {
    echo "yolo: failed to start tmux session" >&2
    return 1
  }

  tmux set-option -t "$session_name" mouse on >/dev/null 2>&1 || true
  tmux attach-session -t "$session_name"
}
EOF

RUN cat <<'EOF' >> /etc/bash.bashrc

# WorkBench AI helpers
_yolo_shell_quote() {
  local quoted="" arg

  for arg in "$@"; do
    quoted="${quoted} $(printf '%q' "$arg")"
  done

  printf '%s\n' "${quoted# }"
}

unalias yolo 2>/dev/null || true
yolo() {
  local session_name command_string prompt_file
  local -a prompt_args

  if ! command -v claude >/dev/null 2>&1; then
    echo "yolo: Claude CLI not found on PATH" >&2
    return 1
  fi

  if ! command -v tmux >/dev/null 2>&1; then
    echo "yolo: tmux not found on PATH" >&2
    return 1
  fi

  prompt_file=""
  for candidate_prompt_file in \
    "$HOME/.claude/prompts/speckit-dashboard-full.md" \
    "/usr/local/share/ct/claude/prompts/speckit-dashboard-full.md" \
    "$HOME/.claude/prompts/speckit-dashboard-bootstrap.md"; do
    if [ -r "$candidate_prompt_file" ]; then
      prompt_file="$candidate_prompt_file"
      break
    fi
  done
  prompt_args=()
  if [ -n "$prompt_file" ]; then
    prompt_args=(--append-system-prompt-file "$prompt_file")
  fi

  if [ -n "${TMUX:-}" ]; then
    claude --dangerously-skip-permissions --teammate-mode tmux "${prompt_args[@]}" "$@"
    return $?
  fi

  session_name="yolo-$(date +%Y%m%d%H%M%S)-$$"
  command_string=$(_yolo_shell_quote \
    claude \
    --dangerously-skip-permissions \
    --teammate-mode tmux \
    "${prompt_args[@]}" \
    "$@") || return 1

  tmux new-session -d -s "$session_name" -c "$PWD" "exec $command_string" || {
    echo "yolo: failed to start tmux session" >&2
    return 1
  }

  tmux set-option -t "$session_name" mouse on >/dev/null 2>&1 || true
  tmux attach-session -t "$session_name"
}
EOF

# ========================================
# OPENCODE CONFIGURATION (into /etc/skel)
# ========================================

RUN mkdir -p /etc/skel/.config/opencode/agent/core \
    && mkdir -p /etc/skel/.config/opencode/context/skills
COPY files/opencode/opencode.json /etc/skel/.config/opencode/
COPY files/opencode/oh-my-opencode.json /etc/skel/.config/opencode/
COPY files/opencode/agent/ /etc/skel/.config/opencode/agent/
COPY files/opencode/context/ /etc/skel/.config/opencode/context/

# ========================================
# SPECKIT SKILLS (Claude Code, into /etc/skel)
# ========================================
# OpenSpec/opsx commands are installed with the devBench OpenSpec layer, where
# the openspec CLI is present. Layer 0 keeps only non-OpenSpec Claude defaults.
# Agent-team-enhanced Speckit workflows. Each skill upgrades the corresponding
# project-level /speckit.* command with parallel specialist agents.
# Uses speckit-* prefix — speckit init/update won't overwrite these.

RUN mkdir -p /etc/skel/.claude/skills/speckit-specify \
    && mkdir -p /etc/skel/.claude/skills/speckit-clarify \
    && mkdir -p /etc/skel/.claude/skills/speckit-plan \
    && mkdir -p /etc/skel/.claude/skills/speckit-tasks \
    && mkdir -p /etc/skel/.claude/skills/speckit-analyze \
    && mkdir -p /etc/skel/.claude/skills/speckit-implement
COPY files/claude/skills/speckit-specify/ /etc/skel/.claude/skills/speckit-specify/
COPY files/claude/skills/speckit-clarify/ /etc/skel/.claude/skills/speckit-clarify/
COPY files/claude/skills/speckit-plan/ /etc/skel/.claude/skills/speckit-plan/
COPY files/claude/skills/speckit-tasks/ /etc/skel/.claude/skills/speckit-tasks/
COPY files/claude/skills/speckit-analyze/ /etc/skel/.claude/skills/speckit-analyze/
COPY files/claude/skills/speckit-implement/ /etc/skel/.claude/skills/speckit-implement/

# ========================================
# WORKSPACE DIRECTORY
# ========================================

RUN mkdir -p /workspace

# Default command
CMD ["sleep", "infinity"]
