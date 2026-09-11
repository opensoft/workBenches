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
GIT_COMMON_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/bash/git-common.sh"
AUTO_COMMIT_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/bash/auto-commit.sh"
WORKSPACE_COMMON_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/bash/workspace-common.sh"
PARK_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/bash/park.sh"
RESUME_SCRIPT="$TEMPLATE_ROOT/specify/extensions/git/scripts/bash/resume.sh"
SELECT_WORKTREE_SCRIPT="$TEMPLATE_ROOT/specify/shell/select-worktree.sh"

# The pinned openRepoShape files this suite READS. The three-leg fixture's
# manifest is derived from the assembly-root template
# (write_three_leg_manifest), and one scenario runs the pin checker over the
# vendored copies themselves.
#
# TWO ways, not the three above: the image deliberately does NOT carry these
# templates — they are a fixture input, not a command, and
# devBenches/base-image/Dockerfile says so — so there is no
# /usr/local/share fallback to invent. A run with only devcontainer.test/
# mounted names them through the environment instead, which is what this
# directory's own docker-compose.yml does.
SOURCE_SHAPE_TEMPLATE_ROOT="$REPO_ROOT/devBenches/base-image/files/openreposhape/templates"
SHAPE_TEMPLATE_ROOT="${WORKBENCHES_SHAPE_TEMPLATE_ROOT:-$SOURCE_SHAPE_TEMPLATE_ROOT}"
THREE_LEG_MANIFEST_TEMPLATE="$SHAPE_TEMPLATE_ROOT/assembly-root/project.yaml"
SOURCE_UPDATE_UPSTREAM_FILE="$REPO_ROOT/devBenches/base-image/update-upstream.py"
UPDATE_UPSTREAM_FILE="${UPDATE_UPSTREAM_FILE:-$SOURCE_UPDATE_UPSTREAM_FILE}"

REAL_GIT="$(command -v git)"

FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/speckit-git-feature.XXXXXX")"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

for required_script in "$FEATURE_SCRIPT" "$GET_LAST_WORKTREE_SCRIPT" "$GIT_COMMON_SCRIPT" "$AUTO_COMMIT_SCRIPT" "$WORKSPACE_COMMON_SCRIPT" "$PARK_SCRIPT" "$RESUME_SCRIPT" "$SELECT_WORKTREE_SCRIPT"; do
    if [ ! -x "$required_script" ]; then
        printf 'Checked-in Speckit script is missing or not executable: %s\n' "$required_script" >&2
        exit 1
    fi
done

# `[ -f ]` and not `[ -x ]`: the manifest template is data, and the pin checker
# is invoked through `python3`. Both are vendored under
# devBenches/base-image/files/openreposhape/ and pinned by
# devBenches/base-image/upstream-pin.yaml.
for required_file in "$THREE_LEG_MANIFEST_TEMPLATE" "$UPDATE_UPSTREAM_FILE"; do
    if [ ! -f "$required_file" ]; then
        printf 'Pinned openRepoShape fixture input is missing: %s\n' "$required_file" >&2
        printf 'Set $WORKBENCHES_SHAPE_TEMPLATE_ROOT and $UPDATE_UPSTREAM_FILE when only\n' >&2
        printf 'devBenches/devcontainer.test/ is mounted; the image does not carry them.\n' >&2
        exit 1
    fi
done

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

install_discovery_scripts() {
    local repo="$1"

    mkdir -p "$repo/.specify/extensions/git/scripts/bash" "$repo/.specify/shell" || return 1
    cp "$GET_LAST_WORKTREE_SCRIPT" "$repo/.specify/extensions/git/scripts/bash/get-last-worktree.sh" || return 1
    cp "$GIT_COMMON_SCRIPT" "$repo/.specify/extensions/git/scripts/bash/git-common.sh" || return 1
    cp "$SELECT_WORKTREE_SCRIPT" "$repo/.specify/shell/select-worktree.sh" || return 1
    chmod +x \
        "$repo/.specify/extensions/git/scripts/bash/get-last-worktree.sh" \
        "$repo/.specify/shell/select-worktree.sh"
}

install_git_porcelain_shim() {
    local shim_dir="$1"

    mkdir -p "$shim_dir" || return 1
    cat > "$shim_dir/git" <<'SH'
#!/usr/bin/env bash
is_worktree=false
is_list=false
has_z=false
for argument in "$@"; do
    case "$argument" in
        worktree) is_worktree=true ;;
        list) is_list=true ;;
        -z) has_z=true ;;
    esac
done

if $is_worktree && $is_list; then
    if [ "${SPECKIT_TEST_GIT_MODE:-}" = fail-list ]; then
        exit 42
    fi
    if $has_z; then
        exit 129
    fi
    if [ "${SPECKIT_TEST_GIT_MODE:-}" = records-file ]; then
        cat "$SPECKIT_TEST_GIT_RECORDS_FILE"
        exit $?
    fi
    if [ "${SPECKIT_TEST_GIT_MODE:-}" = no-z-with-records ]; then
        "$SPECKIT_TEST_REAL_GIT" "$@" || exit $?
        printf 'worktree %s\nHEAD %s\nbranch refs/heads/test/prunable\nprunable test fixture\n\n' \
            "$SPECKIT_TEST_PRUNABLE_PATH" "$SPECKIT_TEST_HEAD"
        printf 'worktree %s\nHEAD %s\nbranch refs/heads/test/incomplete\n' \
            "$SPECKIT_TEST_INCOMPLETE_PATH" "$SPECKIT_TEST_HEAD"
        exit 0
    fi
fi

exec "$SPECKIT_TEST_REAL_GIT" "$@"
SH
    chmod +x "$shim_dir/git"
}

install_number_reservation_git_shim() {
    local shim_dir="$1"

    mkdir -p "$shim_dir" || return 1
    cat > "$shim_dir/git" <<'SH'
#!/usr/bin/env bash
reservation_ref=""
if [ "${1:-}" = update-ref ]; then
    if [ "${2:-}" = -d ]; then
        reservation_ref="${3:-}"
    else
        reservation_ref="${2:-}"
    fi
    case "$reservation_ref" in
        refs/speckit/number-reservations/v1/*)
            if [ -n "${SPECKIT_TEST_RESERVATION_LOG:-}" ]; then
                printf '%s\n' "$*" >> "$SPECKIT_TEST_RESERVATION_LOG"
            fi
            if [ "${SPECKIT_TEST_GIT_MODE:-}" = fail-reservation-create ] \
                && [ "${2:-}" != -d ]; then
                printf 'forced unrelated update-ref failure\n' >&2
                exit 73
            fi
            if [ "${SPECKIT_TEST_GIT_MODE:-}" = released-reservation-interleaving ]; then
                case "$reservation_ref" in
                    */002)
                        if [ "${SPECKIT_TEST_CREATOR_ROLE:-}" = delayed ] \
                            && [ "${2:-}" != -d ]; then
                            attempts=0
                            while [ ! -e "$SPECKIT_TEST_RELEASE_MARKER" ]; do
                                attempts=$((attempts + 1))
                                if [ "$attempts" -ge 3000 ]; then
                                    printf 'timed out waiting for publisher reservation release\n' >&2
                                    exit 124
                                fi
                                sleep 0.01
                            done
                        elif [ "${SPECKIT_TEST_CREATOR_ROLE:-}" = publisher ] \
                            && [ "${2:-}" = -d ]; then
                            "$SPECKIT_TEST_REAL_GIT" "$@" || exit $?
                            : > "$SPECKIT_TEST_RELEASE_MARKER"
                            exit 0
                        fi
                        ;;
                esac
            fi
            ;;
    esac
fi

uses_snapshot_barrier=false
case "${SPECKIT_TEST_GIT_MODE:-}" in
    branch-snapshot-barrier|released-reservation-interleaving)
        uses_snapshot_barrier=true
        ;;
