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
GIT_COMMON_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/bash/git-common.sh"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/speckit-git-compat.XXXXXX")"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT
if [ ! -x "$FEATURE_SCRIPT" ] || [ ! -f "$GIT_COMMON_SCRIPT" ]; then
    printf 'Speckit Git templates are missing: %s\n' "$TEMPLATE_ROOT" >&2
    exit 1
fi
initialize_fixture() {
    local repo="$1" config="$2"
    mkdir -p "$repo/.specify/extensions/git" || return 1
    git init -q -b main "$repo" || return 1
    git -C "$repo" config user.name 'Spec Kit test' || return 1
    git -C "$repo" config user.email 'spec-kit-test@example.invalid' || return 1
    printf '%s\n' "$config" > "$repo/.specify/extensions/git/git-config.yml" || return 1
    printf 'fixture\n' > "$repo/README.md" || return 1
    git -C "$repo" add README.md .specify/extensions/git/git-config.yml || return 1
    git -C "$repo" commit -qm 'fixture commit' || return 1
}
FEATURE_OUTPUT=''
invoke_feature() {
    local repo="$1" description="$2" stderr_file="$3"
    shift 3
    FEATURE_OUTPUT="$(cd "$repo" && env -u GIT_BRANCH_NAME bash "$FEATURE_SCRIPT" --json "$@" "$description" 2>"$stderr_file")"
}
invoke_exact_feature() {
    local repo="$1" branch="$2" stderr_file="$3"
    shift 3
    FEATURE_OUTPUT="$(cd "$repo" && GIT_BRANCH_NAME="$branch" bash "$FEATURE_SCRIPT" --json "$@" ignored 2>"$stderr_file")"
}
json_field() {
    printf '%s' "$1" | python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$2"
}
json_has_key() {
    printf '%s' "$1" | python3 -c 'import json, sys; sys.exit(0 if sys.argv[1] in json.load(sys.stdin) else 1)' "$2"
}
json_true() {
    printf '%s' "$1" | python3 -c 'import json, sys; sys.exit(0 if json.load(sys.stdin)[sys.argv[1]] is True else 1)' "$2"
}
assert_equal() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" != "$actual" ]; then
        printf 'assertion failed: %s (expected %q, got %q)\n' "$label" "$expected" "$actual" >&2
        return 1
    fi
}
assert_worktree() {
    local expected_branch="$1" expected_path="$2" actual_root actual_branch
    [ -d "$expected_path" ] || {
        printf 'assertion failed: missing worktree: %s\n' "$expected_path" >&2
        return 1
    }
    actual_root="$(git -C "$expected_path" rev-parse --show-toplevel 2>/dev/null)" || return 1
    assert_equal "$expected_path" "$actual_root" 'real worktree root' || return 1
    actual_branch="$(git -C "$expected_path" branch --show-current 2>/dev/null)" || return 1
    assert_equal "$expected_branch" "$actual_branch" 'real worktree branch'
}
test_branch_prefix_traversal() {
    local repo="$FIXTURE_ROOT/traversal" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: worktrees\nbranch_prefix: ../../escaped' stderr_file="$FIXTURE_ROOT/traversal.stderr"
    # Given: a fixture repository whose configured worktree root is inside the repository.
    initialize_fixture "$repo" "$config" || return 1
    # When: a traversal branch prefix is supplied to feature creation.
    if invoke_feature "$repo" 'Reject traversal prefix' "$stderr_file"; then
        printf 'assertion failed: traversal prefix unexpectedly succeeded\n' >&2
        return 1
    fi
    # Then: creation fails without creating a directory outside the configured worktree root.
    if [ -e "$FIXTURE_ROOT/escaped" ]; then
        printf 'assertion failed: traversal escaped worktree_root\n' >&2
        return 1
    fi
}
test_exact_branch_override() {
    local repo="$FIXTURE_ROOT/exact-override" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../override-worktrees\nbranch_template: invalid-unused-template' stderr_file="$FIXTURE_ROOT/exact-override.stderr" expected_branch='override/008-exact-name' expected_path="$FIXTURE_ROOT/override-worktrees/override/008-exact-name" branch worktree_path
    # Given: an invalid unused template and a valid exact branch override.
    initialize_fixture "$repo" "$config" || return 1
    # When: GIT_BRANCH_NAME requests the exact branch and worktree.
    if ! invoke_exact_feature "$repo" "$expected_branch" "$stderr_file"; then
        printf 'exact override failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: the exact branch and real worktree succeed without template validation.
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1
    assert_equal "$expected_branch" "$branch" 'exact override branch' || return 1
    assert_equal "$expected_path" "$worktree_path" 'exact override worktree' || return 1
    assert_worktree "$branch" "$worktree_path"
}

