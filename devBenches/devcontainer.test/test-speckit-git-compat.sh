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
GET_LAST_WORKTREE_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/bash/get-last-worktree.sh"
POWERSHELL_FEATURE_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/powershell/create-new-feature.ps1"
GIT_COMMON_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/bash/git-common.sh"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/speckit-git-compat.XXXXXX")"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT
if [ ! -x "$FEATURE_SCRIPT" ] || [ ! -x "$GET_LAST_WORKTREE_SCRIPT" ] || [ ! -f "$POWERSHELL_FEATURE_SCRIPT" ] || [ ! -f "$GIT_COMMON_SCRIPT" ]; then
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
initialize_minimal_common_fixture() {
    local repo="$1" config="$2" script_dir
    initialize_fixture "$repo" "$config" || return 1
    script_dir="$repo/.specify/extensions/git/scripts/bash"
    mkdir -p "$script_dir" || return 1
    cp "$FEATURE_SCRIPT" "$script_dir/create-new-feature.sh" || return 1
    cp "$GIT_COMMON_SCRIPT" "$script_dir/git-common.sh" || return 1
    git -C "$repo" add .specify/extensions/git/scripts/bash || return 1
    git -C "$repo" commit --amend -qm 'fixture commit' || return 1
}
prepare_minimal_path() {
    local target="$1" include_python="$2" command_name command_path
    mkdir -p "$target" || return 1
    for command_name in bash basename chmod date dirname git grep head mkdir mktemp mv rm sed sh tail tr wc; do
        command_path="$(command -v "$command_name")" || return 1
        ln -s "$command_path" "$target/$command_name" || return 1
    done
    if [ "$include_python" = true ]; then
        command_path="$(command -v python3)" || return 1
        ln -s "$command_path" "$target/python3" || return 1
    fi
}
prepare_discovery_path() {
    local target="$1" command_name command_path
    mkdir -p "$target" || return 1
    for command_name in awk basename bash dirname git grep rm sed stat; do
        command_path="$(command -v "$command_name")" || return 1
        ln -s "$command_path" "$target/$command_name" || return 1
    done
}
install_get_last_fixture() {
    local repo="$1" script_dir="$repo/.specify/extensions/git/scripts/bash"
    mkdir -p "$script_dir" || return 1
    cp "$GET_LAST_WORKTREE_SCRIPT" "$script_dir/get-last-worktree.sh" || return 1
    cp "$GIT_COMMON_SCRIPT" "$script_dir/git-common.sh" || return 1
    chmod +x "$script_dir/get-last-worktree.sh" || return 1
}
write_worktree_state() {
    local state_file="$1" worktree_path="$2" branch_name="$3"
    python3 - "$state_file" "$worktree_path" "$branch_name" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as stream:
    json.dump({"WORKTREE_PATH": sys.argv[2], "BRANCH_NAME": sys.argv[3]}, stream)
PY
}
assert_state_output_file() {
    local output_file="$1" expected_path="$2" label="$3"
    python3 - "$output_file" "$expected_path" "$label" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    payload = json.load(stream)
if payload.get("WORKTREE_PATH") != sys.argv[2]:
    print("assertion failed: %s path was not byte-exact" % sys.argv[3], file=sys.stderr)
    raise SystemExit(1)
if payload.get("SOURCE") != "state_file":
    print("assertion failed: %s state was not authoritative" % sys.argv[3], file=sys.stderr)
    raise SystemExit(1)
PY
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
worktree_count() {
    if git -C "$1" worktree list --porcelain -z 2>/dev/null | python3 -c 'import sys; print(sum(field.startswith(b"worktree ") for field in sys.stdin.buffer.read().split(b"\0")))'; then
        return 0
    fi
    git -C "$1" worktree list --porcelain | python3 -c 'import sys; print(sum(line.startswith("worktree ") for line in sys.stdin))'
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
test_repeated_number_template_rejected_before_mutation() {
    local repo="$FIXTURE_ROOT/repeated-number" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../repeated-number-worktrees\nbranch_template: {number}/{number}-{slug}' stderr_file="$FIXTURE_ROOT/repeated-number.stderr" head_before status_before refs_before worktrees_before
    # Given: a clean fixture whose branch template repeats the numbering token.
    initialize_fixture "$repo" "$config" || return 1
    head_before="$(git -C "$repo" rev-parse HEAD)" || return 1
    status_before="$(git -C "$repo" status --porcelain)" || return 1
    refs_before="$(git -C "$repo" for-each-ref --format='%(refname)' refs/heads)" || return 1
    worktrees_before="$(git -C "$repo" worktree list --porcelain | grep -c '^worktree ')" || return 1
    # When: feature creation evaluates the repeated {number} template.
    if invoke_feature "$repo" 'Reject repeated number token' "$stderr_file"; then
        printf 'assertion failed: repeated {number} template unexpectedly succeeded\n' >&2
        return 1
    fi
    # Then: validation explains the exactly-one rule before Git, worktree, or state mutation.
    if ! grep -Fq 'exactly one {number}' "$stderr_file"; then
        printf 'assertion failed: repeated {number} template did not report the exactly-one rule\n' >&2
        return 1
    fi
    assert_equal "$head_before" "$(git -C "$repo" rev-parse HEAD)" 'HEAD after repeated number rejection' || return 1
    assert_equal "$status_before" "$(git -C "$repo" status --porcelain)" 'status after repeated number rejection' || return 1
    assert_equal "$refs_before" "$(git -C "$repo" for-each-ref --format='%(refname)' refs/heads)" 'branches after repeated number rejection' || return 1
    assert_equal "$worktrees_before" "$(git -C "$repo" worktree list --porcelain | grep -c '^worktree ')" 'worktrees after repeated number rejection' || return 1
    if [ -e "$FIXTURE_ROOT/repeated-number-worktrees" ] || [ -e "$repo/.git/speckit-last-worktree.json" ]; then
        printf 'assertion failed: repeated {number} rejection mutated worktree or state\n' >&2
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
    if [ "$branch_bytes" -gt 244 ] || ! git -C "$repo" check-ref-format --branch "$branch" >/dev/null 2>&1; then
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
    if ! grep -Fq "if (-not \$ScopePrefix -and \$name.Contains('/')) {" "$POWERSHELL_FEATURE_SCRIPT"; then
        printf 'assertion failed: PowerShell root numbering does not exclude namespaced refs\n' >&2
        return 1
    fi
    if ! grep -Fq "([regex]::Matches(\$Template, '\{number\}')).Count -ne 1" "$POWERSHELL_FEATURE_SCRIPT" \
        || ! grep -Fq 'exactly one {number}' "$POWERSHELL_FEATURE_SCRIPT"; then
        printf 'assertion failed: PowerShell branch template validation does not require exactly one {number} token\n' >&2
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
    local repo="$FIXTURE_ROOT/idempotent" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../unused-idempotent-worktrees' stderr_file="$FIXTURE_ROOT/idempotent.stderr" branch worktree_path rerun_branch rerun_path before_count after_count state_path
    local worktree_root="$FIXTURE_ROOT/"$'idempotent-"quote\\slash\tcontrol\nline-worktrees'
    # Given: an existing feature branch is checked out at a path Git C-quotes in line-oriented porcelain.
    initialize_fixture "$repo" "$config" || return 1
    if ! FEATURE_OUTPUT="$(cd "$repo" && SPECKIT_GIT_WORKTREE_ROOT="$worktree_root" env -u GIT_BRANCH_NAME bash "$FEATURE_SCRIPT" --json 'Idempotent feature' 2>"$stderr_file")"; then return 1; fi
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1
    assert_equal "$worktree_root/$branch" "$worktree_path" 'special idempotent worktree path' || return 1
    before_count="$(worktree_count "$repo")" || return 1
    # When: the exact branch is rerun with --allow-existing-branch.
    if ! FEATURE_OUTPUT="$(cd "$repo" && SPECKIT_GIT_WORKTREE_ROOT="$worktree_root" GIT_BRANCH_NAME="$branch" bash "$FEATURE_SCRIPT" --json --allow-existing-branch ignored 2>"$stderr_file")"; then
        printf 'allow-existing rerun failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: the same worktree resolves without adding another worktree entry.
    rerun_branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    rerun_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1
    after_count="$(worktree_count "$repo")" || return 1
    assert_equal "$branch" "$rerun_branch" 'idempotent branch' || return 1
    assert_equal "$worktree_path" "$rerun_path" 'idempotent worktree' || return 1
    assert_equal "$before_count" "$after_count" 'worktree count' || return 1
    assert_worktree "$rerun_branch" "$rerun_path" || return 1
    state_path="$(json_field "$(<"$repo/.git/speckit-last-worktree.json")" WORKTREE_PATH)" || return 1
    assert_equal "$worktree_path" "$state_path" 'idempotent state worktree'
}
test_no_jq_minimal_common_json_round_trip() {
    local repo="$FIXTURE_ROOT/minimal-common" stderr_file="$FIXTURE_ROOT/minimal-common.stderr" no_jq_path="$FIXTURE_ROOT/no-jq-bin" branch worktree_path state_path config worktree_root
    worktree_root="$FIXTURE_ROOT/"$'forged","X":"z\\backslash\tcontrol-worktrees'
    config="$(printf 'checkout_mode: worktree\nbase_branch: main\nworktree_root: %s\n' "$worktree_root")"
    # Given: only the bundled minimal common script, Python 3, and no jq are available.
    initialize_minimal_common_fixture "$repo" "$config" || return 1
    prepare_minimal_path "$no_jq_path" true || return 1
    # When: a configured root contains JSON metacharacters and a control character.
    if ! FEATURE_OUTPUT="$(cd "$repo" && PATH="$no_jq_path" GIT_BRANCH_NAME='001-minimal-json' "$no_jq_path/bash" "$repo/.specify/extensions/git/scripts/bash/create-new-feature.sh" --json ignored 2>"$stderr_file")"; then
        printf 'minimal-common no-jq invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: Python serializes the complete payload and state without forged fields.
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1
    state_path="$(json_field "$(<"$repo/.git/speckit-last-worktree.json")" WORKTREE_PATH)" || return 1
    assert_equal '001-minimal-json' "$branch" 'minimal-common branch' || return 1
    assert_equal "$worktree_root/$branch" "$worktree_path" 'minimal-common JSON worktree' || return 1
    assert_equal "$worktree_path" "$state_path" 'minimal-common state worktree' || return 1
    if json_has_key "$FEATURE_OUTPUT" X; then
        printf 'assertion failed: malicious worktree root forged a JSON field\n' >&2
        return 1
    fi
    assert_worktree "$branch" "$worktree_path"
}
test_missing_json_encoder_fails_before_mutation() {
    local repo="$FIXTURE_ROOT/no-encoder" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../no-encoder-worktrees' stderr_file="$FIXTURE_ROOT/no-encoder.stderr" no_encoder_path="$FIXTURE_ROOT/no-encoder-bin" refs_before worktrees_before
    # Given: worktree output requires JSON state but jq, json_escape, and Python are unavailable.
    initialize_minimal_common_fixture "$repo" "$config" || return 1
    prepare_minimal_path "$no_encoder_path" false || return 1
    refs_before="$(git -C "$repo" for-each-ref --format='%(refname)' refs/heads)" || return 1
    worktrees_before="$(worktree_count "$repo")" || return 1
    # When: feature creation cannot select a trusted JSON encoder.
    if (cd "$repo" && PATH="$no_encoder_path" GIT_BRANCH_NAME='001-no-encoder' "$no_encoder_path/bash" "$repo/.specify/extensions/git/scripts/bash/create-new-feature.sh" ignored 2>"$stderr_file"); then
        printf 'assertion failed: feature creation succeeded without a JSON encoder\n' >&2
        return 1
    fi
    # Then: it fails closed before creating a branch, worktree, or state file.
    if ! grep -Fq 'JSON encoder' "$stderr_file"; then
        printf 'assertion failed: missing JSON encoder diagnostic was not reported\n' >&2
        return 1
    fi
    assert_equal "$refs_before" "$(git -C "$repo" for-each-ref --format='%(refname)' refs/heads)" 'branches after encoder failure' || return 1
    assert_equal "$worktrees_before" "$(worktree_count "$repo")" 'worktrees after encoder failure' || return 1
    if [ -e "$FIXTURE_ROOT/no-encoder-worktrees" ] || [ -e "$repo/.git/speckit-last-worktree.json" ]; then
        printf 'assertion failed: missing encoder failure mutated worktree or state\n' >&2
        return 1
    fi
}
test_state_symlink_rejected_before_mutation() {
    local repo="$FIXTURE_ROOT/state-symlink" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../state-symlink-worktrees' stderr_file="$FIXTURE_ROOT/state-symlink.stderr"
    local state_file sentinel sentinel_before refs_before worktrees_before
    # Given: the final state path is a symlink to external sentinel bytes.
    initialize_fixture "$repo" "$config" || return 1
    state_file="$repo/.git/speckit-last-worktree.json"
    sentinel="$FIXTURE_ROOT/state-symlink-sentinel"
    printf 'external sentinel bytes\n' > "$sentinel" || return 1
    sentinel_before="$(<"$sentinel")"
    ln -s "$sentinel" "$state_file" || return 1
    refs_before="$(git -C "$repo" for-each-ref --format='%(refname)' refs/heads)" || return 1
    worktrees_before="$(worktree_count "$repo")" || return 1
    # When: feature creation attempts to create a worktree.
    if invoke_exact_feature "$repo" '001-state-symlink' "$stderr_file"; then
        printf 'assertion failed: feature creation succeeded with symlinked state\n' >&2
        return 1
    fi
    # Then: rejection precedes all Git/worktree mutation and never follows the link.
    assert_equal "$refs_before" "$(git -C "$repo" for-each-ref --format='%(refname)' refs/heads)" 'branches after symlinked state rejection' || return 1
    assert_equal "$worktrees_before" "$(worktree_count "$repo")" 'worktrees after symlinked state rejection' || return 1
    assert_equal "$sentinel_before" "$(<"$sentinel")" 'external sentinel after symlinked state rejection' || return 1
    if [ ! -L "$state_file" ] || [ -e "$FIXTURE_ROOT/state-symlink-worktrees" ]; then
        printf 'assertion failed: symlinked state rejection changed the state path or worktree root\n' >&2
        return 1
    fi
}
test_malformed_regular_state_is_atomically_replaced() {
    local repo="$FIXTURE_ROOT/malformed-state" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../malformed-state-worktrees' stderr_file="$FIXTURE_ROOT/malformed-state.stderr"
    local state_file branch state_branch state_mode temp_count temp_path
    # Given: the final state path is an existing malformed regular file.
    initialize_fixture "$repo" "$config" || return 1
    state_file="$repo/.git/speckit-last-worktree.json"
    printf '{malformed json\n' > "$state_file" || return 1
    # When: feature creation succeeds.
    if ! invoke_exact_feature "$repo" '001-malformed-state' "$stderr_file"; then
        printf 'malformed-state recovery failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: valid JSON replaces the regular file and no sibling temporary survives.
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    state_branch="$(json_field "$(<"$state_file")" BRANCH_NAME)" || return 1
    assert_equal "$branch" "$state_branch" 'recovered state branch' || return 1
    state_mode="$(python3 - "$state_file" <<'PY'
import os
import stat
import sys

print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))
PY
)" || return 1
    assert_equal '0o600' "$state_mode" 'state file owner-only permissions' || return 1
    temp_count=0
    for temp_path in "$repo/.git"/.speckit-last-worktree.json.tmp.*; do
        [ -e "$temp_path" ] || continue
        temp_count=$((temp_count + 1))
    done
    assert_equal '0' "$temp_count" 'state temporary cleanup'
}
test_temporary_state_leaf_swap_cannot_touch_external_sentinel() {
    local repo="$FIXTURE_ROOT/state-temp-leaf-swap" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../state-temp-leaf-swap-worktrees'
    local stderr_file="$FIXTURE_ROOT/state-temp-leaf-swap.stderr" restricted_path="$FIXTURE_ROOT/state-temp-leaf-swap-bin"
    local state_file sentinel sentinel_before sentinel_mode_before sentinel_mode_after hook_marker site_dir
    local real_chmod real_rm real_ln invocation_succeeded=false temp_count=0 temp_path
    # Given: an attacker can replace the temporary directory entry exactly when publication first changes its mode.
    initialize_minimal_common_fixture "$repo" "$config" || return 1
    prepare_minimal_path "$restricted_path" true || return 1
    state_file="$repo/.git/speckit-last-worktree.json"
    sentinel="$FIXTURE_ROOT/state-temp-leaf-swap-sentinel"
    hook_marker="$FIXTURE_ROOT/state-temp-leaf-swap-hook-fired"
    site_dir="$FIXTURE_ROOT/state-temp-leaf-swap-site"
    mkdir -p "$site_dir" || return 1
    printf 'external sentinel bytes\n' > "$sentinel" || return 1
    chmod 640 "$sentinel" || return 1
    printf '{"BRANCH_NAME":"old-state"}\n' > "$state_file" || return 1
    sentinel_before="$(<"$sentinel")"
    sentinel_mode_before="$(python3 - "$sentinel" <<'PY'
import os
import stat
import sys

print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))
PY
)" || return 1
    real_chmod="$(command -v chmod)" || return 1
    real_rm="$(command -v rm)" || return 1
    real_ln="$(command -v ln)" || return 1
    "$real_rm" -f "$restricted_path/chmod" || return 1
    cat > "$restricted_path/chmod" <<'SH'
