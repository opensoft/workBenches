#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/workbenches"
default_manifest="$config_dir/claude-profiles.json"
manifest="${CLAUDE_PROFILES_MANIFEST:-$default_manifest}"
base="${CLAUDE_PROFILES_HOME:-$HOME/.claude-profiles}"
interactive=false

usage() {
  cat <<'EOF'
Usage: setup-claude-profiles.sh [--interactive] [--manifest PATH]

Creates isolated Claude credential profiles with shared history per family.
The manifest stores profile names and login emails, never OAuth credentials.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interactive) interactive=true; shift ;;
    --manifest) manifest="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

mkdir -p "$config_dir"
if [[ ! -f "$manifest" ]]; then
  cp "$repo_dir/config/claude-profiles.example.json" "$manifest"
  chmod 600 "$manifest"
  echo "Created Claude profile manifest: $manifest"
fi

if [[ "$interactive" == true ]]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  cp "$manifest" "$tmp"
  while IFS=$'\t' read -r name email; do
    read -r -p "Claude email for $name [$email]: " answer </dev/tty || true
    [[ -n "${answer:-}" ]] || continue
    jq --arg name "$name" --arg email "$answer" \
      '(.profiles[] | select(.name == $name) | .email) = $email' "$tmp" > "$tmp.next"
    mv "$tmp.next" "$tmp"
  done < <(jq -r '.profiles[] | [.name, .email] | @tsv' "$manifest")
  install -m 600 "$tmp" "$manifest"
fi

jq -e '.version == 1 and (.profiles | type == "array") and all(.profiles[]; (.name|length)>0 and (.family|length)>0 and (.email|length)>0)' "$manifest" >/dev/null

# The launcher uses the default path. When setup is driven by a private
# source-of-truth manifest, link that path instead of copying private account
# inventory into the public workBenches checkout.
if [[ "$(realpath -m "$manifest")" != "$(realpath -m "$default_manifest")" ]]; then
  if [[ -L "$default_manifest" || ! -e "$default_manifest" ]]; then
    ln -sfn "$(realpath "$manifest")" "$default_manifest"
  else
    echo "Preserving existing default manifest: $default_manifest" >&2
    echo "Set CLAUDE_PROFILES_MANIFEST=$manifest when using claude-profile." >&2
  fi
fi

mkdir -p "$base/shared" "$base/state" "$base/profiles"
for item in skills agents commands rules; do mkdir -p "$base/shared/$item"; done

link_path() {
  local target="$1" link="$2"
  if [[ -L "$link" ]]; then
    ln -sfn "$target" "$link"
  elif [[ -e "$link" ]]; then
    echo "Preserving existing path (migration required): $link" >&2
  else
    ln -s "$target" "$link"
  fi
}

while IFS=$'\t' read -r name family; do
  profile_dir="$base/profiles/$name"
  state_dir="$base/state/$family"
  mkdir -p "$profile_dir" "$state_dir"
  metadata="$profile_dir/.claude.json"
  if [[ ! -e "$metadata" ]]; then
    printf '%s\n' '{"hasCompletedOnboarding":true}' > "$metadata"
    chmod 600 "$metadata"
  fi
  for item in projects file-history plans tasks todos; do mkdir -p "$state_dir/$item"; done
  touch "$state_dir/history.jsonl"
  chmod 600 "$state_dir/history.jsonl"
  for item in skills agents commands rules; do link_path "../../shared/$item" "$profile_dir/$item"; done
  for item in projects file-history plans tasks todos; do link_path "../../state/$family/$item" "$profile_dir/$item"; done
  link_path "../../state/$family/history.jsonl" "$profile_dir/history.jsonl"
done < <(jq -r '.profiles[] | [.name, .family] | @tsv' "$manifest")

mkdir -p "$HOME/.local/bin"
ln -sfn "$repo_dir/scripts/claude-profile" "$HOME/.local/bin/claude-profile"
echo "Claude profiles configured under $base"
echo "Run: claude-profile list"
echo "Then: claude-profile login PROFILE"
