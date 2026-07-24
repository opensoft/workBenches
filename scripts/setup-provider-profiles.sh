#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
provider=""
manifest=""

usage() {
  echo "Usage: setup-provider-profiles.sh --provider {gemini|grok|glm} [--manifest PATH]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) provider="$2"; shift 2 ;;
    --manifest) manifest="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$provider" in
  gemini)
    filename=gemini-profiles.json
    base="${GEMINI_PROFILES_HOME:-$HOME/.gemini-profiles}"
    launchers=(gemini-profile pgemini)
    ;;
  grok)
    filename=grok-profiles.json
    base="${GROK_PROFILES_HOME:-$HOME/.grok-profiles}"
    if [[ -z "${GROK_PROFILES_HOME:-}" && -e "$base" && ! -w "$base" ]]; then
      base="${XDG_DATA_HOME:-$HOME/.local/share}/workbenches/grok-profiles"
      printf 'Default Grok profile root is not writable; using %s\n' "$base" >&2
    fi
    launchers=(grok-profile pgrok)
    ;;
  glm)
    filename=glm-profiles.json
    base="${GLM_PROFILES_HOME:-$HOME/.glm-profiles}"
    launchers=(glm-profile zai-profile pglm pzai)
    ;;
  *) usage >&2; exit 2 ;;
esac

manifest="${manifest:-${XDG_CONFIG_HOME:-$HOME/.config}/workbenches/$filename}"
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }
[[ -f "$manifest" ]] || { echo "Missing $provider profile manifest: $manifest" >&2; exit 1; }
jq -e '
  .version == 1
  and (.profiles | type == "array")
  and ((.families // []) | type == "array")
  and all(.families[]?; type == "string" and test("^[a-z0-9][a-z0-9-]*$"))
  and all(.profiles[];
    (.name | type == "string" and length > 0)
    and (.email | type == "string" and length > 0)
    and (.family | type == "string" and test("^[a-z0-9][a-z0-9-]*$"))
    and ((.aliases // []) | type == "array")
    and ((.profilePath // .name) |
      type == "string"
      and length > 0
      and (startswith("/") | not)
      and (split("/") | all(.[]; length > 0 and . != "." and . != ".."))
    )
  )
' "$manifest" >/dev/null

mkdir -p "$base/profiles" "$base/state" "$HOME/.local/bin"
while IFS= read -r family; do
  mkdir -p "$base/state/$family"
  if [[ "$family" == personal ]]; then
    mkdir -p "$base/profiles/personal"
  else
    mkdir -p "$base/profiles/$family"/{team,max,xfactor}
  fi
done < <(jq -r '[(.families[]?), .profiles[].family] | unique[]' "$manifest")
chmod 700 "$base" "$base/profiles"
while IFS=$'\t' read -r name email family profile_path aliases; do
  profile_dir="$base/profiles/$profile_path"
  legacy_profile_dir="$base/profiles/$name"
  if [[ "$profile_path" != "$name" && -d "$legacy_profile_dir" && ! -e "$profile_dir" ]]; then
    mkdir -p "$(dirname "$profile_dir")"
    cp -a "$legacy_profile_dir" "$profile_dir"
  fi
  mkdir -p "$profile_dir"
  chmod 700 "$profile_dir"
  metadata_tmp="$(mktemp "$profile_dir/.profile.XXXXXX.tmp")"
  jq -n --arg name "$name" --arg email "$email" --arg family "$family" \
    --arg profile_path "$profile_path" --argjson aliases "$aliases" \
    '{name: $name, profilePath: $profile_path, email: $email, family: $family, aliases: $aliases}' \
    > "$metadata_tmp"
  chmod 600 "$metadata_tmp"
  mv -f "$metadata_tmp" "$profile_dir/.profile.json"
  case "$provider" in
    gemini) mkdir -p "$profile_dir/.gemini" ;;
    glm) mkdir -p "$profile_dir/xdg"/{config,data,cache,state} ;;
  esac
done < <(jq -r '.profiles[] | [.name,.email,.family,(.profilePath // .name),((.aliases // []) | tojson)] | @tsv' "$manifest")

for launcher in "${launchers[@]}"; do
  ln -sfn "$repo_dir/base-image/files/provider-profile" "$HOME/.local/bin/$launcher"
done
printf '%s profiles configured under %s\n' "$provider" "$base"
