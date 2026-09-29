#!/usr/bin/env bash
# Layer 3's user-owned Claude Code copy at npm latest (opensoft/workBenches#119;
# openspec/changes/launch-current-claude, user-managed-claude-updates, design.md
# Decisions 2 and 3). Modeled on test-layer3-codex-version.sh:
#
#   1. user-layer/build.sh reads npm's latest version with the BASE IMAGE's own
#      npm, bounded, through the same pinned reference the build uses; takes an
#      exact --claude-version instead; and fails closed, naming the lookup, on
#      anything that is not an exact version. Docker and timeout are mocks.
#   2. The Dockerfile's Claude RUN is executed as written, against fake npm,
#      node and claude, so its install-hook and verification logic is tested
#      without Docker.
#   3. Static checks that the step sits where the ratified text needs it.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
case_root="$(mktemp -d)"
trap 'rm -rf "$case_root"' EXIT
mock_bin="$case_root/bin"
docker_log="$case_root/docker.log"
timeout_log="$case_root/timeout.log"
stderr_log="$case_root/stderr.log"
pinned_tag_file="$case_root/pinned-tag"
dockerfile="$repo_root/user-layer/Dockerfile"
build_script="$repo_root/user-layer/build.sh"
mkdir -p "$mock_bin"
checks=0

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { checks=$((checks + 1)); }

base_image_id="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
lookup='npm view @anthropic-ai/claude-code version'

cat > "$mock_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == image && "${2:-}" == inspect ]]; then
  image="${!#}"
  if [[ "$image" == workbenches-layer3-base-pin:* ]]; then
    [[ -f "$MOCK_PINNED_TAG_FILE" && "$image" == "$(cat "$MOCK_PINNED_TAG_FILE")" ]] || exit 1
  fi
  printf '%s\n' 'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  exit 0
fi
if [[ "${1:-}" == tag ]]; then
  printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"
  printf '%s\n' "$3" > "$MOCK_PINNED_TAG_FILE"
  exit 0
fi
if [[ "${1:-}" == image && "${2:-}" == rm ]]; then
  printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"
  rm -f "$MOCK_PINNED_TAG_FILE"
  exit 0
fi
if [[ "${1:-}" == run ]]; then
  printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"
  if [[ "$*" == *'npm view @anthropic-ai/claude-code version'* ]]; then
    [[ "${MOCK_CLAUDE_LOOKUP_FAIL:-false}" != true ]] || exit 1
    printf '%s\n' "${MOCK_CLAUDE_LOOKUP_OUTPUT-2.1.284}"
    exit 0
  fi
  printf '%s\n' 'codex-cli 0.199.0'
  exit 0
fi
printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"
EOF
cat > "$mock_bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_TIMEOUT_LOG"
if [[ -n "${MOCK_TIMEOUT_MATCH:-}" && "$*" == *"$MOCK_TIMEOUT_MATCH"* ]]; then exit 124; fi
shift
exec "$@"
EOF
chmod 0755 "$mock_bin/docker" "$mock_bin/timeout"

run_build() {
    : > "$docker_log"
    : > "$timeout_log"
    : > "$stderr_log"
    MOCK_DOCKER_LOG="$docker_log" MOCK_TIMEOUT_LOG="$timeout_log" \
        MOCK_PINNED_TAG_FILE="$pinned_tag_file" PATH="$mock_bin:$PATH" \
        "$build_script" --base py-bench:latest --user tester "$@" >/dev/null 2>"$stderr_log"
}
# expect_refusal <what> <text the refusal must say> [build args...]: the build
# fails, says so, and never reaches docker build.
expect_refusal() {
    local what="$1" text="$2"
    shift 2
    if run_build "$@"; then fail "$what: the build succeeded"; fi
    grep -Fq -- "$text" "$stderr_log" || fail "$what: it did not say '$text' ($(cat "$stderr_log"))"
    if grep -q '^build ' "$docker_log"; then fail "$what: docker build ran"; fi
}
pinned() { awk '$1 == "tag" { print $3; exit }' "$docker_log"; }
line_of() { grep -nF -- "$1" "$docker_log" | head -n 1 | cut -d: -f1; }

