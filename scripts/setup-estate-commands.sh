#!/usr/bin/env bash
#
# scripts/setup-estate-commands.sh
#
# Installs the estate commands on this host from workBenches' own vendored
# pin: openRepoShape, and openRepoTools's own TWENTY-NINE artifacts, placed by
# the vendored shims' own `--install` (devBenches/base-image/files/
# openreposhape/openRepoShape and devBenches/base-image/files/openrepotools/
# openRepoTools). `openRepoTools --install` places FIFTEEN files on $PATH
# (itself, park, resume, status, lane, lanes, lane-handoff, lane-rename, the
# four lane helpers `lanes-edit.sh`, `lane-start`, `lane-end` and
# `link-estates` with the alias table `repos.tsv` they read, and the two
# Claude Code launch commands `claude-current` and `claude-restart-check` --
# lane-collision-protocol Amendments 11, 16, 17(a) and 18, and
# opensoft/openRepoTools#26, #45 and opensoft/workBenches#119),
# THREE skills (`handoff`, `lane-swap`, `restart`) at
# `~/.claude-profiles/shared/skills/<name>/SKILL.md` and
# `~/.claude/skills/<name>/SKILL.md`, THREE command files (`handoff`, `ctx`,
# `swap`) at that same pair of paths under `commands/`, and merges two
# entries into `~/.claude/settings.json` -- the `SessionStart` entry and
# lane-collision-protocol Amendment 12's `UserPromptSubmit` name guard. This
# script adds no install logic of its own: it
# runs `update-upstream.py check`, then the two shims, and relays their own
# output unchanged -- but it pre-flights every bin-directory install target
# and verifies every one of them afterward, because the shims' own `cp` can
# write through a symlink or into a directory, and two shim invocations are
# two independent transactions (an adversarial review of this script,
# opensoft/workBenches#37, found and named these gaps D1-D6; every guarantee
# below closes one).
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
# Guarantees added by the adversarial review round, extended to the ELEVEN,
# now FIFTEEN, bin-directory files: opensoft/openRepoTools#26 grew the
# installable set from four to eleven, and opensoft/openRepoTools#45
# (lane-collision-protocol Amendment 18 Addendum 2) retired `restart` from
# $PATH while Amendment 17(a) added `lane-handoff` beside it, net one file;
# upstream then added `lane-rename` as the thirteenth bin file, and
# opensoft/workBenches#119 added `claude-current` and `claude-restart-check`
# at the END of the list for the fourteenth and fifteenth
# (the three skills, the three command files and the two hook entries are
# placed and verified by `openRepoTools --install` itself, under its own
# all-or-nothing rule -- see "Ruling 2" below):
#   - Refuses (exit 1) before running either shim if any of the fifteen
#     openRepoTools install targets (or openRepoShape's own) already exists
#     as a symlink, as anything other than a regular file (e.g. a
#     directory), or is not writable -- or if its bin dir exists and is not
#     writable. Nothing is installed once any one target fails this check
#     (closes D1, D2, most of D4).
#   - Refuses (exit 2) if the pin file itself is missing, if a file this
#     script or either shim needs is missing, if `jq` is not on $PATH (the
#     shim needs it to merge the SessionStart entry, and refusing here means
#     NOTHING is installed rather than fourteen of fifteen bin files landing
#     before the shim discovers jq is missing on its own), or if a file the
#     shims would install has no row in the pin's own `list` output -- so a
#     row removed the documented way (`apply --remove`) is caught here,
#     before either shim could fall back to fetching that file over the
#     network (D3).
#   - Refuses (exit 2) if TOOLS_FILES, SKILL_NAMES or COMMAND_NAMES below
#     ever disagrees with the vendored shim's own INSTALLABLES, SKILLS or
#     COMMANDS array (`check_shim_list`, added for Copilot's review of
#     opensoft/workBenches#91: those three lists here are still hand-kept,
#     not generated -- there is no `--list-installables` to generate them
#     from -- but a shim that grows past what this script lists no longer
#     installs the new file's bytes while silently skipping its preflight
#     and verification; it refuses the whole install and names both lists).
#   - For the duration of both installer runs, OPENREPOSHAPE_REPO/_REF and
#     OPENREPOTOOLS_REPO/_REF are overridden to a sentinel that cannot
#     resolve, so that IF a fetch is ever attempted despite the checks
#     above, it fails loudly naming the sentinel rather than silently
#     succeeding against whatever the operator's shell happened to export
#     (D3, defense in depth). Under openRepoTools#26's all-or-nothing rule
#     this now guards TWENTY-ONE pinned paths, not five: the fifteen bin files
#     plus the three skills' SKILL.md and the three command files, because
#     `--install` places all fifteen files, all three skills and all three
#     command files, or none -- one missing or unpinned refuses the WHOLE
#     install, bin files included. The one exception is OPENREPOSHAPE_REF on
#     the one call that records the pin (next bullet): there it is the pin's
#     commit, and OPENREPOSHAPE_REPO is still the sentinel, so a fetch there
#     still resolves to nothing real.
#   - Holds the host's openRepoShape on the release the pin names, the same
#     release the image holds (opensoft/workBenches#159, the host half of
#     #153): the vendored launcher's own `--install` writes the pin's
#     `openreposhape` commit to `openRepoShape.ref` beside the command it
#     places, so the host command fetches setup.sh and clones the standard at
#     that commit and stops following openRepoShape's main. The record is the
#     launcher's to write, not this script's; this script names the ref and
#     asks for it to be recorded, for that one call only, and the launcher
#     reads nothing from the network to do it (see "THE RECORD" below). The
#     caller's own $OPENREPOSHAPE_RECORD_REF is never read: it used to reach
#     that call, and with it set to 1 the install recorded the sentinel as
#     the host command's ref.
#   - After both installers exit 0, every one of the FIFTEEN openRepoTools
#     bin files (and openRepoShape's own) is re-checked: a regular,
#     non-symlink file, mode exactly 0755, and `cmp`-identical to its
#     vendored copy; and the record beside openRepoShape is re-read and must
#     hold exactly the pin's commit. Only then does this script report
#     success (D1/D2/D3/D4 residue, closed in one place). The three skills,
#     the three command files and the merged settings.json are NOT
#     re-verified here the same way: they are per-user artifacts under $HOME
#     with their own modes (0644, 0600) and their own all-or-nothing
#     preflight inside `openRepoTools --install` (`plan_skill_targets`,
#     `plan_hook_merge`) -- this script trusts that shim's own exit code for
#     them, exactly as ruling 2 already trusted it for the bin files before
#     this script added its own belt-and-braces re-check.
#
# Set WORKBENCHES_SKIP_ESTATE_COMMANDS=1 to skip this step entirely (prints
# one line, exits 0).
#
# WORKBENCHES_BASE_IMAGE_DIR overrides the base-image directory this script
# reads the pin, the checker and the vendored shims from (default:
# "<repo root>/devBenches/base-image"). This exists for the test suite's
# corruption scenarios only -- point it at a throwaway copy of base-image to
# prove a corrupted vendor copy refuses to install; there is no reason to
# set it on a real host.
#
# Exit codes when run directly: 0 ok; 1 refused (a target -- openRepoShape's
# record included -- is a symlink, a non-regular file, or not writable (the
# record: or not readable);
# update-upstream.py check found drift; one of the two installers itself
# failed; or a placed file, or the record, failed verification after
# install); 2 tooling or configuration missing (no
# python3; no jq; the pin file, update-upstream.py, or a file either shim
# needs is missing; a file the shims would install has no row in the pin;
# this script's TOOLS_FILES/SKILL_NAMES/COMMAND_NAMES disagrees with the
# shim's own INSTALLABLES/SKILLS/COMMANDS; or update-upstream.py check itself
# refused structurally). setup.sh runs this
# under `log_header "ESTATE COMMANDS"` and treats any non-zero exit here as
# best-effort, continuing either way; this script is also safe to run
# directly, any time. A host that runs it now ends up with the same
# TWENTY-NINE artifacts `openRepoTools --install` places by hand.

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

