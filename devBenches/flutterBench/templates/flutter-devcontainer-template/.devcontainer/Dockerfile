# Lightweight Flutter Project Container
# Based on FlutterBench but stripped down for individual project use
FROM ubuntu:24.04

# ====================================
# Build Arguments (from .env via docker-compose)
# ====================================
ARG USER_NAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000
ARG FLUTTER_VERSION=3.24.0
ARG ANDROID_HOME=/home/vscode/android-sdk
ARG DEBUG_MODE=false

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Set DEBUG as environment variable for runtime access
ENV DEBUG_MODE=${DEBUG_MODE}

# ========================================
# PHASE 1: MINIMAL SYSTEM SETUP
# ========================================

# Install only essential system packages
RUN apt-get update && apt-get install -y \
    # Core utilities
    curl \
    wget \
    git \
    unzip \
    xz-utils \
    ca-certificates \
    # Flutter/Android essentials
    libglu1-mesa \
    openjdk-17-jdk \
    android-tools-adb \
    android-tools-fastboot \
    # User management
    sudo \
    # Shell essentials
    zsh \
    bash \
    # Basic tools for debugging
    less \
    nano \
    tree \
    jq \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# PHASE 2: USER SETUP
# ========================================

# Create user with matching host UID/GID (with conflict handling)
RUN set -eux && \
    # Remove existing user/group with same UID/GID if they exist
    if getent passwd "$USER_UID" >/dev/null; then \
        userdel --force --remove $(getent passwd "$USER_UID" | cut -d: -f1); \
    fi && \
    if getent group "$USER_GID" >/dev/null; then \
        groupdel $(getent group "$USER_GID" | cut -d: -f1); \
    fi && \
    # Create new group and user
    groupadd --gid $USER_GID $USER_NAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/zsh $USER_NAME \
    && echo $USER_NAME ALL=\(ALL\) NOPASSWD:ALL > /etc/sudoers.d/$USER_NAME \
    && chmod 0440 /etc/sudoers.d/$USER_NAME

# Switch to user
USER $USER_NAME
WORKDIR /home/$USER_NAME

# ========================================
# PHASE 3: FLUTTER SETUP (LIGHTWEIGHT)
# ========================================

# Set Flutter environment variables (using ARG for configurable paths)
ENV FLUTTER_HOME="/opt/flutter"
ENV ANDROID_HOME="${ANDROID_HOME}"
ENV ANDROID_SDK_ROOT="${ANDROID_HOME}"
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# Install Flutter (version from .env)
RUN sudo mkdir -p $FLUTTER_HOME \
    && if [ "$FLUTTER_VERSION" = "stable" ] || [ "$FLUTTER_VERSION" = "beta" ] || [ "$FLUTTER_VERSION" = "dev" ]; then \
         curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/${FLUTTER_VERSION}/linux/flutter_linux_${FLUTTER_VERSION}.tar.xz | sudo tar -xJC /opt; \
       else \
         curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz | sudo tar -xJC /opt; \
       fi \
    && sudo chown -R $USER_NAME:$USER_NAME $FLUTTER_HOME

# Install minimal Android SDK (just what's needed for ADB)
RUN mkdir -p $ANDROID_HOME \
    && curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /tmp/cmdtools.zip \
    && unzip /tmp/cmdtools.zip -d $ANDROID_HOME \
    && rm /tmp/cmdtools.zip \
    && mv $ANDROID_HOME/cmdline-tools $ANDROID_HOME/tools \
    && mkdir -p $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/tools $ANDROID_HOME/cmdline-tools/latest

# Accept licenses and install minimal SDK components (just basics for debugging)
RUN yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --licenses \
    && $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager \
    "platform-tools" \
    "platforms;android-34" \
    "build-tools;34.0.0"

# Configure Flutter (minimal setup)
RUN flutter config --no-analytics \
    && flutter config --android-sdk $ANDROID_HOME

# ========================================
# PHASE 4: SHELL SETUP (MINIMAL)
# ========================================

# Install Oh My Zsh (for better developer experience)
RUN curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh -s -- --unattended || \
    echo "Oh My Zsh installation failed, using default zsh"

# Add essential environment variables to shell configs
RUN echo "export FLUTTER_HOME=\"$FLUTTER_HOME\"" >> ~/.bashrc \
    && echo "export ANDROID_HOME=\"$ANDROID_HOME\"" >> ~/.bashrc \
    && echo "export ANDROID_SDK_ROOT=\"$ANDROID_HOME\"" >> ~/.bashrc \
    && echo "export PATH=\"\$FLUTTER_HOME/bin:\$FLUTTER_HOME/bin/cache/dart-sdk/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH\"" >> ~/.bashrc \
    && echo "export ADB_SERVER_SOCKET=tcp:shared-adb-server:5037" >> ~/.bashrc \
    && echo "export FLUTTER_HOME=\"$FLUTTER_HOME\"" >> ~/.zshrc \
    && echo "export ANDROID_HOME=\"$ANDROID_HOME\"" >> ~/.zshrc \
    && echo "export ANDROID_SDK_ROOT=\"$ANDROID_HOME\"" >> ~/.zshrc \
    && echo "export PATH=\"\$FLUTTER_HOME/bin:\$FLUTTER_HOME/bin/cache/dart-sdk/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH\"" >> ~/.zshrc \
    && echo "export ADB_SERVER_SOCKET=tcp:shared-adb-server:5037" >> ~/.zshrc \
    && echo "export DEBUG_MODE=\"$DEBUG_MODE\"" >> ~/.bashrc \
    && echo "export DEBUG_MODE=\"$DEBUG_MODE\"" >> ~/.zshrc

# ========================================
# PHASE 5: WORKSPACE SETUP
# ========================================

# Set up workspace
WORKDIR /workspace

# Expose Flutter development ports
EXPOSE 8080 8181 9100

# Keep container running
CMD ["sleep", "infinity"]
