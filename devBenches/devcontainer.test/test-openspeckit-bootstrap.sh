#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
WORKBENCH_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
SETUP_SCRIPT="$WORKBENCH_ROOT/devBenches/base-image/files/openspeckit/setup-openspeckit"
WORKTREE_TEMPLATE_ROOT="$WORKBENCH_ROOT/devBenches/base-image/files/speckit-worktree/templates"
COMMAND_TEMPLATE_ROOT="$WORKBENCH_ROOT/devBenches/base-image/files/claude/commands/opsx"
if [[ ! -f "$SETUP_SCRIPT" ]]; then
    SETUP_SCRIPT="/usr/local/bin/setup-openspeckit"
fi
if [[ ! -d "$WORKTREE_TEMPLATE_ROOT" ]]; then
    WORKTREE_TEMPLATE_ROOT="/usr/local/share/speckit-worktree/templates"
fi
if [[ ! -d "$COMMAND_TEMPLATE_ROOT" ]]; then
    COMMAND_TEMPLATE_ROOT="/etc/skel/.claude/commands/opsx"
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

FIXTURE_HOME="$TMPDIR_ROOT/home"
AGENT_PROTOCOL_ROOT="$TMPDIR_ROOT/agent-protocol"
REPO_DIR="$TMPDIR_ROOT/repo"
REPO_SKILL_PATH="$REPO_DIR/.agents/skills/ct"
EXPLORE_COMMAND="$REPO_DIR/.claude/commands/opsx/explore.md"
APPLY_COMMAND="$REPO_DIR/.claude/commands/opsx/apply.md"
PROPOSE_COMMAND="$REPO_DIR/.claude/commands/opsx/propose.md"
REGISTRY_PATH="$REPO_DIR/.specify/extensions/.registry"
EXTENSION_MANIFEST="$REPO_DIR/.specify/extensions/git/extension.yml"
WORKFLOW_PROTOCOL="$AGENT_PROTOCOL_ROOT/protocols/openspec-speckit-workflow.md"
BOOTSTRAP_PROTOCOL="$AGENT_PROTOCOL_ROOT/protocols/project-agent-bootstrap.md"
FIRST_SNAPSHOT="$TMPDIR_ROOT/first.snapshot"
SECOND_SNAPSHOT="$TMPDIR_ROOT/second.snapshot"
FIRST_MODE_SNAPSHOT="$TMPDIR_ROOT/first-mode.snapshot"
SECOND_MODE_SNAPSHOT="$TMPDIR_ROOT/second-mode.snapshot"
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

assert_not_exists() {
    local path="$1"
    local label="$2"
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        pass "$label"
    else
        fail "$label: unexpected path $path"
    fi
}

