# Layer 3: User Personalization
# Thin layer that creates a user matching the host UID/GID.
# /etc/skel content (oh-my-zsh, shell configs, aliases) is copied
# automatically by useradd -m.
#
# Usage:
#   docker build \
#     --build-arg BASE_IMAGE=cpp-bench:latest \
#     --build-arg BASE_IMAGE_ID="$(docker image inspect --format '{{.Id}}' cpp-bench:latest)" \
#     --build-arg CODEX_VERSION=0.199.0 \
#     --build-arg USERNAME=brett \
#     --build-arg USER_UID=1000 \
#     --build-arg USER_GID=1000 \
#     --build-arg EXTRA_CHOWN_DIRS="/opt/vcpkg" \
#     -t cpp-bench:brett .

ARG BASE_IMAGE=workbench-base:latest
FROM ${BASE_IMAGE}

# Container version labels
LABEL layer="3"
LABEL layer.name="user-layer"
LABEL layer.version="1.2.2"
LABEL layer.description="User personalization layer"

# Build arguments
ARG USERNAME=brett
ARG USER_UID=1000
ARG USER_GID=1000
ARG DOCKER_SOCKET_GID=""
ARG EXTRA_CHOWN_DIRS=""
ARG LAYER3_RECIPE_SHA256="unknown"
ARG BASE_IMAGE_ID=""
# Keep the writable user overlay aligned with the exact shared Layer 0
# version. user-layer/build.sh derives this value from BASE_IMAGE; direct
# Dockerfile callers must pass an exact reviewed version.
ARG CODEX_VERSION=""

RUN printf '%s\n' "$BASE_IMAGE_ID" | grep -Eq '^sha256:[0-9a-fA-F]{64}$'

LABEL io.opensoft.workbenches.layer3.recipe-sha256="${LAYER3_RECIPE_SHA256}"
LABEL io.opensoft.workbenches.layer3.username="${USERNAME}"
LABEL io.opensoft.workbenches.layer3.uid="${USER_UID}"
LABEL io.opensoft.workbenches.layer3.gid="${USER_GID}"
LABEL io.opensoft.workbenches.layer3.docker-socket-gid="${DOCKER_SOCKET_GID}"
LABEL io.opensoft.workbenches.layer3.base-image-id="${BASE_IMAGE_ID}"

USER root

# Corepack's shared base-layer cache is root-owned. Route Corepack and its
# package-manager shims through a runtime wrapper that selects a writable cache
# from the effective user's passwd home. Preserve the original Corepack entry
# points before intercepting both common PATH locations; mounted shell configs
# may put /usr/bin ahead of /usr/local/bin.
COPY corepack-user-cache /usr/local/libexec/workbenches-corepack-user-cache
RUN set -eux && \
    chmod 0755 /usr/local/libexec/workbenches-corepack-user-cache && \
    mkdir -p /usr/local/libexec/workbenches-corepack-original && \
    for command in corepack pnpm pnpx yarn yarnpkg; do \
        if [ -e "/usr/bin/$command" ] || [ -L "/usr/bin/$command" ]; then \
            original_command="/usr/bin/$command"; \
        elif [ -e "/usr/local/bin/$command" ] || [ -L "/usr/local/bin/$command" ]; then \
            original_command="/usr/local/bin/$command"; \
        else \
            echo "Required Corepack command is unavailable: $command" >&2; \
            exit 1; \
        fi; \
        preserved_command="${original_command}.workbenches-original"; \
        mv "$original_command" "$preserved_command"; \
        test -x "$preserved_command"; \
        ln -sfn "$preserved_command" "/usr/local/libexec/workbenches-corepack-original/$command"; \
        ln -sfn /usr/local/libexec/workbenches-corepack-user-cache "/usr/local/bin/$command"; \
        ln -sfn /usr/local/libexec/workbenches-corepack-user-cache "/usr/bin/$command"; \
    done

# ========================================
# USER CREATION
# ========================================