esac
if $uses_snapshot_barrier && [ "${1:-}" = branch ] && [ "${2:-}" = -a ]; then
    snapshot="$SPECKIT_TEST_BARRIER_DIR/snapshots/$SPECKIT_TEST_CREATOR_ID"
    arrivals="$SPECKIT_TEST_BARRIER_DIR/arrivals"
    release="$SPECKIT_TEST_BARRIER_DIR/release"
    if [ -d "$arrivals/$SPECKIT_TEST_CREATOR_ID" ]; then
        exec "$SPECKIT_TEST_REAL_GIT" "$@"
    fi
    "$SPECKIT_TEST_REAL_GIT" "$@" > "$snapshot" || exit $?
    mkdir "$arrivals/$SPECKIT_TEST_CREATOR_ID" || exit $?

    attempts=0
    while [ ! -e "$release" ]; do
        arrival_count=0
        for arrival in "$arrivals"/*; do
            [ -d "$arrival" ] || continue
            arrival_count=$((arrival_count + 1))
        done
        if [ "$arrival_count" -eq "$SPECKIT_TEST_CREATOR_COUNT" ]; then
            : > "$release"
            break
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 3000 ]; then
            printf 'timed out waiting for creator barrier: %s/%s\n' \
                "$arrival_count" "$SPECKIT_TEST_CREATOR_COUNT" >&2
            exit 124
        fi
        sleep 0.01
    done

    cat "$snapshot"
    exit $?
fi

exec "$SPECKIT_TEST_REAL_GIT" "$@"
SH
    chmod +x "$shim_dir/git"
}

number_reservation_refs() {
    GIT_MASTER=1 "$REAL_GIT" -C "$1" for-each-ref \
        --format='%(refname)' refs/speckit/number-reservations/v1
}

write_worktree_state() {
    local state_file="$1"
    local worktree_path="$2"
    local branch_name="$3"

    python3 - "$state_file" "$worktree_path" "$branch_name" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump({"WORKTREE_PATH": sys.argv[2], "BRANCH_NAME": sys.argv[3]}, fh)
PY
}

test_parent_root_excludes_primary_checkout() {
    local parent="$FIXTURE_ROOT/parent-root"
    local repo="$parent/main-checkout"
    local linked_path="$parent/linked-worktree"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ..'
    local get_last_output list_output selected_path

    # Given: the configured root contains both the primary checkout and a linked worktree.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    git -C "$repo" branch feature/parent-root || return 1
    git -C "$repo" worktree add -q "$linked_path" feature/parent-root || return 1
    touch -t 202001010101 "$linked_path" || return 1
    touch -t 202001010102 "$repo" || return 1
    rm -f "$repo/.git/speckit-last-worktree.json"

    # When: discovery ranks registered worktrees under the broad parent root.
    get_last_output="$(cd "$repo" && bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json)" || return 1
    list_output="$(cd "$repo" && bash .specify/shell/select-worktree.sh --list)" || return 1
    selected_path="$(cd "$repo" && bash .specify/shell/select-worktree.sh --path </dev/null)" || return 1

    # Then: the canonical primary checkout is never returned or listed.
    assert_equal "$linked_path" "$(json_field "$get_last_output" WORKTREE_PATH)" 'parent-root get-last path' || return 1
    assert_equal 'feature/parent-root' "$(json_field "$get_last_output" BRANCH_NAME)" 'parent-root get-last branch' || return 1
    assert_equal "$linked_path" "$selected_path" 'parent-root selected path' || return 1
    if printf '%s\n' "$list_output" | grep -Fq "$repo"; then
        printf 'assertion failed: parent-root selection listed the primary checkout\n%s\n' "$list_output" >&2
        return 1
    fi
}

test_state_requires_registered_in_root_worktree() {
    local repo="$FIXTURE_ROOT/state-validation"
    local root="$FIXTURE_ROOT/state-validation-worktrees"
    local registered_path="$root/team/012-registered"
    local unregistered_path="$root/unregistered-existing"
    local outside_path="$FIXTURE_ROOT/state-outside-existing"
    local state_file="$repo/.git/speckit-last-worktree.json"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../state-validation-worktrees'
    local get_last_output

    # Given: one registered in-root worktree plus existing forged in-root and outside paths.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    git -C "$repo" branch team/012-registered || return 1
    git -C "$repo" worktree add -q "$registered_path" team/012-registered || return 1
    mkdir -p "$unregistered_path" "$outside_path" || return 1

    # When: state names the registered path but forges its branch metadata.
    write_worktree_state "$state_file" "$registered_path" 'forged/state-branch' || return 1
    get_last_output="$(cd "$repo" && bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json)" || return 1

    # Then: the path is accepted through its registered record and its real branch is returned.
    assert_equal "$registered_path" "$(json_field "$get_last_output" WORKTREE_PATH)" 'registered state path' || return 1
    assert_equal 'team/012-registered' "$(json_field "$get_last_output" BRANCH_NAME)" 'registered state branch' || return 1
    assert_equal 'state_file' "$(json_field "$get_last_output" SOURCE)" 'registered state source' || return 1

    # When: state instead names an existing unregistered in-root directory.
    write_worktree_state "$state_file" "$unregistered_path" 'forged/unregistered' || return 1
    get_last_output="$(cd "$repo" && bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json)" || return 1

    # Then: stale state is ignored in favor of the registered in-root candidate.
    assert_equal "$registered_path" "$(json_field "$get_last_output" WORKTREE_PATH)" 'unregistered state fallback path' || return 1
    assert_equal 'team/012-registered' "$(json_field "$get_last_output" BRANCH_NAME)" 'unregistered state fallback branch' || return 1
    assert_equal 'worktree_root_fallback' "$(json_field "$get_last_output" SOURCE)" 'unregistered state fallback source' || return 1

    # When: state names an existing directory outside the configured root.
    write_worktree_state "$state_file" "$outside_path" 'forged/outside' || return 1
    get_last_output="$(cd "$repo" && bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json)" || return 1

    # Then: outside-root state is also ignored in favor of the registered record.
    assert_equal "$registered_path" "$(json_field "$get_last_output" WORKTREE_PATH)" 'outside state fallback path' || return 1
    assert_equal 'team/012-registered' "$(json_field "$get_last_output" BRANCH_NAME)" 'outside state fallback branch' || return 1
    assert_equal 'worktree_root_fallback' "$(json_field "$get_last_output" SOURCE)" 'outside state fallback source' || return 1
}

test_malformed_and_symlinked_state_fall_back_safely() {
    local repo="$FIXTURE_ROOT/state-file-safety"
    local root="$FIXTURE_ROOT/state-file-safety-worktrees"
    local registered_path="$root/014-registered"
    local state_file="$repo/.git/speckit-last-worktree.json"
    local sentinel="$FIXTURE_ROOT/state-file-sentinel"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../state-file-safety-worktrees'
    local output sentinel_before

    # Given: discovery has a registered candidate and the regular state file is malformed JSON.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    git -C "$repo" branch feature/014-registered || return 1
    git -C "$repo" worktree add -q "$registered_path" feature/014-registered || return 1
    printf '{malformed json\n' > "$state_file" || return 1

    # When: get-last reads the malformed regular state file.
    output="$(cd "$repo" && bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json)" || return 1

    # Then: parse failure is ignored and the registered worktree wins.
    assert_equal "$registered_path" "$(json_field "$output" WORKTREE_PATH)" 'malformed state fallback path' || return 1
    assert_equal 'worktree_root_fallback' "$(json_field "$output" SOURCE)" 'malformed state fallback source' || return 1

    # Given: the same state pathname is a symlink to external sentinel bytes.
    rm -f "$state_file" || return 1
    printf 'external sentinel bytes\n' > "$sentinel" || return 1
    sentinel_before="$(<"$sentinel")"
    ln -s "$sentinel" "$state_file" || return 1

    # When: get-last encounters the symlinked state file.
    output="$(cd "$repo" && bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json)" || return 1

    # Then: it ignores the symlink and leaves its external target unchanged.
    assert_equal "$registered_path" "$(json_field "$output" WORKTREE_PATH)" 'symlinked state fallback path' || return 1
    assert_equal 'worktree_root_fallback' "$(json_field "$output" SOURCE)" 'symlinked state fallback source' || return 1
    assert_equal "$sentinel_before" "$(<"$sentinel")" 'symlinked state external sentinel bytes'
}

test_json_output_requires_encoder() {
    local repo="$FIXTURE_ROOT/json-encoder"
    local root="$FIXTURE_ROOT/json-encoder-worktrees"
    local linked_path="$root/013-json-encoder"
    local restricted_bin="$FIXTURE_ROOT/no-json-tools-bin"
    local stdout_file="$FIXTURE_ROOT/no-json-tools.stdout"
    local stderr_file="$FIXTURE_ROOT/no-json-tools.stderr"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../json-encoder-worktrees'
    local tool tool_path

    # Given: discovery can find a registered worktree but PATH has neither jq nor Python.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    git -C "$repo" branch feature/json-encoder || return 1
    git -C "$repo" worktree add -q "$linked_path" feature/json-encoder || return 1
    rm -f "$repo/.git/speckit-last-worktree.json"
    mkdir -p "$restricted_bin" || return 1
    for tool in awk basename dirname git rm stat; do
        tool_path="$(command -v "$tool")" || return 1
        ln -s "$tool_path" "$restricted_bin/$tool" || return 1
    done

    # When: JSON mode cannot invoke either supported encoder.
    if (cd "$repo" && PATH="$restricted_bin" "$BASH" .specify/extensions/git/scripts/bash/get-last-worktree.sh --json >"$stdout_file" 2>"$stderr_file"); then
        printf 'assertion failed: JSON mode succeeded without jq or Python\n' >&2
        return 1
    fi

    # Then: it fails closed with a clear error and no raw JSON payload.
    if ! grep -Fq 'JSON output requires jq or python3' "$stderr_file"; then
        printf 'assertion failed: JSON encoder failure was unclear\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if [ -s "$stdout_file" ]; then
        printf 'assertion failed: JSON mode emitted an unencoded payload without an encoder\n%s\n' "$(<"$stdout_file")" >&2
        return 1
    fi
}

test_registered_namespaced_worktree_discovery() {
    local repo="$FIXTURE_ROOT/discovery"
    local root="$FIXTURE_ROOT/discovery-worktrees"
    local direct_path="$root/007 direct"
    local nested_path="$root/feature/team/008 nested"
    local tab_path="$root/"$'009\ttab'
    local detached_path="$root/detached worktree"
    local newline_path="$root/"$'011\t"quote\\backslash-é\nnewline'
    local decoy_path="$root/decoy-newer"
    local prunable_path="$root/prunable-newest"
    local incomplete_path="$root/incomplete-newest"
    local outside_path="$FIXTURE_ROOT/registered outside root"
    local shim_dir="$FIXTURE_ROOT/discovery-git-shim"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../discovery-worktrees'
    local get_last_output list_output selected_path expected_path expected_branch
    local get_last_stdout list_stdout select_stdout
    local newline_supported=false

    # Given: discovery protocol parsing is centralized and remains Bash 3.2-compatible.
    if grep -Eq 'find .*-(maxdepth|mindepth)|sort .*-[^[:space:]]*z|(^|[[:space:]])(local|declare)[[:space:]]+-n' \
        "$GIT_COMMON_SCRIPT" "$GET_LAST_WORKTREE_SCRIPT" "$SELECT_WORKTREE_SCRIPT"; then
        printf 'assertion failed: discovery scripts use GNU-only or post-Bash-3.2 features\n' >&2
        return 1
    fi
    if ! grep -Fq 'worktree list --porcelain -z' "$GIT_COMMON_SCRIPT"; then
        printf 'assertion failed: shared Git helper does not prefer NUL porcelain\n' >&2
        return 1
    fi
    for discovery_script in "$FEATURE_SCRIPT" "$GET_LAST_WORKTREE_SCRIPT" "$SELECT_WORKTREE_SCRIPT"; do
        if ! grep -Fq 'git-common.sh' "$discovery_script" \
            || grep -Fq 'worktree list --porcelain' "$discovery_script" \
            || grep -Fq "IFS=\$'\\t'" "$discovery_script"; then
            printf 'assertion failed: discovery script does not delegate to the shared porcelain loader: %s\n' "$discovery_script" >&2
            return 1
        fi
    done

    # Given: registered paths contain spaces, a tab, a nested namespace, and detached state.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    git -C "$repo" branch 007-direct || return 1
    git -C "$repo" branch feature/team/008-nested || return 1
    git -C "$repo" branch ops/009-tab || return 1
    git -C "$repo" branch outside/099-decoy || return 1
    git -C "$repo" worktree add -q "$direct_path" 007-direct || return 1
    git -C "$repo" worktree add -q "$nested_path" feature/team/008-nested || return 1
    git -C "$repo" worktree add -q "$tab_path" ops/009-tab || return 1
    git -C "$repo" worktree add --detach -q "$detached_path" HEAD || return 1
    git -C "$repo" worktree add -q "$outside_path" outside/099-decoy || return 1

    # Given: a newline-containing registered path when the host filesystem supports it.
    git -C "$repo" branch qa/011-newline || return 1
    if git -C "$repo" worktree add -q "$newline_path" qa/011-newline >/dev/null 2>&1; then
        newline_supported=true
    fi

    touch -t 202001010101 "$direct_path" || return 1
    touch -t 202001010102 "$nested_path" || return 1
    touch -t 202001010103 "$tab_path" || return 1
    touch -t 202001010104 "$detached_path" || return 1
    touch -t 202001010106 "$outside_path" || return 1
    if $newline_supported; then
        touch -t 202001010105 "$newline_path" || return 1
        GIT_MASTER=1 git -C "$repo" worktree lock --reason 'active special-path fixture' "$newline_path" || return 1
        expected_path="$newline_path"
        expected_branch='qa/011-newline'
    else
        GIT_MASTER=1 git -C "$repo" worktree lock --reason 'active detached fixture' "$detached_path" || return 1
        expected_path="$detached_path"
        expected_branch='(detached)'
    fi
    mkdir -p "$decoy_path" || return 1
    mkdir -p "$prunable_path" "$incomplete_path" || return 1
    touch -t 202001010107 "$prunable_path" || return 1
    touch -t 202001010108 "$incomplete_path" || return 1
    install_git_porcelain_shim "$shim_dir" || return 1
    rm -f "$repo/.git/speckit-last-worktree.json"

    # When: modern Git is forced through line porcelain with a valid prunable record followed by an unterminated record.
    get_last_stdout="$FIXTURE_ROOT/no-z-with-records-get-last.stdout"
    list_stdout="$FIXTURE_ROOT/no-z-with-records-list.stdout"
    select_stdout="$FIXTURE_ROOT/no-z-with-records-select.stdout"
    if (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=no-z-with-records SPECKIT_TEST_PRUNABLE_PATH="$prunable_path" \
        SPECKIT_TEST_INCOMPLETE_PATH="$incomplete_path" SPECKIT_TEST_HEAD="$(GIT_MASTER=1 git -C "$repo" rev-parse HEAD)" \
        bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json >"$get_last_stdout"); then
        printf 'assertion failed: get-last accepted an unterminated line record\n' >&2
        return 1
    fi
    if (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=no-z-with-records SPECKIT_TEST_PRUNABLE_PATH="$prunable_path" \
        SPECKIT_TEST_INCOMPLETE_PATH="$incomplete_path" SPECKIT_TEST_HEAD="$(GIT_MASTER=1 git -C "$repo" rev-parse HEAD)" \
        bash .specify/shell/select-worktree.sh --list >"$list_stdout"); then
        printf 'assertion failed: selector list accepted an unterminated line record\n' >&2
        return 1
    fi
    if (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=no-z-with-records SPECKIT_TEST_PRUNABLE_PATH="$prunable_path" \
        SPECKIT_TEST_INCOMPLETE_PATH="$incomplete_path" SPECKIT_TEST_HEAD="$(GIT_MASTER=1 git -C "$repo" rev-parse HEAD)" \
        bash .specify/shell/select-worktree.sh --path </dev/null >"$select_stdout"); then
        printf 'assertion failed: selector path accepted an unterminated line record\n' >&2
        return 1
    fi
    # Then: every consumer fails closed without success output, despite the preceding valid prunable record.
    for stdout_file in "$get_last_stdout" "$list_stdout" "$select_stdout"; do
        if [ -s "$stdout_file" ]; then
            printf 'assertion failed: truncated line porcelain emitted success output: %s\n%s\n' \
                "$stdout_file" "$(<"$stdout_file")" >&2
            return 1
        fi
    done
}

test_line_porcelain_allow_existing_reuses_special_path() {
    local repo="$FIXTURE_ROOT/line-reuse"
    local root="$FIXTURE_ROOT/"$'line-reuse-\t"quote\\backslash-é\nworktrees'
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../unused-line-reuse-worktrees'
    local stderr_file="$FIXTURE_ROOT/line-reuse.stderr"
    local shim_dir="$FIXTURE_ROOT/line-reuse-git-shim"
    local branch='feature/021-line-reuse'
    local expected_path="$root/$branch"
    local output reused_path

    # Given: a feature branch is already checked out at a path containing line-protocol special bytes.
    initialize_fixture "$repo" "$config" || return 1
    GIT_MASTER=1 git -C "$repo" branch "$branch" || return 1
    mkdir -p "$(dirname "$expected_path")" || return 1
    GIT_MASTER=1 git -C "$repo" worktree add -q "$expected_path" "$branch" || return 1
    install_git_porcelain_shim "$shim_dir" || return 1

    # When: allow-existing discovery is forced to retry without -z.
    if ! output="$(cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=no-z SPECKIT_GIT_WORKTREE_ROOT="$root" GIT_BRANCH_NAME="$branch" \
        bash "$FEATURE_SCRIPT" --json --allow-existing-branch ignored 2>"$stderr_file")"; then
        printf 'line-porcelain allow-existing failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi

    # Then: the exact registered path is reused without trying to create it again.
    reused_path="$(json_field "$output" WORKTREE_PATH)" || return 1
    assert_equal "$expected_path" "$reused_path" 'line-porcelain allow-existing path'
}

test_line_porcelain_head_collision_does_not_fabricate_a_worktree() {
    local repo="$FIXTURE_ROOT/line-head-collision"
    local root="$FIXTURE_ROOT/line-head-collision-worktrees"
    local branch='feature/023-head-collision'
    local head collision_prefix collision_path records_file shim_dir state_file
    local feature_stdout get_last_stdout select_stdout before_worktrees after_worktrees
    local feature_stderr get_last_stderr select_stderr
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../line-head-collision-worktrees'
    local scenario_failed=false

    # Given: a real worktree path contains a complete line that is indistinguishable from HEAD metadata.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    GIT_MASTER=1 git -C "$repo" branch "$branch" || return 1
    head="$(GIT_MASTER=1 git -C "$repo" rev-parse HEAD)" || return 1
    collision_prefix="$root/collision-prefix"
    collision_path="$collision_prefix"$'\n'"HEAD $head"$'\n''collision-tail'
    mkdir -p "$collision_prefix" || return 1
    GIT_MASTER=1 git -C "$repo" worktree add -q "$collision_path" "$branch" || return 1
    records_file="$FIXTURE_ROOT/line-head-collision.records"
    printf 'worktree %s\nHEAD %s\nbranch refs/heads/%s\n\n' \
        "$collision_path" "$head" "$branch" > "$records_file" || return 1
    shim_dir="$FIXTURE_ROOT/line-head-collision-git-shim"
    install_git_porcelain_shim "$shim_dir" || return 1
    state_file="$repo/.git/speckit-last-worktree.json"
    feature_stdout="$FIXTURE_ROOT/line-head-collision-feature.stdout"
    get_last_stdout="$FIXTURE_ROOT/line-head-collision-get-last.stdout"
    select_stdout="$FIXTURE_ROOT/line-head-collision-select.stdout"
    feature_stderr="$FIXTURE_ROOT/line-head-collision-feature.stderr"
    get_last_stderr="$FIXTURE_ROOT/line-head-collision-get-last.stderr"
    select_stderr="$FIXTURE_ROOT/line-head-collision-select.stderr"
    before_worktrees="$(GIT_MASTER=1 "$REAL_GIT" -C "$repo" worktree list --porcelain)" || return 1

    # When: every Bash consumer is forced through the ambiguous legacy record.
    if (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        SPECKIT_GIT_WORKTREE_ROOT="$root" GIT_BRANCH_NAME="$branch" \
        bash "$FEATURE_SCRIPT" --json --allow-existing-branch ignored >"$feature_stdout" 2>"$feature_stderr"); then
        printf 'assertion failed: creator accepted a line-porcelain path containing a structural HEAD line\n' >&2
        scenario_failed=true
    fi
    if (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json >"$get_last_stdout" 2>"$get_last_stderr"); then
        printf 'assertion failed: get-last accepted a line-porcelain path containing a structural HEAD line\n' >&2
        scenario_failed=true
    fi
    if (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        bash .specify/shell/select-worktree.sh --path </dev/null >"$select_stdout" 2>"$select_stderr"); then
        printf 'assertion failed: selector accepted a line-porcelain path containing a structural HEAD line\n' >&2
        scenario_failed=true
    fi

    # Then: ambiguity fails closed without success output or repository mutation.
    for stdout_file in "$feature_stdout" "$get_last_stdout" "$select_stdout"; do
        if [ -s "$stdout_file" ]; then
            printf 'assertion failed: ambiguous line porcelain emitted success output: %s\n%s\n' \
                "$stdout_file" "$(<"$stdout_file")" >&2
            scenario_failed=true
        fi
    done
    if [ -e "$state_file" ]; then
        printf 'assertion failed: ambiguous line porcelain created worktree handoff state\n' >&2
        scenario_failed=true
    fi
    after_worktrees="$(GIT_MASTER=1 "$REAL_GIT" -C "$repo" worktree list --porcelain)" || return 1
    if [ "$before_worktrees" != "$after_worktrees" ]; then
        printf 'assertion failed: ambiguous line porcelain mutated registered worktrees\n' >&2
        scenario_failed=true
    fi
    [ "$scenario_failed" = false ]
}

test_line_porcelain_ordinary_newline_path_still_round_trips() {
    local repo="$FIXTURE_ROOT/line-ordinary-newline"
    local root="$FIXTURE_ROOT/line-ordinary-newline-worktrees"
    local branch='feature/024-ordinary-newline'
    local newline_path head records_file shim_dir feature_output get_last_output selected_path
    local stderr_file="$FIXTURE_ROOT/line-ordinary-newline.stderr"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../line-ordinary-newline-worktrees'

    # Given: a registered path has a newline, but no path line impersonates structural metadata.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    GIT_MASTER=1 git -C "$repo" branch "$branch" || return 1
    newline_path="$root/ordinary-prefix"$'\n''ordinary-tail'
    GIT_MASTER=1 git -C "$repo" worktree add -q "$newline_path" "$branch" || return 1
    head="$(GIT_MASTER=1 git -C "$repo" rev-parse HEAD)" || return 1
    records_file="$FIXTURE_ROOT/line-ordinary-newline.records"
    printf 'worktree %s\nHEAD %s\nbranch refs/heads/%s\n\n' \
        "$newline_path" "$head" "$branch" > "$records_file" || return 1
    shim_dir="$FIXTURE_ROOT/line-ordinary-newline-git-shim"
    install_git_porcelain_shim "$shim_dir" || return 1

    # When: creator, get-last, and selector consume the forced line record.
    feature_output="$(cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        SPECKIT_GIT_WORKTREE_ROOT="$root" GIT_BRANCH_NAME="$branch" \
        bash "$FEATURE_SCRIPT" --json --allow-existing-branch ignored 2>"$stderr_file")" || return 1
    get_last_output="$(cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json)" || return 1
    selected_path="$(cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        bash .specify/shell/select-worktree.sh --path </dev/null)" || return 1

    # Then: the exact ordinary newline path survives every consumer.
    assert_equal "$newline_path" "$(json_field "$feature_output" WORKTREE_PATH)" 'ordinary newline creator path' || return 1
    assert_equal "$newline_path" "$(json_field "$get_last_output" WORKTREE_PATH)" 'ordinary newline get-last path' || return 1
    assert_equal "$newline_path" "$selected_path" 'ordinary newline selected path'
}

test_line_porcelain_c_quoted_path_decodes_byte_exactly() {
    local repo="$FIXTURE_ROOT/line-c-quoted"
    local root="$FIXTURE_ROOT/line-c-quoted-worktrees"
    local branch='feature/029-c-quoted'
    local expected_path quoted_path head records_file shim_dir feature_output get_last_output selected_path
    local stderr_file="$FIXTURE_ROOT/line-c-quoted.stderr"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../line-c-quoted-worktrees'

    # Given: Git's line porcelain C-quotes every documented escape class in a registered path.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    GIT_MASTER=1 git -C "$repo" branch "$branch" || return 1
    expected_path="$root/"$'controls-\a\b\t\n\v\f\r-"quote\\backslash-\303\251-tail'
    GIT_MASTER=1 git -C "$repo" worktree add -q "$expected_path" "$branch" || return 1
    head="$(GIT_MASTER=1 git -C "$repo" rev-parse HEAD)" || return 1
    quoted_path="\"$root/"'controls-\a\b\t\n\v\f\r-\"quote\\backslash-\303\251-tail"'
    records_file="$FIXTURE_ROOT/line-c-quoted.records"
    printf 'worktree %s\nHEAD %s\nbranch refs/heads/%s\n\n' \
        "$quoted_path" "$head" "$branch" > "$records_file" || return 1
    shim_dir="$FIXTURE_ROOT/line-c-quoted-git-shim"
    install_git_porcelain_shim "$shim_dir" || return 1

    # When: all fallback consumers receive the same C-quoted line record.
    feature_output="$(cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        SPECKIT_GIT_WORKTREE_ROOT="$root" GIT_BRANCH_NAME="$branch" \
        bash "$FEATURE_SCRIPT" --json --allow-existing-branch ignored 2>"$stderr_file")" || return 1
    get_last_output="$(cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json)" || return 1
    selected_path="$(cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        bash .specify/shell/select-worktree.sh --path </dev/null)" || return 1

    # Then: controls, quotes, backslashes, and octal UTF-8 bytes decode to the registered path exactly.
    assert_equal "$expected_path" "$(json_field "$feature_output" WORKTREE_PATH)" 'C-quoted creator path' || return 1
    assert_equal "$expected_path" "$(json_field "$get_last_output" WORKTREE_PATH)" 'C-quoted get-last path' || return 1
    assert_equal "$expected_path" "$selected_path" 'C-quoted selected path'
}

test_line_porcelain_malformed_c_quotes_fail_closed() {
    local records_file="$FIXTURE_ROOT/line-malformed-c-quotes.records"
    local head='1111111111111111111111111111111111111111'
    local payload label index
    local -a malformed_payloads malformed_labels

    malformed_payloads=(
        '"/tmp/missing-closing-quote'
        '"/tmp/unescaped"interior"'
        '"/tmp/dangling\"'
        '"/tmp/unsupported\x41"'
        '"/tmp/nul\000byte"'
        '"/tmp/out-of-range\400byte"'
        '"/tmp/short-octal\12byte"'
    )
    malformed_labels=(
        'missing closing quote'
        'unescaped interior quote'
        'dangling escape'
        'unsupported escape'
        'NUL octal escape'
        'out-of-range octal escape'
        'short octal escape'
    )

    index=0
    while [ "$index" -lt "${#malformed_payloads[@]}" ]; do
        payload="${malformed_payloads[$index]}"
        label="${malformed_labels[$index]}"
        printf 'worktree %s\nHEAD %s\nbranch refs/heads/feature/malformed\n\n' \
            "$payload" "$head" > "$records_file" || return 1

        # The parser itself must reject malformed encodings instead of relying on later Git corroboration.
        if (
            source "$GIT_COMMON_SCRIPT"
            _GIT_WORKTREE_STAGED_PATHS=()
            _GIT_WORKTREE_STAGED_BRANCH_REFS=()
            _GIT_WORKTREE_STAGED_HEADS=()
            _GIT_WORKTREE_STAGED_DETACHED=()
            _git_worktree_parse_lines "$records_file"
        ); then
            printf 'assertion failed: line parser accepted malformed C quote: %s (%s)\n' "$label" "$payload" >&2
            return 1
        fi
        index=$((index + 1))
    done
}

test_line_porcelain_candidates_without_git_corroboration_are_not_worktrees() {
    local root="$FIXTURE_ROOT/corroboration-root"
    local repo="$root/main-checkout"
    local foreign_repo="$root/foreign-checkout"
    local ordinary_path="$root/ordinary-directory"
    local valid_path="$root/valid-worktree"
    local forged_head_path="$root/forged-head-worktree"
    local forged_branch_path="$root/forged-branch-worktree"
    local hidden_target_path="$root/hidden-target-worktree"
    local valid_branch='feature/025-valid'
    local forged_head_branch='feature/026-forged-head'
    local actual_forged_branch='feature/027-actual-branch'
    local target_branch='feature/028-forged-branch'
    local head foreign_head forged_branch_head records_file shim_dir state_file
    local expected_list get_last_stdout list_stdout feature_stdout feature_stderr before_worktrees after_worktrees
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ..'
    local scenario_failed=false

    # Given: one valid record is mixed with directory, foreign, primary, and forged Git candidates.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    initialize_fixture "$foreign_repo" $'checkout_mode: worktree\nbase_branch: main' || return 1
    mkdir -p "$ordinary_path" || return 1
    GIT_MASTER=1 git -C "$repo" branch "$valid_branch" || return 1
    GIT_MASTER=1 git -C "$repo" branch "$forged_head_branch" || return 1
    GIT_MASTER=1 git -C "$repo" branch "$actual_forged_branch" || return 1
    GIT_MASTER=1 git -C "$repo" branch "$target_branch" || return 1
    GIT_MASTER=1 git -C "$repo" worktree add -q "$valid_path" "$valid_branch" || return 1
    GIT_MASTER=1 git -C "$repo" worktree add -q "$forged_head_path" "$forged_head_branch" || return 1
    GIT_MASTER=1 git -C "$repo" worktree add -q "$forged_branch_path" "$actual_forged_branch" || return 1
    GIT_MASTER=1 git -C "$repo" worktree add -q "$hidden_target_path" "$target_branch" || return 1
    head="$(GIT_MASTER=1 git -C "$repo" rev-parse HEAD)" || return 1
    foreign_head="$(GIT_MASTER=1 git -C "$foreign_repo" rev-parse HEAD)" || return 1
    forged_branch_head="$(GIT_MASTER=1 git -C "$forged_branch_path" rev-parse HEAD)" || return 1
    touch -t 202001010101 "$valid_path" || return 1
    touch -t 202001010102 "$forged_head_path" || return 1
    touch -t 202001010103 "$forged_branch_path" || return 1
    touch -t 202001010104 "$foreign_repo" || return 1
    touch -t 202001010105 "$ordinary_path" || return 1
    records_file="$FIXTURE_ROOT/corroboration.records"
    {
        printf 'worktree %s\nHEAD %s\nbranch refs/heads/%s\n\n' "$valid_path" "$head" "$valid_branch"
        printf 'worktree %s\nHEAD %s\nbranch refs/heads/feature/ordinary-forgery\n\n' "$ordinary_path" "$head"
        printf 'worktree %s\nHEAD %s\nbranch refs/heads/main\n\n' "$foreign_repo" "$foreign_head"
        printf 'worktree %s\nHEAD %s\nbranch refs/heads/main\n\n' "$repo" "$head"
        printf 'worktree %s\nHEAD %040d\nbranch refs/heads/%s\n\n' "$forged_head_path" 0 "$forged_head_branch"
        printf 'worktree %s\nHEAD %s\nbranch refs/heads/%s\n\n' "$forged_branch_path" "$forged_branch_head" "$target_branch"
    } > "$records_file" || return 1
    shim_dir="$FIXTURE_ROOT/corroboration-git-shim"
    install_git_porcelain_shim "$shim_dir" || return 1
    state_file="$repo/.git/speckit-last-worktree.json"
    get_last_stdout="$FIXTURE_ROOT/corroboration-get-last.stdout"
    list_stdout="$FIXTURE_ROOT/corroboration-list.stdout"
    feature_stdout="$FIXTURE_ROOT/corroboration-feature.stdout"
    feature_stderr="$FIXTURE_ROOT/corroboration-feature.stderr"
    before_worktrees="$(GIT_MASTER=1 "$REAL_GIT" -C "$repo" worktree list --porcelain)" || return 1

    # When: discovery and allow-existing consume parser candidates requiring live Git proof.
    if ! (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json >"$get_last_stdout"); then
        printf 'assertion failed: get-last rejected the corroborated control worktree\n' >&2
        scenario_failed=true
    fi
    if ! (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        bash .specify/shell/select-worktree.sh --list >"$list_stdout"); then
        printf 'assertion failed: selector rejected the corroborated control worktree\n' >&2
        scenario_failed=true
    fi
    if (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        SPECKIT_TEST_GIT_MODE=records-file SPECKIT_TEST_GIT_RECORDS_FILE="$records_file" \
        SPECKIT_GIT_WORKTREE_ROOT="$root" GIT_BRANCH_NAME="$target_branch" \
        bash "$FEATURE_SCRIPT" --json --allow-existing-branch ignored >"$feature_stdout" 2>"$feature_stderr"); then
        printf 'assertion failed: creator accepted forged branch metadata for another worktree\n' >&2
        scenario_failed=true
    fi

    # Then: only the fully corroborated candidate is discoverable and failed creation leaves no trace.
    if [ -s "$get_last_stdout" ]; then
        if ! assert_equal "$valid_path" "$(json_field "$(<"$get_last_stdout")" WORKTREE_PATH)" 'corroborated get-last path'; then
            scenario_failed=true
        fi
    fi
    expected_list="$(printf '1. %s [default]\n   %s' "$valid_branch" "$valid_path")"
    if ! assert_equal "$expected_list" "$(<"$list_stdout")" 'corroborated selector candidates'; then
        scenario_failed=true
    fi
    if [ -s "$feature_stdout" ]; then
        printf 'assertion failed: forged branch candidate emitted creator success output\n%s\n' "$(<"$feature_stdout")" >&2
        scenario_failed=true
    fi
    if [ -e "$state_file" ]; then
        printf 'assertion failed: forged branch candidate created worktree handoff state\n' >&2
        scenario_failed=true
    fi
    after_worktrees="$(GIT_MASTER=1 "$REAL_GIT" -C "$repo" worktree list --porcelain)" || return 1
    if [ "$before_worktrees" != "$after_worktrees" ]; then
        printf 'assertion failed: uncorroborated candidate handling mutated registered worktrees\n' >&2
        scenario_failed=true
    fi
    [ "$scenario_failed" = false ]
}

test_discovery_failure_is_not_reported_as_zero_records() {
    local repo="$FIXTURE_ROOT/discovery-failure"
    local root="$FIXTURE_ROOT/discovery-failure-worktrees"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../discovery-failure-worktrees'
    local shim_dir="$FIXTURE_ROOT/discovery-failure-git-shim"
    local get_last_stderr="$FIXTURE_ROOT/discovery-failure-get-last.stderr"
    local select_stderr="$FIXTURE_ROOT/discovery-failure-select.stderr"
    local feature_stderr="$FIXTURE_ROOT/discovery-failure-feature.stderr"
    local branch='feature/022-load-failure'

    # Given: Git itself is available, but both worktree porcelain commands fail.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    install_git_porcelain_shim "$shim_dir" || return 1
    mkdir -p "$root" || return 1
    GIT_MASTER=1 git -C "$repo" branch "$branch" || return 1

    # When: each Bash consumer attempts discovery.
    if (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" SPECKIT_TEST_GIT_MODE=fail-list \
        bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json >/dev/null 2>"$get_last_stderr"); then
        printf 'assertion failed: get-last succeeded after Git discovery failure\n' >&2
        return 1
    fi
    if (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" SPECKIT_TEST_GIT_MODE=fail-list \
        bash .specify/shell/select-worktree.sh --list >/dev/null 2>"$select_stderr"); then
        printf 'assertion failed: select succeeded after Git discovery failure\n' >&2
        return 1
    fi
    if (cd "$repo" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" SPECKIT_TEST_GIT_MODE=fail-list \
        SPECKIT_GIT_WORKTREE_ROOT="$root" GIT_BRANCH_NAME="$branch" \
        bash "$FEATURE_SCRIPT" --json --allow-existing-branch ignored >/dev/null 2>"$feature_stderr"); then
        printf 'assertion failed: feature creation succeeded after Git discovery failure\n' >&2
        return 1
    fi

    # Then: every command identifies discovery failure rather than claiming there are no records.
    for stderr_file in "$get_last_stderr" "$select_stderr" "$feature_stderr"; do
        if ! grep -Fq 'Failed to list Git worktrees' "$stderr_file"; then
            printf 'assertion failed: discovery failure diagnostic was lost: %s\n%s\n' "$stderr_file" "$(<"$stderr_file")" >&2
            return 1
        fi
    done
}

test_fallback_root_ignores_decoy_directories() {
    local repo="$FIXTURE_ROOT/fallback-root"
    local decoy_root="$repo/worktrees"
    local registered_root="$repo/.worktrees"
    local registered_path="$registered_root/team/009-real"
    local config=$'checkout_mode: worktree\nbase_branch: main'
    local get_last_output list_output

    # Given: the first legacy root contains only a decoy and the second has a registered worktree.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    mkdir -p "$decoy_root/newer-decoy" || return 1
    git -C "$repo" branch team/009-real || return 1
    git -C "$repo" worktree add -q "$registered_path" team/009-real || return 1
    rm -f "$repo/.git/speckit-last-worktree.json"

    # When: discovery resolves a legacy worktree root.
    get_last_output="$(cd "$repo" && bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json)" || return 1
    list_output="$(cd "$repo" && bash .specify/shell/select-worktree.sh --list)" || return 1

    # Then: a decoy-only directory cannot win root detection.
    assert_equal "$registered_path" "$(json_field "$get_last_output" WORKTREE_PATH)" 'fallback root registered path' || return 1
    if ! printf '%s\n' "$list_output" | grep -Fq '1. team/009-real [default]'; then
        printf 'assertion failed: fallback root list did not select the registered namespaced worktree\n%s\n' "$list_output" >&2
        return 1
    fi
    if printf '%s\n%s\n' "$get_last_output" "$list_output" | grep -Fq "$decoy_root/newer-decoy"; then
        printf 'assertion failed: fallback root discovery included a decoy\n' >&2
        return 1
    fi
}

test_explicit_decoy_only_root_reports_no_worktrees() {
    local repo="$FIXTURE_ROOT/explicit-decoy-only"
    local root="$FIXTURE_ROOT/explicit-decoy-only-worktrees"
    local stderr_file="$FIXTURE_ROOT/explicit-decoy-only.stderr"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../explicit-decoy-only-worktrees'

    # Given: an explicit existing worktree root contains only an unregistered decoy.
    initialize_fixture "$repo" "$config" || return 1
    install_discovery_scripts "$repo" || return 1
    mkdir -p "$root/unregistered decoy" || return 1

    # When: selection loads an empty registered-worktree array under nounset mode.
    if (cd "$repo" && bash .specify/shell/select-worktree.sh --list > /dev/null 2>"$stderr_file"); then
        printf 'assertion failed: select unexpectedly succeeded for a decoy-only explicit root\n' >&2
        return 1
    fi

    # Then: the command reports its intended domain error instead of an array runtime error.
    if ! grep -Fq "No Speckit worktrees found under: $root" "$stderr_file"; then
        printf 'assertion failed: select did not report the empty explicit root\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if grep -Fqi 'unbound variable' "$stderr_file"; then
        printf 'assertion failed: select exposed a Bash nounset error\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
}

test_concurrent_sequential_number_reservations() {
    local repo="$FIXTURE_ROOT/concurrent-numbering"
    local shim_dir="$FIXTURE_ROOT/concurrent-numbering-git-shim"
    local barrier_dir="$FIXTURE_ROOT/concurrent-numbering-barrier"
    local reservation_log="$FIXTURE_ROOT/concurrent-numbering-reservations.log"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../concurrent-numbering-worktrees\nbranch_prefix: feature/'
    local -a creator_names creator_pids output_files
    local creator_name creator_index creator_pid output_file stderr_file
    local branch worktree_path reservation_refs owner_oid_count
    local scenario_failed=false

    creator_names=(alpha bravo charlie delta echo foxtrot golf hotel)

    # Given: eight creators share one Git common directory and all observe only feature/001.
    initialize_fixture "$repo" "$config" || return 1
    GIT_MASTER=1 git -C "$repo" branch feature/001-existing || return 1
    install_number_reservation_git_shim "$shim_dir" || return 1
    mkdir -p "$barrier_dir/arrivals" "$barrier_dir/snapshots" || return 1
    : > "$reservation_log"

    # When: the Git shim releases every creator only after all eight branch snapshots exist.
    creator_index=0
    while [ "$creator_index" -lt "${#creator_names[@]}" ]; do
        creator_name="${creator_names[$creator_index]}"
        output_file="$FIXTURE_ROOT/concurrent-numbering-$creator_name.stdout"
        stderr_file="$FIXTURE_ROOT/concurrent-numbering-$creator_name.stderr"
        output_files+=("$output_file")
        (
            cd "$repo" || exit 1
            PATH="$shim_dir:$PATH" GIT_BRANCH_NAME= \
                SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
                SPECKIT_TEST_GIT_MODE=branch-snapshot-barrier \
                SPECKIT_TEST_BARRIER_DIR="$barrier_dir" \
                SPECKIT_TEST_CREATOR_ID="$creator_name" \
                SPECKIT_TEST_CREATOR_COUNT="${#creator_names[@]}" \
                SPECKIT_TEST_RESERVATION_LOG="$reservation_log" \
                bash "$FEATURE_SCRIPT" --json "Concurrent $creator_name" \
                > "$output_file" 2> "$stderr_file"
        ) &
        creator_pids+=("$!")
        creator_index=$((creator_index + 1))
    done

    creator_index=0
    while [ "$creator_index" -lt "${#creator_pids[@]}" ]; do
        creator_pid="${creator_pids[$creator_index]}"
        if ! wait "$creator_pid"; then
            creator_name="${creator_names[$creator_index]}"
            printf 'concurrent creator failed: %s\n%s\n' \
                "$creator_name" "$(<"$FIXTURE_ROOT/concurrent-numbering-$creator_name.stderr")" >&2
            scenario_failed=true
        fi
        creator_index=$((creator_index + 1))
    done
    if [ "$scenario_failed" = true ]; then
        return 1
    fi

    # Then: numbers are exactly 002..009, with distinct branches and valid worktrees.
    if ! python3 - "${output_files[@]}" <<'PY'
import json
import sys

payloads = []
for path in sys.argv[1:]:
    with open(path, "r", encoding="utf-8") as stream:
        payloads.append(json.load(stream))

numbers = sorted(payload["FEATURE_NUM"] for payload in payloads)
expected = ["%03d" % number for number in range(2, 10)]
if numbers != expected:
    print(
        "assertion failed: concurrent feature numbers "
        "(expected 002..009, got %s)" % ",".join(numbers),
        file=sys.stderr,
    )
    raise SystemExit(1)
if len({payload["BRANCH_NAME"] for payload in payloads}) != 8:
    print("assertion failed: concurrent branches were not distinct", file=sys.stderr)
    raise SystemExit(1)
if len({payload["WORKTREE_PATH"] for payload in payloads}) != 8:
    print("assertion failed: concurrent worktree paths were not distinct", file=sys.stderr)
    raise SystemExit(1)
PY
    then
        return 1
    fi

    for output_file in "${output_files[@]}"; do
        branch="$(json_field "$(<"$output_file")" BRANCH_NAME)" || return 1
        worktree_path="$(json_field "$(<"$output_file")" WORKTREE_PATH)" || return 1
        assert_worktree "$branch" "$worktree_path" || return 1
    done
    reservation_refs="$(number_reservation_refs "$repo")" || return 1
    assert_equal '' "$reservation_refs" 'reservation refs after concurrent success'
    owner_oid_count="$(awk '$1 == "update-ref" && $2 ~ /^refs\/speckit\/number-reservations\/v1\// { print $3 }' \
        "$reservation_log" | sort -u | wc -l | tr -d ' ')"
    assert_equal '8' "$owner_oid_count" 'distinct reservation owner OIDs for eight same-HEAD Bash creators'
}

test_released_reservation_stale_scan_retry() {
    local repo="$FIXTURE_ROOT/released-reservation-interleaving"
    local shim_dir="$FIXTURE_ROOT/released-reservation-git-shim"
    local barrier_dir="$FIXTURE_ROOT/released-reservation-barrier"
    local release_marker="$barrier_dir/publisher-released-002"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../released-reservation-worktrees\nbranch_prefix: feature/'
    local publisher_stdout="$FIXTURE_ROOT/released-reservation-publisher.stdout"
    local publisher_stderr="$FIXTURE_ROOT/released-reservation-publisher.stderr"
    local delayed_stdout="$FIXTURE_ROOT/released-reservation-delayed.stdout"
    local delayed_stderr="$FIXTURE_ROOT/released-reservation-delayed.stderr"
    local publisher_pid delayed_pid publisher_number delayed_number
    local publisher_branch delayed_branch publisher_worktree delayed_worktree

    # Given: both creators snapshot 002 before either can reserve it.
    initialize_fixture "$repo" "$config" || return 1
    GIT_MASTER=1 git -C "$repo" branch feature/001-existing || return 1
    install_number_reservation_git_shim "$shim_dir" || return 1
    mkdir -p "$barrier_dir/arrivals" "$barrier_dir/snapshots" || return 1

    # When: B's claim is blocked until A publishes its branch and releases reservation 002.
    (
        cd "$repo" || exit 1
        PATH="$shim_dir:$PATH" GIT_BRANCH_NAME= \
            SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
            SPECKIT_TEST_GIT_MODE=released-reservation-interleaving \
            SPECKIT_TEST_BARRIER_DIR="$barrier_dir" \
            SPECKIT_TEST_CREATOR_ID=publisher SPECKIT_TEST_CREATOR_COUNT=2 \
            SPECKIT_TEST_CREATOR_ROLE=publisher SPECKIT_TEST_RELEASE_MARKER="$release_marker" \
            bash "$FEATURE_SCRIPT" --json 'Published first' \
            > "$publisher_stdout" 2> "$publisher_stderr"
    ) &
    publisher_pid=$!
    (
        cd "$repo" || exit 1
        PATH="$shim_dir:$PATH" GIT_BRANCH_NAME= \
            SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
            SPECKIT_TEST_GIT_MODE=released-reservation-interleaving \
            SPECKIT_TEST_BARRIER_DIR="$barrier_dir" \
            SPECKIT_TEST_CREATOR_ID=delayed SPECKIT_TEST_CREATOR_COUNT=2 \
            SPECKIT_TEST_CREATOR_ROLE=delayed SPECKIT_TEST_RELEASE_MARKER="$release_marker" \
            bash "$FEATURE_SCRIPT" --json 'Delayed claim' \
            > "$delayed_stdout" 2> "$delayed_stderr"
    ) &
    delayed_pid=$!

    if ! wait "$publisher_pid"; then
        printf 'publisher creator failed: %s\n' "$(<"$publisher_stderr")" >&2
        wait "$delayed_pid" 2>/dev/null || true
        return 1
    fi
    if ! wait "$delayed_pid"; then
        printf 'delayed creator failed: %s\n' "$(<"$delayed_stderr")" >&2
        return 1
    fi

    # Then: B rejects its stale successful claim and advances to 003.
    publisher_number="$(json_field "$(<"$publisher_stdout")" FEATURE_NUM)" || return 1
    delayed_number="$(json_field "$(<"$delayed_stdout")" FEATURE_NUM)" || return 1
    if [ "$publisher_number" != 002 ] || [ "$delayed_number" != 003 ]; then
        printf 'assertion failed: released-reservation interleaving (expected publisher=002 delayed=003, got publisher=%s delayed=%s)\n' \
            "$publisher_number" "$delayed_number" >&2
        return 1
    fi
    if [ ! -e "$release_marker" ]; then
        printf 'assertion failed: publisher release marker was not created\n' >&2
        return 1
    fi
    publisher_branch="$(json_field "$(<"$publisher_stdout")" BRANCH_NAME)" || return 1
    delayed_branch="$(json_field "$(<"$delayed_stdout")" BRANCH_NAME)" || return 1
    publisher_worktree="$(json_field "$(<"$publisher_stdout")" WORKTREE_PATH)" || return 1
    delayed_worktree="$(json_field "$(<"$delayed_stdout")" WORKTREE_PATH)" || return 1
    assert_worktree "$publisher_branch" "$publisher_worktree" || return 1
    assert_worktree "$delayed_branch" "$delayed_worktree" || return 1
    assert_equal '' "$(number_reservation_refs "$repo")" 'reservation refs after released-reservation interleaving'
}

test_number_reservation_cleanup_and_update_failures() {
    local repo="$FIXTURE_ROOT/reservation-cleanup"
    local branch_repo="$FIXTURE_ROOT/reservation-cleanup-branch-mode"
    local shim_dir="$FIXTURE_ROOT/reservation-cleanup-git-shim"
    local config_file="$repo/.specify/extensions/git/git-config.yml"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../reservation-cleanup-worktrees\nbranch_prefix: team/'
    local stderr_file="$FIXTURE_ROOT/reservation-cleanup.stderr"
    local failure_log="$FIXTURE_ROOT/reservation-update-failure.log"
    local branch worktree_path

    # Given: a sequential namespace has one visible branch and no reservation refs.
    initialize_fixture "$repo" "$config" || return 1
    GIT_MASTER=1 git -C "$repo" branch team/001-existing || return 1
    install_number_reservation_git_shim "$shim_dir" || return 1

    # When: one creator succeeds and the next creator fails after number allocation.
    if ! invoke_feature "$repo" 'Successful reservation cleanup' "$stderr_file"; then
        printf 'successful reservation cleanup failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1
    assert_equal 'team/002-successful-reservation-cleanup' "$branch" 'successful reserved branch' || return 1
    assert_worktree "$branch" "$worktree_path" || return 1
    assert_equal '' "$(number_reservation_refs "$repo")" 'reservation refs after success' || return 1

    printf '%s\n' "$config" | sed 's/base_branch: main/base_branch: missing-base/' > "$config_file" || return 1
    if invoke_feature "$repo" 'Failed reservation cleanup' "$stderr_file"; then
        printf 'assertion failed: missing base creator unexpectedly succeeded\n' >&2
        return 1
    fi
    if ! grep -Fq "Base branch 'missing-base' does not exist" "$stderr_file"; then
        printf 'assertion failed: missing base failure was not exercised\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi

    # Then: both successful and failed creators leave no owned reservation ref.
    assert_equal '' "$(number_reservation_refs "$repo")" 'reservation refs after failed creator' || return 1
    if GIT_MASTER=1 "$REAL_GIT" -C "$repo" branch --list 'team/003-*' | grep -q .; then
        printf 'assertion failed: failed creator left a feature branch\n' >&2
        return 1
    fi

    printf '%s\n' "$config" > "$config_file" || return 1
    : > "$failure_log"
    if (cd "$repo" && PATH="$shim_dir:$PATH" GIT_BRANCH_NAME= \
        SPECKIT_TEST_REAL_GIT="$REAL_GIT" SPECKIT_TEST_GIT_MODE=fail-reservation-create \
        SPECKIT_TEST_RESERVATION_LOG="$failure_log" \
        bash "$FEATURE_SCRIPT" --json 'Fatal update ref failure' \
        >/dev/null 2>"$stderr_file"); then
        printf 'assertion failed: unrelated update-ref failure was ignored\n' >&2
        return 1
    fi
    if ! grep -Fq 'Failed to reserve sequential feature number' "$stderr_file"; then
        printf 'assertion failed: unrelated update-ref failure was not reported\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if [ ! -s "$failure_log" ]; then
        printf 'assertion failed: update-ref failure shim was not exercised\n' >&2
        return 1
    fi
    assert_equal '' "$(number_reservation_refs "$repo")" 'reservation refs after update-ref failure' || return 1

    initialize_fixture "$branch_repo" $'checkout_mode: branch\nbase_branch: main\nbranch_prefix: branch-mode/' || return 1
    GIT_MASTER=1 git -C "$branch_repo" branch branch-mode/001-existing || return 1
    if ! invoke_feature "$branch_repo" 'Branch checkout cleanup' "$stderr_file"; then
        printf 'branch-mode reservation cleanup failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    assert_equal 'branch-mode/002-branch-checkout-cleanup' "$branch" 'branch-mode reserved branch' || return 1
    assert_equal "$branch" "$(GIT_MASTER=1 "$REAL_GIT" -C "$branch_repo" branch --show-current)" 'branch-mode checkout' || return 1
    assert_equal '' "$(number_reservation_refs "$branch_repo")" 'reservation refs after checkout -b success'
}

test_orphan_reservation_gap_and_scope_isolation() {
    local repo="$FIXTURE_ROOT/orphan-reservation"
    local config_file="$repo/.specify/extensions/git/git-config.yml"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../orphan-reservation-worktrees\nbranch_prefix: feature/'
    local stderr_file="$FIXTURE_ROOT/orphan-reservation.stderr"
    local scope_hash head_oid orphan_ref branch worktree_path refs

    # Given: feature/002 is reserved by an unknown owner while feature/001 is visible.
    initialize_fixture "$repo" "$config" || return 1
    GIT_MASTER=1 git -C "$repo" branch feature/001-existing || return 1
    scope_hash="$(printf '%s' 'feature/' | GIT_MASTER=1 "$REAL_GIT" -C "$repo" hash-object --stdin)" || return 1
    head_oid="$(GIT_MASTER=1 "$REAL_GIT" -C "$repo" rev-parse HEAD)" || return 1
    orphan_ref="refs/speckit/number-reservations/v1/$scope_hash/002"
    GIT_MASTER=1 "$REAL_GIT" -C "$repo" update-ref "$orphan_ref" "$head_oid" "" || return 1

    # When: one same-scope creator and one unrelated-scope creator allocate numbers.
    if ! invoke_feature "$repo" 'Skip orphan reservation' "$stderr_file"; then
        printf 'orphan-gap creator failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1
    assert_equal 'feature/003-skip-orphan-reservation' "$branch" 'orphan-gap branch' || return 1
    assert_worktree "$branch" "$worktree_path" || return 1

    printf '%s\n' "$config" | sed 's/branch_prefix: feature\//branch_prefix: other\//' > "$config_file" || return 1
    if ! invoke_feature "$repo" 'Independent reservation scope' "$stderr_file"; then
        printf 'independent-scope creator failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1

    # Then: the orphan creates only a same-scope gap and remains untouched.
    assert_equal 'other/001-independent-reservation-scope' "$branch" 'independent-scope branch' || return 1
    assert_worktree "$branch" "$worktree_path" || return 1
    refs="$(number_reservation_refs "$repo")" || return 1
    assert_equal "$orphan_ref" "$refs" 'preserved orphan reservation'
}

test_non_reserving_numbering_paths() {
    local shim_dir="$FIXTURE_ROOT/non-reserving-git-shim"
    local reservation_log="$FIXTURE_ROOT/non-reserving-update-ref.log"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: ../non-reserving-worktrees'
    local stderr_file="$FIXTURE_ROOT/non-reserving.stderr"
    local repo output branch no_git_root no_git_script_dir

    install_number_reservation_git_shim "$shim_dir" || return 1
    : > "$reservation_log"

    # Given: Git records every attempted write to the reservation namespace.
    repo="$FIXTURE_ROOT/non-reserving-exact"
    initialize_fixture "$repo" "$config" || return 1
    output="$(cd "$repo" && PATH="$shim_dir:$PATH" GIT_BRANCH_NAME='manual/041-exact-name' \
        SPECKIT_TEST_REAL_GIT="$REAL_GIT" SPECKIT_TEST_RESERVATION_LOG="$reservation_log" \
        bash "$FEATURE_SCRIPT" --json ignored 2>"$stderr_file")" || return 1
    branch="$(json_field "$output" BRANCH_NAME)" || return 1
    assert_equal 'manual/041-exact-name' "$branch" 'exact branch bypass' || return 1

    repo="$FIXTURE_ROOT/non-reserving-explicit"
    initialize_fixture "$repo" "$config" || return 1
    output="$(cd "$repo" && PATH="$shim_dir:$PATH" GIT_BRANCH_NAME= \
        SPECKIT_TEST_REAL_GIT="$REAL_GIT" SPECKIT_TEST_RESERVATION_LOG="$reservation_log" \
        bash "$FEATURE_SCRIPT" --json --number 42 'Explicit number' 2>"$stderr_file")" || return 1
    assert_equal '042-explicit-number' "$(json_field "$output" BRANCH_NAME)" 'explicit number bypass' || return 1

    repo="$FIXTURE_ROOT/non-reserving-timestamp"
    initialize_fixture "$repo" "$config" || return 1
    output="$(cd "$repo" && PATH="$shim_dir:$PATH" GIT_BRANCH_NAME= \
        SPECKIT_TEST_REAL_GIT="$REAL_GIT" SPECKIT_TEST_RESERVATION_LOG="$reservation_log" \
        bash "$FEATURE_SCRIPT" --json --timestamp 'Timestamp number' 2>"$stderr_file")" || return 1
    if [[ "$(json_field "$output" FEATURE_NUM)" != [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9] ]]; then
        printf 'assertion failed: timestamp bypass did not produce a timestamp\n' >&2
        return 1
    fi

    repo="$FIXTURE_ROOT/non-reserving-dry-run"
    initialize_fixture "$repo" "$config" || return 1
    output="$(cd "$repo" && PATH="$shim_dir:$PATH" GIT_BRANCH_NAME= \
        SPECKIT_TEST_REAL_GIT="$REAL_GIT" SPECKIT_TEST_RESERVATION_LOG="$reservation_log" \
        bash "$FEATURE_SCRIPT" --json --dry-run 'Dry run number' 2>"$stderr_file")" || return 1
    assert_equal '001-dry-run-number' "$(json_field "$output" BRANCH_NAME)" 'dry-run bypass' || return 1

    no_git_root="$FIXTURE_ROOT/non-reserving-no-git"
    no_git_script_dir="$no_git_root/.specify/extensions/git/scripts/bash"
    mkdir -p "$no_git_script_dir" || return 1
    cp "$FEATURE_SCRIPT" "$no_git_script_dir/create-new-feature.sh" || return 1
    cp "$GIT_COMMON_SCRIPT" "$no_git_script_dir/git-common.sh" || return 1
    printf 'checkout_mode: branch\nbranch_numbering: sequential\n' \
        > "$no_git_root/.specify/extensions/git/git-config.yml" || return 1
    output="$(cd "$no_git_root" && PATH="$shim_dir:$PATH" GIT_BRANCH_NAME= \
        SPECKIT_TEST_REAL_GIT="$REAL_GIT" SPECKIT_TEST_RESERVATION_LOG="$reservation_log" \
        bash "$no_git_script_dir/create-new-feature.sh" --json 'No Git number' 2>"$stderr_file")" || return 1
    assert_equal 'False' "$(json_field "$output" HAS_GIT)" 'no-Git bypass' || return 1

    # Then: exact, explicit, timestamp, dry-run, and no-Git paths never call reservation update-ref.
    if [ -s "$reservation_log" ]; then
        printf 'assertion failed: a bypass path touched reservation refs\n%s\n' "$(<"$reservation_log")" >&2
        return 1
    fi
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

# ---------------------------------------------------------------------------
# openRepoShape three-leg fixtures and scenarios.
#
# A three-leg fixture is three local repositories: two leg "origins" plus an
# assembly root that mounts them as real submodules at spec/ and code/, with a
# project.yaml manifest and the root's .specify/ overlay.
# ---------------------------------------------------------------------------

THREE_LEG_ROOT=''
THREE_LEG_SPEC_ORIGIN=''
THREE_LEG_CODE_ORIGIN=''

init_plain_repo() {
    local repo="$1"

    mkdir -p "$repo" || return 1
    git init -q -b main "$repo" || return 1
    git -C "$repo" config user.name 'Spec Kit test' || return 1
    git -C "$repo" config user.email 'spec-kit-test@example.invalid' || return 1
    printf 'fixture\n' > "$repo/README.md" || return 1
    git -C "$repo" add README.md || return 1
    git -C "$repo" commit -qm 'fixture commit' || return 1
}

# Newer Git refuses the file:// transport for submodules unless it is allowed
# explicitly; older Git does not know the option at all.
add_local_submodule() {
    local repo="$1"
    local source="$2"
    local mount="$3"

    if git -C "$repo" -c protocol.file.allow=always submodule add -q "$source" "$mount" 2>/dev/null; then
        return 0
    fi
    git -C "$repo" submodule add -q "$source" "$mount"
}

# The three-leg fixture's manifest is DERIVED from the pinned copy of
# openRepoShape's own assembly-root template, not hand-mirrored: every
# `{{PLACEHOLDER}}` is substituted with a dummy value and the derivation
# REFUSES if any survives. A field the standard adds therefore fails here,
# loudly, instead of leaving a fixture that quietly stops resembling the thing
# it stands for. The template's own ~140-line comment block reaches the
# readers with it, which is the point: `workspace_read_scalar`,
# `workspace_project_repository` and `load_repo_shape` all strip comments
# before anything else, and this is the run that says so.
#
# The nested `naming:` records are the deliberate trap, and they arrive
# through the substituted values: a naive parser that takes the last `role:`
# it saw reads the CODE leg's nested `role: spec` and mounts that leg at
# spec/. The commented decoy leg is the FIXTURE's own and is appended after
# substitution — the template carries no commented leg block.
write_three_leg_manifest() {
    local manifest="$1"

    python3 - "$THREE_LEG_MANIFEST_TEMPLATE" "$manifest" <<'PY' || return 1
import re
import sys

template, destination = sys.argv[1], sys.argv[2]

# One entry per `{{...}}` in openRepoShape's assembly-root project.yaml. A
# placeholder the standard ADDS has no entry here, so the refusal below names
# it; a placeholder it REMOVES leaves an unused entry, which is harmless and
# is not what this fixture is guarding.
#
# The `*_NAMING` values carry their own indentation, because the template puts
# those placeholders at column zero and the block they stand for is nested
# under the leg at indent 4.
VALUES = {
    "PROJECT_ID": "fixture-project",
    "PROJECT_NAME": "Fixture Project",
    "REFERENCE": "dummy reference",
    "ELECTED_BY": "spec-kit-test",
    "ELECTED_ON": "2026-01-01",
    "TOPIC": "xf-project-fixture",
    "VISIBILITY": "private",
    "TRACKING_BRANCH": "main",
    "SHAPE_REPOSITORY": "dummy/openRepoShape",
    "SHAPE_COMMIT": "0" * 40,
    "DIGEST_DEFINITION": "sorted-ls-tree-r-v1",
    "SHAPE_TREE_SHA256": "0" * 64,
    "NEUTRAL_PRODUCT_PINS": "[]",
    "ASSEMBLY_REPOSITORY": "dummy/fixture-project",
    "SPEC_REPOSITORY": "dummy/fixture-project-spec",
    "SPEC_PATH": "spec",
    "CODE_REPOSITORY": "dummy/fixture-project-code",
    "CODE_PATH": "code",
    "ASSEMBLY_NAMING": "    naming:\n      form: project-leg\n"
                       "      role: assembly\n      also_matches: []",
    "SPEC_NAMING": "    naming:\n      form: project-leg\n"
                   "      role: spec\n      also_matches: []",
    "CODE_NAMING": "    naming:\n      form: project-leg\n"
                   "      role: spec\n      also_matches: []",
}

# The fixture's own decoy, carried by no openRepoShape template. A parser that
# greps for `role:` reads these two commented lines as a fourth leg mounted at
# a path that does not exist; every reader in the git extension strips comments
# first (workspace-common.sh, git-common.sh), and this block is what makes that
# a tested property rather than a claim.
DECOY = """
# ===========================================================================
# THE LINES BELOW ARE THIS FIXTURE'S, not openRepoShape's, and they are a
# DECOY: a naive `grep role:` reader mounts a leg named here that does not
# exist. Every reader must strip comments before it reads anything.
#   - role: spec
#     path: not-a-real-leg
# ===========================================================================
"""

with open(template, "r", encoding="utf-8") as stream:
    text = stream.read()
for name, value in VALUES.items():
    text = text.replace("{{%s}}" % name, value)

leftover = sorted(set(re.findall(r"\{\{[^{}]*\}\}", text)))
if leftover:
    raise SystemExit(
        "the pinned openRepoShape manifest template carries "
        "placeholder(s) this fixture has no value for: %s\n"
        "    template: %s\n"
        "Add them to VALUES in write_three_leg_manifest "
        "(devBenches/devcontainer.test/test-speckit-git-feature.sh)."
        % (", ".join(leftover), template))

# Three properties the helpers below depend on, asserted where the derivation
# happens so that a template change is named here rather than three scenarios
# later.
#
# (1) `set_assembly_repository` replaces this exact line and refuses unless it
#     is unique. The spec and code legs render with a suffix, and the `shape:`
#     block's repository: sits at indent 2, so it is.
assembly = "    repository: dummy/fixture-project\n"
if text.count(assembly) != 1:
    raise SystemExit(
        "the derived manifest holds %d assembly-leg repository lines, not 1; "
        "set_assembly_repository cannot work" % text.count(assembly))
# (2) Exactly three legs, each opening with its role at indent 2, and the
#     roles are exactly the three load_repo_shape needs, once each — a
#     template that renamed one would otherwise pass this and then fail three
#     scenarios later inside the reader.
roles = re.findall(r"^  - role: (\S+)$", text, re.MULTILINE)
if sorted(roles) != ["assembly", "code", "spec"]:
    raise SystemExit(
        "the derived manifest's legs are %r, not assembly/spec/code once each"
        % (roles,))
# (3) The nested `role:` trap survived the substitution, twice: the spec leg's
#     naming block and the code leg's, the second of which says `spec`.
if text.count("\n      role: spec\n") != 2:
    raise SystemExit(
        "the derived manifest holds %d nested `role: spec` records, not 2; "
        "the naive-parser trap is gone"
        % text.count("\n      role: spec\n"))

with open(destination, "w", encoding="utf-8") as stream:
    stream.write(text)
    if not text.endswith("\n"):
        stream.write("\n")
    stream.write(DECOY)
PY
}

initialize_three_leg_fixture() {
    local name="$1"
    local config="$2"
    local base="$FIXTURE_ROOT/$name"

    THREE_LEG_ROOT="$base/root"
    THREE_LEG_SPEC_ORIGIN="$base/spec-origin"
    THREE_LEG_CODE_ORIGIN="$base/code-origin"

    mkdir -p "$base" || return 1
    init_plain_repo "$THREE_LEG_SPEC_ORIGIN" || return 1
    init_plain_repo "$THREE_LEG_CODE_ORIGIN" || return 1
    init_plain_repo "$THREE_LEG_ROOT" || return 1
    add_local_submodule "$THREE_LEG_ROOT" "$THREE_LEG_SPEC_ORIGIN" spec || return 1
    add_local_submodule "$THREE_LEG_ROOT" "$THREE_LEG_CODE_ORIGIN" code || return 1
    # A submodule checkout has its own config under .git/modules/<leg>, so the
    # identity set on the origin does not reach it; commits made in the leg
    # worktrees (auto-commit) need it there. CI runners have no global identity.
    local leg
    for leg in spec code; do
        git -C "$THREE_LEG_ROOT/$leg" config user.name 'Spec Kit test' || return 1
        git -C "$THREE_LEG_ROOT/$leg" config user.email 'spec-kit-test@example.invalid' || return 1
    done
    write_three_leg_manifest "$THREE_LEG_ROOT/project.yaml" || return 1
    mkdir -p "$THREE_LEG_ROOT/.specify/extensions/git" || return 1
    printf '%s\n' "$config" > "$THREE_LEG_ROOT/.specify/extensions/git/git-config.yml" || return 1
    printf '/worktrees/\n' > "$THREE_LEG_ROOT/.gitignore" || return 1
    git -C "$THREE_LEG_ROOT" add -A || return 1
    git -C "$THREE_LEG_ROOT" commit -qm 'three-leg fixture' || return 1
}

install_three_leg_scripts() {
    local root="$1"
    local script_dir="$root/.specify/extensions/git/scripts/bash"

    mkdir -p "$script_dir" "$root/.specify/shell" || return 1
    cp "$GET_LAST_WORKTREE_SCRIPT" "$script_dir/get-last-worktree.sh" || return 1
    cp "$GIT_COMMON_SCRIPT" "$script_dir/git-common.sh" || return 1
    cp "$AUTO_COMMIT_SCRIPT" "$script_dir/auto-commit.sh" || return 1
    cp "$SELECT_WORKTREE_SCRIPT" "$root/.specify/shell/select-worktree.sh" || return 1
    chmod +x \
        "$script_dir/get-last-worktree.sh" \
        "$script_dir/auto-commit.sh" \
        "$root/.specify/shell/select-worktree.sh"
}

invoke_three_leg_feature() {
    local root="$1"
    local description="$2"
    local stderr_file="$3"
    shift 3

    FEATURE_OUTPUT=''
    FEATURE_OUTPUT="$(cd "$root" && bash "$FEATURE_SCRIPT" --json "$@" "$description" 2>"$stderr_file")" || return 1
}

leg_branches() {
    git -C "$1" for-each-ref --format='%(refname:short)' refs/heads | sort | tr '\n' ' '
}

worktree_record_count() {
    git -C "$1" worktree list --porcelain | grep -c '^worktree ' || true
}

assert_no_three_leg_side_effects() {
    local root="$1"
    local label="$2"

    if [ -e "$root/worktrees" ]; then
        printf 'assertion failed: %s created %s\n' "$label" "$root/worktrees" >&2
        return 1
    fi
    if [ -e "$root/.specify/feature.json" ]; then
        printf 'assertion failed: %s wrote .specify/feature.json\n' "$label" >&2
        return 1
    fi
    assert_equal 'main ' "$(leg_branches "$root/spec")" "$label spec leg branches" || return 1
    assert_equal 'main ' "$(leg_branches "$root/code")" "$label code leg branches" || return 1
    assert_equal 'main ' "$(leg_branches "$root")" "$label root branches"
}

THREE_LEG_CONFIG=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: worktrees'

test_three_leg_creates_both_leg_worktrees() {
    local stderr_file="$FIXTURE_ROOT/three-leg-create.stderr"
    local root branch worktree_path spec_worktree code_worktree feature_dir
    local repo_shape project_root feature_json

    # Given: a three-leg root whose code leg already carries a 002 branch.
    initialize_three_leg_fixture 'three-leg-create' "$THREE_LEG_CONFIG" || return 1
    root="$THREE_LEG_ROOT"
    git -C "$root/code" branch 002-existing || return 1

    # When: the feature hook runs from the assembly root.
    if ! invoke_three_leg_feature "$root" 'Add routing core' "$stderr_file"; then
        printf 'three-leg invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi

    # Then: numbering crosses both legs and the JSON carries the shape keys.
    branch="$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" || return 1
    repo_shape="$(json_field "$FEATURE_OUTPUT" REPO_SHAPE)" || return 1
    project_root="$(json_field "$FEATURE_OUTPUT" PROJECT_ROOT)" || return 1
    worktree_path="$(json_field "$FEATURE_OUTPUT" WORKTREE_PATH)" || return 1
    spec_worktree="$(json_field "$FEATURE_OUTPUT" SPEC_WORKTREE_PATH)" || return 1
    code_worktree="$(json_field "$FEATURE_OUTPUT" CODE_WORKTREE_PATH)" || return 1
    feature_dir="$(json_field "$FEATURE_OUTPUT" FEATURE_DIR)" || return 1

    assert_equal '003-routing-core' "$branch" 'three-leg branch number across legs' || return 1
    assert_equal 'three-leg' "$repo_shape" 'three-leg REPO_SHAPE' || return 1
    assert_equal "$root" "$project_root" 'three-leg PROJECT_ROOT' || return 1
    assert_equal "$root/worktrees/003-routing-core" "$worktree_path" 'three-leg WORKTREE_PATH' || return 1
    assert_equal "$worktree_path/spec" "$spec_worktree" 'three-leg SPEC_WORKTREE_PATH' || return 1
    assert_equal "$worktree_path/code" "$code_worktree" 'three-leg CODE_WORKTREE_PATH' || return 1
    assert_equal "$spec_worktree/specs/003-routing-core" "$feature_dir" 'three-leg FEATURE_DIR' || return 1

    # Then: both legs hold a real worktree on the same branch.
    assert_worktree '003-routing-core' "$spec_worktree" || return 1
    assert_worktree '003-routing-core' "$code_worktree" || return 1
    if [ ! -d "$feature_dir" ]; then
        printf 'assertion failed: FEATURE_DIR was not created: %s\n' "$feature_dir" >&2
        return 1
    fi

    # Then: the assembly root gets no branch and no worktree of its own.
    assert_equal 'main ' "$(leg_branches "$root")" 'three-leg root branches' || return 1
    assert_equal '1' "$(worktree_record_count "$root")" 'three-leg root worktree records' || return 1

    # Then: feature.json at the ROOT points into the spec worktree.
    feature_json="$(<"$root/.specify/feature.json")" || return 1
    assert_equal 'worktrees/003-routing-core/spec/specs/003-routing-core' \
        "$(json_field "$feature_json" feature_directory)" 'three-leg feature.json' || return 1

    # Then: the stderr hints name both environment variables.
    if ! grep -Fq '# To persist: export SPECIFY_FEATURE=003-routing-core' "$stderr_file"; then
        printf 'assertion failed: missing SPECIFY_FEATURE hint\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if ! grep -Fq '#             export SPECIFY_FEATURE_DIRECTORY=worktrees/003-routing-core/spec/specs/003-routing-core' "$stderr_file"; then
        printf 'assertion failed: missing SPECIFY_FEATURE_DIRECTORY hint\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
}

test_three_leg_dry_run_creates_nothing() {
    local stderr_file="$FIXTURE_ROOT/three-leg-dry-run.stderr"
    local root

    # Given: a clean three-leg root.
    initialize_three_leg_fixture 'three-leg-dry-run' "$THREE_LEG_CONFIG" || return 1
    root="$THREE_LEG_ROOT"

    # When: the hook runs in dry-run mode.
    if ! invoke_three_leg_feature "$root" 'Add routing core' "$stderr_file" --dry-run; then
        printf 'three-leg dry-run invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi

    # Then: the shape and paths are reported but nothing is created.
    assert_equal 'three-leg' "$(json_field "$FEATURE_OUTPUT" REPO_SHAPE)" 'dry-run REPO_SHAPE' || return 1
    assert_equal '001-routing-core' "$(json_field "$FEATURE_OUTPUT" BRANCH_NAME)" 'dry-run branch' || return 1
    assert_equal "$root/worktrees/001-routing-core/spec/specs/001-routing-core" \
        "$(json_field "$FEATURE_OUTPUT" FEATURE_DIR)" 'dry-run FEATURE_DIR' || return 1
    assert_no_three_leg_side_effects "$root" 'three-leg dry run'
}

test_three_leg_refuses_branch_checkout_mode() {
    local stderr_file="$FIXTURE_ROOT/three-leg-branch-mode.stderr"
    local root

    # Given: a three-leg root configured for branch mode.
    initialize_three_leg_fixture 'three-leg-branch-mode' $'checkout_mode: branch\nbase_branch: main' || return 1
    root="$THREE_LEG_ROOT"

    # When: the hook runs.
    if invoke_three_leg_feature "$root" 'Add routing core' "$stderr_file"; then
        printf 'assertion failed: branch checkout_mode was accepted in a three-leg project\n' >&2
        return 1
    fi

    # Then: the refusal names checkout_mode and nothing was created.
    if ! grep -Fq 'checkout_mode: worktree' "$stderr_file"; then
        printf 'assertion failed: refusal does not name checkout_mode\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    assert_no_three_leg_side_effects "$root" 'three-leg branch mode refusal'
}

test_three_leg_refuses_uninitialised_leg() {
    local stderr_file="$FIXTURE_ROOT/three-leg-empty-leg.stderr"
    local root

    # Given: the code leg submodule was never fetched (an empty mount point).
    initialize_three_leg_fixture 'three-leg-empty-leg' "$THREE_LEG_CONFIG" || return 1
    root="$THREE_LEG_ROOT"
    rm -rf "$root/code" || return 1
    mkdir -p "$root/code" || return 1

    # When: the hook runs.
    if invoke_three_leg_feature "$root" 'Add routing core' "$stderr_file"; then
        printf 'assertion failed: an uninitialised leg was accepted\n' >&2
        return 1
    fi

    # Then: the refusal tells the user how to fetch the submodule.
    if ! grep -Fq 'git submodule update --init' "$stderr_file"; then
        printf 'assertion failed: refusal does not name git submodule update --init\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if [ -e "$root/worktrees" ] || [ -e "$root/.specify/feature.json" ]; then
        printf 'assertion failed: uninitialised leg refusal still created state\n' >&2
        return 1
    fi
    assert_equal 'main ' "$(leg_branches "$root/spec")" 'uninitialised leg refusal spec branches'
}

test_three_leg_refuses_existing_feature_directory() {
    local stderr_file="$FIXTURE_ROOT/three-leg-existing-dir.stderr"
    local root

    # Given: the feature directory the hook would use already exists.
    initialize_three_leg_fixture 'three-leg-existing-dir' "$THREE_LEG_CONFIG" || return 1
    root="$THREE_LEG_ROOT"
    mkdir -p "$root/worktrees/001-routing-core" || return 1

    # When: the hook runs.
    if invoke_three_leg_feature "$root" 'Add routing core' "$stderr_file"; then
        printf 'assertion failed: an existing feature directory was accepted\n' >&2
        return 1
    fi

    # Then: it refuses without creating branches in either leg.
    if ! grep -Fq "Feature worktree directory '$root/worktrees/001-routing-core' already exists" "$stderr_file"; then
        printf 'assertion failed: refusal does not name the existing feature directory\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    assert_equal 'main ' "$(leg_branches "$root/spec")" 'existing dir refusal spec branches' || return 1
    assert_equal 'main ' "$(leg_branches "$root/code")" 'existing dir refusal code branches'
}

install_code_worktree_failure_shim() {
    local shim_dir="$1"

    mkdir -p "$shim_dir" || return 1
    cat > "$shim_dir/git" <<'SH'
#!/usr/bin/env bash
is_worktree=false
is_add=false
touches_code_leg=false
for argument in "$@"; do
    case "$argument" in
        worktree) is_worktree=true ;;
        add) is_add=true ;;
        */code|*/code/*) touches_code_leg=true ;;
    esac
done

if $is_worktree && $is_add && $touches_code_leg; then
    printf 'forced code leg worktree failure\n' >&2
    exit 128
fi

exec "$SPECKIT_TEST_REAL_GIT" "$@"
SH
    chmod +x "$shim_dir/git"
}

test_three_leg_rolls_back_when_code_leg_fails() {
    local stderr_file="$FIXTURE_ROOT/three-leg-rollback.stderr"
    local shim_dir="$FIXTURE_ROOT/three-leg-rollback-bin"
    local root

    # Given: adding the code leg worktree is forced to fail.
    initialize_three_leg_fixture 'three-leg-rollback' "$THREE_LEG_CONFIG" || return 1
    root="$THREE_LEG_ROOT"
    install_code_worktree_failure_shim "$shim_dir" || return 1

    # When: the hook runs with the failing shim first on PATH.
    if (cd "$root" && PATH="$shim_dir:$PATH" SPECKIT_TEST_REAL_GIT="$REAL_GIT" \
        bash "$FEATURE_SCRIPT" --json 'Add routing core' >/dev/null 2>"$stderr_file"); then
        printf 'assertion failed: the hook succeeded although the code leg failed\n' >&2
        return 1
    fi

    # Then: the spec leg worktree and branch are rolled back.
    if ! grep -Fq 'Rolling back the spec leg worktree' "$stderr_file"; then
        printf 'assertion failed: no rollback message\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    assert_equal 'main ' "$(leg_branches "$root/spec")" 'rollback spec leg branches' || return 1
    assert_equal 'main ' "$(leg_branches "$root/code")" 'rollback code leg branches' || return 1
    assert_equal '1' "$(worktree_record_count "$root/spec")" 'rollback spec worktree records' || return 1
    if [ -e "$root/worktrees/001-routing-core" ]; then
        printf 'assertion failed: rollback left the feature directory behind\n' >&2
        return 1
    fi
}

test_three_leg_get_last_worktree_reports_feature() {
    local stderr_file="$FIXTURE_ROOT/three-leg-get-last.stderr"
    local root output list_output

    # Given: a created three-leg feature and the discovery scripts installed.
    initialize_three_leg_fixture 'three-leg-get-last' "$THREE_LEG_CONFIG" || return 1
    root="$THREE_LEG_ROOT"
    install_three_leg_scripts "$root" || return 1
    if ! invoke_three_leg_feature "$root" 'Add routing core' "$stderr_file"; then
        printf 'three-leg invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi

    # When: discovery runs from the assembly root.
    output="$(cd "$root" && bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json)" || return 1

    # Then: it reports the feature directory and both leg worktrees.
    assert_equal 'three-leg' "$(json_field "$output" REPO_SHAPE)" 'get-last REPO_SHAPE' || return 1
    assert_equal '001-routing-core' "$(json_field "$output" BRANCH_NAME)" 'get-last branch' || return 1
    assert_equal "$root/worktrees/001-routing-core" "$(json_field "$output" WORKTREE_PATH)" 'get-last WORKTREE_PATH' || return 1
    assert_equal "$root/worktrees/001-routing-core/spec" "$(json_field "$output" SPEC_WORKTREE_PATH)" 'get-last SPEC_WORKTREE_PATH' || return 1
    assert_equal "$root/worktrees/001-routing-core/code" "$(json_field "$output" CODE_WORKTREE_PATH)" 'get-last CODE_WORKTREE_PATH' || return 1
    assert_equal "$root/worktrees/001-routing-core/spec/specs/001-routing-core" \
        "$(json_field "$output" FEATURE_DIR)" 'get-last FEATURE_DIR' || return 1
    assert_equal "$root" "$(json_field "$output" PROJECT_ROOT)" 'get-last PROJECT_ROOT' || return 1

    # Then: the selector lists the same feature directory, not a leg checkout.
    list_output="$(cd "$root" && bash .specify/shell/select-worktree.sh --list)" || return 1
    if ! printf '%s\n' "$list_output" | grep -Fq "$root/worktrees/001-routing-core"; then
        printf 'assertion failed: selector did not list the feature directory\n%s\n' "$list_output" >&2
        return 1
    fi
    if printf '%s\n' "$list_output" | grep -Fq "$root/spec"; then
        printf 'assertion failed: selector listed the pinned spec leg\n%s\n' "$list_output" >&2
        return 1
    fi
}

test_three_leg_auto_commit_commits_both_legs_only() {
    local stderr_file="$FIXTURE_ROOT/three-leg-auto-commit.stderr"
    local config=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: worktrees\nauto_commit:\n  default: true'
    local root feature_dir root_head_before spec_head_before code_head_before

    # Given: a created feature with pending edits in both leg worktrees.
    initialize_three_leg_fixture 'three-leg-auto-commit' "$config" || return 1
    root="$THREE_LEG_ROOT"
    install_three_leg_scripts "$root" || return 1
    if ! invoke_three_leg_feature "$root" 'Add routing core' "$stderr_file"; then
        printf 'three-leg invocation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    feature_dir="$root/worktrees/001-routing-core"
    printf 'spec\n' > "$feature_dir/spec/specs/001-routing-core/spec.md" || return 1
    printf 'code\n' > "$feature_dir/code/implementation.txt" || return 1
    root_head_before="$(git -C "$root" rev-parse HEAD)" || return 1
    spec_head_before="$(git -C "$feature_dir/spec" rev-parse HEAD)" || return 1
    code_head_before="$(git -C "$feature_dir/code" rev-parse HEAD)" || return 1

    # When: the auto-commit hook runs from the assembly root.
    if ! (cd "$root" && bash .specify/extensions/git/scripts/bash/auto-commit.sh after_specify 2>"$stderr_file"); then
        printf 'three-leg auto-commit failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi

    # Then: both leg worktrees advanced and the assembly root did not.
    if [ "$spec_head_before" = "$(git -C "$feature_dir/spec" rev-parse HEAD)" ]; then
        printf 'assertion failed: the spec worktree was not committed\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if [ "$code_head_before" = "$(git -C "$feature_dir/code" rev-parse HEAD)" ]; then
        printf 'assertion failed: the code worktree was not committed\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    assert_equal "$root_head_before" "$(git -C "$root" rev-parse HEAD)" 'auto-commit left the root HEAD alone' || return 1
    assert_equal '001-routing-core' "$(git -C "$feature_dir/spec" branch --show-current)" 'auto-commit spec branch' || return 1
    assert_equal '001-routing-core' "$(git -C "$feature_dir/code" branch --show-current)" 'auto-commit code branch' || return 1

    # When: no feature is selected any more.
    rm -f "$root/.specify/feature.json" || return 1
    printf 'spec again\n' >> "$feature_dir/spec/specs/001-routing-core/spec.md" || return 1
    spec_head_before="$(git -C "$feature_dir/spec" rev-parse HEAD)" || return 1
    if ! (cd "$root" && env -u SPECIFY_FEATURE bash .specify/extensions/git/scripts/bash/auto-commit.sh after_plan 2>"$stderr_file"); then
        printf 'three-leg auto-commit without a feature failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi

    # Then: it says so and commits nothing.
    if ! grep -Fq 'No Speckit feature is selected' "$stderr_file"; then
        printf 'assertion failed: missing no-feature message\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    assert_equal "$spec_head_before" "$(git -C "$feature_dir/spec" rev-parse HEAD)" 'no-feature auto-commit left the spec worktree alone' || return 1
    assert_equal "$root_head_before" "$(git -C "$root" rev-parse HEAD)" 'no-feature auto-commit left the root alone'
}

# ---------------------------------------------------------------------------
# park / resume fixtures and scenarios (openRepoShape#77 S1, workBenches#30).
#
# The leg origins are BARE here, unlike initialize_three_leg_fixture's: park
# pushes the feature branch, and pushing the checked-out branch of a non-bare
# origin works only by accident (receive.denyCurrentBranch). The divergence
# scenario also has to push a foreign commit INTO an origin.
# ---------------------------------------------------------------------------

PARKED_ROOT=''
PARKED_SPEC_ORIGIN=''
PARKED_CODE_ORIGIN=''
PARKED_BASE=''
WORKSPACE_DIR=''
WORKSPACE_ORIGIN=''

init_bare_repo() {
    local bare="$1"

    if git init -q --bare -b main "$bare" 2>/dev/null; then
        return 0
    fi
    git init -q --bare "$bare" || return 1
    git -C "$bare" symbolic-ref HEAD refs/heads/main
}

# A bare origin seeded with one commit on main, through a throwaway checkout.
init_seeded_bare_origin() {
    local bare="$1"
    local seed="$2"

    mkdir -p "$seed" || return 1
    git init -q -b main "$seed" || return 1
    git -C "$seed" config user.name 'Spec Kit test' || return 1
    git -C "$seed" config user.email 'spec-kit-test@example.invalid' || return 1
    printf 'fixture\n' > "$seed/README.md" || return 1
    mkdir -p "$seed/specs" || return 1
    printf 'fixture\n' > "$seed/specs/.keep" || return 1
    git -C "$seed" add -A || return 1
    git -C "$seed" commit -qm 'fixture commit' || return 1
    init_bare_repo "$bare" || return 1
    git -C "$seed" remote add origin "$bare" || return 1
    git -C "$seed" push -q origin main || return 1
}

install_park_scripts() {
    local root="$1"
    local script_dir="$root/.specify/extensions/git/scripts/bash"

    mkdir -p "$script_dir" "$root/.specify/shell" || return 1
    cp "$GIT_COMMON_SCRIPT" "$script_dir/git-common.sh" || return 1
    cp "$WORKSPACE_COMMON_SCRIPT" "$script_dir/workspace-common.sh" || return 1
    cp "$PARK_SCRIPT" "$script_dir/park.sh" || return 1
    cp "$RESUME_SCRIPT" "$script_dir/resume.sh" || return 1
    cp "$GET_LAST_WORKTREE_SCRIPT" "$script_dir/get-last-worktree.sh" || return 1
    cp "$SELECT_WORKTREE_SCRIPT" "$root/.specify/shell/select-worktree.sh" || return 1
    chmod +x \
        "$script_dir/park.sh" \
        "$script_dir/resume.sh" \
        "$script_dir/get-last-worktree.sh" \
        "$root/.specify/shell/select-worktree.sh"
}

initialize_three_leg_parked_fixture() {
    local name="$1"
    local config="$2"
    local base="$FIXTURE_ROOT/$name"
    local leg

    PARKED_BASE="$base"
    PARKED_ROOT="$base/root"
    PARKED_SPEC_ORIGIN="$base/spec-origin.git"
    PARKED_CODE_ORIGIN="$base/code-origin.git"

    mkdir -p "$base" || return 1
    init_seeded_bare_origin "$PARKED_SPEC_ORIGIN" "$base/spec-seed" || return 1
    init_seeded_bare_origin "$PARKED_CODE_ORIGIN" "$base/code-seed" || return 1
    init_plain_repo "$PARKED_ROOT" || return 1
    add_local_submodule "$PARKED_ROOT" "$PARKED_SPEC_ORIGIN" spec || return 1
    add_local_submodule "$PARKED_ROOT" "$PARKED_CODE_ORIGIN" code || return 1
    for leg in spec code; do
        git -C "$PARKED_ROOT/$leg" config user.name 'Spec Kit test' || return 1
        git -C "$PARKED_ROOT/$leg" config user.email 'spec-kit-test@example.invalid' || return 1
    done
    write_three_leg_manifest "$PARKED_ROOT/project.yaml" || return 1
    mkdir -p "$PARKED_ROOT/.specify/extensions/git" || return 1
    printf '%s\n' "$config" > "$PARKED_ROOT/.specify/extensions/git/git-config.yml" || return 1
    printf '/worktrees/\n' > "$PARKED_ROOT/.gitignore" || return 1
    install_park_scripts "$PARKED_ROOT" || return 1
    git -C "$PARKED_ROOT" add -A || return 1
    git -C "$PARKED_ROOT" commit -qm 'three-leg parked fixture' || return 1
}

initialize_workspace_fixture() {
    local name="$1"
    local base="$FIXTURE_ROOT/$name"

    WORKSPACE_ORIGIN="$base/workspace-origin.git"
    WORKSPACE_DIR="$base/workspace"
    mkdir -p "$base" || return 1
    init_bare_repo "$WORKSPACE_ORIGIN" || return 1
    git init -q -b main "$WORKSPACE_DIR" || return 1
    git -C "$WORKSPACE_DIR" config user.name 'Spec Kit test' || return 1
    git -C "$WORKSPACE_DIR" config user.email 'spec-kit-test@example.invalid' || return 1
    mkdir -p "$WORKSPACE_DIR/workspaces" || return 1
    printf 'workspace manifests\n' > "$WORKSPACE_DIR/workspaces/README.md" || return 1
    git -C "$WORKSPACE_DIR" add -A || return 1
    git -C "$WORKSPACE_DIR" commit -qm 'workspace fixture' || return 1
    git -C "$WORKSPACE_DIR" remote add origin "$WORKSPACE_ORIGIN" || return 1
    git -C "$WORKSPACE_DIR" push -q -u origin main || return 1
}

clone_workspace_fixture() {
    local destination="$1"

    git clone -q "$WORKSPACE_ORIGIN" "$destination" || return 1
    git -C "$destination" config user.name 'Spec Kit test' || return 1
    git -C "$destination" config user.email 'spec-kit-test@example.invalid'
}

# A second checkout of a three-leg root, the way a person reaches one on
# another workstation: clone the assembly root, then initialise the legs.
clone_three_leg_root() {
    local source="$1"
    local destination="$2"
    local leg

    git -c protocol.file.allow=always clone -q "$source" "$destination" || return 1
    git -C "$destination" config user.name 'Spec Kit test' || return 1
    git -C "$destination" config user.email 'spec-kit-test@example.invalid' || return 1
    git -C "$destination" -c protocol.file.allow=always submodule update -q --init || return 1
    for leg in spec code; do
        git -C "$destination/$leg" config user.name 'Spec Kit test' || return 1
        git -C "$destination/$leg" config user.email 'spec-kit-test@example.invalid' || return 1
    done
    rm -f "$destination/.specify/feature.json"
}

PARK_OUTPUT=''
PARK_STATUS=0
invoke_park() {
    local root="$1"
    local stderr_file="$2"
    shift 2

    PARK_OUTPUT=''
    PARK_STATUS=0
    PARK_OUTPUT="$(cd "$root" && env \
        SPECKIT_WORKSTATION=Fixture SPECKIT_LANE=fixture-lane \
        bash .specify/extensions/git/scripts/bash/park.sh \
        --workspace "$WORKSPACE_DIR" "$@" 2>"$stderr_file")" || PARK_STATUS=$?
    return 0
}

RESUME_OUTPUT=''
RESUME_STATUS=0
invoke_resume() {
    local root="$1"
    local stderr_file="$2"
    shift 2

    RESUME_OUTPUT=''
    RESUME_STATUS=0
    RESUME_OUTPUT="$(cd "$root" && env \
        SPECKIT_WORKSTATION=Fixture SPECKIT_LANE=fixture-lane \
        bash .specify/extensions/git/scripts/bash/resume.sh \
        --workspace "$WORKSPACE_DIR" "$@" 2>"$stderr_file")" || RESUME_STATUS=$?
    return 0
}

create_parked_feature() {
    local root="$1"
    local description="$2"
    local stderr_file="$3"
    shift 3

    FEATURE_OUTPUT=''
    FEATURE_OUTPUT="$(cd "$root" && bash "$FEATURE_SCRIPT" --json "$@" "$description" 2>"$stderr_file")" || return 1
}

assert_contains_block() {
    local file="$1"
    local expected="$2"
    local label="$3"
    local content

    content="$(cat "$file")"
    case "$content" in
        *"$expected"*) return 0 ;;
    esac
    printf 'assertion failed: %s\n--- expected block ---\n%s\n--- actual ---\n%s\n' \
        "$label" "$expected" "$content" >&2
    return 1
}

assert_file_absent() {
    local path="$1"
    local label="$2"

    if [ -e "$path" ]; then
        printf 'assertion failed: %s exists: %s\n' "$label" "$path" >&2
        return 1
    fi
}

commit_count() {
    git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0
}

manifest_line_count() {
    grep -c "$2" "$1" 2>/dev/null || true
}

# Mask the values that move between runs so a whole-file comparison can assert
# every field AND the fixed key order at once. Python 3 rather than sed -E,
# because BusyBox sed is what the Bash 3.2 CI image has.
mask_manifest() {
    python3 - "$1" <<'PY'
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    for line in stream:
        line = line.rstrip("\n")
        line = re.sub(r"^( *parked_commit:) [0-9a-f]{40}$", r"\1 <SHA>", line)
        line = re.sub(
            r"^( *parked_at:) [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
            r"\1 <TS>",
            line,
        )
        print(line)
PY
}

PARKED_CONFIG=$'checkout_mode: worktree\nbase_branch: main\nworktree_root: worktrees'

# Point the fixture project's assembly leg at another org, so its manifest is
# filed — and its workspace chosen — under that org instead.
set_assembly_repository() {
    local root="$1"
    local slug="$2"

    python3 - "$root/project.yaml" "$slug" <<'PY'
import sys

path, slug = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as stream:
    text = stream.read()
old = "    repository: dummy/fixture-project\n"
if text.count(old) != 1:
    raise SystemExit("the assembly leg's repository line is not unique")
with open(path, "w", encoding="utf-8") as stream:
    stream.write(text.replace(old, "    repository: %s\n" % slug))
PY
    git -C "$root" add project.yaml || return 1
    git -C "$root" commit -qm 'point the assembly leg at another org'
}

test_park_commits_and_pushes_both_legs() {
    local stderr_file="$FIXTURE_ROOT/park-both-legs.stderr"
    local root spec_tree code_tree spec_before code_before
    local root_head_before root_index_before subject

    # Given: a parked-shape fixture with uncommitted work in both legs.
    initialize_three_leg_parked_fixture 'park-both-legs' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'park-both-legs-ws' || return 1
    root="$PARKED_ROOT"
    if ! create_parked_feature "$root" 'Add routing core' "$stderr_file"; then
        printf 'feature creation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    spec_tree="$root/worktrees/001-routing-core/spec"
    code_tree="$root/worktrees/001-routing-core/code"
    printf 'draft\n' > "$spec_tree/specs/001-routing-core/spec.md" || return 1
    printf 'impl\n' > "$code_tree/implementation.txt" || return 1
    spec_before="$(commit_count "$spec_tree")"
    code_before="$(commit_count "$code_tree")"
    root_head_before="$(git -C "$root" rev-parse HEAD)"
    root_index_before="$(git -C "$root" diff --cached --name-only | sort | tr '\n' ' ')"

    # When: park runs from the assembly root.
    invoke_park "$root" "$stderr_file"
    if [ "$PARK_STATUS" -ne 0 ]; then
        printf 'park failed (%s): %s\n' "$PARK_STATUS" "$(<"$stderr_file")" >&2
        return 1
    fi

    # Then: exactly one WIP commit per leg, with the fixed subject.
    assert_equal "$((spec_before + 1))" "$(commit_count "$spec_tree")" 'spec leg WIP commit' || return 1
    assert_equal "$((code_before + 1))" "$(commit_count "$code_tree")" 'code leg WIP commit' || return 1
    subject="$(git -C "$spec_tree" log -1 --format=%s)"
    if ! printf '%s\n' "$subject" | grep -Eq '^wip: park [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z — lane fixture-lane$'; then
        printf 'assertion failed: WIP subject does not match: %s\n' "$subject" >&2
        return 1
    fi

    # Then: the origins carry the branch at the parked commit.
    assert_equal "$(git -C "$spec_tree" rev-parse HEAD)" \
        "$(git -C "$PARKED_SPEC_ORIGIN" rev-parse refs/heads/001-routing-core)" \
        'spec origin has the parked commit' || return 1
    assert_equal "$(git -C "$code_tree" rev-parse HEAD)" \
        "$(git -C "$PARKED_CODE_ORIGIN" rev-parse refs/heads/001-routing-core)" \
        'code origin has the parked commit' || return 1

    # Then: the manifest records the WIP.
    assert_equal '2' "$(manifest_line_count "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml" '^            wip: true$')" \
        'manifest wip: true per leg' || return 1
    assert_equal '2' "$(manifest_line_count "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml" '^            wip_depth: 1$')" \
        'manifest wip_depth: 1 per leg' || return 1

    # Then: the assembly root is untouched — no branch, no worktree, no index.
    assert_equal 'main ' "$(leg_branches "$root")" 'park left the root branches alone' || return 1
    assert_equal '1' "$(worktree_record_count "$root")" 'park left the root worktree records alone' || return 1
    assert_equal "$root_head_before" "$(git -C "$root" rev-parse HEAD)" 'park left the root HEAD alone' || return 1
    assert_equal "$root_index_before" "$(git -C "$root" diff --cached --name-only | sort | tr '\n' ' ')" \
        'park left the root index alone'
}

test_park_clean_feature_makes_no_commit() {
    local stderr_file="$FIXTURE_ROOT/park-clean.stderr"
    local root spec_tree spec_before spec_tip

    # Given: a created feature with nothing uncommitted.
    initialize_three_leg_parked_fixture 'park-clean' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'park-clean-ws' || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    spec_tree="$root/worktrees/001-routing-core/spec"
    spec_before="$(commit_count "$spec_tree")"
    spec_tip="$(git -C "$spec_tree" rev-parse HEAD)"

    # When: park runs.
    invoke_park "$root" "$stderr_file"
    assert_equal '0' "$PARK_STATUS" 'clean park exit code' || return 1

    # Then: no commit was created anywhere and the tip is what was recorded.
    assert_equal "$spec_before" "$(commit_count "$spec_tree")" 'clean park created no commit' || return 1
    assert_equal '2' "$(manifest_line_count "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml" '^            wip: false$')" \
        'clean park records wip: false' || return 1
    assert_equal '2' "$(manifest_line_count "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml" '^            wip_depth: 0$')" \
        'clean park records wip_depth: 0' || return 1
    if ! grep -Fq "            parked_commit: $spec_tip" "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml"; then
        printf 'assertion failed: the spec tip was not recorded as the parked commit\n%s\n' \
            "$(<"$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml")" >&2
        return 1
    fi
}

test_park_enumerates_from_git_not_feature_json() {
    local stderr_file="$FIXTURE_ROOT/park-stale-json.stderr"
    local root

    # Given: a created feature and a feature.json naming a directory that is
    # not an open feature.
    initialize_three_leg_parked_fixture 'park-stale-json' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'park-stale-json-ws' || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    printf '%s\n' '{"feature_directory":"worktrees/009-removed/spec/specs/009-removed"}' \
        > "$root/.specify/feature.json" || return 1

    # When: park runs.
    invoke_park "$root" "$stderr_file"
    assert_equal '0' "$PARK_STATUS" 'stale feature.json park exit code' || return 1

    # Then: the open feature is parked, and the disagreement is a warning.
    if ! grep -Fq "[specify] Warning: .specify/feature.json names 'worktrees/009-removed/spec/specs/009-removed', which is not an open feature under 'worktrees'." "$stderr_file"; then
        printf 'assertion failed: missing W1 first line\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if ! grep -Fq "[specify] Recorded active_feature_source: stale-feature-json; resume will select '001-routing-core' instead." "$stderr_file"; then
        printf 'assertion failed: missing W1 second line\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if ! grep -Fq '    active_feature_source: stale-feature-json' "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml"; then
        printf 'assertion failed: active_feature_source was not recorded as stale-feature-json\n' >&2
        return 1
    fi
    grep -Fq '      - branch: 001-routing-core' "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml"
}

test_park_refuses_a_leg_without_origin() {
    local stderr_file="$FIXTURE_ROOT/park-no-origin.stderr"
    local root

    # Given: a created feature whose code leg has no origin. A remote is a
    # property of the leg REPOSITORY, so this refusal reaches every feature of
    # that leg — here there is one, so nothing is parked at all.
    initialize_three_leg_parked_fixture 'park-no-origin' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'park-no-origin-ws' || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    git -C "$root/code" remote remove origin || return 1

    # When: park runs.
    invoke_park "$root" "$stderr_file"

    # Then: R5, exactly, and nothing was recorded for the feature.
    assert_equal '2' "$PARK_STATUS" 'no-origin park exit code' || return 1
    assert_contains_block "$stderr_file" \
"Error: 001-routing-core (code leg) has no 'origin' remote; that feature was NOT parked.
resume rebuilds worktrees from pushed branches, so a leg with no remote cannot travel.
  git -C code remote add origin <url>" 'R5 wording' || return 1
    if grep -Fq '      - branch: 001-routing-core' "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml" 2>/dev/null; then
        printf 'assertion failed: a refused feature was recorded\n' >&2
        return 1
    fi
    assert_equal '0' "$(commit_count "$root/worktrees/001-routing-core/spec")" \
        'no-origin park made no spec commit' 2>/dev/null || true
    if [ "$(git -C "$root/worktrees/001-routing-core/spec" log -1 --format=%s)" != 'fixture commit' ]; then
        printf 'assertion failed: the spec leg was committed before the blockers were checked\n' >&2
        return 1
    fi
}

test_park_refuses_a_rebase_in_progress() {
    local stderr_file="$FIXTURE_ROOT/park-rebase.stderr"
    local root spec_tree spec_before

    # Given: two features, one of which has a real conflicted rebase in its
    # spec leg worktree.
    initialize_three_leg_parked_fixture 'park-rebase' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'park-rebase-ws' || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    create_parked_feature "$root" 'Add label render' "$stderr_file" || return 1
    spec_tree="$root/worktrees/001-routing-core/spec"
    printf 'feature side\n' > "$spec_tree/README.md" || return 1
    git -C "$spec_tree" commit -q -am 'feature edit' || return 1
    printf 'main side\n' > "$root/spec/README.md" || return 1
    git -C "$root/spec" commit -q -am 'main edit' || return 1
    git -C "$spec_tree" rebase main >/dev/null 2>&1 || true
    if [ ! -e "$(git -C "$spec_tree" rev-parse --absolute-git-dir)/rebase-merge" ] \
        && [ ! -e "$(git -C "$spec_tree" rev-parse --absolute-git-dir)/rebase-apply" ]; then
        printf 'fixture failed: no rebase is in progress\n' >&2
        return 1
    fi
    spec_before="$(commit_count "$spec_tree")"

    # When: park runs.
    invoke_park "$root" "$stderr_file"

    # Then: R4, exit 3, no commit in that leg, and the other feature parked.
    assert_equal '3' "$PARK_STATUS" 'rebase-in-progress park exit code' || return 1
    assert_contains_block "$stderr_file" \
"Error: 001-routing-core (spec leg) has a rebase in progress; that feature was NOT parked.
A WIP commit over an unresolved index would park a conflicted tree as if it were work.
  finish it:  git -C worktrees/001-routing-core/spec rebase --continue
  or drop it: git -C worktrees/001-routing-core/spec rebase --abort
Then re-run \`make park\`." 'R4 wording' || return 1
    assert_equal "$spec_before" "$(commit_count "$spec_tree")" 'R4 made no commit' || return 1
    grep -Fq '      - branch: 002-label-render' "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml" || {
        printf 'assertion failed: the other feature was not parked\n%s\n' \
            "$(<"$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml")" >&2
        return 1
    }
}

test_park_refuses_a_rejected_push_and_keeps_the_wip_commit() {
    local stderr_file="$FIXTURE_ROOT/park-push-refused.stderr"
    local root spec_tree wip_sha

    # Given: two features and a spec origin that rejects only 002-*.
    initialize_three_leg_parked_fixture 'park-push-refused' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'park-push-refused-ws' || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    create_parked_feature "$root" 'Add label render' "$stderr_file" || return 1
    mkdir -p "$PARKED_SPEC_ORIGIN/hooks" || return 1
    cat > "$PARKED_SPEC_ORIGIN/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
while read -r _old _new ref; do
    case "$ref" in
        */002-*) printf 'the fixture refuses %s\n' "$ref" >&2; exit 1 ;;
    esac