test_unsupported_template_token() {
    local repo="$FIXTURE_ROOT/unsupported-token" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../unsupported-worktrees\nbranch_template: {number}-{slgu}' stderr_file="$FIXTURE_ROOT/unsupported-token.stderr"
    # Given: a branch template contains a misspelled, unsupported token.
    initialize_fixture "$repo" "$config" || return 1
    # When: feature creation evaluates the template.
    if invoke_feature "$repo" 'Reject unsupported token' "$stderr_file"; then
        printf 'assertion failed: unsupported template token unexpectedly succeeded\n' >&2
        return 1
    fi
    # Then: configuration validation fails before creating a branch or worktree.
    if ! grep -q 'unsupported token' "$stderr_file" || [ -e "$FIXTURE_ROOT/unsupported-worktrees" ]; then
        printf 'assertion failed: unsupported token was not rejected before mutation\n' >&2
        return 1
    fi
}
test_namespaced_branch_validator() {
    # Given: the bundled Bash Git common functions are loaded.
    # When: valid and malformed namespaced final segments are checked.
    # Then: only the valid {number}-{slug} final segment succeeds.
    source "$GIT_COMMON_SCRIPT"
    if ! check_feature_branch 'feature/008-next' true >/dev/null 2>&1; then
        printf 'assertion failed: valid namespaced branch rejected\n' >&2
        return 1
    fi
    for malformed_branch in 'feature/008' 'feature/next'; do
        if check_feature_branch "$malformed_branch" true >/dev/null 2>&1; then
            printf 'assertion failed: malformed branch accepted: %s\n' "$malformed_branch" >&2
            return 1
        fi
    done
}
test_branch_truncation() {
    local repo="$FIXTURE_ROOT/truncation" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../truncation-worktrees' stderr_file="$FIXTURE_ROOT/truncation.stderr" long_slug branch worktree_path branch_bytes
    # Given: a worktree fixture and a short-name longer than GitHub's branch limit.
    initialize_fixture "$repo" "$config" || return 1
    long_slug="$(printf 'longfeature%.0s' {1..30})"
    # When: the feature script creates the feature with that long slug.
    if ! invoke_feature "$repo" 'Truncate branch name' "$stderr_file" --short-name "$long_slug"; then
        printf 'truncation invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: JSON names a valid <=244-byte branch backed by a real worktree.
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1
    branch_bytes="$(printf '%s' "$branch" | LC_ALL=C wc -c | tr -d ' ')"
    if [ "$branch_bytes" -gt 244 ] || ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
        printf 'assertion failed: truncated branch is invalid or too long\n' >&2
        return 1
    fi
    assert_worktree "$branch" "$worktree_path"
}
test_dry_run_non_mutation() {
    local repo="$FIXTURE_ROOT/dry-run" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../dry-run-worktrees' stderr_file="$FIXTURE_ROOT/dry-run.stderr" head_before status_before branch worktree_path
    # Given: a clean worktree fixture with no prior feature branch or state file.
    initialize_fixture "$repo" "$config" || return 1
    head_before="$(git -C "$repo" rev-parse HEAD)"
    status_before="$(git -C "$repo" status --porcelain)"
    # When: feature creation runs in JSON dry-run mode.
    if ! invoke_feature "$repo" 'Dry run feature' "$stderr_file" --dry-run; then
        printf 'dry-run invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: JSON is predictive while Git, worktree, and state remain untouched.
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1
    json_true "$FEATURE_OUTPUT" DRY_RUN || return 1
    assert_equal '001-dry-run-feature' "$branch" 'dry-run branch' || return 1
    assert_equal "$FIXTURE_ROOT/dry-run-worktrees/$branch" "$worktree_path" 'dry-run path' || return 1
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" || [ -e "$worktree_path" ] || [ -e "$repo/.git/speckit-last-worktree.json" ]; then
        printf 'assertion failed: dry-run mutated Git state\n' >&2
        return 1
    fi
    assert_equal "$head_before" "$(git -C "$repo" rev-parse HEAD)" 'dry-run HEAD' || return 1
    assert_equal "$status_before" "$(git -C "$repo" status --porcelain)" 'dry-run status'
}
test_branch_checkout_mode() {
    local repo="$FIXTURE_ROOT/branch-mode" config=$'branch_numbering: sequential\ncheckout_mode: branch\nbase_branch: main\nworktree_root: ../branch-worktrees' stderr_file="$FIXTURE_ROOT/branch-mode.stderr" branch checkout_mode
    # Given: a fixture configured for branch checkout instead of linked worktrees.
    initialize_fixture "$repo" "$config" || return 1
    # When: the feature script creates a branch.
    if ! invoke_feature "$repo" 'Checkout branch mode' "$stderr_file"; then
        printf 'branch-mode invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: the repository switches to the branch and creates no worktree.
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    checkout_mode="$(json_field "$FEATURE_OUTPUT" CHECKOUT_MODE)" || return 1
    assert_equal '001-checkout-branch-mode' "$branch" 'branch-mode branch' || return 1
    assert_equal 'branch' "$checkout_mode" 'branch-mode checkout mode' || return 1
    assert_equal "$branch" "$(git -C "$repo" branch --show-current)" 'checked out branch' || return 1
    if json_has_key "$FEATURE_OUTPUT" WORKTREE_PATH || [ -e "$FIXTURE_ROOT/branch-worktrees" ]; then
        printf 'assertion failed: branch mode created a worktree\n' >&2
        return 1
    fi
}
test_allow_existing_branch_idempotency() {
    local repo="$FIXTURE_ROOT/idempotent" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../idempotent-worktrees' stderr_file="$FIXTURE_ROOT/idempotent.stderr" branch worktree_path rerun_branch rerun_path before_count after_count
    # Given: an existing feature branch is already checked out in one worktree.
    initialize_fixture "$repo" "$config" || return 1
    if ! invoke_feature "$repo" 'Idempotent feature' "$stderr_file"; then return 1; fi
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1
    before_count="$(git -C "$repo" worktree list --porcelain | grep -c '^worktree ')" || return 1
    # When: the exact branch is rerun with --allow-existing-branch.
    if ! invoke_exact_feature "$repo" "$branch" "$stderr_file" --allow-existing-branch; then
        printf 'allow-existing rerun failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: the same worktree resolves without adding another worktree entry.
    rerun_branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    rerun_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1
    after_count="$(git -C "$repo" worktree list --porcelain | grep -c '^worktree ')" || return 1
    assert_equal "$branch" "$rerun_branch" 'idempotent branch' || return 1
    assert_equal "$worktree_path" "$rerun_path" 'idempotent worktree' || return 1
    assert_equal "$before_count" "$after_count" 'worktree count' || return 1
    assert_worktree "$rerun_branch" "$rerun_path"
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
run_scenario 'branch prefix traversal is rejected' test_branch_prefix_traversal
run_scenario 'exact branch override ignores invalid template' test_exact_branch_override
run_scenario 'unsupported template token is rejected' test_unsupported_template_token
run_scenario 'namespaced branch validator' test_namespaced_branch_validator
run_scenario '244-byte branch truncation' test_branch_truncation
run_scenario 'dry-run non-mutation' test_dry_run_non_mutation
run_scenario 'branch checkout mode' test_branch_checkout_mode
run_scenario 'allow-existing-branch idempotency' test_allow_existing_branch_idempotency
if [ "$failures" -ne 0 ]; then
    printf 'RED: Speckit Git compatibility tests failed: %d scenario(s)\n' "$failures" >&2
    exit 1
fi
printf 'GREEN: Speckit Git compatibility tests passed\n'
