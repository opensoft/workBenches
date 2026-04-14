# Layer 3: User Personalization
# Thin layer that creates a user matching the host UID/GID.
# /etc/skel content (oh-my-zsh, shell configs, aliases) is copied
# automatically by useradd -m.
#
# Usage:
#   docker build \
#     --build-arg BASE_IMAGE=cpp-bench:latest \
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
LABEL layer.version="1.2.0"
LABEL layer.description="User personalization layer"

# Build arguments
ARG USERNAME=brett
ARG USER_UID=1000
ARG USER_GID=1000
ARG DOCKER_SOCKET_GID=""
ARG EXTRA_CHOWN_DIRS=""

USER root

# ========================================
# USER CREATION
# ========================================

# Remove any existing user/group with target UID/GID, then create new user
RUN set -eux && \
    # Remove existing user with target UID if exists
    if getent passwd "$USER_UID" >/dev/null; then \
        existing_user=$(getent passwd "$USER_UID" | cut -d: -f1) && \
        userdel --force --remove $existing_user 2>/dev/null || true; \
    fi && \
    # Handle existing group with target GID
    if getent group "$USER_GID" >/dev/null; then \
        existing_group=$(getent group "$USER_GID" | cut -d: -f1) && \
        groupmod -n $USERNAME $existing_group 2>/dev/null || true; \
    else \
        groupadd --gid $USER_GID $USERNAME 2>/dev/null || true; \
    fi && \
    # Create user (-m copies /etc/skel to home directory)
    if ! getent passwd "$USERNAME" >/dev/null; then \
        useradd --uid $USER_UID --gid $USERNAME -m -s /bin/zsh $USERNAME 2>/dev/null || true; \
    fi && \
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

# Pre-create .vscode-server so volume mounts inherit correct ownership
RUN mkdir -p /home/$USERNAME/.vscode-server/extensions

# Configure git credential helper
RUN git config --global credential.helper gh

# Avoid first-run Flutter telemetry prompts in images that include Flutter.
RUN if command -v flutter >/dev/null 2>&1; then \
        flutter config --no-analytics || true; \
    fi

WORKDIR /workspace

# Default command
CMD ["sleep", "infinity"]
