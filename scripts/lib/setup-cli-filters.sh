#!/usr/bin/env bash
# CLI view state only. No installers, account probes or subprocesses.
declare -A setup_cli_filter_selected=([type]=frontier)
setup_cli_filter_row=0
setup_cli_filter_cache_key=''
setup_cli_filter_members=''
setup_cli_filter_count=0
setup_cli_filter_total=0
setup_cli_filter_active=0

setup_cli_filter_key_v() {
    local filter_key_text='' filter_key_facet
    for filter_key_facet in "${setup_cli_filter_rows[@]}"; do
        filter_key_text+=";$filter_key_facet=${setup_cli_filter_selected[$filter_key_facet]:-all}"
    done
    printf -v "$1" '%s' "$filter_key_text"
}

setup_cli_filter_matches() {
    local match_item="$1" match_facet match_value match_values
    for match_facet in "${setup_cli_filter_rows[@]}"; do
        match_value=${setup_cli_filter_selected[$match_facet]:-all}
        [[ "$match_value" == all ]] && continue
        match_values=" ${setup_cli_filter_values[$match_item:$match_facet]:-unknown} "
        [[ "$match_values" == *" $match_value "* ]] || return 1
    done
    return 0
}

setup_cli_filters_refresh() {
    local filter_next_key filter_item filter_facet filter_old_item="${ai_items[$current_selection]:-}" filter_first='' filter_kept=false
    local -a filter_candidates=() filter_all=()
    setup_cli_filter_key_v filter_next_key
    if [[ "$setup_cli_filter_cache_key" == "$filter_next_key" ]]; then
        if [[ "$CURRENT_SECTION" == 1 && "$setup_harness_category" == tui && "$setup_cli_filter_count" -gt 0 && " $setup_cli_filter_members " != *" $filter_old_item "* ]]; then
            filter_first=${setup_cli_filter_members%% *}
            setup_focus_harness_key "$filter_first"
        fi
        return 0
    fi
    setup_cli_filter_cache_key=$filter_next_key
    setup_cli_filter_members=''; setup_cli_filter_count=0; setup_cli_filter_active=0
    IFS=' ' read -r -a filter_all <<< "${setup_cli_group_members[all]}"
    setup_cli_filter_total=${#filter_all[@]}
    for filter_facet in "${setup_cli_filter_rows[@]}"; do
        [[ "${setup_cli_filter_selected[$filter_facet]:-all}" == all ]] || ((setup_cli_filter_active++))
    done
    filter_candidates=("${filter_all[@]}")
    for filter_item in "${filter_candidates[@]}"; do
        setup_cli_filter_matches "$filter_item" || continue
        [[ -n "$filter_first" ]] || filter_first=$filter_item
        [[ -z "$setup_cli_filter_members" ]] || setup_cli_filter_members+=' '
        setup_cli_filter_members+="$filter_item"; ((setup_cli_filter_count++))
        [[ "$filter_item" != "$filter_old_item" ]] || filter_kept=true
    done
    if [[ "$CURRENT_SECTION" == 1 && "$setup_harness_category" == tui && "$filter_kept" != true && -n "$filter_first" ]]; then
        setup_focus_harness_key "$filter_first"
    fi
}

setup_cli_filters_clear() {
    setup_cli_filter_selected=()
    setup_cli_filter_cache_key=''
    setup_about_offset=0
    setup_cli_filters_refresh
}

# Select a single value. Values in product metadata may still overlap.
setup_cli_filter_toggle() {
    local select_facet="$1" select_option="$2"
    [[ " ${setup_cli_filter_options[$select_facet]:-} " == *" $select_option "* ]] || return 1
    setup_cli_filter_selected[$select_facet]=$select_option
    setup_cli_filters_refresh
    setup_about_offset=0
}

setup_cli_filter_cycle() {
    local cycle_facet=${setup_cli_filter_rows[setup_cli_filter_row]} cycle_index=0 cycle_delta="$1"
    local -a cycle_options=()
    IFS=' ' read -r -a cycle_options <<< "${setup_cli_filter_options[$cycle_facet]}"
    for cycle_index in "${!cycle_options[@]}"; do
        [[ "${cycle_options[cycle_index]}" != "${setup_cli_filter_selected[$cycle_facet]:-all}" ]] || break
    done
    cycle_index=$(( (cycle_index+cycle_delta+${#cycle_options[@]}) % ${#cycle_options[@]} ))
    setup_cli_filter_toggle "$cycle_facet" "${cycle_options[cycle_index]}"
}

setup_cli_filters_key() {
    local filter_key="$1"
    [[ "$CURRENT_SECTION" == 1 && "$setup_harness_category" == tui ]] || return 1
    if [[ "$filter_key" == f || "$filter_key" == F ]]; then
        if [[ "$setup_harness_zone" == filter ]]; then setup_harness_zone=harness
        else setup_harness_zone=filter; fi
        setup_about_offset=0; setup_cli_filters_refresh
        return 0
    fi
    if [[ "$filter_key" == c || "$filter_key" == C ]]; then setup_cli_filters_clear; return 0; fi
    [[ "$setup_harness_zone" == filter ]] || return 1
    case "$filter_key" in
        left|backtab) setup_cli_filter_row=$(( (setup_cli_filter_row+${#setup_cli_filter_rows[@]}-1) % ${#setup_cli_filter_rows[@]} )) ;;
        right|tab) setup_cli_filter_row=$(( (setup_cli_filter_row+1) % ${#setup_cli_filter_rows[@]} )) ;;
        up) setup_cli_filter_cycle -1 ;;
        down|' ') setup_cli_filter_cycle 1 ;;
        d|D) return 0 ;;
        *) return 1 ;;
    esac
    setup_about_offset=0
    return 0
}

setup_cli_filter_option_label_v() {
    local option_label="${setup_cli_filter_option_labels[$2:$3]}"
    if ((setup_ui_width < 60)); then
        case "$3" in subscription) option_label=Subscr. ;; classifier) option_label=Class. ;; esac
    fi
    printf -v "$1" '%s' "$option_label"
}

# Four fixed columns remain visible while results update underneath.
setup_frame_cli_filter_bar() {
    local bar_line bar_headers='' bar_values='' bar_index bar_facet bar_label bar_value bar_header bar_cell bar_color
    local bar_width bar_base=$(( (setup_ui_width-7)/4 )) bar_extra=$(( (setup_ui_width-7)%4 ))
    bar_width=$bar_base
    ((bar_width > 0)) || bar_width=1
    setup_cli_filters_refresh
    setup_panel_top_v bar_line FILTERS "$setup_cli_filter_count/$setup_cli_filter_total F/C"; setup_frame_append "$bar_line"
    for bar_index in "${!setup_cli_filter_rows[@]}"; do
        bar_width=$bar_base; ((bar_index >= bar_extra)) || ((bar_width++))
        bar_facet=${setup_cli_filter_rows[bar_index]}
        bar_header=${setup_cli_filter_labels[$bar_facet]}; bar_color=$SILVER
        if [[ "$setup_harness_zone" == filter ]] && ((bar_index == setup_cli_filter_row)); then bar_header="›$bar_header"; bar_color=$SILVER_FOCUS; fi
        bar_value=${setup_cli_filter_selected[$bar_facet]:-all}
        setup_cli_filter_option_label_v bar_label "$bar_facet" "$bar_value"
        setup_ui_cut_v bar_header "$bar_header" "$bar_width"
        setup_ui_cut_v bar_label "$bar_label" "$bar_width"
        printf -v bar_cell '%*s' "$((bar_width-${#bar_header}))" ''; bar_headers+="$bar_color$bar_header$bar_cell$NC"
        printf -v bar_cell '%-*s' "$bar_width" "$bar_label"; bar_values+="$bar_cell"
        if ((bar_index+1 < ${#setup_cli_filter_rows[@]})); then bar_headers+='│'; bar_values+='│'; fi
    done
    printf -v bar_line '%b│%b %b%b %b│%b' "$SILVER_EDGE" "$NC" "$bar_headers" "$NC" "$SILVER_EDGE" "$NC"
    setup_frame_append "$bar_line"
    setup_frame_row "$bar_values"
    setup_panel_bottom_v bar_line; setup_frame_append "$bar_line"
}

setup_frame_cli_filter_about() {
    local filter_facet=${setup_cli_filter_rows[setup_cli_filter_row]} filter_value filter_about filter_window="$1" filter_lab filter_labs=''
    filter_value=${setup_cli_filter_selected[$filter_facet]:-all}
    filter_about="${setup_cli_filter_summaries[$filter_facet]}"$'\nSelected: '"${setup_cli_filter_option_labels[$filter_facet:$filter_value]}"$'\nLeft/Right chooses a column; Up/Down cycles its value. Columns combine with AND. Unknown includes partial metadata. F results; C sets all columns to All.'
    if [[ "$filter_facet" == type && "$filter_value" == frontier ]]; then
        for filter_lab in "${!setup_cli_filter_lab_labels[@]}"; do
            [[ -z "$filter_labs" ]] || filter_labs+=', '
            filter_labs+="${setup_cli_filter_lab_labels[$filter_lab]}"
        done
        filter_about+=$'\nCurated labs: '"$filter_labs"
    fi
    setup_frame_about "harness-filter:$filter_facet:$filter_value" "ABOUT FILTER · ${setup_cli_filter_labels[$filter_facet]^^}" "$filter_about" "$filter_window"
}