# 1. BUILD.SH ----------------------------------------------------------------

# The default reads npm latest with the base image's own npm, through the pin.
run_build
pinned_ref="$(pinned)"
[[ "$pinned_ref" == workbenches-layer3-base-pin:* ]] || fail "no pinned base reference ($pinned_ref)"; ok
grep -Fxq -- "run --rm --entrypoint= $pinned_ref sh -c $lookup" "$docker_log" \
    || fail "npm latest was not read with the pinned base image's npm ($(cat "$docker_log"))"; ok
if grep -F -- "$lookup" "$docker_log" | grep -Fq -- '--network none'; then
    fail 'the npm lookup was run without the network it needs'
fi; ok
grep -Fq -- '--build-arg CLAUDE_CODE_VERSION=2.1.284' "$docker_log" || fail 'npm latest was not passed as CLAUDE_CODE_VERSION'; ok
grep -Fq -- "--build-arg BASE_IMAGE=$pinned_ref" "$docker_log" || fail 'the lookup and the build did not share one pinned image'; ok
grep -Fq -- '--build-arg CODEX_VERSION=0.199.0' "$docker_log" || fail 'the Codex overlay stopped inheriting the base version'; ok
grep -Fxq -- "30s docker run --rm --entrypoint= $pinned_ref sh -c $lookup" "$timeout_log" \
    || fail "the lookup was not bounded by the 30s default ($(cat "$timeout_log"))"; ok
tag_line="$(line_of "tag $base_image_id $pinned_ref")"
lookup_line="$(line_of "$lookup")"
build_line="$(grep -n '^build ' "$docker_log" | head -n 1 | cut -d: -f1)"
[[ -n "$tag_line" && -n "$lookup_line" && -n "$build_line" \
    && "$tag_line" -lt "$lookup_line" && "$lookup_line" -lt "$build_line" ]] \
    || fail "the lookup did not run between pinning and building ($tag_line/$lookup_line/$build_line)"; ok
grep -Fq -- "image rm $pinned_ref" "$docker_log" || fail 'the pinned tag was not removed'; ok

# The bound is the build's own seam, and an invalid one is refused before Docker.
WORKBENCHES_CLAUDE_VERSION_PROBE_TIMEOUT_SECONDS=7 run_build
grep -Fxq -- "7s docker run --rm --entrypoint= $(pinned) sh -c $lookup" "$timeout_log" \
    || fail 'WORKBENCHES_CLAUDE_VERSION_PROBE_TIMEOUT_SECONDS did not bound the lookup'; ok
WORKBENCHES_CLAUDE_VERSION_PROBE_TIMEOUT_SECONDS=0 expect_refusal 'zero timeout' \
    'WORKBENCHES_CLAUDE_VERSION_PROBE_TIMEOUT_SECONDS must be a positive integer'; ok
[[ ! -s "$docker_log" ]] || fail 'an invalid timeout still reached Docker'; ok

# A lookup that fails, times out or answers anything but an exact version
# fails the build and names the lookup, instead of baking a version nobody chose.
MOCK_TIMEOUT_MATCH="$lookup" expect_refusal 'lookup timed out' 'Claude Code version lookup'; ok
MOCK_CLAUDE_LOOKUP_FAIL=true expect_refusal 'lookup failed' "Claude Code version lookup ($lookup"; ok
grep -Fq -- "image rm $(pinned)" "$docker_log" || fail 'a failed lookup left the pinned tag behind'; ok
MOCK_CLAUDE_LOOKUP_OUTPUT=latest expect_refusal 'lookup said latest' "returned 'latest', not an exact version"; ok
MOCK_CLAUDE_LOOKUP_OUTPUT='' expect_refusal 'lookup said nothing' "returned '', not an exact version"; ok
MOCK_CLAUDE_LOOKUP_OUTPUT='npm ERR! code E404' expect_refusal 'lookup said an npm error' 'not an exact version'; ok

