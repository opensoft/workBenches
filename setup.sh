#!/bin/bash

# Setup script for workBenches
# This script launches the interactive configuration manager

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"
source "$SCRIPT_DIR/scripts/lib/setup-prerequisites.sh"

# Cancellation during prerequisite/password prompts must stop the launcher.
trap 'exit 130' INT
trap 'exit 143' TERM

# ========================================
# LOGGING
# ========================================
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"
export WORKBENCHES_SETUP_LOG_FILE="$LOG_FILE"
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
        if ! workbenches_clone "$installer_repo" "$installer_dir" --depth 1; then
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

# Select components before profile/host changes and before any image build.
ensure_setup_dependencies || exit "$?"
selection_file="$(mktemp "${TMPDIR:-/tmp}/workbenches-selection.XXXXXX")" || exit 1
trap 'rm -f "$selection_file"' EXIT
"${SCRIPT_DIR}/scripts/interactive-setup.sh" --select-only "$selection_file" || exit "$?"
python3 "$SCRIPT_DIR/scripts/setup_selection.py" rows "$selection_file" >/dev/null || exit "$?"
if python3 "$SCRIPT_DIR/scripts/setup_selection.py" empty "$selection_file"; then
    echo "No components selected. Setup complete."
    exit 0
fi
selected_bench_paths="$(python3 "$SCRIPT_DIR/scripts/setup_selection.py" benches "$selection_file")" || exit "$?"
export WORKBENCHES_SELECTED_PROVIDERS="$(python3 "$SCRIPT_DIR/scripts/setup_selection.py" providers "$selection_file")"
export WORKBENCHES_PROFILE_PROVIDERS="$(python3 -c 'import os; print(",".join(p for p in os.environ["WORKBENCHES_SELECTED_PROVIDERS"].split(",") if p in ("claude", "openai")))')"

# Verify local prerequisites before host installers, account onboarding,
# credential recovery or any image build can run.
log_header "DOCKER CHECK"
if ! python3 "$SCRIPT_DIR/scripts/setup_selection.py" docker "$selection_file"; then
    echo "Host-tool removal does not require Docker."
elif ensure_docker; then
    :
else
    prerequisite_status=$?
    case "$prerequisite_status" in
        130|143) log_header "SETUP CANCELLED" ;;
        *) log_header "DOCKER PREREQUISITE FAILED" ;;
    esac
    exit "$prerequisite_status"
fi


# Enter in the TUI authorizes the selected changes. Account setup is opt-in.
python3 "$SCRIPT_DIR/scripts/setup_selection.py" review "$selection_file" || exit "$?"
export WORKBENCHES_AUTH_ROUTE=later
unset WORKBENCHES_AUTH_ROUTE_FILE
"${SCRIPT_DIR}/scripts/interactive-setup.sh" --dependencies-plan "$selection_file" || exit "$?"
if python3 "$SCRIPT_DIR/scripts/setup_selection.py" node "$selection_file"; then
    ensure_npm_install_location || exit "$?"
fi

# Reuse existing profiles. New account onboarding runs only through AI accounts.
run_ai_profile_setup() {
    if "${SCRIPT_DIR}/scripts/setup-ai-profiles.sh" "$@"; then
        return 0
    else
        local profile_status=$?
        case "$profile_status" in 130|143) exit "$profile_status" ;; esac
        echo "⚠ AI profile setup failed; provider sign-in remains available."
    fi
}
profile_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/workbenches"
if [[ -n "$WORKBENCHES_PROFILE_PROVIDERS" ]] && python3 - "$profile_config_dir" "$WORKBENCHES_PROFILE_PROVIDERS" <<'PROFILES'
import json, pathlib, sys
try:
    root = pathlib.Path(sys.argv[1])
    ready = all(json.loads((root / (provider + '-profiles.json')).read_text()).get('profiles')
                for provider in sys.argv[2].split(','))
except (OSError, ValueError, TypeError):
    ready = False
sys.exit(0 if ready else 1)
PROFILES
then
    # Reuse approved profile configuration without opening vaults or onboarding.
    echo "Reusing configured AI profiles."
    run_ai_profile_setup --apply-existing
fi
persist_npm_user_path

# Estate commands (openRepoShape, openRepoTools, park, resume, status) come from
# workBenches' own vendored pin and are placed by their own installers; see
# scripts/setup-estate-commands.sh. Best-effort, like the other host-user
# steps here: it never fails setup.sh. WORKBENCHES_SKIP_ESTATE_COMMANDS=1 skips it.
if [[ -n "$selected_bench_paths" ]] && [ -x "${SCRIPT_DIR}/scripts/setup-estate-commands.sh" ]; then
    log_header "ESTATE COMMANDS"
    "${SCRIPT_DIR}/scripts/setup-estate-commands.sh" || echo "⚠ Estate command install skipped or failed; continuing workBenches setup."
    echo ""
