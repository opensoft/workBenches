#!/usr/bin/env bash
# Explicit host-side file selection/read. No credentials or GUI stderr are relayed.
set -uo pipefail
case "${1:-}" in
    path)
        if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v wslpath >/dev/null 2>&1; then
            wslpath -u "${2:-}"
        elif command -v cygpath >/dev/null 2>&1; then
            cygpath -u "${2:-}"
        else
            exit 3
        fi
        exit "$?" ;;
    read)
        target=${2:-}
        [[ "$target" == /* && -f "$target" && ! -L "$target" ]] || exit 2
        parent=$target
        while [[ "$parent" != / ]]; do
            [[ ! -L "$parent" ]] || exit 2
            parent=$(dirname "$parent")
        done
        head -c 1048577 -- "$target"
        exit "$?" ;;
    pick) ;;
    *) exit 2 ;;
esac
[[ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] || exit 3
system=$(uname -s)
if [[ "$system" == Darwin ]]; then
    command -v osascript >/dev/null 2>&1 || exit 3
    # AppleScript catches user cancellation separately from native errors.
    exec osascript -e 'try' -e 'POSIX path of (choose file with prompt "Choose an AI profile manifest" of type {"json"})' \
        -e 'on error number -128' -e 'return ""' -e 'end try' 2>/dev/null
    exit "$?"
elif [[ -n "${WSL_DISTRO_NAME:-}" || "$system" == MINGW* || "$system" == MSYS* || "$system" == CYGWIN* ]]; then
    command -v powershell.exe >/dev/null 2>&1 || exit 3
    exec powershell.exe -NoProfile -NonInteractive -STA -Command '
$ErrorActionPreference="Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = "Choose an AI profile manifest"
$dialog.Filter = "JSON profile manifests (*.json)|*.json"
$dialog.Multiselect = $false
$dialog.CheckFileExists = $true
try { if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::Write($dialog.FileName) } } finally { $dialog.Dispose() }
' 2>/dev/null
else
    [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || exit 3
    if command -v zenity >/dev/null 2>&1; then
        exec zenity --file-selection --title='Choose an AI profile manifest' --file-filter='JSON manifests | *.json *.JSON' 2>/dev/null
    elif command -v kdialog >/dev/null 2>&1; then
        exec kdialog --getopenfilename "$HOME/" '*.json' --title 'Choose an AI profile manifest' 2>/dev/null
    else
        exit 3
    fi
fi
