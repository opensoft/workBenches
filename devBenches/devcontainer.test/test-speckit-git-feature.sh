#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(CDPATH="" cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH="" cd -- "$SCRIPT_DIR/../.." && pwd)"
SOURCE_TEMPLATE_ROOT="$REPO_ROOT/devBenches/base-image/files/speckit-worktree/templates"
TEMPLATE_ROOT="${SPECKIT_WORKTREE_TEMPLATE_ROOT:-$SOURCE_TEMPLATE_ROOT}"
if [ ! -d "$TEMPLATE_ROOT" ]; then
    TEMPLATE_ROOT="/usr/local/share/speckit-worktree/templates"
fi
FEATURE_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/bash/create-new-feature.sh"

FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/speckit-git-feature.XXXXXX")"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

if [ ! -x "$FEATURE_SCRIPT" ]; then
    printf 'Checked-in feature script is missing or not executable: %s\n' "$FEATURE_SCRIPT" >&2
    exit 1
fi

initialize_fixture() {
    local repo="$1"
    local config="$2"

    mkdir -p "$repo/.specify/extensions/git" || return 1
    git init -q -b main "$repo" || return 1
    git -C "$repo" config user.name 'Spec Kit test'
    git -C "$repo" config user.email 'spec-kit-test@example.invalid'
    printf '%s\n' "$config" > "$repo/.specify/extensions/git/git-config.yml" || return 1
    printf 'fixture\n' > "$repo/README.md" || return 1
    git -C "$repo" add README.md .specify/extensions/git/git-config.yml || return 1
    git -C "$repo" commit -qm 'fixture commit' || return 1
}

FEATURE_OUTPUT=''
invoke_feature() {
    local repo="$1"
    local description="$2"
    local stderr_file="$3"

    FEATURE_OUTPUT=''
    FEATURE_OUTPUT="$(cd "$repo" && bash "$FEATURE_SCRIPT" --json "$description" 2>"$stderr_file")" || return 1
}

json_field() {
    local payload="$1"
    local field="$2"

    printf '%s' "$payload" | python3 -c \
        'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$field"
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    if [ "$expected" != "$actual" ]; then
        printf 'assertion failed: %s (expected %q, got %q)\n' "$label" "$expected" "$actual" >&2
        return 1
    fi
}

assert_worktree() {
    local expected_branch="$1"
    local expected_path="$2"
    local actual_root
    local actual_branch

    if [ ! -d "$expected_path" ]; then
        printf 'assertion failed: worktree directory does not exist: %s\n' "$expected_path" >&2
        return 1
    fi
    if ! actual_root="$(git -C "$expected_path" rev-parse --show-toplevel 2>/dev/null)"; then
        printf 'assertion failed: path is not a Git worktree: %s\n' "$expected_path" >&2
        return 1
    fi
    assert_equal "$expected_path" "$actual_root" 'real worktree root' || return 1
    if ! actual_branch="$(git -C "$expected_path" branch --show-current 2>/dev/null)"; then
        printf 'assertion failed: could not read worktree branch: %s\n' "$expected_path" >&2
        return 1
    fi
    assert_equal "$expected_branch" "$actual_branch" 'real worktree branch'
}

test_default_sequential_worktree() {
    local repo="$FIXTURE_ROOT/default-sequential"
    local config=$'checkout_mode: worktree\nbase_branch: main'
    local stderr_file="$FIXTURE_ROOT/default-sequential.stderr"
    local description="Review the user's access policy"
    local branch
    local feature_num
    local checkout_mode
    local worktree_path
    local expected_path="$FIXTURE_ROOT/default-sequential-worktrees/001-review-user-access-policy"

    # Given: a Git repository with only the worktree mode and base branch configured.
    initialize_fixture "$repo" "$config" || return 1
    # When: the checked-in feature script receives a description containing an apostrophe.
    if ! invoke_feature "$repo" "$description" "$stderr_file"; then
        printf 'default sequential invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: the default template and sequential number produce a real sibling worktree.
    if ! branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)"; then return 1; fi
    if ! feature_num="$(json_field "$FEATURE_OUTPUT" FEATURE_NUM)"; then return 1; fi
    if ! checkout_mode="$(json_field "$FEATURE_OUTPUT" CHECKOUT_MODE)"; then return 1; fi
    if ! worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)"; then return 1; fi
    assert_equal '001-review-user-access-policy' "$branch" 'default branch name' || return 1
    assert_equal '001' "$feature_num" 'default feature number' || return 1
    assert_equal 'worktree' "$checkout_mode" 'default checkout mode' || return 1
    assert_equal "$expected_path" "$worktree_path" 'default WORKTREE_PATH' || return 1
    assert_worktree "$branch" "$worktree_path"
}

test_branch_template() {
    local repo="$FIXTURE_ROOT/template"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../template-worktrees\nbranch_template: ticket/{number}-{slug}'
    local stderr_file="$FIXTURE_ROOT/template.stderr"
    local branch
    local worktree_path
    local expected_branch='ticket/001-ship-dashboard-exports'
    local expected_path="$FIXTURE_ROOT/template-worktrees/$expected_branch"

    # Given: a fixture repository with an explicit template whose final segment is {number}-{slug}.
    initialize_fixture "$repo" "$config" || return 1
    # When: the feature script creates a worktree from that configuration.
    if ! invoke_feature "$repo" 'Ship dashboard exports' "$stderr_file"; then
        printf 'branch template invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: the configured template is used for both the branch and worktree path.
    if ! branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)"; then return 1; fi
    if ! worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)"; then return 1; fi
    assert_equal "$expected_branch" "$branch" 'branch_template branch name' || return 1
    assert_equal "$expected_path" "$worktree_path" 'branch_template WORKTREE_PATH' || return 1
    assert_worktree "$branch" "$worktree_path"
}

