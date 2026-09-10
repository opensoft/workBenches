#!/usr/bin/env bash
#
# scripts/setup-estate-commands.sh
#
# Installs the estate commands on this host from workBenches' own vendored
# pin: openRepoShape, openRepoTools, park and resume, placed by the vendored
# shims' own `--install` (devBenches/base-image/files/openreposhape/openRepoShape
# and devBenches/base-image/files/openrepotools/openRepoTools). This script
# adds no install logic of its own: it runs `update-upstream.py check`, then
# the two shims, and relays their own output unchanged.
#
# Two of the four rulings of opensoft/workBenches#37 that this script
# embodies:
#   - "Version" means the pin, not a number (ruling 1): the shims' own
#     `--version` never prints the pinned commit, so this script prints the
#     two commits devBenches/base-image/upstream-pin.yaml names, read via
#     `update-upstream.py list`. It adds no version string to either shim.
#   - The host follows the pin, both ways (ruling 2): a host copy that
#     differs from the vendored one -- behind, ahead, or hand-edited -- is
#     replaced, and the shim's own per-file line says `updated`. This step
#     is best-effort and default-on in setup.sh, like the Wave widgets step:
#     it never fails setup.sh.
#
# Set WORKBENCHES_SKIP_ESTATE_COMMANDS=1 to skip this step entirely (prints
# one line, exits 0).
#
# WORKBENCHES_BASE_IMAGE_DIR overrides the base-image directory this script
# reads the pin, the checker and the vendored shims from (default:
# "<repo root>/devBenches/base-image"). This exists for the test suite's
# corruption scenario only -- point it at a throwaway copy of base-image to
# prove a corrupted vendor copy refuses to install; there is no reason to
# set it on a real host.
#
# Exit codes when run directly: 0 ok; 1 refused (update-upstream.py check
# found drift, so NOTHING was installed, or one of the two installers itself
# failed); 2 tooling missing (no python3, or a file this script needs is
# missing). setup.sh runs this under `log_header "ESTATE COMMANDS"` and
# treats any non-zero exit here as best-effort, continuing either way; this
# script is also safe to run directly, any time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_IMAGE_DIR="${WORKBENCHES_BASE_IMAGE_DIR:-$ROOT_DIR/devBenches/base-image}"

if [ "${WORKBENCHES_SKIP_ESTATE_COMMANDS:-}" = "1" ]; then
    echo "Estate command install skipped by WORKBENCHES_SKIP_ESTATE_COMMANDS=1."
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Estate command install refused: python3 is not available, and" >&2
    echo "$BASE_IMAGE_DIR/update-upstream.py needs it to check the vendored" >&2
    echo "copies against their pin. Nothing was installed." >&2
    exit 2
fi

UPDATE_UPSTREAM="$BASE_IMAGE_DIR/update-upstream.py"
SHAPE_SHIM="$BASE_IMAGE_DIR/files/openreposhape/openRepoShape"
TOOLS_SHIM="$BASE_IMAGE_DIR/files/openrepotools/openRepoTools"

missing=""
for f in "$UPDATE_UPSTREAM" "$SHAPE_SHIM" "$TOOLS_SHIM"; do
    if [ ! -f "$f" ]; then
        missing="${missing:+$missing }$f"
    fi
done
if [ -n "$missing" ]; then
    echo "Estate command install refused: missing file(s): $missing" >&2
    echo "Nothing was installed." >&2
    exit 2
fi

# Ruling 3 (drift refuses): the checker runs BEFORE anything is placed. A
# non-zero exit means the vendored bytes are not the pinned bytes, and this
# script installs NOTHING rather than spread a local edit that the pin
# exists to forbid. Its own stdout/stderr stream through unchanged above.
if ! python3 "$UPDATE_UPSTREAM" check; then
    echo "" >&2
    echo "Estate command install refused: the vendored copies do not match" >&2
    echo "$BASE_IMAGE_DIR/upstream-pin.yaml (see the finding above). NOTHING" >&2
    echo "was installed, because the vendored bytes are not the pinned bytes." >&2
    exit 1
fi

# Ruling 1 ("version" means the pin): read the two pinned commits from
# `update-upstream.py list`, which prints each source's id, then its
# attributes (including "commit") in a stable, parseable form -- never from
# a version string, because neither shim's `--version` carries one.
if ! list_output="$(python3 "$UPDATE_UPSTREAM" list)"; then
    echo "Estate command install refused: '$UPDATE_UPSTREAM list' failed" >&2
    echo "unexpectedly, right after 'check' passed. Nothing was installed." >&2
    exit 1
fi

shape_commit="$(printf '%s\n' "$list_output" | awk '/^openreposhape$/{f=1;next} f&&/^  commit /{print $2;exit}')"
tools_commit="$(printf '%s\n' "$list_output" | awk '/^openrepotools$/{f=1;next} f&&/^  commit /{print $2;exit}')"

if [ -z "$shape_commit" ] || [ -z "$tools_commit" ]; then
    echo "Estate command install refused: could not read the pinned commits" >&2
    echo "from '$UPDATE_UPSTREAM list'. Nothing was installed." >&2
    exit 1
fi

echo "openRepoShape pinned at $shape_commit"
echo "openRepoTools pinned at $tools_commit"

# Ruling 2 (the host follows the pin, both ways): each shim, invoked as a
# FILE, installs its own bytes (and openRepoTools copies park and resume
# from beside itself); it reports each target `already installed ...
# (unchanged)`, `updated`, or `installed`. That per-file report is relayed
# unchanged below -- this script adds no version logic and no flags of its
# own to either shim (ruling 4).
if ! "$SHAPE_SHIM" --install; then
    echo "openRepoShape --install failed; estate command install refused." >&2
    exit 1
fi

if ! "$TOOLS_SHIM" --install; then
    echo "openRepoTools --install failed; estate command install refused." >&2
    exit 1
fi

# Each shim already warns on its own bin dir; this is a second, de-duplicated
# pass over both effective bin dirs, in case they differ. Names the
# directory only -- PATH and rc files are never touched here.
shape_bin_dir="${OPENREPOSHAPE_BIN_DIR:-$HOME/.local/bin}"
tools_bin_dir="${OPENREPOTOOLS_BIN_DIR:-$HOME/.local/bin}"

seen=""
for dir in "$shape_bin_dir" "$tools_bin_dir"; do
    case " $seen " in
        *" $dir "*) continue ;;
    esac
    seen="$seen $dir"
    case ":${PATH:-}:" in
        *":$dir:"*) ;;
        *) echo "Warning: $dir is not on \$PATH. Add it, e.g.: export PATH=\"$dir:\$PATH\"" ;;
    esac
done

exit 0