# jq, preflighted HERE rather than left to the shim: `openRepoTools --install`
# needs it to merge the SessionStart and UserPromptSubmit entries into
# ~/.claude/settings.json under openRepoTools#26's all-or-nothing rule, and
# refuses (placing nothing) the moment it discovers jq is missing -- but that
# discovery happens AFTER the fifteen bin files are already staged, so
# refusing before either shim runs means a host with no jq never sees
# openRepoShape or any of the fifteen land either, one refusal instead of a
# install that reads like it got most of the way there.
if ! command -v jq >/dev/null 2>&1; then
    echo "Estate command install refused: jq is not available, and" >&2
    echo "openRepoTools --install needs it to merge the SessionStart and" >&2
    echo "UserPromptSubmit entries into ~/.claude/settings.json. Nothing was" >&2
    echo "installed. Install jq, then re-run." >&2
    exit 2
fi

UPDATE_UPSTREAM="$BASE_IMAGE_DIR/update-upstream.py"
PIN_FILE="$BASE_IMAGE_DIR/upstream-pin.yaml"
SHAPE_SHIM="$BASE_IMAGE_DIR/files/openreposhape/openRepoShape"
TOOLS_SHIM="$BASE_IMAGE_DIR/files/openrepotools/openRepoTools"

# THE FIFTEEN FILES `openRepoTools --install` PLACES ON $PATH (openRepoTools#26
# and #45, lane-collision-protocol Amendments 11, 16, 17(a) and 18, and
# opensoft/workBenches#119's `claude-current` and `claude-restart-check`, which
# the shim lists LAST so every index a test takes into its list holds) -- one list,
# so the file-existence check, the pin-row check, the preflight and the
# post-install verification below cannot disagree about what a complete
# bin-directory install is, the same reason openRepoTools's own INSTALLABLES
# is one list there. Checked against that list itself below (`check_shim_list`),
# not just kept in sync by a person's own care.
TOOLS_FILES=(openRepoTools park resume status lane lanes lane-handoff lane-rename lanes-edit.sh lane-start lane-end link-estates repos.tsv claude-current claude-restart-check)
# THE THREE SKILLS and THE THREE COMMAND FILES `openRepoTools --install` also
# places (skill_source_path/command_source_path in that shim derive the two
# paths each of these takes from the name alone, the same way this script's
# own require_pin_row loops below do). Also checked against the shim's own
# SKILLS/COMMANDS arrays below.
SKILL_NAMES=(handoff lane-swap restart)
COMMAND_NAMES=(handoff ctx swap)

