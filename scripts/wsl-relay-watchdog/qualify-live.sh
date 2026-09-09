#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENGINE=${1:-"${SCRIPT_DIR}/wsl_relay_watchdog.py"}
MIN_AGE_SECONDS=${MIN_AGE_SECONDS:-300}

temporary_directory=$(mktemp -d)
trap 'rm -rf -- "${temporary_directory}"' EXIT

engine_json="${temporary_directory}/engine.json"
engine_pids="${temporary_directory}/engine-pids"
manual_pids="${temporary_directory}/manual-pids"
protected_pids="${temporary_directory}/protected-pids"

python3 "${ENGINE}" scan >"${engine_json}"
python3 - "${engine_json}" "${engine_pids}" "${protected_pids}" <<'PY'
import json
from pathlib import Path
import sys

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
strict = sorted(int(item["pid"]) for item in payload["strict_candidates"])
protected = sorted(
    int(item["pid"])
    for key in ("protected_named_relays", "protected_session_leaders")
    for item in payload[key]
)
Path(sys.argv[2]).write_text("".join(f"{pid}\n" for pid in strict), encoding="ascii")
Path(sys.argv[3]).write_text("".join(f"{pid}\n" for pid in protected), encoding="ascii")
print(f"ENGINE_STRICT={len(strict)}")
print(f"PROTECTED_NAMED={payload['protected_named_relay_count']}")
print(f"PROTECTED_SESSION_LEADERS={payload['protected_session_leader_count']}")
print(f"ENGINE_INSPECTION_ERRORS={len(payload['inspection_errors'])}")
PY

: >"${manual_pids}"
clock_ticks=$(getconf CLK_TCK)
uptime_seconds=$(cut -d ' ' -f 1 /proc/uptime)
for process_dir in /proc/[0-9]*; do
    pid=${process_dir##*/}
    if ! IFS= read -r process_name <"${process_dir}/comm" 2>/dev/null; then
        continue
    fi
    [[ "${process_name}" == "Relay" ]] || continue

    if ! IFS= read -r stat_line <"${process_dir}/stat" 2>/dev/null; then
        continue
    fi
    read -r -a stat_fields <<<"${stat_line}"
    [[ ${#stat_fields[@]} -ge 22 ]] || continue
    [[ "${stat_fields[3]}" == "1" ]] || continue
    start_time_ticks=${stat_fields[21]}
    [[ "${start_time_ticks}" =~ ^[0-9]+$ ]] || continue

    command_line=()
    if ! mapfile -d '' -t command_line <"${process_dir}/cmdline" 2>/dev/null; then
        continue
    fi
    [[ ${#command_line[@]} -eq 1 && "${command_line[0]}" == "/init" ]] || continue

    if ! children=$(cat "${process_dir}/task/${pid}/children" 2>/dev/null); then
        continue
    fi
    [[ -z "${children//[[:space:]]/}" ]] || continue

    if awk -v uptime="${uptime_seconds}" -v start="${start_time_ticks}" -v hz="${clock_ticks}" -v minimum="${MIN_AGE_SECONDS}" 'BEGIN { exit !((uptime - start / hz) >= minimum) }'; then
        printf '%s\n' "${pid}" >>"${manual_pids}"
    fi
done
sort -n -o "${manual_pids}" "${manual_pids}"

printf 'MANUAL_STRICT=%s\n' "$(wc -l <"${manual_pids}")"
if cmp -s "${engine_pids}" "${manual_pids}"; then
    echo "STRICT_SET_MATCH=true"
else
    echo "STRICT_SET_MATCH=false"
    echo "Strict PID differences:" >&2
    diff -u "${manual_pids}" "${engine_pids}" >&2 || true
    exit 1
fi

protected_overlap=$(awk 'NR == FNR { protected[$1] = 1; next } protected[$1] { count++ } END { print count + 0 }' "${protected_pids}" "${engine_pids}")
printf 'PROTECTED_OVERLAP=%s\n' "${protected_overlap}"
[[ "${protected_overlap}" == "0" ]]