# Remove any conflicting user, create the requested account, and verify the
# effective passwd identity. Fail the build instead of publishing labels for a
# user whose inherited UID/GID does not match the requested host identity.
RUN set -eux && \
    case "$USERNAME" in \
        root|''|[!a-z_]*|*[!a-z0-9_-]*) \
            echo "Layer 3 requires a valid non-root username" >&2; exit 1;; \
    esac && \
    case "$USER_UID" in ''|0*|*[!0-9]*) echo "Layer 3 requires a canonical positive UID" >&2; exit 1;; esac && \
    case "$USER_GID" in ''|0*|*[!0-9]*) echo "Layer 3 requires a canonical positive GID" >&2; exit 1;; esac && \
    if getent passwd "$USERNAME" >/dev/null; then \
        userdel --force --remove "$USERNAME"; \
    fi && \
    if getent passwd "$USER_UID" >/dev/null; then \
        existing_user=$(getent passwd "$USER_UID" | cut -d: -f1); \
        userdel --force --remove "$existing_user"; \
    fi && \
    # Handle existing group with target GID
    if getent group "$USER_GID" >/dev/null; then \
        existing_group=$(getent group "$USER_GID" | cut -d: -f1); \
        if getent group "$USERNAME" >/dev/null && [ "$existing_group" != "$USERNAME" ]; then \
            groupdel "$USERNAME"; \
        fi; \
        [ "$existing_group" = "$USERNAME" ] || groupmod -n "$USERNAME" "$existing_group"; \
    elif getent group "$USERNAME" >/dev/null; then \
        groupmod -g "$USER_GID" "$USERNAME"; \
    else \
        groupadd --gid "$USER_GID" "$USERNAME"; \
    fi && \
    useradd --uid "$USER_UID" --gid "$USERNAME" -m -s /bin/zsh "$USERNAME" && \
    getent passwd "$USERNAME" | awk -F: -v uid="$USER_UID" -v gid="$USER_GID" \
        '$3 == uid && $4 == gid { found = 1 } END { exit !found }' && \
    # Add to sudoers
    mkdir -p /etc/sudoers.d && \
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME && \
    chmod 0440 /etc/sudoers.d/$USERNAME

# If the host Docker socket is mounted later, give the user a matching group in
# the image so non-root Docker access works without manual fixes.
RUN if [ -n "$DOCKER_SOCKET_GID" ] && [ "$DOCKER_SOCKET_GID" != "$USER_GID" ]; then \
        if getent group "$DOCKER_SOCKET_GID" >/dev/null; then \
            docker_group=$(getent group "$DOCKER_SOCKET_GID" | cut -d: -f1); \
        else \
            docker_group=docker-host; \
            if getent group "$docker_group" >/dev/null; then \
                groupmod -g "$DOCKER_SOCKET_GID" "$docker_group"; \
            else \
                groupadd --gid "$DOCKER_SOCKET_GID" "$docker_group"; \
            fi; \
        fi; \
        usermod -aG "$docker_group" "$USERNAME"; \
    fi

# Set default shell to zsh
RUN chsh -s /bin/zsh $USERNAME

# ========================================
# DIRECTORY OWNERSHIP
# ========================================

# Ensure the workspace exists even if the base image tag is stale, then hand it
# to the runtime user.
RUN mkdir -p /workspace && chown -R $USERNAME:$USERNAME /workspace

# Grant user write access to bench-specific directories (e.g. /opt/flutter, /opt/android-sdk)
# IMPORTANT: No recursive chown/chmod here! Recursive metadata changes on multi-GB
# SDK trees trigger Docker copy-on-write on every file, creating a huge duplicate
# layer (~15GB) that causes containerd lease-timeout failures during export.
# Layer 2 sets these dirs to 775/root:root. We add the user to the root group
# so they get group-write access without touching any file metadata.
RUN if [ -n "$EXTRA_CHOWN_DIRS" ]; then \
        usermod -aG root $USERNAME; \
    fi

# ========================================
# USER-SPECIFIC CONFIGURATION
# ========================================

USER $USERNAME

# User-owned Codex overlay. Keep the shared Layer 0 package root-owned while
# allowing the runtime user to run `codex update` against this writable prefix.
ENV NPM_CONFIG_PREFIX=/home/${USERNAME}/.npm-global
ENV PATH=/home/${USERNAME}/.npm-global/bin:${PATH}
RUN test -n "$CODEX_VERSION" \
    && printf '%s\n' "$CODEX_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$' \
    && mkdir -p "$NPM_CONFIG_PREFIX" \
    && npm install -g "@openai/codex@${CODEX_VERSION}" \
    && test "$(codex --version | awk 'NR == 1 { print $NF; exit }')" = "$CODEX_VERSION"

# Pre-create user-owned cache roots so first-use named volumes inherit the
# runtime user's ownership instead of becoming root-only.
RUN mkdir -p \
        /home/$USERNAME/.vscode-server/extensions \
        /home/$USERNAME/.cargo

# Configure git credential helper
RUN git config --global credential.helper gh

# Avoid first-run Flutter telemetry prompts in images that include Flutter.
RUN if command -v flutter >/dev/null 2>&1; then \
        flutter config --no-analytics || true; \
    fi

WORKDIR /workspace

# Default command
CMD ["sleep", "infinity"]
