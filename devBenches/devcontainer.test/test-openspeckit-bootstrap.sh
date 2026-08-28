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
