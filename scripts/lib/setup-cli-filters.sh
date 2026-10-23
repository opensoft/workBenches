#!/usr/bin/env bash
# CLI view state only. No installers, account probes or subprocesses.
declare -A setup_cli_filter_selected=() setup_cli_filter_cursor=()
setup_cli_filter_row=0
setup_cli_filter_offset=0
setup_cli_filter_cache_key=''
setup_cli_filter_members=''
setup_cli_filter_count=0
setup_cli_filter_total=0
setup_cli_filter_active=0

setup_cli_filter_key_v() {
    local filter_key_text="group=$setup_cli_group" filter_key_facet
    for filter_key_facet in "${setup_cli_filter_rows[@]}"; do
        [[ "$filter_key_facet" == group ]] || filter_key_text+=";$filter_key_facet=${setup_cli_filter_selected[$filter_key_facet]:-}"
    done
    printf -v "$1" '%s' "$filter_key_text"
}

setup_cli_filter_matches() {
    local match_item="$1" match_facet match_value match_any match_values
    local -a match_options=()
    for match_facet in "${setup_cli_filter_rows[@]}"; do
        [[ "$match_facet" == group || -z "${setup_cli_filter_selected[$match_facet]:-}" ]] && continue
        match_values=" ${setup_cli_filter_values[$match_item:$match_facet]:-unknown} "
        IFS=' ' read -r -a match_options <<< "${setup_cli_filter_selected[$match_facet]}"
        match_any=false
        for match_value in "${match_options[@]}"; do
            [[ "$match_values" != *" $match_value "* ]] || { match_any=true; break; }
        done
        [[ "$match_any" == true ]] || return 1
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
    [[ "$setup_cli_group" == all ]] || ((setup_cli_filter_active++))
    for filter_facet in "${setup_cli_filter_rows[@]}"; do
        [[ "$filter_facet" == group || -z "${setup_cli_filter_selected[$filter_facet]:-}" ]] || ((setup_cli_filter_active++))
    done
    IFS=' ' read -r -a filter_candidates <<< "${setup_cli_group_members[$setup_cli_group]}"
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
    setup_cli_filter_selected=(); setup_cli_group=all
    setup_cli_filter_cache_key=''; setup_cli_filter_offset=0
    setup_about_offset=0
    setup_cli_filters_refresh
}

setup_cli_filter_toggle() {
    local toggle_facet="$1" toggle_option="$2" toggle_text='' toggle_value toggle_old=" ${setup_cli_filter_selected[$1]:-} "
    local -a toggle_options=()
    if [[ "$toggle_facet" == group ]]; then
        setup_cli_group=$toggle_option
    else
        IFS=' ' read -r -a toggle_options <<< "${setup_cli_filter_options[$toggle_facet]}"
        for toggle_value in "${toggle_options[@]}"; do
            if [[ "$toggle_value" == "$toggle_option" ]]; then
                [[ "$toggle_old" != *" $toggle_value "* ]] || continue
            else
                [[ "$toggle_old" == *" $toggle_value "* ]] || continue
            fi
            [[ -z "$toggle_text" ]] || toggle_text+=' '
            toggle_text+="$toggle_value"
        done
        setup_cli_filter_selected[$toggle_facet]=$toggle_text
    fi
    setup_cli_filters_refresh
    setup_about_offset=0
}

