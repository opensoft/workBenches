# Shared SonarQube/SonarCloud environment for devBench-derived containers.
# This file is sourceable from bash, zsh, or /etc/profile.d.

if [ -n "${HOME:-}" ]; then
    if [ -z "${SONARQUBE_ENV_FILE:-}" ]; then
        export SONARQUBE_ENV_FILE="$HOME/.config/sonarqube/sonar.env"
    fi

    if [ ! -f "$SONARQUBE_ENV_FILE" ] && [ -f "$HOME/.config/ledgerlinc/secrets/sonar.env" ]; then
        export SONARQUBE_ENV_FILE="$HOME/.config/ledgerlinc/secrets/sonar.env"
    fi

    if [ -z "${SONARQUBE_CLI_DIR:-}" ]; then
        export SONARQUBE_CLI_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sonarqube-cli"
    fi

    mkdir -p "$SONARQUBE_CLI_DIR" 2>/dev/null || true

    if [ -z "${SONARQUBE_CLI_KEYCHAIN_FILE:-}" ]; then
        export SONARQUBE_CLI_KEYCHAIN_FILE="$SONARQUBE_CLI_DIR/keychain.json"
    fi

    if [ -f "$SONARQUBE_ENV_FILE" ]; then
        _sonar_restore_allexport=0
        case $- in
            *a*) _sonar_restore_allexport=1 ;;
        esac

        set -a
        # shellcheck disable=SC1090
        . "$SONARQUBE_ENV_FILE"
        if [ "$_sonar_restore_allexport" = "1" ]; then
            set -a
        else
            set +a
        fi
        unset _sonar_restore_allexport
    fi
fi

if [ -z "${SONAR_TOKEN:-}" ] && [ -n "${SONARQUBE_TOKEN:-}" ]; then
    export SONAR_TOKEN="$SONARQUBE_TOKEN"
fi

if [ -z "${SONARQUBE_TOKEN:-}" ] && [ -n "${SONAR_TOKEN:-}" ]; then
    export SONARQUBE_TOKEN="$SONAR_TOKEN"
fi

if [ -z "${SONARQUBE_CLI_TOKEN:-}" ] && [ -n "${SONARQUBE_TOKEN:-}" ]; then
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