done
exit 0
HOOK
    chmod +x "$PARKED_SPEC_ORIGIN/hooks/pre-receive" || return 1
    spec_tree="$root/worktrees/002-label-render/spec"
    printf 'draft\n' > "$spec_tree/specs/002-label-render/spec.md" || return 1

    # When: park runs.
    invoke_park "$root" "$stderr_file"

    # Then: R6, exit 3, the WIP commit is still there, nothing recorded for it.
    assert_equal '3' "$PARK_STATUS" 'rejected-push park exit code' || return 1
    wip_sha="$(git -C "$spec_tree" rev-parse HEAD)"
    if ! grep -Fq 'Error: pushing 002-label-render to origin refused in the spec leg; that feature was NOT parked.' "$stderr_file"; then
        printf 'assertion failed: missing R6 first line\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if ! grep -Fq "Your work is NOT lost: it is committed locally at $wip_sha. park never force-pushes." "$stderr_file"; then
        printf 'assertion failed: missing R6 reassurance\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if ! grep -Fq "  look:  git -C worktrees/002-label-render/spec fetch origin && git -C worktrees/002-label-render/spec log --oneline $wip_sha..origin/002-label-render" "$stderr_file"; then
        printf 'assertion failed: missing R6 remediation\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if ! grep -Fq 'Then reconcile by hand and re-run `make park`.' "$stderr_file"; then
        printf 'assertion failed: missing R6 closing line\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if ! git -C "$spec_tree" log -1 --format=%s | grep -q '^wip: park '; then
        printf 'assertion failed: the WIP commit was not kept\n' >&2
        return 1
    fi
    if grep -Fq '      - branch: 002-label-render' "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml"; then
        printf 'assertion failed: a feature whose push was refused was recorded\n' >&2
        return 1
    fi
    grep -Fq '      - branch: 001-routing-core' "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml"
}

