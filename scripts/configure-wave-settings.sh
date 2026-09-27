#!/usr/bin/env bash
# Apply the workBenches defaults to Wave Terminal's user settings.

set -euo pipefail

is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null
}

default_waveterm_config_dir() {
    if is_wsl; then
        local powershell_command
        local windows_profile
        local wsl_profile
        if command -v powershell.exe >/dev/null 2>&1; then
            powershell_command="powershell.exe"
        elif command -v pwsh.exe >/dev/null 2>&1; then
            powershell_command="pwsh.exe"
        else
            echo "Unable to resolve Windows Wave settings: powershell.exe or pwsh.exe is required under WSL." >&2
            return 1
        fi
        if ! command -v wslpath >/dev/null 2>&1; then
            echo "Unable to resolve Windows Wave settings: wslpath is required under WSL." >&2
            return 1
        fi
        windows_profile="$("$powershell_command" -NoProfile -Command '[Environment]::GetFolderPath("UserProfile")' 2>/dev/null | tr -d '\r' || true)"
        if [[ -z "$windows_profile" ]]; then
            echo "Unable to resolve the Windows user profile for Wave settings." >&2
            return 1
        fi
        wsl_profile="$(wslpath -u "$windows_profile" 2>/dev/null || true)"
        if [[ -z "$wsl_profile" ]]; then
            echo "Unable to convert the Windows user profile to a WSL path." >&2
            return 1
        fi
        printf '%s\n' "$wsl_profile/.config/waveterm"
        return
    fi

    if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        printf '%s\n' "$XDG_CONFIG_HOME/waveterm"
        return
    fi
    if [[ -z "${HOME:-}" ]]; then
        echo "HOME is required when resolving the native Linux Wave settings path." >&2
        return 1
    fi
    printf '%s\n' "$HOME/.config/waveterm"
}

waveterm_config_dir="${WAVETERM_CONFIG_DIR:-}"

usage() {
    cat <<'EOF'
Usage: configure-wave-settings.sh [options]

Options:
  --waveterm-config PATH   Wave config directory (default: Windows Wave config on WSL, otherwise XDG_CONFIG_HOME/waveterm)
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

if [[ -z "$waveterm_config_dir" ]]; then
    waveterm_config_dir="$(default_waveterm_config_dir)"
fi

mkdir -p "$waveterm_config_dir"
settings_file="$waveterm_config_dir/settings.json"

python3 - "$settings_file" <<'PY'
import json
import decimal
import os
import pathlib
import tempfile
import sys

settings_path = pathlib.Path(sys.argv[1])
if settings_path.is_symlink():
    raise SystemExit(f"{settings_path} is a symlink; refusing to replace it")

def reject_constant(value):
    raise ValueError(f"non-standard JSON constant: {value}")

def parse_finite_decimal(value):
    parsed = decimal.Decimal(value)
    if not parsed.is_finite():
        raise ValueError(f"non-finite JSON number: {value}")
    return parsed

original_text = None
if settings_path.exists():
    try:
        original_text = settings_path.read_text(encoding="utf-8")
        settings = json.loads(
            original_text,
            parse_constant=reject_constant,
            parse_float=parse_finite_decimal,
        )
    except (OSError, ValueError) as exc:
        raise SystemExit(f"{settings_path} could not be read as JSON: {exc}")
else:
    settings = {}

if not isinstance(settings, dict):
    raise SystemExit(f"{settings_path} must contain a JSON object")

defaults = {
    "app:disablectrlshiftdisplay": True,
    "term:copyonselect": True,
}
additions = {}
for key, value in defaults.items():
    if key not in settings:
        additions[key] = value

if additions or not settings_path.exists():
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    mode = settings_path.stat().st_mode & 0o7777 if settings_path.exists() else None
    if original_text is None:
        updated_text = json.dumps(defaults, indent=2, allow_nan=False) + "\n"
    else:
        stripped = original_text.rstrip()
        close_index = len(stripped) - 1
        before_close = original_text[:close_index]
        after_close = original_text[close_index:]
        content = before_close.rstrip()
        inner_whitespace = before_close[len(content):]
        rendered_additions = ",\n".join(
            f"  {json.dumps(key)}: {json.dumps(value, allow_nan=False)}"
            for key, value in additions.items()
        )
        separator = ",\n" if settings else "\n"
        closing_whitespace = inner_whitespace or "\n"
        updated_text = content + separator + rendered_additions + closing_whitespace + after_close

    fd, temporary_name = tempfile.mkstemp(prefix=f".{settings_path.name}.", dir=settings_path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as temporary:
            temporary.write(updated_text)
        if mode is not None:
            os.chmod(temporary_name, mode)
        os.replace(temporary_name, settings_path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass

settings.update(additions)

print(f"Wave settings defaults present: {settings_path}")
for key in defaults:
    print(f"  {key}={settings[key]!r}")
PY