fi

# Organization workspace initialization runs only when selected in the TUI.

# The project command is authored in openRepoProject and distributed at a pin.
if [[ -n "$selected_bench_paths" ]] && command -v python3 >/dev/null 2>&1; then
    run_logged "PROJECT COMMAND" python3 -I "${SCRIPT_DIR}/scripts/setup-project-command.py" \
        || echo "Project command installation failed; see the refusal above."
fi

# Claude workflow setup is host-user state. The benches bind-mount ~/.claude, so
# seed it before any container build without overwriting existing user workflows.
# Claude account workflows are configured by the optional AI accounts step.

# Wave Terminal widgets are host-user state. Install them before any image
# builds so the desktop terminal shortcuts track the current checkout.
if python3 "$SCRIPT_DIR/scripts/setup_selection.py" rows "$selection_file" | grep -q $'wave\tinstall'; then install_wave_terminal_widgets; fi

# Ensure Layer 0 base image exists
log_header "LAYER 0 BUILD"
if [[ -z "$selected_bench_paths" ]]; then
    echo "No bench images selected; skipping Layer 0."
else
    python3 "${SCRIPT_DIR}/scripts/setup-bench-home.py" || exit "$?"
    if python3 "${SCRIPT_DIR}/scripts/shared-images.py" ensure base; then
        echo "Layer 0 is ready."
    else
        image_status=$?
        case "$image_status" in 130|143) exit "$image_status" ;; esac
        echo "Building workbench-base:latest from local sources..."
        "${SCRIPT_DIR}/base-image/build.sh" || { echo "✗ Layer 0 build failed"; exit 1; }
    fi
fi

# Call the interactive setup script
# NOTE: OpenTUI (TypeScript) UI is disabled — keyboard handling is broken and
# requires Bun upgrade. Using Bash UI directly. See docs/setup-input-troubleshooting.md
run_interactive_setup() {
    "${SCRIPT_DIR}/scripts/interactive-setup.sh" --apply-plan "$selection_file"
}

# Build the selected family layers before any bench setup consumes them.
log_header "LAYER 1 BUILDS"
BUILD_FAILED=false

if command -v jq >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/config/bench-config.json" ]; then
    has_dev=false
    has_sys=false
    has_bio=false

    while IFS= read -r bench_path; do
        case "$bench_path" in
            devBenches/*)   has_dev=true ;;
            sysBenches/*)   has_sys=true ;;
            bioBenches/*)   has_bio=true ;;
        esac
    done <<< "$selected_bench_paths"

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

if [ "$BUILD_FAILED" = false ]; then
    log_header "INTERACTIVE SETUP"
    if run_interactive_setup; then
        :
    else
        interactive_status=$?
        if [ "$interactive_status" -eq 130 ]; then
            log_header "SETUP CANCELLED"
        else
            log_header "INTERACTIVE SETUP FAILED"
            echo "✗ Interactive setup stopped (exit $interactive_status)."
        fi
        exit "$interactive_status"
    fi
else
    echo "Skipping component installation because a selected base layer failed."
fi

# ========================================
# SUMMARY
# ========================================
log_header "SETUP COMPLETE"

echo ""

# The workspace repository step (above) relays `openRepoTools wip init`'s own
# output byte for byte rather than summarising it, which is right for that
# step but means its most important lines -- an administrator block, or a
# precondition it stopped on -- can scroll off screen under eight more headers
# before a person ever reads this far. It leaves a marker file behind on
# anything but a clean run; surface it here, at the one place a person is
# still looking, rather than let it go unmentioned.
#
# RV-W7: checked BEFORE the BUILD_FAILED exit below, not after. A first-run
# Docker/Layer-1 build failure exits this script at that check, and a marker
# check placed after it would never run on that path -- silently dropping the
# one reminder a person most needs when the run did not go cleanly end to end.
workspace_repo_marker="${AGENT_PROTOCOL_ROOT:-$HOME/.agents}/.workspace-step-needs-attention"
if python3 "$SCRIPT_DIR/scripts/setup_selection.py" selected "$selection_file" workspace_repo && [ -e "$workspace_repo_marker" ]; then
    echo "⚠ Workspace repository step needs attention: grep -n \"WORKSPACE REPOSITORY\" \"$LOG_FILE\""
fi

if [ "$BUILD_FAILED" = true ]; then
    echo "✗ One or more Layer 1 builds failed."
    echo "  Full log: $LOG_FILE"
    exit 1
else
    echo "✓ Setup complete."
fi
echo "  Log saved to: $LOG_FILE"