if [ ! -f "$PIN_FILE" ]; then
    echo "Estate command install refused: the pin file is missing or" >&2
    echo "unreadable: $PIN_FILE. Nothing was installed." >&2
    exit 2
fi

missing=""
for f in "$UPDATE_UPSTREAM" "$SHAPE_SHIM" "$TOOLS_SHIM"; do
    if [ ! -f "$f" ]; then
        missing="${missing:+$missing }$f"
    fi
done
for name in "${TOOLS_FILES[@]}"; do
    f="$BASE_IMAGE_DIR/files/openrepotools/$name"
    if [ ! -f "$f" ]; then
        missing="${missing:+$missing }$f"
    fi
done
if [ -n "$missing" ]; then
    echo "Estate command install refused: missing file(s): $missing" >&2
    echo "Nothing was installed." >&2
    exit 2
fi

# Ruling 3 (drift refuses): the checker runs BEFORE anything is placed. Its
# own stdout/stderr stream through unchanged above. Its exit code decides
# which of two different refusals this is:
#   1 -- a vendored copy no longer matches its pinned row (drift);
#   anything else nonzero -- the pin itself could not be read or validated
#   (a structural refusal, e.g. malformed YAML) -- a different failure than
#   drift, and it gets a different exit code from this script too.
check_status=0
python3 "$UPDATE_UPSTREAM" check || check_status=$?

