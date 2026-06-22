#!/usr/bin/env bash
# Install/check Windows workstation tools from WSL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${WORKBENCH_LOG_FILE:-$SCRIPT_DIR/../logs/setup-windows-tools-$(date +%Y%m%d-%H%M%S).log}"
mkdir -p "$(dirname "$LOG_FILE")"

PI_NPM_PACKAGE="@earendil-works/pi-coding-agent"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null
}

run_powershell() {
    local command="$1"
    if command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$command" | tr -d '\r'
    elif command -v pwsh.exe >/dev/null 2>&1; then
        pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "$command" | tr -d '\r'
    else
        return 127
    fi
}

ps_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

windows_file_exists() {
    local path="$1"
    run_powershell "if (Test-Path -LiteralPath $(ps_quote "$path")) { 'yes' } else { 'no' }" 2>/dev/null | grep -q '^yes$'
}

windows_env_file_exists() {
    local env_name="$1"
    local suffix="$2"
    run_powershell "\$base = [Environment]::GetEnvironmentVariable($(ps_quote "$env_name")); if (\$base -and (Test-Path -LiteralPath (Join-Path \$base $(ps_quote "$suffix")))) { 'yes' } else { 'no' }" 2>/dev/null | grep -q '^yes$'
}

windows_command_exists() {
    local command="$1"
    run_powershell "if (Get-Command $(ps_quote "$command") -ErrorAction SilentlyContinue) { 'yes' } else { 'no' }" 2>/dev/null | grep -q '^yes$'
}

run_winget() {
    local args="$1"
    local ps
    ps="\$winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
if (-not \$winget) {
  \$alias = Join-Path \$env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
  if (Test-Path -LiteralPath \$alias) { \$winget = \$alias }
}
if (-not \$winget) {
  \$pkg = Get-ChildItem -Path (Join-Path \$env:ProgramFiles 'WindowsApps') -Filter winget.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if (\$pkg) { \$winget = \$pkg.FullName }
}
if (-not \$winget) {
  Write-Output 'winget-not-found'
  exit 127
}
& \$winget $args"
    run_powershell "$ps"
}

winget_install() {
    local id="$1"
    local name="$2"

    echo "  Installing $name with winget..."
    log "Installing $name with winget id=$id"
    if run_winget "install -e --id $(ps_quote "$id") --accept-package-agreements --accept-source-agreements"; then
        echo "  ✓ $name install command completed"
        return 0
    fi

    echo "  ⚠ Could not install $name automatically"
    echo "    winget package id: $id"
    return 1
}

install_vscode_extensions() {
    local failed=0

    if command -v code >/dev/null 2>&1; then
        echo "  Installing VS Code WSL and Dev Containers extensions..."
        code --install-extension ms-vscode-remote.remote-wsl >/dev/null 2>&1 || failed=1
        code --install-extension ms-vscode-remote.remote-containers >/dev/null 2>&1 || failed=1
    else
        echo "  VS Code installed; reopen WSL or run 'code .' once so the code shim is available."
        failed=1
    fi

    return "$failed"
}

install_vscode() {
    echo "Checking Visual Studio Code..."
    if command -v code >/dev/null 2>&1 ||
       windows_file_exists "C:\\Program Files\\Microsoft VS Code\\Code.exe" ||
       windows_env_file_exists "LOCALAPPDATA" "Programs\\Microsoft VS Code\\Code.exe"; then
        echo "  ✓ Visual Studio Code is installed"
        install_vscode_extensions || true
        return 0
    fi

    winget_install "Microsoft.VisualStudioCode" "Visual Studio Code" || return 1
    install_vscode_extensions || true
}

install_warp() {
    echo "Checking Warp Terminal..."
    if windows_file_exists "C:\\Program Files\\Warp\\Warp.exe" ||
       windows_env_file_exists "LOCALAPPDATA" "Programs\\Warp\\Warp.exe"; then
        echo "  ✓ Warp Terminal is installed"
        return 0
    fi

    winget_install "Warp.Warp" "Warp Terminal"
}

install_wave() {
    echo "Checking Wave Terminal..."
    if windows_file_exists "C:\\Program Files\\Wave\\Wave.exe" ||
       windows_env_file_exists "LOCALAPPDATA" "Programs\\waveterm\\Wave.exe" ||
       windows_env_file_exists "LOCALAPPDATA" "Programs\\Wave\\Wave.exe"; then
        echo "  ✓ Wave Terminal is installed"
        return 0
    fi

    winget_install "CommandLine.Wave" "Wave Terminal"
}

install_pi_terminal() {
    echo "Checking Pi Terminal..."
    if windows_command_exists "pi" || windows_env_file_exists "APPDATA" "npm\\pi.cmd"; then
        echo "  ✓ Pi Terminal is installed for Windows"
        return 0
    fi

    if windows_command_exists "npm"; then
        echo "  Installing Pi Terminal with Windows npm..."
        if run_powershell "npm install -g --ignore-scripts $(ps_quote "$PI_NPM_PACKAGE")"; then
            echo "  ✓ Pi Terminal installed for Windows"
            echo "    Run 'pi' from a project, then use /login to configure a provider."
            return 0
        fi
    fi

    if command -v npm >/dev/null 2>&1; then
        echo "  Windows npm was not available; installing Pi Terminal in WSL..."
        if npm install -g --ignore-scripts "$PI_NPM_PACKAGE"; then
            echo "  ✓ Pi Terminal installed in WSL"
            echo "    Run 'pi' from a project, then use /login to configure a provider."
            return 0
        fi
    fi

    echo "  ✗ Node.js/npm not found in Windows or WSL"
    echo "    Install Node.js 22+ on Windows, then rerun this setup."
    return 1
}

usage() {
    cat <<'USAGE'
Usage: setup-windows-tools.sh [vscode|warp|wave|pi_terminal|all]...

Installs Windows workstation tools from WSL using winget where available.
USAGE
}

main() {
    if ! is_wsl; then
        echo "This helper installs Windows apps from WSL. Use the Linux/manual installer path on non-WSL hosts."
        exit 2
    fi

    local tools=("$@")
    if [ "${#tools[@]}" -eq 0 ]; then
        tools=("all")
    fi

    local failed=0
    for tool in "${tools[@]}"; do
        case "$tool" in
            all)
                install_vscode || failed=1
                echo ""
                install_warp || failed=1
                echo ""
                install_wave || failed=1
                echo ""
                install_pi_terminal || failed=1
                ;;
            vscode) install_vscode || failed=1 ;;
            warp) install_warp || failed=1 ;;
            wave) install_wave || failed=1 ;;
            pi_terminal|pi) install_pi_terminal || failed=1 ;;
            -h|--help) usage; exit 0 ;;
            *)
                echo "Unknown tool: $tool"
                usage
                failed=1
                ;;
        esac
        echo ""
    done

    if [ "$failed" -eq 0 ]; then
        echo "✓ Windows workstation tool setup complete"
    else
        echo "⚠ Windows workstation tool setup completed with warnings"
        echo "  See: $LOG_FILE"
    fi
    exit "$failed"
}

main "$@"