test_park_stacks_a_second_wip_without_a_force_push() {
    local stderr_file="$FIXTURE_ROOT/park-stacked.stderr"
    local root spec_tree base_count

    # Given: a feature already parked with one WIP commit, then dirty again.
    initialize_three_leg_parked_fixture 'park-stacked' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'park-stacked-ws' || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    spec_tree="$root/worktrees/001-routing-core/spec"
    base_count="$(commit_count "$spec_tree")"
    printf 'draft\n' > "$spec_tree/specs/001-routing-core/spec.md" || return 1
    invoke_park "$root" "$stderr_file"
    assert_equal '0' "$PARK_STATUS" 'first park of a stack' || return 1
    printf 'draft again\n' >> "$spec_tree/specs/001-routing-core/spec.md" || return 1

    # When: park runs a second time.
    invoke_park "$root" "$stderr_file"

    # Then: a second WIP commit, depth 2, and a fast-forward push.
    assert_equal '0' "$PARK_STATUS" 'second park of a stack' || return 1
    assert_equal "$((base_count + 2))" "$(commit_count "$spec_tree")" 'two stacked WIP commits' || return 1
    if ! grep -Fq '            wip_depth: 2' "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml"; then
        printf 'assertion failed: wip_depth 2 was not recorded\n%s\n' \
            "$(<"$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml")" >&2
        return 1
    fi
    assert_equal "$(git -C "$spec_tree" rev-parse HEAD)" \
        "$(git -C "$PARKED_SPEC_ORIGIN" rev-parse refs/heads/001-routing-core)" \
        'the stacked push reached the origin' || return 1
    if grep -Fq 'force' "$stderr_file"; then
        printf 'assertion failed: a force-push was mentioned\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
}

