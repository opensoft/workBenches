#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/workbenches"
default_manifest="$config_dir/claude-profiles.json"
manifest="${CLAUDE_PROFILES_MANIFEST:-$default_manifest}"
base="${CLAUDE_PROFILES_HOME:-$HOME/.claude-profiles}"
default_model='claude-fable-5-1'
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

  prompt_email() {
    local prompt="$1" value
    while true; do
      read -r -p "$prompt: " value </dev/tty
      if [[ $value == *@*.* ]]; then
        printf '%s\n' "$value"
        return
      fi
      echo "Enter a valid email address." >/dev/tty
    done
  }

  slugify() {
    local value="$1"
    value=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
    printf '%s\n' "${value:-company}"
  }

  personal_email=$(prompt_email "Personal Claude login email")
  jq -n --arg email "$personal_email" '{
    version: 1,
    profiles: [{name: "personal", profilePath: "personal/personal", family: "personal", email: $email}]
  }' > "$tmp"

  read -r -p "Do you work for one or more companies using this workstation? [y/N]: " uses_work </dev/tty
  case "$uses_work" in
    [Yy]*)
      while true; do
        read -r -p "How many companies? " company_count </dev/tty
        [[ $company_count =~ ^[1-9][0-9]*$ ]] && break
        echo "Enter a whole number greater than zero." >/dev/tty
      done

      for ((index = 1; index <= company_count; index++)); do
        while true; do
          read -r -p "Company $index name: " company_name </dev/tty
          [[ -n $company_name ]] && break
          echo "Company name is required." >/dev/tty
        done
        company_email=$(prompt_email "Claude login email for $company_name")
        company_slug=$(slugify "$company_name")
        profile_name="work-$company_slug"
        if jq -e --arg name "$profile_name" '.profiles[] | select(.name == $name)' "$tmp" >/dev/null; then
          profile_name="$profile_name-$index"
        fi
        jq --arg name "$profile_name" --arg family "$company_slug" \
          --arg profile_path "$company_slug/xfactor/$profile_name" \
          --arg email "$company_email" --arg workspace "$company_name" '
          .profiles += [{
            name: $name,
            profilePath: $profile_path,
            family: $family,
            email: $email,
            workspace: $workspace
          }]
        ' "$tmp" > "$tmp.next"
        mv "$tmp.next" "$tmp"
      done
      ;;
  esac

  install -m 600 "$tmp" "$manifest"
fi

