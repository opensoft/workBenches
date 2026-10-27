#!/usr/bin/env bash
# Native gh boundary. Tokens remain in gh storage and the child process environment.
set +x
set -euo pipefail
umask 077
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_DEBUG
operation=$1
configuration=$2
shift 2
if [[ "$configuration" != native ]]; then
    export GH_CONFIG_DIR="$configuration"
fi
case "$operation" in
    list)
        gh auth status --hostname github.com --json hosts --jq \
          '[.hosts["github.com"][]? | {login,active,state}]'
        ;;
    verify)
        github_login=$1
        [[ "$github_login" =~ ^[A-Za-z0-9-]{1,39}$ ]] || exit 2
        github_credential=$(gh auth token --hostname github.com --user "$github_login" 2>/dev/null) || exit 4
        [[ -n "$github_credential" ]] || exit 4
        if github_identity=$(GH_TOKEN="$github_credential" gh api --hostname github.com user --jq '{login,id}' 2>&1); then
            printf '%s\n' "$github_identity"
        elif [[ "$github_identity" == *"HTTP 401"* ]]; then
            exit 4
        else
            exit 1
        fi
        ;;
    profile-file|profile-export-base)
        github_login=$1
        endpoint=$2
        [[ "$github_login" =~ ^[A-Za-z0-9-]{1,39}$ ]] || exit 2
        [[ "$endpoint" =~ ^repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/contents/ ]] || exit 2
        github_credential=$(gh auth token --hostname github.com --user "$github_login" 2>/dev/null) || exit 4
        [[ -n "$github_credential" ]] || exit 4
        if github_file=$(GH_TOKEN="$github_credential" gh api --hostname github.com "$endpoint" --jq \
            'if .type == "file" and .size <= 1048576 and .encoding == "base64" then {content,encoding,sha,size} else error("Unsupported manifest file") end' 2>&1); then
            printf '%s' "$github_file"
        elif [[ "$operation" == profile-export-base && "$github_file" == *'HTTP 404'* ]]; then
            exit 44
        else exit 1; fi
        ;;
    profile-put)
        github_login=$1
        endpoint=$2
        payload=$3
        [[ "$github_login" =~ ^[A-Za-z0-9-]{1,39}$ ]] || exit 2
        [[ "$endpoint" =~ ^repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/contents/ && "$endpoint" != *'?'* ]] || exit 2
        [[ -f "$payload" && ! -L "$payload" && $(wc -c < "$payload") -le 1500000 ]] || exit 2
        github_credential=$(gh auth token --hostname github.com --user "$github_login" 2>/dev/null) || exit 4
        [[ -n "$github_credential" ]] || exit 4
        GH_TOKEN="$github_credential" gh api --hostname github.com --method PUT "$endpoint" --input "$payload" --jq '.commit.sha' 2>/dev/null
        ;;
    profile-revision)
        github_login=$1
        endpoint=$2
        [[ "$github_login" =~ ^[A-Za-z0-9-]{1,39}$ ]] || exit 2
        [[ "$endpoint" =~ ^repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/commits/ ]] || exit 2
        github_credential=$(gh auth token --hostname github.com --user "$github_login" 2>/dev/null) || exit 4
        [[ -n "$github_credential" ]] || exit 4
        GH_TOKEN="$github_credential" gh api --hostname github.com "$endpoint" --jq .sha 2>/dev/null
        ;;
    start-login)
        progress=$1
        # Return promptly so the native Tools broker can service browser and
        # clipboard requests while gh waits for device approval.
        (
            trap '' HUP
            set +e
            bash "${BASH_SOURCE[0]}" login "$configuration" "$progress"
            result=$?
            printf '%s\n' "$result" > "$progress.exit.new"
            mv -f "$progress.exit.new" "$progress.exit"
        ) </dev/null >"$progress.launch" 2>&1 &
        ;;
    login)
        # gh emits the device code to this private progress file. Browser opening
        # is an explicit TUI action, so gh must not launch it independently.
        export BROWSER=true GH_BROWSER=true
        progress=$1
        gh auth login --hostname github.com --git-protocol https --web >"$progress" 2>&1 &
        child=$!
        trap 'kill "$child" 2>/dev/null || true' EXIT TERM INT
        while kill -0 "$child" 2>/dev/null; do
            if [[ -f "$progress.cancel" ]]; then
                kill "$child" 2>/dev/null || true
                wait "$child" 2>/dev/null || true
                exit 130
            fi
            sleep .1
        done
        wait "$child"
        ;;
    current) gh api --hostname github.com user --jq '{login,id}' ;;
    *) exit 2 ;;
esac
