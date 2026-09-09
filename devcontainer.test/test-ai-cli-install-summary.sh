#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for installer in \
    "$repo_root/base-image/install-ai-clis.sh" \
    "$repo_root/devBenches/base-image/install-ai-clis.sh"; do
    bash -n "$installer"
    summary_block="$(sed -n '/^if command -v chelper /,/^fi$/p' "$installer")"
    grep -Fq 'command -v chelper' <<<"$summary_block"
    grep -Fq 'Z.AI Coding Plan helper (chelper)' <<<"$summary_block"
    grep -Fq '[install skipped or failed]' <<<"$summary_block"

    minimax_summary_block="$(sed -n '/^if command -v mcode /,/^fi$/p' "$installer")"
    grep -Fq 'command -v mcode' <<<"$minimax_summary_block"
    grep -Fq "\$HOME/.minimax-code/bin/mcode" <<<"$minimax_summary_block"
    grep -Fq 'MiniMax Code (mcode)' <<<"$minimax_summary_block"
    grep -Fq '[install skipped or failed]' <<<"$minimax_summary_block"
done

printf 'ai-cli optional install summaries are status-aware\n'