if [ "$check_status" -eq 1 ]; then
    echo "" >&2
    echo "Estate command install refused: the vendored copies do not match" >&2
    echo "$PIN_FILE (see the finding above). NOTHING was installed, because" >&2
    echo "the vendored bytes are not the pinned bytes." >&2
    exit 1
elif [ "$check_status" -ne 0 ]; then
    echo "" >&2
    echo "Estate command install refused: the pin is unreadable or was" >&2
    echo "refused structurally (see '$UPDATE_UPSTREAM check' above, exit" >&2
    echo "$check_status). Nothing was installed." >&2
    exit 2
fi

# CHECKED AGAINST THE SHIM'S OWN LIST, not trusted on a person's care alone
# (Copilot's review of opensoft/workBenches#91, README.md:108: "TOOLS_FILES
# is a literal array... This sentence therefore promises a safeguard that
# does not exist; a future upstream artifact could make --install succeed
# while this wrapper omits its preflight/verification"). TOOLS_FILES,
# SKILL_NAMES and COMMAND_NAMES above are still hand-kept mirrors, not
# generated -- there is no `openRepoTools --list-installables` to generate
# them from -- but from here on a shim whose own INSTALLABLES, SKILLS or
# COMMANDS grew past what this script lists REFUSES the whole install rather
# than silently omitting the new file's preflight and verification. Read
# AFTER `check` above has already proven $TOOLS_SHIM's bytes match the pin,
# so `eval`-ing its three one-line array assignments is evaluating content
# already integrity-checked by sha256, not arbitrary vendored bytes.
check_shim_list() {
    local our_name="$1" shim_array_name="$2" expected_csv="$3" shim_line shim_csv
    shim_line="$(grep -m1 "^${shim_array_name}=" "$TOOLS_SHIM")"
    if [ -z "$shim_line" ]; then
        echo "Estate command install refused: could not find '${shim_array_name}=' in" >&2
        echo "$TOOLS_SHIM; this script's own $our_name may be stale. Nothing was installed." >&2
        exit 2
    fi
    # Evaluated in a SEPARATE bash process, never in this script's own shell:
    # a shim array named identically to this script's own local ($shim_line
    # is always some upstream INSTALLABLES/SKILLS/COMMANDS, never TOOLS_FILES/
    # SKILL_NAMES/COMMAND_NAMES, so this is defensive rather than live) would
    # otherwise shadow it depending on which assignment ran last.
    shim_csv="$(bash -c "$shim_line"$'\n'"IFS=,; echo \"\${${shim_array_name}[*]}\"")"
    if [ "$shim_csv" != "$expected_csv" ]; then
        echo "Estate command install refused: this script's $our_name list" >&2
        echo "  ($expected_csv)" >&2
        echo "does not match the vendored shim's own $shim_array_name" >&2
        echo "  ($shim_csv)." >&2
        echo "Nothing was installed. Update $our_name in $0 to match." >&2
        exit 2
    fi
}
check_shim_list TOOLS_FILES INSTALLABLES "$(IFS=,; echo "${TOOLS_FILES[*]}")"
check_shim_list SKILL_NAMES SKILLS "$(IFS=,; echo "${SKILL_NAMES[*]}")"
check_shim_list COMMAND_NAMES COMMANDS "$(IFS=,; echo "${COMMAND_NAMES[*]}")"

# Ruling 1 ("version" means the pin): read the two pinned commits from
# `update-upstream.py list`, which prints each source's id, then its
# attributes (including "commit") in a stable, parseable form -- never from
# a version string, because neither shim's `--version` carries one. Read
# once into a variable, then parsed from there with a here-string, not a
# pipeline: a pipeline into a command that exits early (an awk `exit`) can
# be sent SIGPIPE against a still-writing producer under `pipefail`, and a
# here-string has no live producer process to receive one.
if ! list_output="$(python3 "$UPDATE_UPSTREAM" list)"; then
    echo "Estate command install refused: '$UPDATE_UPSTREAM list' failed" >&2
    echo "unexpectedly, right after 'check' passed. Nothing was installed." >&2
    exit 1
