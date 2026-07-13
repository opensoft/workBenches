#!/usr/bin/env bash
# Install/check workstation VPN clients and apply the 0dcloud TUN MTU patch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${WORKBENCH_LOG_FILE:-$SCRIPT_DIR/../logs/setup-vpn-$(date +%Y%m%d-%H%M%S).log}"
mkdir -p "$(dirname "$LOG_FILE")"

MTU="${WORKBENCHES_0DCLOUD_MTU:-1400}"
GSO_MAX_SIZE="${WORKBENCHES_0DCLOUD_GSO_MAX_SIZE:-1400}"
ODCLOUD_DOC_URL="https://help.0dcloud.top/zh/article/windows-b7pvuk/"
AMNEZIA_WINGET_ID="AmneziaVPN.AmneziaVPN"

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

windows_file_exists() {
    local path="$1"
    run_powershell "if (Test-Path -LiteralPath '$path') { 'yes' } else { 'no' }" 2>/dev/null | grep -q '^yes$'
}

usage() {
    cat <<'USAGE'
Usage: setup-vpn.sh [amnezia|0dcloud|patch|all]...

Installs/checks selected Windows VPN clients from WSL. Selecting 0dcloud also
applies the 0dcloud TUN MTU patch after the client check.
USAGE
}

install_windows_amnezia() {
    echo "Checking AmneziaVPN..."
    log "Checking AmneziaVPN"

    if windows_file_exists "C:\\Program Files\\AmneziaVPN\\AmneziaVPN.exe" ||
       windows_file_exists "C:\\Program Files\\AmneziaVPN.ORG\\AmneziaVPN\\AmneziaVPN.exe"; then
        echo "  ✓ AmneziaVPN is installed"
        return 0
    fi

    echo "  Installing AmneziaVPN with winget..."
    log "Installing AmneziaVPN with winget"
    if run_powershell "winget install -e --id $AMNEZIA_WINGET_ID --accept-package-agreements --accept-source-agreements"; then
        echo "  ✓ AmneziaVPN install command completed"
    else
        echo "  ⚠ Could not install AmneziaVPN automatically"
        echo "    Manual install: https://amnezia.org/downloads"
        return 1
    fi
}

install_windows_0dcloud() {
    echo "Checking 0dcloud..."
    log "Checking 0dcloud"

    if windows_file_exists "C:\\Program Files\\0dcloud\\0dcloud.exe"; then
        echo "  ✓ 0dcloud is installed"
        return 0
    fi

    local installer="${WORKBENCHES_0DCLOUD_INSTALLER:-}"
    if [ -n "$installer" ]; then
        echo "  Installing 0dcloud from WORKBENCHES_0DCLOUD_INSTALLER..."
        log "Installing 0dcloud from $installer"
        local ps_installer
        ps_installer="$(printf '%s' "$installer" | sed "s/'/''/g")"
        if run_powershell "Start-Process -FilePath '$ps_installer' -Wait"; then
            echo "  ✓ 0dcloud installer completed"
            return 0
        fi
        echo "  ⚠ 0dcloud installer did not complete successfully"
        return 1
    fi

    echo "  ⚠ 0dcloud is not installed and no local installer was provided"
    echo "    Download/install 0dcloud, then rerun this script:"
    echo "    $ODCLOUD_DOC_URL"
    echo "    Optional automation: WORKBENCHES_0DCLOUD_INSTALLER=/mnt/c/path/to/0dcloud.exe ./scripts/setup-vpn.sh"
    return 1
}

patch_0dcloud_mtu() {
    echo "Patching 0dcloud TUN MTU..."
    log "Patching 0dcloud TUN MTU to mtu=$MTU gso-max-size=$GSO_MAX_SIZE"

    local patch_script
    patch_script="\$ErrorActionPreference = 'Stop'
\$uri = 'http://127.0.0.1:9090/configs'
try {
  \$before = Invoke-RestMethod -Uri \$uri -TimeoutSec 3
} catch {
  Write-Output 'not-running'
  exit 2
}
\$body = @{ tun = @{ enable = \$true; mtu = $MTU; 'gso-max-size' = $GSO_MAX_SIZE } } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri \$uri -Method Patch -ContentType 'application/json' -Body \$body -TimeoutSec 5 | Out-Null
\$after = Invoke-RestMethod -Uri \$uri -TimeoutSec 3
Write-Output ('mtu=' + \$after.tun.mtu + ' gso-max-size=' + \$after.tun.'gso-max-size')"

    local output
    if output="$(run_powershell "$patch_script" 2>/dev/null)"; then
        echo "  ✓ 0dcloud TUN patched: $output"
        return 0
    fi

    if echo "${output:-}" | grep -q 'not-running'; then
        echo "  ⚠ 0dcloud is installed but not running; start it and rerun setup-vpn.sh"
    else
        echo "  ⚠ Could not patch 0dcloud MTU through the local controller"
    fi
    echo "    In 0dcloud/mihomo TUN settings, use MTU $MTU and GSO max size $GSO_MAX_SIZE."
    return 1
}

main() {
    echo "=========================================="
    echo "WorkBenches VPN Setup"
    echo "=========================================="
    echo ""

    if ! is_wsl; then
        echo "This installer currently automates Windows VPN setup from WSL."
        echo "Manual installs:"
        echo "  AmneziaVPN: https://amnezia.org/downloads"
        echo "  0dcloud:    $ODCLOUD_DOC_URL"
        exit 0
    fi

    local targets=("$@")
    if [ "${#targets[@]}" -eq 0 ]; then
        targets=("all")
    fi

    local failed=0
    local target
    for target in "${targets[@]}"; do
        case "$target" in
            all)
                install_windows_amnezia || failed=1
                echo ""
                install_windows_0dcloud || failed=1
                echo ""
                patch_0dcloud_mtu || failed=1
                ;;
            amnezia|amnezia_vpn|amneziavpn)
                install_windows_amnezia || failed=1
                ;;
            0dcloud|odcloud)
                install_windows_0dcloud || failed=1
                echo ""
                patch_0dcloud_mtu || failed=1
                ;;
            patch|patch_0dcloud_mtu)
                patch_0dcloud_mtu || failed=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown VPN setup target: $target"
                usage
                failed=1
                ;;
        esac
        echo ""
    done

    if [ "$failed" -eq 0 ]; then
        echo "✓ VPN setup complete"
    else
        echo "⚠ VPN setup completed with warnings"
        echo "  See: $LOG_FILE"
    fi
}

main "$@"
