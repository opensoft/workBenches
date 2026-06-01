# Shared SonarQube/SonarCloud environment for devBench-derived containers.
# This file is sourceable from bash, zsh, or /etc/profile.d.

if [ -n "${HOME:-}" ]; then
    if [ -z "${SONARQUBE_ENV_FILE:-}" ]; then
        export SONARQUBE_ENV_FILE="$HOME/.config/sonarqube/sonar.env"
    fi

    if [ -z "${SONARQUBE_CLI_DIR:-}" ]; then
        export SONARQUBE_CLI_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sonarqube-cli"
    fi

    mkdir -p "$SONARQUBE_CLI_DIR" 2>/dev/null || true
    chmod 700 "$SONARQUBE_CLI_DIR" 2>/dev/null || true

    if [ -z "${SONARQUBE_CLI_KEYCHAIN_FILE:-}" ]; then
        export SONARQUBE_CLI_KEYCHAIN_FILE="$SONARQUBE_CLI_DIR/keychain.json"
    fi

    if [ -f "$SONARQUBE_ENV_FILE" ]; then
        while IFS='=' read -r _sonar_key _sonar_value || [ -n "$_sonar_key" ]; do
            case "$_sonar_key" in
                ''|\#*) continue ;;
                SONARQUBE_TOKEN|SONARQUBE_ORG|SONAR_TOKEN|SONAR_ORGANIZATION|SONAR_HOST_URL|SONARQUBE_URL)
                    export "$_sonar_key=$_sonar_value"
                    ;;
            esac
        done < "$SONARQUBE_ENV_FILE"
        unset _sonar_key _sonar_value
    fi
fi

if [ -n "${SONARQUBE_TOKEN:-}" ]; then
    export SONAR_TOKEN="$SONARQUBE_TOKEN"
fi

if [ -z "${SONARQUBE_TOKEN:-}" ] && [ -n "${SONAR_TOKEN:-}" ]; then
    export SONARQUBE_TOKEN="$SONAR_TOKEN"
fi

if [ -n "${SONARQUBE_TOKEN:-}" ]; then
    export SONARQUBE_CLI_TOKEN="$SONARQUBE_TOKEN"
fi

if [ -z "${SONAR_HOST_URL:-}" ] && [ -n "${SONARQUBE_URL:-}" ]; then
    export SONAR_HOST_URL="$SONARQUBE_URL"
fi

if [ -z "${SONAR_HOST_URL:-}" ]; then
    export SONAR_HOST_URL="https://sonarcloud.io"
fi

if [ -z "${SONARQUBE_URL:-}" ]; then
    export SONARQUBE_URL="$SONAR_HOST_URL"
fi

if [ -z "${SONARQUBE_CLI_SERVER:-}" ]; then
    export SONARQUBE_CLI_SERVER="$SONAR_HOST_URL"
fi

if [ -z "${SONAR_ORGANIZATION:-}" ] && [ -n "${SONARQUBE_ORG:-}" ]; then
    export SONAR_ORGANIZATION="$SONARQUBE_ORG"
fi

if [ -z "${SONARQUBE_ORG:-}" ] && [ -n "${SONAR_ORGANIZATION:-}" ]; then
    export SONARQUBE_ORG="$SONAR_ORGANIZATION"
fi

if [ -z "${SONARQUBE_CLI_ORG:-}" ] && [ -n "${SONARQUBE_ORG:-}" ]; then
    export SONARQUBE_CLI_ORG="$SONARQUBE_ORG"
fi

if [ -n "${SONARQUBE_CLI_KEYCHAIN_FILE:-}" ] && [ -f "$SONARQUBE_CLI_KEYCHAIN_FILE" ]; then
    chmod 600 "$SONARQUBE_CLI_KEYCHAIN_FILE" 2>/dev/null || true
fi