fi

shape_commit="$(awk '/^openreposhape$/{f=1;next} f&&/^  commit /{print $2;exit}' <<<"$list_output")"
tools_commit="$(awk '/^openrepotools$/{f=1;next} f&&/^  commit /{print $2;exit}' <<<"$list_output")"

if [ -z "$shape_commit" ] || [ -z "$tools_commit" ]; then
    echo "Estate command install refused: could not read the pinned commits" >&2
    echo "from '$UPDATE_UPSTREAM list'. Nothing was installed." >&2
    exit 1
fi

# D3, closed a second way: a file either shim would install must also have
# a row in the pin's own listing, not just exist on disk -- so a row
# dropped the documented way (`apply --remove`, which deletes the row AND
# the file together) is refused here explicitly, naming the file, rather
# than ever reaching a shim that would fall back to fetching it over the
# network. TWENTY-ONE rows now, not five: the fifteen bin files plus the three
# skills' SKILL.md and the three command files -- openRepoTools#26's
# all-or-nothing rule means any one of the twenty-one missing a row refuses
# the WHOLE install, bin files included, so all twenty-one are checked here,
# not only the fifteen this script itself places into a bin dir.
require_pin_row() {
    local path="$1"
    if ! grep -Eq "^    [0-9a-f]{12}  ${path}\$" <<<"$list_output"; then
        echo "Estate command install refused: '$path' has no row in" >&2
        echo "'$UPDATE_UPSTREAM list' output; it is not a pinned file." >&2
        echo "Nothing was installed." >&2
        exit 2
    fi
}
require_pin_row "openRepoShape"
for name in "${TOOLS_FILES[@]}"; do
    require_pin_row "$name"
done
for name in "${SKILL_NAMES[@]}"; do
    require_pin_row "skills/$name/SKILL.md"
done
for name in "${COMMAND_NAMES[@]}"; do
    require_pin_row "commands/$name.md"
done

echo "openRepoShape pinned at $shape_commit"
echo "openRepoTools pinned at $tools_commit"

shape_bin_dir="${OPENREPOSHAPE_BIN_DIR:-$HOME/.local/bin}"
tools_bin_dir="${OPENREPOTOOLS_BIN_DIR:-$HOME/.local/bin}"

refuse_preflight() {
    echo "Estate command install refused: $1" >&2
    echo "Nothing was installed." >&2
    exit 1
}

refuse_postverify() {
    echo "Estate command install refused: $1" >&2
    echo "One or more of the fifteen openRepoTools commands may now be in a" >&2
    echo "mixed state; fix the problem above and re-run this script." >&2
    exit 1
}

# The record's own refusal (`verify_record`), and not `refuse_postverify`'s: the
# shared text above is about the fifteen openRepoTools files, which this script
# has not re-checked yet when the record is, and it tells the person to re-run
# -- which cannot help, because the vendored launcher writes the same record
# every time. What is wrong here is that openRepoShape is placed but not held
# on the pin, and what fixes it is the pin or the vendored launcher.
refuse_record() {
    echo "Estate command install refused: $1" >&2
    echo "openRepoShape is placed but is NOT held on the pin ($shape_commit), so the host" >&2
    echo "command does not run at the release the pin names. Both installers ran and this" >&2
    echo "script stopped before it re-checked the openRepoTools files. Re-running cannot" >&2
    echo "change the record: the vendored launcher writes it. The fix is the pin" >&2
    echo "($PIN_FILE)" >&2
    echo "or the vendored launcher ($SHAPE_SHIM)." >&2
    exit 1
}