# Whitespace around the answer is not part of it, and a prerelease is exact.
MOCK_CLAUDE_LOOKUP_OUTPUT='  2.1.290  ' run_build
grep -Fq -- '--build-arg CLAUDE_CODE_VERSION=2.1.290' "$docker_log" || fail 'a padded npm answer was not accepted'; ok
MOCK_CLAUDE_LOOKUP_OUTPUT='2.2.0-beta.1' run_build
grep -Fq -- '--build-arg CLAUDE_CODE_VERSION=2.2.0-beta.1' "$docker_log" || fail 'a prerelease version was not accepted'; ok

# A direct caller names the version: it is installed instead, with no lookup.
run_build --claude-version 2.1.300
grep -Fq -- '--build-arg CLAUDE_CODE_VERSION=2.1.300' "$docker_log" || fail '--claude-version was not passed'; ok
if grep -Fq -- "$lookup" "$docker_log"; then fail 'an explicit --claude-version still looked npm up'; fi; ok
expect_refusal '--claude-version latest' "--claude-version needs an exact version, not 'latest'" --claude-version latest; ok
"$build_script" --help | grep -Fq -- '--claude-version VERSION' || fail '--help does not name --claude-version'; ok

# 2. THE DOCKERFILE'S RUN, EXECUTED ---------------------------------------------
claude_run="$(awk '
    /^RUN test -n "\$CLAUDE_CODE_VERSION"/ { inside = 1 }
    inside { print; if ($0 !~ /\\$/) exit }' "$dockerfile")"
[[ -n "$claude_run" ]] || fail 'the Claude Code RUN step was not found in user-layer/Dockerfile'; ok
claude_run="${claude_run#RUN }"

sandbox="$case_root/sandbox"
tools="$sandbox/tools"
mkdir -p "$tools" "$sandbox/system-bin"
cat > "$tools/npm" <<'EOF'
#!/usr/bin/env bash
# npm as the runtime user sees it: -g writes into NPM_CONFIG_PREFIX only.
printf '%s\n' "$*" >> "$FAKE_NPM_LOG"
case "$1" in
  root) printf '%s\n' "$NPM_CONFIG_PREFIX/lib/node_modules"; exit 0 ;;
  install)
    [[ "${FAKE_NPM_FAIL:-false}" != true ]] || exit 1
    spec="${!#}"
    package_root="$NPM_CONFIG_PREFIX/lib/node_modules/@anthropic-ai/claude-code"
    mkdir -p "$package_root" "$NPM_CONFIG_PREFIX/bin"
    : > "$package_root/install.cjs"
    cat > "$NPM_CONFIG_PREFIX/bin/claude" <<'CLAUDE'
#!/usr/bin/env bash
state="$(cat "$FAKE_CLAUDE_STATE" 2>/dev/null || true)"
[[ -n "$state" ]] || { echo 'claude native binary not installed' >&2; exit 1; }
printf '%s (Claude Code)\n' "$state"
CLAUDE
    chmod +x "$NPM_CONFIG_PREFIX/bin/claude"
    # Whether npm's install-script policy ran the package's own hook.
    if [[ "${FAKE_HOOK_SKIPPED:-false}" == true ]]; then : > "$FAKE_CLAUDE_STATE"; else printf '%s\n' "${spec##*@}" > "$FAKE_CLAUDE_STATE"; fi
    exit 0
    ;;
esac
exit 1
EOF
cat > "$tools/node" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_NODE_LOG"
printf '%s\n' "${FAKE_HOOK_RESULT:-$CLAUDE_CODE_VERSION}" > "$FAKE_CLAUDE_STATE"
EOF
printf '%s\n' '#!/usr/bin/env bash' 'echo "2.1.280 (Claude Code)"' > "$sandbox/system-bin/claude"
chmod +x "$tools/npm" "$tools/node" "$sandbox/system-bin/claude"

# run_step <env assignment>...: the RUN as /bin/sh runs it, as the runtime user.
run_step() {
    rm -rf "$sandbox/prefix"
    rm -f "$sandbox/npm.log" "$sandbox/node.log" "$sandbox/state"
    mkdir -p "$sandbox/prefix"
    env -i HOME="$sandbox" NPM_CONFIG_PREFIX="$sandbox/prefix" \
        PATH="$sandbox/prefix/bin:$tools:/usr/bin:/bin" CLAUDE_CODE_VERSION=2.1.284 \
        FAKE_NPM_LOG="$sandbox/npm.log" FAKE_NODE_LOG="$sandbox/node.log" \
        FAKE_CLAUDE_STATE="$sandbox/state" "$@" \
        sh -c "$claude_run" >/dev/null 2>&1
}

