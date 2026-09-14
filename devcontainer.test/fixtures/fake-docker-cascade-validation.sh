#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_DOCKER_LOG:?FAKE_DOCKER_LOG is required}"

case "$1" in
    image)
        [ "$2" = "inspect" ] || exit 1
        image="${!#}"
        case "$image" in
            test-bench:latest|test-bench:brett*|sha256:*) ;;
            *) exit 1 ;;
        esac
        case "$*" in
            *'{{.Id}}'*)
                if [[ "$image" == sha256:* ]]; then
                    echo "$image"
                else
                    echo "${FAKE_DOCKER_IMAGE_ID:-sha256:${image//[:]/-}}"
                fi
                ;;
            *'{{.Created}}'*)
                if [ "$image" = "test-bench:brett" ]; then
                    echo "2026-09-10T01:00:01Z"
                else
                    echo "2026-09-10T01:00:00Z"
                fi
                ;;
        esac
        ;;
    container)
        if [ "$2" = "ls" ]; then
            printf '%b' "${FAKE_DOCKER_RUNNING_CONTAINERS:-}"
            exit 0
        fi
        exit 1
        ;;
    run)
        printf '%s\n' probe-batch >> "${FAKE_DOCKER_LOG:?FAKE_DOCKER_LOG is required}"
        [[ " $* " == *' --network none '* ]]
        [[ " $* " == *' --cap-drop ALL '* ]]
        [[ " $* " == *' --security-opt no-new-privileges '* ]]
        [[ " $* " == *' --read-only '* ]]
        while [[ $# -gt 0 && "$1" != "sh" ]]; do shift; done
        shift 4
        for cli in "$@"; do
            if [[ "$cli" == "${FAKE_DOCKER_MISSING_CLI:-}" ]]; then
                printf 'missing\t%s\t\n' "$cli"
            else
                printf 'ok\t%s\t/usr/local/bin/%s\n' "$cli" "$cli"
            fi
        done
        ;;
    *)
        echo "Unexpected fake Docker command: $*" >&2
        exit 1
        ;;
esac
