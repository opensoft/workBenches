#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 ENV_FILE USER_NAME" >&2
  exit 2
fi

env_file="$1"
user_name="$2"
tmp_file="$(mktemp)"

mkdir -p "$(dirname "$env_file")"

if [ -f "$env_file" ]; then
  grep -v -E '^(USER|USER_NAME)=' "$env_file" > "$tmp_file" || true
fi

{
  printf 'USER=%s\n' "$user_name"
  printf 'USER_NAME=%s\n' "$user_name"
} >> "$tmp_file"

mv "$tmp_file" "$env_file"
