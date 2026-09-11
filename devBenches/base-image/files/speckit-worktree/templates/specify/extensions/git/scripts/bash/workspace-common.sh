#!/usr/bin/env bash
# speckit-overlay-shape: 1
# Workspace helpers for park.sh and resume.sh.
#
# Sourced, never executed: this file sets no shell options and runs nothing at
# load time. It requires git-common.sh to have been sourced first, for
# _shape_set_trimmed and _shape_set_scalar.
#
# The workspace is the PRIVATE repository the person owns and names once in
# ${AGENT_PROTOCOL_ROOT:-$HOME/.agents}/workspace.yaml. Its workspaces/
# directory holds one manifest per family or standalone project. Nothing here
# reads or writes a handoff document, and nothing here ever force-pushes:
# park.sh owns the single leased push in this object, behind
# --retire-parked-wip.
#
# shellcheck disable=SC2034  # the WORKSPACE_* and MANIFEST_* results are
# consumed by the scripts that source this file.

WORKSPACE_LOCK_DIR=""

# The user-level config path, honouring AGENT_PROTOCOL_ROOT the way
# setup-openspeckit does.
workspace_config_file() {
    printf '%s\n' "${AGENT_PROTOCOL_ROOT:-$HOME/.agents}/workspace.yaml"
}

# Read one indent-zero scalar out of a small YAML file with parameter
# expansion only: no YAML library, no Python per line, no forks per line. This
# is load_repo_shape's reader, narrowed to top-level keys.
workspace_read_scalar() {
    local file="$1"
    local want="$2"
    local raw content trimmed indent_ws key

    WORKSPACE_SCALAR=""
    [ -f "$file" ] || return 1
    while IFS= read -r raw || [ -n "$raw" ]; do
        content="${raw%%#*}"
        _shape_set_trimmed "$content"
        trimmed="$_SHAPE_TRIMMED"
        [ -n "$trimmed" ] || continue
        indent_ws="${content%%[![:space:]]*}"
        [ "${#indent_ws}" -eq 0 ] || continue
        key="${trimmed%%:*}"
        [ "$key" != "$trimmed" ] || continue
        [ "$key" = "$want" ] || continue
        _shape_set_scalar "${trimmed#*:}"
        WORKSPACE_SCALAR="$_SHAPE_SCALAR"
        return 0
    done < "$file"
    return 1
}

# True when a family manifest's members: block names this project id. Read the
# same way: the block is every line indented deeper than the members: key.
workspace_members_contains() {
    local file="$1"
    local want="$2"
    local raw content trimmed indent_ws indent key in_members=false

    [ -f "$file" ] || return 1
    while IFS= read -r raw || [ -n "$raw" ]; do
        content="${raw%%#*}"
        _shape_set_trimmed "$content"
        trimmed="$_SHAPE_TRIMMED"
        [ -n "$trimmed" ] || continue
        indent_ws="${content%%[![:space:]]*}"
        indent=${#indent_ws}
        if [ "$indent" -eq 0 ]; then
            key="${trimmed%%:*}"
            if [ "$key" != "$trimmed" ] && [ "$key" = "members" ]; then
                in_members=true
            else
                in_members=false
            fi
            continue
        fi
        [ "$in_members" = true ] || continue
        _shape_set_trimmed "${trimmed#- }"
        trimmed="$_SHAPE_TRIMMED"
        key="${trimmed%%:*}"
        [ "$key" != "$trimmed" ] || continue
        [ "$key" = "id" ] || continue
        _shape_set_scalar "${trimmed#*:}"
        [ "$_SHAPE_SCALAR" = "$want" ] || continue
        return 0
    done < "$file"
    return 1
}

# shellcheck disable=SC2088  # a literal leading ~ is what is matched here
# ---------------------------------------------------------------------------
# The optional per-org override in the user config.
#
#   repository: opensoft/brett-wip
#   path: ~/projects/brett-wip
#   orgs:
#     MedxSoft:
#       repository: MedxSoft/brett-wip
#       path: ~/projects/MedxSoft-wip
#
# Returns 0 and sets WORKSPACE_ORG_PATH / WORKSPACE_ORG_REPOSITORY when <org>
# has an override, 1 when there is no orgs: block or no entry for it, and 2
# when the block is malformed, with the reason in WORKSPACE_CONFIG_ERROR. A
# malformed block is a REFUSAL and never a silent fall-through to the default:
# indexing a confidential org's work in the wrong repository is the one thing
# this override exists to prevent.
# ---------------------------------------------------------------------------
workspace_read_org_override() {
    local file="$1"
    local want="$2"
    local raw content trimmed indent_ws indent key value
    local in_orgs=false org_col=-1 key_col=-1
    local current="" current_folded="" found=false
    local found_repository="" found_path="" want_folded

    # GitHub org names are case-insensitive, so `orgs: medxsoft:` must match a
    # `repository: MedxSoft/...`. Routing a confidential org's manifest to the
    # DEFAULT workspace over a capital letter is the one failure this override
    # exists to prevent.
    want_folded="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')"
    WORKSPACE_ORG_PATH=""
    WORKSPACE_ORG_REPOSITORY=""
    WORKSPACE_CONFIG_ERROR=""
    [ -n "$want" ] || return 1
    [ -f "$file" ] || return 1

    while IFS= read -r raw || [ -n "$raw" ]; do
        content="${raw%%#*}"
        _shape_set_trimmed "$content"
        trimmed="$_SHAPE_TRIMMED"
        [ -n "$trimmed" ] || continue
        indent_ws="${content%%[![:space:]]*}"
        indent=${#indent_ws}

        if [ "$indent" -eq 0 ]; then
            [ "$in_orgs" = false ] || break
            key="${trimmed%%:*}"
            [ "$key" != "$trimmed" ] || continue
            [ "$key" = "orgs" ] || continue
            _shape_set_scalar "${trimmed#*:}"
            if [ -n "$_SHAPE_SCALAR" ]; then
                WORKSPACE_CONFIG_ERROR="orgs: must be a map of org names, not a scalar"
                return 2
            fi
            in_orgs=true
            org_col=-1
            key_col=-1
            continue
        fi

        [ "$in_orgs" = true ] || continue

        case "$trimmed" in
            '-'|'- '*)
                WORKSPACE_CONFIG_ERROR="orgs: must be a map of org names, not a list"
                return 2
                ;;
        esac
        key="${trimmed%%:*}"
        if [ "$key" = "$trimmed" ]; then
            WORKSPACE_CONFIG_ERROR="'$trimmed' is not a 'key: value' line"
            return 2
        fi
        _shape_set_scalar "${trimmed#*:}"
        value="$_SHAPE_SCALAR"

        [ "$org_col" -ge 0 ] || org_col=$indent
        if [ "$indent" -lt "$org_col" ]; then
            WORKSPACE_CONFIG_ERROR="'$key' is indented above the org names"
            return 2
        fi
        if [ "$indent" -eq "$org_col" ]; then
            if [ -n "$value" ]; then
                WORKSPACE_CONFIG_ERROR="org '$key' must be a block with repository: and path:"
                return 2
            fi
            current="$key"
            current_folded="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
            key_col=-1
            continue
        fi
        if [ -z "$current" ]; then
            WORKSPACE_CONFIG_ERROR="'$key' appears before any org name"
            return 2
        fi
        [ "$key_col" -ge 0 ] || key_col=$indent
        if [ "$indent" -ne "$key_col" ]; then
            WORKSPACE_CONFIG_ERROR="'$key' is indented inconsistently under '$current'"
            return 2
        fi
        case "$key" in
            repository|path) ;;
            *)
                WORKSPACE_CONFIG_ERROR="'$key' is not a key of an org override; only repository: and path: are"
                return 2
                ;;
        esac
        if [ -z "$value" ]; then
            WORKSPACE_CONFIG_ERROR="'$key' under '$current' has no value"
            return 2
        fi
        if [ "$current_folded" = "$want_folded" ]; then
            found=true
            case "$key" in
                repository) found_repository="$value" ;;
                path) found_path="$value" ;;
            esac
        fi
    done < "$file"

    [ "$found" = true ] || return 1
    if [ -z "$found_path" ]; then
        WORKSPACE_CONFIG_ERROR="org '$want' has no path:"
        return 2
    fi
    WORKSPACE_ORG_PATH="$found_path"
    WORKSPACE_ORG_REPOSITORY="$found_repository"
    return 0
}

