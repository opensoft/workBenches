#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
WORKBENCH_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
SETUP_SCRIPT="$WORKBENCH_ROOT/devBenches/base-image/files/openspeckit/setup-openspeckit"
WORKTREE_TEMPLATE_ROOT="$WORKBENCH_ROOT/devBenches/base-image/files/speckit-worktree/templates"
COMMAND_TEMPLATE_ROOT="$WORKBENCH_ROOT/devBenches/base-image/files/claude/commands/opsx"

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

FIXTURE_HOME="$TMPDIR_ROOT/home"
AGENT_PROTOCOL_ROOT="$TMPDIR_ROOT/agent-protocol"
REPO_DIR="$TMPDIR_ROOT/repo"
REPO_SKILL_PATH="$REPO_DIR/.agents/skills/ct"
EXPLORE_COMMAND="$REPO_DIR/.claude/commands/opsx/explore.md"
REGISTRY_PATH="$REPO_DIR/.specify/extensions/.registry"
EXTENSION_MANIFEST="$REPO_DIR/.specify/extensions/git/extension.yml"
WORKFLOW_PROTOCOL="$AGENT_PROTOCOL_ROOT/protocols/openspec-speckit-workflow.md"
BOOTSTRAP_PROTOCOL="$AGENT_PROTOCOL_ROOT/protocols/project-agent-bootstrap.md"
FIRST_SNAPSHOT="$TMPDIR_ROOT/first.snapshot"
SECOND_SNAPSHOT="$TMPDIR_ROOT/second.snapshot"
FIRST_LOG="$TMPDIR_ROOT/first.log"
SECOND_LOG="$TMPDIR_ROOT/second.log"

failures=0

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1"
    failures=$((failures + 1))
}

assert_file() {
    local path="$1"
    local label="$2"
    if [[ -f "$path" ]]; then
        pass "$label"
    else
        fail "$label: missing $path"
    fi
}

assert_contains() {
    local path="$1"
    local needle="$2"
    local label="$3"
    if [[ -f "$path" ]] && grep -Fq -- "$needle" "$path"; then
        pass "$label"
    else
        fail "$label: $path does not contain $needle"
    fi
}

assert_not_contains() {
    local path="$1"
    local needle="$2"
    local label="$3"
    if [[ -f "$path" ]] && ! grep -Fq -- "$needle" "$path"; then
        pass "$label"
    else
        fail "$label: $path contains $needle"
    fi
}

assert_equal() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$label"
    else
        fail "$label: expected $expected, got $actual"
    fi
}

assert_regular_directory() {
    local path="$1"
    local label="$2"
    if [[ -d "$path" && ! -L "$path" ]]; then
        pass "$label"
    else
        fail "$label: expected regular directory at $path"
    fi
}

snapshot_repo() {
    local repo="$1"
    (
        cd "$repo"
        while IFS= read -r -d '' path; do
            sha256sum "$path"
        done < <(find . -path './.git' -prune -o -type f -print0 | sort -z)
    )
}

printf '%s\n' 'Given: an isolated HOME, protocol root, and checked-in template roots'
mkdir -p \
    "$FIXTURE_HOME/.claude/skills/ct" \
    "$FIXTURE_HOME/.codex/skills/ct" \
    "$FIXTURE_HOME/.agents/skills/ct" \
    "$REPO_DIR"

for skill_home in .claude .codex .agents; do
    printf '%s\n' 'fixture skill' > "$FIXTURE_HOME/$skill_home/skills/ct/SKILL.md"
done

printf '%s\n' '# Fixture Repository' 'hand-written content must survive bootstrap' > "$REPO_DIR/AGENTS.md"
mkdir -p "$REPO_DIR/.agents/skills" "$REPO_DIR/.specify/extensions"
ln -s "$FIXTURE_HOME/.agents/skills/ct" "$REPO_SKILL_PATH"
printf '%s\n' \
    '{' \
    '  "extensions": {' \
    '    "git": {' \
    '      "enabled": true,' \
    '      "manifest_hash": "sha256:stale"' \
    '    }' \
    '  }' \
    '}' > "$REGISTRY_PATH"

if [[ -L "$REPO_SKILL_PATH" && "$(readlink "$REPO_SKILL_PATH")" == "$FIXTURE_HOME/.agents/skills/ct" ]]; then
    pass 'Given fixture has a host-absolute repo-local skill symlink'
else
    fail 'Given fixture has a host-absolute repo-local skill symlink'
fi

git init -q "$REPO_DIR"

export HOME="$FIXTURE_HOME"
export AGENT_PROTOCOL_ROOT
export SPECKIT_WORKTREE_TEMPLATE_ROOT="$WORKTREE_TEMPLATE_ROOT"
export OPSX_COMMAND_TEMPLATE_ROOT="$COMMAND_TEMPLATE_ROOT"
export PATH="/usr/bin:/bin"