test_park_dry_run_writes_nothing() {
    local stderr_file="$FIXTURE_ROOT/park-dry-run.stderr"
    local root spec_tree spec_before

    # Given: a created feature with uncommitted work.
    initialize_three_leg_parked_fixture 'park-dry-run' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'park-dry-run-ws' || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    spec_tree="$root/worktrees/001-routing-core/spec"
    printf 'draft\n' > "$spec_tree/specs/001-routing-core/spec.md" || return 1
    spec_before="$(commit_count "$spec_tree")"

    # When: park runs with --dry-run.
    invoke_park "$root" "$stderr_file" --dry-run
    assert_equal '0' "$PARK_STATUS" 'dry-run park exit code' || return 1

    # Then: no commit, no push, no manifest, no lock left behind.
    assert_equal "$spec_before" "$(commit_count "$spec_tree")" 'dry-run park made no commit' || return 1
    if git -C "$PARKED_SPEC_ORIGIN" rev-parse --verify --quiet refs/heads/001-routing-core >/dev/null; then
        printf 'assertion failed: dry-run park pushed a branch\n' >&2
        return 1
    fi
    assert_file_absent "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml" 'dry-run park manifest' || return 1
    assert_file_absent "$WORKSPACE_DIR/.workspaces.lock" 'dry-run park lock directory' || return 1
    assert_equal '1' "$(commit_count "$WORKSPACE_DIR")" 'dry-run park made no workspace commit' || return 1
    if ! printf '%s\n' "$PARK_OUTPUT" | grep -Fq 'COMMITTED: nothing (--dry-run)'; then
        printf 'assertion failed: dry-run park did not say it wrote nothing\n%s\n' "$PARK_OUTPUT" >&2
        return 1
    fi
}