# shellcheck disable=SC2088  # a literal leading ~ is what is matched here
workspace_expand_home() {
    local path="$1"

    case "$path" in
        '~') printf '%s\n' "$HOME" ;;
        '~/'*) printf '%s\n' "$HOME/${path#\~/}" ;;
        *) printf '%s\n' "$path" ;;
    esac
}

# Which workspace checkout this project is recorded in, for a project whose
# org is <org>. THE RESOLVED ORDER:
#
#   1. --workspace <path>          wins over everything
#   2. $SPECKIT_WORKSPACE_PATH     a whole-run override
#   3. orgs.<org> in the config    an org whose work must stay inside that org
#   4. the config's top-level      the default workspace
#   5. nothing                     R1
#
# Returns 1 when nothing names a path (the caller prints R1) and 2 when the
# config's orgs: block is malformed (the caller prints workspace-config-invalid).
workspace_resolve() {
    local cli_path="$1"
    local org="$2"
    local override_status=0

    WORKSPACE_PATH=""
    WORKSPACE_REPOSITORY=""
    WORKSPACE_SOURCE=""
    WORKSPACE_SOURCE_LABEL=""
    WORKSPACE_CONFIG_FILE="$(workspace_config_file)"

    if [ -n "$cli_path" ]; then
        WORKSPACE_PATH="$(workspace_expand_home "$cli_path")"
        WORKSPACE_SOURCE="--workspace"
        WORKSPACE_SOURCE_LABEL="--workspace"
    elif [ -n "${SPECKIT_WORKSPACE_PATH:-}" ]; then
        WORKSPACE_PATH="$(workspace_expand_home "$SPECKIT_WORKSPACE_PATH")"
        WORKSPACE_SOURCE="SPECKIT_WORKSPACE_PATH"
        WORKSPACE_SOURCE_LABEL="SPECKIT_WORKSPACE_PATH"
    else
        override_status=0
        workspace_read_org_override "$WORKSPACE_CONFIG_FILE" "$org" || override_status=$?
        [ "$override_status" -ne 2 ] || return 2
        if [ "$override_status" -eq 0 ]; then
            WORKSPACE_PATH="$(workspace_expand_home "$WORKSPACE_ORG_PATH")"
            WORKSPACE_REPOSITORY="$WORKSPACE_ORG_REPOSITORY"
            WORKSPACE_SOURCE="$WORKSPACE_CONFIG_FILE"
            WORKSPACE_SOURCE_LABEL="orgs.$org override"
        elif workspace_read_scalar "$WORKSPACE_CONFIG_FILE" path \
            && [ -n "$WORKSPACE_SCALAR" ]; then
            WORKSPACE_PATH="$(workspace_expand_home "$WORKSPACE_SCALAR")"
            WORKSPACE_SOURCE="$WORKSPACE_CONFIG_FILE"
            WORKSPACE_SOURCE_LABEL="default"
        else
            return 1
        fi
    fi

    # R2's remediation must name the clone command for the repository that was
    # actually chosen, so a fresh machine is told which <org>/<user>-wip to get.
    if [ -n "${SPECKIT_WORKSPACE_REPOSITORY:-}" ]; then
        WORKSPACE_REPOSITORY="$SPECKIT_WORKSPACE_REPOSITORY"
    elif [ -z "$WORKSPACE_REPOSITORY" ] \
        && workspace_read_scalar "$WORKSPACE_CONFIG_FILE" repository; then
        WORKSPACE_REPOSITORY="$WORKSPACE_SCALAR"
    fi
    return 0
}

