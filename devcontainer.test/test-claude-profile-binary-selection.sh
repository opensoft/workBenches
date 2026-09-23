#!/usr/bin/env bash
# Profile launches use the newest locally installed native Claude Code binary.
set -euo pipefail

# A caller may itself be a claude-profile tmux child or lane. Neither the
# normal launches nor the explicit CLAUDE_BIN case should inherit that routing.
unset TMUX TMUX_PANE WORKBENCHES_CLAUDE_TMUX WORKBENCHES_CLAUDE_TMUX_CHILD \
  WORKBENCHES_CLAUDE_WINDOW WORKBENCHES_CLAUDE_WINDOW_ID \
  WORKBENCHES_CLAUDE_WINDOW_REF WORKBENCHES_TMUX_SESSION \
  WORKBENCHES_TMUX_PANE CLAUDE_LANE CLAUDE_NO_LANE CLAUDE_LANE_DIR \
  LANES_WORKSTATION LANES_HOST LANES_OS LANES_CONTAINER PROJECTS_ROOT \
  AGENT_PROTOCOL_ROOT 2>/dev/null || true

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
launcher="${1:-$repo_root/base-image/files/claude-profile}"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

test_home="$test_root/home"
versions="$test_home/.local/share/claude/versions"
fake_bin="$test_root/bin"
profiles="$test_root/profiles"
mkdir -p "$versions" "$fake_bin" "$profiles/profiles/opensoft/team/team-002"

printf '%s\n' '{"profiles":[{"name":"team-002","email":"test@example.invalid","family":"testing","aliases":["team002"],"profilePath":"opensoft/team/team-002"}]}' > "$test_root/manifest.json"
printf '%s\n' '{"name":"team-002","family":"testing","email":"test@example.invalid"}' > "$profiles/profiles/opensoft/team/team-002/.profile.json"

printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$0" > "$LAUNCH_LOG"' > "$fake_bin/claude"
chmod +x "$fake_bin/claude"
cp "$fake_bin/claude" "$versions/2.1.9"
cp "$fake_bin/claude" "$versions/2.1.10"
cp "$fake_bin/claude" "$versions/2.0.999"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$CLAUDE_BIN" > "$LANE_LOG"' > "$fake_bin/lane-start"
chmod +x "$versions/2.1.9" "$versions/2.1.10" "$versions/2.0.999" "$fake_bin/lane-start"

common_env=(
  "HOME=$test_home"
  "PATH=$fake_bin:$PATH"
  "CLAUDE_PROFILES_HOME=$profiles"
  "CLAUDE_PROFILES_MANIFEST=$test_root/manifest.json"
  "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
  "WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS=0"
  "LAUNCH_LOG=$test_root/launch.log"
  "LANE_LOG=$test_root/lane.log"
  "TMPDIR=$test_root"
)

launch() {
  env -u CLAUDE_BIN -u CLAUDE_LANE -u CLAUDE_NO_LANE -u CLAUDE_LANE_DIR \
    "${common_env[@]}" TMUX=fake-session "$launcher" "$@" >/dev/null
}

launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.10" ]] || fail 'newest numeric native version was not launched'

launch --lane example-1 run team002 --resume fixture-session
[[ "$(< "$test_root/lane.log")" == "$versions/2.1.10" ]] || fail 'lane-start did not receive newest native version'

cp "$fake_bin/claude" "$versions/2.1.11"
chmod +x "$versions/2.1.11"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.11" ]] || fail 'a version installed between launches was not selected'
rm "$versions/2.1.11"

cp "$fake_bin/claude" "$versions/2.1.9223372036854775808"
cp "$fake_bin/claude" "$versions/99999999999999999999999999999.0.0"
chmod +x "$versions/2.1.9223372036854775808" "$versions/99999999999999999999999999999.0.0"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/99999999999999999999999999999.0.0" ]] || fail 'oversized numeric version was not selected'
rm "$versions/99999999999999999999999999999.0.0"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.9223372036854775808" ]] || fail 'oversized patch version was not selected'
rm "$versions/2.1.9223372036854775808"
cp "$fake_bin/claude" "$versions/2.0001.00011"
chmod +x "$versions/2.0001.00011"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/2.0001.00011" ]] || fail 'leading zeroes changed numeric version order'
rm "$versions/2.0001.00011"

cp "$fake_bin/claude" "$versions/not-a-version"
cp "$fake_bin/claude" "$versions/2.1.99"
chmod +x "$versions/not-a-version"
chmod -x "$versions/2.1.99"
mkdir "$versions/9.9.9"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.10" ]] || fail 'invalid or nonexecutable entry was selected'

env -u CLAUDE_LANE -u CLAUDE_NO_LANE -u CLAUDE_LANE_DIR \
  "${common_env[@]}" TMUX=fake-session "CLAUDE_BIN=$fake_bin/claude" \
  "$launcher" run team002 --resume fixture-session >/dev/null
[[ "$(< "$test_root/launch.log")" == "$fake_bin/claude" ]] || fail 'explicit CLAUDE_BIN did not win'

# A running tmux server can have an older environment than this invocation.
# Exercise the interactive parent-to-child command with that stale value.
cat > "$fake_bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  new-session)
    for child_command; do :; done
    printf '%s\n' new-session > "$TMUX_LOG"
    env CLAUDE_BIN="$STALE_CLAUDE_BIN" bash -c "$child_command"
    ;;
  attach-session) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/tmux"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" stale > "$LAUNCH_LOG"' > "$fake_bin/stale-claude"
chmod +x "$fake_bin/stale-claude"
command_string=""
printf -v command_string '%q ' "$launcher" run team002 --resume fixture-session
env -u TMUX -u CLAUDE_LANE -u CLAUDE_LANE_DIR \
  "${common_env[@]}" CLAUDE_NO_LANE=1 "CLAUDE_BIN=$fake_bin/claude" \
  "STALE_CLAUDE_BIN=$fake_bin/stale-claude" "TMUX_LOG=$test_root/tmux.log" \
  script -q -e -c "$command_string" /dev/null >/dev/null
[[ "$(< "$test_root/tmux.log")" == new-session ]] || fail 'interactive tmux relaunch was not exercised'
[[ "$(< "$test_root/launch.log")" == "$fake_bin/claude" ]] || fail 'tmux child lost explicit CLAUDE_BIN override'
env -u TMUX -u CLAUDE_BIN -u CLAUDE_LANE -u CLAUDE_LANE_DIR \
  "${common_env[@]}" CLAUDE_NO_LANE=1 \
  "STALE_CLAUDE_BIN=$fake_bin/stale-claude" "TMUX_LOG=$test_root/tmux.log" \
  script -q -e -c "$command_string" /dev/null >/dev/null
[[ "$(< "$test_root/launch.log")" == "$versions/2.1.10" ]] || fail 'tmux server stale CLAUDE_BIN replaced newest native version'

mv "$versions" "$test_root/versions-removed"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$fake_bin/claude" ]] || fail 'PATH fallback failed without native versions'

mkdir "$versions"
cp "$fake_bin/claude" "$versions/2.1.99"
chmod -x "$versions/2.1.99"
launch run team002 --resume fixture-session
[[ "$(< "$test_root/launch.log")" == "$fake_bin/claude" ]] || fail 'PATH fallback failed with only unusable native versions'

printf '%s\n' 'PASS: Claude profile binary selection'