assert_mode() {
    local path="$1"
    local expected="$2"
    local label="$3"
    if [[ -e "$path" ]]; then
        assert_equal "$(stat -c '%a' "$path")" "$expected" "$label"
    else
        fail "$label: missing $path"
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

snapshot_repo_modes() {
    local repo="$1"
    (
        cd "$repo"
        find . -path './.git' -prune -o \( -type d -o -type f -o -type l \) -printf '%m %y %p %l\n' | sort
    )
}

printf '%s\n' 'Given: an isolated HOME, protocol root, and checked-in template roots'
mkdir -p \
    "$FIXTURE_HOME/.claude/skills/ct" \
    "$FIXTURE_HOME/.codex/skills/ct" \
    "$FIXTURE_HOME/.agents/skills/ct" \
    "$REPO_DIR"

for skill_home in .claude .codex .agents; do
    skill_root="$FIXTURE_HOME/$skill_home/skills"
    mkdir -p \
        "$skill_root/ct/bin" \
        "$skill_root/speckit-clarify" \
        "$skill_root/speckit-specify" \
        "$skill_root/speckit-git-feature" \
        "$skill_root/speckit-git-validate" \
        "$skill_root/claude-session-driver" \
        "$skill_root/speckit-claude-driver"
    printf '%s\n' 'fixture skill' > "$skill_root/ct/SKILL.md"
    printf '%s\n' 'fixture: yaml' > "$skill_root/ct/config.yaml"
    printf '%s\n' 'fixture: yml' > "$skill_root/ct/config.yml"
    printf '%s\n' '{"fixture": "json"}' > "$skill_root/ct/config.json"
    printf '%s\n' 'fixture text' > "$skill_root/ct/notes.txt"
    printf '%s\n' 'fixture binary data' > "$skill_root/ct/bin/data.bin"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "skill script ran"' > "$skill_root/ct/bin/run.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "extensionless runner ran"' > "$skill_root/ct/bin/runner"
    chmod 0777 \
        "$skill_root/ct" \
        "$skill_root/ct/bin" \
        "$skill_root/ct/bin/run.sh" \
        "$skill_root/ct/bin/runner"
    chmod 0777 \
        "$skill_root/ct/SKILL.md" \
        "$skill_root/ct/config.yaml" \
        "$skill_root/ct/config.yml" \
        "$skill_root/ct/config.json"
    chmod 0666 \
        "$skill_root/ct/notes.txt" \
        "$skill_root/ct/bin/data.bin"

    printf '%s\n' 'GLOBAL SKILL MUST NOT OVERRIDE WORKTREE OVERLAY' > "$skill_root/speckit-specify/SKILL.md"
    printf '%s\n' 'GLOBAL SKILL MUST NOT OVERRIDE WORKTREE OVERLAY' > "$skill_root/speckit-git-feature/SKILL.md"
    printf '%s\n' 'GLOBAL STALE VALIDATOR MUST NOT OVERRIDE WORKTREE OVERLAY' > "$skill_root/speckit-git-validate/SKILL.md"

    cat > "$skill_root/speckit-clarify/SKILL.md" <<'EOF'
---
description: Ask up to 5 highly targeted clarification questions.
---
Generate a prioritized queue of candidate clarification questions (maximum 5).
- Maximum of 5 total questions across the whole session.
- Use 2–5 distinct, mutually exclusive options.
- Constrain short answers to "Answer in <=5 words".
- If more than 5 categories remain unresolved, select the top 5.
- Present EXACTLY ONE question at a time.
- Stop when you reach 5 asked questions.
- Total asked questions ≤ 5.
- Never exceed 5 total asked questions.
EOF

    printf '%s\n' 'DANGEROUS DRIVER MUST NOT BE COPIED' > "$skill_root/claude-session-driver/SKILL.md"
    printf '%s\n' 'DANGEROUS DRIVER MUST NOT BE COPIED' > "$skill_root/speckit-claude-driver/SKILL.md"

    for action in apply-change archive-change explore propose; do
        mkdir -p "$skill_root/openspec-$action"
        printf '%s\n' 'DIRECT OPEN SPEC IMPLEMENTATION MUST NOT BE COPIED' > "$skill_root/openspec-$action/SKILL.md"
    done
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
    assert_contains "$pointer_path" '${AGENT_PROTOCOL_ROOT:-$HOME/.agents}' "pointer uses portable protocol root fallback: $pointer_file"
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
assert_file "$APPLY_COMMAND" 'generated apply command exists'
assert_contains "$APPLY_COMMAND" 'Only the lead may edit the linked Speckit `tasks.md`' 'apply reserves the shared task ledger for the lead'
assert_contains "$APPLY_COMMAND" 'Do not edit the linked Speckit `tasks.md`' 'apply forbids teammate writes to the shared task ledger'
assert_contains "$APPLY_COMMAND" 'completed task IDs, changed files, tests run, and blockers' 'apply requires structured teammate evidence'
assert_contains "$APPLY_COMMAND" 'verify each package result before marking' 'apply requires lead verification before task completion'
assert_contains "$APPLY_COMMAND" 'Only the lead may edit or check off the linked Speckit `tasks.md`' 'apply guardrails reserve task edits and checkoffs for the lead'
assert_not_contains "$APPLY_COMMAND" 'Each agent only checks off its own assigned Speckit tasks' 'apply contains no teammate task-checkoff contradiction'
assert_file "$PROPOSE_COMMAND" 'generated propose command exists'
assert_not_contains "$PROPOSE_COMMAND" '/opsx:analyze' 'propose recommends only installed OPSX commands'
assert_file "$EXTENSION_MANIFEST" 'installed Git extension manifest exists'
assert_file "$REGISTRY_PATH" 'extension registry exists'
FRESH_GIT_CONFIG="$REPO_DIR/.specify/extensions/git/git-config.yml"
assert_file "$FRESH_GIT_CONFIG" 'newly copied Git overlay config exists'
assert_contains "$FRESH_GIT_CONFIG" 'branch_numbering: sequential' 'newly copied Git overlay uses sequential numbering'
assert_contains "$FRESH_GIT_CONFIG" 'checkout_mode: worktree' 'newly copied Git overlay uses worktree checkout mode'
assert_contains "$FRESH_GIT_CONFIG" 'base_branch: main' 'newly copied Git overlay uses the resolved base branch'
assert_contains "$FRESH_GIT_CONFIG" 'worktree_root: ../repo-worktrees' 'newly copied Git overlay uses the repository worktree root'

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
    assert_mode "$skill_path" 755 "copied skill directory is portable: $skill_home"
    assert_mode "$skill_path/bin" 755 "copied nested skill directory is portable: $skill_home"
    for declarative_file in SKILL.md config.yaml config.yml config.json; do
        assert_mode "$skill_path/$declarative_file" 644 "copied executable-source declarative file normalizes to 0644: $skill_home/$declarative_file"
    done
    assert_mode "$skill_path/notes.txt" 644 "copied non-declarative file is portable: $skill_home/notes.txt"
    assert_mode "$skill_path/bin/data.bin" 644 "copied nested non-executable file is portable: $skill_home/bin/data.bin"
    assert_mode "$skill_path/bin/run.sh" 755 "copied executable script mode is portable: $skill_home/bin/run.sh"
    assert_mode "$skill_path/bin/runner" 755 "copied extensionless executable mode is portable: $skill_home/bin/runner"
    if [[ -x "$skill_path/bin/run.sh" ]]; then
        pass "copied executable script stays executable: $skill_home"
    else
        fail "copied executable script stays executable: $skill_home"
    fi
    assert_equal "$("$skill_path/bin/run.sh")" 'skill script ran' "copied executable script runs: $skill_home"
    assert_equal "$("$skill_path/bin/runner")" 'extensionless runner ran' "copied extensionless executable runs: $skill_home"

    clarify_path="$REPO_DIR/$skill_home/skills/speckit-clarify/SKILL.md"
    assert_file "$clarify_path" "clarify skill is copied: $skill_home"
    assert_contains "$clarify_path" 'up to 25 highly targeted clarification questions' "clarify description uses shared quota: $skill_home"
    assert_contains "$clarify_path" 'maximum 25' "clarify queue uses shared quota: $skill_home"
    assert_contains "$clarify_path" 'Maximum of 25 total questions' "clarify session uses shared quota: $skill_home"
    assert_contains "$clarify_path" 'If more than 25 categories remain unresolved, select the top 25' "clarify prioritization uses shared quota: $skill_home"
    assert_contains "$clarify_path" 'Present EXACTLY ONE question at a time' "clarify asks one question at a time: $skill_home"
    assert_contains "$clarify_path" 'reach 25 asked questions' "clarify stop condition uses shared quota: $skill_home"
    assert_contains "$clarify_path" 'Total asked questions ≤ 25' "clarify validation uses shared quota: $skill_home"
    assert_contains "$clarify_path" 'Never exceed 25 total asked questions' "clarify behavior rule uses shared quota: $skill_home"
    assert_contains "$clarify_path" '2–5 distinct, mutually exclusive options' "clarify preserves option-count limit: $skill_home"
    assert_contains "$clarify_path" 'Answer in <=5 words' "clarify preserves answer-length limit: $skill_home"

    assert_not_exists "$REPO_DIR/$skill_home/skills/claude-session-driver" "Claude session driver is excluded: $skill_home"
    assert_not_exists "$REPO_DIR/$skill_home/skills/speckit-claude-driver" "Speckit Claude driver is excluded: $skill_home"
done

printf '%s\n' 'Given: a fresh repository and a current Specify CLI without --ai-skills'
FRESH_INIT_REPO="$TMPDIR_ROOT/fresh-init-repo"
FRESH_INIT_BIN="$TMPDIR_ROOT/fresh-init-bin"
FRESH_INIT_LOG="$TMPDIR_ROOT/fresh-init.log"
mkdir -p "$FRESH_INIT_REPO" "$FRESH_INIT_BIN"
cat > "$FRESH_INIT_BIN/specify" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FRESH_INIT_LOG"
for argument in "$@"; do
    if [[ "$argument" == '--ai-skills' ]]; then
        printf '%s\n' 'No such option: --ai-skills' >&2
        exit 2
    fi
done
mkdir -p .specify/templates .claude
printf '%s\n' '{"integration":"claude"}' > .specify/init-options.json
printf '%s\n' '{"integration":"claude"}' > .specify/integration.json
printf '%s\n' '# Spec template' > .specify/templates/spec-template.md
printf '%s\n' '# Agent instructions' > .claude/AGENTS.md
EOF
chmod 0755 "$FRESH_INIT_BIN/specify"
git init -q "$FRESH_INIT_REPO"

printf '%s\n' 'When: bootstrap initializes the fresh repository with a supported current Specify CLI'
if PATH="$FRESH_INIT_BIN:/usr/bin:/bin" FRESH_INIT_LOG="$FRESH_INIT_LOG" python3 "$SETUP_SCRIPT" \
    --repo "$FRESH_INIT_REPO" \
    --integration claude \
    --no-speckit-registration \
    --no-worktrees \
    --no-repo-agent-pointers \
    --no-skill-links \
    --no-global-agent-pointers > "$TMPDIR_ROOT/fresh-init-bootstrap.log" 2>&1; then
    pass 'fresh bootstrap accepts a current Specify CLI'
else
    fail 'fresh bootstrap accepts a current Specify CLI'
    cat "$TMPDIR_ROOT/fresh-init-bootstrap.log"
fi

printf '%s\n' 'Then: initialization preserves supported arguments and creates expected outputs'
assert_file "$FRESH_INIT_LOG" 'fresh bootstrap records the Specify invocation'
assert_not_contains "$FRESH_INIT_LOG" '--ai-skills' 'fresh bootstrap does not pass the removed Specify option'
for preserved_argument in --here --force --integration --script sh --ignore-agent-tools; do
    assert_contains "$FRESH_INIT_LOG" "$preserved_argument" "fresh bootstrap preserves Specify argument: $preserved_argument"
done
assert_file "$FRESH_INIT_REPO/.specify/init-options.json" 'fresh initialization creates init options'
assert_file "$FRESH_INIT_REPO/.specify/integration.json" 'fresh initialization creates integration state'
assert_file "$FRESH_INIT_REPO/.specify/templates/spec-template.md" 'fresh initialization creates expected template'
assert_file "$FRESH_INIT_REPO/.claude/AGENTS.md" 'fresh initialization creates expected integration output'

printf '%s\n' 'Given: a stock-like Git overlay whose feature script has legacy compatibility markers but whose helper lacks load_git_worktrees'
STOCK_OVERLAY_REPO="$TMPDIR_ROOT/stock-overlay-repo"
STOCK_OVERLAY_PROTOCOL_ROOT="$TMPDIR_ROOT/stock-overlay-protocol"
STOCK_GIT_OVERLAY="$STOCK_OVERLAY_REPO/.specify/extensions/git"
mkdir -p "$STOCK_GIT_OVERLAY"
cp -a "$WORKTREE_TEMPLATE_ROOT/specify/extensions/git/." "$STOCK_GIT_OVERLAY/"
cat > "$STOCK_GIT_OVERLAY/scripts/bash/git-common.sh" <<'EOF'
#!/usr/bin/env bash
has_git() {
    command -v git >/dev/null 2>&1
}
EOF
git init -q "$STOCK_OVERLAY_REPO"

printf '%s\n' 'When: bootstrap runs normally without --force against the incompatible stock-like overlay'
export AGENT_PROTOCOL_ROOT="$STOCK_OVERLAY_PROTOCOL_ROOT"
export SPECKIT_WORKTREE_TEMPLATE_ROOT="$WORKTREE_TEMPLATE_ROOT"
if ! python3 "$SETUP_SCRIPT" \
    --repo "$STOCK_OVERLAY_REPO" \
    --skip-init \
    --no-speckit-registration \
    --no-repo-agent-pointers \
    --no-skill-links \
    --no-global-agent-pointers > "$TMPDIR_ROOT/stock-overlay.log" 2>&1; then
    printf '%s\n' 'FAIL: stock-overlay bootstrap invocation failed:'
    cat "$TMPDIR_ROOT/stock-overlay.log"
    exit 1
fi

printf '%s\n' 'Then: normal setup replaces every managed file with the complete checked-in Git overlay'
STOCK_OVERLAY_MISMATCHES=0
while IFS= read -r -d '' overlay_source; do
    overlay_relative_path="${overlay_source#"$WORKTREE_TEMPLATE_ROOT/specify/extensions/git/"}"
    if ! cmp -s "$overlay_source" "$STOCK_GIT_OVERLAY/$overlay_relative_path"; then
        printf 'FAIL: normal setup did not restore managed Git overlay file: %s\n' "$overlay_relative_path"
        STOCK_OVERLAY_MISMATCHES=$((STOCK_OVERLAY_MISMATCHES + 1))
    fi
done < <(find "$WORKTREE_TEMPLATE_ROOT/specify/extensions/git" -type f -print0)
assert_equal "$STOCK_OVERLAY_MISMATCHES" 0 'normal setup restores the complete checked-in Git overlay without --force'
assert_contains \
    "$STOCK_GIT_OVERLAY/scripts/bash/git-common.sh" \
    'load_git_worktrees()' \
    'normal setup restores the helper required by create-new-feature.sh'

printf '%s\n' '# repository-specific complete overlay customization' >> "$STOCK_GIT_OVERLAY/scripts/bash/git-common.sh"
if ! python3 "$SETUP_SCRIPT" \
    --repo "$STOCK_OVERLAY_REPO" \
    --skip-init \
    --no-speckit-registration \
    --no-repo-agent-pointers \
    --no-skill-links \
    --no-global-agent-pointers > "$TMPDIR_ROOT/custom-complete-overlay.log" 2>&1; then
    printf '%s\n' 'FAIL: complete customized overlay bootstrap invocation failed:'
    cat "$TMPDIR_ROOT/custom-complete-overlay.log"
    exit 1
fi
assert_contains \
    "$STOCK_GIT_OVERLAY/scripts/bash/git-common.sh" \
    'repository-specific complete overlay customization' \
    'normal setup preserves a structurally complete customized Git overlay'

printf '%s\n' 'Given: an existing Git workflow config with customized top-level values, comments, and nested YAML'
CUSTOM_GIT_CONFIG="$STOCK_GIT_OVERLAY/git-config.yml"
CUSTOM_GIT_CONFIG_BEFORE="$TMPDIR_ROOT/custom-git-config.before"
cat > "$CUSTOM_GIT_CONFIG" <<'EOF'
# repository-specific Git workflow configuration
branch_numbering: timestamp
branch_template: "{author}/{number}-{slug}"
branch_prefix: "teams/{app}"
checkout_mode: branch
base_branch: integration
worktree_root: ../custom-worktrees
repository_extension: retained
nested_extension:
  enabled: true
EOF
cp "$CUSTOM_GIT_CONFIG" "$CUSTOM_GIT_CONFIG_BEFORE"

printf '%s\n' 'When: bootstrap reruns normally without Git workflow overrides'
if ! python3 "$SETUP_SCRIPT" \
    --repo "$STOCK_OVERLAY_REPO" \
    --skip-init \
    --no-speckit-registration \
    --no-repo-agent-pointers \
    --no-skill-links \
    --no-global-agent-pointers > "$TMPDIR_ROOT/custom-git-config.log" 2>&1; then
    printf '%s\n' 'FAIL: customized Git workflow config bootstrap invocation failed:'
    cat "$TMPDIR_ROOT/custom-git-config.log"
    exit 1
fi

printf '%s\n' 'Then: every customized value and the original YAML shape survive the normal rerun'
if cmp -s "$CUSTOM_GIT_CONFIG_BEFORE" "$CUSTOM_GIT_CONFIG"; then
    pass 'normal rerun preserves the complete customized Git workflow config'
else
    fail 'normal rerun changes the customized Git workflow config'
fi

printf '%s\n' 'When: bootstrap reruns with explicit base branch and worktree root overrides'
if ! python3 "$SETUP_SCRIPT" \
    --repo "$STOCK_OVERLAY_REPO" \
    --skip-init \
    --base-branch release \
    --worktree-root ../release-worktrees \
    --no-speckit-registration \
    --no-repo-agent-pointers \
    --no-skill-links \
    --no-global-agent-pointers > "$TMPDIR_ROOT/overridden-git-config.log" 2>&1; then
    printf '%s\n' 'FAIL: overridden Git workflow config bootstrap invocation failed:'
    cat "$TMPDIR_ROOT/overridden-git-config.log"
    exit 1
fi

printf '%s\n' 'Then: explicit overrides change only their respective Git workflow values'
assert_contains "$CUSTOM_GIT_CONFIG" 'branch_numbering: timestamp' 'explicit overrides preserve customized branch numbering'
assert_contains "$CUSTOM_GIT_CONFIG" 'branch_template: "{author}/{number}-{slug}"' 'explicit overrides preserve customized branch template'
assert_contains "$CUSTOM_GIT_CONFIG" 'branch_prefix: "teams/{app}"' 'explicit overrides preserve customized branch prefix'
assert_contains "$CUSTOM_GIT_CONFIG" 'checkout_mode: branch' 'explicit overrides preserve customized checkout mode'
assert_contains "$CUSTOM_GIT_CONFIG" 'base_branch: release' 'explicit base branch overrides the customized value'
assert_contains "$CUSTOM_GIT_CONFIG" 'worktree_root: ../release-worktrees' 'explicit worktree root overrides the customized value'
assert_contains "$CUSTOM_GIT_CONFIG" '# repository-specific Git workflow configuration' 'explicit overrides preserve comments'
assert_contains "$CUSTOM_GIT_CONFIG" 'repository_extension: retained' 'explicit overrides preserve unknown top-level values'
assert_contains "$CUSTOM_GIT_CONFIG" '  enabled: true' 'explicit overrides preserve nested YAML'

printf '%s\n' 'Given: an existing Git workflow config missing the required worktree keys'
INCOMPLETE_GIT_CONFIG_REPO="$TMPDIR_ROOT/incomplete-git-config-repo"
INCOMPLETE_GIT_CONFIG_PROTOCOL_ROOT="$TMPDIR_ROOT/incomplete-git-config-protocol"
INCOMPLETE_GIT_OVERLAY="$INCOMPLETE_GIT_CONFIG_REPO/.specify/extensions/git"
mkdir -p "$INCOMPLETE_GIT_OVERLAY"
cp -a "$WORKTREE_TEMPLATE_ROOT/specify/extensions/git/." "$INCOMPLETE_GIT_OVERLAY/"
cat > "$INCOMPLETE_GIT_OVERLAY/git-config.yml" <<'EOF'
# incomplete repository-specific Git workflow configuration
branch_template: "{app}/{number}-{slug}"
branch_prefix: feature
repository_extension: retained
nested_extension:
  enabled: true
EOF
GIT_MASTER=1 git init -q -b fixture-base "$INCOMPLETE_GIT_CONFIG_REPO"
GIT_MASTER=1 git -C "$INCOMPLETE_GIT_CONFIG_REPO" \
    -c user.name='Bootstrap Test' \
    -c user.email='bootstrap-test@example.invalid' \
    commit -q --allow-empty -m 'fixture base'

printf '%s\n' 'When: bootstrap reruns without overrides against the incomplete Git workflow config'
export AGENT_PROTOCOL_ROOT="$INCOMPLETE_GIT_CONFIG_PROTOCOL_ROOT"
if ! python3 "$SETUP_SCRIPT" \
    --repo "$INCOMPLETE_GIT_CONFIG_REPO" \
    --skip-init \
    --no-speckit-registration \
    --no-repo-agent-pointers \
    --no-skill-links \
    --no-global-agent-pointers > "$TMPDIR_ROOT/incomplete-git-config.log" 2>&1; then
    printf '%s\n' 'FAIL: incomplete Git workflow config bootstrap invocation failed:'
    cat "$TMPDIR_ROOT/incomplete-git-config.log"
    exit 1
fi

printf '%s\n' 'Then: missing required keys receive defaults while existing YAML content survives'
INCOMPLETE_GIT_CONFIG="$INCOMPLETE_GIT_OVERLAY/git-config.yml"
assert_contains "$INCOMPLETE_GIT_CONFIG" 'branch_numbering: sequential' 'missing branch numbering receives the sequential default'
assert_contains "$INCOMPLETE_GIT_CONFIG" 'checkout_mode: worktree' 'missing checkout mode receives the worktree default'
assert_contains "$INCOMPLETE_GIT_CONFIG" 'base_branch: fixture-base' 'missing base branch receives the resolved repository default'
assert_contains "$INCOMPLETE_GIT_CONFIG" 'worktree_root: ../incomplete-git-config-repo-worktrees' 'missing worktree root receives the repository default'
assert_contains "$INCOMPLETE_GIT_CONFIG" 'branch_template: "{app}/{number}-{slug}"' 'missing-key initialization preserves branch template'
assert_contains "$INCOMPLETE_GIT_CONFIG" 'branch_prefix: feature' 'missing-key initialization preserves branch prefix'
assert_contains "$INCOMPLETE_GIT_CONFIG" 'repository_extension: retained' 'missing-key initialization preserves unknown top-level values'
assert_contains "$INCOMPLETE_GIT_CONFIG" '  enabled: true' 'missing-key initialization preserves nested YAML'

OPEN_SPEC_SKILLS=(
    'apply-change:apply'
    'archive-change:archive'
    'explore:explore'
    'propose:propose'
)
for skill_home in .claude .codex .agents; do
    if [[ "$skill_home" == '.claude' ]]; then
        command_prefix='../../commands/opsx'
    else
        command_prefix='../../../.claude/commands/opsx'
    fi
    for skill_mapping in "${OPEN_SPEC_SKILLS[@]}"; do
        skill_name="${skill_mapping%%:*}"
        action="${skill_mapping##*:}"
        wrapper="$REPO_DIR/$skill_home/skills/openspec-$skill_name/SKILL.md"
        assert_file "$wrapper" "OpenSpec skill wrapper exists: $skill_home/$action"
        assert_contains "$wrapper" "$command_prefix/$action.md" "OpenSpec wrapper uses portable canonical path: $skill_home/$action"
        assert_contains "$wrapper" 'source workflow' "OpenSpec wrapper names the command as source workflow: $skill_home/$action"
        assert_contains "$wrapper" 'Do not execute implementation tasks from OpenSpec artifacts' "OpenSpec wrapper rejects OpenSpec executable task authority: $skill_home/$action"
        assert_not_contains "$wrapper" 'DIRECT OPEN SPEC IMPLEMENTATION MUST NOT BE COPIED' "OpenSpec wrapper does not copy stale implementation: $skill_home/$action"
    done
done

snapshot_repo "$REPO_DIR" > "$FIRST_SNAPSHOT"
snapshot_repo_modes "$REPO_DIR" > "$FIRST_MODE_SNAPSHOT"

if ! python3 "$SETUP_SCRIPT" "${BOOTSTRAP_FLAGS[@]}" > "$SECOND_LOG" 2>&1; then
    printf '%s\n' 'FAIL: second bootstrap invocation failed:'
    cat "$SECOND_LOG"
    exit 1
fi

snapshot_repo "$REPO_DIR" > "$SECOND_SNAPSHOT"
snapshot_repo_modes "$REPO_DIR" > "$SECOND_MODE_SNAPSHOT"

if cmp -s "$FIRST_SNAPSHOT" "$SECOND_SNAPSHOT"; then
    pass 'second bootstrap preserves repository file hashes'
else
    fail 'second bootstrap changes repository file hashes'
fi

if cmp -s "$FIRST_MODE_SNAPSHOT" "$SECOND_MODE_SNAPSHOT"; then
    pass 'second bootstrap preserves repository modes'
else
    fail 'second bootstrap changes repository modes'
fi

assert_equal "$(grep -Fc '<!-- OPENSPEC-SPECKIT-GLOBAL:START -->' "$REPO_DIR/AGENTS.md")" 1 'second bootstrap keeps one managed start marker'
assert_equal "$(grep -Fc '<!-- OPENSPEC-SPECKIT-GLOBAL:END -->' "$REPO_DIR/AGENTS.md")" 1 'second bootstrap keeps one managed end marker'
assert_contains "$REPO_DIR/AGENTS.md" 'hand-written content must survive bootstrap' 'second bootstrap preserves content outside managed markers'

printf '%s\n' 'Given: a generated OpenSpec wrapper is replaced by a repository customization'
CUSTOM_WRAPPER="$REPO_DIR/.codex/skills/openspec-propose/SKILL.md"
printf '%s\n' 'repository-specific OpenSpec proposal customization' > "$CUSTOM_WRAPPER"

printf '%s\n' 'When: bootstrap reruns without --force'
if ! python3 "$SETUP_SCRIPT" "${BOOTSTRAP_FLAGS[@]}" > "$TMPDIR_ROOT/custom-wrapper.log" 2>&1; then
    printf '%s\n' 'FAIL: customized-wrapper bootstrap invocation failed:'
    cat "$TMPDIR_ROOT/custom-wrapper.log"
    exit 1
fi

printf '%s\n' 'Then: the repository customization is preserved'
assert_contains "$CUSTOM_WRAPPER" 'repository-specific OpenSpec proposal customization' 'normal rerun preserves customized OpenSpec skill'
assert_not_contains "$CUSTOM_WRAPPER" 'source workflow' 'normal rerun does not replace customized OpenSpec skill'

printf '%s\n' 'When: bootstrap reruns with --force'
if ! python3 "$SETUP_SCRIPT" "${BOOTSTRAP_FLAGS[@]}" --force > "$TMPDIR_ROOT/forced-wrapper.log" 2>&1; then
    printf '%s\n' 'FAIL: forced customized-wrapper bootstrap invocation failed:'
    cat "$TMPDIR_ROOT/forced-wrapper.log"
    exit 1
fi

printf '%s\n' 'Then: the governed wrapper is restored'
assert_contains "$CUSTOM_WRAPPER" '../../../.claude/commands/opsx/propose.md' '--force restores the portable canonical command path'
assert_contains "$CUSTOM_WRAPPER" 'source workflow' '--force restores the governed OpenSpec wrapper'
assert_not_contains "$CUSTOM_WRAPPER" 'repository-specific OpenSpec proposal customization' '--force removes the repository customization'

for overlay_mapping in \
    '.agents:agents' \
    '.claude:claude' \
    '.codex:codex'; do
    repo_agent_dir="${overlay_mapping%%:*}"
    template_agent_dir="${overlay_mapping##*:}"
    for overlay_skill in speckit-specify speckit-git-feature speckit-git-validate; do
        overlay_source="$WORKTREE_TEMPLATE_ROOT/$template_agent_dir/skills/$overlay_skill/SKILL.md"
        overlay_destination="$REPO_DIR/$repo_agent_dir/skills/$overlay_skill/SKILL.md"
        if cmp -s "$overlay_source" "$overlay_destination"; then
            pass "--force preserves checked-in worktree overlay: $repo_agent_dir/$overlay_skill"
        else
            fail "--force replaced checked-in worktree overlay: $repo_agent_dir/$overlay_skill"
        fi
        assert_not_contains \
            "$overlay_destination" \
            'GLOBAL SKILL MUST NOT OVERRIDE WORKTREE OVERLAY' \
            "global skill does not override worktree overlay: $repo_agent_dir/$overlay_skill"
        assert_not_contains \
            "$overlay_destination" \
            'GLOBAL STALE VALIDATOR MUST NOT OVERRIDE WORKTREE OVERLAY' \
            "stale global validator does not override worktree overlay: $repo_agent_dir/$overlay_skill"
        if [[ "$overlay_skill" == 'speckit-git-validate' && "$repo_agent_dir" == '.codex' ]]; then
            assert_contains \
                "$overlay_destination" \
                '../../../.agents/skills/speckit-git-validate/SKILL.md' \
                'Codex validator delegates to the canonical Agents workflow'
        elif [[ "$overlay_skill" == 'speckit-git-validate' ]]; then
            assert_contains \
                "$overlay_destination" \
                "final path segment" \
                "validator supports namespaced feature branches: $repo_agent_dir"
            assert_contains \
                "$overlay_destination" \
                '.specify/feature.json' \
                "validator honors the authoritative feature mapping: $repo_agent_dir"
        fi
    done
done

printf '%s\n' 'Given: a repository whose openspec directory is a symlink to an external directory'
UNSAFE_SCAFFOLD_REPO="$TMPDIR_ROOT/unsafe-scaffold-repo"
UNSAFE_SCAFFOLD_PROTOCOL_ROOT="$TMPDIR_ROOT/unsafe-scaffold-protocol"
UNSAFE_SCAFFOLD_EXTERNAL_DIR="$TMPDIR_ROOT/unsafe-scaffold-external"
UNSAFE_SCAFFOLD_SNAPSHOT_BEFORE="$TMPDIR_ROOT/unsafe-scaffold.before"
UNSAFE_SCAFFOLD_SNAPSHOT_AFTER="$TMPDIR_ROOT/unsafe-scaffold.after"
UNSAFE_SCAFFOLD_MODES_BEFORE="$TMPDIR_ROOT/unsafe-scaffold-modes.before"
UNSAFE_SCAFFOLD_MODES_AFTER="$TMPDIR_ROOT/unsafe-scaffold-modes.after"
mkdir -p "$UNSAFE_SCAFFOLD_REPO" "$UNSAFE_SCAFFOLD_EXTERNAL_DIR"
printf '%s\n' 'external scaffold sentinel' > "$UNSAFE_SCAFFOLD_EXTERNAL_DIR/sentinel.txt"
ln -s "$UNSAFE_SCAFFOLD_EXTERNAL_DIR" "$UNSAFE_SCAFFOLD_REPO/openspec"
snapshot_repo "$UNSAFE_SCAFFOLD_EXTERNAL_DIR" > "$UNSAFE_SCAFFOLD_SNAPSHOT_BEFORE"
snapshot_repo_modes "$UNSAFE_SCAFFOLD_EXTERNAL_DIR" > "$UNSAFE_SCAFFOLD_MODES_BEFORE"

printf '%s\n' 'When: bootstrap runs with --skip-init against the symlinked openspec directory'
export AGENT_PROTOCOL_ROOT="$UNSAFE_SCAFFOLD_PROTOCOL_ROOT"
if python3 "$SETUP_SCRIPT" \
    --repo "$UNSAFE_SCAFFOLD_REPO" \
    --skip-init \
    --preserve-readmes \
    --no-speckit-registration \
    --no-worktrees \
    --no-repo-agent-pointers \
    --no-skill-links \
    --no-global-agent-pointers > "$TMPDIR_ROOT/unsafe-scaffold.log" 2>&1; then
    fail 'bootstrap rejects a symlinked openspec scaffold directory'
else
    pass 'bootstrap rejects a symlinked openspec scaffold directory'
fi

printf '%s\n' 'Then: scaffold rejection leaves the external directory byte-for-byte unchanged'
snapshot_repo "$UNSAFE_SCAFFOLD_EXTERNAL_DIR" > "$UNSAFE_SCAFFOLD_SNAPSHOT_AFTER"
snapshot_repo_modes "$UNSAFE_SCAFFOLD_EXTERNAL_DIR" > "$UNSAFE_SCAFFOLD_MODES_AFTER"
assert_contains "$TMPDIR_ROOT/unsafe-scaffold.log" 'symlink parent' 'unsafe scaffold rejection identifies the symlinked parent'
assert_not_exists "$UNSAFE_SCAFFOLD_EXTERNAL_DIR/config.yaml" 'unsafe scaffold does not create external config.yaml'
if cmp -s "$UNSAFE_SCAFFOLD_SNAPSHOT_BEFORE" "$UNSAFE_SCAFFOLD_SNAPSHOT_AFTER"; then
    pass 'unsafe scaffold preserves external file paths and hashes'
else
    fail 'unsafe scaffold changes external file paths or hashes'
fi
if cmp -s "$UNSAFE_SCAFFOLD_MODES_BEFORE" "$UNSAFE_SCAFFOLD_MODES_AFTER"; then
    pass 'unsafe scaffold preserves external path types and modes'
else
    fail 'unsafe scaffold changes external path types or modes'
fi

printf '%s\n' 'Given: .specify is a symlink to an external directory and registration is enabled'
SYMLINK_SPECIFY_REPO="$TMPDIR_ROOT/symlink-specify-repo"
SYMLINK_SPECIFY_PROTOCOL_ROOT="$TMPDIR_ROOT/symlink-specify-protocol"
SYMLINK_SPECIFY_EXTERNAL_DIR="$TMPDIR_ROOT/symlink-specify-external"
SYMLINK_SPECIFY_BIN="$TMPDIR_ROOT/symlink-specify-bin"
SYMLINK_SPECIFY_SNAPSHOT_BEFORE="$TMPDIR_ROOT/symlink-specify.before"
SYMLINK_SPECIFY_SNAPSHOT_AFTER="$TMPDIR_ROOT/symlink-specify.after"
SYMLINK_SPECIFY_MODES_BEFORE="$TMPDIR_ROOT/symlink-specify-modes.before"
SYMLINK_SPECIFY_MODES_AFTER="$TMPDIR_ROOT/symlink-specify-modes.after"
mkdir -p \
    "$SYMLINK_SPECIFY_REPO" \
    "$SYMLINK_SPECIFY_EXTERNAL_DIR" \
    "$SYMLINK_SPECIFY_BIN"
printf '%s\n' 'external Speckit sentinel' > "$SYMLINK_SPECIFY_EXTERNAL_DIR/sentinel.txt"
printf '\377' > "$SYMLINK_SPECIFY_EXTERNAL_DIR/integration.json"
chmod 0700 "$SYMLINK_SPECIFY_EXTERNAL_DIR"
chmod 0600 \
    "$SYMLINK_SPECIFY_EXTERNAL_DIR/integration.json" \
    "$SYMLINK_SPECIFY_EXTERNAL_DIR/sentinel.txt"
ln -s "$SYMLINK_SPECIFY_EXTERNAL_DIR" "$SYMLINK_SPECIFY_REPO/.specify"
cat > "$SYMLINK_SPECIFY_BIN/specify" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'external registration mutation' > .specify/registration-mutated.txt
chmod 0777 .specify
chmod 0666 .specify/registration-mutated.txt
EOF
chmod 0755 "$SYMLINK_SPECIFY_BIN/specify"
git init -q "$SYMLINK_SPECIFY_REPO"
snapshot_repo "$SYMLINK_SPECIFY_EXTERNAL_DIR" > "$SYMLINK_SPECIFY_SNAPSHOT_BEFORE"
snapshot_repo_modes "$SYMLINK_SPECIFY_EXTERNAL_DIR" > "$SYMLINK_SPECIFY_MODES_BEFORE"

printf '%s\n' 'When: bootstrap runs registration with --skip-init'
export AGENT_PROTOCOL_ROOT="$SYMLINK_SPECIFY_PROTOCOL_ROOT"
if PATH="$SYMLINK_SPECIFY_BIN:/usr/bin:/bin" python3 "$SETUP_SCRIPT" \
    --repo "$SYMLINK_SPECIFY_REPO" \
    --skip-init \
    --preserve-readmes \
    --no-worktrees \
    --no-repo-agent-pointers \
    --no-skill-links \
    --no-global-agent-pointers > "$TMPDIR_ROOT/symlink-specify.log" 2>&1; then
    fail 'bootstrap rejects a symlinked .specify registration parent'
else
    pass 'bootstrap rejects a symlinked .specify registration parent'
fi

printf '%s\n' 'Then: registration rejection occurs before external bytes, types, or modes change'
snapshot_repo "$SYMLINK_SPECIFY_EXTERNAL_DIR" > "$SYMLINK_SPECIFY_SNAPSHOT_AFTER"
snapshot_repo_modes "$SYMLINK_SPECIFY_EXTERNAL_DIR" > "$SYMLINK_SPECIFY_MODES_AFTER"
assert_contains "$TMPDIR_ROOT/symlink-specify.log" 'symlink leaf' 'symlinked .specify rejection identifies the symlink'
assert_not_contains "$TMPDIR_ROOT/symlink-specify.log" 'UnicodeDecodeError' 'symlinked .specify rejection precedes integration discovery'
if cmp -s "$SYMLINK_SPECIFY_SNAPSHOT_BEFORE" "$SYMLINK_SPECIFY_SNAPSHOT_AFTER"; then
    pass 'symlinked .specify preserves external file paths and hashes'
else
    fail 'symlinked .specify changes external file paths or hashes'
fi
if cmp -s "$SYMLINK_SPECIFY_MODES_BEFORE" "$SYMLINK_SPECIFY_MODES_AFTER"; then
    pass 'symlinked .specify preserves external path types and modes'
else
    fail 'symlinked .specify changes external path types or modes'
fi

for registration_descendant in extensions workflows; do
    printf 'Given: .specify is safe and .specify/%s is a symlink to an external directory\n' "$registration_descendant"
    SYMLINK_REGISTRATION_REPO="$TMPDIR_ROOT/symlink-registration-$registration_descendant-repo"
    SYMLINK_REGISTRATION_PROTOCOL_ROOT="$TMPDIR_ROOT/symlink-registration-$registration_descendant-protocol"
    SYMLINK_REGISTRATION_EXTERNAL_DIR="$TMPDIR_ROOT/symlink-registration-$registration_descendant-external"
    SYMLINK_REGISTRATION_BIN="$TMPDIR_ROOT/symlink-registration-$registration_descendant-bin"
    SYMLINK_REGISTRATION_SNAPSHOT_BEFORE="$TMPDIR_ROOT/symlink-registration-$registration_descendant.before"
    SYMLINK_REGISTRATION_SNAPSHOT_AFTER="$TMPDIR_ROOT/symlink-registration-$registration_descendant.after"
    SYMLINK_REGISTRATION_MODES_BEFORE="$TMPDIR_ROOT/symlink-registration-$registration_descendant-modes.before"
    SYMLINK_REGISTRATION_MODES_AFTER="$TMPDIR_ROOT/symlink-registration-$registration_descendant-modes.after"
    mkdir -p \
        "$SYMLINK_REGISTRATION_REPO/.specify" \
        "$SYMLINK_REGISTRATION_EXTERNAL_DIR" \
        "$SYMLINK_REGISTRATION_BIN"
    printf '%s\n' 'external registration sentinel' > "$SYMLINK_REGISTRATION_EXTERNAL_DIR/sentinel.txt"
    chmod 0700 "$SYMLINK_REGISTRATION_EXTERNAL_DIR"
    chmod 0600 "$SYMLINK_REGISTRATION_EXTERNAL_DIR/sentinel.txt"
    ln -s \
        "$SYMLINK_REGISTRATION_EXTERNAL_DIR" \
        "$SYMLINK_REGISTRATION_REPO/.specify/$registration_descendant"
    cat > "$SYMLINK_REGISTRATION_BIN/specify" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    extension) destination='.specify/extensions' ;;
    workflow) destination='.specify/workflows' ;;
    *) exit 2 ;;
