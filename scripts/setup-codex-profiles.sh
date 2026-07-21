#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/workbenches"
default_manifest="$config_dir/openai-profiles.json"
manifest="${CODEX_PROFILES_MANIFEST:-${CHATGPT_PROFILES_MANIFEST:-$default_manifest}}"
base="${CODEX_PROFILES_HOME:-${CHATGPT_PROFILES_HOME:-$HOME/.chatgpt-profiles}}"
template_config="${CODEX_PROFILE_CONFIG_TEMPLATE:-$HOME/.codex/config.toml}"

usage() {
  cat <<'EOF'
Usage: setup-codex-profiles.sh [--manifest PATH]

Creates isolated ChatGPT credential profiles for Codex CLI with conversation
history shared per family. The manifest stores profile names and login emails,
never OAuth credentials or API keys.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) manifest="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required." >&2; exit 1; }

mkdir -p "$config_dir"
if [[ ! -f "$manifest" ]]; then
  cp "$repo_dir/config/openai-profiles.example.json" "$manifest"
  chmod 600 "$manifest"
  echo "Created Codex profile manifest: $manifest"
fi

jq -e '
  .version == 1
  and (.profiles | type == "array")
  and all(.profiles[];
    (.name | length) > 0
    and (.family | length) > 0
    and (.email | length) > 0
    and ((.aliases // []) | type == "array")
    and all(.aliases[]?; type == "string" and length > 0)
  )
' "$manifest" >/dev/null

if [[ "$(realpath -m "$manifest")" != "$(realpath -m "$default_manifest")" ]]; then
  if [[ -L "$default_manifest" || ! -e "$default_manifest" ]]; then
    ln -sfn "$(realpath "$manifest")" "$default_manifest"
  else
    echo "Preserving existing default manifest: $default_manifest" >&2
    echo "Set CODEX_PROFILES_MANIFEST=$manifest when using codex-profile." >&2
  fi
fi

mkdir -p "$base/profiles" "$base/state"
chmod 700 "$base" "$base/profiles" "$base/state"

link_path() {
  local target="$1" link="$2"
  if [[ -L "$link" ]]; then
    ln -sfn "$target" "$link"
  elif [[ -e "$link" ]]; then
    echo "Preserving existing path: $link" >&2
  else
    ln -s "$target" "$link"
  fi
}

next_backup_path() {
  local path="$1" candidate suffix=1
  candidate="${path}.pre-shared-state"
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="${path}.pre-shared-state.$suffix"
    suffix=$((suffix + 1))
  done
  printf '%s\n' "$candidate"
}

share_state_directory() {
  local profile_path="$1" state_path="$2" target="$3" backup
  mkdir -p "$state_path"
  chmod 700 "$state_path"
  if [[ -L "$profile_path" ]]; then
    ln -sfn "$target" "$profile_path"
  elif [[ -d "$profile_path" ]]; then
    # Session rollout names contain UUIDs. Never overwrite an existing shared
    # rollout during migration, and retain the original tree as a recovery copy.
    cp -a -n "$profile_path/." "$state_path/"
    backup="$(next_backup_path "$profile_path")"
    mv "$profile_path" "$backup"
    ln -s "$target" "$profile_path"
  elif [[ -e "$profile_path" ]]; then
    echo "Cannot share Codex state directory over non-directory: $profile_path" >&2
    return 1
  else
    ln -s "$target" "$profile_path"
  fi
}

share_state_file() {
  local profile_path="$1" state_path="$2" target="$3" backup
  mkdir -p "$(dirname "$state_path")"
  touch "$state_path"
  chmod 600 "$state_path"
  if [[ -L "$profile_path" ]]; then
    ln -sfn "$target" "$profile_path"
  elif [[ -f "$profile_path" ]]; then
    # Prompt history and the portable session index are append-only JSONL.
    # Preserve every existing line while keeping a recovery copy.
    if [[ -s "$profile_path" ]]; then
      cat "$profile_path" >> "$state_path"
    fi
    backup="$(next_backup_path "$profile_path")"
    mv "$profile_path" "$backup"
    ln -s "$target" "$profile_path"
  elif [[ -e "$profile_path" ]]; then
    echo "Cannot share Codex state file over unsupported path: $profile_path" >&2
    return 1
  else
    ln -s "$target" "$profile_path"
  fi
}

configure_auth_storage() {
  local config="$1" tmp
  tmp="$(mktemp "$(dirname "$config")/.config.XXXXXX.tmp")"
  awk '
    BEGIN {
      print "forced_login_method = \"chatgpt\""
      print "cli_auth_credentials_store = \"file\""
      print ""
      in_root = 1
    }
    /^[[:space:]]*\[/ { in_root = 0 }
    in_root && /^[[:space:]]*(forced_login_method|cli_auth_credentials_store)[[:space:]]*=/ { next }
    { print }
  ' "$config" > "$tmp"
  python3 - "$tmp" <<'PY'
import pathlib
import sys
import tomllib

tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
PY
  chmod 600 "$tmp"
  mv -f "$tmp" "$config"
}

configure_tui_status_line() {
  local config="$1" tmp
  tmp="$(mktemp "$(dirname "$config")/.config.XXXXXX.tmp")"
  python3 - "$config" "$tmp" <<'PY'
import pathlib
import re
import sys
import tomllib

source = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
text = source.read_text()
lines = text.splitlines(keepends=True)

status_line = [
    "five-hour-limit",
    "weekly-limit",
    "used-tokens",
    "total-input-tokens",
    "total-output-tokens",
    "context-remaining",
    "model-with-reasoning",
    "git-branch",
    "pull-request-number",
    "permissions",
    "project-name",
]
rendered = ["status_line = [\n"]
rendered.extend(f'  "{item}",\n' for item in status_line)
rendered.extend(["]\n", "\n"])

table_pattern = re.compile(r"^\s*\[[^\]]+\]\s*(?:#.*)?$")
tui_pattern = re.compile(r"^\s*\[tui\]\s*(?:#.*)?$")
assignment_pattern = re.compile(r"^\s*status_line\s*=")

tui_start = next((i for i, line in enumerate(lines) if tui_pattern.match(line.rstrip("\r\n"))), None)
if tui_start is None:
    if lines and not lines[-1].endswith(("\n", "\r")):
        lines[-1] += "\n"
    if lines and lines[-1].strip():
        lines.append("\n")
    lines.extend(["[tui]\n", *rendered])
else:
    tui_end = next(
        (
            i
            for i in range(tui_start + 1, len(lines))
            if table_pattern.match(lines[i].rstrip("\r\n"))
        ),
        len(lines),
    )
    assignment_start = next(
        (
            i
            for i in range(tui_start + 1, tui_end)
            if assignment_pattern.match(lines[i])
        ),
        None,
    )
    if assignment_start is None:
        lines[tui_start + 1:tui_start + 1] = ["\n", *rendered]
    else:
        assignment_end = assignment_start + 1
        bracket_depth = (
            lines[assignment_start].count("[")
            - lines[assignment_start].count("]")
        )
        while bracket_depth > 0 and assignment_end < tui_end:
            bracket_depth += lines[assignment_end].count("[")
            bracket_depth -= lines[assignment_end].count("]")
            assignment_end += 1
        while assignment_end < tui_end and not lines[assignment_end].strip():
            assignment_end += 1
        lines[assignment_start:assignment_end] = rendered

updated = "".join(lines)
tomllib.loads(updated)
target.write_text(updated)
PY
  chmod 600 "$tmp"
  mv -f "$tmp" "$config"
}

while IFS=$'\t' read -r name family; do
  profile_dir="$base/profiles/$name"
  state_dir="$base/state/$family"
  mkdir -p "$profile_dir"
  chmod 700 "$profile_dir"
  mkdir -p "$state_dir"
  chmod 700 "$state_dir"

  email="$(jq -r --arg name "$name" '.profiles[] | select(.name == $name) | .email' "$manifest")"
  aliases="$(jq -c --arg name "$name" '.profiles[] | select(.name == $name) | (.aliases // [])' "$manifest")"
  profile_info="$profile_dir/.profile.json"
  profile_info_tmp="$(mktemp "$profile_dir/.profile.XXXXXX.tmp")"
  jq -n --arg name "$name" --arg family "$family" --arg email "$email" --argjson aliases "$aliases" \
    '{name: $name, family: $family, email: $email, aliases: $aliases}' > "$profile_info_tmp"
  chmod 600 "$profile_info_tmp"
  mv -f "$profile_info_tmp" "$profile_info"

  settings="$profile_dir/config.toml"
  if [[ ! -e "$settings" ]]; then
    if [[ -f "$template_config" ]]; then
      cp "$template_config" "$settings"
    else
      : > "$settings"
    fi
    chmod 600 "$settings"
  fi
  configure_auth_storage "$settings"
  configure_tui_status_line "$settings"

  for item in sessions archived_sessions; do
    share_state_directory \
      "$profile_dir/$item" "$state_dir/$item" "../../state/$family/$item"
  done
  for item in history.jsonl session_index.jsonl; do
    share_state_file \
      "$profile_dir/$item" "$state_dir/$item" "../../state/$family/$item"
  done

  for item in skills prompts policy; do
    [[ -e "$HOME/.codex/$item" ]] && link_path "../../../.codex/$item" "$profile_dir/$item"
  done
  for item in AGENTS.md tmux.conf; do
    [[ -e "$HOME/.codex/$item" ]] && link_path "../../../.codex/$item" "$profile_dir/$item"
  done
done < <(jq -r '.profiles[] | [.name, .family] | @tsv' "$manifest")

mkdir -p "$HOME/.local/bin"
ln -sfn "$repo_dir/scripts/codex-profile" "$HOME/.local/bin/codex-profile"
ln -sfn "$repo_dir/scripts/codex-profile" "$HOME/.local/bin/pcodex"
echo "Codex profiles configured under $base"
echo "Run: codex-profile list"
echo "Then: codex-profile login PROFILE"