jq -e '
  .version == 1
  and (.profiles | type == "array")
  and ((.families // []) | type == "array")
  and all(.families[]?; type == "string" and test("^[a-z0-9][a-z0-9-]*$"))
  and all(.profiles[];
    (.name | length) > 0
    and (.family | test("^[a-z0-9][a-z0-9-]*$"))
    and (.email | length) > 0
    and ((.aliases // []) | type == "array")
    and all(.aliases[]?; type == "string" and length > 0)
    and ((.profilePath // .name) |
      type == "string"
      and length > 0
      and (startswith("/") | not)
      and (split("/") | all(.[]; length > 0 and . != "." and . != ".."))
    )
  )
' "$manifest" >/dev/null

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
while IFS= read -r family; do
  mkdir -p "$base/state/$family"
  if [[ "$family" == personal ]]; then
    mkdir -p "$base/profiles/personal"
  else
    mkdir -p "$base/profiles/$family"/{team,max,xfactor}
  fi
done < <(jq -r '[(.families[]?), .profiles[].family] | unique[]' "$manifest")
install -m 0755 "$repo_dir/base-image/files/claude-statusline-command.sh" \
  "$base/shared/statusline-command.sh"
# AND THE USAGE GUARD BESIDE IT — round-3 confirmation review 5192133162,
# non-blocking 5. `claude-profile`'s configure_profile_runtime looks for the
# guard at `$base/shared/usage-guard.sh` and then at
# `/usr/local/share/workbenches/claude/usage-guard.sh`, and sets `guard_ok`
# false when it finds neither — in which case the `UserPromptSubmit` entry is
# not written and the hook never runs. Nothing in this repository put the file
# in either place: the statusline is installed here and copied by
# `base-image/Dockerfile:184`, and `base-image/files/claude-usage-guard.sh` had
# no equivalent in either file (`grep -c 'claude-usage-guard'
# base-image/Dockerfile` = 0). That is PRE-EXISTING on `main` and not this PR's
# regression — but this is the PR that makes the guard load-bearing for a
# RATIFIED decision (Amendment 11(4)'s automatic swap), and a ratified swap that
# no profile ever wires is worth the one line that wires it.
#
# This is the HOST half. The container half is `base-image/Dockerfile`, which is
# not in this PR's remit; the PR body names the line it owes.
# A vendored source that is not there is SKIPPED rather than fatal, the same
# `[[ -f ]] || continue` the two vendoring loops below carry and for the same
# reason: this file runs on checkouts that predate the guard, and `set -euo
# pipefail` at the top of it turns one unguarded read of a missing source into a
# failed setup for every profile on the machine.
if [[ -f "$repo_dir/base-image/files/claude-usage-guard.sh" ]]; then
  install -m 0755 "$repo_dir/base-image/files/claude-usage-guard.sh" \
    "$base/shared/usage-guard.sh"
fi

link_path() {
  local target="$1" link="$2"
  local relative_target
  relative_target="$(realpath -m --relative-to="$(dirname "$link")" "$target")"
  if [[ -L "$link" ]]; then
    ln -sfn "$relative_target" "$link"
  elif [[ -e "$link" ]]; then
    echo "Preserving existing path (migration required): $link" >&2
  else
    ln -s "$relative_target" "$link"
  fi
}

# Bare `claude` and the `yolo` helper use ~/.claude rather than a named profile.
# Keep that compatibility path on the same renderer so its panel cannot drift.
default_claude_dir="${WORKBENCHES_DEFAULT_CLAUDE_HOME:-$HOME/.claude}"
mkdir -p "$default_claude_dir"
default_statusline="$default_claude_dir/statusline-command.sh"
if [[ -e "$default_statusline" && ! -L "$default_statusline" ]]; then
  default_statusline_backup="$default_statusline.pre-workbenches-shared"
  [[ -e "$default_statusline_backup" ]] || cp -p "$default_statusline" "$default_statusline_backup"
fi
default_statusline_relative="$(realpath -m --relative-to="$default_claude_dir" "$base/shared/statusline-command.sh")"
ln -sfn "$default_statusline_relative" "$default_statusline"

# lane-collision-protocol Amendment 9 adoption act 4b DELETES three writers
# from here, and nothing replaces them in this file:
#
#   * the `for skill in lane-swap` loop that installed SKILL.md into
#     "$base/shared/skills/lane-swap/" and into "$default_claude_dir/skills/
#     lane-swap/", together with the vendored copy it installed from
#     (base-image/files/claude/skills/lane-swap/SKILL.md);
#   * the `for command in swap` loop that installed swap.md into
#     "$base/shared/commands/" and into "$default_claude_dir/commands/",
#     together with the vendored copy it installed from
#     (base-image/files/claude/commands/swap.md). That loop was TRANSITIONAL
#     by its own comment, conditional on `openRepoTools --install` placing
#     `commands/swap.md` first: A11 Addendum 4 ruling 9 (ratified by Brett
#     Heap 2026-09-13T21:08:26Z, brettheap/new-workstation#20
#     issuecomment-5656154524) put that file on `--install`'s list, built in
#     `opensoft/openRepoTools#26` round 2, and the pin
#     (`devBenches/base-image/upstream-pin.yaml`, commit `8a36eb3`) landed it
#     here as `opensoft/workBenches#78` (merged `d17bd28`) — so the one
#     condition this loop's own comment set for its own deletion is met;
#   * the SessionStart ensure that appended Amendment 8(e)'s entry to
#     "$default_claude_dir/settings.json".
#
# `openRepoTools --install` owns all four of those paths (two skills, the one
# command, and the one settings entry) from Amendment 9's adoption act 3
# (clause (b), on A8 Addendum 2's ratified R-A8-5, and A11 Addendum 4 ruling 9
# for the command), so keeping any of them here would leave two writers of one
# path — the defect act 4b exists to close. The shared skills/agents/commands/
# rules directories are still created above, and the statusLine write below is
# untouched and still this script's.
#
# WHAT IS NOT DELETED: the launcher's own SessionStart ensure in
# base-image/files/claude-profile. R-A8-5(b) is ratified and `--install` never
# writes a PROFILE's settings.json at all — one path, one writer, in both
# halves.

default_settings="$default_claude_dir/settings.json"
if [[ -e "$default_settings" ]] && ! jq -e 'type == "object"' "$default_settings" >/dev/null 2>&1; then
  echo "Claude default settings are not valid JSON: $default_settings" >&2
  exit 1
fi
default_settings_tmp="$(mktemp "$default_claude_dir/.settings.XXXXXX.tmp")"
default_statusline_command="bash $default_statusline"
if [[ -f "$default_settings" ]]; then
  jq --arg command "$default_statusline_command" '
    .statusLine = {type: "command", command: $command, refreshInterval: 10}
  ' "$default_settings" > "$default_settings_tmp"
else
  jq -n --arg command "$default_statusline_command" '
    {statusLine: {type: "command", command: $command, refreshInterval: 10}}' \
    > "$default_settings_tmp"
fi
chmod 600 "$default_settings_tmp"
mv -f "$default_settings_tmp" "$default_settings"

while IFS=$'\t' read -r name family profile_path; do
  profile_dir="$base/profiles/$profile_path"
  legacy_profile_dir="$base/profiles/$name"
  state_dir="$base/state/$family"
  if [[ "$profile_path" != "$name" && -d "$legacy_profile_dir" && ! -e "$profile_dir" ]]; then
    mkdir -p "$(dirname "$profile_dir")"
    cp -a "$legacy_profile_dir" "$profile_dir"
  fi
  mkdir -p "$profile_dir" "$state_dir"
  metadata="$profile_dir/.claude.json"
  if [[ ! -e "$metadata" ]]; then
    printf '%s\n' '{"hasCompletedOnboarding":true}' > "$metadata"
    chmod 600 "$metadata"
  fi
  profile_info="$profile_dir/.profile.json"
  email="$(jq -r --arg name "$name" '.profiles[] | select(.name == $name) | .email' "$manifest")"
  aliases="$(jq -c --arg name "$name" '.profiles[] | select(.name == $name) | (.aliases // [])' "$manifest")"
  profile_info_tmp="$(mktemp "$profile_dir/.profile.XXXXXX.tmp")"
  jq -n --arg name "$name" --arg family "$family" --arg email "$email" \
    --arg profile_path "$profile_path" --argjson aliases "$aliases" \
    '{name: $name, profilePath: $profile_path, family: $family, email: $email, aliases: $aliases}' \
    > "$profile_info_tmp"
  chmod 600 "$profile_info_tmp"
  mv -f "$profile_info_tmp" "$profile_info"
  for item in projects file-history plans tasks todos; do mkdir -p "$state_dir/$item"; done
  touch "$state_dir/history.jsonl"
  chmod 600 "$state_dir/history.jsonl"
  for item in skills agents commands rules; do link_path "$base/shared/$item" "$profile_dir/$item"; done
  link_path "$base/shared/statusline-command.sh" "$profile_dir/statusline-command.sh"
  for item in projects file-history plans tasks todos; do link_path "$state_dir/$item" "$profile_dir/$item"; done
  link_path "$state_dir/history.jsonl" "$profile_dir/history.jsonl"

  settings="$profile_dir/settings.json"
  settings_tmp="$(mktemp "$profile_dir/.settings.XXXXXX.tmp")"
  statusline_command='bash "${CLAUDE_CONFIG_DIR}/statusline-command.sh"'
  if [[ -e "$settings" ]] && ! jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
    echo "Claude profile settings are not valid JSON: $settings" >&2
    rm -f "$settings_tmp"
    exit 1
  fi
  if [[ -f "$settings" ]]; then
    jq --arg command "$statusline_command" --arg model "$default_model" '
      .statusLine = {type: "command", command: $command, refreshInterval: 10}
      | .permissions = (.permissions // {})
      | .permissions.defaultMode = "bypassPermissions"
      | .effortLevel = (.effortLevel // "xhigh")
      | .model = (.model // $model)
    ' "$settings" > "$settings_tmp"
  else
    jq -n --arg command "$statusline_command" --arg model "$default_model" '{
      statusLine: {type: "command", command: $command, refreshInterval: 10},
      permissions: {defaultMode: "bypassPermissions"},
      effortLevel: "xhigh",
      model: $model
    }' > "$settings_tmp"
  fi
  chmod 600 "$settings_tmp"
  mv -f "$settings_tmp" "$settings"
done < <(jq -r '.profiles[] | [.name, .family, (.profilePath // .name)] | @tsv' "$manifest")

# Profiles retained from older manifests remain launchable through their local
# metadata. Preserve explicit selections and seed the current default only when
# a retained profile has no model configured.
while IFS= read -r -d '' settings; do
  if ! jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
    echo "Claude profile settings are not valid JSON: $settings" >&2
    exit 1
  fi
  settings_tmp="$(mktemp "$(dirname "$settings")/.settings.XXXXXX.tmp")"
  jq --arg model "$default_model" '.model = (.model // $model)' "$settings" > "$settings_tmp"
  chmod 600 "$settings_tmp"
  mv -f "$settings_tmp" "$settings"
done < <(find "$base/profiles" -mindepth 2 -type f -name settings.json -print0)

mkdir -p "$HOME/.local/bin"
ln -sfn "$repo_dir/scripts/claude-profile" "$HOME/.local/bin/claude-profile"
ln -sfn "$repo_dir/scripts/claude-profile" "$HOME/.local/bin/pclaude"
ln -sfn "$repo_dir/scripts/workbenches-mcp-sync" "$HOME/.local/bin/workbenches-mcp-sync"
echo "Claude profiles configured under $base"
echo "Run: claude-profile list"
echo "Then: claude-profile login PROFILE"
echo "Manage credentials: $repo_dir/scripts/check-ai-credentials.sh"