#!/usr/bin/env bash
case "${2:-}" in
    */.speckit-last-worktree.json.tmp.*)
        if [ ! -e "$SPECKIT_TEST_HOOK_MARKER" ]; then
            "$SPECKIT_TEST_REAL_RM" -f "$2" || exit 1
            "$SPECKIT_TEST_REAL_LN" -s "$SPECKIT_TEST_SENTINEL" "$2" || exit 1
            : > "$SPECKIT_TEST_HOOK_MARKER"
        fi
        ;;
esac
exec "$SPECKIT_TEST_REAL_CHMOD" "$@"
SH
    chmod +x "$restricted_path/chmod" || return 1
    cat > "$site_dir/sitecustomize.py" <<'PY'
import os

_original_fchmod = os.fchmod
_original_open = os.open
_temporary_files = {}


def _state_open(path, flags, mode=0o777, *, dir_fd=None):
    descriptor = _original_open(path, flags, mode, dir_fd=dir_fd)
    if flags & os.O_CREAT and os.path.basename(path).startswith(".speckit-last-worktree.json.tmp."):
        _temporary_files[descriptor] = (path, dir_fd)
    return descriptor


def _state_fchmod(descriptor, mode):
    temporary_file = _temporary_files.get(descriptor)
    marker = os.environ.get("SPECKIT_TEST_HOOK_MARKER", "")
    if temporary_file is not None and marker and not os.path.exists(marker):
        path, directory_fd = temporary_file
        os.unlink(path, dir_fd=directory_fd)
        os.symlink(os.environ["SPECKIT_TEST_SENTINEL"], path, dir_fd=directory_fd)
        with open(marker, "wb"):
            pass
    return _original_fchmod(descriptor, mode)


