# Layer 3: User Personalization
# Thin layer on top of Layer 2 (cpp-bench) pulled from registry
# Only handles: user creation, UID/GID matching, default shell
# All configs (shell, creds, SSH) are mounted at runtime via docker-compose.yml

ARG BASE_IMAGE=cpp-bench:latest
FROM ${BASE_IMAGE}

LABEL layer="3"
LABEL layer.name="cpp-bench-user"
LABEL layer.description="User personalization for cpp-bench"

# Build args - passed from docker-compose.yml
ARG USERNAME=brett
ARG USER_UID=1000
ARG USER_GID=1000

USER root

# ========================================
# USER MANAGEMENT
# ========================================

# Remove existing user/group with target UID/GID if they conflict,
# then create the host user with matching UID/GID
RUN set -eux && \
    # Remove existing user with target UID if it's not our user
    if getent passwd "$USER_UID" >/dev/null; then \
        existing_user=$(getent passwd "$USER_UID" | cut -d: -f1) && \
        if [ "$existing_user" != "$USERNAME" ]; then \
            userdel --force --remove "$existing_user" 2>/dev/null || true; \
        fi; \
    fi && \
    # Handle existing group with target GID
    if getent group "$USER_GID" >/dev/null; then \
        existing_group=$(getent group "$USER_GID" | cut -d: -f1) && \
        if [ "$existing_group" != "$USERNAME" ]; then \
            groupmod -n "$USERNAME" "$existing_group" 2>/dev/null || true; \
        fi; \
    else \
        groupadd --gid "$USER_GID" "$USERNAME" 2>/dev/null || true; \
    fi && \
    # Create user if it doesn't exist
    if ! getent passwd "$USERNAME" >/dev/null; then \
        useradd --uid "$USER_UID" --gid "$USERNAME" -m -s /bin/zsh "$USERNAME" 2>/dev/null || true; \
    fi && \
    # Ensure user has correct UID/GID and shell
    usermod -u "$USER_UID" -g "$USER_GID" -s /bin/zsh "$USERNAME" 2>/dev/null || true && \
    # Add to sudo and docker groups
    usermod -aG sudo "$USERNAME" 2>/dev/null || true && \
    usermod -aG docker "$USERNAME" 2>/dev/null || true && \
    # Passwordless sudo
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" && \
    chmod 0440 "/etc/sudoers.d/$USERNAME" && \
    # Ensure home directory ownership
    mkdir -p "/home/$USERNAME" && \
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME" && \
    # Ensure workspace ownership
    mkdir -p /workspace && \
    chown "$USERNAME:$USERNAME" /workspace

# Set SHELL environment variable
ENV SHELL=/bin/zsh

# Switch to the host user
USER $USERNAME
WORKDIR /workspace

CMD ["sleep", "infinity"]