esac
mkdir -p "$destination"
printf '%s\n' 'external registration mutation' > "$destination/registration-mutated.txt"
chmod 0777 "$destination"
chmod 0666 "$destination/registration-mutated.txt"
EOF
    chmod 0755 "$SYMLINK_REGISTRATION_BIN/specify"
    git init -q "$SYMLINK_REGISTRATION_REPO"
    snapshot_repo "$SYMLINK_REGISTRATION_EXTERNAL_DIR" > "$SYMLINK_REGISTRATION_SNAPSHOT_BEFORE"
    snapshot_repo_modes "$SYMLINK_REGISTRATION_EXTERNAL_DIR" > "$SYMLINK_REGISTRATION_MODES_BEFORE"

    printf 'When: bootstrap runs registration with --skip-init and symlinked .specify/%s\n' "$registration_descendant"
    export AGENT_PROTOCOL_ROOT="$SYMLINK_REGISTRATION_PROTOCOL_ROOT"
    if PATH="$SYMLINK_REGISTRATION_BIN:/usr/bin:/bin" python3 "$SETUP_SCRIPT" \
        --repo "$SYMLINK_REGISTRATION_REPO" \
        --skip-init \
        --preserve-readmes \
        --no-worktrees \
        --no-repo-agent-pointers \
        --no-skill-links \
        --no-global-agent-pointers > "$TMPDIR_ROOT/symlink-registration-$registration_descendant.log" 2>&1; then
        fail "bootstrap rejects a symlinked .specify/$registration_descendant registration descendant"
    else
        pass "bootstrap rejects a symlinked .specify/$registration_descendant registration descendant"
    fi

    printf 'Then: .specify/%s rejection occurs before external bytes, types, or modes change\n' "$registration_descendant"
    snapshot_repo "$SYMLINK_REGISTRATION_EXTERNAL_DIR" > "$SYMLINK_REGISTRATION_SNAPSHOT_AFTER"
    snapshot_repo_modes "$SYMLINK_REGISTRATION_EXTERNAL_DIR" > "$SYMLINK_REGISTRATION_MODES_AFTER"
    assert_contains \
        "$TMPDIR_ROOT/symlink-registration-$registration_descendant.log" \
        "symlink found at $SYMLINK_REGISTRATION_REPO/.specify/$registration_descendant" \
        "symlinked .specify/$registration_descendant rejection identifies the descendant"
    if cmp -s "$SYMLINK_REGISTRATION_SNAPSHOT_BEFORE" "$SYMLINK_REGISTRATION_SNAPSHOT_AFTER"; then
        pass "symlinked .specify/$registration_descendant preserves external file paths and hashes"
    else
        fail "symlinked .specify/$registration_descendant changes external file paths or hashes"
    fi
    if cmp -s "$SYMLINK_REGISTRATION_MODES_BEFORE" "$SYMLINK_REGISTRATION_MODES_AFTER"; then
        pass "symlinked .specify/$registration_descendant preserves external path types and modes"
    else
        fail "symlinked .specify/$registration_descendant changes external path types or modes"
    fi