printf '%s\n' 'When: bootstrap runs with flags that avoid external initialization and global mutations'
BOOTSTRAP_FLAGS=(
    --repo "$REPO_DIR"
    --skip-init
    --no-speckit-registration
    --no-global-agent-pointers
)

if ! python3 "$SETUP_SCRIPT" "${BOOTSTRAP_FLAGS[@]}" > "$FIRST_LOG" 2>&1; then
    printf '%s\n' 'FAIL: first bootstrap invocation failed:'
    cat "$FIRST_LOG"
    exit 1
fi

printf '%s\n' 'Then: generated pointers use relocatable paths and preserve repository content'
POINTER_FILES=(
    AGENTS.md
    CLAUDE.md
    CODEBUDDY.md
    GEMINI.md
    IFLOW.md
    KIMI.md
    QODER.md
    QWEN.md
    SHAI.md
    TABNINE.md
    .augment/rules/specify-rules.md
    .cursor/rules/specify-rules.mdc
    .github/copilot-instructions.md
    .junie/AGENTS.md
    .kilocode/rules/specify-rules.md
    .roo/rules/specify-rules.md
    .trae/rules/project_rules.md
    .vibe/agents/specify-agents.md
    .windsurf/rules/specify-rules.md
    openspec/README.md
    .specify/README.md
)

for pointer_file in "${POINTER_FILES[@]}"; do
    pointer_path="$REPO_DIR/$pointer_file"
    assert_file "$pointer_path" "generated pointer exists: $pointer_file"
    assert_contains "$pointer_path" '$HOME/.agents' "pointer uses literal HOME agent root: $pointer_file"
    assert_not_contains "$pointer_path" "$FIXTURE_HOME" "pointer omits fixture absolute HOME: $pointer_file"
    assert_not_contains "$pointer_path" "$AGENT_PROTOCOL_ROOT" "pointer omits fixture protocol root: $pointer_file"
done

assert_contains \
    "$REPO_DIR/AGENTS.md" \
    'hand-written content must survive bootstrap' \
    'hand-written content outside markers is preserved'
assert_file "$REPO_DIR/openspec/config.yaml" 'OpenSpec config exists'
assert_contains "$REPO_DIR/openspec/config.yaml" 'schema: spec-driven' 'OpenSpec config selects spec-driven schema'
assert_file "$REPO_DIR/.claude/commands/opsx/apply.md" 'command template comes from isolated template root'
assert_file "$WORKFLOW_PROTOCOL" 'generated workflow protocol exists'
assert_contains "$WORKFLOW_PROTOCOL" 'maximum of **25** accepted' 'workflow protocol carries the 25-question clarify limit'
assert_contains "$WORKFLOW_PROTOCOL" 'Ask one question at a time' 'workflow protocol carries one-question-at-a-time clarify rule'
assert_file "$BOOTSTRAP_PROTOCOL" 'generated bootstrap protocol exists'
assert_contains "$BOOTSTRAP_PROTOCOL" 'copied directories' 'bootstrap protocol describes copied skill directories'
assert_not_contains "$BOOTSTRAP_PROTOCOL" 'skills links' 'bootstrap protocol does not describe repo-local skills as links'
assert_file "$EXPLORE_COMMAND" 'generated explore command exists'
if [[ -f "$EXPLORE_COMMAND" ]] && grep -Eiq 'executable work.{0,80}exclusively.{0,80}specs/<feature>/tasks\.md' "$EXPLORE_COMMAND"; then
    pass 'explore routes executable work exclusively to Speckit tasks'
else
    fail 'explore routes executable work exclusively to Speckit tasks'
fi
assert_contains "$EXPLORE_COMMAND" 'governance/handoff milestones only' 'explore limits OpenSpec tasks to governance handoff'
assert_not_contains "$EXPLORE_COMMAND" '| New work identified | `tasks.md` |' 'explore rejects direct OpenSpec task routing'
assert_file "$EXTENSION_MANIFEST" 'installed Git extension manifest exists'
assert_file "$REGISTRY_PATH" 'extension registry exists'

EXTENSION_DIGEST="$(sha256sum "$EXTENSION_MANIFEST")"
EXTENSION_DIGEST="${EXTENSION_DIGEST%% *}"
EXPECTED_MANIFEST_HASH="sha256:$EXTENSION_DIGEST"
if REGISTRY_MANIFEST_HASH="$(
    python3 - "$REGISTRY_PATH" 2>/dev/null <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as registry_file:
    registry = json.load(registry_file)

print(registry["extensions"]["git"]["manifest_hash"])
PY
)"; then
    assert_equal "$REGISTRY_MANIFEST_HASH" "$EXPECTED_MANIFEST_HASH" 'registry Git manifest hash matches installed manifest'
else
    fail 'registry Git manifest hash is readable JSON'