os.open = _state_open
os.fchmod = _state_fchmod
PY
    # When: the leaf is swapped at the former pathname reopen seam or its descriptor-retaining equivalent.
    if FEATURE_OUTPUT="$(cd "$repo" && PATH="$restricted_path" PYTHONPATH="$site_dir" \
        SPECKIT_TEST_STATE_FILE="$state_file" SPECKIT_TEST_SENTINEL="$sentinel" \
        SPECKIT_TEST_HOOK_MARKER="$hook_marker" SPECKIT_TEST_REAL_CHMOD="$real_chmod" \
        SPECKIT_TEST_REAL_RM="$real_rm" SPECKIT_TEST_REAL_LN="$real_ln" \
        GIT_BRANCH_NAME='001-state-temp-leaf-swap' "$restricted_path/bash" \
        "$repo/.specify/extensions/git/scripts/bash/create-new-feature.sh" --json ignored 2>"$stderr_file")"; then
        invocation_succeeded=true
    fi
    # Then: the swap is exercised, external bytes and mode are unchanged, and no attacker leaf is published or removed.
    if [ ! -f "$hook_marker" ]; then
        printf 'assertion failed: temporary state leaf swap hook did not fire\n' >&2
        return 1
    fi
    assert_equal "$sentinel_before" "$(<"$sentinel")" 'external sentinel bytes after temporary leaf swap' || return 1
    sentinel_mode_after="$(python3 - "$sentinel" <<'PY'
