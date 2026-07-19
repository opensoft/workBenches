#!/usr/bin/env bash
set -euo pipefail

command="${1:-status}"
case "$command" in
  status|check|info)
    exec claude auth status --text
    ;;
  get|export)
    echo "Refusing to expose Claude credential contents." >&2
    echo "Use 'claude auth status --text' or the AI Harness Account Manager." >&2
    exit 2
    ;;
  help|-h|--help)
    cat <<'EOF'
Usage: claude-session-helper.sh [status]

Compatibility wrapper for safe Claude authentication status checks. Raw OAuth
tokens are never printed or exported.
EOF
    ;;
  *)
    echo "Unknown command: $command" >&2
    exit 2
    ;;
esac
