#!/usr/bin/env python3
"""Faceted CLI filter intersections, provenance, queue safety and state."""
import json
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')


class FilterTests(unittest.TestCase):
    def shell(self, body, locale='C.UTF-8'):
        result = subprocess.run(['bash', '-c', 'source scripts/interactive-setup.sh\ninit_components --loading\nsetup_arrive_step 1\n' + body], cwd=ROOT,
                                env=dict(os.environ, WORKBENCHES_SETUP_LOG_FILE='/dev/null', LC_ALL=locale),
                                text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(result.stderr, result.stderr)
        return result.stdout

    def test_facets_use_or_within_and_across_and_do_not_change_the_queue(self):
        output=self.shell(r'''
component_checked[codex_cli]=true; component_action[codex_cli]=update
setup_cli_filters_refresh; [[ "$setup_cli_filter_count" == 77 ]] || exit 30
setup_cli_filter_toggle region usa
usa=$setup_cli_filter_count
setup_cli_filter_toggle region china
[[ "$setup_cli_filter_count" -gt "$usa" ]] || exit 31
setup_cli_filter_toggle access api
[[ "$setup_cli_filter_members" == *codex_cli* && "$setup_cli_filter_members" == *opencode_cli* ]] && exit 32
# Region USA/China excludes independent OpenCode's unverified region.
[[ "$setup_cli_filter_members" == *codex_cli* && "$setup_cli_filter_members" == *claude_cli* ]] || exit 33
setup_cli_filter_toggle frontier frontier
[[ "$setup_cli_filter_members" == *codex_cli* && "$setup_cli_filter_members" != *opencode_cli* ]] || exit 34
setup_cli_filter_toggle native image
[[ "$setup_cli_filter_members" == codex_cli ]] || exit 35
setup_cli_filter_toggle access subscription
[[ "$setup_cli_filter_members" == codex_cli ]] || exit 36
setup_cli_filter_toggle native llm
[[ "$setup_cli_filter_members" == *claude_cli* ]] || exit 37
[[ "${component_action[codex_cli]}" == update ]] || exit 38
setup_cli_filters_clear
[[ "$setup_cli_filter_count" == 77 && "${component_action[codex_cli]}" == update ]] || exit 39
echo combined
''')
        self.assertEqual(output.strip(),'combined')

    def test_native_and_external_capabilities_and_unknown_remain_separate(self):
        output=self.shell(r'''
setup_cli_filter_toggle via voice
[[ "$setup_cli_filter_members" == *codex_cli* && "$setup_cli_filter_members" == *qwen_cli* ]] || exit 30
setup_cli_filter_toggle native voice
[[ "$setup_cli_filter_count" == 0 ]] || exit 31
setup_cli_filter_toggle native voice
setup_cli_filter_toggle native image
[[ "$setup_cli_filter_members" == codex_cli ]] || exit 32
setup_cli_filters_clear
setup_cli_filter_toggle native video
[[ "$setup_cli_filter_members" == kimi_code ]] || exit 38
setup_cli_filters_clear
setup_cli_filter_toggle access unknown
[[ "$setup_cli_filter_count" == 77 ]] || exit 33
setup_cli_filter_toggle frontier frontier
[[ "$setup_cli_filter_members" != *opencode_cli* && "$setup_cli_filter_members" == *qwen_cli* ]] || exit 34
[[ "${setup_cli_filter_values[codex_cli:native]}" == *image* ]] || exit 35
[[ "${setup_cli_filter_values[codex_cli:native]}" != *voice* ]] || exit 36
[[ "${setup_cli_filter_values[codex_cli:via]}" == *voice* ]] || exit 37
echo qualified
''')
        self.assertEqual(output.strip(),'qualified')

    def test_empty_results_never_expose_or_queue_a_hidden_product(self):
        output=self.shell(r'''
for key in "${ai_items[@]}"; do component_status[$key]=installed; done
setup_focus_harness_key codex_cli; setup_harness_zone=harness
component_checked[codex_cli]=true; component_action[codex_cli]=update
setup_cli_filter_toggle native classifier
setup_ui_width=87; setup_ui_height=40; setup_frame_build
printf '%s\n' "${setup_frame_lines[@]}"
[[ "$setup_about_anchor" == harness-empty ]] || exit 30
handle_input <<< ' '; handle_input <<< D
[[ "${component_action[codex_cli]}" == update ]] || exit 31
handle_input <<< $'\e[B'; handle_input <<< ' '
[[ "${component_action[codex_cli]}" == update ]] || exit 32
handle_input <<< C
[[ "$setup_cli_filter_count" == 77 && "${component_action[codex_cli]}" == update ]] || exit 33
''')
        plain=ANSI.sub('',output)
        self.assertIn('No matching harnesses',plain)
        self.assertIn('NO MATCHING HARNESSES',plain)
        self.assertIn('Queued changes stay in Review',plain)
        self.assertNotIn('ABOUT CODEX',plain)
        self.assertNotIn('› [',plain)

    def test_keyboard_options_toggle_and_panel_navigation_is_not_installation(self):
        output=self.shell(r'''
handle_input <<< F
[[ "$setup_harness_zone" == filter ]] || exit 30
handle_input <<< ' '
[[ "${setup_cli_filter_selected[frontier]}" == frontier ]] || exit 31
handle_input <<< $'\e[B'; handle_input <<< $'\t'; handle_input <<< ' '
[[ "${setup_cli_filter_selected[region]}" == china ]] || exit 32
handle_input <<< $'\e[Z'; handle_input <<< ' '
[[ "${setup_cli_filter_selected[region]}" == 'usa china' ]] || exit 33
handle_input <<< $'\e[B'; handle_input <<< $'\t'; handle_input <<< ' '
[[ "${setup_cli_filter_selected[access]}" == api ]] || exit 34
handle_input <<< D
for key in "${ai_items[@]}"; do [[ "${component_checked[$key]}" != true ]] || exit 35; done
handle_input <<< F
[[ "$setup_harness_zone" == harness ]] || exit 36
handle_input <<< F; handle_input <<< C
[[ "$setup_cli_filter_active" == 0 && "$setup_cli_filter_count" == 77 ]] || exit 37
handle_input <<< $'\e[C'
[[ "$CURRENT_SECTION" == 2 ]] || exit 38
handle_input <<< F; handle_input <<< C
[[ "$CURRENT_SECTION" == 2 ]] || exit 39
setup_arrive_step 1; handle_input <<< F; handle_input <<< ''
[[ "$CURRENT_SECTION" == 5 ]] || exit 40
echo keyboard
''')
        self.assertEqual(output.strip(),'keyboard')

    def test_filtered_product_and_panel_state_survive_jumps_and_refresh(self):
        output=self.shell(r'''
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
for key in "${ai_items[@]}"; do component_status[$key]=installed; done
setup_cli_filter_toggle frontier frontier
setup_cli_filter_toggle region china
setup_harness_zone=harness; setup_focus_harness_key dsh_cli
component_about[dsh_cli]=''
for ((i=0;i<80;i++)); do component_about[dsh_cli]+='Long filter evidence and integration description. '; done
setup_ui_width=36; setup_ui_height=24; setup_frame_build
result_key="tui:$setup_cli_filter_cache_key"; saved_list=${setup_harness_offsets[$result_key]}
handle_input <<< ']'; saved_about=$setup_about_offset
[[ "$saved_about" -gt 0 ]] || exit 30
for jump in G P; do
    handle_input <<< "$jump"; setup_frame_build; handle_input <<< "$jump"; setup_frame_build
    [[ "${setup_cli_filter_selected[frontier]}" == frontier && "${setup_cli_filter_selected[region]}" == china ]] || exit 31
    [[ "${ai_items[$current_selection]}" == dsh_cli && "$setup_about_offset" == "$saved_about" && "${setup_harness_offsets[$result_key]}" == "$saved_list" ]] || exit 32
done
handle_input <<< F; handle_input <<< $'\e[B'; handle_input <<< $'\t'; setup_frame_build
saved_row=$setup_cli_filter_row; saved_option=${setup_cli_filter_cursor[region]}
handle_input <<< G; setup_frame_build; handle_input <<< G; setup_frame_build
[[ "$setup_harness_zone" == filter && "$setup_cli_filter_row" == "$saved_row" && "${setup_cli_filter_cursor[region]}" == "$saved_option" ]] || exit 33
status_async_ui=false
refresh_host_tool_inventory() { :; }; setup_load_bench_metadata_sync() { :; }; refresh_bench_inventory() { :; }
check_component_status() { echo installed; }; load_requirements() { :; }; draw_ui() { setup_frame_build; }
handle_input <<< R
[[ "${setup_cli_filter_selected[region]}" == china && "$setup_harness_zone" == filter && "${setup_cli_filter_cursor[region]}" == "$saved_option" ]] || exit 34
setup_arrive_step 2; setup_arrive_step 1; setup_frame_build
[[ "${setup_cli_filter_selected[region]}" == china ]] || exit 35
[[ " $setup_cli_filter_members " == *" ${ai_items[$current_selection]} "* && "${ai_items[$current_selection]}" != claude_cli ]] || exit 36
setup_harness_zone=harness; current_selection=0
handle_input <<< ' '; handle_input <<< D
[[ "${component_action[claude_cli]}" == '' ]] || exit 37
echo restored
''')
        self.assertEqual(output.strip(),'restored')

    def test_filter_panel_and_empty_results_fit_both_locale_size_matrices(self):
        for locale in ('C.UTF-8','C'):
            output=self.shell(r'''
for key in "${!component_description[@]}"; do component_status[$key]=installed; done
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
for setup_ui_width in 36 60 87; do
    for setup_ui_height in 24 40 ''; do
        for setup_cli_filter_row in 0 1 2 3 4 5; do
            setup_harness_zone=filter
            facet=${setup_cli_filter_rows[setup_cli_filter_row]}
            IFS=' ' read -r -a options <<< "${setup_cli_filter_options[$facet]}"
            setup_cli_filter_cursor[$facet]=$((${#options[@]}-1))
            setup_frame_build
            printf 'FRAME:%s:%s:filter\n' "$setup_ui_width" "$setup_ui_height"
            printf '%s\n' "${setup_frame_lines[@]}"
        done
        setup_cli_filter_toggle native classifier; setup_harness_zone=harness; setup_frame_build
        printf 'FRAME:%s:%s:empty\n' "$setup_ui_width" "$setup_ui_height"
        printf '%s\n' "${setup_frame_lines[@]}"
        setup_cli_filters_clear
    done
done
''',locale)
            frames=output.split('FRAME:')[1:]
            self.assertEqual(len(frames),63)
            for frame in frames:
                marker,*lines=ANSI.sub('',frame).splitlines(); width,height,zone=marker.split(':')
                self.assertTrue(all(len(line)<=int(width) for line in lines),marker)
                if height:self.assertLessEqual(len(lines),int(height),marker)
                text='\n'.join(lines)
                for required in ('ABOUT','Navigation:','Enter Review','Q Quit'):self.assertIn(required,text)
                if zone=='filter':
                    self.assertIn('Harnesses',text);self.assertIn('Filters',text);self.assertIn('›',text)
                else:self.assertIn('No matching',text)

    def test_matching_and_rendering_start_no_discovery_process(self):
        output=self.shell(r'''
for key in "${!component_description[@]}"; do component_status[$key]=installed; done
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
python3() { echo UNEXPECTED_DISCOVERY; return 99; }; jq() { echo UNEXPECTED_DISCOVERY; return 99; }
docker() { echo UNEXPECTED_DISCOVERY; return 99; }; git() { echo UNEXPECTED_DISCOVERY; return 99; }
setup_cli_filter_toggle region usa; setup_cli_filter_toggle native image
setup_harness_zone=filter; setup_ui_width=87; setup_ui_height=40; setup_frame_build
printf '%s\n' "${setup_frame_lines[@]}"
''')
        self.assertNotIn('UNEXPECTED_DISCOVERY',output)
        self.assertIn('1/77',output)


if __name__=='__main__':unittest.main()