# D1/D2/most of D4: every bin-directory target either shim is about to write
# to is checked BEFORE either of them runs, so a bad target refuses before
# anything at all is placed -- never after only some of the fifteen are done.
# (The skills, the command file and the settings.json merge have their own
# preflight inside `openRepoTools --install` -- `plan_skill_targets` -- under
# the same all-or-nothing rule; this script does not duplicate it.)
check_target_preflight() {
    local target="$1" dir="$2"
    if [ -L "$target" ]; then
        refuse_preflight "$target is a symlink; refusing to write through it into whatever it points at."
    fi
    if [ -e "$target" ] && [ ! -f "$target" ]; then
        refuse_preflight "$target exists and is not a regular file (a directory, device, or similar)."
    fi
    if [ -e "$target" ] && [ ! -w "$target" ]; then
        refuse_preflight "$target exists and is not writable."
    fi
    if [ -d "$dir" ] && [ ! -w "$dir" ]; then
        refuse_preflight "$dir exists and is not writable, so $target could not be placed."
    fi
}

check_target_preflight "$shape_bin_dir/openRepoShape" "$shape_bin_dir"
# The record the launcher writes beside openRepoShape is a target of this run
# too (see "THE RECORD" below): the launcher would write through a symlink
# there, or remove one, exactly as `cp` writes through one for the files above.
check_target_preflight "$shape_bin_dir/openRepoShape.ref" "$shape_bin_dir"
# And READABLE: the launcher reads the ref a record already holds before it
# replaces it, and does so only after it has placed openRepoShape, so a record
# it cannot read would fail the install half-way and say only "Permission denied".
if [ -e "$shape_bin_dir/openRepoShape.ref" ] && [ ! -r "$shape_bin_dir/openRepoShape.ref" ]; then
    refuse_preflight "$shape_bin_dir/openRepoShape.ref exists and is not readable, and the launcher reads the ref it holds before it replaces it."
fi
for name in "${TOOLS_FILES[@]}"; do
    check_target_preflight "$tools_bin_dir/$name" "$tools_bin_dir"
done

# D3, defense in depth: every file the checks above proved is present and
# pinned is about to be installed with no fetch ever reachable, because
# neither shim's `collect_commands`/`collect_skills` falls back to the
# network for a file already beside it. If that ever stopped being true --
# a future change, a race -- these four must resolve to nothing real, so a
# fetch this sentinel can never satisfy fails loudly, naming it, instead of
# quietly succeeding against whichever ref/repo the operator's own shell
# happened to export. (The one call that records the pin overrides
# OPENREPOSHAPE_REF alone, below; its REPO stays the sentinel.)
ESTATE_SENTINEL="pinned-by-workBenches-no-fetch"
export OPENREPOSHAPE_REPO="$ESTATE_SENTINEL"
export OPENREPOSHAPE_REF="$ESTATE_SENTINEL"
export OPENREPOTOOLS_REPO="$ESTATE_SENTINEL"
export OPENREPOTOOLS_REF="$ESTATE_SENTINEL"

