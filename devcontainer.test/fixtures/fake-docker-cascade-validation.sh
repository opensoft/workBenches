#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_DOCKER_LOG:?FAKE_DOCKER_LOG is required}"

case "$1" in
    image)
        if [ "$2" = "ls" ]; then
            printf '%s\n' "${FAKE_DOCKER_IMAGE_REFS:-test-bench:latest}"
            exit 0
        fi
        [ "$2" = "inspect" ] || exit 1
        image="${!#}"
        case "$image" in
            test-bench:latest|test-bench:brett*|sim-bench:*|sim-bench-*|sha256:*) ;;
            *) exit 1 ;;
        esac
        case "$*" in
            *'{{.Id}}'*)
                if [[ "$image" == sha256:* ]]; then
                    echo "$image"
                else
                    echo "${FAKE_DOCKER_IMAGE_ID:-sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
                fi
                ;;
            *'recipe-sha256'*)
                echo "${FAKE_DOCKER_LAYER3_RECIPE_SHA256:-}"
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
        if [[ " $* " == *' layer3-identity-probe '* ]]; then
            exit "${FAKE_DOCKER_LAYER3_IDENTITY_STATUS:-0}"
        fi
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