done

printf '%s\n' 'Given: AGENTS.md is a symlink to an external file'
SYMLINK_AGENT_REPO="$TMPDIR_ROOT/symlink-agent-repo"
SYMLINK_AGENT_PROTOCOL_ROOT="$TMPDIR_ROOT/symlink-agent-protocol"
SYMLINK_AGENT_EXTERNAL_DIR="$TMPDIR_ROOT/symlink-agent-external"
SYMLINK_AGENT_EXTERNAL="$SYMLINK_AGENT_EXTERNAL_DIR/AGENTS.md"
SYMLINK_AGENT_SNAPSHOT_BEFORE="$TMPDIR_ROOT/symlink-agent.before"
SYMLINK_AGENT_SNAPSHOT_AFTER="$TMPDIR_ROOT/symlink-agent.after"
SYMLINK_AGENT_MODES_BEFORE="$TMPDIR_ROOT/symlink-agent-modes.before"
SYMLINK_AGENT_MODES_AFTER="$TMPDIR_ROOT/symlink-agent-modes.after"
mkdir -p "$SYMLINK_AGENT_REPO" "$SYMLINK_AGENT_EXTERNAL_DIR"
printf '%s\n' 'external agent instructions' > "$SYMLINK_AGENT_EXTERNAL"
ln -s "$SYMLINK_AGENT_EXTERNAL" "$SYMLINK_AGENT_REPO/AGENTS.md"
git init -q "$SYMLINK_AGENT_REPO"
snapshot_repo "$SYMLINK_AGENT_EXTERNAL_DIR" > "$SYMLINK_AGENT_SNAPSHOT_BEFORE"
snapshot_repo_modes "$SYMLINK_AGENT_EXTERNAL_DIR" > "$SYMLINK_AGENT_MODES_BEFORE"

printf '%s\n' 'When: bootstrap updates repository agent pointers'
export AGENT_PROTOCOL_ROOT="$SYMLINK_AGENT_PROTOCOL_ROOT"
if python3 "$SETUP_SCRIPT" \
    --repo "$SYMLINK_AGENT_REPO" \
    --skip-init \
    --preserve-readmes \
    --no-speckit-registration \
    --no-worktrees \
    --no-skill-links \
    --no-global-agent-pointers > "$TMPDIR_ROOT/symlink-agent.log" 2>&1; then
    fail 'bootstrap rejects a symlinked AGENTS.md leaf'
else
    pass 'bootstrap rejects a symlinked AGENTS.md leaf'
fi

printf '%s\n' 'Then: agent pointer rejection leaves the external file unchanged'
snapshot_repo "$SYMLINK_AGENT_EXTERNAL_DIR" > "$SYMLINK_AGENT_SNAPSHOT_AFTER"
snapshot_repo_modes "$SYMLINK_AGENT_EXTERNAL_DIR" > "$SYMLINK_AGENT_MODES_AFTER"
assert_contains "$TMPDIR_ROOT/symlink-agent.log" 'symlink leaf' 'symlinked AGENTS.md rejection identifies the symlink leaf'
if cmp -s "$SYMLINK_AGENT_SNAPSHOT_BEFORE" "$SYMLINK_AGENT_SNAPSHOT_AFTER"; then
    pass 'symlinked AGENTS.md preserves external file paths and hashes'
else
    fail 'symlinked AGENTS.md changes external file paths or hashes'
fi
if cmp -s "$SYMLINK_AGENT_MODES_BEFORE" "$SYMLINK_AGENT_MODES_AFTER"; then
    pass 'symlinked AGENTS.md preserves external path types and modes'
else
    fail 'symlinked AGENTS.md changes external path types or modes'
fi

printf '%s\n' 'Given: openspec/README.md is a symlink to an external file'
SYMLINK_README_REPO="$TMPDIR_ROOT/symlink-readme-repo"
SYMLINK_README_PROTOCOL_ROOT="$TMPDIR_ROOT/symlink-readme-protocol"
SYMLINK_README_EXTERNAL_DIR="$TMPDIR_ROOT/symlink-readme-external"
SYMLINK_README_EXTERNAL="$SYMLINK_README_EXTERNAL_DIR/README.md"
SYMLINK_README_SNAPSHOT_BEFORE="$TMPDIR_ROOT/symlink-readme.before"
SYMLINK_README_SNAPSHOT_AFTER="$TMPDIR_ROOT/symlink-readme.after"
SYMLINK_README_MODES_BEFORE="$TMPDIR_ROOT/symlink-readme-modes.before"
SYMLINK_README_MODES_AFTER="$TMPDIR_ROOT/symlink-readme-modes.after"
mkdir -p "$SYMLINK_README_REPO/openspec" "$SYMLINK_README_EXTERNAL_DIR"
printf '%s\n' 'external README content' > "$SYMLINK_README_EXTERNAL"
ln -s "$SYMLINK_README_EXTERNAL" "$SYMLINK_README_REPO/openspec/README.md"
git init -q "$SYMLINK_README_REPO"
snapshot_repo "$SYMLINK_README_EXTERNAL_DIR" > "$SYMLINK_README_SNAPSHOT_BEFORE"
snapshot_repo_modes "$SYMLINK_README_EXTERNAL_DIR" > "$SYMLINK_README_MODES_BEFORE"

printf '%s\n' 'When: bootstrap writes generated workflow READMEs'
export AGENT_PROTOCOL_ROOT="$SYMLINK_README_PROTOCOL_ROOT"
if python3 "$SETUP_SCRIPT" \
    --repo "$SYMLINK_README_REPO" \
    --skip-init \
    --no-speckit-registration \
    --no-worktrees \
    --no-repo-agent-pointers \
    --no-skill-links \
    --no-global-agent-pointers > "$TMPDIR_ROOT/symlink-readme.log" 2>&1; then
    fail 'bootstrap rejects a symlinked generated README leaf'
else
    pass 'bootstrap rejects a symlinked generated README leaf'
fi

printf '%s\n' 'Then: README rejection leaves the external file unchanged'
snapshot_repo "$SYMLINK_README_EXTERNAL_DIR" > "$SYMLINK_README_SNAPSHOT_AFTER"
snapshot_repo_modes "$SYMLINK_README_EXTERNAL_DIR" > "$SYMLINK_README_MODES_AFTER"
assert_contains "$TMPDIR_ROOT/symlink-readme.log" 'symlink leaf' 'symlinked README rejection identifies the symlink leaf'
if cmp -s "$SYMLINK_README_SNAPSHOT_BEFORE" "$SYMLINK_README_SNAPSHOT_AFTER"; then
    pass 'symlinked README preserves external file paths and hashes'
else
    fail 'symlinked README changes external file paths or hashes'
fi
if cmp -s "$SYMLINK_README_MODES_BEFORE" "$SYMLINK_README_MODES_AFTER"; then
    pass 'symlinked README preserves external path types and modes'
else
    fail 'symlinked README changes external path types or modes'
fi