# Ruling 2 (the host follows the pin, both ways): each shim, invoked as a
# FILE, installs its own bytes -- and openRepoTools also copies the other
# fourteen files beside itself (park, resume, status, lane, lanes,
# lane-handoff, lane-rename, the four lane helpers, repos.tsv,
# claude-current and claude-restart-check), places the handoff,
# lane-swap and restart skills and the handoff, ctx and swap command files
# under $HOME (~/.claude-profiles/shared/... and ~/.claude/...), and merges
# the SessionStart entry and the UserPromptSubmit name guard entry into
# ~/.claude/settings.json, ALL from beside itself, under openRepoTools#26's
# all-or-nothing rule: no fetch is reachable once every one of the twenty-one
# checks above has passed. It reports each target `already installed ...
# (unchanged)`, `updated`, or `installed`. That per-file report is relayed
# unchanged below -- this script adds no version logic and no flags of its
# own to either shim (ruling 4).
#
# THE RECORD (opensoft/workBenches#159, the host half of #153, which gave the
# image `/usr/local/bin/openRepoShape.ref`). From v1.0.1 the launcher reads the
# ref it runs at from `openRepoShape.ref` beside the installed command, and
# stays on it: it fetches setup.sh at that ref, setup.sh clones the standard at
# it, and `--doctor` checks its clone out at it. Its `--install` writes that
# record only when $OPENREPOSHAPE_RECORD_REF is 1, from $OPENREPOSHAPE_REF; with
# neither it records nothing and REMOVES a record already there, which left a
# host command following openRepoShape's main while the image's command stayed
# on the release. So the call below names both, as assignments on that one
# command and nowhere else, so neither becomes part of this script's own
# environment for the openRepoTools install after it:
#   - OPENREPOSHAPE_REF is the pin's commit ($shape_commit, read above through
#     `update-upstream.py list`, which `check` has already proven is 40
#     lowercase hex), the same commit the Dockerfile writes into the image's
#     record, not the sentinel exported above;
#   - OPENREPOSHAPE_RECORD_REF is 1, never whatever the caller's shell held. An
#     inherited 1 used to make the install record the SENTINEL, and the host
#     command then reported `@ pinned-by-workBenches-no-fetch` and fetched at a
#     ref that does not exist.
# NO FETCH IS ADDED: run as a file, as it is here, the launcher installs the
# bytes beside it (`collect_commands`, which the checks above proved are there)
# and only reads $OPENREPOSHAPE_REF as a string (`checked_ref`), so the install
# still touches no network for it; and $OPENREPOSHAPE_REPO is still the sentinel,
# so a fetch reached anyway would still name a repository that cannot resolve.
# A launcher too old to record is caught by `verify_record` below, not here.
if ! OPENREPOSHAPE_REF="$shape_commit" OPENREPOSHAPE_RECORD_REF=1 "$SHAPE_SHIM" --install; then
    echo "openRepoShape --install failed; estate command install refused." >&2
    exit 1
fi

if ! "$TOOLS_SHIM" --install; then
    echo "openRepoTools --install failed; estate command install refused." >&2
    exit 1
fi

# Post-install verification: D1/D2/D3/D4 residue, closed in one place. Both
# shims reported success above, but `cp` can write through a symlink or into
# a directory without either shim noticing -- so every placed bin file is
# re-checked against the vendored copy it was supposed to become, and only
# once openRepoShape and all fifteen openRepoTools files pass does this
# script report success itself. (Why not the skills/command/hook too: see
# the guarantees note above.)
file_mode_octal() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

verify_installed() {
    local target="$1" vendor="$2" mode
    if [ -L "$target" ] || [ ! -f "$target" ]; then
        refuse_postverify "$target is not a regular file after install."
    fi
    mode="$(file_mode_octal "$target")"
    if [ "$mode" != "755" ]; then
        refuse_postverify "$target has mode ${mode:-unknown} after install, expected 755."
    fi
    if ! cmp -s "$target" "$vendor"; then
        refuse_postverify "$target does not match its vendored copy ($vendor) after install."
    fi
}

# The record is checked by what it SAYS, not only that it exists: it is the one
# file here whose bytes are decided by an environment this script sets and a
# launcher it does not own, and a record that holds the sentinel, a branch or
# nothing would leave the host command following main or fetching at a ref that
# does not exist while every file above verified. The launcher writes
# `<commit>\n` and reads it back with `$(< file)`, which drops the newline.
verify_record() {
    local record="$1" held
    if [ -L "$record" ] || [ ! -f "$record" ]; then
        refuse_record "$record is not a regular file after install."
    fi
    held="$(< "$record")"
    if [ "$held" != "$shape_commit" ]; then
        refuse_record "$record holds '$held' after install, expected the pinned openRepoShape commit $shape_commit."
    fi
}

verify_installed "$shape_bin_dir/openRepoShape" "$SHAPE_SHIM"
verify_record "$shape_bin_dir/openRepoShape.ref"
for name in "${TOOLS_FILES[@]}"; do
    verify_installed "$tools_bin_dir/$name" "$BASE_IMAGE_DIR/files/openrepotools/$name"
done

echo "Estate commands verified against the vendored pin."

exit 0
