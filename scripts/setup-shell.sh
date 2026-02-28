#!/bin/bash

# Setup script for zsh + Powerlevel10k + Oh My Zsh
# Installs and configures the shell environment from workBenches config.
# Safe to run multiple times (idempotent).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SHELL_CONFIG_DIR="$REPO_DIR/config/shell"

echo "=========================================="
echo "Shell Environment Setup"
echo "=========================================="
echo ""

# Detect OS for package manager
detect_package_manager() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS=$(uname -s)
    fi

    case "$OS" in
        ubuntu|debian|pop)
            PKG_INSTALL="sudo apt update && sudo apt install -y"
            ;;
        fedora|rhel|centos)
            PKG_INSTALL="sudo dnf install -y"
            ;;
        alpine)
            PKG_INSTALL="sudo apk add"
            ;;
        *)
            PKG_INSTALL=""
            ;;
    esac
}

detect_package_manager

# --- 1. Install zsh ---
if command -v zsh >/dev/null 2>&1; then
    echo "✓ zsh is already installed: $(zsh --version)"
else
    echo "Installing zsh..."
    if [ -n "$PKG_INSTALL" ]; then
        eval "$PKG_INSTALL zsh"
        echo "✓ zsh installed: $(zsh --version)"
    else
        echo "✗ Cannot auto-install zsh for OS '$OS'. Please install it manually."
        exit 1
    fi
fi
echo ""

# --- 2. Install Oh My Zsh ---
if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "✓ Oh My Zsh is already installed"
else
    echo "Installing Oh My Zsh..."
    # RUNZSH=no prevents it from switching shell immediately
    # KEEP_ZSHRC=yes prevents it from overwriting .zshrc (we deploy our own)
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    echo "✓ Oh My Zsh installed"
fi
echo ""

# --- 3. Install Powerlevel10k theme ---
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ -d "$P10K_DIR" ]; then
    echo "✓ Powerlevel10k is already installed"
else
    echo "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
    echo "✓ Powerlevel10k installed"
fi
echo ""

# --- 4. Install plugins ---
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# zsh-autosuggestions
if [ -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ]; then
    echo "✓ zsh-autosuggestions is already installed"
else
    echo "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
    echo "✓ zsh-autosuggestions installed"
fi

# zsh-syntax-highlighting
if [ -d "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" ]; then
    echo "✓ zsh-syntax-highlighting is already installed"
else
    echo "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
    echo "✓ zsh-syntax-highlighting installed"
fi
echo ""

# --- 5. Deploy configs ---
echo "Deploying shell configs..."

# .zshrc
if [ -f "$SHELL_CONFIG_DIR/zshrc" ]; then
    if [ -f "$HOME/.zshrc" ]; then
        # Only back up if the file differs from what we're deploying
        if ! diff -q "$HOME/.zshrc" "$SHELL_CONFIG_DIR/zshrc" >/dev/null 2>&1; then
            cp "$HOME/.zshrc" "$HOME/.zshrc.bak"
            echo "  Backed up existing ~/.zshrc to ~/.zshrc.bak"
        fi
    fi
    cp "$SHELL_CONFIG_DIR/zshrc" "$HOME/.zshrc"
    echo "✓ ~/.zshrc deployed"
else
    echo "✗ config/shell/zshrc not found in repo — skipping"
fi

# .p10k.zsh
if [ -f "$SHELL_CONFIG_DIR/p10k.zsh" ]; then
    if [ -f "$HOME/.p10k.zsh" ]; then
        if ! diff -q "$HOME/.p10k.zsh" "$SHELL_CONFIG_DIR/p10k.zsh" >/dev/null 2>&1; then
            cp "$HOME/.p10k.zsh" "$HOME/.p10k.zsh.bak"
            echo "  Backed up existing ~/.p10k.zsh to ~/.p10k.zsh.bak"
        fi
    fi
    cp "$SHELL_CONFIG_DIR/p10k.zsh" "$HOME/.p10k.zsh"
    echo "✓ ~/.p10k.zsh deployed"
else
    echo "✗ config/shell/p10k.zsh not found in repo — skipping"
fi
echo ""

# --- 6. Set default shell to zsh ---
CURRENT_SHELL=$(getent passwd "$(whoami)" | cut -d: -f7)
ZSH_PATH=$(command -v zsh)

if [ "$CURRENT_SHELL" = "$ZSH_PATH" ]; then
    echo "✓ Default shell is already zsh"
else
    echo "Setting default shell to zsh..."
    if chsh -s "$ZSH_PATH" 2>/dev/null; then
        echo "✓ Default shell set to zsh"
    else
        echo "  Could not set default shell automatically."
        echo "  Run manually: chsh -s $ZSH_PATH"
    fi
fi

echo ""
echo "=========================================="
echo "✓ Shell setup complete!"
echo "  Restart your terminal or run: exec zsh"
echo "=========================================="