test_namespaced_numbering() {
    local repo="$FIXTURE_ROOT/namespaced"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../namespace-worktrees\nbranch_prefix: feature/\nbranch_template: {number}-{slug}'
    local stderr_file="$FIXTURE_ROOT/namespaced.stderr"
    local branch
    local feature_num
    local worktree_path
    local expected_branch='feature/008-update-incident-dashboard'
    local expected_path="$FIXTURE_ROOT/namespace-worktrees/$expected_branch"

    # Given: a namespaced feature branch already occupies sequential number 007.
    initialize_fixture "$repo" "$config" || return 1
    mkdir -p "$repo/specs/099-old" || return 1
    git -C "$repo" branch feature/007-existing || return 1
    git -C "$repo" branch other/050-unrelated || return 1
    # When: the next namespaced feature is created without an explicit number.
    if ! invoke_feature "$repo" 'Update incident dashboard' "$stderr_file"; then
        printf 'namespaced numbering invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: numbering scans the final {number}-{slug} segment within the namespace.
    if ! branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)"; then return 1; fi
    if ! feature_num="$(json_field "$FEATURE_OUTPUT" FEATURE_NUM)"; then return 1; fi
    if ! worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)"; then return 1; fi
    assert_equal "$expected_branch" "$branch" 'namespaced branch name' || return 1
    assert_equal '008' "$feature_num" 'namespaced feature number' || return 1
    assert_equal "$expected_path" "$worktree_path" 'namespaced WORKTREE_PATH' || return 1
    assert_worktree "$branch" "$worktree_path"
}

test_root_numbering_ignores_namespaces() {
    local repo="$FIXTURE_ROOT/root-numbering"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../root-numbering-worktrees'
    local stderr_file="$FIXTURE_ROOT/root-numbering.stderr"
    local branch

    # Given: only an unrelated namespaced feature branch has a high number.
    initialize_fixture "$repo" "$config" || return 1
    git -C "$repo" branch team/099-other || return 1
    # When: root-scoped sequential numbering is computed.
    if ! invoke_feature "$repo" 'Create root feature' "$stderr_file"; then
        printf 'root numbering invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: the unrelated namespace does not advance the root counter.
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    assert_equal '001-create-root-feature' "$branch" 'root-scoped branch number'
}

test_explicit_configuration() {
    local repo="$FIXTURE_ROOT/explicit"
    local config=$'branch_numbering: timestamp\ncheckout_mode: worktree\nbase_branch: develop\nworktree_root: ../explicit-worktrees\nbranch_prefix: release/\nbranch_template: {number}-{slug}'
    local stderr_file="$FIXTURE_ROOT/explicit.stderr"
    local branch
    local feature_num
    local checkout_mode
    local base_branch
    local worktree_path

    # Given: explicit timestamp, base branch, prefix, template, and worktree root settings.
    initialize_fixture "$repo" "$config" || return 1
    git -C "$repo" branch develop || return 1
    # When: the feature script creates a worktree while preserving those settings.
    if ! invoke_feature "$repo" 'Preserve explicit settings' "$stderr_file"; then
        printf 'explicit configuration invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: JSON preserves the configured mode and base, and the timestamped branch is real.
    if ! branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)"; then return 1; fi
    if ! feature_num="$(json_field "$FEATURE_OUTPUT" FEATURE_NUM)"; then return 1; fi
    if ! checkout_mode="$(json_field "$FEATURE_OUTPUT" CHECKOUT_MODE)"; then return 1; fi
    if ! base_branch="$(json_field "$FEATURE_OUTPUT" BASE_BRANCH)"; then return 1; fi
    if ! worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)"; then return 1; fi
    if [[ ! "$branch" =~ ^release/[0-9]{8}-[0-9]{6}-preserve-explicit-settings$ ]]; then
        printf 'assertion failed: explicit branch format (got %q)\n' "$branch" >&2
        return 1
    fi
    if [[ ! "$feature_num" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
        printf 'assertion failed: explicit timestamp feature number (got %q)\n' "$feature_num" >&2
        return 1
    fi
    assert_equal 'worktree' "$checkout_mode" 'explicit checkout mode' || return 1
    assert_equal 'develop' "$base_branch" 'explicit base branch' || return 1
    assert_equal "$FIXTURE_ROOT/explicit-worktrees/$branch" "$worktree_path" 'explicit WORKTREE_PATH' || return 1
    assert_worktree "$branch" "$worktree_path"
}

failures=0
run_scenario() {
    local name="$1"
    shift

    if "$@"; then
        printf 'PASS: %s\n' "$name"
    else
        printf 'FAIL: %s\n' "$name" >&2
        failures=$((failures + 1))
    fi
}

run_scenario 'default sequential worktree with apostrophe description' test_default_sequential_worktree
run_scenario 'branch_template with {number}-{slug} final segment' test_branch_template
run_scenario 'namespaced sequential numbering' test_namespaced_numbering
run_scenario 'root numbering ignores namespaced branches' test_root_numbering_ignores_namespaces
run_scenario 'preservation of explicit configuration' test_explicit_configuration

if [ "$failures" -ne 0 ]; then
    printf 'RED: Speckit Git feature behavior tests failed: %d scenario(s)\n' "$failures" >&2
    exit 1
fi

printf 'GREEN: Speckit Git feature behavior tests passed\n'