for scaffold_parent in changes specs; do
    printf 'Given: openspec/%s is a symlink to an external directory\n' "$scaffold_parent"
    NESTED_SCAFFOLD_REPO="$TMPDIR_ROOT/nested-scaffold-$scaffold_parent-repo"
    NESTED_SCAFFOLD_PROTOCOL_ROOT="$TMPDIR_ROOT/nested-scaffold-$scaffold_parent-protocol"
    NESTED_SCAFFOLD_EXTERNAL_DIR="$TMPDIR_ROOT/nested-scaffold-$scaffold_parent-external"
    NESTED_SCAFFOLD_SNAPSHOT_BEFORE="$TMPDIR_ROOT/nested-scaffold-$scaffold_parent.before"
    NESTED_SCAFFOLD_SNAPSHOT_AFTER="$TMPDIR_ROOT/nested-scaffold-$scaffold_parent.after"
    NESTED_SCAFFOLD_MODES_BEFORE="$TMPDIR_ROOT/nested-scaffold-$scaffold_parent-modes.before"
    NESTED_SCAFFOLD_MODES_AFTER="$TMPDIR_ROOT/nested-scaffold-$scaffold_parent-modes.after"
    mkdir -p "$NESTED_SCAFFOLD_REPO/openspec" "$NESTED_SCAFFOLD_EXTERNAL_DIR"
    printf '%s\n' 'external nested scaffold sentinel' > "$NESTED_SCAFFOLD_EXTERNAL_DIR/sentinel.txt"
    ln -s "$NESTED_SCAFFOLD_EXTERNAL_DIR" "$NESTED_SCAFFOLD_REPO/openspec/$scaffold_parent"
    git init -q "$NESTED_SCAFFOLD_REPO"
    snapshot_repo "$NESTED_SCAFFOLD_EXTERNAL_DIR" > "$NESTED_SCAFFOLD_SNAPSHOT_BEFORE"
    snapshot_repo_modes "$NESTED_SCAFFOLD_EXTERNAL_DIR" > "$NESTED_SCAFFOLD_MODES_BEFORE"

    printf 'When: bootstrap creates the nested OpenSpec %s scaffold\n' "$scaffold_parent"
    export AGENT_PROTOCOL_ROOT="$NESTED_SCAFFOLD_PROTOCOL_ROOT"
    if python3 "$SETUP_SCRIPT" \
        --repo "$NESTED_SCAFFOLD_REPO" \
        --preserve-readmes \
        --no-speckit-registration \
        --no-worktrees \
        --no-repo-agent-pointers \
        --no-skill-links \
        --no-global-agent-pointers > "$TMPDIR_ROOT/nested-scaffold-$scaffold_parent.log" 2>&1; then
        fail "bootstrap rejects a symlinked openspec/$scaffold_parent scaffold path"
    else
        pass "bootstrap rejects a symlinked openspec/$scaffold_parent scaffold path"
    fi

    printf 'Then: nested %s rejection leaves the external directory unchanged\n' "$scaffold_parent"
    snapshot_repo "$NESTED_SCAFFOLD_EXTERNAL_DIR" > "$NESTED_SCAFFOLD_SNAPSHOT_AFTER"
    snapshot_repo_modes "$NESTED_SCAFFOLD_EXTERNAL_DIR" > "$NESTED_SCAFFOLD_MODES_AFTER"
    assert_contains "$TMPDIR_ROOT/nested-scaffold-$scaffold_parent.log" 'symlink' "nested $scaffold_parent rejection identifies the symlink"
    if cmp -s "$NESTED_SCAFFOLD_SNAPSHOT_BEFORE" "$NESTED_SCAFFOLD_SNAPSHOT_AFTER"; then
        pass "nested $scaffold_parent preserves external file paths and hashes"
    else
        fail "nested $scaffold_parent changes external file paths or hashes"
    fi
    if cmp -s "$NESTED_SCAFFOLD_MODES_BEFORE" "$NESTED_SCAFFOLD_MODES_AFTER"; then
        pass "nested $scaffold_parent preserves external path types and modes"
    else
        fail "nested $scaffold_parent changes external path types or modes"
    fi
done

printf '%s\n' 'Given: openspec/config.yaml is a broken symlink to an external file'
BROKEN_CONFIG_REPO="$TMPDIR_ROOT/broken-config-repo"
BROKEN_CONFIG_PROTOCOL_ROOT="$TMPDIR_ROOT/broken-config-protocol"
BROKEN_CONFIG_EXTERNAL="$TMPDIR_ROOT/broken-config-external.yaml"
mkdir -p "$BROKEN_CONFIG_REPO/openspec"
ln -s "$BROKEN_CONFIG_EXTERNAL" "$BROKEN_CONFIG_REPO/openspec/config.yaml"
git init -q "$BROKEN_CONFIG_REPO"

printf '%s\n' 'When: bootstrap ensures the OpenSpec config'
export AGENT_PROTOCOL_ROOT="$BROKEN_CONFIG_PROTOCOL_ROOT"
if python3 "$SETUP_SCRIPT" \
    --repo "$BROKEN_CONFIG_REPO" \
    --skip-init \
    --no-speckit-registration \
    --no-global-agent-pointers \
    --no-skill-links \
    --no-worktrees > "$TMPDIR_ROOT/broken-config.log" 2>&1; then
    fail 'bootstrap rejects a broken OpenSpec config symlink'
else
    pass 'bootstrap rejects a broken OpenSpec config symlink'
fi

printf '%s\n' 'Then: config rejection leaves the external target absent'
assert_contains "$TMPDIR_ROOT/broken-config.log" 'symlink' 'broken config rejection identifies the symlink'
assert_not_exists "$BROKEN_CONFIG_EXTERNAL" 'broken config symlink does not create its external target'

printf '%s\n' 'Given: the Git extension registry is a symlink to an external JSON file'
SYMLINK_REGISTRY_REPO="$TMPDIR_ROOT/symlink-registry-repo"
SYMLINK_REGISTRY_PROTOCOL_ROOT="$TMPDIR_ROOT/symlink-registry-protocol"
SYMLINK_REGISTRY_EXTERNAL="$TMPDIR_ROOT/symlink-registry-external.json"
SYMLINK_REGISTRY_SNAPSHOT="$TMPDIR_ROOT/symlink-registry.snapshot"
mkdir -p "$SYMLINK_REGISTRY_REPO/.specify/extensions" "$SYMLINK_REGISTRY_REPO/openspec"
printf '%s\n' '{"extensions":{"git":{"enabled":true,"manifest_hash":"sha256:external"}}}' > "$SYMLINK_REGISTRY_EXTERNAL"
cp "$SYMLINK_REGISTRY_EXTERNAL" "$SYMLINK_REGISTRY_SNAPSHOT"
ln -s "$SYMLINK_REGISTRY_EXTERNAL" "$SYMLINK_REGISTRY_REPO/.specify/extensions/.registry"
printf '%s\n' 'schema: spec-driven' > "$SYMLINK_REGISTRY_REPO/openspec/config.yaml"
git init -q "$SYMLINK_REGISTRY_REPO"

printf '%s\n' 'When: bootstrap refreshes the Git extension manifest hash'
export AGENT_PROTOCOL_ROOT="$SYMLINK_REGISTRY_PROTOCOL_ROOT"
if python3 "$SETUP_SCRIPT" \
    --repo "$SYMLINK_REGISTRY_REPO" \
    --skip-init \
    --no-speckit-registration \
    --no-global-agent-pointers \
    --no-skill-links > "$TMPDIR_ROOT/symlink-registry.log" 2>&1; then
    fail 'bootstrap rejects a symlinked extension registry'
else
    pass 'bootstrap rejects a symlinked extension registry'
fi

printf '%s\n' 'Then: registry rejection leaves the external JSON unchanged'
assert_contains "$TMPDIR_ROOT/symlink-registry.log" 'symlink' 'symlinked registry rejection identifies the symlink'
if cmp -s "$SYMLINK_REGISTRY_SNAPSHOT" "$SYMLINK_REGISTRY_EXTERNAL"; then
    pass 'symlinked registry preserves the external JSON bytes'
else
    fail 'symlinked registry changes the external JSON bytes'
fi

printf '%s\n' 'Given: an OPSX command source tree containing a file symlink'
UNSAFE_COMMAND_ROOT="$TMPDIR_ROOT/unsafe-command-source"
UNSAFE_COMMAND_REPO="$TMPDIR_ROOT/unsafe-command-repo"
UNSAFE_COMMAND_PROTOCOL_ROOT="$TMPDIR_ROOT/unsafe-command-protocol"
UNSAFE_COMMAND_TARGET="$TMPDIR_ROOT/unsafe-command-target.md"
mkdir -p "$UNSAFE_COMMAND_ROOT" "$UNSAFE_COMMAND_REPO"
printf '%s\n' 'safe command copied before the symlink without preflight' > "$UNSAFE_COMMAND_ROOT/00-safe.md"
printf '%s\n' 'outside command target must never be materialized' > "$UNSAFE_COMMAND_TARGET"
ln -s "$UNSAFE_COMMAND_TARGET" "$UNSAFE_COMMAND_ROOT/99-linked.md"
git init -q "$UNSAFE_COMMAND_REPO"

printf '%s\n' 'When: bootstrap encounters the unsafe command source tree'
export OPSX_COMMAND_TEMPLATE_ROOT="$UNSAFE_COMMAND_ROOT"
export AGENT_PROTOCOL_ROOT="$UNSAFE_COMMAND_PROTOCOL_ROOT"
if python3 "$SETUP_SCRIPT" \
    --repo "$UNSAFE_COMMAND_REPO" \
    --skip-init \
    --no-speckit-registration \
    --no-global-agent-pointers \
    --no-skill-links \
    --no-worktrees > "$TMPDIR_ROOT/unsafe-command.log" 2>&1; then
    fail 'bootstrap rejects an OPSX command source tree containing a symlink'
else
    pass 'bootstrap rejects an OPSX command source tree containing a symlink'
fi

printf '%s\n' 'Then: the unsafe command tree is rejected before any of it is copied'
assert_contains "$TMPDIR_ROOT/unsafe-command.log" 'symlink' 'unsafe command rejection identifies the symlink'
assert_not_exists "$UNSAFE_COMMAND_REPO/.claude/commands/opsx/00-safe.md" 'unsafe command preflight leaves no partial safe file'
assert_not_exists "$UNSAFE_COMMAND_REPO/.claude/commands/opsx/99-linked.md" 'unsafe command target is never materialized'

printf '%s\n' 'Given: the configured OPSX command source root is a regular file'
REGULAR_COMMAND_SOURCE="$TMPDIR_ROOT/regular-command-source"
REGULAR_COMMAND_REPO="$TMPDIR_ROOT/regular-command-repo"
REGULAR_COMMAND_PROTOCOL_ROOT="$TMPDIR_ROOT/regular-command-protocol"
printf '%s\n' 'not a source directory' > "$REGULAR_COMMAND_SOURCE"
mkdir -p "$REGULAR_COMMAND_REPO"
git init -q "$REGULAR_COMMAND_REPO"

printf '%s\n' 'When: bootstrap preflights the regular-file source root'
export OPSX_COMMAND_TEMPLATE_ROOT="$REGULAR_COMMAND_SOURCE"
export AGENT_PROTOCOL_ROOT="$REGULAR_COMMAND_PROTOCOL_ROOT"
if python3 "$SETUP_SCRIPT" \
    --repo "$REGULAR_COMMAND_REPO" \
    --skip-init \
    --no-speckit-registration \
    --no-worktrees \
    --no-repo-agent-pointers \
    --no-skill-links \
    --no-global-agent-pointers > "$TMPDIR_ROOT/regular-command.log" 2>&1; then
    fail 'bootstrap rejects a regular-file OPSX command source root'
else
    pass 'bootstrap rejects a regular-file OPSX command source root'
fi

printf '%s\n' 'Then: source rejection occurs before any bootstrap destination is created'
assert_contains "$TMPDIR_ROOT/regular-command.log" 'not a directory' 'regular-file source rejection identifies its type'
assert_not_exists "$REGULAR_COMMAND_REPO/openspec" 'regular-file source rejection leaves no repository destination'
assert_not_exists "$REGULAR_COMMAND_PROTOCOL_ROOT" 'regular-file source rejection leaves no protocol destination'

printf '%s\n' 'Given: a global skill source tree containing a directory symlink'
UNSAFE_SKILL_HOME="$TMPDIR_ROOT/unsafe-skill-home"
UNSAFE_SKILL_REPO="$TMPDIR_ROOT/unsafe-skill-repo"
UNSAFE_SKILL_PROTOCOL_ROOT="$TMPDIR_ROOT/unsafe-skill-protocol"
UNSAFE_SKILL_EXTERNAL_DIR="$TMPDIR_ROOT/unsafe-skill-external"
mkdir -p \
    "$UNSAFE_SKILL_HOME/.agents/skills/ct" \
    "$UNSAFE_SKILL_REPO" \
    "$UNSAFE_SKILL_EXTERNAL_DIR"
printf '%s\n' 'safe skill file copied before the symlink without preflight' > "$UNSAFE_SKILL_HOME/.agents/skills/ct/00-safe.txt"
printf '%s\n' 'outside skill target must never be materialized' > "$UNSAFE_SKILL_EXTERNAL_DIR/secret.txt"
ln -s "$UNSAFE_SKILL_EXTERNAL_DIR" "$UNSAFE_SKILL_HOME/.agents/skills/ct/99-linked-dir"
git init -q "$UNSAFE_SKILL_REPO"

printf '%s\n' 'When: bootstrap encounters the unsafe skill source tree'
export HOME="$UNSAFE_SKILL_HOME"
export AGENT_PROTOCOL_ROOT="$UNSAFE_SKILL_PROTOCOL_ROOT"
export OPSX_COMMAND_TEMPLATE_ROOT="$COMMAND_TEMPLATE_ROOT"
if python3 "$SETUP_SCRIPT" \
    --repo "$UNSAFE_SKILL_REPO" \
    --skip-init \
    --no-speckit-registration \
    --no-global-agent-pointers \
    --no-worktrees > "$TMPDIR_ROOT/unsafe-skill.log" 2>&1; then
    fail 'bootstrap rejects a skill source tree containing a symlink'
else
    pass 'bootstrap rejects a skill source tree containing a symlink'
fi

printf '%s\n' 'Then: the unsafe skill tree is rejected before any of it is copied'
assert_contains "$TMPDIR_ROOT/unsafe-skill.log" 'symlink' 'unsafe skill rejection identifies the symlink'
assert_not_exists "$UNSAFE_SKILL_REPO/.agents/skills/ct/00-safe.txt" 'unsafe skill preflight leaves no partial safe file'
assert_not_exists "$UNSAFE_SKILL_REPO/.agents/skills/ct/99-linked-dir" 'unsafe skill directory target is never materialized'

printf '%s\n' 'Given: isolated copy and wrapper-helper destinations with symlinks, collisions, and restrictive modes'
if python3 - "$SETUP_SCRIPT" "$TMPDIR_ROOT/copy-helper-safety" <<'PY'
from pathlib import Path
import runpy
import stat
import sys