run_step || fail 'the RUN failed when npm ran the package hook itself'; ok
grep -Fxq -- 'install -g @anthropic-ai/claude-code@2.1.284' "$sandbox/npm.log" \
    || fail "the RUN did not install the exact version into the user prefix ($(cat "$sandbox/npm.log"))"; ok
[[ ! -e "$sandbox/node.log" ]] || fail 'the RUN ran install.cjs when claude already reported the version'; ok

run_step FAKE_HOOK_SKIPPED=true || fail 'the RUN failed when npm skipped the package hook'; ok
[[ "$(cat "$sandbox/node.log")" == "$sandbox/prefix/lib/node_modules/@anthropic-ai/claude-code/install.cjs" ]] \
    || fail "the RUN did not run the package's own install.cjs ($(cat "$sandbox/node.log" 2>/dev/null))"; ok

if run_step FAKE_HOOK_SKIPPED=true FAKE_HOOK_RESULT=2.1.283; then
    fail 'the RUN accepted a claude that reports another version'
fi; ok
if run_step PATH="$sandbox/system-bin:$sandbox/prefix/bin:$tools:/usr/bin:/bin"; then
    fail 'the RUN accepted a claude that does not resolve under the user prefix'
fi; ok
if run_step FAKE_NPM_FAIL=true; then fail 'the RUN accepted a failed npm install'; fi; ok
[[ ! -e "$sandbox/node.log" ]] || fail 'the RUN ran the hook after a failed install'; ok
if run_step CLAUDE_CODE_VERSION=; then fail 'the RUN accepted no version at all'; fi; ok
if run_step CLAUDE_CODE_VERSION=latest; then fail 'the RUN accepted a mutable dist-tag'; fi; ok
[[ ! -e "$sandbox/npm.log" ]] || fail 'the RUN ran npm for a version it should have refused'; ok

# 3. WHERE THE STEP SITS ---------------------------------------------------------
[[ "$(grep -c '^ARG CLAUDE_CODE_VERSION=""$' "$dockerfile")" -eq 1 ]] \
    || fail 'user-layer/Dockerfile does not declare ARG CLAUDE_CODE_VERSION="" exactly once'; ok
arg_line="$(grep -n '^ARG CLAUDE_CODE_VERSION=""$' "$dockerfile" | cut -d: -f1)"
run_line="$(grep -n '^RUN test -n "\$CLAUDE_CODE_VERSION"' "$dockerfile" | cut -d: -f1)"
user_line="$(grep -n '^USER \$USERNAME$' "$dockerfile" | cut -d: -f1)"
codex_line="$(grep -n '@openai/codex@\${CODEX_VERSION}' "$dockerfile" | cut -d: -f1)"
[[ "$run_line" -eq $((arg_line + 1)) ]] \
    || fail 'the ARG is not declared at its only use, so a new release would invalidate earlier steps'; ok
[[ "$arg_line" -gt "$user_line" && "$arg_line" -gt "$codex_line" ]] \
    || fail 'the Claude Code step does not run as the user, after the Codex overlay'; ok
if grep -Eq '(/usr/local|/usr)/lib/node_modules/@anthropic-ai' "$dockerfile"; then
    fail 'user-layer/Dockerfile names the shared Claude Code install, which Layer 3 must leave alone'
fi; ok
if printf '%s\n' "$claude_run" | grep -Eq '(^|[^a-z])(chown|chmod|rm|sudo)[[:space:]]'; then
    fail 'the Claude Code step changes files it does not own'
fi; ok
grep -Fq -- '--build-arg CLAUDE_CODE_VERSION="$CLAUDE_CODE_VERSION"' "$build_script" \
    || fail 'user-layer/build.sh does not pass CLAUDE_CODE_VERSION to the build'; ok

printf 'layer3 Claude Code version: %s checks passed; npm latest by default, exact when named, fail closed otherwise\n' "$checks"
