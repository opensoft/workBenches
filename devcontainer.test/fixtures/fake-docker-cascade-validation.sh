#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_DOCKER_LOG:?FAKE_DOCKER_LOG is required}"

case "$1" in
    compose)
        "${TEST_REAL_DOCKER:?TEST_REAL_DOCKER is required}" "$@"
        ;;
    image)
        if [ "$2" = "ls" ]; then
            printf '%s\n' "${FAKE_DOCKER_IMAGE_REFS:-test-bench:latest}"
            exit 0
        fi
        if [ "$2" = "save" ]; then
            if [ "${FAKE_DOCKER_IMAGE_SAVE_FAIL:-false}" = true ]; then
                exit 124
            fi
            python3 - <<'PY'
import io
import json
import os
import sys
import tarfile

username = os.environ.get("FAKE_DOCKER_LAYER3_PASSWD_USERNAME", "brett")
uid = os.environ.get("FAKE_DOCKER_LAYER3_UID", str(os.getuid()))
gid = os.environ.get("FAKE_DOCKER_LAYER3_GID", str(os.getgid()))
docker_gid = os.environ.get("FAKE_DOCKER_LAYER3_DOCKER_SOCKET_GID", "")
passwd = f"root:x:0:0:root:/root:/bin/sh\n{username}:x:{uid}:{gid}:User:/home/{username}:/bin/sh\n".encode()
group = b"root:x:0:\n"
if docker_gid and docker_gid != gid:
    group += f"docker-host:x:{docker_gid}:{username}\n".encode()

layer_buffer = io.BytesIO()
with tarfile.open(fileobj=layer_buffer, mode="w") as layer:
    for name, data in (("etc/passwd", passwd), ("etc/group", group)):
        member = tarfile.TarInfo(name)
        member.size = len(data)
        layer.addfile(member, io.BytesIO(data))
layer_data = layer_buffer.getvalue()
manifest_data = json.dumps([{"Config": "config.json", "RepoTags": [], "Layers": ["layer/layer.tar"]}]).encode()

with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as archive:
    for name, data in (("manifest.json", manifest_data), ("layer/layer.tar", layer_data)):
        member = tarfile.TarInfo(name)
        member.size = len(data)
        archive.addfile(member, io.BytesIO(data))
PY
            exit 0
        fi
        [ "$2" = "inspect" ] || exit 1
        image="${!#}"
        if [[ "$image" == "${FAKE_DOCKER_IMAGE_INSPECT_FAIL:-}" ]]; then
            echo "simulated Docker image inspect failure for $image" >&2
            exit 2
        fi
        if [[ "$image" == "${FAKE_DOCKER_MISSING_IMAGE:-}" ]]; then
            echo "Error response from daemon: No such image: $image" >&2
            exit 1
        fi
        case "$image" in
            test-bench:latest|test-bench:brett*|sim-bench-*:*|sha256:*) ;;
            *) exit 1 ;;
        esac
        case "$*" in
            *'{{.Id}}'*)
                if [[ "$image" == sha256:* ]]; then
                    echo "$image"
                elif [[ "$image" == test-bench:brett* ]]; then
                    echo "${FAKE_DOCKER_USER_IMAGE_ID:-sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd}"
                else
                    echo "${FAKE_DOCKER_IMAGE_ID:-sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
                fi
                ;;
            *'recipe-sha256'*)
                if [ "${FAKE_DOCKER_RECIPE_INSPECT_FAIL:-false}" = true ]; then
                    echo "simulated recipe metadata inspection failure" >&2
                    exit 2
                fi
                echo "${FAKE_DOCKER_LAYER3_RECIPE_SHA256:-}"
                ;;
            *'layer3.base-image-id'*)
                if [ "${FAKE_DOCKER_BASE_IMAGE_LABEL_INSPECT_FAIL:-false}" = true ]; then
                    echo "simulated base-image metadata inspection failure" >&2
                    exit 2
                fi
                echo "${FAKE_DOCKER_LAYER3_BASE_IMAGE_ID:-${FAKE_DOCKER_IMAGE_ID:-sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}}"
                ;;
            *'layer3.username'*)
                [ "${FAKE_DOCKER_LABEL_INSPECT_FAIL:-false}" = false ] || exit 1
                echo "${FAKE_DOCKER_LAYER3_USERNAME:-brett}"
                ;;
            *'layer3.uid'*)
                [ "${FAKE_DOCKER_LABEL_INSPECT_FAIL:-false}" = false ] || exit 1
                echo "${FAKE_DOCKER_LAYER3_UID:-$(id -u)}"
                ;;
            *'layer3.gid'*)
                [ "${FAKE_DOCKER_LABEL_INSPECT_FAIL:-false}" = false ] || exit 1
                echo "${FAKE_DOCKER_LAYER3_GID:-$(id -g)}"
                ;;
            *'layer3.docker-socket-gid'*)
                [ "${FAKE_DOCKER_LABEL_INSPECT_FAIL:-false}" = false ] || exit 1
                echo "${FAKE_DOCKER_LAYER3_DOCKER_SOCKET_GID:-}"
                ;;
            *'{{.Created}}'*)
                if [ "${FAKE_DOCKER_CREATED_INSPECT_FAIL:-false}" = true ]; then
                    echo "simulated creation metadata inspection failure" >&2
                    exit 2
                fi
                if [[ "$image" == "test-bench:brett" \
                    || "$image" == "${FAKE_DOCKER_USER_IMAGE_ID:-sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd}" ]]; then
                    echo "2026-09-10T01:00:01Z"
                else
                    echo "2026-09-10T01:00:00Z"
                fi
                ;;
        esac
        ;;
    container)
        if [ "$2" = "ls" ]; then
            while IFS=$'\t' read -r configured_image container_name; do
                [[ -n "$configured_image" && -n "$container_name" ]] || continue
                printf '%s\n' "$container_name"
            done <<< "${FAKE_DOCKER_RUNNING_CONTAINERS:-}"
            exit 0
        fi
        if [ "$2" = "inspect" ]; then
            container_name="${!#}"
            if [[ "$container_name" == "${FAKE_DOCKER_CONTAINER_INSPECT_FAIL:-}" ]]; then
                echo "simulated Docker container inspect failure for $container_name" >&2
                exit 2
            fi
            configured_image="${FAKE_DOCKER_RUNNING_CONTAINER_CONFIG_IMAGE:-}"
            if [[ -z "$configured_image" ]]; then
                while IFS=$'\t' read -r candidate_image candidate_name; do
                    if [[ "$candidate_name" == "$container_name" ]]; then
                        configured_image="$candidate_image"
                        break
                    fi
                done <<< "${FAKE_DOCKER_RUNNING_CONTAINERS:-}"
            fi
            actual_image_id="${FAKE_DOCKER_RUNNING_CONTAINER_IMAGE_ID:-${FAKE_DOCKER_USER_IMAGE_ID:-sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd}}"
            layer3_username="${FAKE_DOCKER_RUNNING_CONTAINER_LAYER3_USERNAME:-${FAKE_DOCKER_LAYER3_USERNAME:-brett}}"
            case "$*" in
                *'{{.Config.Image}}'*) printf '%s\n' "$configured_image" ;;
                *'layer3.username'*) printf '%s\n' "$layer3_username" ;;
                *'{{.Image}}'*) printf '%s\n' "$actual_image_id" ;;
                *) exit 1 ;;
            esac
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