namespace = runpy.run_path(sys.argv[1], run_name="setup_openspeckit_test")
copy_missing_tree = namespace["copy_missing_tree"]
copy_overlay_tree = namespace["copy_overlay_tree"]
ensure_openspec_skill_wrapper = namespace["ensure_openspec_skill_wrapper"]
is_usable_skill_tree = namespace["is_usable_skill_tree"]
link_or_copy_skill = namespace["link_or_copy_skill"]
openspec_skill_wrapper = namespace["openspec_skill_wrapper"]
skill_tree_will_be_usable = namespace["skill_tree_will_be_usable"]
fixture_root = Path(sys.argv[2])
fixture_root.mkdir()
failures = 0


def check(condition, label):
    global failures
    if condition:
        print(f"PASS: {label}")
    else:
        print(f"FAIL: {label}")
        failures += 1


def expect_refusal(action, label):
    global failures
    try:
        action()
    except SystemExit:
        print(f"PASS: {label}")
    except OSError as exc:
        print(f"FAIL: {label}: unexpected {type(exc).__name__}: {exc}")
        failures += 1
    else:
        print(f"FAIL: {label}: unsafe destination was accepted")
        failures += 1


def make_incremental_source(case_root):
    source = case_root / "source"
    (source / "nested").mkdir(parents=True)
    (source / "00-safe.txt").write_text("safe\n", encoding="utf-8")
    (source / "nested" / "payload.txt").write_text("new\n", encoding="utf-8")
    return source


def exercise_incremental_copy(name, copier):
    case_root = fixture_root / name

    retained_root_case = case_root / "retained-root-file-collision"
    source = make_incremental_source(retained_root_case)
    destination = retained_root_case / "destination"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("local\n", encoding="utf-8")
    destination.chmod(0o600)
    copier(source, destination, False, False)
    check(destination.is_file(), f"{name}: no-force preserves a root file collision")
    check(destination.read_text(encoding="utf-8") == "local\n", f"{name}: no-force preserves root file content")
    check(stat.S_IMODE(destination.stat().st_mode) == 0o600, f"{name}: no-force preserves root file mode")

    forced_root_case = case_root / "forced-root-file-collision"
    source = make_incremental_source(forced_root_case)
    destination = forced_root_case / "destination"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("local\n", encoding="utf-8")
    try:
        copier(source, destination, False, True)
    except OSError as exc:
        check(False, f"{name}: force replaces a root file with the source directory ({type(exc).__name__}: {exc})")
    else:
        check((destination / "nested" / "payload.txt").read_text(encoding="utf-8") == "new\n", f"{name}: force replaces a root file with the source directory")

    retained_directory_case = case_root / "retained-directory-file-collision"
    source = make_incremental_source(retained_directory_case)
    destination = retained_directory_case / "destination"
    destination.mkdir(parents=True)
    retained_directory = destination / "nested"
    retained_directory.write_text("local\n", encoding="utf-8")
    retained_directory.chmod(0o600)
    copier(source, destination, False, False)
    check(retained_directory.is_file(), f"{name}: no-force preserves a nested directory-to-file collision")
    check(retained_directory.read_text(encoding="utf-8") == "local\n", f"{name}: no-force preserves nested file content")
    check(stat.S_IMODE(retained_directory.stat().st_mode) == 0o600, f"{name}: no-force preserves nested file mode")

    forced_directory_case = case_root / "forced-directory-file-collision"
    source = make_incremental_source(forced_directory_case)
    destination = forced_directory_case / "destination"
    destination.mkdir(parents=True)
    (destination / "nested").write_text("local\n", encoding="utf-8")
    try:
        copier(source, destination, False, True)
    except OSError as exc:
        check(False, f"{name}: force replaces a nested file with the source directory ({type(exc).__name__}: {exc})")
    else:
        check((destination / "nested" / "payload.txt").read_text(encoding="utf-8") == "new\n", f"{name}: force replaces a nested file with the source directory")

    valid_case = case_root / "valid-leaf-force"
    source = make_incremental_source(valid_case)
    destination = valid_case / "destination"
    (destination / "nested").mkdir(parents=True)
    external = valid_case / "external.txt"
    external.write_text("old\n", encoding="utf-8")
    external.chmod(0o600)
    (destination / "nested" / "payload.txt").symlink_to(external)
    copier(source, destination, False, True)
    copied_leaf = destination / "nested" / "payload.txt"
    check(copied_leaf.is_file() and not copied_leaf.is_symlink(), f"{name}: force replaces a valid leaf symlink")
    check(external.read_text(encoding="utf-8") == "old\n", f"{name}: valid leaf symlink target content is untouched")
    check(stat.S_IMODE(external.stat().st_mode) == 0o600, f"{name}: valid leaf symlink target mode is untouched")

    broken_case = case_root / "broken-leaf-no-force"
    source = make_incremental_source(broken_case)
    destination = broken_case / "destination"
    (destination / "nested").mkdir(parents=True)
    missing_external = broken_case / "missing-external.txt"
    broken_leaf = destination / "nested" / "payload.txt"
    broken_leaf.symlink_to(missing_external)
    copier(source, destination, False, False)
    check(broken_leaf.is_symlink(), f"{name}: no-force preserves a broken leaf symlink")
    check(not missing_external.exists(), f"{name}: broken leaf symlink target is not created")

    parent_case = case_root / "symlinked-parent"
    source = make_incremental_source(parent_case)
    destination = parent_case / "destination"
    destination.mkdir(parents=True)
    external_directory = parent_case / "external-directory"
    external_directory.mkdir()
    (destination / "nested").symlink_to(external_directory, target_is_directory=True)
    expect_refusal(
        lambda: copier(source, destination, False, False),
        f"{name}: symlinked destination parent fails closed",
    )
    check(not (destination / "00-safe.txt").exists(), f"{name}: destination preflight prevents a partial safe copy")
    check(not (external_directory / "payload.txt").exists(), f"{name}: symlinked parent receives no copied file")

    mode_case = case_root / "retained-modes"
    source = make_incremental_source(mode_case)
    destination = mode_case / "destination"
    (destination / "nested").mkdir(parents=True)
    destination.chmod(0o700)
    (destination / "nested").chmod(0o700)
    copier(source, destination, False, False)
    check(stat.S_IMODE(destination.stat().st_mode) == 0o700, f"{name}: retained root directory stays 0700")
    check(stat.S_IMODE((destination / "nested").stat().st_mode) == 0o700, f"{name}: retained nested directory stays 0700")

    retained_collision_case = case_root / "retained-file-directory-collision"
    source = make_incremental_source(retained_collision_case)
    destination = retained_collision_case / "destination"
    retained_collision = destination / "nested" / "payload.txt"
    retained_collision.mkdir(parents=True)
    retained_collision.chmod(0o700)
    copier(source, destination, False, False)
    check(retained_collision.is_dir(), f"{name}: no-force preserves a leaf directory collision")
    check(stat.S_IMODE(retained_collision.stat().st_mode) == 0o700, f"{name}: no-force preserves a colliding directory mode")
    check(not (retained_collision / "payload.txt").exists(), f"{name}: no-force does not copy inside a colliding directory")

    collision_case = case_root / "forced-file-directory-collision"
    source = make_incremental_source(collision_case)
    destination = collision_case / "destination"
    collision = destination / "nested" / "payload.txt"
    collision.mkdir(parents=True)
    try:
        copier(source, destination, False, True)
    except OSError as exc:
        check(False, f"{name}: force replaces a leaf directory with a regular file ({type(exc).__name__}: {exc})")
    else:
        check(collision.is_file() and not collision.is_symlink(), f"{name}: force replaces a leaf directory with a regular file")
    if collision.is_dir():
        collision.chmod(0o700)


exercise_incremental_copy("copy-missing", copy_missing_tree)
exercise_incremental_copy("copy-overlay", copy_overlay_tree)

overlay_file_root_case = fixture_root / "overlay-file-root"
overlay_source = overlay_file_root_case / "source"
overlay_source.mkdir(parents=True)
(overlay_source / "SKILL.md").write_text("overlay\n", encoding="utf-8")
overlay_destination = overlay_file_root_case / "destination"
overlay_destination.write_text("local\n", encoding="utf-8")
copy_overlay_tree(overlay_source, overlay_destination, False, False)
check(not is_usable_skill_tree(overlay_destination), "copy-overlay: file destination root is not a usable skill tree")
check(not skill_tree_will_be_usable(overlay_destination, False), "copy-overlay: file destination root permits no-force fallback planning")
check(skill_tree_will_be_usable(overlay_destination, True), "copy-overlay: file destination root permits forced replacement planning")

source_symlink_case = fixture_root / "overlay-source-symlink"
source = make_incremental_source(source_symlink_case)
(source / "linked.txt").symlink_to(source_symlink_case / "outside.txt")
overlay_destination = source_symlink_case / "destination"
expect_refusal(
    lambda: copy_overlay_tree(source, overlay_destination, False, True),
    "copy-overlay: source symlink fails closed",
)
check(not overlay_destination.exists(), "copy-overlay: unsafe source leaves no partial destination")

source_file_case = fixture_root / "overlay-source-regular-file"
source_file_case.mkdir()
source = source_file_case / "source"
source.write_text("not a tree\n", encoding="utf-8")
overlay_destination = source_file_case / "destination"
expect_refusal(
    lambda: copy_overlay_tree(source, overlay_destination, False, True),
    "copy-overlay: regular-file source root fails closed",
)
check(not overlay_destination.exists(), "copy-overlay: regular-file source leaves no destination")

skill_source_root = fixture_root / "skill-source"
(skill_source_root / "nested").mkdir(parents=True)
(skill_source_root / "SKILL.md").write_text("fixture skill\n", encoding="utf-8")
(skill_source_root / "nested" / "data.txt").write_text("data\n", encoding="utf-8")

broken_skill_case = fixture_root / "skill-broken-top-level"
broken_skill_destination = broken_skill_case / "destination"
broken_skill_case.mkdir()
broken_skill_destination.symlink_to(broken_skill_case / "missing-skill", target_is_directory=True)
link_or_copy_skill(skill_source_root, broken_skill_destination, False, False)
check(broken_skill_destination.is_dir() and not broken_skill_destination.is_symlink(), "copy-skill: approved broken top-level symlink becomes a regular directory")

skill_parent_case = fixture_root / "skill-symlinked-parent"
skill_parent_case.mkdir()
skill_external_directory = skill_parent_case / "external-directory"
skill_external_directory.mkdir()
skill_parent = skill_parent_case / "linked-parent"
skill_parent.symlink_to(skill_external_directory, target_is_directory=True)
expect_refusal(
    lambda: link_or_copy_skill(skill_source_root, skill_parent / "ct", False, True),
    "copy-skill: symlinked destination parent fails closed",
)
check(not (skill_external_directory / "ct").exists(), "copy-skill: symlinked parent receives no skill tree")

nested_skill_case = fixture_root / "skill-nested-symlink"
nested_skill_destination = nested_skill_case / "destination"
nested_skill_destination.mkdir(parents=True)
skill_external_file = nested_skill_case / "external.txt"
skill_external_file.write_text("old\n", encoding="utf-8")
(nested_skill_destination / "linked.txt").symlink_to(skill_external_file)
expect_refusal(
    lambda: link_or_copy_skill(skill_source_root, nested_skill_destination, False, True),
    "copy-skill: nested destination symlink fails closed under force",
)
check(skill_external_file.read_text(encoding="utf-8") == "old\n", "copy-skill: nested symlink target is untouched")

retained_skill_case = fixture_root / "skill-retained-no-force"
retained_skill_destination = retained_skill_case / "destination"
retained_skill_destination.mkdir(parents=True)
retained_skill_destination.chmod(0o700)
(retained_skill_destination / "local.txt").write_text("local\n", encoding="utf-8")
link_or_copy_skill(skill_source_root, retained_skill_destination, False, False)
check(stat.S_IMODE(retained_skill_destination.stat().st_mode) == 0o700, "copy-skill: retained no-force directory stays 0700")

skill_file_collision_case = fixture_root / "skill-file-collision"
skill_file_collision_case.mkdir()
retained_skill_file = skill_file_collision_case / "retained"
retained_skill_file.write_text("local\n", encoding="utf-8")
retained_skill_file.chmod(0o600)
link_or_copy_skill(skill_source_root, retained_skill_file, False, False)
check(retained_skill_file.read_text(encoding="utf-8") == "local\n", "copy-skill: no-force preserves a file collision")
check(stat.S_IMODE(retained_skill_file.stat().st_mode) == 0o600, "copy-skill: no-force preserves a colliding file mode")
replaced_skill_file = skill_file_collision_case / "replaced"
replaced_skill_file.write_text("local\n", encoding="utf-8")
link_or_copy_skill(skill_source_root, replaced_skill_file, False, True)
check(replaced_skill_file.is_dir() and not replaced_skill_file.is_symlink(), "copy-skill: force replaces a file collision with a skill directory")

wrapper_parent_case = fixture_root / "openspec-wrapper-symlinked-parent"
wrapper_parent_repo = wrapper_parent_case / "repo"
wrapper_parent_external = wrapper_parent_case / "external-skills"
(wrapper_parent_repo / ".agents").mkdir(parents=True)
wrapper_parent_external.mkdir(parents=True)
wrapper_parent_sentinel = wrapper_parent_external / "sentinel.txt"
wrapper_parent_sentinel.write_text("external\n", encoding="utf-8")
(wrapper_parent_repo / ".agents" / "skills").symlink_to(
    wrapper_parent_external,
    target_is_directory=True,
)
wrapper_parent_entries = sorted(
    path.relative_to(wrapper_parent_external).as_posix()
    for path in wrapper_parent_external.rglob("*")
)
expect_refusal(
    lambda: ensure_openspec_skill_wrapper(
        wrapper_parent_repo,
        ".agents",
        "openspec-propose",
        "propose",
        False,
        False,
    ),
    "openspec-wrapper: symlinked parent skill directory is refused",
)
check(
    sorted(
        path.relative_to(wrapper_parent_external).as_posix()
        for path in wrapper_parent_external.rglob("*")
    )
    == wrapper_parent_entries
    and wrapper_parent_sentinel.read_text(encoding="utf-8") == "external\n",
    "openspec-wrapper: symlinked parent leaves the external target untouched",
)