workspace_is_checkout() {
    local path="$1"

    [ -d "$path" ] || return 1
    { [ -d "$path/.git" ] || [ -f "$path/.git" ]; } || return 1
    git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# R1. The remediation names ~/.agents/workspace.yaml literally, because that
# is the path a person types; AGENT_PROTOCOL_ROOT moves the file for a
# non-standard install and workspace_config_file follows it.
workspace_refuse_no_config() {
    local past="$1"
    local verb="$2"

    >&2 echo "Error: no workspace repository is configured; nothing was $past."
    >&2 echo "park records the feature list in a private repository you own. Name it once in"
    # shellcheck disable=SC2088  # the literal path a person types, not a glob
    >&2 echo "~/.agents/workspace.yaml:"
    >&2 echo ""
    >&2 echo "  repository: <owner>/<repo>"
    >&2 echo "  path: ~/projects/<repo>"
    >&2 echo ""
    >&2 echo "Then re-run \`make $verb\`."
}

# workspace-config-invalid.
workspace_refuse_invalid_config() {
    local past="$1"
    local verb="$2"

    >&2 echo "Error: workspace-config-invalid: the orgs: block in $WORKSPACE_CONFIG_FILE is malformed ($WORKSPACE_CONFIG_ERROR); nothing was $past."
    >&2 echo "An org override is two keys under the org's name:"
    >&2 echo ""
    >&2 echo "  orgs:"
    >&2 echo "    <Org>:"
    >&2 echo "      repository: <owner>/<repo>"
    >&2 echo "      path: ~/projects/<repo>"
    >&2 echo ""
    >&2 echo "Refusing rather than falling back to the default workspace: a confidential org's work"
    >&2 echo "must never be indexed in the wrong repository. Fix the file, then re-run \`make $verb\`."
}

# R2.
workspace_refuse_not_a_checkout() {
    local past="$1"
    local repository="$WORKSPACE_REPOSITORY"

    [ -n "$repository" ] || repository="<owner>/<repo>"
    >&2 echo "Error: '$WORKSPACE_PATH', named by $WORKSPACE_SOURCE as your workspace checkout, is not a Git checkout; nothing was $past."
    >&2 echo "Remediation: git clone git@github.com:$repository.git $WORKSPACE_PATH"
}

# The workstation name, in Rule 10's spelling. SPECKIT_WORKSTATION is the
# override the tests use; nothing is ever guessed from a window name.
workspace_workstation() {
    local name=""

    if [ -n "${SPECKIT_WORKSTATION:-}" ]; then
        name="$SPECKIT_WORKSTATION"
    elif [ -n "${WORKSTATION:-}" ]; then
        name="$WORKSTATION"
    else
        name="$(hostname 2>/dev/null || true)"
        [ -n "$name" ] || name="$(uname -n 2>/dev/null || true)"
    fi
    [ -n "$name" ] || name="unknown"
    printf '%s\n' "${name%%.*}"
}

# The lane, in Rule 5's spelling, never guessed from a window name.
workspace_lane() {
    local lane="$1"

    [ -n "$lane" ] || lane="${SPECKIT_LANE:-}"
    [ -n "$lane" ] || lane="${LANE:-}"
    [ -n "$lane" ] || lane="unknown"
    printf '%s\n' "$lane"
}

# A manifest file name is refused rather than sanitised.
workspace_name_is_safe() {
    case "$1" in
        '' | '.' | '..') return 1 ;;
        *[!A-Za-z0-9._-]*) return 1 ;;
        *) return 0 ;;
    esac
}

# project.yaml's id:, falling back to the repository directory name.
workspace_project_id() {
    local root="$1"

    WORKSPACE_PROJECT_ID=""
    if [ -f "$root/project.yaml" ] \
        && workspace_read_scalar "$root/project.yaml" id \
        && [ -n "$WORKSPACE_SCALAR" ]; then
        WORKSPACE_PROJECT_ID="$WORKSPACE_SCALAR"
        return 0
    fi
    WORKSPACE_PROJECT_ID="${root##*/}"
}

# The project's repository slug, read out of project.yaml's legs: block: the
# assembly leg's repository:. There is no top-level repository: key in the
# openRepoShape project manifest, and the git remote URL is a host path here,
# which the manifest may never record.
workspace_project_repository() {
    local root="$1"
    local manifest="$root/project.yaml"
    local raw content trimmed indent_ws indent key rest
    local in_legs=false key_col=-1
    local cur_role="" cur_repository=""

    WORKSPACE_PROJECT_REPOSITORY=""
    [ -f "$manifest" ] || return 0
    while IFS= read -r raw || [ -n "$raw" ]; do
        content="${raw%%#*}"
        _shape_set_trimmed "$content"
        trimmed="$_SHAPE_TRIMMED"
        [ -n "$trimmed" ] || continue
        indent_ws="${content%%[![:space:]]*}"
        indent=${#indent_ws}

        if [ "$in_legs" = true ]; then
            if [ "$indent" -eq 0 ]; then
                in_legs=false
            elif [ "${trimmed:0:2}" = "- " ] || [ "$trimmed" = "-" ]; then
                if [ "$cur_role" = "assembly" ] && [ -n "$cur_repository" ]; then
                    WORKSPACE_PROJECT_REPOSITORY="$cur_repository"
                    return 0
                fi
                cur_role=""
                cur_repository=""
                key_col=$((indent + 2))
                _shape_set_trimmed "${trimmed#-}"
                rest="$_SHAPE_TRIMMED"
                key="${rest%%:*}"
                if [ -n "$rest" ] && [ "$key" != "$rest" ]; then
                    _shape_set_scalar "${rest#*:}"
                    case "$key" in
                        role) cur_role="$_SHAPE_SCALAR" ;;
                        repository) cur_repository="$_SHAPE_SCALAR" ;;
                    esac
                fi
                continue
            elif [ "$indent" -eq "$key_col" ]; then
                key="${trimmed%%:*}"
                if [ "$key" != "$trimmed" ]; then
                    _shape_set_scalar "${trimmed#*:}"
                    case "$key" in
                        role) cur_role="$_SHAPE_SCALAR" ;;
                        repository) cur_repository="$_SHAPE_SCALAR" ;;
                    esac
                fi
                continue
            else
                continue
            fi
        fi

        if [ "$indent" -eq 0 ]; then
            key="${trimmed%%:*}"
            [ "$key" != "$trimmed" ] || continue
            if [ "$key" = "legs" ]; then
                in_legs=true
                key_col=-1
            fi
        fi
    done < "$manifest"
    if [ "$cur_role" = "assembly" ] && [ -n "$cur_repository" ]; then
        WORKSPACE_PROJECT_REPOSITORY="$cur_repository"
    fi
    return 0
}

