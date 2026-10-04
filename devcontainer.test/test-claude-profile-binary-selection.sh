#!/usr/bin/env bash
# Profile launches use the newest locally installed native Claude Code binary.
set -euo pipefail

# Count the full suite, including native-selection and no-lane assertions.
assertions=0
assertion() { assertions=$((assertions + 1)); }

# A caller may itself be a claude-profile tmux child or lane. Neither the
# normal launches nor the explicit CLAUDE_BIN case should inherit that routing.
# Nor may it inherit an executable: a session this launcher started carries
# CLAUDE_BIN and CLAUDE_RESOLVED_BIN (opensoft/workBenches#119), and a launch
# below that meant to resolve would otherwise start the caller's own claude.
unset TMUX TMUX_PANE WORKBENCHES_CLAUDE_TMUX WORKBENCHES_CLAUDE_TMUX_CHILD \
  WORKBENCHES_CLAUDE_WINDOW WORKBENCHES_CLAUDE_WINDOW_ID \
  WORKBENCHES_CLAUDE_WINDOW_REF WORKBENCHES_TMUX_SESSION \
  WORKBENCHES_TMUX_PANE CLAUDE_LANE CLAUDE_NO_LANE CLAUDE_LANE_DIR \
  LANES_WORKSTATION LANES_HOST LANES_OS LANES_CONTAINER PROJECTS_ROOT \
  AGENT_PROTOCOL_ROOT CLAUDE_BIN CLAUDE_RESOLVED_BIN CLAUDE_VERIFIED_VERSION \
  CLAUDE_ALLOW_STALE WORKBENCHES_CLAUDE_CURRENT_BIN 2>/dev/null || true

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Physical, because the entry-point check below compares it with readlink -f:
# a checkout reached through a symlinked directory would otherwise fail it.
repo_root="$(cd "$script_dir/.." && pwd -P)"
launcher="${1:-$repo_root/base-image/files/claude-profile}"
# Absolute, because it is also linked into the fake PATH below: a relative
# argument would make that link dangle, and pclaude would then reach whatever
# claude-profile the host has installed instead of the one under test.
[[ "$launcher" == /* ]] || launcher="$PWD/$launcher"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for entry_point in claude-profile pclaude lclaude; do
  if [[ -e "$repo_root/scripts/$entry_point" ]]; then
    [[ "$(readlink -f "$repo_root/scripts/$entry_point")" == "$repo_root/base-image/files/$entry_point" ]] \
      || fail "host $entry_point entry point does not resolve to its launcher"; assertion
  fi
done

test_home="$test_root/home"
versions="$test_home/.local/share/claude/versions"
fake_bin="$test_root/bin"
profiles="$test_root/profiles"
mkdir -p "$versions" "$fake_bin" "$profiles/profiles/opensoft/team/team-002"

printf '%s\n' '{"profiles":[{"name":"team-002","email":"test@example.invalid","family":"testing","aliases":["team002"],"profilePath":"opensoft/team/team-002"}]}' > "$test_root/manifest.json"
printf '%s\n' '{"name":"team-002","family":"testing","email":"test@example.invalid"}' > "$profiles/profiles/opensoft/team/team-002/.profile.json"

printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$0" > "$LAUNCH_LOG"' 'printf "%s" "${WORKBENCHES_CLAUDE_LANE:-}" > "$IDENTITY_LOG"' 'printf "%s" "${CLAUDE_NO_LANE-<unset>}" > "$MODE_LOG"' \
  'if [[ -n "${REAL_GUARD:-}" ]]; then' \
  '  printf "{\"session_id\":\"profile-fixture\",\"cwd\":\"%s\",\"prompt\":\"check profile-only mode\"}\n" "$PROJECTS_ROOT/example" | "$REAL_GUARD" guard || exit "$?"' \
  'fi' > "$fake_bin/claude"
chmod +x "$fake_bin/claude"
cp "$fake_bin/claude" "$versions/2.1.9"
cp "$fake_bin/claude" "$versions/2.1.10"
cp "$fake_bin/claude" "$versions/2.0.999"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$CLAUDE_BIN" > "$LANE_LOG"' 'printf "%s\n" "$1" > "$LANE_NAME_LOG"' \
  'printf "CLAUDE_RESOLVED_BIN=%s\nCLAUDE_VERIFIED_VERSION=%s\n" "${CLAUDE_RESOLVED_BIN-<unset>}" "${CLAUDE_VERIFIED_VERSION-<unset>}" > "$LANE_ENV_LOG"' \
  'printf "%s" "${CLAUDE_NO_LANE-<unset>}" > "$LANE_MODE_LOG"' \
  'exit "${FAKE_LANE_STATUS:-0}"' \
  > "$fake_bin/lane-start"
chmod +x "$versions/2.1.9" "$versions/2.1.10" "$versions/2.0.999" "$fake_bin/lane-start"
if [[ -x "$repo_root/base-image/files/pclaude" ]]; then
  ln -s "$repo_root/base-image/files/pclaude" "$fake_bin/pclaude"
  ln -s "$repo_root/base-image/files/lclaude" "$fake_bin/lclaude"
else
  ln -s "$(command -v pclaude)" "$fake_bin/pclaude"
  ln -s "$(command -v lclaude)" "$fake_bin/lclaude"
fi
ln -s "$launcher" "$fake_bin/claude-profile"

common_env=(
  "HOME=$test_home"
  "PATH=$fake_bin:$PATH"
  "CLAUDE_PROFILES_HOME=$profiles"
  "CLAUDE_PROFILES_MANIFEST=$test_root/manifest.json"
  "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
  "WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS=0"
  "LAUNCH_LOG=$test_root/launch.log"
  "LANE_LOG=$test_root/lane.log"
  "LANE_NAME_LOG=$test_root/lane-name.log"
  "IDENTITY_LOG=$test_root/identity.log"
  "LANE_ENV_LOG=$test_root/lane-env.log"
  "MODE_LOG=$test_root/mode.log"
  "LANE_MODE_LOG=$test_root/lane-mode.log"
  "TMPDIR=$test_root"
  # The cases up to the claude-current section below are the #109 native
  # ordering, which is the launcher's fallback when no claude-current is
  # installed (openspec/changes/launch-current-claude). The seam names nothing,
  # so they stay that fallback on a host whose PATH carries a real resolver.
  "WORKBENCHES_CLAUDE_CURRENT_BIN=$test_root/no-claude-current"
)

launch() {
  env -u CLAUDE_BIN -u CLAUDE_LANE -u CLAUDE_NO_LANE -u CLAUDE_LANE_DIR \
    "${common_env[@]}" TMUX=fake-session "$launcher" "$@" >/dev/null
}

launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.10" ]] || fail 'newest numeric native version was not launched'; assertion
[[ "$(< "$test_root/mode.log")" == 1 ]] || fail 'bare Claude launch did not publish no-lane mode'; assertion

rm -f "$test_root/lane.log" "$test_root/launch.log" "$test_root/mode.log" "$test_root/identity.log"
env "${common_env[@]}" TMUX=fake-session CLAUDE_LANE=example-1 \
  WORKBENCHES_CLAUDE_LANE=example-1 "$fake_bin/pclaude" run team002 --resume fixture-session >/dev/null
[[ ! -e "$test_root/lane.log" ]] || fail 'bare pclaude invoked lane-start'; assertion
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.10" ]] || fail 'bare pclaude did not launch the selected Claude'; assertion
[[ ! -s "$test_root/identity.log" ]] || fail 'bare pclaude inherited lane identity'; assertion
[[ "$(< "$test_root/mode.log")" == 1 ]] || fail 'bare pclaude did not publish no-lane mode'; assertion
rm -f "$test_root/launch.log" "$test_root/mode.log"
env "${common_env[@]}" TMUX=fake-session CLAUDE_LANE=example-1 \
  WORKBENCHES_CLAUDE_LANE=example-1 PROJECTS_ROOT="$test_home/projects" \
  AGENT_PROTOCOL_ROOT="$test_root/missing-protocol" \
  REAL_GUARD="$repo_root/devBenches/base-image/files/openrepotools/lanes-edit.sh" \
  "$fake_bin/pclaude" run team002 --resume fixture-session >/dev/null
[[ -s "$test_root/launch.log" ]] || fail 'real vendored guard case did not launch Claude'; assertion
[[ "$(< "$test_root/mode.log")" == 1 ]] || fail 'real vendored guard case lost no-lane mode'; assertion
rm -f "$test_root/lane.log" "$test_root/lane-mode.log"
env "${common_env[@]}" TMUX=fake-session CLAUDE_LANE=example-1 \
  "$fake_bin/lclaude" run team002 --resume fixture-session >/dev/null
[[ "$(< "$test_root/lane.log")" == "$versions/2.1.10" ]] || fail 'lclaude did not enable lane handoff'; assertion
[[ "$(< "$test_root/lane-mode.log")" == '<unset>' ]] || fail 'lane handoff carried a guard exemption'; assertion
rm -f "$test_root/lane.log" "$test_root/lane-mode.log"
env "${common_env[@]}" TMUX=fake-session CLAUDE_LANE=example-1 CLAUDE_NO_LANE=1 \
  "$fake_bin/lclaude" run team002 --resume fixture-session >/dev/null
[[ "$(< "$test_root/lane.log")" == "$versions/2.1.10" ]] || fail 'lclaude inherited no-lane routing'; assertion
[[ "$(< "$test_root/lane-mode.log")" == '<unset>' ]] || fail 'lclaude inherited the profile session guard exemption'; assertion
rm -f "$test_root/lane.log" "$test_root/lane-mode.log"
env "${common_env[@]}" TMUX=fake-session CLAUDE_LANE=example-1 CLAUDE_NO_LANE=0 \
  "$launcher" run team002 --resume fixture-session >/dev/null
[[ "$(< "$test_root/lane.log")" == "$versions/2.1.10" ]] || fail 'unsupported no-lane marker changed routing'; assertion
[[ "$(< "$test_root/lane-mode.log")" == '<unset>' ]] || fail 'unsupported no-lane marker reached lane handoff'; assertion
rm -f "$test_root/lane.log" "$test_root/lane-mode.log"
env "${common_env[@]}" TMUX=fake-session \
  "$fake_bin/pclaude" --lane example-1 run team002 --resume fixture-session >/dev/null
[[ -s "$test_root/lane.log" ]] || fail 'explicit pclaude --lane did not call lane-start'; assertion
[[ "$(< "$test_root/lane-name.log")" == example-1 ]] || fail 'explicit pclaude --lane lost compatibility'; assertion
rm -f "$test_root/lane.log" "$test_root/lane-mode.log"
env "${common_env[@]}" TMUX=fake-session CLAUDE_NO_LANE=1 \
  "$fake_bin/pclaude" --lane example-1 run team002 --resume fixture-session >/dev/null
[[ -s "$test_root/lane.log" ]] || fail 'explicit pclaude --lane inherited no-lane routing'; assertion
[[ "$(< "$test_root/lane-mode.log")" == '<unset>' ]] || fail 'explicit pclaude --lane inherited the guard exemption'; assertion
rm -f "$test_root/lane.log" "$test_root/launch.log" "$test_root/mode.log" "$test_root/identity.log"
env "${common_env[@]}" TMUX=fake-session \
  "$fake_bin/lclaude" --no-lane --lane example-1 run team002 --resume fixture-session >/dev/null
[[ ! -e "$test_root/lane.log" ]] || fail '--no-lane did not override lclaude --lane'; assertion
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.10" ]] || fail '--no-lane did not launch the selected Claude'; assertion
[[ ! -s "$test_root/identity.log" ]] || fail '--no-lane kept lane identity'; assertion
[[ "$(< "$test_root/mode.log")" == 1 ]] || fail '--no-lane did not reach Claude'; assertion
rm -f "$test_root/launch.log" "$test_root/mode.log" "$test_root/identity.log"
env "${common_env[@]}" TMUX=fake-session \
  "$fake_bin/lclaude" --lane example-1 --no-lane run team002 --resume fixture-session >/dev/null
[[ ! -e "$test_root/lane.log" ]] || fail '--no-lane lost precedence after --lane'; assertion
[[ "$(< "$test_root/mode.log")" == 1 ]] || fail 'trailing --no-lane did not reach Claude'; assertion
[[ -s "$test_root/launch.log" ]] || fail 'trailing --no-lane did not launch Claude'; assertion

launch --lane example-1 run team002 --resume fixture-session
[[ "$(< "$test_root/lane.log")" == "$versions/2.1.10" ]] || fail 'lane-start did not receive newest native version'; assertion

cp "$fake_bin/claude" "$versions/2.1.11"
chmod +x "$versions/2.1.11"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.11" ]] || fail 'a version installed between launches was not selected'; assertion
rm "$versions/2.1.11"

cp "$fake_bin/claude" "$versions/2.1.9223372036854775808"
cp "$fake_bin/claude" "$versions/99999999999999999999999999999.0.0"
chmod +x "$versions/2.1.9223372036854775808" "$versions/99999999999999999999999999999.0.0"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/99999999999999999999999999999.0.0" ]] || fail 'oversized numeric version was not selected'; assertion
rm "$versions/99999999999999999999999999999.0.0"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.9223372036854775808" ]] || fail 'oversized patch version was not selected'; assertion
rm "$versions/2.1.9223372036854775808"
cp "$fake_bin/claude" "$versions/2.0001.00011"
chmod +x "$versions/2.0001.00011"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/2.0001.00011" ]] || fail 'leading zeroes changed numeric version order'; assertion
rm "$versions/2.0001.00011"

cp "$fake_bin/claude" "$versions/not-a-version"
cp "$fake_bin/claude" "$versions/2.1.99"
chmod +x "$versions/not-a-version"
chmod -x "$versions/2.1.99"
mkdir "$versions/9.9.9"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.10" ]] || fail 'invalid or nonexecutable entry was selected'; assertion

env -u CLAUDE_LANE -u CLAUDE_NO_LANE -u CLAUDE_LANE_DIR \
  "${common_env[@]}" TMUX=fake-session "CLAUDE_BIN=$fake_bin/claude" \
  "$launcher" run team002 --resume fixture-session >/dev/null
[[ "$(< "$test_root/launch.log")" == "$fake_bin/claude" ]] || fail 'explicit CLAUDE_BIN did not win'; assertion

# A running tmux server can have an older environment than this invocation.
# Exercise the interactive parent-to-child command with that stale value, and
# with the stale marker and version a server captured from an earlier session
# (opensoft/workBenches#119). `new-session -d` returns at once whatever its
# command later does, so the child's own status is recorded, not returned.
cat > "$fake_bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display-message) printf '%s\n' "${FAKE_TMUX_WINDOW:-example-1}" ;;
  new-session)
    for child_command; do :; done
    printf '%s\n' new-session > "$TMUX_LOG"
    env CLAUDE_BIN="$STALE_CLAUDE_BIN" CLAUDE_RESOLVED_BIN="${STALE_RESOLVED_BIN:-$STALE_CLAUDE_BIN}" \
      CLAUDE_VERIFIED_VERSION=0.0.1 CLAUDE_NO_LANE=1 CLAUDE_LANE=stale-1 bash -c "$child_command" \
      || printf 'child-exit %s\n' "$?" >> "$TMUX_LOG"
    ;;
  set-option|set-window-option) printf '%s\n' "$*" >> "${TMUX_OPTION_LOG:-/dev/null}" ;;
  attach-session) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/tmux"
rm -f "$test_root/lane.log"
env -u CLAUDE_LANE -u CLAUDE_NO_LANE -u CLAUDE_LANE_DIR \
  "${common_env[@]}" TMUX=fake-session \
  "$fake_bin/pclaude" run team002 --resume fixture-session >/dev/null
[[ ! -e "$test_root/lane.log" ]] || fail 'bare pclaude inferred the lane-named tmux window'; assertion
[[ ! -s "$test_root/identity.log" ]] || fail 'bare pclaude exported the tmux window as a lane'; assertion
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" stale > "$LAUNCH_LOG"' > "$fake_bin/stale-claude"
chmod +x "$fake_bin/stale-claude"
command_string=""
printf -v command_string '%q ' "$launcher" run team002 --resume fixture-session
env -u TMUX -u CLAUDE_LANE -u CLAUDE_LANE_DIR \
  "${common_env[@]}" CLAUDE_NO_LANE=1 "CLAUDE_BIN=$fake_bin/claude" \
  "STALE_CLAUDE_BIN=$fake_bin/stale-claude" "TMUX_LOG=$test_root/tmux.log" \
  script -q -e -c "$command_string" /dev/null >/dev/null
[[ "$(< "$test_root/tmux.log")" == new-session ]] || fail 'interactive tmux relaunch was not exercised'; assertion
[[ "$(< "$test_root/launch.log")" == "$fake_bin/claude" ]] || fail 'tmux child lost explicit CLAUDE_BIN override'; assertion
[[ "$(< "$test_root/mode.log")" == 1 ]] || fail 'profile tmux child lost no-lane mode'; assertion
env -u TMUX -u CLAUDE_BIN -u CLAUDE_LANE -u CLAUDE_LANE_DIR \
  "${common_env[@]}" CLAUDE_NO_LANE=1 \
  "STALE_CLAUDE_BIN=$fake_bin/stale-claude" "TMUX_LOG=$test_root/tmux.log" \
  script -q -e -c "$command_string" /dev/null >/dev/null
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.10" ]] || fail 'tmux server stale CLAUDE_BIN replaced newest native version'; assertion
rm -f "$test_root/lane.log" "$test_root/lane-name.log" "$test_root/lane-mode.log"
printf -v command_string '%q ' "$fake_bin/lclaude" run team002 --resume fixture-session
rm -f "$test_root/lane.log"
env -u TMUX -u CLAUDE_NO_LANE \
  "${common_env[@]}" CLAUDE_LANE=example-1 \
  "STALE_CLAUDE_BIN=$fake_bin/stale-claude" "TMUX_LOG=$test_root/tmux.log" \
  script -q -e -c "$command_string" /dev/null >/dev/null
[[ "$(< "$test_root/lane.log")" == "$versions/2.1.10" ]] || fail 'tmux child lost lclaude lane mode'; assertion
[[ "$(< "$test_root/lane-name.log")" == example-1 ]] || fail 'tmux child inherited a stale lane'; assertion
[[ "$(< "$test_root/lane-mode.log")" == '<unset>' ]] || fail 'lane tmux child kept the stale guard exemption'; assertion

rm -f "$test_root/lane.log" "$test_root/lane-mode.log" "$test_root/launch.log" "$test_root/mode.log" "$test_root/identity.log"
env "${common_env[@]}" TMUX=fake-session FAKE_TMUX_WINDOW=claude FAKE_LANE_STATUS=2 \
  "$fake_bin/lclaude" --lane example-1 run team002 --resume fixture-session >/dev/null
[[ "$(< "$test_root/lane.log")" == "$versions/2.1.10" ]] || fail 'fallback did not attempt lane-start'; assertion
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.10" ]] || fail 'fallback did not launch Claude'; assertion
[[ "$(< "$test_root/mode.log")" == 1 ]] || fail 'bare fallback after lane refusal did not publish no-lane mode'; assertion
[[ ! -s "$test_root/identity.log" ]] || fail 'bare fallback kept the refused lane identity'; assertion

mv "$versions" "$test_root/versions-removed"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$fake_bin/claude" ]] || fail 'PATH fallback failed without native versions'; assertion

mkdir "$versions"
cp "$fake_bin/claude" "$versions/2.1.99"
chmod -x "$versions/2.1.99"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$fake_bin/claude" ]] || fail 'PATH fallback failed with only unusable native versions'; assertion

# ---------------------------------------------------------------------------
# THE RESOLVER (opensoft/workBenches#119; openspec/changes/launch-current-claude,
# claude-profile-binary-selection as it MODIFIES it, design.md Decision 4). A
# stub claude-current stands in for opensoft/openRepoTools' command, at the
# contract this launcher calls: `--porcelain [--offline]` prints path=,
# version=, published= and status=, and exits 0 resolved, 1 no candidate at
# all, 2 refused as stale. It logs every call, so "once per launch", "offline
# for a launch that starts no session" and "never for a pin" are read back
# rather than assumed.
checks=0
ok() { checks=$((checks + 1)); }

stub_current="$test_root/current/claude-current"
user_copy="$test_root/installs/user/bin/claude"
system_copy="$test_root/installs/system/claude"
mkdir -p "$test_root/current" "$test_root/installs/user/bin" "$test_root/installs/system" \
  "$test_root/refusing-bin"
cat > "$stub_current" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURRENT_LOG"
printf 'CLAUDE_ALLOW_STALE=%s\n' "${CLAUDE_ALLOW_STALE-<unset>}" > "$CURRENT_ENV_LOG"
case "${STUB_EXIT:-0}" in
  0)
    printf 'path=%s\nversion=%s\npublished=%s\nstatus=%s\n' \
      "$STUB_PATH" "$STUB_VERSION" "${STUB_PUBLISHED-}" "$STUB_STATE"
    printf 'claude-current: claude %s (%s) at %s\n' "$STUB_VERSION" "$STUB_SAYS" "$STUB_PATH" >&2
    ;;
  1) printf '%s\n' 'claude-current: no runnable Claude Code candidate' >&2 ;;
  2) printf '%s\n' 'claude-current: REFUSED: claude 2.1.280 is behind npm 2.1.284; fix: openRepoTools --install' >&2 ;;
  *) printf '%s\n' 'claude-current: usage error' >&2 ;;
esac
exit "${STUB_EXIT:-0}"
EOF
# Two installed copies, each started by ABSOLUTE PATH: the user's npm copy and
# the image's. Each logs how it was started and the three hand-off names.
for copy in "$user_copy" "$system_copy"; do
  cat > "$copy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0" > "$LAUNCH_LOG"
printf '%s\n' "$*" > "$CLAUDE_ARGS_LOG"
printf 'CLAUDE_BIN=%s\nCLAUDE_RESOLVED_BIN=%s\nCLAUDE_VERIFIED_VERSION=%s\n' \
  "${CLAUDE_BIN-<unset>}" "${CLAUDE_RESOLVED_BIN-<unset>}" "${CLAUDE_VERIFIED_VERSION-<unset>}" > "$CLAUDE_ENV_LOG"
EOF
done
# A lane-start that refuses the lane (its own status 2) and records what it was handed.
cat > "$test_root/refusing-bin/lane-start" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$CLAUDE_BIN" > "$LANE_LOG"
printf 'CLAUDE_RESOLVED_BIN=%s\nCLAUDE_VERIFIED_VERSION=%s\n' \
  "${CLAUDE_RESOLVED_BIN-<unset>}" "${CLAUDE_VERIFIED_VERSION-<unset>}" > "$LANE_ENV_LOG"
exit 2
EOF
chmod +x "$stub_current" "$user_copy" "$system_copy" "$test_root/refusing-bin/lane-start"
# The image's copy is FIRST ON PATH: the two-installs hazard of #119 itself.
rm -f "$fake_bin/claude"
ln -s "$system_copy" "$fake_bin/claude"

current_env=(
  "WORKBENCHES_CLAUDE_CURRENT_BIN=$stub_current"
  "WORKBENCHES_LANES_EDIT_BIN=$test_root/no-lanes-edit"
  "CURRENT_LOG=$test_root/current.log"
  "CURRENT_ENV_LOG=$test_root/current-env.log"
  "CLAUDE_ENV_LOG=$test_root/claude-env.log"
  "CLAUDE_ARGS_LOG=$test_root/claude-args.log"
  "STUB_PATH=$user_copy" "STUB_VERSION=2.1.284" "STUB_PUBLISHED=2.1.284"
  "STUB_STATE=verified" "STUB_SAYS=verified against npm 2.1.284"
)
reset_case_logs() {
  rm -f "$test_root/launch.log" "$test_root/claude-env.log" "$test_root/claude-args.log" \
    "$test_root/current.log" "$test_root/current-env.log" "$test_root/lane.log" \
    "$test_root/lane-env.log" "$test_root/stderr.log" "$test_root/tmux.log" \
    "$test_root/tmux-option.log"
}
# resolve_case <env assignment>... -- <command>...: stdin is not a terminal, so
# nothing re-execs into tmux; the status is kept in case_status.
resolve_case() {
  local -a assignments=()
  while [[ $# -gt 0 && "$1" != -- ]]; do assignments+=("$1"); shift; done
  shift
  reset_case_logs
  set +e
  env "${common_env[@]}" TMUX=fake-session "${current_env[@]}" ${assignments[@]+"${assignments[@]}"} \
    "$@" >/dev/null 2>"$test_root/stderr.log" </dev/null
  case_status=$?
  set -e
}
# tmux_case <env assignment>... -- <command>...: the same launch from a terminal
# outside tmux, so the parent re-execs into the fake tmux's session.
tmux_case() {
  local -a assignments=() command=()
  local command_string=""
  while [[ $# -gt 0 && "$1" != -- ]]; do assignments+=("$1"); shift; done
  shift
  command=("$@")
  printf -v command_string '%q ' "${command[@]}"
  reset_case_logs
  set +e
  env -u TMUX "${common_env[@]}" "${current_env[@]}" ${assignments[@]+"${assignments[@]}"} \
    "STALE_CLAUDE_BIN=$fake_bin/stale-claude" "TMUX_LOG=$test_root/tmux.log" \
    "TMUX_OPTION_LOG=$test_root/tmux-option.log" \
    script -q -e -c "$command_string" /dev/null >/dev/null 2>&1
  case_status=$?
  set -e
}
current_calls() {
  if [[ -f "$test_root/current.log" ]]; then wc -l < "$test_root/current.log" | tr -d ' '; else printf '0\n'; fi
}
has_line() { grep -Fxq -- "$1" "$test_root/$2"; }
stderr_count() { grep -cF -- "$1" "$test_root/stderr.log" || true; }
stderr_lines() { wc -l < "$test_root/stderr.log" | tr -d ' '; }
bare=("$fake_bin/pclaude" run team002 --resume fixture-session)
session_args='--allow-dangerously-skip-permissions --dangerously-skip-permissions --permission-mode bypassPermissions --resume fixture-session'

# VERIFIED. The session starts on the absolute path the resolver printed, not
# the image copy PATH finds first; the resolver's own line is the launch's one
# line; the session inherits the marked pair and never the version.
resolve_case -- "${bare[@]}"
[[ "$case_status" -eq 0 ]] || fail "verified: the launch exited $case_status"; ok; assertion
[[ "$(< "$test_root/launch.log")" == "$user_copy" ]] || fail 'verified: the path claude-current printed was not the one started'; ok; assertion
[[ "$(< "$test_root/claude-args.log")" == "$session_args" ]] || fail 'verified: the Claude arguments changed'; ok; assertion
[[ "$(< "$test_root/current.log")" == --porcelain ]] || fail "verified: claude-current was not asked once, with --porcelain alone ($(cat "$test_root/current.log"))"; ok; assertion
[[ "$(stderr_count 'claude 2.1.284 (verified against npm 2.1.284)')" -eq 1 ]] || fail 'verified: what launched was not said exactly once'; ok; assertion
[[ "$(stderr_lines)" -eq 1 ]] || fail "verified: the launcher added lines of its own ($(cat "$test_root/stderr.log"))"; ok; assertion
has_line "CLAUDE_BIN=$user_copy" claude-env.log || fail 'verified: the session did not inherit CLAUDE_BIN'; ok; assertion
has_line "CLAUDE_RESOLVED_BIN=$user_copy" claude-env.log || fail 'verified: the session did not inherit the resolution marker'; ok; assertion
has_line 'CLAUDE_VERIFIED_VERSION=<unset>' claude-env.log || fail 'verified: CLAUDE_VERIFIED_VERSION reached the session'; ok; assertion

# AHEAD. A copy newer than npm still launches; the resolver says it is ahead.
resolve_case "STUB_PATH=$system_copy" STUB_VERSION=2.1.290 STUB_STATE=ahead "STUB_SAYS=ahead of npm 2.1.284" -- "${bare[@]}"
[[ "$case_status" -eq 0 && "$(< "$test_root/launch.log")" == "$system_copy" ]] || fail 'ahead: the newer copy did not launch'; ok; assertion
[[ "$(stderr_count 'ahead of npm 2.1.284')" -eq 1 ]] || fail 'ahead: the launch did not say it is ahead of npm'; ok; assertion

# UNVERIFIED. npm could not be read: the highest installed copy starts anyway.
resolve_case STUB_STATE=unverified STUB_PUBLISHED= "STUB_SAYS=UNVERIFIED: could not reach npm" -- "${bare[@]}"
[[ "$case_status" -eq 0 && "$(< "$test_root/launch.log")" == "$user_copy" ]] || fail 'unverified: offline did not launch'; ok; assertion
[[ "$(stderr_count 'UNVERIFIED: could not reach npm')" -eq 1 ]] || fail 'unverified: the launch did not say UNVERIFIED'; ok; assertion

# STALE, REFUSED. Nothing starts, nothing is handed over, and the resolver's
# refusal is the only line: the launcher prints no copy of its own.
resolve_case STUB_EXIT=2 -- "${bare[@]}"
[[ "$case_status" -eq 2 ]] || fail "stale: the launch exited $case_status, not the refusal"; ok; assertion
[[ ! -e "$test_root/launch.log" ]] || fail 'stale: a stale Claude was started'; ok; assertion
[[ "$(stderr_count 'REFUSED: claude 2.1.280 is behind npm 2.1.284')" -eq 1 && "$(stderr_lines)" -eq 1 ]] \
  || fail "stale: the refusal was not printed exactly once ($(cat "$test_root/stderr.log"))"; ok; assertion
resolve_case STUB_EXIT=2 -- "$launcher" --lane example-1 run team002 --resume fixture-session
[[ "$case_status" -eq 2 && ! -e "$test_root/lane.log" ]] || fail 'stale: lane-start was handed a refused launch'; ok; assertion

# STALE, ALLOWED. CLAUDE_ALLOW_STALE=1 reaches the resolver, which starts it.
resolve_case CLAUDE_ALLOW_STALE=1 STUB_STATE=stale STUB_VERSION=2.1.280 "STUB_SAYS=STALE, started under CLAUDE_ALLOW_STALE=1" -- "${bare[@]}"
[[ "$case_status" -eq 0 && "$(< "$test_root/launch.log")" == "$user_copy" ]] || fail 'stale allowed: the launch did not start'; ok; assertion
has_line 'CLAUDE_ALLOW_STALE=1' current-env.log || fail 'stale allowed: the escape did not reach claude-current'; ok; assertion

# NO CANDIDATE AT ALL: the words and the status it always had.
resolve_case STUB_EXIT=1 -- "${bare[@]}"
[[ "$case_status" -eq 1 && ! -e "$test_root/launch.log" ]] || fail "no candidate: exited $case_status"; ok; assertion
has_line 'Claude CLI not found.' stderr.log || fail 'no candidate: Claude CLI not found. was not printed'; ok; assertion

# A RESOLVER THAT ANSWERS OUTSIDE ITS CONTRACT starts nothing.
resolve_case STUB_EXIT=64 -- "${bare[@]}"
[[ "$case_status" -eq 2 && ! -e "$test_root/launch.log" ]] || fail 'resolver usage error: a Claude was started'; ok; assertion
[[ "$(stderr_count 'claude-current exited 64')" -eq 1 ]] || fail 'resolver usage error: the status was not named'; ok; assertion
resolve_case STUB_PATH=relative/claude -- "${bare[@]}"
[[ "$case_status" -eq 2 && ! -e "$test_root/launch.log" ]] || fail 'relative path: a Claude was started'; ok; assertion
[[ "$(stderr_count 'without naming an executable absolute path')" -eq 1 ]] || fail 'relative path: the refusal was not said'; ok; assertion

# AN INHERITED RESOLUTION IS NOT A PIN: the pair an earlier launch exported,
# with a stale version beside it, is resolved again and the version dropped.
resolve_case "CLAUDE_BIN=$system_copy" "CLAUDE_RESOLVED_BIN=$system_copy" CLAUDE_VERIFIED_VERSION=0.0.1 -- "${bare[@]}"
[[ "$(current_calls)" -eq 1 && "$(< "$test_root/launch.log")" == "$user_copy" ]] || fail 'inherited: the inherited pair was reused'; ok; assertion
has_line 'CLAUDE_VERIFIED_VERSION=<unset>' claude-env.log || fail 'inherited: a stale CLAUDE_VERIFIED_VERSION reached the session'; ok; assertion

# AN OPERATOR PIN: verbatim, no update check, no notice, and no marker left.
resolve_case "CLAUDE_BIN=$system_copy" -- "${bare[@]}"
[[ ! -e "$test_root/current.log" ]] || fail 'pin: claude-current was asked'; ok; assertion
[[ "$(< "$test_root/launch.log")" == "$system_copy" && ! -s "$test_root/stderr.log" ]] || fail 'pin: the pin was not started silently'; ok; assertion
resolve_case "CLAUDE_BIN=$system_copy" "CLAUDE_RESOLVED_BIN=$user_copy" -- "${bare[@]}"
[[ ! -e "$test_root/current.log" && "$(< "$test_root/launch.log")" == "$system_copy" ]] || fail 'pin beside another marker: not honoured'; ok; assertion
has_line 'CLAUDE_RESOLVED_BIN=<unset>' claude-env.log || fail 'pin: a marker for another copy reached the session'; ok; assertion

# A LAUNCH THAT STARTS NO SESSION resolves offline and never waits on npm.
resolve_case -- "$fake_bin/pclaude" run team002 --version
[[ "$(< "$test_root/current.log")" == '--porcelain --offline' ]] || fail "--version: not resolved offline ($(cat "$test_root/current.log"))"; ok; assertion
resolve_case -- "$launcher" status team002
[[ "$(< "$test_root/current.log")" == '--porcelain --offline' ]] || fail 'status: not resolved offline'; ok; assertion
[[ "$(< "$test_root/claude-args.log")" == 'auth status --text' && "$(< "$test_root/launch.log")" == "$user_copy" ]] \
  || fail 'status: auth status did not run on the resolved path'; ok; assertion
resolve_case -- "$launcher" --no-lane run team002 mcp list
[[ "$(< "$test_root/current.log")" == '--porcelain --offline' ]] || fail 'mcp: not resolved offline'; ok; assertion

# THE LANE-START HAND-OFF carries the path, the marker and the version.
resolve_case -- "$launcher" --lane example-1 run team002 --resume fixture-session
[[ "$(current_calls)" -eq 1 && "$(< "$test_root/lane.log")" == "$user_copy" ]] || fail 'hand-off: lane-start did not get the resolved path'; ok; assertion
has_line "CLAUDE_RESOLVED_BIN=$user_copy" lane-env.log || fail 'hand-off: lane-start did not get CLAUDE_RESOLVED_BIN'; ok; assertion
has_line 'CLAUDE_VERIFIED_VERSION=2.1.284' lane-env.log || fail 'hand-off: lane-start did not get CLAUDE_VERIFIED_VERSION'; ok; assertion
resolve_case "CLAUDE_BIN=$system_copy" -- "$launcher" --lane example-1 run team002 --resume fixture-session
[[ ! -e "$test_root/current.log" && "$(< "$test_root/lane.log")" == "$system_copy" ]] || fail 'hand-off: the pin was not handed verbatim'; ok; assertion
has_line 'CLAUDE_RESOLVED_BIN=<unset>' lane-env.log && has_line 'CLAUDE_VERIFIED_VERSION=<unset>' lane-env.log \
  || fail 'hand-off: a pin was handed as a resolution'; ok; assertion
# ...and when lane-start refuses, the bare Claude behind it starts on the same
# resolution, made once, and the version stayed on lane-start's call alone.
resolve_case "PATH=$test_root/refusing-bin:$fake_bin:$PATH" -- "$launcher" --lane other-1 run team002 --resume fixture-session
[[ "$(current_calls)" -eq 1 && "$(< "$test_root/launch.log")" == "$user_copy" ]] || fail 'refused hand-off: the bare Claude was not the resolved one'; ok; assertion
has_line 'CLAUDE_VERIFIED_VERSION=2.1.284' lane-env.log || fail 'refused hand-off: lane-start did not get the version'; ok; assertion
has_line 'CLAUDE_VERIFIED_VERSION=<unset>' claude-env.log || fail 'refused hand-off: the version reached the bare session'; ok; assertion

# THE HAND-OFF FOR EVERY ANSWER THE RESOLVER GIVES. The scenario "The launch
# says what launched" covers a launch the resolver answered "whether verified,
# ahead, unverified or stale": it prints the version it started and how that
# compares with npm, and hands lane-start the same path as CLAUDE_BIN with
# CLAUDE_VERIFIED_VERSION set to the version the resolver read from that copy.
# The verified answer is pinned above. Each answer below reports an installed
# version that differs from npm's published one, so a hand-off that sent npm's
# version, or kept the version for a verified answer alone, fails here.
# handoff_case <answer> <path> <version> <line the launch prints> <env assignment>...
handoff_case() {
  local answer="$1" path="$2" version="$3" said="$4"
  shift 4
  resolve_case "$@" -- "$launcher" --lane example-1 run team002 --resume fixture-session
  [[ "$case_status" -eq 0 && "$(< "$test_root/current.log")" == --porcelain ]] \
    || fail "hand-off $answer: the launch exited $case_status, or claude-current was not asked exactly once with --porcelain alone"; ok; assertion
  # A lane launch also prints the path of its defect capture (#95); beside that
  # line, the resolver's is the only one, and the launcher adds none of its own.
  [[ "$(stderr_count "$said")" -eq 1 && "$(grep -cvF 'pclaude: lane defect capture:' "$test_root/stderr.log" || true)" -eq 1 ]] \
    || fail "hand-off $answer: the launch did not print '$said' exactly once, alone ($(cat "$test_root/stderr.log"))"; ok; assertion
  [[ "$(< "$test_root/lane.log")" == "$path" ]] || fail "hand-off $answer: lane-start did not get $path as CLAUDE_BIN"; ok; assertion
  has_line "CLAUDE_RESOLVED_BIN=$path" lane-env.log || fail "hand-off $answer: lane-start did not get the resolution marker"; ok; assertion
  has_line "CLAUDE_VERIFIED_VERSION=$version" lane-env.log \
    || fail "hand-off $answer: lane-start did not get CLAUDE_VERIFIED_VERSION=$version ($(cat "$test_root/lane-env.log"))"; ok; assertion
}
# AHEAD: the copy is newer than npm's 2.1.284; lane-start gets that copy's 2.1.290.
handoff_case ahead "$system_copy" 2.1.290 'claude 2.1.290 (ahead of npm 2.1.284)' \
  "STUB_PATH=$system_copy" STUB_VERSION=2.1.290 STUB_STATE=ahead "STUB_SAYS=ahead of npm 2.1.284"
# UNVERIFIED: npm was unreachable, so no published version; the highest installed
# copy's 2.1.283 is what lane-start gets.
handoff_case unverified "$user_copy" 2.1.283 'claude 2.1.283 (UNVERIFIED: could not reach npm)' \
  STUB_VERSION=2.1.283 STUB_PUBLISHED= STUB_STATE=unverified "STUB_SAYS=UNVERIFIED: could not reach npm"
# STALE, ALLOWED: CLAUDE_ALLOW_STALE=1 reaches the resolver, which starts the
# behind copy, and lane-start gets that copy's 2.1.280, not npm's 2.1.284.
handoff_case 'stale allowed' "$user_copy" 2.1.280 'claude 2.1.280 (STALE, started under CLAUDE_ALLOW_STALE=1)' \
  CLAUDE_ALLOW_STALE=1 STUB_VERSION=2.1.280 STUB_STATE=stale "STUB_SAYS=STALE, started under CLAUDE_ALLOW_STALE=1"
has_line 'CLAUDE_ALLOW_STALE=1' current-env.log || fail 'hand-off stale allowed: the escape did not reach claude-current'; ok; assertion

# FROM A TERMINAL OUTSIDE TMUX the parent only wraps tmux: the child resolves,
# once. The server's stale pair and version reach neither side.
tmux_case -- "${bare[@]}"
[[ "$(< "$test_root/tmux.log")" == new-session ]] || fail "tmux: the child did not launch ($(cat "$test_root/tmux.log"))"; ok; assertion
[[ "$(< "$test_root/current.log")" == --porcelain ]] || fail "tmux: claude-current was not asked exactly once ($(cat "$test_root/current.log"))"; ok; assertion
[[ "$(< "$test_root/launch.log")" == "$user_copy" ]] || fail 'tmux: the child did not start the resolved path'; ok; assertion
has_line 'CLAUDE_VERIFIED_VERSION=<unset>' claude-env.log || fail 'tmux: the server stale version reached the session'; ok; assertion
# A pin equal to a marker the server captured is still the operator's pin.
tmux_case "CLAUDE_BIN=$system_copy" "STALE_RESOLVED_BIN=$system_copy" CLAUDE_NO_LANE=1 -- "$launcher" run team002 --resume fixture-session
[[ ! -e "$test_root/current.log" && "$(< "$test_root/launch.log")" == "$system_copy" ]] || fail 'tmux: a stale server marker turned the pin into a resolution'; ok; assertion
# A refusal in the pane this launch created keeps the pane, so it stays readable.
tmux_case STUB_EXIT=2 -- "${bare[@]}"
grep -Fxq 'child-exit 2' "$test_root/tmux.log" || fail "tmux: the refused child did not exit 2 ($(cat "$test_root/tmux.log"))"; ok; assertion
grep -Fq 'remain-on-exit on' "$test_root/tmux-option.log" || fail 'tmux: the refused pane was not kept'; ok; assertion
[[ ! -e "$test_root/launch.log" && "$(current_calls)" -eq 1 ]] || fail 'tmux: the refused child started a Claude'; ok; assertion

# NO RESOLVER INSTALLED: the #109 native ordering, then PATH, with ONE notice
# naming the install act, and the choice marked so a later launch resolves.
rm -rf "$versions"
mkdir -p "$versions"
cp "$user_copy" "$versions/2.1.50"
chmod +x "$versions/2.1.50"
resolve_case "WORKBENCHES_CLAUDE_CURRENT_BIN=$test_root/no-claude-current" -- "${bare[@]}"
[[ "$case_status" -eq 0 && "$(< "$test_root/launch.log")" == "$versions/2.1.50" ]] || fail 'no resolver: the newest native version did not launch'; ok; assertion
[[ "$(stderr_count 'not verified against npm')" -eq 1 && "$(stderr_count 'openRepoTools --install')" -eq 1 && "$(stderr_lines)" -eq 1 ]] \
  || fail "no resolver: not exactly one notice naming openRepoTools --install ($(cat "$test_root/stderr.log"))"; ok; assertion
has_line "CLAUDE_RESOLVED_BIN=$versions/2.1.50" claude-env.log || fail 'no resolver: the fallback was not marked as a resolution'; ok; assertion
resolve_case "WORKBENCHES_CLAUDE_CURRENT_BIN=$test_root/no-claude-current" -- "$launcher" --lane example-1 run team002 --resume fixture-session
[[ "$(< "$test_root/lane.log")" == "$versions/2.1.50" ]] && has_line 'CLAUDE_VERIFIED_VERSION=<unset>' lane-env.log \
  || fail 'no resolver: lane-start was not handed the unverified native choice'; ok; assertion
rm -rf "$versions"
resolve_case "WORKBENCHES_CLAUDE_CURRENT_BIN=$test_root/no-claude-current" -- "${bare[@]}"
[[ "$(< "$test_root/launch.log")" == "$fake_bin/claude" && "$(stderr_count 'not verified against npm')" -eq 1 ]] \
  || fail 'no resolver, no native version: the PATH lookup did not launch with its notice'; ok; assertion

printf 'claude-current resolution: %s checks passed\n' "$checks"
printf '%s\n' 'PASS: Claude profile binary selection'
printf "COUNT: %s assertions passed\n" "$assertions"