import os
import stat
import sys

print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))
PY
)" || return 1
    assert_equal "$sentinel_mode_before" "$sentinel_mode_after" 'external sentinel mode after temporary leaf swap' || return 1
    if $invocation_succeeded || [ -L "$state_file" ] || [ ! -f "$state_file" ]; then
        printf 'assertion failed: temporary state leaf swap was published or accepted\n' >&2
        return 1
    fi
    for temp_path in "$repo/.git"/.speckit-last-worktree.json.tmp.*; do
        [ -L "$temp_path" ] || continue
        temp_count=$((temp_count + 1))
        assert_equal "$sentinel" "$(readlink "$temp_path")" 'unowned replacement leaf target' || return 1
    done
    assert_equal '1' "$temp_count" 'unowned replacement leaf preservation'
}
test_replacement_race_cannot_publish_into_symlinked_directory() {
    local repo="$FIXTURE_ROOT/state-replacement-race" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../state-replacement-race-worktrees'
    local stderr_file="$FIXTURE_ROOT/state-replacement-race.stderr" restricted_path="$FIXTURE_ROOT/state-replacement-race-bin"
    local state_file sentinel_dir sentinel_file sentinel_before hook_marker site_dir real_mv real_rm real_ln entry_count entry
    # Given: publication is paused at its final replacement operation while an attacker swaps the checked destination.
    initialize_minimal_common_fixture "$repo" "$config" || return 1
    prepare_minimal_path "$restricted_path" true || return 1
    state_file="$repo/.git/speckit-last-worktree.json"
    sentinel_dir="$FIXTURE_ROOT/state-replacement-race-sentinel"
    sentinel_file="$sentinel_dir/external-sentinel"
    hook_marker="$FIXTURE_ROOT/state-replacement-race-hook-fired"
    site_dir="$FIXTURE_ROOT/state-replacement-race-site"
    mkdir -p "$sentinel_dir" "$site_dir" || return 1
    printf 'external sentinel bytes\n' > "$sentinel_file" || return 1
    printf '{"WORKTREE_PATH":"old-state"}\n' > "$state_file" || return 1
    sentinel_before="$(<"$sentinel_file")"
    real_mv="$(command -v mv)" || return 1
    real_rm="$(command -v rm)" || return 1
    real_ln="$(command -v ln)" || return 1
    "$real_rm" -f "$restricted_path/mv" || return 1
    cat > "$restricted_path/mv" <<'SH'
#!/usr/bin/env bash
if [ "$#" -eq 3 ] && [ "$1" = -f ] && [ "$3" = "$SPECKIT_TEST_STATE_FILE" ] && [ ! -e "$SPECKIT_TEST_HOOK_MARKER" ]; then
    "$SPECKIT_TEST_REAL_RM" -f "$SPECKIT_TEST_STATE_FILE" || exit 1
    "$SPECKIT_TEST_REAL_LN" -s "$SPECKIT_TEST_SENTINEL_DIR" "$SPECKIT_TEST_STATE_FILE" || exit 1
    : > "$SPECKIT_TEST_HOOK_MARKER"
fi
exec "$SPECKIT_TEST_REAL_MV" "$@"
SH
    chmod +x "$restricted_path/mv" || return 1
    cat > "$site_dir/sitecustomize.py" <<'PY'
import os

_original_replace = os.replace


def _state_replace(source, destination, *args, **kwargs):
    state_file = os.environ.get("SPECKIT_TEST_STATE_FILE", "")
    marker = os.environ.get("SPECKIT_TEST_HOOK_MARKER", "")
    destination_text = os.fspath(destination)
    targets_state = destination_text == state_file or (
        destination_text == os.path.basename(state_file)
        and kwargs.get("dst_dir_fd") is not None
    )
    if state_file and marker and targets_state and not os.path.exists(marker):
        if os.path.lexists(state_file):
            os.unlink(state_file)
        os.symlink(os.environ["SPECKIT_TEST_SENTINEL_DIR"], state_file)
        with open(marker, "wb"):
            pass
    return _original_replace(source, destination, *args, **kwargs)


os.replace = _state_replace
PY
    # When: the race hook swaps the destination immediately before mv or descriptor-relative os.replace publishes.
    if ! FEATURE_OUTPUT="$(cd "$repo" && PATH="$restricted_path" PYTHONPATH="$site_dir" \
        SPECKIT_TEST_STATE_FILE="$state_file" SPECKIT_TEST_SENTINEL_DIR="$sentinel_dir" \
        SPECKIT_TEST_HOOK_MARKER="$hook_marker" SPECKIT_TEST_REAL_MV="$real_mv" \
        SPECKIT_TEST_REAL_RM="$real_rm" SPECKIT_TEST_REAL_LN="$real_ln" \
        GIT_BRANCH_NAME='001-state-replacement-race' "$restricted_path/bash" \
        "$repo/.specify/extensions/git/scripts/bash/create-new-feature.sh" --json ignored 2>"$stderr_file")"; then
        printf 'state replacement race invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    # Then: the hook ran, publication replaced the pathname itself, and no temporary file entered the sentinel directory.
    if [ ! -f "$hook_marker" ]; then
        printf 'assertion failed: state replacement race hook did not fire\n' >&2
        return 1
    fi
    entry_count=0
    for entry in "$sentinel_dir"/.[!.]* "$sentinel_dir"/..?* "$sentinel_dir"/*; do
        [ -e "$entry" ] || continue
        entry_count=$((entry_count + 1))
    done
    assert_equal '1' "$entry_count" 'external sentinel directory entries after replacement race' || return 1
    assert_equal "$sentinel_before" "$(<"$sentinel_file")" 'external sentinel bytes after replacement race' || return 1
    if [ -L "$state_file" ] || [ ! -f "$state_file" ]; then
        printf 'assertion failed: replacement race did not publish a regular state file\n' >&2
        return 1
    fi
    assert_equal '001-state-replacement-race' "$(json_field "$(<"$state_file")" BRANCH_NAME)" 'replacement race state branch'
}
test_parserless_non_json_state_uses_verified_fallback() {
    local repo="$FIXTURE_ROOT/parserless-state" root="$FIXTURE_ROOT/parserless-state-worktrees"
    local stale_path="$root/001-stale-state" fallback_path="$root/002-verified-fallback"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../parserless-state-worktrees'
    local restricted_path="$FIXTURE_ROOT/parserless-state-bin" state_file output
    # Given: parser tools are absent and regex-shaped non-JSON names an older registered worktree.
    initialize_fixture "$repo" "$config" || return 1
    install_get_last_fixture "$repo" || return 1
    prepare_discovery_path "$restricted_path" || return 1
    GIT_MASTER=1 git -C "$repo" branch '001-stale-state' || return 1
    GIT_MASTER=1 git -C "$repo" branch '002-verified-fallback' || return 1
    GIT_MASTER=1 git -C "$repo" worktree add -q "$stale_path" '001-stale-state' || return 1
    GIT_MASTER=1 git -C "$repo" worktree add -q "$fallback_path" '002-verified-fallback' || return 1
    touch -t 202001010101 "$stale_path" || return 1
    touch -t 202001010102 "$fallback_path" || return 1
    state_file="$repo/.git/speckit-last-worktree.json"
    printf 'not-json {"WORKTREE_PATH":"%s"} trailing bytes\n' "$stale_path" > "$state_file" || return 1
    # When: get-last runs without jq or Python.
    output="$(cd "$repo" && PATH="$restricted_path" "$restricted_path/bash" \
        .specify/extensions/git/scripts/bash/get-last-worktree.sh)" || return 1
    # Then: unverified state is ignored and the newest verified registration is used.
    if [ "$output" != "$fallback_path" ]; then
        printf 'assertion failed: regex-shaped non-JSON state remained authoritative without a parser\n' >&2
        return 1
    fi
}
test_trailing_lf_state_paths_round_trip_authoritatively() {
    local repo="$FIXTURE_ROOT/trailing-lf-state" root="$FIXTURE_ROOT/trailing-lf-state-worktrees"
    local one_lf_path="$root/001-one-lf"$'\n' two_lf_path="$root/002-two-lf"$'\n\n'
    local fallback_path="$root/003-newer-fallback" state_file one_output two_output scenario_failed=false
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../trailing-lf-state-worktrees'
    # Given: one- and two-LF terminal paths are registered, but a different worktree is newer.
    initialize_fixture "$repo" "$config" || return 1
    install_get_last_fixture "$repo" || return 1
    GIT_MASTER=1 git -C "$repo" branch '001-one-lf' || return 1
    GIT_MASTER=1 git -C "$repo" branch '002-two-lf' || return 1
    GIT_MASTER=1 git -C "$repo" branch '003-newer-fallback' || return 1
    GIT_MASTER=1 git -C "$repo" worktree add -q "$one_lf_path" '001-one-lf' || return 1
    GIT_MASTER=1 git -C "$repo" worktree add -q "$two_lf_path" '002-two-lf' || return 1
    GIT_MASTER=1 git -C "$repo" worktree add -q "$fallback_path" '003-newer-fallback' || return 1
    touch -t 202001010101 "$one_lf_path" || return 1
    touch -t 202001010102 "$two_lf_path" || return 1
    touch -t 202001010103 "$fallback_path" || return 1
    state_file="$repo/.git/speckit-last-worktree.json"
    one_output="$FIXTURE_ROOT/trailing-lf-state-one.json"
    two_output="$FIXTURE_ROOT/trailing-lf-state-two.json"
    # When: each exact path is written to state and read through file-backed JSON output.
    write_worktree_state "$state_file" "$one_lf_path" 'forged/ignored' || return 1
    (cd "$repo" && bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json > "$one_output") || return 1
    if ! assert_state_output_file "$one_output" "$one_lf_path" 'one-LF'; then
        scenario_failed=true
    fi
    write_worktree_state "$state_file" "$two_lf_path" 'forged/ignored' || return 1
    (cd "$repo" && bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json > "$two_output") || return 1
    if ! assert_state_output_file "$two_output" "$two_lf_path" 'two-LF'; then
        scenario_failed=true
    fi
    # Then: both byte-exact registered paths remain authoritative despite fallback ordering.
    if $scenario_failed; then
        return 1
    fi
}
test_jq_without_python_fails_before_worktree_mutation() {
    local repo="$FIXTURE_ROOT/jq-no-python" config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../jq-no-python-worktrees'
    local stderr_file="$FIXTURE_ROOT/jq-no-python.stderr" restricted_path="$FIXTURE_ROOT/jq-no-python-bin"
    local jq_path head_before status_before refs_before worktrees_before scenario_failed=false
    # Given: jq is available in a restricted PATH, but Python is absent from a clean worktree fixture.
    initialize_minimal_common_fixture "$repo" "$config" || return 1
    prepare_minimal_path "$restricted_path" false || return 1
    jq_path="$(command -v jq)" || return 1
    ln -s "$jq_path" "$restricted_path/jq" || return 1
    head_before="$(GIT_MASTER=1 git -C "$repo" rev-parse HEAD)" || return 1
    status_before="$(GIT_MASTER=1 git -C "$repo" status --porcelain)" || return 1
    refs_before="$(GIT_MASTER=1 git -C "$repo" for-each-ref --format='%(refname)' refs/heads)" || return 1
    worktrees_before="$(worktree_count "$repo")" || return 1
    # When: non-dry-run worktree creation attempts to rely on jq alone.
    if (cd "$repo" && PATH="$restricted_path" GIT_BRANCH_NAME='001-jq-no-python' \
        "$restricted_path/bash" "$repo/.specify/extensions/git/scripts/bash/create-new-feature.sh" \
        ignored >/dev/null 2>"$stderr_file"); then
        printf 'assertion failed: non-dry-run worktree creation succeeded with jq but without Python\n' >&2
        scenario_failed=true
    fi
    # Then: Python preflight fails before changing HEAD, status, refs, worktrees, or state.
    assert_equal "$head_before" "$(GIT_MASTER=1 git -C "$repo" rev-parse HEAD)" 'HEAD after jq-only rejection' || scenario_failed=true
    assert_equal "$status_before" "$(GIT_MASTER=1 git -C "$repo" status --porcelain)" 'status after jq-only rejection' || scenario_failed=true
    assert_equal "$refs_before" "$(GIT_MASTER=1 git -C "$repo" for-each-ref --format='%(refname)' refs/heads)" 'branches after jq-only rejection' || scenario_failed=true
    assert_equal "$worktrees_before" "$(worktree_count "$repo")" 'worktrees after jq-only rejection' || scenario_failed=true
    if [ -e "$FIXTURE_ROOT/jq-no-python-worktrees" ] || [ -e "$repo/.git/speckit-last-worktree.json" ]; then
        printf 'assertion failed: jq-only rejection mutated worktree or state\n' >&2
        scenario_failed=true
    fi
    if $scenario_failed; then
        return 1
    fi
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
run_scenario 'repeated {number} template is rejected before mutation' test_repeated_number_template_rejected_before_mutation
run_scenario 'namespaced branch validator' test_namespaced_branch_validator
run_scenario 'unknown Bash option is rejected before mutation' test_unknown_option_rejected_before_mutation
run_scenario 'Bash description option sentinel' test_description_option_sentinel
run_scenario '244-byte branch truncation' test_branch_truncation
run_scenario 'branch truncation rejects an empty slug' test_branch_truncation_rejects_empty_slug
run_scenario 'PowerShell repository and truncation source safety' test_powershell_repository_and_truncation_source_safety
run_scenario 'dry-run non-mutation' test_dry_run_non_mutation
run_scenario 'branch checkout mode' test_branch_checkout_mode
run_scenario 'allow-existing-branch special-path idempotency' test_allow_existing_branch_idempotency
run_scenario 'no-jq minimal-common JSON round trip' test_no_jq_minimal_common_json_round_trip
run_scenario 'missing JSON encoder fails before mutation' test_missing_json_encoder_fails_before_mutation
run_scenario 'symlinked state is rejected before Git mutation' test_state_symlink_rejected_before_mutation
run_scenario 'malformed regular state is atomically replaced' test_malformed_regular_state_is_atomically_replaced
run_scenario 'temporary state leaf swap cannot touch an external sentinel' test_temporary_state_leaf_swap_cannot_touch_external_sentinel
run_scenario 'replacement race cannot publish into a symlinked directory' test_replacement_race_cannot_publish_into_symlinked_directory
run_scenario 'parserless non-JSON state uses verified fallback' test_parserless_non_json_state_uses_verified_fallback
run_scenario 'trailing-LF state paths round-trip authoritatively' test_trailing_lf_state_paths_round_trip_authoritatively
run_scenario 'jq without Python fails before worktree mutation' test_jq_without_python_fails_before_worktree_mutation
if [ "$failures" -ne 0 ]; then
    printf 'RED: Speckit Git compatibility tests failed: %d scenario(s)\n' "$failures" >&2
    exit 1
fi
printf 'GREEN: Speckit Git compatibility tests passed\n'