# A parked three-leg fixture with one feature carrying WIP in both legs, and a
# second checkout of the root ready to resume it. Sets PARKED_ROOT,
# WORKSPACE_DIR, RESUME_ROOT and RESUME_PARKED_SPEC / RESUME_PARKED_CODE.
RESUME_ROOT=''
RESUME_PARKED_SPEC=''
RESUME_PARKED_CODE=''
park_then_clone() {
    local name="$1"
    local stderr_file="$2"
    local root

    initialize_three_leg_parked_fixture "$name" "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture "$name-ws" || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    printf 'draft\n' > "$root/worktrees/001-routing-core/spec/specs/001-routing-core/spec.md" || return 1
    printf 'impl\n' > "$root/worktrees/001-routing-core/code/implementation.txt" || return 1
    invoke_park "$root" "$stderr_file"
    if [ "$PARK_STATUS" -ne 0 ]; then
        printf 'park failed (%s): %s\n' "$PARK_STATUS" "$(<"$stderr_file")" >&2
        return 1
    fi
    RESUME_PARKED_SPEC="$(git -C "$root/worktrees/001-routing-core/spec" rev-parse HEAD)"
    RESUME_PARKED_CODE="$(git -C "$root/worktrees/001-routing-core/code" rev-parse HEAD)"
    RESUME_ROOT="$PARKED_BASE/second"
    clone_three_leg_root "$root" "$RESUME_ROOT"
}

test_resume_recreates_worktrees_feature_json_and_state() {
    local stderr_file="$FIXTURE_ROOT/resume-fresh.stderr"
    local clone output

    # Given: a parked feature and a fresh clone of the assembly root.
    park_then_clone 'resume-fresh' "$stderr_file" || return 1
    clone="$RESUME_ROOT"

    # When: resume runs there.
    invoke_resume "$clone" "$stderr_file"
    if [ "$RESUME_STATUS" -ne 0 ]; then
        printf 'resume failed (%s): %s\n' "$RESUME_STATUS" "$(<"$stderr_file")" >&2
        return 1
    fi

    # Then: both legs are registered on the branch at the parked commit.
    assert_worktree '001-routing-core' "$clone/worktrees/001-routing-core/spec" || return 1
    assert_worktree '001-routing-core' "$clone/worktrees/001-routing-core/code" || return 1
    assert_equal "$RESUME_PARKED_SPEC" \
        "$(git -C "$clone/spec" rev-parse refs/remotes/origin/001-routing-core)" \
        'resume fetched the parked spec commit' || return 1

    # Then: feature.json and the state file are restored, and discovery agrees.
    assert_equal 'worktrees/001-routing-core/spec/specs/001-routing-core' \
        "$(json_field "$(<"$clone/.specify/feature.json")" feature_directory)" 'resume feature.json' || return 1
    assert_equal '001-routing-core' \
        "$(json_field "$(<"$clone/.git/speckit-last-worktree.json")" BRANCH_NAME)" 'resume state file' || return 1
    output="$(cd "$clone" && bash .specify/extensions/git/scripts/bash/get-last-worktree.sh --json)" || return 1
    assert_equal 'state_file' "$(json_field "$output" SOURCE)" 'resume discovery source' || return 1
    assert_equal '001-routing-core' "$(json_field "$output" BRANCH_NAME)" 'resume discovery branch'
}

test_resume_uncommits_exactly_the_parked_wip() {
    local stderr_file="$FIXTURE_ROOT/resume-uncommit.stderr"
    local clone staged_clone spec_tree

    # Given: a parked feature and a fresh clone.
    park_then_clone 'resume-uncommit' "$stderr_file" || return 1
    clone="$RESUME_ROOT"

    # When: resume runs.
    invoke_resume "$clone" "$stderr_file"
    assert_equal '0' "$RESUME_STATUS" 'un-commit resume exit code' || return 1

    # Then: the work is back, nothing is staged, and files absent from HEAD are
    # untracked again.
    spec_tree="$clone/worktrees/001-routing-core/spec"
    assert_equal 'draft' "$(cat "$spec_tree/specs/001-routing-core/spec.md")" 'the parked content is back' || return 1
    assert_equal '' "$(git -C "$spec_tree" diff --cached --name-only)" 'nothing is left staged' || return 1
    if ! git -C "$spec_tree" status --porcelain | grep -q '^?? specs/001-routing-core/'; then
        printf 'assertion failed: the restored file is not untracked\n%s\n' \
            "$(git -C "$spec_tree" status --porcelain)" >&2
        return 1
    fi
    assert_equal '1' "$(git -C "$spec_tree" rev-list --count HEAD..origin/001-routing-core)" \
        'the local branch is exactly one WIP commit behind' || return 1

    # When: another clone resumes with --keep-staged.
    staged_clone="$PARKED_BASE/staged"
    clone_three_leg_root "$PARKED_ROOT" "$staged_clone" || return 1
    invoke_resume "$staged_clone" "$stderr_file" --keep-staged
    assert_equal '0' "$RESUME_STATUS" '--keep-staged resume exit code' || return 1

    # Then: the work is staged instead.
    if ! git -C "$staged_clone/worktrees/001-routing-core/spec" diff --cached --name-only \
        | grep -q '^specs/001-routing-core/spec.md$'; then
        printf 'assertion failed: --keep-staged did not leave the work staged\n%s\n' \
            "$(git -C "$staged_clone/worktrees/001-routing-core/spec" diff --cached --name-only)" >&2
        return 1
    fi
}

test_resume_refuses_on_divergence() {
    local stderr_file="$FIXTURE_ROOT/resume-divergence.stderr"
    local root clone foreign parked_at foreign_tip

    # Given: two parked features, then a foreign commit pushed to the spec
    # origin on the first one's branch.
    initialize_three_leg_parked_fixture 'resume-divergence' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'resume-divergence-ws' || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    create_parked_feature "$root" 'Add label render' "$stderr_file" || return 1
    printf 'draft\n' > "$root/worktrees/001-routing-core/spec/specs/001-routing-core/spec.md" || return 1
    invoke_park "$root" "$stderr_file"
    if [ "$PARK_STATUS" -ne 0 ]; then
        printf 'park failed (%s): %s\n' "$PARK_STATUS" "$(<"$stderr_file")" >&2
        return 1
    fi
    parked_at="$(grep -E '^    parked_at:' "$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml")"
    parked_at="${parked_at#    parked_at: }"
    RESUME_PARKED_SPEC="$(git -C "$root/worktrees/001-routing-core/spec" rev-parse HEAD)"

    foreign="$PARKED_BASE/foreign"
    git clone -q --branch 001-routing-core "$PARKED_SPEC_ORIGIN" "$foreign" || return 1
    git -C "$foreign" config user.name 'Someone else' || return 1
    git -C "$foreign" config user.email 'someone-else@example.invalid' || return 1
    printf 'a foreign commit\n' > "$foreign/foreign.txt" || return 1
    git -C "$foreign" add foreign.txt || return 1
    git -C "$foreign" commit -qm 'foreign work' || return 1
    git -C "$foreign" push -q origin 001-routing-core || return 1
    foreign_tip="$(git -C "$foreign" rev-parse HEAD)"

    clone="$PARKED_BASE/second"
    clone_three_leg_root "$root" "$clone" || return 1

    # When: resume runs in the fresh clone.
    invoke_resume "$clone" "$stderr_file"

    # Then: RR1, byte-for-byte, and nothing was recreated for that feature.
    assert_equal '3' "$RESUME_STATUS" 'divergence resume exit code' || return 1
    assert_contains_block "$stderr_file" \
"Error: 001-routing-core (spec leg) has moved since it was parked; that feature was NOT recreated.
  parked commit  $RESUME_PARKED_SPEC   (parked $parked_at on Fixture)
  current tip    $foreign_tip   (origin/001-routing-core)
Nothing is ever reset over commits this workspace did not park. Reconcile by hand:
  git -C spec fetch origin 001-routing-core
  git -C spec log --oneline $RESUME_PARKED_SPEC..origin/001-routing-core
  git -C spec worktree add -b 001-routing-core worktrees/001-routing-core/spec origin/001-routing-core
  # then decide: rebase the parked WIP onto the new tip, or discard it" 'RR1 wording' || return 1
    assert_file_absent "$clone/worktrees/001-routing-core" 'the diverged feature directory' || return 1
    assert_worktree '002-label-render' "$clone/worktrees/002-label-render/spec" || return 1
    assert_worktree '002-label-render' "$clone/worktrees/002-label-render/code"
}

test_resume_is_idempotent() {
    local stderr_file="$FIXTURE_ROOT/resume-idempotent.stderr"
    local clone spec_tree head_before dirty_before

    # Given: a clone that has already been resumed, with new local work.
    park_then_clone 'resume-idempotent' "$stderr_file" || return 1
    clone="$RESUME_ROOT"
    invoke_resume "$clone" "$stderr_file"
    assert_equal '0' "$RESUME_STATUS" 'first resume exit code' || return 1
    spec_tree="$clone/worktrees/001-routing-core/spec"
    printf 'later work\n' > "$spec_tree/later.txt" || return 1
    head_before="$(git -C "$spec_tree" rev-parse HEAD)"
    dirty_before="$(git -C "$spec_tree" status --porcelain)"

    # When: resume runs again.
    invoke_resume "$clone" "$stderr_file"

    # Then: it says so, creates nothing, and never double-resets.
    assert_equal '0' "$RESUME_STATUS" 'second resume exit code' || return 1
    if ! grep -Fq "[specify] 001-routing-core (spec): worktree already registered at worktrees/001-routing-core/spec; left as it is." "$stderr_file"; then
        printf 'assertion failed: missing RR4 line\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    assert_equal "$head_before" "$(git -C "$spec_tree" rev-parse HEAD)" 'the second resume did not reset' || return 1
    assert_equal "$dirty_before" "$(git -C "$spec_tree" status --porcelain)" 'the second resume left the dirty state alone' || return 1
    assert_equal '2' "$(worktree_record_count "$clone/spec")" 'the second resume created no worktree'
}