wrapper_file_case = fixture_root / "openspec-wrapper-retained-file"
wrapper_file_repo = wrapper_file_case / "repo"
wrapper_file_destination = wrapper_file_repo / ".agents" / "skills" / "openspec-propose"
wrapper_file_destination.parent.mkdir(parents=True)
wrapper_file_destination.write_text("local wrapper file\n", encoding="utf-8")
ensure_openspec_skill_wrapper(
    wrapper_file_repo,
    ".agents",
    "openspec-propose",
    "propose",
    False,
    False,
)
check(
    wrapper_file_destination.is_file() and not wrapper_file_destination.is_symlink(),
    "openspec-wrapper: no-force preserves an existing regular-file destination",
)
check(
    wrapper_file_destination.is_file()
    and not wrapper_file_destination.is_symlink()
    and wrapper_file_destination.read_text(encoding="utf-8") == "local wrapper file\n",
    "openspec-wrapper: no-force preserves existing regular-file content",
)

wrapper_symlink_case = fixture_root / "openspec-wrapper-retained-symlink"
wrapper_symlink_repo = wrapper_symlink_case / "repo"
wrapper_symlink_destination = wrapper_symlink_repo / ".agents" / "skills" / "openspec-propose"
wrapper_symlink_destination.parent.mkdir(parents=True)
wrapper_symlink_external = wrapper_symlink_case / "external-wrapper.txt"
wrapper_symlink_external.write_text("external wrapper\n", encoding="utf-8")
wrapper_symlink_destination.symlink_to(wrapper_symlink_external)
wrapper_symlink_target = wrapper_symlink_destination.readlink()
ensure_openspec_skill_wrapper(
    wrapper_symlink_repo,
    ".agents",
    "openspec-propose",
    "propose",
    False,
    False,
)
check(
    wrapper_symlink_destination.is_symlink(),
    "openspec-wrapper: no-force preserves an existing symlink destination",
)
check(
    wrapper_symlink_destination.is_symlink()
    and wrapper_symlink_destination.readlink() == wrapper_symlink_target,
    "openspec-wrapper: no-force preserves the existing symlink target",
)
check(
    wrapper_symlink_external.is_file()
    and wrapper_symlink_external.read_text(encoding="utf-8") == "external wrapper\n",
    "openspec-wrapper: no-force leaves the symlink external target untouched",
)

wrapper_skill_symlink_case = fixture_root / "openspec-wrapper-matching-skill-symlink"
wrapper_skill_symlink_repo = wrapper_skill_symlink_case / "repo"
wrapper_skill_symlink_destination = (
    wrapper_skill_symlink_repo / ".agents" / "skills" / "openspec-propose"
)
wrapper_skill_symlink_destination.mkdir(parents=True)
wrapper_skill_symlink_destination.chmod(0o755)
wrapper_skill_symlink_external = wrapper_skill_symlink_case / "external-SKILL.md"
wrapper_skill_symlink_external.write_text(
    openspec_skill_wrapper(
        "openspec-propose",
        "propose",
        "../../../.claude/commands/opsx/propose.md",
    ),
    encoding="utf-8",
)
wrapper_skill_symlink_external.chmod(0o644)
(wrapper_skill_symlink_destination / "SKILL.md").symlink_to(
    wrapper_skill_symlink_external
)
ensure_openspec_skill_wrapper(
    wrapper_skill_symlink_repo,
    ".agents",
    "openspec-propose",
    "propose",
    False,
    True,
)
wrapper_skill_file = wrapper_skill_symlink_destination / "SKILL.md"
check(
    wrapper_skill_file.is_file() and not wrapper_skill_file.is_symlink(),
    "openspec-wrapper: force replaces a matching-content SKILL.md symlink",
)
check(
    wrapper_skill_symlink_external.is_file()
    and wrapper_skill_symlink_external.read_text(encoding="utf-8")
    == openspec_skill_wrapper(
        "openspec-propose",
        "propose",
        "../../../.claude/commands/opsx/propose.md",
    ),
    "openspec-wrapper: matching-content SKILL.md symlink target is untouched",
)

raise SystemExit(1 if failures else 0)
PY
then
    pass 'copy and wrapper helpers reject destination escapes and handle collisions and retained modes'
else
    fail 'copy and wrapper helpers reject destination escapes and handle collisions and retained modes'
fi

printf '%s\n' 'Given: checked destination directories are replaced by symlinks at deterministic publication seams'
if python3 - "$SETUP_SCRIPT" "$TMPDIR_ROOT/pathname-swap-safety" <<'PY'
from contextlib import contextmanager
from pathlib import Path
import os
import runpy
import stat
import sys

namespace = runpy.run_path(sys.argv[1], run_name="setup_openspeckit_test")
copy_missing_tree = namespace["copy_missing_tree"]
ensure_speckit_registration = namespace["ensure_speckit_registration"]
link_or_copy_skill = namespace["link_or_copy_skill"]
write_text = namespace["write_text"]
bootstrap_globals = write_text.__globals__
fixture_root = Path(sys.argv[2])
fixture_root.mkdir()
failures = 0


def check(condition, label):
    global failures
    if condition:
        print(f"PASS: {label}")
    else:
        print(f"FAIL: {label}")
        failures += 1


def tree_bytes(root):
    return {
        path.relative_to(root).as_posix(): path.read_bytes()
        for path in sorted(root.rglob("*"))
        if path.is_file() and not path.is_symlink()
    }


def tree_modes(root):
    paths = [root, *sorted(root.rglob("*"))]
    return {
        "." if path == root else path.relative_to(root).as_posix(): (
            stat.S_IFMT(path.lstat().st_mode),
            stat.S_IMODE(path.lstat().st_mode),
            os.readlink(path) if path.is_symlink() else None,
        )
        for path in paths
    }


def make_external(case_root):
    external = case_root / "external"
    (external / "sentinels").mkdir(parents=True)
    (external / "sentinel.txt").write_bytes(b"external sentinel\x00\xff\n")
    (external / "sentinels" / "nested.txt").write_bytes(b"nested sentinel\n")
    external.chmod(0o700)
    (external / "sentinels").chmod(0o711)
    (external / "sentinel.txt").chmod(0o600)
    (external / "sentinels" / "nested.txt").chmod(0o640)
    return external


def swap_directory(checked_directory, original_directory, external):
    checked_directory.rename(original_directory)
    checked_directory.symlink_to(external, target_is_directory=True)


def run_action(action):
    try:
        action()
    except (OSError, SystemExit):
        return True
    return False


generated_case = fixture_root / "generated-text"
generated_parent = generated_case / "checked-parent"
generated_original = generated_case / "original-parent"
generated_destination = generated_parent / "generated.txt"
generated_external = make_external(generated_case)
generated_parent.mkdir()
generated_bytes_before = tree_bytes(generated_external)
generated_modes_before = tree_modes(generated_external)
generated_swapped = False
original_file_check = bootstrap_globals["ensure_safe_destination_file"]


def swap_after_generated_check(path, safe_directories):
    global generated_swapped
    result = original_file_check(path, safe_directories)
    if path == generated_destination and not generated_swapped:
        swap_directory(generated_parent, generated_original, generated_external)
        generated_swapped = True
    return result


bootstrap_globals["ensure_safe_destination_file"] = swap_after_generated_check
try:
    generated_refused = run_action(
        lambda: write_text(generated_destination, "managed generated text\n", False)
    )
finally:
    bootstrap_globals["ensure_safe_destination_file"] = original_file_check

generated_written_to_original = (
    (generated_original / "generated.txt").is_file()
    and (generated_original / "generated.txt").read_bytes()
    == b"managed generated text\n"
)
check(generated_swapped, "generated text: deterministic swap seam was reached")
check(
    generated_refused or generated_written_to_original,
    "generated text: swap fails closed or writes through the checked original directory",
)
check(
    tree_bytes(generated_external) == generated_bytes_before,
    "generated text: external sentinel tree remains byte-for-byte unchanged",
)
check(
    tree_modes(generated_external) == generated_modes_before,
    "generated text: external sentinel tree remains mode-for-mode unchanged",
)

regular_case = fixture_root / "copied-regular"
regular_source = regular_case / "source"
regular_destination = regular_case / "checked-destination"
regular_original = regular_case / "original-destination"
regular_external = make_external(regular_case)
regular_source.mkdir(parents=True)
regular_destination.mkdir()
(regular_source / "payload.bin").write_bytes(b"copied regular payload\x00\xff\n")
(regular_source / "payload.bin").chmod(0o640)
regular_target = regular_destination / "payload.bin"
regular_bytes_before = tree_bytes(regular_external)
regular_modes_before = tree_modes(regular_external)
regular_swapped = False
original_parent_check = bootstrap_globals["ensure_safe_destination_parent"]


def swap_after_regular_parent_check(path, safe_directories):
    global regular_swapped
    result = original_parent_check(path, safe_directories)
    if path == regular_target and not regular_swapped:
        swap_directory(regular_destination, regular_original, regular_external)
        regular_swapped = True
    return result


bootstrap_globals["ensure_safe_destination_parent"] = swap_after_regular_parent_check
try:
    regular_refused = run_action(
        lambda: copy_missing_tree(regular_source, regular_destination, False, False)
    )
finally:
    bootstrap_globals["ensure_safe_destination_parent"] = original_parent_check

regular_written_to_original = (
    (regular_original / "payload.bin").is_file()
    and (regular_original / "payload.bin").read_bytes()
    == b"copied regular payload\x00\xff\n"
)
check(regular_swapped, "copied regular file: deterministic swap seam was reached")
check(
    regular_refused or regular_written_to_original,
    "copied regular file: swap fails closed or publishes through the checked original directory",
)
check(
    tree_bytes(regular_external) == regular_bytes_before,
    "copied regular file: external sentinel tree remains byte-for-byte unchanged",
)
check(
    tree_modes(regular_external) == regular_modes_before,
    "copied regular file: external sentinel tree remains mode-for-mode unchanged",
)

source_swap_case = fixture_root / "substituted-source-file"
source_swap_root = source_swap_case / "source"
source_swap_destination = source_swap_case / "destination"
source_swap_original = source_swap_case / "preflighted-payload.bin"
source_swap_file = source_swap_root / "payload.bin"
source_swap_root.mkdir(parents=True)
source_swap_file.write_bytes(b"preflighted source payload\x00\xff\n")
source_swap_file.chmod(0o640)
substituted_source_bytes = b"substituted source payload must not copy\x00\xff\n"
source_swapped = False
original_directory_descriptor = bootstrap_globals["directory_descriptor"]


@contextmanager
def swap_source_file_before_open(path, create=False):
    global source_swapped
    if path == source_swap_root and not source_swapped:
        source_swap_file.rename(source_swap_original)
        source_swap_file.write_bytes(substituted_source_bytes)
        source_swap_file.chmod(0o755)
        source_swapped = True
    with original_directory_descriptor(path, create) as descriptor:
        yield descriptor


bootstrap_globals["directory_descriptor"] = swap_source_file_before_open
try:
    source_substitution_refused = run_action(
        lambda: copy_missing_tree(
            source_swap_root,
            source_swap_destination,
            False,
            False,
        )
    )
finally:
    bootstrap_globals["directory_descriptor"] = original_directory_descriptor

source_swap_target = source_swap_destination / "payload.bin"
check(source_swapped, "source regular file: deterministic substitution seam was reached")
check(
    source_substitution_refused,
    "source regular file: substituted object identity fails closed",
)
check(
    not source_swap_target.exists()
    or source_swap_target.read_bytes() != substituted_source_bytes,
    "source regular file: substituted bytes never reach the destination",
)

tree_case = fixture_root / "copied-tree"
tree_source = tree_case / "source-skill"
tree_parent = tree_case / "checked-parent"
tree_original = tree_case / "original-parent"
tree_destination = tree_parent / "copied-skill"
tree_external = make_external(tree_case)
(tree_source / "nested").mkdir(parents=True)
(tree_source / "SKILL.md").write_text("copied tree skill\n", encoding="utf-8")
(tree_source / "nested" / "payload.bin").write_bytes(b"copied tree payload\x00\xff\n")
tree_parent.mkdir()
tree_bytes_before = tree_bytes(tree_external)
tree_modes_before = tree_modes(tree_external)
tree_swapped = False


def swap_after_tree_parent_check(path, safe_directories):
    global tree_swapped
    result = original_parent_check(path, safe_directories)
    if path == tree_destination and not tree_swapped:
        swap_directory(tree_parent, tree_original, tree_external)
        tree_swapped = True
    return result


bootstrap_globals["ensure_safe_destination_parent"] = swap_after_tree_parent_check
try:
    tree_refused = run_action(
        lambda: link_or_copy_skill(tree_source, tree_destination, False, False)
    )
finally:
    bootstrap_globals["ensure_safe_destination_parent"] = original_parent_check

tree_written_to_original = (
    (tree_original / "copied-skill" / "SKILL.md").is_file()
    and (tree_original / "copied-skill" / "SKILL.md").read_text(encoding="utf-8")
    == "copied tree skill\n"
    and (tree_original / "copied-skill" / "nested" / "payload.bin").read_bytes()
    == b"copied tree payload\x00\xff\n"
)
check(tree_swapped, "copied tree: deterministic swap seam was reached")
check(
    tree_refused or tree_written_to_original,
    "copied tree: swap fails closed or publishes through the checked original directory",
)
check(
    tree_bytes(tree_external) == tree_bytes_before,
    "copied tree: external sentinel tree remains byte-for-byte unchanged",
)
check(
    tree_modes(tree_external) == tree_modes_before,
    "copied tree: external sentinel tree remains mode-for-mode unchanged",
)

