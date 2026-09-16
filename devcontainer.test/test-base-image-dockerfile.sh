#!/usr/bin/env bash
set -euo pipefail

# TWO DOCKERFILES, ONE JOB — this suite is the source-only guard on both.
#
# Part 1 (Layer 0, base-image/Dockerfile):
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
#
# Part 2 (Layer 2, devBenches/base-image/Dockerfile), added for opensoft/
# workBenches#90: the container-start step that reinstalls the estate's lane
# commands after a recreate is three instructions and a running script, and NO
# suite in this repository can run `docker build` — the tests themselves run
# inside a bench container. The script's behaviour is covered by
# devcontainer.test/test-setup-estate-commands.sh, which runs it for real
# against a sandboxed $HOME; what is left over is exactly the wiring, and this
# is where it is asserted: that the vendored tree the installer needs beside
# itself is copied WHOLE (skills/ and commands/ included, or six of the
# twenty-six artifacts would be fetched over the network at container start),
# that the step and the entrypoint land at the paths they themselves name, and
# that ENTRYPOINT is declared ABOVE CMD — because an ENTRYPOINT instruction
# resets a CMD inherited from the base image, so the wrong order would leave
# every dev bench with no default command, which is a broken container rather
# than a missing feature.

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

# ---------------------------------------------------------------------------
# Part 2: devBenches/base-image/Dockerfile and the opensoft/workBenches#90
# container-start step.

dev_dockerfile="$repo_root/devBenches/base-image/Dockerfile"
estate_start="$repo_root/devBenches/base-image/files/estate/estate-commands-start"
estate_entrypoint="$repo_root/devBenches/base-image/files/estate/workbench-entrypoint"

for f in "$dev_dockerfile" "$estate_start" "$estate_entrypoint"; do
    [ -f "$f" ] || {
        echo "FAIL: $f is missing — the workBenches#90 container-start step is not there to wire" >&2
        exit 1
    }
done

# The two in-container paths are read from the scripts themselves, never
# guessed here, exactly as the usage-guard path above is read from
# claude-profile: this suite tracks what the scripts say, so renaming a
# destination in one place and not the other is what fails, not a stale
# constant in a test.
vendor_dir="$(sed -nE 's#^ESTATE_VENDOR_DIR="\$\{WORKBENCHES_ESTATE_VENDOR_DIR:-(/[^}"]+)\}"$#\1#p' "$estate_start" | head -n1)"
[ -n "$vendor_dir" ] || {
    echo "FAIL: could not read estate-commands-start's own vendored-tree path (the ESTATE_VENDOR_DIR default assignment is missing or changed shape)" >&2
    exit 1
}

# The DEFAULT of the entrypoint's own parameter expansion, not the seam that
# overrides it: `WORKBENCHES_ENTRYPOINT_STEP` exists so the behavioural suite
# can run that file for real, and reading the default here is what stops the
# seam drifting away from the path the image actually COPYs the step to.
start_dest="$(sed -nE 's#^ESTATE_START="\$\{WORKBENCHES_ENTRYPOINT_STEP:-(/[^}"]+)\}"$#\1#p' "$estate_entrypoint" | head -n1)"
[ -n "$start_dest" ] || {
    echo "FAIL: could not read workbench-entrypoint's own path for the start-up step (the ESTATE_START assignment is missing or changed shape)" >&2
    exit 1
}

# WHOLE TREE, not file by file. `openRepoTools --install` copies each of its
# twenty-six artifacts from its own directory when they are beside it and
# FETCHES the ones that are not, so a COPY that carried only the twelve bin
# files would send the three skills and three command files to the network on
# every container start — the one thing the vendoring note in that Dockerfile
# forbids.
grep -Fq "COPY files/openrepotools/ $vendor_dir/" "$dev_dockerfile" || {
    echo "FAIL: devBenches/base-image/Dockerfile does not COPY the whole vendored openrepotools tree to $vendor_dir/ (the path estate-commands-start runs --install from)" >&2
    exit 1
}
for needed in skills/handoff/SKILL.md commands/handoff.md link-estates openRepoTools; do
    [ -e "$repo_root/devBenches/base-image/files/openrepotools/$needed" ] || {
        echo "FAIL: devBenches/base-image/files/openrepotools/$needed is missing, so the COPY above cannot carry a complete install set into the image" >&2
        exit 1
    }
done

grep -Fq "COPY files/estate/estate-commands-start $start_dest" "$dev_dockerfile" || {
    echo "FAIL: devBenches/base-image/Dockerfile does not COPY files/estate/estate-commands-start to $start_dest (the path workbench-entrypoint runs)" >&2
    exit 1
}

grep -Fq 'COPY files/estate/workbench-entrypoint /usr/local/bin/workbench-entrypoint' "$dev_dockerfile" || {
    echo "FAIL: devBenches/base-image/Dockerfile does not COPY files/estate/workbench-entrypoint into the image" >&2
    exit 1
}

# Every `RUN chmod 0755 ...` block in the file, continuations included — both
# new files must be made executable by one of them, the same belt-and-braces
# the Layer 0 half above applies to the usage guard.
dev_chmod_runs="$(awk '/^RUN chmod 0755 /{p=1} p{print; if ($0 !~ /\\$/) p=0}' "$dev_dockerfile")"
for path in "$start_dest" /usr/local/bin/workbench-entrypoint; do
    grep -Fq "$path" <<<"$dev_chmod_runs" || {
        echo "FAIL: devBenches/base-image/Dockerfile copies $path but no chmod 0755 block mentions it — it would land unexecutable and the step would never run" >&2
        exit 1
    }
done

grep -Fq 'ENTRYPOINT ["/usr/local/bin/workbench-entrypoint"]' "$dev_dockerfile" || {
    echo "FAIL: devBenches/base-image/Dockerfile never wires ENTRYPOINT to /usr/local/bin/workbench-entrypoint — a recreate would come up with no estate commands again (opensoft/workBenches#90)" >&2
    exit 1
}

# THE ORDER IS THE ASSERTION. An ENTRYPOINT instruction resets a CMD inherited
# from the base image; the image's own `CMD ["sleep", "infinity"]` must be
# declared after it or every dev bench comes up with no default command.
entrypoint_line="$(grep -n '^ENTRYPOINT ' "$dev_dockerfile" | head -n1 | cut -d: -f1)"
cmd_line="$(grep -n '^CMD ' "$dev_dockerfile" | tail -n1 | cut -d: -f1)"
[ -n "$entrypoint_line" ] && [ -n "$cmd_line" ] || {
    echo "FAIL: devBenches/base-image/Dockerfile is missing an ENTRYPOINT or a CMD line" >&2
    exit 1
}
[ "$entrypoint_line" -lt "$cmd_line" ] || {
    echo "FAIL: devBenches/base-image/Dockerfile declares ENTRYPOINT (line $entrypoint_line) after CMD (line $cmd_line) — the ENTRYPOINT resets the inherited CMD, so the benches would have no default command" >&2
    exit 1
}

printf 'devBenches/base-image/Dockerfile wires the workBenches#90 container-start step: vendored tree at %s, step at %s, ENTRYPOINT (line %s) above CMD (line %s)\n' \
    "$vendor_dir" "$start_dest" "$entrypoint_line" "$cmd_line"