# The family, when the root sits in the doubled <Family>/<Family> layout and
# the holder's family.yaml names this project as a member. Sets
# WORKSPACE_FAMILY (empty for a standalone project) and WORKSPACE_FAMILY_DIR.
workspace_family_name() {
    local root="$1"
    local project_id="$2"
    local parent family_dir manifest

    WORKSPACE_FAMILY=""
    WORKSPACE_FAMILY_DIR=""
    WORKSPACE_FAMILY_MANIFEST=""
    parent="${root%/*}"
    [ -n "$parent" ] || return 0
    [ "$parent" != "$root" ] || return 0
    family_dir="${parent##*/}"
    [ -n "$family_dir" ] || return 0
    manifest="$parent/$family_dir/family.yaml"
    [ -f "$manifest" ] || return 0
    workspace_read_scalar "$manifest" kind || return 0
    [ "$WORKSPACE_SCALAR" = "family-manifest" ] || return 0
    workspace_members_contains "$manifest" "$project_id" || return 0
    workspace_read_scalar "$manifest" id || return 0
    [ -n "$WORKSPACE_SCALAR" ] || return 0
    WORKSPACE_FAMILY="$WORKSPACE_SCALAR"
    WORKSPACE_FAMILY_DIR="$family_dir"
    WORKSPACE_FAMILY_MANIFEST="$manifest"
}

# The owner segment of a repository slug or URL: owner/repo,
# git@host:owner/repo.git, ssh://git@host/owner/repo.git and
# https://host/owner/repo all give "owner". A filesystem path has no owner and
# is refused, so nothing invents one.
workspace_org_from_url() {
    local url="$1"
    local rest owner

    WORKSPACE_ORG=""
    [ -n "$url" ] || return 1
    case "$url" in
        file://*) return 1 ;;
        *://*)
            rest="${url#*://}"
            rest="${rest#*@}"
            case "$rest" in
                */*) rest="${rest#*/}" ;;
                *) return 1 ;;
            esac
            ;;
        /*) return 1 ;;
        *:*) rest="${url#*:}" ;;
        */*) rest="$url" ;;
        *) return 1 ;;
    esac
    case "$rest" in
        */*) owner="${rest%%/*}" ;;
        *) return 1 ;;
    esac
    [ -n "$owner" ] || return 1
    WORKSPACE_ORG="$owner"
}

# The org a manifest file is filed under. One private workspace repository can
# track work across several orgs, and two projects in different orgs may share
# an id, so the file is workspaces/<org>/<name>.yaml and never workspaces/
# <name>.yaml. The org is the owner segment of the family holder's or the
# project's declared repository, falling back to the root's origin remote and
# then to "local" for a checkout that declares no owner at all.
workspace_org_for() {
    local root="$1"
    local family_manifest="$2"
    local url

    WORKSPACE_ORG=""
    if [ -n "$family_manifest" ] \
        && workspace_read_scalar "$family_manifest" repository \
        && workspace_org_from_url "$WORKSPACE_SCALAR"; then
        return 0
    fi
    workspace_project_repository "$root"
    if [ -n "$WORKSPACE_PROJECT_REPOSITORY" ] \
        && workspace_org_from_url "$WORKSPACE_PROJECT_REPOSITORY"; then
        return 0
    fi
    url="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
    if workspace_org_from_url "$url"; then
        return 0
    fi
    WORKSPACE_ORG="local"
}

# The manifest's own `root:` value: POSIX, relative, never absolute. A member
# of a family is recorded as <family folder>/<project folder>; a standalone
# project as its own folder name.
workspace_manifest_root_value() {
    local root="$1"
    local family_dir="$2"

    if [ -n "$family_dir" ]; then
        printf '%s/%s\n' "$family_dir" "${root##*/}"
    else
        printf '%s\n' "${root##*/}"
    fi
}

# One JSON field out of the last-worktree state file. Python 3 is a hard
# requirement of park.sh and resume.sh, so there is one implementation.
workspace_read_state_field() {
    local state_file="$1"
    local field="$2"

    WORKSPACE_STATE_VALUE=""
    [ -n "$state_file" ] || return 1
    [ -L "$state_file" ] && return 1
    [ -f "$state_file" ] || return 1
    WORKSPACE_STATE_VALUE="$(python3 - "$state_file" "$field" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as stream:
        payload = json.load(stream)
except (OSError, ValueError):
    raise SystemExit(1)
if not isinstance(payload, dict):
    raise SystemExit(1)
value = payload.get(sys.argv[2], "")
if not isinstance(value, str):
    raise SystemExit(1)
sys.stdout.write(value)
PY
    )" || return 1
    [ -n "$WORKSPACE_STATE_VALUE" ]
}

