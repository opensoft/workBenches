#!/usr/bin/env bash
# Apply the workBenches defaults to Wave Terminal's user settings.

set -euo pipefail

home_dir="${HOME:?HOME is required}"

is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null
}

default_waveterm_config_dir() {
    if is_wsl && command -v powershell.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
        local windows_profile
        local wsl_profile
        windows_profile="$(powershell.exe -NoProfile -Command '[Environment]::GetFolderPath("UserProfile")' 2>/dev/null | tr -d '\r' || true)"
        if [[ -n "$windows_profile" ]]; then
            wsl_profile="$(wslpath -u "$windows_profile" 2>/dev/null || true)"
            if [[ -n "$wsl_profile" ]]; then
                printf '%s\n' "$wsl_profile/.config/waveterm"
                return
            fi
        fi
    fi

    printf '%s\n' "$home_dir/.config/waveterm"
}

waveterm_config_dir="${WAVETERM_CONFIG_DIR:-$(default_waveterm_config_dir)}"

usage() {
    cat <<'EOF'
Usage: configure-wave-settings.sh [options]

Options:
  --waveterm-config PATH   Wave config directory (default: Windows Wave config on WSL, otherwise ~/.config/waveterm)
  -h, --help               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --waveterm-config)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "--waveterm-config requires a path" >&2
                exit 1
            fi
            waveterm_config_dir="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        --*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        *) echo "Unexpected argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "Wave settings setup skipped: python3 is not available." >&2
    exit 0
fi

mkdir -p "$waveterm_config_dir"
settings_file="$waveterm_config_dir/settings.json"

python3 - "$settings_file" <<'PY'
import json
import os
import pathlib
import tempfile
import sys

settings_path = pathlib.Path(sys.argv[1])
if settings_path.is_symlink():
    raise SystemExit(f"{settings_path} is a symlink; refusing to replace it")
if settings_path.exists():
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"{settings_path} could not be read as JSON: {exc}")
else:
    settings = {}

if not isinstance(settings, dict):
    raise SystemExit(f"{settings_path} must contain a JSON object")

defaults = {
    "app:disablectrlshiftdisplay": True,
    "term:copyonselect": True,
}
changed = False
for key, value in defaults.items():
    if key not in settings:
        settings[key] = value
        changed = True

if changed or not settings_path.exists():
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    mode = settings_path.stat().st_mode & 0o777 if settings_path.exists() else None
    fd, temporary_name = tempfile.mkstemp(prefix=f".{settings_path.name}.", dir=settings_path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as temporary:
            json.dump(settings, temporary, indent=2)
            temporary.write("\n")
        if mode is not None:
            os.chmod(temporary_name, mode)
        os.replace(temporary_name, settings_path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass

print(f"Wave settings defaults present: {settings_path}")
for key in defaults:
    print(f"  {key}={settings[key]!r}")
PY
