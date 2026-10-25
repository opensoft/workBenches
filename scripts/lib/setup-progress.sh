#!/usr/bin/env bash

# Reserve five lines for progress; commands keep their original stdin/stdout
# and write normally in the scrolling area below. No background output reader
# can consume password prompts or interfere with cancellation.
setup_progress_active=false
setup_progress_owner=false
setup_progress_rows=0
setup_progress_columns=0
setup_progress_stage_name="${WORKBENCHES_PROGRESS_STAGE:-Preparing installation}"
setup_progress_current='Working; details below'
setup_progress_total="${WORKBENCHES_PROGRESS_TOTAL:-0}"
setup_progress_success=0
setup_progress_failed=0

setup_progress_measure() {
    local geometry
    geometry="$(stty size 2>/dev/null)" || return 1
    read -r setup_progress_rows setup_progress_columns <<< "$geometry"
    [[ "$setup_progress_rows" =~ ^[0-9]+$ && "$setup_progress_columns" =~ ^[0-9]+$ ]] &&
        (( setup_progress_rows >= 12 && setup_progress_columns >= 36 ))
}

setup_progress_line() {
    local row=$1 text=$2 width=$((setup_progress_columns - 1))
    text="${text//[[:cntrl:]]/ }"
    printf '\033[%d;1H\033[0m\033[2K%s' "$row" "${text:0:width}"
}

setup_progress_draw() {
    [[ "$setup_progress_active" == true ]] || return 0
    printf '\0337'
    setup_progress_line 1 'workBenches - Installation progress'
    setup_progress_line 2 "Stage: $setup_progress_stage_name"
    setup_progress_line 3 "Current: $setup_progress_current"
    setup_progress_line 4 "Completed: $setup_progress_success/$setup_progress_total  Failed: $setup_progress_failed"
    setup_progress_line 5 '--- Live output below; Ctrl+C cancels ---'
    printf '\0338'
}

setup_progress_resize() {
    [[ "$setup_progress_active" == true ]] || return 0
    if setup_progress_measure; then
        printf '\0337\033[6;%dr\0338' "$setup_progress_rows"
        setup_progress_draw
    else
        # A small terminal must still have space to show prompts and logs.
        printf '\0337\033[r\0338\033[0m\033[?25h'
        setup_progress_active=false
        unset WORKBENCHES_SETUP_PROGRESS
    fi
}

setup_progress_start() {
    [[ "$setup_progress_active" != true ]] || return 0
    [[ -t 0 && -t 1 && "${TERM:-dumb}" != dumb ]] || return 0
    setup_progress_measure || return 0
    setup_progress_total="${1:-$setup_progress_total}"
    setup_progress_active=true
    if [[ "${WORKBENCHES_SETUP_PROGRESS:-}" != 1 ]]; then
        setup_progress_owner=true
        printf '\033[0m\033[2J\033[H\033[6;%dr\033[6;1H' "$setup_progress_rows"
    else
        # The parent setup owns terminal cleanup. Child installers share its
        # panel without clearing the log area or resetting the parent's traps.
        printf '\0337\033[6;%dr\0338' "$setup_progress_rows"
    fi
    export WORKBENCHES_SETUP_PROGRESS=1 WORKBENCHES_PROGRESS_TOTAL="$setup_progress_total"
    export BUILDKIT_PROGRESS=plain
    trap 'setup_progress_resize' WINCH
    setup_progress_draw
}

setup_progress_stage() {
    [[ "$setup_progress_active" == true ]] || return 0
    setup_progress_stage_name=$1
    setup_progress_current="${2:-Working; details below}"
    export WORKBENCHES_PROGRESS_STAGE="$setup_progress_stage_name"
    setup_progress_resize
}

setup_progress_component() {
    [[ "$setup_progress_active" == true ]] || return 0
    setup_progress_current=$1
    setup_progress_success=$2
    setup_progress_failed=$3
    setup_progress_resize
}

setup_progress_finish() {
    local status=${1:-0} label=Finished
    [[ "$setup_progress_owner" == true && "$setup_progress_active" == true ]] || return 0
    case "$status" in 0) ;; 130|143) label=Cancelled ;; *) label='Needs attention' ;; esac
    printf '\0337'
    setup_progress_line 2 "Status: $label"
    # Restore normal scrolling and the original output cursor on every exit.
    printf '\033[r\0338\033[0m\033[?25h\n'
    setup_progress_active=false
    unset WORKBENCHES_SETUP_PROGRESS WORKBENCHES_PROGRESS_TOTAL WORKBENCHES_PROGRESS_STAGE
    trap - WINCH
}