# ---------------------------------------------------------------------------
# The manifest reader.
#
# workspace_load_project <manifest file> <project id> fills, for resume.sh:
#   MANIFEST_PROJECT_FOUND        true | false
#   MANIFEST_FAMILY               the family name, or empty
#   MANIFEST_SHAPE                three-leg | single
#   MANIFEST_ROOT                 relative POSIX path
#   MANIFEST_TRACKING_BRANCH
#   MANIFEST_WORKTREE_ROOT        provenance only; resume uses the LOCAL config
#   MANIFEST_PARKED_AT / _ON / _BY_LANE
#   MANIFEST_ACTIVE_FEATURE / _SOURCE
#   MANIFEST_FEATURE_BRANCHES[]   MANIFEST_FEATURE_DIRECTORIES[]
#   MANIFEST_LEG_FEATURE[]        the feature index each leg row belongs to
#   MANIFEST_LEG_ROLE[] _REMOTE[] _COMMIT[] _WIP[] _DEPTH[] _PUSHED[]
#   MANIFEST_LEG_PUSHED_SEEN[]    the word `pushed` where that leg's record
#                                 carried the key, empty where it did not
#
# _PUSHED[] IS NOT DEFAULTED TO A VALUE THE RECORD DOES NOT CARRY. It was
# seeded with "false" at the `- role:` line, so a leg with no `pushed:` key
# loaded as though the record said `pushed: false` — and two readers then
# spoke for a record that had said nothing: `resume.sh`'s RR6 refused the leg
# in the `--no-push` words, and `park.sh`'s `emit_recorded_feature`, which
# carries a REFUSED feature's loaded entry forward verbatim, wrote
# `pushed: false` back into the file. The seed is the empty string instead,
# which `workspace_write_manifest` drops rather than writes, so a refused park
# carries the hole forward as a hole. _PUSHED_SEEN[] is what keeps the two
# empties apart — a key that is absent from a key that is there with no value
# after the colon — because they are two different things for a reader to say,
# and a reader never guesses.
#
# Bash 3.2 has no nested arrays, so the leg rows are a flat table keyed by
# feature index. The file is written by this extension with a fixed layout, so
# the reader keys on indent width and on the leading "- " of a list item.
# ---------------------------------------------------------------------------
workspace_load_project() {
    local file="$1"
    local want="$2"
    local raw content trimmed indent_ws indent key value rest
    local in_projects=false matching=false in_features=false in_legs=false
    local feature_index=-1

    MANIFEST_PROJECT_FOUND=false
    MANIFEST_FAMILY=""
    MANIFEST_SHAPE=""
    MANIFEST_ROOT=""
    MANIFEST_TRACKING_BRANCH=""
    MANIFEST_WORKTREE_ROOT=""
    MANIFEST_PARKED_AT=""
    MANIFEST_PARKED_ON=""
    MANIFEST_PARKED_BY_LANE=""
    MANIFEST_ACTIVE_FEATURE=""
    MANIFEST_ACTIVE_FEATURE_SOURCE=""
    MANIFEST_FEATURE_BRANCHES=()
    MANIFEST_FEATURE_DIRECTORIES=()
    MANIFEST_LEG_FEATURE=()
    MANIFEST_LEG_ROLE=()
    MANIFEST_LEG_REMOTE=()
    MANIFEST_LEG_COMMIT=()
    MANIFEST_LEG_WIP=()
    MANIFEST_LEG_DEPTH=()
    MANIFEST_LEG_PUSHED=()
    MANIFEST_LEG_PUSHED_SEEN=()

    [ -f "$file" ] || return 1
    while IFS= read -r raw || [ -n "$raw" ]; do
        content="${raw%%#*}"
        _shape_set_trimmed "$content"
        trimmed="$_SHAPE_TRIMMED"
        [ -n "$trimmed" ] || continue
        indent_ws="${content%%[![:space:]]*}"
        indent=${#indent_ws}

        if [ "$indent" -eq 0 ]; then
            in_projects=false
            matching=false
            in_features=false
            in_legs=false
            key="${trimmed%%:*}"
            [ "$key" != "$trimmed" ] || continue
            _shape_set_scalar "${trimmed#*:}"
            value="$_SHAPE_SCALAR"
            case "$key" in
                family) MANIFEST_FAMILY="$value" ;;
                projects) in_projects=true ;;
            esac
            continue
        fi

        [ "$in_projects" = true ] || continue

        if [ "$indent" -eq 2 ]; then
            matching=false
            in_features=false
            in_legs=false
            case "$trimmed" in
                '- '*) ;;
                *) continue ;;
            esac
            _shape_set_trimmed "${trimmed#- }"
            rest="$_SHAPE_TRIMMED"
            key="${rest%%:*}"
            [ "$key" != "$rest" ] || continue
            _shape_set_scalar "${rest#*:}"
            if [ "$key" = "id" ] && [ "$_SHAPE_SCALAR" = "$want" ]; then
                matching=true
                MANIFEST_PROJECT_FOUND=true
            fi
            continue
        fi

        [ "$matching" = true ] || continue

        if [ "$indent" -eq 4 ]; then
            in_features=false
            in_legs=false
            key="${trimmed%%:*}"
            [ "$key" != "$trimmed" ] || continue
            _shape_set_scalar "${trimmed#*:}"
            value="$_SHAPE_SCALAR"
            case "$key" in
                shape) MANIFEST_SHAPE="$value" ;;
                root) MANIFEST_ROOT="$value" ;;
                tracking_branch) MANIFEST_TRACKING_BRANCH="$value" ;;
                worktree_root) MANIFEST_WORKTREE_ROOT="$value" ;;
                parked_at) MANIFEST_PARKED_AT="$value" ;;
                parked_on) MANIFEST_PARKED_ON="$value" ;;
                parked_by_lane) MANIFEST_PARKED_BY_LANE="$value" ;;
                active_feature) MANIFEST_ACTIVE_FEATURE="$value" ;;
                active_feature_source) MANIFEST_ACTIVE_FEATURE_SOURCE="$value" ;;
                features) in_features=true ;;
            esac
            continue
        fi

        [ "$in_features" = true ] || continue

        if [ "$indent" -eq 6 ]; then
            in_legs=false
            case "$trimmed" in
                '- '*) ;;
                *) continue ;;
            esac
            _shape_set_trimmed "${trimmed#- }"
            rest="$_SHAPE_TRIMMED"
            key="${rest%%:*}"
            [ "$key" != "$rest" ] || continue
            _shape_set_scalar "${rest#*:}"
            [ "$key" = "branch" ] || continue
            MANIFEST_FEATURE_BRANCHES[${#MANIFEST_FEATURE_BRANCHES[@]}]="$_SHAPE_SCALAR"
            MANIFEST_FEATURE_DIRECTORIES[${#MANIFEST_FEATURE_DIRECTORIES[@]}]=""
            feature_index=$((${#MANIFEST_FEATURE_BRANCHES[@]} - 1))
            continue
        fi

        [ "$feature_index" -ge 0 ] || continue

        if [ "$indent" -eq 8 ]; then
            in_legs=false
            key="${trimmed%%:*}"
            [ "$key" != "$trimmed" ] || continue
            _shape_set_scalar "${trimmed#*:}"
            case "$key" in
                feature_directory)
                    MANIFEST_FEATURE_DIRECTORIES[feature_index]="$_SHAPE_SCALAR"
                    ;;
                legs) in_legs=true ;;
            esac
            continue
        fi

        [ "$in_legs" = true ] || continue

        if [ "$indent" -eq 10 ]; then
            case "$trimmed" in
                '- '*) ;;
                *) continue ;;
            esac
            _shape_set_trimmed "${trimmed#- }"
            rest="$_SHAPE_TRIMMED"
            key="${rest%%:*}"
            [ "$key" != "$rest" ] || continue
            _shape_set_scalar "${rest#*:}"
            [ "$key" = "role" ] || continue
            MANIFEST_LEG_FEATURE[${#MANIFEST_LEG_FEATURE[@]}]="$feature_index"
            MANIFEST_LEG_ROLE[${#MANIFEST_LEG_ROLE[@]}]="$_SHAPE_SCALAR"
            MANIFEST_LEG_REMOTE[${#MANIFEST_LEG_REMOTE[@]}]=""
            MANIFEST_LEG_COMMIT[${#MANIFEST_LEG_COMMIT[@]}]=""
            MANIFEST_LEG_WIP[${#MANIFEST_LEG_WIP[@]}]="false"
            MANIFEST_LEG_DEPTH[${#MANIFEST_LEG_DEPTH[@]}]="0"
            MANIFEST_LEG_PUSHED[${#MANIFEST_LEG_PUSHED[@]}]=""
            MANIFEST_LEG_PUSHED_SEEN[${#MANIFEST_LEG_PUSHED_SEEN[@]}]=""
            continue
        fi

        if [ "$indent" -eq 12 ] && [ "${#MANIFEST_LEG_ROLE[@]}" -gt 0 ]; then
            local leg_index=$((${#MANIFEST_LEG_ROLE[@]} - 1))
            key="${trimmed%%:*}"
            [ "$key" != "$trimmed" ] || continue
            _shape_set_scalar "${trimmed#*:}"
            case "$key" in
                remote) MANIFEST_LEG_REMOTE[leg_index]="$_SHAPE_SCALAR" ;;
                parked_commit) MANIFEST_LEG_COMMIT[leg_index]="$_SHAPE_SCALAR" ;;
                wip) MANIFEST_LEG_WIP[leg_index]="$_SHAPE_SCALAR" ;;
                wip_depth) MANIFEST_LEG_DEPTH[leg_index]="$_SHAPE_SCALAR" ;;
                pushed)
                    MANIFEST_LEG_PUSHED[leg_index]="$_SHAPE_SCALAR"
                    MANIFEST_LEG_PUSHED_SEEN[leg_index]=pushed
                    ;;
            esac
        fi
    done < "$file"

    [ "$MANIFEST_PROJECT_FOUND" = true ]
}

# ---------------------------------------------------------------------------
# The mutex, and the writes in the workspace repository.
#
# This is ~/projects/xFactory/.lanes/lanes-edit.sh's shape, and for its
# reasons: a peer's in-flight edit is committed as its own commit before ours,
# every commit carries an explicit pathspec, and a rebase conflict ABORTS
# rather than leaving a mid-rebase checkout behind.
# ---------------------------------------------------------------------------
workspace_lock() {
    local workspace="$1"
    local lock="$workspace/.workspaces.lock"
    local attempt=0

    while [ "$attempt" -lt 60 ]; do
        if mkdir "$lock" 2>/dev/null; then
            WORKSPACE_LOCK_DIR="$lock"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
}

workspace_unlock() {
    [ -n "$WORKSPACE_LOCK_DIR" ] || return 0
    rmdir "$WORKSPACE_LOCK_DIR" 2>/dev/null || true
    WORKSPACE_LOCK_DIR=""
}

# Any pre-existing uncommitted change under workspaces/ becomes its own commit
# first, so a peer's in-flight edit is never swept into ours.
workspace_commit_pre_existing() {
    local workspace="$1"
    local workstation="$2"
    local dirty count

    dirty="$(git -C "$workspace" status --porcelain --untracked-files=all -- workspaces 2>/dev/null || true)"
    [ -n "$dirty" ] || return 0
    count="$(printf '%s\n' "$dirty" | grep -c '^' || true)"
    git -C "$workspace" add -- workspaces >/dev/null 2>&1 || return 1
    git -C "$workspace" commit -q \
        -m "park(pre-existing@$workstation): $count file(s)" -- workspaces || return 1
    echo "[specify] Committed $count pre-existing change(s) under workspaces/ as their own commit." >&2
}

# Refuse if the write touched anything under workspaces/ other than our file.
workspace_only_our_file_changed() {
    local workspace="$1"
    local relative="$2"
    local line path

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        path="${line:3}"
        case "$path" in
            "$relative") ;;
            *) return 1 ;;
        esac
    done <<EOF
$(git -C "$workspace" status --porcelain --untracked-files=all -- workspaces 2>/dev/null || true)
EOF
    return 0
}

# Tracked changes outside workspaces/ that would stop a rebase. Untracked
# files do not stop one, so they are not counted: a half-written handoff that
# has never been added is nobody's problem. workspace_commit_pre_existing has
# already dealt with everything under workspaces/.
workspace_dirty_outside_manifests() {
    local workspace="$1"
    local line path

    WORKSPACE_DIRTY_PATHS=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            '??'*) continue ;;
        esac
        path="${line:3}"
        case "$path" in
            workspaces/*) continue ;;
        esac
        WORKSPACE_DIRTY_PATHS="$WORKSPACE_DIRTY_PATHS$path
"
    done <<EOF
$(git -C "$workspace" status --porcelain 2>/dev/null || true)
EOF
    [ -n "$WORKSPACE_DIRTY_PATHS" ]
}

# workspace-dirty.
workspace_refuse_dirty() {
    local workspace="$1"
    local past="$2"

    >&2 echo "Error: workspace-dirty: '$workspace' has uncommitted changes outside workspaces/, so it cannot be brought up to date; nothing was $past."
    >&2 printf '  %s
' "$WORKSPACE_DIRTY_PATHS" | sed '/^  $/d'
    >&2 echo "park and resume never touch a file outside workspaces/ — a handoff is yours to commit."
    >&2 echo "  commit or stash those paths, then re-run:"
    >&2 echo "  git -C $workspace status"
}

# Bring the workspace checkout up to date before the manifest is rewritten, so
# the write lands on what origin already holds instead of colliding with it.
# On a rebase conflict the rebase is ABORTED and the caller refuses. Returns 2
# when the checkout is dirty outside workspaces/ and a rebase is needed, so
# the caller can refuse by name instead of misreporting a conflict.
workspace_sync() {
    local workspace="$1"
    local branch conflict

    git -C "$workspace" remote get-url origin >/dev/null 2>&1 || return 0
    branch="$(git -C "$workspace" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [ -n "$branch" ] && [ "$branch" != "HEAD" ] || return 0
    git -C "$workspace" fetch -q origin "$branch" >/dev/null 2>&1 || return 0
    git -C "$workspace" merge-base --is-ancestor "refs/remotes/origin/$branch" HEAD 2>/dev/null && return 0
    # A rebase is actually needed, so the working tree has to be clean for it.
    if workspace_dirty_outside_manifests "$workspace"; then
        return 2
    fi
    if git -C "$workspace" pull --rebase -q origin "$branch" >/dev/null 2>&1; then
        return 0
    fi
    conflict="$(git -C "$workspace" diff --name-only --diff-filter=U 2>/dev/null || true)"
    git -C "$workspace" rebase --abort >/dev/null 2>&1 || true
    >&2 echo "Error: rebasing the workspace repository '$workspace' onto origin/$branch conflicted; nothing was recorded."
    if [ -n "$conflict" ]; then
        >&2 printf '  %s\n' "$conflict"
    fi
    >&2 echo "The rebase was aborted, so the checkout is clean and not mid-rebase. Reconcile by hand:"
    >&2 echo "  git -C $workspace pull --rebase origin $branch"
    return 1
}

workspace_commit_manifest() {
    local workspace="$1"
    local relative="$2"
    local subject="$3"

    git -C "$workspace" add -- "$relative" >/dev/null 2>&1 || return 1
    git -C "$workspace" commit -q -m "$subject" -- "$relative" || return 1
}

# git pull --rebase then push, with a race retry. On a rebase conflict the
# rebase is ABORTED and the caller refuses: the checkout is left clean and not
# mid-rebase. Never a force-push here.
WORKSPACE_PUSH_RESULT=""
workspace_push_manifest() {
    local workspace="$1"
    local attempt=0
    local branch conflict

    WORKSPACE_PUSH_RESULT="not-pushed"
    if ! git -C "$workspace" remote get-url origin >/dev/null 2>&1; then
        echo "[specify] Warning: the workspace checkout '$workspace' has no 'origin' remote; the manifest commit was not pushed." >&2
        return 0
    fi
    branch="$(git -C "$workspace" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
        echo "[specify] Warning: the workspace checkout '$workspace' is not on a branch; the manifest commit was not pushed." >&2
        return 0
    fi

    while [ "$attempt" -lt 6 ]; do
        if git -C "$workspace" push -q origin "HEAD:refs/heads/$branch" 2>/dev/null; then
            WORKSPACE_PUSH_RESULT="pushed"
            return 0
        fi
        if workspace_dirty_outside_manifests "$workspace"; then
            WORKSPACE_PUSH_RESULT="dirty"
            return 1
        fi
        if ! git -C "$workspace" pull --rebase -q origin "$branch" 2>/dev/null; then
            conflict="$(git -C "$workspace" diff --name-only --diff-filter=U 2>/dev/null || true)"
            git -C "$workspace" rebase --abort >/dev/null 2>&1 || true
            >&2 echo "Error: rebasing the workspace repository '$workspace' onto origin/$branch conflicted; the manifest commit was NOT pushed."
            if [ -n "$conflict" ]; then
                >&2 printf '  %s\n' "$conflict"
            fi
            >&2 echo "The rebase was aborted, so the checkout is clean and not mid-rebase. Reconcile by hand:"
            >&2 echo "  git -C $workspace pull --rebase origin $branch"
            >&2 echo "  git -C $workspace push origin $branch"
            WORKSPACE_PUSH_RESULT="conflict"
            return 1
        fi
        attempt=$((attempt + 1))
    done
    echo "[specify] Warning: could not push the manifest commit to origin/$branch after 6 attempts; it is committed locally." >&2
    return 0
}

# ---------------------------------------------------------------------------
# The record file, and the two Python 3 writers.
#
# park.sh and resume.sh describe their result once, as a small tab-delimited
# record file, and hand it to the writers below. That keeps one description of
# the facts instead of one per output format:
#
#   <key>\t<value>        a top-level fact; a key starting with "_" is
#                         manifest-only and never appears in --json output
#   [feature]             starts a feature; its own <key>\t<value> lines follow
#   [leg]                 starts a leg of the current feature
#   [refused]             starts a refusal record (never reaches the manifest)
#
# Python 3 is a hard requirement of both scripts — the manifest and the
# last-worktree state file are both published through it — so there is one
# implementation of each writer rather than three.
# ---------------------------------------------------------------------------

workspace_record_reset() {
    : > "$1"
}

workspace_record_put() {
    local file="$1"
    local key="$2"
    local value="$3"

    value="${value//	/ }"
    value="${value//$'\n'/ }"
    printf '%s\t%s\n' "$key" "$value" >> "$file"
}

workspace_record_section() {
    printf '[%s]\n' "$2" >> "$1"
}

# Merge this project's block into <manifest>, in a fixed key order, rewriting
# no other project's block. Prints "changed" or "unchanged"; a byte-identical
# rewrite is not a write, so park makes no empty commit.
workspace_write_manifest() {
    local manifest="$1"
    local record="$2"

    python3 - "$manifest" "$record" <<'PY'
import os
import re
import sys

manifest_path, record_path = sys.argv[1], sys.argv[2]
SAFE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/@:+-]*$")
INTEGER = re.compile(r"^(?:0|[1-9][0-9]*)$")


def scalar(value):
    if value in ("true", "false") or INTEGER.match(value):
        return value
    if SAFE.match(value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return '"%s"' % escaped


def relative(value, where):
    if value.startswith("/") or value.startswith("~"):
        sys.stderr.write(
            "Error: refusing to record an absolute path in the workspace "
            "manifest: %s = %s\n" % (where, value)
        )
        raise SystemExit(1)
    return value


top = {}
features = []
section = None
with open(record_path, "r", encoding="utf-8") as stream:
    for raw in stream:
        line = raw.rstrip("\n")
        if not line:
            continue
        if line == "[feature]":
            features.append({"legs": []})
            section = "feature"
            continue
        if line == "[leg]":
            features[-1]["legs"].append({})
            section = "leg"
            continue
        if line == "[refused]":
            section = "refused"
            continue
        key, _, value = line.partition("\t")
        if section == "feature":
            features[-1][key] = value
        elif section == "leg":
            features[-1]["legs"][-1][key] = value
        elif section == "refused":
            continue
        else:
            top[key] = value

project_id = top.get("project_id", "")
if not project_id:
    sys.stderr.write("Error: the workspace record names no project id.\n")
    raise SystemExit(1)

PROJECT_KEYS = (
    ("repository", "_repository"),
    ("shape", "_shape"),
    ("root", "_root"),
    ("tracking_branch", "_tracking_branch"),
    ("worktree_root", "_worktree_root"),
    ("parked_at", "_parked_at"),
    ("parked_on", "_parked_on"),
    ("parked_by_lane", "_parked_by_lane"),
    ("active_feature", "active_feature"),
    ("active_feature_source", "active_feature_source"),
)
LEG_KEYS = (
    ("role", "role"),
    ("remote", "_remote"),
    ("parked_commit", "parked_commit"),
    ("wip", "wip"),
    ("wip_depth", "wip_depth"),
    ("pushed", "pushed"),
)

block = ["  - id: %s" % scalar(project_id)]
for out_key, record_key in PROJECT_KEYS:
    value = top.get(record_key, "")
    if value == "":
        continue
    if out_key in ("root", "worktree_root"):
        value = relative(value, out_key)
    block.append("    %s: %s" % (out_key, scalar(value)))
if not features:
    block.append("    features: []")
else:
    block.append("    features:")
    for feature in features:
        block.append("      - branch: %s" % scalar(feature.get("branch", "")))
        directory = feature.get("_feature_directory", "")
        if directory:
            block.append(
                "        feature_directory: %s"
                % scalar(relative(directory, "feature_directory"))
            )
        legs = feature.get("legs", [])
        if not legs:
            block.append("        legs: []")
            continue
        block.append("        legs:")
        for leg in legs:
            first = True
            for out_key, record_key in LEG_KEYS:
                value = leg.get(record_key, "")
                if value == "" and out_key != "role":
                    continue
                prefix = "          - " if first else "            "
                block.append("%s%s: %s" % (prefix, out_key, scalar(value)))
                first = False

try:
    with open(manifest_path, "r", encoding="utf-8") as stream:
        existing = stream.read()
except OSError:
    existing = ""

blocks = []
lines = existing.splitlines()
index = 0
while index < len(lines) and not lines[index].startswith("projects:"):
    index += 1
index += 1
current = None
while index < len(lines):
    line = lines[index]
    index += 1
    if not line.strip():
        continue
    if not line.startswith(" "):
        break
    if line.startswith("  - "):
        current = [line]
        blocks.append(current)
    elif current is not None:
        current.append(line)


def block_id(candidate):
    match = re.match(r"^  - id:\s*(.*)$", candidate[0])
    if match is None:
        return None
    value = match.group(1).strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value


def without_parked_at(candidate):
    return [line for line in candidate if not line.startswith("    parked_at:")]


# parked_at is the only volatile field. When the rest of the block is
# unchanged, keep the recorded instant: a re-park of unchanged state must
# produce a byte-identical file and therefore no commit at all.
for candidate in blocks:
    if block_id(candidate) != project_id:
        continue
    if without_parked_at(candidate) == without_parked_at(block):
        previous = [line for line in candidate if line.startswith("    parked_at:")]
        if previous:
            block = [
                previous[0] if line.startswith("    parked_at:") else line
                for line in block
            ]
    break

merged = []
placed = False
for candidate in blocks:
    if block_id(candidate) == project_id:
        if not placed:
            merged.append(block)
            placed = True
        continue
    merged.append(candidate)
if not placed:
    merged.append(block)

header = ["schema_version: 1", "kind: workspace-manifest"]
family = top.get("_family", "")
if family:
    header.append("family: %s" % scalar(family))
header.append("written_by: speckit park")
header.append("projects:")
rendered = "\n".join(header + [line for candidate in merged for line in candidate]) + "\n"

if rendered == existing:
    sys.stdout.write("unchanged\n")
    raise SystemExit(0)

directory = os.path.dirname(manifest_path) or "."
os.makedirs(directory, exist_ok=True)
temporary = os.path.join(directory, ".%s.tmp" % os.path.basename(manifest_path))
with open(temporary, "w", encoding="utf-8") as stream:
    stream.write(rendered)
os.replace(temporary, manifest_path)
sys.stdout.write("changed\n")
PY
}

# Render the record file as the extension's uppercase-keyed JSON. The list key
# is PARKED for park.sh and RESUMED for resume.sh.
workspace_emit_json() {
    local record="$1"
    local list_key="$2"

    python3 - "$record" "$list_key" <<'PY'
import json
import re
import sys

record_path, list_key = sys.argv[1], sys.argv[2]
INTEGER = re.compile(r"^(?:0|[1-9][0-9]*)$")


def coerce(value):
    if value == "true":
        return True
    if value == "false":
        return False
    if INTEGER.match(value):
        return int(value)
    return value


top = {}
features = []
refused = []
section = None
with open(record_path, "r", encoding="utf-8") as stream:
    for raw in stream:
        line = raw.rstrip("\n")
        if not line:
            continue
        if line == "[feature]":
            features.append({"LEGS": []})
            section = "feature"
            continue
        if line == "[leg]":
            features[-1]["LEGS"].append({})
            section = "leg"
            continue
        if line == "[refused]":
            refused.append({})
            section = "refused"
            continue
        key, _, value = line.partition("\t")
        if key.startswith("_"):
            continue
        if section == "feature":
            features[-1][key.upper()] = coerce(value)
        elif section == "leg":
            features[-1]["LEGS"][-1][key.upper()] = coerce(value)
        elif section == "refused":
            refused[-1][key.upper()] = coerce(value)
        else:
            top[key.upper()] = coerce(value)

payload = {}
for key in (
    "REPO_SHAPE",
    "PROJECT_ID",
    "WORKSPACE_PATH",
    "WORKSPACE_SOURCE",
    "MANIFEST_PATH",
):
    if key in top:
        payload[key] = top[key]
payload[list_key] = features
payload["REFUSED"] = refused
for key in ("ACTIVE_FEATURE", "ACTIVE_FEATURE_SOURCE", "FEATURE_JSON", "STATE_FILE"):
    if key in top:
        payload[key] = top[key]
for key in sorted(top):
    if key not in payload and key != "DRY_RUN":
        payload[key] = top[key]
if top.get("DRY_RUN") is True:
    payload["DRY_RUN"] = True
json.dump(payload, sys.stdout, ensure_ascii=False, separators=(",", ":"))
sys.stdout.write("\n")
PY
}
