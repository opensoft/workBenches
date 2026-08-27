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
POWERSHELL_FEATURE_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/powershell/create-new-feature.ps1"
GIT_COMMON_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/bash/git-common.sh"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/speckit-git-compat.XXXXXX")"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT
if [ ! -x "$FEATURE_SCRIPT" ] || [ ! -f "$POWERSHELL_FEATURE_SCRIPT" ] || [ ! -f "$GIT_COMMON_SCRIPT" ]; then
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
    for malformed_branch in 'feature/008' 'feature/next' 'feature/008-' 'release/20260319-143022-'; do
        if check_feature_branch "$malformed_branch" true >/dev/null 2>&1; then
            printf 'assertion failed: malformed branch accepted: %s\n' "$malformed_branch" >&2
            return 1
        fi
    done
}
test_unknown_option_rejected_before_mutation() {
    local repo="$FIXTURE_ROOT/unknown-option" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../unknown-option-worktrees' stderr_file="$FIXTURE_ROOT/unknown-option.stderr"
    # Given: a clean worktree fixture with no feature branches.
    initialize_fixture "$repo" "$config" || return 1
    # When: feature creation receives an unrecognized option.
    if (cd "$repo" && env -u GIT_BRANCH_NAME bash "$FEATURE_SCRIPT" --json --bogus 'Reject unknown option' 2>"$stderr_file"); then
        printf 'assertion failed: unknown option unexpectedly succeeded\n' >&2
        return 1
    fi
    # Then: the option is identified and no branch or worktree is created.
    if ! grep -q 'unknown option.*--bogus' "$stderr_file"; then
        printf 'assertion failed: unknown option error was not reported\n' >&2
        return 1
    fi
    assert_equal 'main' "$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads)" 'branches after unknown option' || return 1
    if [ -e "$FIXTURE_ROOT/unknown-option-worktrees" ]; then
        printf 'assertion failed: unknown option created a worktree root\n' >&2
        return 1
    fi
}
test_description_option_sentinel() {
    local repo="$FIXTURE_ROOT/description-sentinel" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../description-sentinel-worktrees' stderr_file="$FIXTURE_ROOT/description-sentinel.stderr" branch
    # Given: a fixture where description text begins with an option-shaped word.
    initialize_fixture "$repo" "$config" || return 1
    # When: -- ends option parsing before the description.
    if ! FEATURE_OUTPUT="$(cd "$repo" && env -u GIT_BRANCH_NAME bash "$FEATURE_SCRIPT" --json --dry-run -- --timestamp remains-description 2>"$stderr_file")"; then
        printf 'description sentinel invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: all following arguments contribute to a sequential dry-run description.
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    assert_equal '001-timestamp-remains-description' "$branch" 'description after option sentinel'
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
test_branch_truncation_rejects_empty_slug() {
    local repo="$FIXTURE_ROOT/empty-truncation" prefix config stderr_file="$FIXTURE_ROOT/empty-truncation.stderr"
    prefix="$(printf 'p%.0s' {1..239})"
    config="$(printf 'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../empty-truncation-worktrees\nbranch_prefix: %s\n' "$prefix")"
    # Given: a disposable dry-run fixture whose prefix leaves no bytes for a slug.
    initialize_fixture "$repo" "$config" || return 1
    # When: branch truncation would reduce the generated name to prefix/001-.
    if invoke_feature "$repo" 'Reject empty truncation slug' "$stderr_file" --dry-run --short-name slug; then
        printf 'assertion failed: truncation that erased the slug unexpectedly succeeded\n' >&2
        return 1
    fi
    # Then: creation fails with the slug boundary identified and leaves Git untouched.
    if ! grep -q 'truncation.*slug' "$stderr_file"; then
        printf 'assertion failed: empty truncation slug error was not reported\n' >&2
        return 1
    fi
    assert_equal 'main' "$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads)" 'branches after empty truncation' || return 1
    if [ -e "$FIXTURE_ROOT/empty-truncation-worktrees" ] || [ -e "$repo/.git/speckit-last-worktree.json" ]; then
        printf 'assertion failed: empty truncation dry-run mutated state\n' >&2
        return 1
    fi
}
test_powershell_repository_and_truncation_source_safety() {
    local negative_guard_line timestamp_number_line mutation_line
    # Given: PowerShell is unavailable, so its critical boundaries are inspected as source.
    # When: repository detection and truncation guards are located.
    # Then: Git detection is rooted explicitly and truncation cannot emit an empty slug.
    if ! grep -Fq 'git -C $repoRoot rev-parse --is-inside-work-tree' "$POWERSHELL_FEATURE_SCRIPT"; then
        printf 'assertion failed: PowerShell Git detection is not rooted at repoRoot\n' >&2
        return 1
    fi
    if grep -Eq '\$hasGit[[:space:]]*=[[:space:]]*Test-HasGit' "$POWERSHELL_FEATURE_SCRIPT"; then
        printf 'assertion failed: PowerShell Git detection still depends on Test-HasGit signatures\n' >&2
        return 1
    fi
    if ! grep -Fq 'if ([string]::IsNullOrWhiteSpace($truncatedSuffix)) {' "$POWERSHELL_FEATURE_SCRIPT" \
        || ! grep -Fq 'Branch name truncation removed the feature slug' "$POWERSHELL_FEATURE_SCRIPT"; then
        printf 'assertion failed: PowerShell truncation lacks a nonempty slug guard\n' >&2
        return 1
    fi
    negative_guard_line="$(grep -nF "if (\$PSBoundParameters.ContainsKey('Number') -and \$Number -lt 0) {" "$POWERSHELL_FEATURE_SCRIPT" | cut -d: -f1)"
    timestamp_number_line="$(grep -nF "if (\$Timestamp -and \$PSBoundParameters.ContainsKey('Number')) {" "$POWERSHELL_FEATURE_SCRIPT" | cut -d: -f1)"
    mutation_line="$(grep -nF 'Set-Location $repoRoot' "$POWERSHELL_FEATURE_SCRIPT" | cut -d: -f1)"
    if [ -z "$negative_guard_line" ] \
        || ! grep -Fq -- '-Number must be zero or greater' "$POWERSHELL_FEATURE_SCRIPT"; then
        printf 'assertion failed: PowerShell lacks an explicit negative -Number guard\n' >&2
        return 1
    fi
    if [ -z "$timestamp_number_line" ] || [ -z "$mutation_line" ] \
        || [ "$negative_guard_line" -ge "$timestamp_number_line" ] \
        || [ "$negative_guard_line" -ge "$mutation_line" ]; then
        printf 'assertion failed: PowerShell negative -Number guard does not precede timestamp handling and mutation\n' >&2
        return 1
    fi
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
run_scenario 'unknown Bash option is rejected before mutation' test_unknown_option_rejected_before_mutation
run_scenario 'Bash description option sentinel' test_description_option_sentinel
run_scenario '244-byte branch truncation' test_branch_truncation
run_scenario 'branch truncation rejects an empty slug' test_branch_truncation_rejects_empty_slug
run_scenario 'PowerShell repository and truncation source safety' test_powershell_repository_and_truncation_source_safety
run_scenario 'dry-run non-mutation' test_dry_run_non_mutation
run_scenario 'branch checkout mode' test_branch_checkout_mode
run_scenario 'allow-existing-branch idempotency' test_allow_existing_branch_idempotency
if [ "$failures" -ne 0 ]; then
    printf 'RED: Speckit Git compatibility tests failed: %d scenario(s)\n' "$failures" >&2
    exit 1
fi
printf 'GREEN: Speckit Git compatibility tests passed\n'