fi

for skill_home in .claude .codex .agents; do
    skill_path="$REPO_DIR/$skill_home/skills/ct"
    assert_regular_directory "$skill_path" "skill is a regular directory: $skill_home"
    assert_file "$skill_path/SKILL.md" "skill contents are copied: $skill_home"
done

snapshot_repo "$REPO_DIR" > "$FIRST_SNAPSHOT"

if ! python3 "$SETUP_SCRIPT" "${BOOTSTRAP_FLAGS[@]}" > "$SECOND_LOG" 2>&1; then
    printf '%s\n' 'FAIL: second bootstrap invocation failed:'
    cat "$SECOND_LOG"
    exit 1
fi

snapshot_repo "$REPO_DIR" > "$SECOND_SNAPSHOT"

if cmp -s "$FIRST_SNAPSHOT" "$SECOND_SNAPSHOT"; then
    pass 'second bootstrap preserves repository file hashes'
else
    fail 'second bootstrap changes repository file hashes'
fi

printf '%s\n' 'Given: a fresh repository and protocol root with sentinel files'
DRY_RUN_HOME="$TMPDIR_ROOT/dry-run-home"
DRY_RUN_PROTOCOL_ROOT="$TMPDIR_ROOT/dry-run-agent-protocol"
DRY_RUN_REPO="$TMPDIR_ROOT/dry-run-repo"
DRY_RUN_REPO_SNAPSHOT_BEFORE="$TMPDIR_ROOT/dry-run-repo.before"
DRY_RUN_REPO_SNAPSHOT_AFTER="$TMPDIR_ROOT/dry-run-repo.after"
DRY_RUN_PROTOCOL_SNAPSHOT_BEFORE="$TMPDIR_ROOT/dry-run-protocol.before"
DRY_RUN_PROTOCOL_SNAPSHOT_AFTER="$TMPDIR_ROOT/dry-run-protocol.after"
mkdir -p "$DRY_RUN_HOME/.agents/skills/ct" "$DRY_RUN_PROTOCOL_ROOT" "$DRY_RUN_REPO"
printf '%s\n' 'dry-run skill fixture' > "$DRY_RUN_HOME/.agents/skills/ct/SKILL.md"
printf '%s\n' 'repo sentinel' > "$DRY_RUN_REPO/.dry-run-sentinel"
printf '%s\n' 'protocol sentinel' > "$DRY_RUN_PROTOCOL_ROOT/.dry-run-sentinel"
git init -q "$DRY_RUN_REPO"
snapshot_repo "$DRY_RUN_REPO" > "$DRY_RUN_REPO_SNAPSHOT_BEFORE"
snapshot_repo "$DRY_RUN_PROTOCOL_ROOT" > "$DRY_RUN_PROTOCOL_SNAPSHOT_BEFORE"

printf '%s\n' 'When: bootstrap runs with --dry-run against the fresh fixture'
DRY_RUN_FLAGS=(
    --repo "$DRY_RUN_REPO"
    --dry-run
    --skip-init
    --no-speckit-registration
    --no-global-agent-pointers
)
export HOME="$DRY_RUN_HOME"
export AGENT_PROTOCOL_ROOT="$DRY_RUN_PROTOCOL_ROOT"
if ! python3 "$SETUP_SCRIPT" "${DRY_RUN_FLAGS[@]}" > "$TMPDIR_ROOT/dry-run.log" 2>&1; then
    printf '%s\n' 'FAIL: dry-run bootstrap invocation failed:'
    cat "$TMPDIR_ROOT/dry-run.log"
    exit 1
fi

printf '%s\n' 'Then: --dry-run leaves both fresh fixture trees byte-for-byte unchanged'
snapshot_repo "$DRY_RUN_REPO" > "$DRY_RUN_REPO_SNAPSHOT_AFTER"
snapshot_repo "$DRY_RUN_PROTOCOL_ROOT" > "$DRY_RUN_PROTOCOL_SNAPSHOT_AFTER"
if cmp -s "$DRY_RUN_REPO_SNAPSHOT_BEFORE" "$DRY_RUN_REPO_SNAPSHOT_AFTER"; then
    pass '--dry-run preserves fresh repository paths and hashes'
else
    fail '--dry-run changes fresh repository paths or hashes'
fi
if cmp -s "$DRY_RUN_PROTOCOL_SNAPSHOT_BEFORE" "$DRY_RUN_PROTOCOL_SNAPSHOT_AFTER"; then
    pass '--dry-run preserves fresh protocol-root paths and hashes'
else
    fail '--dry-run changes fresh protocol-root paths or hashes'
fi

if (( failures == 0 )); then
    printf '%s\n' 'GREEN: OpenSpec bootstrap regression test passed'
else
    printf 'RED: %d assertion(s) failed\n' "$failures"
    exit 1
fi
