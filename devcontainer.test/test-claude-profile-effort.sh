#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="${1:-$repo_root/base-image/files/claude-profile}"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
profile_dir="$test_root/profiles/profiles/team"
mkdir -p "$profile_dir" "$test_root/bin" "$test_root/home"
printf '%s\n' '{"profiles":[{"name":"team","email":"team@example.invalid","family":"testing","profilePath":"team"}]}' > "$test_root/manifest.json"
printf '%s\n' '{"model":"claude-opus-5-5","effortLevel":"xhigh"}' > "$profile_dir/settings.json"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\0" "$@" > "${FAKE_CLAUDE_LOG:?}"' \
  'printf "%s" "${CLAUDE_CODE_EFFORT_LEVEL:-}" > "${FAKE_CLAUDE_LOG}.effort-env"' > "$test_root/bin/claude"
chmod +x "$test_root/bin/claude"
ln -s "$launcher" "$test_root/bin/claude-profile"
ln -s "$repo_root/base-image/files/pclaude" "$test_root/bin/pclaude"

unset TMUX TMUX_PANE CLAUDE_LANE CLAUDE_NO_LANE CLAUDE_CODE_EFFORT_LEVEL \
  WORKBENCHES_CLAUDE_TMUX_CHILD CLAUDE_RESOLVED_BIN 2>/dev/null || true
export HOME="$test_root/home" PATH="$test_root/bin:$PATH" \
  CLAUDE_PROFILES_HOME="$test_root/profiles" CLAUDE_PROFILES_MANIFEST="$test_root/manifest.json" \
  CLAUDE_BIN="$test_root/bin/claude" WORKBENCHES_SHARED_MCP_FAMILIES=none \
  WORKBENCHES_CLAUDE_TMUX=off FAKE_CLAUDE_LOG="$test_root/argv"

scenarios=0
assertions=0
run() {
  scenarios=$((scenarios + 1))
  : > "$FAKE_CLAUDE_LOG"
  pclaude "$@" >/dev/null 2>"$test_root/stderr"
  mapfile -d '' -t argv < "$FAKE_CLAUDE_LOG"
  [[ ${#argv[@]} -gt 0 ]] || { echo "FAIL: mock Claude was not launched" >&2; exit 1; }
}
expect_effort() {
  local expected="$1" argument count=0 index=0 value=""
  for argument in "${argv[@]}"; do
    [[ "$argument" != -- ]] || break
    case "$argument" in
      --effort) count=$((count + 1)); value="${argv[index + 1]:-}" ;;
      --effort=*) count=$((count + 1)); value="${argument#--effort=}" ;;
    esac
    index=$((index + 1))
  done
  if [[ "$expected" == absent ]]; then
    [[ "$count" == 0 ]] || { echo "FAIL: unexpected effort argument" >&2; exit 1; }
  else
    [[ "$count" == 1 && "$value" == "$expected" ]] || {
      echo "FAIL: expected one $expected effort, got count=$count value=$value" >&2; exit 1;
    }
  fi
  assertions=$((assertions + 1))
}
expect_tail() {
  local start=$(( ${#argv[@]} - $# )) argument
  for argument in "$@"; do
    [[ "${argv[start]}" == "$argument" ]] || { echo "FAIL: original argv changed" >&2; exit 1; }
    start=$((start + 1))
  done
  assertions=$((assertions + 1))
}

# Fake a long-lived tmux server with a stale effort, then execute the launcher's
# actual child command under that server environment. No live tmux is touched.
run_tty() {
  local command_string argument
  scenarios=$((scenarios + 1))
  : > "$FAKE_CLAUDE_LOG"
  printf '%s\n' '#!/usr/bin/env bash' 'case "${1:-}" in' \
    'new-session) TMUX=fixture CLAUDE_CODE_EFFORT_LEVEL=medium bash -c "${@: -1}" ;;' \
    'esac' > "$test_root/bin/tmux"
  chmod +x "$test_root/bin/tmux"
  printf -v command_string '%q ' "$test_root/bin/pclaude" "$@"
  WORKBENCHES_CLAUDE_TMUX=auto script -qefc "$command_string" /dev/null </dev/null >/dev/null
  mapfile -d '' -t argv < "$FAKE_CLAUDE_LOG"
  [[ ${#argv[@]} -gt 0 ]] || { echo "FAIL: tmux child not launched" >&2; exit 1; }
}

run team
expect_effort xhigh
run team --resume fixture-session
expect_effort xhigh
expect_tail --resume fixture-session
run team -p 'fixture prompt'
expect_effort xhigh
expect_tail -p 'fixture prompt'
run team --print 'fixture prompt'
expect_effort xhigh
run team -- --effort 'prompt text'
expect_effort xhigh
expect_tail -- --effort 'prompt text'

for level in low medium high xhigh max; do
  run team --effort "$level"
  expect_effort "$level"
  expect_tail --effort "$level"
  run team "--effort=$level"
  expect_effort "$level"
  expect_tail "--effort=$level"
done

run team --effort
expect_effort ""

export CLAUDE_CODE_EFFORT_LEVEL=max
run team
expect_effort absent
run team --effort high
expect_effort high
export CLAUDE_CODE_EFFORT_LEVEL=""
run team
expect_effort xhigh
unset CLAUDE_CODE_EFFORT_LEVEL

printf '%s\n' '{"model":"claude-opus-5-5","effortLevel":"xhigh","env":{"CLAUDE_CODE_EFFORT_LEVEL":"max"}}' > "$profile_dir/settings.json"
run team
expect_effort absent
run team --effort low
expect_effort low
printf '%s\n' '{"model":"custom-model","effortLevel":"high","env":{"CLAUDE_CODE_EFFORT_LEVEL":""}}' > "$profile_dir/settings.json"
run team
expect_effort xhigh
jq -e '.model == "custom-model" and .effortLevel == "high"' "$profile_dir/settings.json" >/dev/null
assertions=$((assertions + 1))

for command in mcp plugin plugins doctor install update upgrade auth agents auto-mode \
  gateway import logs purge respawn rm setup-token stop kill ultrareview attach \
  --help -h --version -v; do
  run team "$command"
  expect_effort absent
done
run status team
expect_effort absent
expect_tail auth status --text
run login team
expect_effort absent
expect_tail auth login --claudeai --email team@example.invalid

run_tty team
expect_effort xhigh
export CLAUDE_CODE_EFFORT_LEVEL=max
run_tty team
expect_effort absent
[[ "$(< "$FAKE_CLAUDE_LOG.effort-env")" == max ]]
assertions=$((assertions + 1))
export CLAUDE_CODE_EFFORT_LEVEL=""
run_tty team
expect_effort xhigh
unset CLAUDE_CODE_EFFORT_LEVEL

[[ "$scenarios" == 52 ]] || { echo "FAIL: scenario count changed ($scenarios)" >&2; exit 1; }
printf 'PASS: Claude startup effort (%s scenarios, %s assertions)\n' "$scenarios" "$assertions"
