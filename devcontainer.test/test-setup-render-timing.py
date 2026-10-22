#!/usr/bin/env python3
"""Local-only key-to-redraw benchmark; no engine or host setup is performed."""
import argparse
import os
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--engine-only', action='store_true')
args = parser.parse_args()
script = r'''source scripts/interactive-setup.sh
init_components
setup_load_bench_metadata_sync
for key in "${!component_description[@]}"; do component_status[$key]=installed; done
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
status_checks_running=false
setup_refresh_bench_counts
tput() { case $1 in cols) echo 88;; lines) echo 40;; esac; }
setup_os_label=Linux
CURRENT_SECTION=0; setup_bench_zone=bench; current_selection=0
'''
if args.engine_only:
    script += r'''
setup_frame_build() {
    setup_frame_lines=()
    local i
    for ((i=0; i<40; i++)); do
        setup_frame_lines+=("Synthetic row $i, focus $current_selection, step $CURRENT_SECTION")
    done
}
'''
script += r'''
draw_ui > /dev/null
keys=($'\e[A' $'\e[B' $'\t' $'\e[6~')
for ((round=0;round<25;round++)); do
    for key in "${keys[@]}"; do
        start=${EPOCHREALTIME/./}
        handle_input <<< "$key"
        setup_update_ui_signature
        draw_ui > /dev/null
        finish=${EPOCHREALTIME/./}
        printf 'sample %s\n' "$((finish-start))"
    done
done
for section in 3 0 1 2 4 5; do
    CURRENT_SECTION=$section
    for ((round=0;round<10;round++)); do
        start=${EPOCHREALTIME/./}
        draw_ui > /dev/null
        finish=${EPOCHREALTIME/./}
        printf 'step %s %s\n' "$section" "$((finish-start))"
    done
done
'''
result = subprocess.run(['bash', '-c', script], cwd=ROOT,
                        env=dict(os.environ, WORKBENCHES_SETUP_LOG_FILE='/dev/null', LC_ALL='C.UTF-8'),
                        capture_output=True, text=True, timeout=60)
if result.returncode or result.stderr:
    print(result.stderr, file=sys.stderr)
    sys.exit(result.returncode or 1)
samples = [int(line.split()[1])/1000 for line in result.stdout.splitlines() if line.startswith('sample ')]
assert len(samples)==100, result.stdout
median = statistics.median(samples)
print(('Engine-only' if args.engine_only else 'Full Benches') +
      f': median={median:.3f}ms p90={sorted(samples)[89]:.3f}ms max={max(samples):.3f}ms')
for section, name in ((3,'Workstation'),(0,'Benches'),(1,'Agents'),(2,'Tools'),(4,'Profiles'),(5,'Review')):
    values=[int(line.split()[2])/1000 for line in result.stdout.splitlines() if line.startswith(f'step {section} ')]
    print(f'{name}: median={statistics.median(values):.3f}ms')
sys.exit(0 if median <= (25 if args.engine_only else 100) else 1)
