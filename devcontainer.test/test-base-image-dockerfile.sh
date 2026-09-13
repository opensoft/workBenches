#!/usr/bin/env bash
set -euo pipefail

# base-image/Dockerfile must COPY every files/* launcher dependency that
# base-image/files/claude-profile falls back to when no host-mounted profile
# base (a `$base/shared/...` path) provides it — at the exact in-container
# path the launcher reads. Nothing else statically checks the Dockerfile's
# shape: the only post-build check is devcontainer.test/test.sh, and that
# requires a full image build (bun, oh-my-zsh, the AI CLIs, ...), so it never
# runs as part of source review. claude-usage-guard.sh shipped in
# base-image/files/, and claude-profile's fallback path for it was wired and
# tested, but nothing copied the file into the image — the ratified Amendment
# 11 automatic usage swap was silently unwired inside every bench container.
# This is a cheap, source-only (no `docker build`) regression guard against
# exactly that class of drift.
#
# Mutation-tested: deleting the `usage-guard.sh` COPY line (or its chmod
# entry) from base-image/Dockerfile makes this fail; restoring it passes.

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
dockerfile="$repo_root/base-image/Dockerfile"
launcher="$repo_root/base-image/files/claude-profile"

# The in-container fallback path claude-profile uses for the usage guard when
# $base/shared/usage-guard.sh (a host-mounted profile base) is absent — read
# from the launcher itself so this test tracks the launcher, not a hardcoded
# guess of its destination.
guard_dest="$(sed -nE 's/^[[:space:]]*guard_source=(\/usr\/local\/share\/workbenches\/claude\/usage-guard\.sh)$/\1/p' "$launcher" | head -n1)"
[ -n "$guard_dest" ] || {
    echo "FAIL: could not read claude-profile's in-container usage-guard.sh fallback path (guard_source=... assignment not found or changed shape)" >&2
    exit 1
}

grep -Fq "COPY files/claude-usage-guard.sh $guard_dest" "$dockerfile" || {
    echo "FAIL: base-image/Dockerfile does not COPY files/claude-usage-guard.sh to $guard_dest (claude-profile's own fallback path) — the Amendment 11 automatic usage swap is unwired inside a bench container" >&2
    exit 1
}

# Same launcher-provisioning RUN command that chmods claude-profile,
# codex-profile, statusline-command.sh, etc. — the copied guard script should
# be set 0755 alongside them, the same way statusline-command.sh is (both are
# only ever invoked as `bash <path>`, but the block chmods every file it
# provisions uniformly; see files/claude-profile's guard_command).
chmod_run="$(awk '/^RUN chmod 0755 /{p=1} p{print; if ($0 !~ /\\$/) exit}' "$dockerfile")"
grep -Fq "$guard_dest" <<<"$chmod_run" || {
    echo "FAIL: base-image/Dockerfile copies $guard_dest but the chmod 0755 block beside it never mentions that path" >&2
    exit 1
}

printf 'base-image/Dockerfile provisions claude-usage-guard.sh at the path claude-profile expects\n'