registration_case = fixture_root / "external-specify"
registration_parent = registration_case / "checked-parent"
registration_original_parent = registration_case / "original-parent"
registration_repo = registration_parent / "repo"
registration_external_parent = registration_case / "external-parent"
registration_external_repo = registration_external_parent / "repo"
(registration_repo / ".specify").mkdir(parents=True)
(registration_external_repo / ".specify" / "sentinels").mkdir(parents=True)
(registration_external_repo / ".specify" / "sentinel.bin").write_bytes(
    b"external specify sentinel\x00\xff\n"
)
(registration_external_repo / ".specify" / "sentinels" / "nested.txt").write_text(
    "nested external specify sentinel\n",
    encoding="utf-8",
)
registration_external_repo.chmod(0o700)
(registration_external_repo / ".specify").chmod(0o711)
(registration_external_repo / ".specify" / "sentinels").chmod(0o750)
(registration_external_repo / ".specify" / "sentinel.bin").chmod(0o600)
(registration_external_repo / ".specify" / "sentinels" / "nested.txt").chmod(0o640)
registration_bytes_before = tree_bytes(registration_external_parent)
registration_modes_before = tree_modes(registration_external_parent)
registration_swapped = False
original_run_command = bootstrap_globals["run_command"]


def staged_specify_with_parent_swap(command, cwd, dry_run):
    global registration_swapped
    if not registration_swapped:
        swap_directory(
            registration_parent,
            registration_original_parent,
            registration_external_parent,
        )
        registration_swapped = True
    if command[1] == "extension":
        destination = cwd / ".specify" / "extensions"
        destination.mkdir(parents=True, exist_ok=True)
        (destination / ".registry").write_text(
            '{"extensions":{"git":{"enabled":true}}}\n',
            encoding="utf-8",
        )
    elif command[1] == "workflow":
        destination = cwd / ".specify" / "workflows"
        destination.mkdir(parents=True, exist_ok=True)
        (destination / "workflow-registry.json").write_text(
            '{"workflows":{"speckit":{}}}\n',
            encoding="utf-8",
        )
    else:
        raise AssertionError(f"unexpected command: {command}")


bootstrap_globals["run_command"] = staged_specify_with_parent_swap
try:
    registration_refused = run_action(
        lambda: ensure_speckit_registration(registration_repo, False, False)
    )
finally:
    bootstrap_globals["run_command"] = original_run_command

registration_original_repo = registration_original_parent / "repo"
registration_imported = (
    (registration_original_repo / ".specify" / "extensions" / ".registry").is_file()
    and (
        registration_original_repo
        / ".specify"
        / "workflows"
        / "workflow-registry.json"
    ).is_file()
)
check(registration_swapped, "external specify: deterministic repository-parent swap seam was reached")
check(
    registration_refused or registration_imported,
    "external specify: swap fails closed or imports through the checked original repository",
)
check(
    tree_bytes(registration_external_parent) == registration_bytes_before,
    "external specify: external sentinel tree remains byte-for-byte unchanged",
)
check(
    tree_modes(registration_external_parent) == registration_modes_before,
    "external specify: external sentinel tree remains mode-for-mode unchanged",
)

raise SystemExit(1 if failures else 0)
PY
then
    pass 'pathname swaps cannot redirect generated text, regular files, or copied trees'
else
    fail 'pathname swaps redirected generated text or copied content outside the checked directory'
fi

printf '%s\n' 'Given: missing, empty, and incomplete worktree skill overlay sources with global fallbacks'
INCOMPLETE_TEMPLATE_ROOT="$TMPDIR_ROOT/incomplete-overlay-templates"
INCOMPLETE_OVERLAY_REPO="$TMPDIR_ROOT/incomplete-overlay-repo"
INCOMPLETE_OVERLAY_PROTOCOL="$TMPDIR_ROOT/incomplete-overlay-protocol"
mkdir -p "$INCOMPLETE_TEMPLATE_ROOT" "$INCOMPLETE_OVERLAY_REPO"
cp -a "$WORKTREE_TEMPLATE_ROOT/." "$INCOMPLETE_TEMPLATE_ROOT/"
rm -rf "$INCOMPLETE_TEMPLATE_ROOT/agents/skills/speckit-specify"
rm -rf "$INCOMPLETE_TEMPLATE_ROOT/claude/skills/speckit-specify"
mkdir -p "$INCOMPLETE_TEMPLATE_ROOT/claude/skills/speckit-specify"
rm -f "$INCOMPLETE_TEMPLATE_ROOT/codex/skills/speckit-specify/SKILL.md"
git init -q "$INCOMPLETE_OVERLAY_REPO"

printf '%s\n' 'When: forced bootstrap runs with the incomplete overlay template root'
export HOME="$FIXTURE_HOME"
export AGENT_PROTOCOL_ROOT="$INCOMPLETE_OVERLAY_PROTOCOL"
export SPECKIT_WORKTREE_TEMPLATE_ROOT="$INCOMPLETE_TEMPLATE_ROOT"
export OPSX_COMMAND_TEMPLATE_ROOT="$COMMAND_TEMPLATE_ROOT"
if ! python3 "$SETUP_SCRIPT" \
    --repo "$INCOMPLETE_OVERLAY_REPO" \
    --skip-init \
    --no-speckit-registration \
    --no-global-agent-pointers \
    --force > "$TMPDIR_ROOT/incomplete-overlay.log" 2>&1; then
    printf '%s\n' 'FAIL: incomplete-overlay bootstrap invocation failed:'
    cat "$TMPDIR_ROOT/incomplete-overlay.log"
    exit 1
fi

printf '%s\n' 'Then: incomplete overlays defer to global skills while complete overlays remain authoritative'
for skill_mapping in '.agents:agents' '.claude:claude' '.codex:codex'; do
    repo_agent_dir="${skill_mapping%%:*}"
    template_agent_dir="${skill_mapping##*:}"
    fallback_skill="$INCOMPLETE_OVERLAY_REPO/$repo_agent_dir/skills/speckit-specify/SKILL.md"
    assert_contains \
        "$fallback_skill" \
        'GLOBAL SKILL MUST NOT OVERRIDE WORKTREE OVERLAY' \
        "incomplete $template_agent_dir overlay allows global fallback"
    complete_overlay_source="$INCOMPLETE_TEMPLATE_ROOT/$template_agent_dir/skills/speckit-git-feature/SKILL.md"
    complete_overlay_destination="$INCOMPLETE_OVERLAY_REPO/$repo_agent_dir/skills/speckit-git-feature/SKILL.md"
    if cmp -s "$complete_overlay_source" "$complete_overlay_destination"; then
        pass "complete $template_agent_dir overlay remains authoritative under --force"
    else
        fail "complete $template_agent_dir overlay lost authority under --force"
    fi
done

printf '%s\n' 'Given: a hostile umask and pre-existing generated control file with a restrictive mode'
UMASK_HOME="$TMPDIR_ROOT/umask-home"
UMASK_PROTOCOL_ROOT="$TMPDIR_ROOT/umask-agent-protocol"
UMASK_REPO="$TMPDIR_ROOT/umask-repo"
mkdir -p "$UMASK_HOME" "$UMASK_REPO/.specify/templates"
printf '%s\n' '# Existing agent instructions' > "$UMASK_REPO/AGENTS.md"
chmod 0600 "$UMASK_REPO/AGENTS.md"
printf '%s\n' '{"integration":"claude"}' > "$UMASK_REPO/.specify/integration.json"
printf '%s\n' '{"integration":"claude"}' > "$UMASK_REPO/.specify/init-options.json"
printf '%s\n' '# Existing template' > "$UMASK_REPO/.specify/templates/spec-template.md"
git init -q "$UMASK_REPO"

printf '%s\n' 'When: bootstrap creates shared control files and directories under umask 077'
export HOME="$UMASK_HOME"
export AGENT_PROTOCOL_ROOT="$UMASK_PROTOCOL_ROOT"
export SPECKIT_WORKTREE_TEMPLATE_ROOT="$WORKTREE_TEMPLATE_ROOT"
export OPSX_COMMAND_TEMPLATE_ROOT="$COMMAND_TEMPLATE_ROOT"
if ! (
    umask 077
    python3 "$SETUP_SCRIPT" \
        --repo "$UMASK_REPO" \
        --no-speckit-registration \
        --no-worktrees \
        --no-skill-links \
        --no-global-agent-pointers > "$TMPDIR_ROOT/umask.log" 2>&1
); then
    printf '%s\n' 'FAIL: hostile-umask bootstrap invocation failed:'
    cat "$TMPDIR_ROOT/umask.log"
    exit 1
fi

printf '%s\n' 'Then: new shared control modes are stable and the existing file mode is preserved'
assert_mode "$UMASK_REPO/AGENTS.md" 600 'hostile umask preserves an existing generated control file mode'
for generated_file in \
    "$UMASK_REPO/CLAUDE.md" \
    "$UMASK_REPO/openspec/config.yaml" \
    "$UMASK_REPO/openspec/README.md" \
    "$UMASK_REPO/openspec/changes/archive/.gitkeep" \
    "$UMASK_REPO/openspec/specs/.gitkeep" \
    "$UMASK_REPO/.specify/README.md" \
    "$UMASK_PROTOCOL_ROOT/AGENTS.md" \
    "$UMASK_PROTOCOL_ROOT/protocols/openspec-speckit-workflow.md" \
    "$UMASK_PROTOCOL_ROOT/protocols/project-agent-bootstrap.md"; do
    assert_mode "$generated_file" 644 "hostile umask creates shared control file as 0644: $generated_file"
done
for generated_directory in \
    "$UMASK_REPO/openspec" \
    "$UMASK_REPO/openspec/changes" \
    "$UMASK_REPO/openspec/changes/archive" \
    "$UMASK_REPO/openspec/specs" \
    "$UMASK_PROTOCOL_ROOT" \
    "$UMASK_PROTOCOL_ROOT/protocols"; do
    assert_mode "$generated_directory" 755 "hostile umask creates shared control directory as 0755: $generated_directory"
done

printf '%s\n' 'Given: a fresh repository and protocol root with sentinel files'
DRY_RUN_HOME="$TMPDIR_ROOT/dry-run-home"
DRY_RUN_PROTOCOL_ROOT="$TMPDIR_ROOT/dry-run-agent-protocol"
DRY_RUN_REPO="$TMPDIR_ROOT/dry-run-repo"
DRY_RUN_REPO_SNAPSHOT_BEFORE="$TMPDIR_ROOT/dry-run-repo.before"
DRY_RUN_REPO_SNAPSHOT_AFTER="$TMPDIR_ROOT/dry-run-repo.after"
DRY_RUN_PROTOCOL_SNAPSHOT_BEFORE="$TMPDIR_ROOT/dry-run-protocol.before"
DRY_RUN_PROTOCOL_SNAPSHOT_AFTER="$TMPDIR_ROOT/dry-run-protocol.after"
DRY_RUN_REPO_MODES_BEFORE="$TMPDIR_ROOT/dry-run-repo-modes.before"
DRY_RUN_REPO_MODES_AFTER="$TMPDIR_ROOT/dry-run-repo-modes.after"
DRY_RUN_PROTOCOL_MODES_BEFORE="$TMPDIR_ROOT/dry-run-protocol-modes.before"
DRY_RUN_PROTOCOL_MODES_AFTER="$TMPDIR_ROOT/dry-run-protocol-modes.after"
mkdir -p "$DRY_RUN_HOME/.agents/skills/ct" "$DRY_RUN_PROTOCOL_ROOT" "$DRY_RUN_REPO"
printf '%s\n' 'dry-run skill fixture' > "$DRY_RUN_HOME/.agents/skills/ct/SKILL.md"
printf '%s\n' 'repo sentinel' > "$DRY_RUN_REPO/.dry-run-sentinel"
printf '%s\n' 'protocol sentinel' > "$DRY_RUN_PROTOCOL_ROOT/.dry-run-sentinel"
mkdir "$DRY_RUN_REPO/.restricted-directory"
chmod 0700 "$DRY_RUN_REPO/.restricted-directory"
ln -s '.dry-run-sentinel' "$DRY_RUN_REPO/.dry-run-symlink"
git init -q "$DRY_RUN_REPO"
snapshot_repo "$DRY_RUN_REPO" > "$DRY_RUN_REPO_SNAPSHOT_BEFORE"
snapshot_repo "$DRY_RUN_PROTOCOL_ROOT" > "$DRY_RUN_PROTOCOL_SNAPSHOT_BEFORE"
snapshot_repo_modes "$DRY_RUN_REPO" > "$DRY_RUN_REPO_MODES_BEFORE"
snapshot_repo_modes "$DRY_RUN_PROTOCOL_ROOT" > "$DRY_RUN_PROTOCOL_MODES_BEFORE"

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
snapshot_repo_modes "$DRY_RUN_REPO" > "$DRY_RUN_REPO_MODES_AFTER"
snapshot_repo_modes "$DRY_RUN_PROTOCOL_ROOT" > "$DRY_RUN_PROTOCOL_MODES_AFTER"
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
if cmp -s "$DRY_RUN_REPO_MODES_BEFORE" "$DRY_RUN_REPO_MODES_AFTER"; then
    pass '--dry-run preserves repository path types, symlinks, and modes'
else
    fail '--dry-run changes repository path types, symlinks, or modes'
fi
if cmp -s "$DRY_RUN_PROTOCOL_MODES_BEFORE" "$DRY_RUN_PROTOCOL_MODES_AFTER"; then
    pass '--dry-run preserves protocol-root path types, symlinks, and modes'
else
    fail '--dry-run changes protocol-root path types, symlinks, or modes'
fi

if (( failures == 0 )); then
    printf '%s\n' 'GREEN: OpenSpec bootstrap regression test passed'
else
    printf 'RED: %d assertion(s) failed\n' "$failures"
    exit 1
fi