test_resume_refuses_a_foreign_directory() {
    local stderr_file="$FIXTURE_ROOT/resume-foreign-dir.stderr"
    local clone intruder

    # Given: a clone with an unrelated directory at the spec leg's target path.
    park_then_clone 'resume-foreign-dir' "$stderr_file" || return 1
    clone="$RESUME_ROOT"
    intruder="$clone/worktrees/001-routing-core/spec"
    mkdir -p "$intruder" || return 1
    printf 'not a worktree\n' > "$intruder/keep.txt" || return 1

    # When: resume runs.
    invoke_resume "$clone" "$stderr_file"

    # Then: RR3, and the intruder's bytes are unchanged.
    assert_equal '2' "$RESUME_STATUS" 'foreign-directory resume exit code' || return 1
    assert_contains_block "$stderr_file" \
"Error: 'worktrees/001-routing-core/spec' exists and is not a registered worktree of the spec leg; that feature was NOT recreated.
Nothing here overwrites a directory it did not create.
  look:  git -C spec worktree list
Move it aside, then re-run \`make resume\`." 'RR3 wording' || return 1
    assert_equal 'not a worktree' "$(cat "$intruder/keep.txt")" 'the foreign directory is unchanged' || return 1
    assert_equal '1' "$(worktree_record_count "$clone/spec")" 'RR3 created no worktree'
}

test_resume_refuses_a_local_branch_that_is_not_the_parked_commit() {
    local stderr_file="$FIXTURE_ROOT/resume-local-branch.stderr"
    local clone local_sha

    # Given: a clone whose spec leg carries the branch with a local commit the
    # parked commit does not contain — DIVERGED, not merely behind.
    park_then_clone 'resume-local-branch' "$stderr_file" || return 1
    clone="$RESUME_ROOT"
    git -C "$clone/spec" checkout -q -b 001-routing-core main || return 1
    printf 'local work\n' > "$clone/spec/local.txt" || return 1
    git -C "$clone/spec" add local.txt || return 1
    git -C "$clone/spec" commit -qm 'local work' || return 1
    git -C "$clone/spec" checkout -q main || return 1
    local_sha="$(git -C "$clone/spec" rev-parse refs/heads/001-routing-core)"

    # When: resume runs.
    invoke_resume "$clone" "$stderr_file"

    # Then: RR5.
    assert_equal '2' "$RESUME_STATUS" 'local-branch resume exit code' || return 1
    assert_contains_block "$stderr_file" \
"Error: the spec leg already has a local branch '001-routing-core' at $local_sha, not the parked commit $RESUME_PARKED_SPEC; that feature was NOT recreated.
  git -C spec log --oneline $RESUME_PARKED_SPEC..001-routing-core
Rename or delete that branch, then re-run \`make resume\`." 'RR5 wording' || return 1
    assert_file_absent "$clone/worktrees/001-routing-core" 'RR5 feature directory'
}

test_resume_refuses_a_local_branch_behind_the_parked_commit() {
    local stderr_file="$FIXTURE_ROOT/resume-behind.stderr"
    local clone local_sha spec_tree

    # Given: a clone whose spec leg carries the branch at an ancestor of the
    # parked commit — this workstation had the feature before the other one
    # parked newer work on it.
    park_then_clone 'resume-behind' "$stderr_file" || return 1
    clone="$RESUME_ROOT"
    git -C "$clone/spec" branch 001-routing-core main || return 1
    local_sha="$(git -C "$clone/spec" rev-parse refs/heads/001-routing-core)"

    # When: resume runs.
    invoke_resume "$clone" "$stderr_file"

    # Then: the remediation is the fast-forward, not a deletion, and nothing
    # was created or reset.
    assert_equal '2' "$RESUME_STATUS" 'behind-branch resume exit code' || return 1
    assert_contains_block "$stderr_file" \
"Error: the spec leg's local branch '001-routing-core' is BEHIND the parked commit ($local_sha is an ancestor of $RESUME_PARKED_SPEC); that feature was NOT recreated.
Fast-forward it, then re-run:
  git -C spec fetch origin 001-routing-core:001-routing-core
  make resume" 'RR5 behind wording' || return 1
    assert_file_absent "$clone/worktrees/001-routing-core" 'behind-branch feature directory' || return 1
    assert_equal "$local_sha" "$(git -C "$clone/spec" rev-parse refs/heads/001-routing-core)" \
        'behind-branch resume moved nothing' || return 1

    # When: the printed command runs, and resume runs again.
    git -C "$clone/spec" fetch -q origin 001-routing-core:001-routing-core || return 1
    invoke_resume "$clone" "$stderr_file"

    # Then: the feature comes back and the parked WIP is un-committed.
    if [ "$RESUME_STATUS" -ne 0 ]; then
        printf 'the replayed resume failed (%s): %s\n' "$RESUME_STATUS" "$(<"$stderr_file")" >&2
        return 1
    fi
    spec_tree="$clone/worktrees/001-routing-core/spec"
    assert_worktree '001-routing-core' "$spec_tree" || return 1
    assert_worktree '001-routing-core' "$clone/worktrees/001-routing-core/code" || return 1
    assert_equal 'draft' "$(cat "$spec_tree/specs/001-routing-core/spec.md")" 'the parked content is back' || return 1
    assert_equal '1' "$(git -C "$spec_tree" rev-list --count HEAD..origin/001-routing-core)" \
        'the replayed resume un-committed the parked WIP'
}

# Hand-edit one leg's `pushed:` in a workspace manifest: `park` writes the
# literal `true` or `false` it computed and `workspace_write_manifest` drops a
# key whose value is empty, so every other state of that field reaches a
# record through an editor or a bad merge, and this is how a fixture reaches
# one. `absent` removes the key; an empty value leaves it bare.
set_manifest_pushed() {
    local manifest="$1"
    local role="$2"
    local value="$3"

    python3 - "$manifest" "$role" "$value" <<'PY'
import sys

path, role, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as stream:
    lines = stream.read().splitlines()
out = []
in_leg = False
edited = 0
for line in lines:
    if line.startswith("          - role:"):
        in_leg = line.split(":", 1)[1].strip() == role
    if in_leg and line.startswith("            pushed:"):
        edited += 1
        if value == "absent":
            continue
        line = "            pushed:" + (" " + value if value else "")
    out.append(line)
if edited != 1:
    raise SystemExit(
        "expected exactly one pushed: line for the %s leg, found %d" % (role, edited)
    )
with open(path, "w", encoding="utf-8") as stream:
    stream.write("\n".join(out) + "\n")
PY
}

# RR6 over the record `park --no-push` actually writes. Its wording is the one
# state of `pushed:` that this extension does write, so it is asserted byte
# for byte and must not move: nothing here is pushed anywhere, which is
# exactly what the refusal is about.
test_resume_refuses_a_no_push_record_in_the_unchanged_words() {
    local stderr_file="$FIXTURE_ROOT/resume-no-push.stderr"
    local root clone manifest parked_spec

    # Given: a feature parked with --no-push, so its commit is on this
    # workstation and nowhere else.
    initialize_three_leg_parked_fixture 'resume-no-push' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'resume-no-push-ws' || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    printf 'draft\n' > "$root/worktrees/001-routing-core/spec/specs/001-routing-core/spec.md" || return 1
    invoke_park "$root" "$stderr_file" --no-push
    if [ "$PARK_STATUS" -ne 0 ]; then
        printf 'the --no-push park failed (%s): %s\n' "$PARK_STATUS" "$(<"$stderr_file")" >&2
        return 1
    fi
    manifest="$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml"
    assert_equal '2' "$(manifest_line_count "$manifest" '^            pushed: false$')" \
        '--no-push recorded pushed: false for both legs' || return 1
    parked_spec="$(git -C "$root/worktrees/001-routing-core/spec" rev-parse HEAD)"

    # When: another checkout resumes it.
    clone="$PARKED_BASE/second"
    clone_three_leg_root "$root" "$clone" || return 1
    invoke_resume "$clone" "$stderr_file"

    # Then: RR6, byte-for-byte, and nothing was recreated.
    assert_equal '2' "$RESUME_STATUS" 'no-push resume exit code' || return 1
    assert_contains_block "$stderr_file" \
"Error: 001-routing-core (spec leg) was parked with --no-push; that feature was NOT recreated.
Its parked commit $parked_spec exists only on the workstation that parked it (Fixture).
Push it there, re-run \`make park\`, then resume here." 'RR6 --no-push wording' || return 1
    if ! printf '%s\n' "$RESUME_OUTPUT" | grep -Fq 'REFUSED: 001-routing-core — parked with --no-push'; then
        printf 'assertion failed: the --no-push summary line\n%s\n' "$RESUME_OUTPUT" >&2
        return 1
    fi
    assert_file_absent "$clone/worktrees/001-routing-core" 'the --no-push feature directory'
}

# A `pushed:` that is neither true nor false is refused exactly as strictly —
# nothing is recreated on a guess — but the refusal says what the record says.
# Reading it as --no-push made a claim nobody made, and told the person the
# parked commit is on one workstation and nowhere else, which the record does
# not say either. A follow-up to a reviewer's note on opensoft/openRepoTools
# #19 and #20 (2026-09-11); nobody has ruled on it.
test_resume_names_an_unreadable_pushed_rather_than_claiming_no_push() {
    local stderr_file="$FIXTURE_ROOT/resume-pushed-unreadable.stderr"
    local clone manifest

    # Given: a parked feature whose spec leg's `pushed:` was hand-edited to a
    # value park never writes.
    park_then_clone 'resume-pushed-unreadable' "$stderr_file" || return 1
    clone="$RESUME_ROOT"
    manifest="$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml"
    set_manifest_pushed "$manifest" spec 'maybe' || return 1

    # When: resume runs there.
    invoke_resume "$clone" "$stderr_file"

    # Then: the refusal names the value, offers the only exit there is, and
    # never says --no-push.
    assert_equal '2' "$RESUME_STATUS" 'unreadable-pushed resume exit code' || return 1
    assert_contains_block "$stderr_file" \
"Error: 001-routing-core (spec leg): its record's \`pushed:\` says 'maybe', which is neither true nor false; that feature was NOT recreated.
Whether its parked commit $RESUME_PARKED_SPEC ever left Fixture cannot be read from the record.
Park it again from there, which writes the record afresh, then resume here." 'RR6 unreadable wording' || return 1
    if grep -Fq -- '--no-push' "$stderr_file"; then
        printf 'assertion failed: an unreadable pushed: drew a --no-push claim\n%s\n' \
            "$(<"$stderr_file")" >&2
        return 1
    fi
    if ! printf '%s\n' "$RESUME_OUTPUT" \
        | grep -Fq "REFUSED: 001-routing-core — its record's \`pushed:\` says 'maybe', which is neither true nor false"; then
        printf 'assertion failed: the unreadable-pushed summary line\n%s\n' "$RESUME_OUTPUT" >&2
        return 1
    fi
    if printf '%s\n' "$RESUME_OUTPUT" | grep -Fq -- '--no-push'; then
        printf 'assertion failed: the summary claimed --no-push\n%s\n' "$RESUME_OUTPUT" >&2
        return 1
    fi
    assert_file_absent "$clone/worktrees/001-routing-core" 'the unreadable-pushed feature directory' || return 1

    # When: the key is bare instead — present, with nothing after the colon.
    set_manifest_pushed "$manifest" spec '' || return 1
    invoke_resume "$clone" "$stderr_file"

    # Then: the same refusal, worded for a key that carries no value.
    assert_equal '2' "$RESUME_STATUS" 'valueless-pushed resume exit code' || return 1
    assert_contains_block "$stderr_file" \
"Error: 001-routing-core (spec leg): its record's \`pushed:\` has no value, which is neither true nor false; that feature was NOT recreated.
Whether its parked commit $RESUME_PARKED_SPEC ever left Fixture cannot be read from the record.
Park it again from there, which writes the record afresh, then resume here." 'RR6 valueless wording' || return 1
    if grep -Fq -- '--no-push' "$stderr_file"; then
        printf 'assertion failed: a bare pushed: drew a --no-push claim\n%s\n' \
            "$(<"$stderr_file")" >&2
        return 1
    fi
    assert_file_absent "$clone/worktrees/001-routing-core" 'the valueless-pushed feature directory'
}

test_manifest_round_trip() {
    local stderr_file="$FIXTURE_ROOT/manifest-round-trip.stderr"
    local root manifest first_bytes second_bytes commits_before
    local expected_manifest actual_manifest

    # Given: a parked feature with WIP in both legs.
    initialize_three_leg_parked_fixture 'manifest-round-trip' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'manifest-round-trip-ws' || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    printf 'draft\n' > "$root/worktrees/001-routing-core/spec/specs/001-routing-core/spec.md" || return 1
    printf 'impl\n' > "$root/worktrees/001-routing-core/code/implementation.txt" || return 1
    invoke_park "$root" "$stderr_file"
    assert_equal '0' "$PARK_STATUS" 'round-trip park exit code' || return 1

    # Then: the file is filed under the org of the project's own repository,
    # so two projects sharing an id in different orgs never share a file.
    manifest="$WORKSPACE_DIR/workspaces/dummy/fixture-project.yaml"
    if [ ! -f "$manifest" ]; then
        printf 'assertion failed: no manifest at the org-namespaced path %s\n' "$manifest" >&2
        find "$WORKSPACE_DIR/workspaces" -type f >&2
        return 1
    fi
    assert_file_absent "$WORKSPACE_DIR/workspaces/fixture-project.yaml" \
        'an un-namespaced manifest' || return 1

    # Then: every field, in a fixed key order.
    expected_manifest="$(cat <<'YAML'
schema_version: 1
kind: workspace-manifest
written_by: speckit park
projects:
  - id: fixture-project
    repository: dummy/fixture-project
    shape: three-leg
    root: root
    tracking_branch: main
    worktree_root: worktrees
    parked_at: <TS>
    parked_on: Fixture
    parked_by_lane: fixture-lane
    active_feature: 001-routing-core
    active_feature_source: state_file
    features:
      - branch: 001-routing-core
        feature_directory: worktrees/001-routing-core/spec/specs/001-routing-core
        legs:
          - role: spec
            remote: origin
            parked_commit: <SHA>
            wip: true
            wip_depth: 1
            pushed: true
          - role: code
            remote: origin
            parked_commit: <SHA>
            wip: true
            wip_depth: 1
            pushed: true
YAML
    )"
    actual_manifest="$(mask_manifest "$manifest")"
    if [ "$expected_manifest" != "$actual_manifest" ]; then
        printf 'assertion failed: the manifest is not the expected shape\n--- expected ---\n%s\n--- actual ---\n%s\n' \
            "$expected_manifest" "$actual_manifest" >&2
        return 1
    fi

    # Then: no value is a host-absolute path.
    if grep -nE ':[[:space:]]+["'"'"']?[~/]' "$manifest"; then
        printf 'assertion failed: the manifest names an absolute path\n' >&2
        return 1
    fi

    # When: park runs again with nothing changed.
    first_bytes="$(cat "$manifest")"
    commits_before="$(commit_count "$WORKSPACE_DIR")"
    invoke_park "$root" "$stderr_file"
    assert_equal '0' "$PARK_STATUS" 'second round-trip park exit code' || return 1

    # Then: the file is byte-identical and no commit was made.
    second_bytes="$(cat "$manifest")"
    if [ "$first_bytes" != "$second_bytes" ]; then
        printf 'assertion failed: an unchanged re-park rewrote the manifest\n--- first ---\n%s\n--- second ---\n%s\n' \
            "$first_bytes" "$second_bytes" >&2
        return 1
    fi
    assert_equal "$commits_before" "$(commit_count "$WORKSPACE_DIR")" 'an unchanged re-park made no commit'
}

test_missing_workspace_config_refuses() {
    local stderr_file="$FIXTURE_ROOT/no-workspace-config.stderr"
    local root empty_home status

    # Given: a created feature and a HOME with no workspace config.
    initialize_three_leg_parked_fixture 'no-workspace-config' "$PARKED_CONFIG" || return 1
    root="$PARKED_ROOT"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    empty_home="$FIXTURE_ROOT/no-workspace-config/empty-home"
    mkdir -p "$empty_home" || return 1

    # When: park runs with nothing to point it at a workspace.
    status=0
    (cd "$root" && env -u SPECKIT_WORKSPACE_PATH -u AGENT_PROTOCOL_ROOT -u SPECKIT_WORKSPACE_REPOSITORY \
        HOME="$empty_home" bash .specify/extensions/git/scripts/bash/park.sh \
        >/dev/null 2>"$stderr_file") || status=$?

    # Then: R1, exit 2, and nothing was created.
    assert_equal '2' "$status" 'no-workspace-config park exit code' || return 1
    assert_contains_block "$stderr_file" \
'Error: no workspace repository is configured; nothing was parked.
park records the feature list in a private repository you own. Name it once in
~/.agents/workspace.yaml:

  repository: <owner>/<repo>
  path: ~/projects/<repo>

Then re-run `make park`.' 'R1 wording for park' || return 1

    # When: resume runs the same way.
    status=0
    (cd "$root" && env -u SPECKIT_WORKSPACE_PATH -u AGENT_PROTOCOL_ROOT -u SPECKIT_WORKSPACE_REPOSITORY \
        HOME="$empty_home" bash .specify/extensions/git/scripts/bash/resume.sh \
        >/dev/null 2>"$stderr_file") || status=$?

    # Then: R1 with resume's verb, exit 2.
    assert_equal '2' "$status" 'no-workspace-config resume exit code' || return 1
    assert_contains_block "$stderr_file" \
'Error: no workspace repository is configured; nothing was resumed.
park records the feature list in a private repository you own. Name it once in
~/.agents/workspace.yaml:

  repository: <owner>/<repo>
  path: ~/projects/<repo>

Then re-run `make resume`.' 'R1 wording for resume' || return 1
    assert_file_absent "$empty_home/.agents" 'no-workspace-config created nothing in HOME' || return 1
    assert_equal '0' "$(commit_count "$root/worktrees/001-routing-core/spec")" \
        'no-workspace-config committed nothing' 2>/dev/null || true
    if [ "$(git -C "$root/worktrees/001-routing-core/spec" log -1 --format=%s)" != 'fixture commit' ]; then
        printf 'assertion failed: a refused park still committed\n' >&2
        return 1
    fi
}

test_two_workstations_share_the_workspace_repository() {
    local stderr_file="$FIXTURE_ROOT/two-workstations.stderr"
    local root second_workspace first_workspace log clone

    # Given: one project and two clones of the workspace repository, with a
    # peer's uncommitted edit sitting in the second one.
    initialize_three_leg_parked_fixture 'two-workstations' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'two-workstations-ws' || return 1
    root="$PARKED_ROOT"
    first_workspace="$WORKSPACE_DIR"
    second_workspace="$FIXTURE_ROOT/two-workstations-ws/workspace-2"
    clone_workspace_fixture "$second_workspace" || return 1
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    printf 'draft\n' > "$root/worktrees/001-routing-core/spec/specs/001-routing-core/spec.md" || return 1

    # When: the first workstation parks.
    invoke_park "$root" "$stderr_file"
    assert_equal '0' "$PARK_STATUS" 'first workstation park exit code' || return 1

    # When: the second workstation parks, over a peer's in-flight edit.
    printf 'a peer was editing this\n' > "$second_workspace/workspaces/peer.yaml" || return 1
    printf 'draft again\n' >> "$root/worktrees/001-routing-core/spec/specs/001-routing-core/spec.md" || return 1
    WORKSPACE_DIR="$second_workspace"
    invoke_park "$root" "$stderr_file"
    WORKSPACE_DIR="$first_workspace"
    assert_equal '0' "$PARK_STATUS" 'second workstation park exit code' || return 1

    # Then: the peer's edit is its own commit, ours rebased on top, and both
    # parks are in the shared history.
    log="$(git -C "$second_workspace" log --format=%s origin/main)"
    if ! printf '%s\n' "$log" | grep -Fq 'park(pre-existing@Fixture): 1 file(s)'; then
        printf 'assertion failed: the pre-existing edit was not its own commit\n%s\n' "$log" >&2
        return 1
    fi
    assert_equal '2' "$(printf '%s\n' "$log" | grep -Fc 'park(fixture-project@Fixture):')" \
        'both parks are in the shared history' || return 1
    if ! grep -Fq 'a peer was editing this' "$second_workspace/workspaces/peer.yaml"; then
        printf 'assertion failed: the peer edit was lost\n' >&2
        return 1
    fi
    assert_equal '' "$(git -C "$second_workspace" status --porcelain -- workspaces)" \
        'the second workspace is clean after the park' || return 1
    assert_file_absent "$second_workspace/.workspaces.lock" 'the mutex was released' || return 1

    # Then: the depth is the BRANCH's, not the stale clone's. The second
    # workstation's clone knew nothing of the first park, so a depth taken
    # from the manifest would have recorded 1 over a two-commit stack.
    if ! grep -Fq '            wip_depth: 2' "$second_workspace/workspaces/dummy/fixture-project.yaml"; then
        printf 'assertion failed: the stacked depth was not recorded\n%s\n' \
            "$(<"$second_workspace/workspaces/dummy/fixture-project.yaml")" >&2
        return 1
    fi
    assert_equal '2' "$(git -C "$root/worktrees/001-routing-core/spec" rev-list --count HEAD ^main)" \
        'two stacked WIP commits on the branch' || return 1

    # Then: a fresh clone resuming from that manifest un-commits BOTH.
    clone="$PARKED_BASE/second-station"
    clone_three_leg_root "$root" "$clone" || return 1
    WORKSPACE_DIR="$second_workspace"
    invoke_resume "$clone" "$stderr_file"
    WORKSPACE_DIR="$first_workspace"
    if [ "$RESUME_STATUS" -ne 0 ]; then
        printf 'the stacked resume failed (%s): %s\n' "$RESUME_STATUS" "$(<"$stderr_file")" >&2
        return 1
    fi
    assert_equal 'fixture commit' \
        "$(git -C "$clone/worktrees/001-routing-core/spec" log -1 --format=%s)" \
        'the stacked resume landed back on the base commit' || return 1
    assert_equal '' "$(git -C "$clone/worktrees/001-routing-core/spec" diff --cached --name-only)" \
        'the stacked resume left nothing staged' || return 1
    if ! git -C "$clone/worktrees/001-routing-core/spec" status --porcelain \
        | grep -q '^?? specs/001-routing-core/'; then
        printf 'assertion failed: the stacked resume did not restore the work\n%s\n' \
            "$(git -C "$clone/worktrees/001-routing-core/spec" status --porcelain)" >&2
        return 1
    fi
}

test_park_against_a_stale_workspace_keeps_a_refused_entry() {
    local stderr_file="$FIXTURE_ROOT/stale-workspace.stderr"
    local root first_workspace stale_workspace manifest parked_001

    # Given: two features parked from one clone of the workspace repository,
    # and a SECOND clone taken before that park — so it knows neither.
    initialize_three_leg_parked_fixture 'stale-workspace' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'stale-workspace-ws' || return 1
    root="$PARKED_ROOT"
    first_workspace="$WORKSPACE_DIR"
    stale_workspace="$FIXTURE_ROOT/stale-workspace-ws/workspace-stale"
    clone_workspace_fixture "$stale_workspace" || return 1
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    create_parked_feature "$root" 'Add label render' "$stderr_file" || return 1
    printf 'draft\n' > "$root/worktrees/001-routing-core/spec/specs/001-routing-core/spec.md" || return 1
    invoke_park "$root" "$stderr_file"
    if [ "$PARK_STATUS" -ne 0 ]; then
        printf 'the first park failed (%s): %s\n' "$PARK_STATUS" "$(<"$stderr_file")" >&2
        return 1
    fi
    parked_001="$(git -C "$root/worktrees/001-routing-core/spec" rev-parse HEAD)"

    # Given: 001 can no longer be parked here — its spec leg worktree is gone.
    git -C "$root/spec" worktree remove --force "$root/worktrees/001-routing-core/spec" || return 1

    # When: park runs against the STALE clone.
    WORKSPACE_DIR="$stale_workspace"
    invoke_park "$root" "$stderr_file"
    WORKSPACE_DIR="$first_workspace"

    # Then: 001 is refused, 002 is parked, and 001's recorded entry SURVIVES —
    # it is the entry the other workstation resumes from.
    assert_equal '3' "$PARK_STATUS" 'stale-workspace park exit code' || return 1
    manifest="$stale_workspace/workspaces/dummy/fixture-project.yaml"
    if ! grep -Fq '      - branch: 001-routing-core' "$manifest"; then
        printf 'assertion failed: the refused feature was erased from the manifest\n%s\n' \
            "$(<"$manifest")" >&2
        return 1
    fi
    if ! grep -Fq "            parked_commit: $parked_001" "$manifest"; then
        printf 'assertion failed: the refused feature lost its parked commit\n%s\n' \
            "$(<"$manifest")" >&2
        return 1
    fi
    grep -Fq '      - branch: 002-label-render' "$manifest" || {
        printf 'assertion failed: the parkable feature was not recorded\n%s\n' "$(<"$manifest")" >&2
        return 1
    }
}

test_park_refuses_a_dirty_workspace_by_name() {
    local stderr_file="$FIXTURE_ROOT/dirty-workspace.stderr"
    local root first_workspace peer_workspace before

    # Given: a workspace clone with an uncommitted edit to a tracked handoff,
    # and an origin that has moved on, so a rebase is actually needed.
    initialize_three_leg_parked_fixture 'dirty-workspace' "$PARKED_CONFIG" || return 1
    initialize_workspace_fixture 'dirty-workspace-ws' || return 1
    root="$PARKED_ROOT"
    first_workspace="$WORKSPACE_DIR"
    mkdir -p "$first_workspace/handoffs" || return 1
    printf 'a handoff\n' > "$first_workspace/handoffs/x.md" || return 1
    git -C "$first_workspace" add handoffs/x.md || return 1
    git -C "$first_workspace" commit -qm 'a handoff' || return 1
    git -C "$first_workspace" push -q origin main || return 1
    peer_workspace="$FIXTURE_ROOT/dirty-workspace-ws/workspace-peer"
    clone_workspace_fixture "$peer_workspace" || return 1
    printf 'a peer commit\n' > "$peer_workspace/handoffs/y.md" || return 1
    git -C "$peer_workspace" add handoffs/y.md || return 1
    git -C "$peer_workspace" commit -qm 'a peer commit' || return 1
    git -C "$peer_workspace" push -q origin main || return 1
    printf 'half-written\n' >> "$first_workspace/handoffs/x.md" || return 1
    before="$(cat "$first_workspace/handoffs/x.md")"
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1

    # When: park runs.
    invoke_park "$root" "$stderr_file"

    # Then: it refuses by name, not with a false rebase conflict, and the
    # half-written handoff is untouched.
    assert_equal '2' "$PARK_STATUS" 'dirty-workspace park exit code' || return 1
    if ! grep -Fq "Error: workspace-dirty: '$first_workspace' has uncommitted changes outside workspaces/, so it cannot be brought up to date; nothing was parked." "$stderr_file"; then
        printf 'assertion failed: missing workspace-dirty refusal\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if ! grep -Fq '  handoffs/x.md' "$stderr_file"; then
        printf 'assertion failed: the refusal did not name the path\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    if grep -Fq 'conflicted' "$stderr_file"; then
        printf 'assertion failed: a dirty checkout was reported as a rebase conflict\n%s\n' \
            "$(<"$stderr_file")" >&2
        return 1
    fi
    assert_equal "$before" "$(cat "$first_workspace/handoffs/x.md")" 'the handoff is untouched' || return 1
    assert_file_absent "$first_workspace/.workspaces.lock" 'the mutex was released' || return 1
    assert_file_absent "$first_workspace/workspaces/dummy" 'a manifest was written anyway'
}

test_resume_rollback_names_the_leg_for_an_attached_worktree() {
    local stderr_file="$FIXTURE_ROOT/rollback-attach.stderr"
    local clone shim_dir spec_tree

    # Given: a clone whose spec leg already carries the branch AT the parked
    # commit but with no worktree — the state the RR5-behind remediation
    # leaves behind — so the spec leg attaches while the code leg creates.
    park_then_clone 'rollback-attach' "$stderr_file" || return 1
    clone="$RESUME_ROOT"
    git -C "$clone/spec" fetch -q origin '001-routing-core:001-routing-core' || return 1
    assert_equal "$RESUME_PARKED_SPEC" \
        "$(git -C "$clone/spec" rev-parse refs/heads/001-routing-core)" \
        'the spec leg branch is at the parked commit' || return 1
    spec_tree="$clone/worktrees/001-routing-core/spec"

    # When: the code leg's worktree add fails, so the run rolls back.
    shim_dir="$FIXTURE_ROOT/rollback-attach-shim"
    install_code_worktree_failure_shim "$shim_dir" || return 1
    RESUME_OUTPUT=''
    RESUME_STATUS=0
    RESUME_OUTPUT="$(cd "$clone" && env \
        SPECKIT_WORKSTATION=Fixture SPECKIT_LANE=fixture-lane \
        SPECKIT_TEST_REAL_GIT="$REAL_GIT" PATH="$shim_dir:$PATH" \
        bash .specify/extensions/git/scripts/bash/resume.sh \
        --workspace "$WORKSPACE_DIR" 2>"$stderr_file")" || RESUME_STATUS=$?

    # Then: the attached spec worktree is really gone — removed through the
    # LEG that registered it, so no phantom registration is left behind for a
    # later resume to read as "already registered".
    assert_equal '2' "$RESUME_STATUS" 'rollback resume exit code' || return 1
    assert_file_absent "$spec_tree" 'the rolled-back spec worktree' || return 1
    if git -C "$clone/spec" worktree list --porcelain | grep -Fq "worktree $spec_tree"; then
        printf 'assertion failed: the spec leg still registers the removed worktree\n%s\n' \
            "$(git -C "$clone/spec" worktree list --porcelain)" >&2
        return 1
    fi
    assert_equal '1' "$(worktree_record_count "$clone/spec")" 'the spec leg has only its own checkout' || return 1

    # Then: the branch the run did NOT create is still there.
    assert_equal "$RESUME_PARKED_SPEC" \
        "$(git -C "$clone/spec" rev-parse refs/heads/001-routing-core)" \
        'the pre-existing branch was not deleted'
}

test_per_org_workspace_override() {
    local stderr_file="$FIXTURE_ROOT/org-override.stderr"
    local root home config default_workspace override_workspace status other_root

    # Given: a default workspace, a second workspace for the 'dummy' org, and a
    # user config that names both.
    initialize_three_leg_parked_fixture 'org-override' "$PARKED_CONFIG" || return 1
    root="$PARKED_ROOT"
    initialize_workspace_fixture 'org-override-default' || return 1
    default_workspace="$WORKSPACE_DIR"
    initialize_workspace_fixture 'org-override-dummy' || return 1
    override_workspace="$WORKSPACE_DIR"
    home="$FIXTURE_ROOT/org-override/home"
    config="$home/.agents/workspace.yaml"
    mkdir -p "$home/.agents" || return 1
    {
        printf 'repository: fixture/default-wip\n'
        printf 'path: %s\n' "$default_workspace"
        printf 'orgs:\n'
        printf '  dummy:\n'
        printf '    repository: dummy/dummy-wip\n'
        printf '    path: %s\n' "$override_workspace"
    } > "$config" || return 1
    create_parked_feature "$root" 'Add routing core' "$stderr_file" || return 1
    printf 'draft\n' > "$root/worktrees/001-routing-core/spec/specs/001-routing-core/spec.md" || return 1

    # When: park runs with nothing but the config to go on.
    status=0
    (cd "$root" && env -u SPECKIT_WORKSPACE_PATH -u SPECKIT_WORKSPACE_REPOSITORY \
        -u AGENT_PROTOCOL_ROOT HOME="$home" \
        SPECKIT_WORKSTATION=Fixture SPECKIT_LANE=fixture-lane \
        bash .specify/extensions/git/scripts/bash/park.sh \
        > "$stderr_file.out" 2>"$stderr_file") || status=$?

    # Then: the org's own repository holds the manifest, and the default does
    # not hold it at all.
    if [ "$status" -ne 0 ]; then
        printf 'override park failed (%s): %s\n' "$status" "$(<"$stderr_file")" >&2
        return 1
    fi
    if [ ! -f "$override_workspace/workspaces/dummy/fixture-project.yaml" ]; then
        printf 'assertion failed: the org override repository has no manifest\n' >&2
        find "$override_workspace/workspaces" -type f >&2
        return 1
    fi
    assert_file_absent "$default_workspace/workspaces/dummy" \
        'the default workspace received the override org' || return 1
    if ! grep -Fq "WORKSPACE: $override_workspace (orgs.dummy override)" "$stderr_file.out"; then
        printf 'assertion failed: park did not name the override\n%s\n' "$(<"$stderr_file.out")" >&2
        return 1
    fi

    # When: a project in another org parks with the same config.
    initialize_three_leg_parked_fixture 'org-override-other' "$PARKED_CONFIG" || return 1
    other_root="$PARKED_ROOT"
    set_assembly_repository "$other_root" 'otherorg/fixture-project' || return 1
    create_parked_feature "$other_root" 'Add routing core' "$stderr_file" || return 1
    status=0
    (cd "$other_root" && env -u SPECKIT_WORKSPACE_PATH -u SPECKIT_WORKSPACE_REPOSITORY \
        -u AGENT_PROTOCOL_ROOT HOME="$home" \
        SPECKIT_WORKSTATION=Fixture SPECKIT_LANE=fixture-lane \
        bash .specify/extensions/git/scripts/bash/park.sh \
        > "$stderr_file.out" 2>"$stderr_file") || status=$?

    # Then: it lands in the default workspace, under its own org.
    if [ "$status" -ne 0 ]; then
        printf 'default park failed (%s): %s\n' "$status" "$(<"$stderr_file")" >&2
        return 1
    fi
    if [ ! -f "$default_workspace/workspaces/otherorg/fixture-project.yaml" ]; then
        printf 'assertion failed: the default workspace has no manifest for the other org\n' >&2
        find "$default_workspace/workspaces" -type f >&2
        return 1
    fi
    if ! grep -Fq "WORKSPACE: $default_workspace (default)" "$stderr_file.out"; then
        printf 'assertion failed: park did not name the default\n%s\n' "$(<"$stderr_file.out")" >&2
        return 1
    fi

    # When: --workspace is given as well.
    WORKSPACE_DIR="$default_workspace"
    invoke_park "$root" "$stderr_file"
    assert_equal '0' "$PARK_STATUS" '--workspace park exit code' || return 1

    # Then: it beats the override.
    if [ ! -f "$default_workspace/workspaces/dummy/fixture-project.yaml" ]; then
        printf 'assertion failed: --workspace did not beat the org override\n' >&2
        return 1
    fi
    if ! printf '%s\n' "$PARK_OUTPUT" | grep -Fq "WORKSPACE: $default_workspace (--workspace)"; then
        printf 'assertion failed: park did not name --workspace\n%s\n' "$PARK_OUTPUT" >&2
        return 1
    fi

    # When: the config spells the org in another case. GitHub org names are
    # case-insensitive, and routing a confidential org's manifest to the
    # DEFAULT workspace over a capital letter is the failure this exists to
    # prevent.
    initialize_three_leg_parked_fixture 'org-override-case' "$PARKED_CONFIG" || return 1
    other_root="$PARKED_ROOT"
    create_parked_feature "$other_root" 'Add routing core' "$stderr_file" || return 1
    {
        printf 'repository: fixture/default-wip\n'
        printf 'path: %s\n' "$default_workspace"
        printf 'orgs:\n'
        printf '  DuMmY:\n'
        printf '    repository: DuMmY/dummy-wip\n'
        printf '    path: %s\n' "$override_workspace"
    } > "$config" || return 1
    rm -rf "$override_workspace/workspaces/dummy" || return 1
    git -C "$override_workspace" commit -q -am 'drop the manifest' >/dev/null 2>&1 || true
    status=0
    (cd "$other_root" && env -u SPECKIT_WORKSPACE_PATH -u SPECKIT_WORKSPACE_REPOSITORY \
        -u AGENT_PROTOCOL_ROOT HOME="$home" \
        SPECKIT_WORKSTATION=Fixture SPECKIT_LANE=fixture-lane \
        bash .specify/extensions/git/scripts/bash/park.sh \
        > "$stderr_file.out" 2>"$stderr_file") || status=$?

    # Then: the override wins, and the directory keeps the ONE canonical
    # spelling — the owner segment as written in repository:.
    if [ "$status" -ne 0 ]; then
        printf 'case-folded park failed (%s): %s\n' "$status" "$(<"$stderr_file")" >&2
        return 1
    fi
    if [ ! -f "$override_workspace/workspaces/dummy/fixture-project.yaml" ]; then
        printf 'assertion failed: a differently-cased org key did not reach the override\n' >&2
        find "$override_workspace/workspaces" "$default_workspace/workspaces" -type f >&2
        return 1
    fi
    if ! grep -Fq "WORKSPACE: $override_workspace (orgs.dummy override)" "$stderr_file.out"; then
        printf 'assertion failed: park did not name the case-folded override\n%s\n' \
            "$(<"$stderr_file.out")" >&2
        return 1
    fi

    # When: the orgs: block is malformed.
    {
        printf 'repository: fixture/default-wip\n'
        printf 'path: %s\n' "$default_workspace"
        printf 'orgs:\n'
        printf '  dummy: %s\n' "$override_workspace"
    } > "$config" || return 1
    status=0
    (cd "$root" && env -u SPECKIT_WORKSPACE_PATH -u SPECKIT_WORKSPACE_REPOSITORY \
        -u AGENT_PROTOCOL_ROOT HOME="$home" \
        bash .specify/extensions/git/scripts/bash/park.sh \
        >/dev/null 2>"$stderr_file") || status=$?

    # Then: it refuses by name rather than falling back to the default.
    assert_equal '2' "$status" 'malformed orgs: exit code' || return 1
    if ! grep -Fq "Error: workspace-config-invalid: the orgs: block in $config is malformed (org 'dummy' must be a block with repository: and path:); nothing was parked." "$stderr_file"; then
        printf 'assertion failed: missing workspace-config-invalid refusal\n%s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    status=0
    (cd "$root" && env -u SPECKIT_WORKSPACE_PATH -u AGENT_PROTOCOL_ROOT HOME="$home" \
        bash .specify/extensions/git/scripts/bash/resume.sh \
        >/dev/null 2>"$stderr_file") || status=$?
    assert_equal '2' "$status" 'malformed orgs: resume exit code' || return 1
    grep -Fq 'nothing was resumed.' "$stderr_file"
}

test_single_repo_park_and_resume() {
    local stderr_file="$FIXTURE_ROOT/single-park.stderr"
    local base repo origin clone worktree branch manifest

    # Given: a single-repository Speckit checkout with a bare origin and one
    # feature worktree carrying WIP.
    base="$FIXTURE_ROOT/single-park"
    repo="$base/single"
    origin="$base/single-origin.git"
    mkdir -p "$base" || return 1
    initialize_fixture "$repo" $'checkout_mode: worktree\nbase_branch: main' || return 1
    install_park_scripts "$repo" || return 1
    git -C "$repo" add -A || return 1
    git -C "$repo" commit -qm 'install park scripts' || return 1
    init_bare_repo "$origin" || return 1
    git -C "$repo" remote add origin "$origin" || return 1
    git -C "$repo" push -q -u origin main || return 1
    initialize_workspace_fixture 'single-park-ws' || return 1

    if ! create_parked_feature "$repo" 'Add routing core' "$stderr_file"; then
        printf 'single-repo feature creation failed: %s\n' "$(<"$stderr_file")" >&2
        return 1
    fi
    branch='001-routing-core'
    worktree="$base/single-worktrees/$branch"
    assert_worktree "$branch" "$worktree" || return 1
    printf 'draft\n' > "$worktree/notes.txt" || return 1

    # When: park runs at the repository root.
    invoke_park "$repo" "$stderr_file"
    if [ "$PARK_STATUS" -ne 0 ]; then
        printf 'single-repo park failed (%s): %s\n' "$PARK_STATUS" "$(<"$stderr_file")" >&2
        return 1
    fi

    # Then: one leg, recorded as role: repo, in a manifest named for the
    # repository directory, under the "local" org: a single-repository fixture
    # declares no owner and nothing invents one.
    manifest="$WORKSPACE_DIR/workspaces/local/single.yaml"
    if [ ! -f "$manifest" ]; then
        printf 'assertion failed: no manifest at %s\n' "$manifest" >&2
        return 1
    fi
    grep -Fq '    shape: single' "$manifest" || {
        printf 'assertion failed: shape single\n%s\n' "$(<"$manifest")" >&2
        return 1
    }
    assert_equal '1' "$(manifest_line_count "$manifest" '^          - role: repo$')" \
        'single-repo leg role' || return 1
    if grep -Fq 'feature_directory:' "$manifest"; then
        printf 'assertion failed: a single-repository manifest recorded a feature_directory\n' >&2
        return 1
    fi

    # When: a fresh clone resumes it. A single-repository project is named by
    # its directory, so the second checkout carries the same directory name.
    mkdir -p "$base/second" || return 1
    clone="$base/second/single"
    git clone -q "$origin" "$clone" || return 1
    git -C "$clone" config user.name 'Spec Kit test' || return 1
    git -C "$clone" config user.email 'spec-kit-test@example.invalid' || return 1
    invoke_resume "$clone" "$stderr_file"
    if [ "$RESUME_STATUS" -ne 0 ]; then
        printf 'single-repo resume failed (%s): %s\n' "$RESUME_STATUS" "$(<"$stderr_file")" >&2
        return 1
    fi

    # Then: the worktree is back, the WIP un-committed, no feature.json, and
    # the state file restored.
    assert_worktree "$branch" "$base/second/single-worktrees/$branch" || return 1
    assert_equal 'draft' "$(cat "$base/second/single-worktrees/$branch/notes.txt")" 'the parked content is back' || return 1
    assert_file_absent "$clone/.specify/feature.json" 'a single-repository feature.json' || return 1
    assert_equal "$branch" \
        "$(json_field "$(<"$clone/.git/speckit-last-worktree.json")" BRANCH_NAME)" \
        'single-repo state file'
}

# The vendored openRepoShape copies — including the manifest template this
# suite derives its three-leg fixture from — are pinned by commit and per-file
# sha256. Checking them HERE and not only in CI is what makes an edited copy
# red for the developer who edited it, before the push. `check` writes nothing
# and needs no network, which is why it can run inside the read-only mounts of
# the Bash 3.2 and Git 2.34.1 jobs. Its own report is suppressed on success;
# a finding goes to stderr and reaches the log.
test_vendored_copies_match_their_pins() {
    python3 "$UPDATE_UPSTREAM_FILE" check >/dev/null
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

run_scenario 'the vendored openRepoShape copies match devBenches/base-image/upstream-pin.yaml' \
    test_vendored_copies_match_their_pins
run_scenario 'default sequential worktree with apostrophe description' test_default_sequential_worktree
run_scenario 'branch_template with {number}-{slug} final segment' test_branch_template
run_scenario 'namespaced sequential numbering' test_namespaced_numbering
run_scenario 'root numbering ignores namespaced branches' test_root_numbering_ignores_namespaces
run_scenario 'preservation of explicit configuration' test_explicit_configuration
run_scenario 'concurrent sequential creators reserve unique numbers' test_concurrent_sequential_number_reservations
run_scenario 'released reservation stale scan retries after branch publication' test_released_reservation_stale_scan_retry
run_scenario 'number reservations clean up and unrelated update-ref failures are fatal' test_number_reservation_cleanup_and_update_failures
run_scenario 'orphan reservations create scope-local gaps' test_orphan_reservation_gap_and_scope_isolation
run_scenario 'non-automatic numbering paths do not reserve' test_non_reserving_numbering_paths
run_scenario 'parent worktree root excludes the primary checkout' test_parent_root_excludes_primary_checkout
run_scenario 'state requires an exact registered in-root worktree' test_state_requires_registered_in_root_worktree
run_scenario 'malformed and symlinked state fall back without following links' test_malformed_and_symlinked_state_fall_back_safely
run_scenario 'JSON output fails closed without an encoder' test_json_output_requires_encoder
run_scenario 'shared worktree discovery preserves special paths across NUL and line porcelain' test_registered_namespaced_worktree_discovery
run_scenario 'line porcelain allow-existing reuses a special-byte path' test_line_porcelain_allow_existing_reuses_special_path
run_scenario 'legacy line porcelain rejects a path line that impersonates HEAD' test_line_porcelain_head_collision_does_not_fabricate_a_worktree
run_scenario 'legacy line porcelain must not reject an ordinary newline path without a HEAD collision' test_line_porcelain_ordinary_newline_path_still_round_trips
run_scenario 'legacy line porcelain decodes Git C-quoted worktree paths byte-exactly' test_line_porcelain_c_quoted_path_decodes_byte_exactly
run_scenario 'legacy line porcelain rejects malformed Git C quoting' test_line_porcelain_malformed_c_quotes_fail_closed
run_scenario 'legacy line porcelain rejects directory and forged candidates without Git corroboration' test_line_porcelain_candidates_without_git_corroboration_are_not_worktrees
run_scenario 'Git discovery failures are not reported as zero records' test_discovery_failure_is_not_reported_as_zero_records
run_scenario 'fallback root detection ignores decoy directories' test_fallback_root_ignores_decoy_directories
run_scenario 'explicit decoy-only root reports no registered worktrees' test_explicit_decoy_only_root_reports_no_worktrees
run_scenario 'three-leg feature creates a worktree in both legs and none at the root' test_three_leg_creates_both_leg_worktrees
run_scenario 'three-leg dry run creates nothing' test_three_leg_dry_run_creates_nothing
run_scenario 'three-leg refuses branch checkout mode' test_three_leg_refuses_branch_checkout_mode
run_scenario 'three-leg refuses an uninitialised leg' test_three_leg_refuses_uninitialised_leg
run_scenario 'three-leg refuses an existing feature directory' test_three_leg_refuses_existing_feature_directory
run_scenario 'three-leg rolls back the spec leg when the code leg fails' test_three_leg_rolls_back_when_code_leg_fails
run_scenario 'three-leg discovery reports the feature and both leg worktrees' test_three_leg_get_last_worktree_reports_feature
run_scenario 'three-leg auto-commit commits both legs and never the root' test_three_leg_auto_commit_commits_both_legs_only
run_scenario 'park commits and pushes a WIP commit in both legs and never at the root' test_park_commits_and_pushes_both_legs
run_scenario 'park with nothing uncommitted makes no commit' test_park_clean_feature_makes_no_commit
run_scenario 'park enumerates from git worktree list, not feature.json' test_park_enumerates_from_git_not_feature_json
run_scenario 'park refuses a leg with no origin remote' test_park_refuses_a_leg_without_origin
run_scenario 'park refuses a rebase in progress and commits nothing there' test_park_refuses_a_rebase_in_progress
run_scenario 'park refuses a rejected push and keeps the WIP commit' test_park_refuses_a_rejected_push_and_keeps_the_wip_commit
run_scenario 'park stacks a second WIP commit without a force-push' test_park_stacks_a_second_wip_without_a_force_push
run_scenario 'park --dry-run writes nothing' test_park_dry_run_writes_nothing
run_scenario 'resume recreates the worktrees, feature.json and the state file' test_resume_recreates_worktrees_feature_json_and_state
run_scenario 'resume un-commits exactly the parked WIP' test_resume_uncommits_exactly_the_parked_wip
run_scenario 'resume refuses on divergence with the exact wording' test_resume_refuses_on_divergence
run_scenario 'resume is idempotent when the worktrees already exist' test_resume_is_idempotent
run_scenario 'resume refuses a foreign directory at the worktree path' test_resume_refuses_a_foreign_directory
run_scenario 'resume refuses a local branch that diverged from the parked commit' test_resume_refuses_a_local_branch_that_is_not_the_parked_commit
run_scenario 'resume refuses a local branch behind the parked commit and names the fast-forward' test_resume_refuses_a_local_branch_behind_the_parked_commit
run_scenario 'resume refuses a --no-push record in the unchanged wording' test_resume_refuses_a_no_push_record_in_the_unchanged_words
run_scenario 'resume names a pushed: that is neither true nor false and never claims --no-push' test_resume_names_an_unreadable_pushed_rather_than_claiming_no_push
run_scenario 'the workspace manifest round-trips byte-identically' test_manifest_round_trip
run_scenario 'a missing workspace config refuses both verbs' test_missing_workspace_config_refuses
run_scenario 'two workstations share one workspace repository' test_two_workstations_share_the_workspace_repository
run_scenario 'park against a stale workspace keeps a refused feature entry' test_park_against_a_stale_workspace_keeps_a_refused_entry
run_scenario 'park refuses a dirty workspace by name, not as a rebase conflict' test_park_refuses_a_dirty_workspace_by_name
run_scenario "resume's rollback removes an attached worktree through its own leg" test_resume_rollback_names_the_leg_for_an_attached_worktree
run_scenario 'a per-org workspace override keeps that org out of the default repository' test_per_org_workspace_override
run_scenario 'single-repository park and resume' test_single_repo_park_and_resume

if [ "$failures" -ne 0 ]; then
    printf 'RED: Speckit Git feature behavior tests failed: %d scenario(s)\n' "$failures" >&2
    exit 1
fi

printf 'GREEN: Speckit Git feature behavior tests passed\n'
