#!/bin/bash

# Setup script for workBenches
# This script launches the interactive configuration manager

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ========================================
# LOGGING
# ========================================
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"
export WORKBENCH_LOG_FILE="$LOG_FILE"

# Log helper: writes to log file only (does not affect stdout/stderr/stdin).
# We do NOT use exec+tee process substitution because it breaks stdin for
# interactive read commands in child scripts.
log_header() {
    echo "" >> "$LOG_FILE"
    echo "======================================" >> "$LOG_FILE"
    echo "[$1] $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "======================================" >> "$LOG_FILE"
}

# Log a command's output to both terminal and log file.
# Usage: run_logged "description" command args...
run_logged() {
    local desc="$1"; shift
    log_header "$desc"
    "$@" > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
    return ${PIPESTATUS[0]}
}

# Log session metadata
log_header "SETUP STARTED"
{
    echo "User: $(whoami)"
    echo "Host: $(hostname)"
    echo "PWD: $PWD"
    echo "Shell: $SHELL"
    [ -n "$WSL_DISTRO_NAME" ] && echo "WSL: $WSL_DISTRO_NAME"
} >> "$LOG_FILE"

# Clean up old logs (keep last 10)
ls -t "$LOG_DIR"/setup-*.log 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null

# Ensure Docker is installed and running
ensure_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker is not installed. It is required to build workBenches images."
        if [ -t 0 ]; then
            read -p "Attempt to install Docker now? [y/N]: " install_choice
            case "$install_choice" in
                [Yy]*)
                    if [ -f /etc/os-release ]; then
                        . /etc/os-release
                        OS=$ID
                    else
                        OS=$(uname -s)
                    fi
                    case "$OS" in
                        ubuntu|debian|pop)
                            echo "Running: sudo apt update && sudo apt install -y docker.io"
                            sudo apt update && sudo apt install -y docker.io || true
                            ;;
                        fedora|rhel|centos)
                            echo "Running: sudo dnf install -y docker"
                            sudo dnf install -y docker || true
                            ;;
                        alpine)
                            echo "Running: sudo apk add docker"
                            sudo apk add docker || true
                            ;;
                        Darwin|darwin|macos)
                            echo "Please install Docker Desktop for macOS:"
                            echo "  https://www.docker.com/products/docker-desktop/"
                            ;;
                        *)
                            echo "Please install Docker for your OS:"
                            echo "  https://docs.docker.com/get-docker/"
                            ;;
                    esac
                    ;;
                *)
                    ;;
            esac
        fi
        if ! command -v docker >/dev/null 2>&1; then
            echo "Docker is still not available. Please install it, then re-run ./setup.sh"
            exit 1
        fi
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "Docker is installed but not running."
        if command -v systemctl >/dev/null 2>&1; then
            echo "Try: sudo systemctl start docker"
        else
            echo "Please start Docker Desktop or your Docker daemon."
        fi
        exit 1
    fi
}

# Install or update Wave Terminal widgets for this workBenches checkout.
# This is best-effort because Wave is a desktop convenience, not a build
# prerequisite.
install_wave_terminal_widgets() {
    if [ "${WORKBENCHES_SKIP_WAVE_WIDGETS:-}" = "1" ]; then
        echo "Wave Terminal widget setup skipped by WORKBENCHES_SKIP_WAVE_WIDGETS=1."
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Wave Terminal widget setup skipped: python3 is not available."
        return 0
    fi

    local installer_repo="${WAVE_TERMINAL_INSTALLER_REPO:-https://github.com/opensoft/Install-Wave-Terminal.git}"
    local sibling_installer_dir
    sibling_installer_dir="$(cd "$SCRIPT_DIR/.." && pwd)/Install-Wave-Terminal"
    local installer_dir
    if [ -z "${WAVE_TERMINAL_INSTALLER_DIR:-}" ] && [ -x "$sibling_installer_dir/scripts/install-workbenches-widgets.sh" ]; then
        installer_dir="$sibling_installer_dir"
    else
        installer_dir="${WAVE_TERMINAL_INSTALLER_DIR:-$HOME/.cache/workbenches/Install-Wave-Terminal}"
    fi
    local installer_script="$installer_dir/scripts/install-workbenches-widgets.sh"
    local projects_root="${WAVE_PROJECTS_ROOT:-${PROJECTS_ROOT:-$HOME/projects}}"
    local wsl_connection="${WAVE_WSL_CONNECTION:-wsl://Ubuntu-24.04}"
    local font_size="${WAVE_WIDGET_FONT_SIZE:-16}"

    if [ ! -x "$installer_script" ]; then
        if [ -e "$installer_dir" ]; then
            echo "Wave Terminal widget setup skipped: $installer_dir exists but does not contain the installer."
            return 0
        fi

        if ! command -v git >/dev/null 2>&1; then
            echo "Wave Terminal widget setup skipped: git is not available."
            return 0
        fi

        mkdir -p "$(dirname "$installer_dir")"
        if ! git clone --depth 1 "$installer_repo" "$installer_dir"; then
            echo "Wave Terminal widget setup skipped: failed to clone $installer_repo."
            return 0
        fi
    elif [ -d "$installer_dir/.git" ] && command -v git >/dev/null 2>&1; then
        git -C "$installer_dir" pull --ff-only --quiet || \
            echo "Wave Terminal installer update skipped; using existing checkout at $installer_dir."
    fi

    "$installer_script" \
        --workbenches-root "$SCRIPT_DIR" \
        --projects-root "$projects_root" \
        --font-size "$font_size" \
        --wsl-connection "$wsl_connection" || {
            echo "Wave Terminal widget setup failed; continuing workBenches setup."
            return 0
        }
}

