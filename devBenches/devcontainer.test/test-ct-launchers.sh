#!/bin/bash
# Verify ct launcher helpers apply the expected permissive defaults per CLI.

set -euo pipefail

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

REPO_ROOT="$TMPDIR_ROOT/repo"
TARGET_DIR="$TMPDIR_ROOT/worktree-target"
BIN_DIR="$TMPDIR_ROOT/bin"
LOG_DIR="$TMPDIR_ROOT/logs"

mkdir -p \
    "$REPO_ROOT/.specify/extensions/git/scripts/bash" \
    "$REPO_ROOT/.specify/shell" \
    "$TARGET_DIR" \
    "$BIN_DIR" \
    "$LOG_DIR"

git init -q "$REPO_ROOT"

cat > "$REPO_ROOT/.specify/extensions/git/scripts/bash/get-last-worktree.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\${1:-}" = "--json" ]; then
    printf '{"WORKTREE_PATH":"%s"}\n' "$TARGET_DIR"
else
    printf '%s\n' "$TARGET_DIR"
fi
EOF

cat > "$REPO_ROOT/.specify/shell/select-worktree.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\${1:-}" = "--list" ]; then
    printf '1. fake-branch [default]\n'
    printf '   %s\n' "$TARGET_DIR"
else
    printf '%s\n' "$TARGET_DIR"
fi
EOF

chmod +x \
    "$REPO_ROOT/.specify/extensions/git/scripts/bash/get-last-worktree.sh" \
    "$REPO_ROOT/.specify/shell/select-worktree.sh"

for cli in claude codex gemini; do
    cat > "$BIN_DIR/$cli" <<EOF
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'pwd=%s\n' "\$PWD"
    for arg in "\$@"; do
        printf 'arg=%s\n' "\$arg"
    done
    printf '%s\n' '---'
} >> "$LOG_DIR/$cli.log"
EOF
    chmod +x "$BIN_DIR/$cli"
done

cat > "$BIN_DIR/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    set-option)
        exit 0
        ;;
    *)
        echo "unexpected tmux command: $*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$BIN_DIR/tmux"

export PATH="$BIN_DIR:$PATH"
export TMUX="${TMUX:-test-tmux}"

# shellcheck source=/dev/null
source "${CT_FUNCTIONS_FILE:-/usr/local/share/ct/ct-functions.zsh}"

cd "$REPO_ROOT"
cta --claude-extra
cd "$REPO_ROOT"
ctc --codex-extra
cd "$REPO_ROOT"
ctg --gemini-extra
cd "$REPO_ROOT"

_ct_prompt_cli() {
    printf 'codex\n'
}

cts --cts-extra

grep -Fx "pwd=$TARGET_DIR" "$LOG_DIR/claude.log" >/dev/null
grep -Fx "arg=--model" "$LOG_DIR/claude.log" >/dev/null
grep -Fx "arg=opus" "$LOG_DIR/claude.log" >/dev/null
grep -Fx "arg=--dangerously-skip-permissions" "$LOG_DIR/claude.log" >/dev/null
grep -Fx "arg=--permission-mode" "$LOG_DIR/claude.log" >/dev/null
grep -Fx "arg=bypassPermissions" "$LOG_DIR/claude.log" >/dev/null
grep -Fx "arg=--claude-extra" "$LOG_DIR/claude.log" >/dev/null

grep -Fx "pwd=$TARGET_DIR" "$LOG_DIR/codex.log" >/dev/null
[ "$(grep -c '^arg=--dangerously-bypass-approvals-and-sandbox$' "$LOG_DIR/codex.log")" -eq 2 ]
[ "$(grep -c '^arg=-m$' "$LOG_DIR/codex.log")" -eq 2 ]
[ "$(grep -c '^arg=gpt-5.4$' "$LOG_DIR/codex.log")" -eq 2 ]
[ "$(grep -c '^arg=-c$' "$LOG_DIR/codex.log")" -eq 2 ]
[ "$(grep -c '^arg=model_reasoning_effort=\"high\"$' "$LOG_DIR/codex.log")" -eq 2 ]
grep -Fx "arg=--codex-extra" "$LOG_DIR/codex.log" >/dev/null
grep -Fx "arg=--cts-extra" "$LOG_DIR/codex.log" >/dev/null

grep -Fx "pwd=$TARGET_DIR" "$LOG_DIR/gemini.log" >/dev/null
grep -Fx "arg=--yolo" "$LOG_DIR/gemini.log" >/dev/null
grep -Fx "arg=--approval-mode" "$LOG_DIR/gemini.log" >/dev/null
grep -Fx "arg=yolo" "$LOG_DIR/gemini.log" >/dev/null
grep -Fx "arg=--model" "$LOG_DIR/gemini.log" >/dev/null
grep -Fx "arg=gemini-2.5-pro" "$LOG_DIR/gemini.log" >/dev/null
grep -Fx "arg=--gemini-extra" "$LOG_DIR/gemini.log" >/dev/null