setup_cli_filters_key() {
    local filter_key="$1" filter_facet filter_option_index
    local -a filter_options=()
    [[ "$CURRENT_SECTION" == 1 && "$setup_harness_category" == tui ]] || return 1
    if [[ "$filter_key" == f || "$filter_key" == F ]]; then
        if [[ "$setup_harness_zone" == filter ]]; then setup_harness_zone=harness
        else setup_harness_zone=filter; fi
        setup_about_offset=0; setup_cli_filters_refresh
        return 0
    fi
    if [[ "$filter_key" == c || "$filter_key" == C ]]; then setup_cli_filters_clear; return 0; fi
    [[ "$setup_harness_zone" == filter ]] || return 1
    filter_facet=${setup_cli_filter_rows[setup_cli_filter_row]}
    filter_option_index=${setup_cli_filter_cursor[$filter_facet]:-0}
    IFS=' ' read -r -a filter_options <<< "${setup_cli_filter_options[$filter_facet]}"
    case "$filter_key" in
        up) ((setup_cli_filter_row <= 0)) || ((setup_cli_filter_row--)) ;;
        down) ((setup_cli_filter_row+1 >= ${#setup_cli_filter_rows[@]})) || ((setup_cli_filter_row++)) ;;
        tab) setup_cli_filter_cursor[$filter_facet]=$(( (filter_option_index+1) % ${#filter_options[@]} )) ;;
        backtab) setup_cli_filter_cursor[$filter_facet]=$(( (filter_option_index+${#filter_options[@]}-1) % ${#filter_options[@]} )) ;;
        ' ') setup_cli_filter_toggle "$filter_facet" "${filter_options[filter_option_index]}" ;;
        d|D) return 0 ;;
        *) return 1 ;;
    esac
    setup_about_offset=0
    return 0
}

setup_cli_filter_option_label_v() {
    local label_value="${setup_cli_filter_option_labels[$2:$3]}"
    if [[ "$2" == group ]] && ((setup_ui_width < 60)); then
        case "$3" in
            all) label_value=All ;;
            model_usa) label_value='Maker USA' ;;
            model_china) label_value='Maker China' ;;
            model_other) label_value='Maker Other' ;;
            combo_open) label_value='Open/BYOK' ;;
            combo_commercial) label_value=Managed ;;
            specialized) label_value=Specialized ;;
        esac
    fi
    printf -v "$1" '%s' "$label_value"
}