# Parse arguments
USERNAME=${1:-$(whoami)}
if [ "$USERNAME" = "--user" ]; then
    USERNAME="${2:-$(whoami)}"
fi

# Shell environment setup (zsh + Powerlevel10k + Oh My Zsh)
log_header "SHELL SETUP"
if [ -x "${SCRIPT_DIR}/scripts/setup-shell.sh" ]; then
    "${SCRIPT_DIR}/scripts/setup-shell.sh"
    echo ""
fi

# Claude workflow setup is host-user state. The benches bind-mount ~/.claude, so
# seed it before any container build without overwriting existing user workflows.
log_header "CLAUDE WORKFLOW SETUP"
if [ -x "${SCRIPT_DIR}/scripts/setup-claude-workflows.sh" ]; then
    "${SCRIPT_DIR}/scripts/setup-claude-workflows.sh" || echo "⚠ Claude workflow setup skipped or failed"
    echo ""
fi

# Workstation VPN setup is offered in the interactive selector so users can
# choose AmneziaVPN and 0dcloud independently.
log_header "VPN SETUP"
echo "VPN client setup is available from the interactive selector." >> "$LOG_FILE"

# Apply existing provider profiles or obtain consent and collect the user's
# work/personal ownership model on first setup. Standard provider credential
# homes are detected and preserved; credentials are never copied implicitly.
log_header "AI PROFILE SETUP"
profile_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/workbenches"
if find "$profile_config_dir" -maxdepth 1 -name '*-profiles.json' -print -quit 2>/dev/null | grep -q .; then
    "${SCRIPT_DIR}/scripts/setup-ai-profiles.sh" --apply-existing \
        || echo "⚠ Existing AI profile setup failed"
elif [ -t 0 ] && [ -t 1 ]; then
    "${SCRIPT_DIR}/scripts/setup-ai-profiles.sh" --interactive \
        || echo "⚠ Interactive AI profile setup failed"
else
    echo "AI profile onboarding skipped because no interactive terminal is available."
fi
echo ""

# Wave Terminal widgets are host-user state. Install them before any image
# builds so the desktop terminal shortcuts track the current checkout.
log_header "WAVE TERMINAL WIDGET SETUP"
install_wave_terminal_widgets
echo ""

# Docker prerequisite
log_header "DOCKER CHECK"
ensure_docker

# Ensure Layer 0 base image exists
log_header "LAYER 0 BUILD"
if ! docker image inspect "workbench-base:latest" >/dev/null 2>&1; then
    echo "Layer 0 image not found. Building workbench-base:latest..."
    "${SCRIPT_DIR}/base-image/build.sh" || { echo "✗ Layer 0 build failed"; exit 1; }
else
    echo "Layer 0 image (workbench-base:latest) already exists, skipping build."
fi

# Call the interactive setup script
# NOTE: OpenTUI (TypeScript) UI is disabled — keyboard handling is broken and
# requires Bun upgrade. Using Bash UI directly. See docs/setup-input-troubleshooting.md
run_interactive_setup() {
    "${SCRIPT_DIR}/scripts/interactive-setup.sh"
}

log_header "INTERACTIVE SETUP"
run_interactive_setup

# Build Layer 1 images for detected bench categories
log_header "LAYER 1 BUILDS"
BUILD_FAILED=false

if command -v jq >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/config/bench-config.json" ]; then
    has_dev=false
    has_sys=false
    has_bio=false

    while IFS= read -r bench_path; do
        [ -d "$SCRIPT_DIR/$bench_path" ] || continue
        case "$bench_path" in
            devBenches/*)   has_dev=true ;;
            sysBenches/*)   has_sys=true ;;
            bioBenches/*)   has_bio=true ;;
        esac
    done < <(jq -r '.benches | to_entries[] | .value.path // empty' "$SCRIPT_DIR/config/bench-config.json")

    if [ "$has_dev" = true ] && [ -x "$SCRIPT_DIR/devBenches/setup.sh" ]; then
        echo ""
        echo "Dev benches detected. Building Layer 1a base image..."
        "$SCRIPT_DIR/devBenches/setup.sh" --user "$USERNAME" || { echo "✗ Layer 1a (devBenches) build failed"; BUILD_FAILED=true; }
    fi

    if [ "$has_sys" = true ] && [ -x "$SCRIPT_DIR/sysBenches/setup.sh" ]; then
        echo ""
        echo "Sys benches detected. Building Layer 1b base image..."
        "$SCRIPT_DIR/sysBenches/setup.sh" --user "$USERNAME" || { echo "✗ Layer 1b (sysBenches) build failed"; BUILD_FAILED=true; }
    fi

    if [ "$has_bio" = true ] && [ -x "$SCRIPT_DIR/bioBenches/setup.sh" ]; then
        echo ""
        echo "Bio benches detected. Building Layer 1c base image..."
        "$SCRIPT_DIR/bioBenches/setup.sh" --user "$USERNAME" || { echo "✗ Layer 1c (bioBenches) build failed"; BUILD_FAILED=true; }
    fi
fi

# ========================================
# SUMMARY
# ========================================
log_header "SETUP COMPLETE"

echo ""
if [ "$BUILD_FAILED" = true ]; then
    echo "✗ One or more Layer 1 builds failed."
    echo "  Full log: $LOG_FILE"
    exit 1
else
    echo "✓ Setup complete."
fi
echo "  Log saved to: $LOG_FILE"