setup_frame_cli_filter_row() {
    local row_facet="$1" row_focus="$2" row_label="${setup_cli_filter_labels[$1]}" row_prefix row_marker=' ' row_value row_token row_box row_text row_budget row_start row_end row_try row_index
    local row_cursor=${setup_cli_filter_cursor[$1]:-0} row_color="$SILVER"
    local -a row_options=() row_tokens=()
    [[ "$row_facet" != via ]] || row_label=Via
    [[ "$row_focus" != true ]] || { row_marker=›; row_color="$SILVER_FOCUS"; }
    printf -v row_prefix '%s %-8s ' "$row_marker" "$row_label"
    IFS=' ' read -r -a row_options <<< "${setup_cli_filter_options[$row_facet]}"
    for row_index in "${!row_options[@]}"; do
        row_value=${row_options[row_index]}; row_box='[ ]'
        if [[ "$row_facet" == group ]]; then
            [[ "$row_value" != "$setup_cli_group" ]] || row_box='[✓]'
        elif [[ " ${setup_cli_filter_selected[$row_facet]:-} " == *" $row_value "* ]]; then row_box='[✓]'; fi
        setup_cli_filter_option_label_v row_token "$row_facet" "$row_value"
        row_token="$row_box $row_token"
        if [[ "$row_focus" == true ]] && ((row_index == row_cursor)); then row_token="›$row_token"; fi
        row_tokens+=("$row_token")
    done
    row_budget=$((setup_ui_width - 4 - ${#row_prefix} - 4)); ((row_budget > 0)) || row_budget=1
    row_start=$row_cursor; row_end=$row_cursor; row_text=${row_tokens[row_cursor]}
    setup_ui_cut_v row_text "$row_text" "$row_budget"
    for ((row_try=row_cursor-1;row_try>=0;row_try--)); do
        ((${#row_tokens[row_try]} + ${#row_text} + 2 <= row_budget)) || break
        row_text="${row_tokens[row_try]}  $row_text"; row_start=$row_try
    done
    for ((row_try=row_cursor+1;row_try<${#row_tokens[@]};row_try++)); do
        ((${#row_tokens[row_try]} + ${#row_text} + 2 <= row_budget)) || break
        row_text+="  ${row_tokens[row_try]}"; row_end=$row_try
    done
    ((row_start == 0)) || row_text="‹ $row_text"
    ((row_end+1 >= ${#row_tokens[@]})) || row_text+=' ›'
    setup_frame_row "$row_prefix$row_text" '' "$row_color"
}

setup_frame_cli_filter_panel() {
    local filter_panel_line panel_budget=0 panel_index panel_facet panel_focus panel_offset=$setup_cli_filter_offset panel_about_window=8 panel_option panel_about panel_selected panel_value
    local -a panel_options=() panel_selected_options=()
    setup_cli_filters_refresh
    [[ "$setup_ui_layout" != roomy ]] || setup_frame_append ''
    setup_panel_top_v filter_panel_line 'Harnesses · Filters' "$setup_cli_filter_count/$setup_cli_filter_total"; setup_frame_append "$filter_panel_line"
    if [[ -n "$setup_ui_height" ]]; then
        panel_budget=$((setup_ui_height - ${#setup_frame_lines[@]} - setup_footer_height - 7))
        ((panel_budget > 0)) || panel_budget=1
    fi
    setup_ui_list_window "${#setup_cli_filter_rows[@]}" "$setup_cli_filter_row" "$panel_budget" panel_offset
    setup_cli_filter_offset=$panel_offset
    if ((setup_window_above > 0)); then setup_frame_row "▲ $setup_window_above filters"; fi
    for ((panel_index=setup_window_start;panel_index<setup_window_start+setup_window_count;panel_index++)); do
        panel_facet=${setup_cli_filter_rows[panel_index]}; panel_focus=false
        ((panel_index != setup_cli_filter_row)) || panel_focus=true
        setup_frame_cli_filter_row "$panel_facet" "$panel_focus"
    done
    if ((setup_window_below > 0)); then setup_frame_row "▼ $setup_window_below filters"; fi
    setup_panel_bottom_v filter_panel_line; setup_frame_append "$filter_panel_line"
    [[ "$setup_ui_layout" != roomy ]] || setup_frame_append ''
    panel_facet=${setup_cli_filter_rows[setup_cli_filter_row]}
    IFS=' ' read -r -a panel_options <<< "${setup_cli_filter_options[$panel_facet]}"
    panel_option=${panel_options[${setup_cli_filter_cursor[$panel_facet]:-0}]}
    panel_selected=''
    IFS=' ' read -r -a panel_selected_options <<< "${setup_cli_filter_selected[$panel_facet]:-}"
    for panel_value in "${panel_selected_options[@]}"; do
        [[ -z "$panel_selected" ]] || panel_selected+=', '
        panel_selected+="${setup_cli_filter_option_labels[$panel_facet:$panel_value]}"
    done
    [[ -n "$panel_selected" ]] || panel_selected=All
    [[ "$panel_facet" != group ]] || panel_selected=${setup_cli_group_labels[$setup_cli_group]}
    panel_about="${setup_cli_filter_summaries[$panel_facet]}"$'\nFocused: '"${setup_cli_filter_option_labels[$panel_facet:$panel_option]}"$'\nSelected: '"$panel_selected"$'\nOR within each row; AND across active rows. Unknown includes partial metadata. F results; C clears filters only.'
    if [[ "$panel_facet" == frontier ]]; then
        panel_about+=$'\nCurated labs: '
        for panel_option in "${!setup_cli_filter_lab_labels[@]}"; do panel_about+="${setup_cli_filter_lab_labels[$panel_option]}, "; done
        panel_option=${panel_options[${setup_cli_filter_cursor[$panel_facet]:-0}]}
    fi
    if [[ -n "$setup_ui_height" ]]; then
        panel_about_window=$((setup_ui_height - ${#setup_frame_lines[@]} - setup_footer_height - 2))
        ((panel_about_window <= 8)) || panel_about_window=8
        ((panel_about_window > 0)) || panel_about_window=1
    fi
    setup_frame_about "harness-filter:$panel_facet:$panel_option" "ABOUT FILTER · ${setup_cli_filter_labels[$panel_facet]^^}" "$panel_about" "$panel_about_window"
}

setup_frame_cli_filter_bar() {
    local bar_line bar_right='F Filters  C Clear'
    setup_cli_filters_refresh
    bar_line="FILTERS · $setup_cli_filter_count/$setup_cli_filter_total"
    if ((setup_ui_width >= 60)); then bar_line+=" · $setup_cli_filter_active active"; fi
    setup_ui_pair_v bar_line "$bar_line" "$bar_right" "$setup_ui_width"
    setup_frame_append "$bar_line"
}
