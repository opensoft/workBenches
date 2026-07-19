#!/usr/bin/env bash
# Two-line Claude Code status line. Claude supplies session data as JSON on stdin.

input=$(cat)
if ! jq -e . >/dev/null 2>&1 <<<"$input"; then
    exit 0
fi

# Parse the input once. Missing fields intentionally become empty strings.
mapfile -t data < <(jq -r '[
    (.workspace.current_dir // .cwd // ""),
    (.workspace.repo.name // ""),
    (.workspace.git_worktree // .worktree.name // ""),
    (.worktree.branch // ""),
    (.model.display_name // .model.id // ""),
    (.context_window.used_percentage // 0),
    (.effort.level // ""),
    (.thinking.enabled // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.session_name // ""),
    (.agent.name // ""),
    (.pr.number // ""),
    (.pr.review_state // ""),
    (.permission_mode // .permissions.mode // "")
] | .[]' <<<"$input")

cwd=${data[0]:-}
repo_name=${data[1]:-}
worktree_name=${data[2]:-}
worktree_branch=${data[3]:-}
model=${data[4]:-}
used_pct=${data[5]:-}
effort=${data[6]:-}
thinking=${data[7]:-}
five_hour_pct=${data[8]:-}
five_hour_reset=${data[9]:-}
seven_day_pct=${data[10]:-}
seven_day_reset=${data[11]:-}
session_name=${data[12]:-}
agent_name=${data[13]:-}
pr_number=${data[14]:-}
pr_state=${data[15]:-}
permission_mode=${data[16]:-}

columns=${COLUMNS:-120}
[[ $columns =~ ^[0-9]+$ ]] || columns=120

reset=$'\033[0m'
dim=$'\033[2m'
blink=$'\033[5m'
cyan=$'\033[36m'
yellow=$'\033[33m'
magenta=$'\033[35m'
blue=$'\033[34m'
green=$'\033[32m'
red=$'\033[31m'
countdown_red=$'\033[38;5;196m'
countdown_red_orange=$'\033[38;5;202m'
countdown_orange=$'\033[38;5;208m'
countdown_amber=$'\033[38;5;214m'
countdown_yellow=$'\033[38;5;220m'
countdown_green_yellow=$'\033[38;5;154m'
countdown_light_green=$'\033[38;5;120m'
countdown_dark_green=$'\033[38;5;22m'
sep="${dim}|${reset}"

join_parts() {
    local out="" part
    for part in "$@"; do
        [[ -z $part ]] && continue
        if [[ -z $out ]]; then
            out=$part
        else
            out+=" $sep $part"
        fi
    done
    printf '%s' "$out"
}

truncate_middle() {
    local value=$1 max=$2 side
    if (( ${#value} <= max )); then
        printf '%s' "$value"
        return
    fi
    side=$(( (max - 3) / 2 ))
    printf '%s...%s' "${value:0:side}" "${value: -side}"
}

pct_integer() {
    local value=$1 rounded
    rounded=$(printf '%.0f' "$value" 2>/dev/null) || rounded=0
    (( rounded < 0 )) && rounded=0
    (( rounded > 100 )) && rounded=100
    printf '%s' "$rounded"
}

pct_color() {
    local value=$1
    if (( value >= 80 )); then
        printf '%s' "$red"
    elif (( value >= 60 )); then
        printf '%s' "$yellow"
    else
        printf '%s' "$green"
    fi
}

context_segment() {
    local pct color filled empty bar_width bar empty_bar
    pct=$(pct_integer "$used_pct")
    color=$(pct_color "$pct")
    bar_width=$(( columns >= 100 ? 12 : 8 ))
    filled=$(( pct * bar_width / 100 ))
    empty=$(( bar_width - filled ))
    printf -v bar '%*s' "$filled" ''
    bar=${bar// /=}
    printf -v empty_bar '%*s' "$empty" ''
    empty_bar=${empty_bar// /-}
    printf '%s[%s%s] %s%%%s' "$color" "$bar" "$empty_bar" "$pct" "$reset"
}

rate_segment() {
    local label=$1 raw_pct=$2 reset_at=$3 pct color effect="" reset_text="" bar_width filled empty bar empty_bar
    bar_width=$(( columns >= 100 ? 10 : 8 ))
    if [[ -z $raw_pct ]]; then
        printf -v empty_bar '%*s' "$bar_width" ''
        empty_bar=${empty_bar// /-}
        printf '%s%s [%s] --%s' "$dim" "$label" "$empty_bar" "$reset"
        return
    fi
    pct=$(pct_integer "$raw_pct")
    color=$(pct_color "$pct")
    if (( pct >= 95 && pct < 100 )); then
        effect=$blink
    fi
    filled=$(( pct * bar_width / 100 ))
    empty=$(( bar_width - filled ))
    printf -v bar '%*s' "$filled" ''
    bar=${bar// /=}
    printf -v empty_bar '%*s' "$empty" ''
    empty_bar=${empty_bar// /-}
    if (( pct >= 80 )) && [[ $reset_at =~ ^[0-9]+$ ]]; then
        reset_text=$(date -d "@$reset_at" '+ %H:%M' 2>/dev/null || true)
    fi
    printf '%s%s%s [%s%s] %s%%%s%s' "$color" "$effect" "$label" "$bar" "$empty_bar" "$pct" "$reset" "$reset_text"
}

repeat_char() {
    local char=$1 count=$2 value
    (( count <= 0 )) && return
    printf -v value '%*s' "$count" ''
    printf '%s' "${value// /$char}"
}

countdown_color() {
    local remaining=$1 window_seconds=$2

    # A reset getting closer is good: move from red toward green. The five-hour
    # window gets human-friendly hourly steps plus finer final thresholds.
    if (( remaining <= 0 )); then
        printf '%s' "$countdown_dark_green"
    elif (( remaining <= 300 )); then
        printf '%s' "$countdown_light_green"
    elif (( remaining <= 1800 )); then
        printf '%s' "$countdown_green_yellow"
    elif (( remaining <= 3600 )); then
        printf '%s' "$countdown_yellow"
    elif (( remaining <= 7200 )); then
        printf '%s' "$countdown_amber"
    elif (( remaining <= 10800 )); then
        printf '%s' "$countdown_orange"
    elif (( remaining <= 14400 )); then
        printf '%s' "$countdown_red_orange"
    elif (( window_seconds <= 18000 )); then
        printf '%s' "$countdown_red"
    elif (( remaining * 100 <= window_seconds * 15 )); then
        printf '%s' "$countdown_green_yellow"
    elif (( remaining * 100 <= window_seconds * 35 )); then
        printf '%s' "$countdown_yellow"
    elif (( remaining * 100 <= window_seconds * 55 )); then
        printf '%s' "$countdown_amber"
    elif (( remaining * 100 <= window_seconds * 75 )); then
        printf '%s' "$countdown_orange"
    elif (( remaining * 100 <= window_seconds * 90 )); then
        printf '%s' "$countdown_red_orange"
    else
        printf '%s' "$countdown_red"
    fi
}

countdown_segment() {
    local label=$1 reset_at=$2 window_seconds=$3 unit=$4
    local now remaining elapsed bar_width marker_pos bar color effect="" amount reset_text

    bar_width=$(( columns >= 100 ? 8 : 6 ))
    if [[ ! $reset_at =~ ^[0-9]+$ ]]; then
        bar=$(repeat_char '-' "$bar_width")
        printf '%s%s [%s] waiting%s' "$dim" "$label" "$bar" "$reset"
        return
    fi

    now=$(date +%s)
    remaining=$(( reset_at - now ))
    (( remaining < 0 )) && remaining=0
    elapsed=$(( window_seconds - remaining ))
    (( elapsed < 0 )) && elapsed=0
    (( elapsed > window_seconds )) && elapsed=$window_seconds
    marker_pos=$(( elapsed * (bar_width - 1) / window_seconds ))
    bar="$(repeat_char '=' "$marker_pos")>$(repeat_char '-' "$((bar_width - marker_pos - 1))")"

    color=$(countdown_color "$remaining" "$window_seconds")
    if (( remaining > 0 && remaining < 120 )); then
        effect=$blink
    fi

    if [[ $unit == minutes ]]; then
        amount="$(( (remaining + 59) / 60 ))m"
        reset_text=$(TZ="${STATUSLINE_TZ:-America/Los_Angeles}" date -d "@$reset_at" '+%-I:%M%p %Z' 2>/dev/null || true)
    else
        if (( remaining >= 86400 )); then
            amount="$(( remaining / 86400 ))d"
        else
            amount="$(( (remaining + 3599) / 3600 ))h"
        fi
        if (( columns >= 100 )); then
            reset_text=$(TZ="${STATUSLINE_TZ:-America/Los_Angeles}" date -d "@$reset_at" '+%a %b %d %-I:%M%p %Z' 2>/dev/null || true)
        else
            reset_text=$(TZ="${STATUSLINE_TZ:-America/Los_Angeles}" date -d "@$reset_at" '+%b %d %-I:%M%p' 2>/dev/null || true)
        fi
    fi

    printf '%s%s%s [%s] %s left%s %s@ %s%s' "$color" "$effect" "$label" "$bar" "$amount" "$reset" "$dim" "$reset_text" "$reset"
}

fable_weekly_limit() {
    local config_dir credentials cache now modified token tmp response_pct response_reset

    # The status-line payload currently exposes only the aggregate seven-day
    # limit. Claude's own read-only usage endpoint also returns scoped weekly
    # limits, including Fable. Cache it because this script refreshes often.
    config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
    credentials="$config_dir/.credentials.json"
    cache="$config_dir/cache/statusline-usage.json"
    now=$(date +%s)
    modified=0
    [[ -f $cache ]] && modified=$(stat -c %Y "$cache" 2>/dev/null || printf '0')

    if (( now - modified >= 60 )) && [[ -r $credentials ]] && command -v curl >/dev/null 2>&1; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$credentials" 2>/dev/null)
        if [[ -n $token ]]; then
            mkdir -p "${cache%/*}"
            tmp="$cache.$$"
            if curl -fsS --connect-timeout 1 --max-time 3 \
                'https://api.anthropic.com/api/oauth/usage' \
                -H "Authorization: Bearer $token" \
                -H 'anthropic-version: 2023-06-01' \
                -H 'anthropic-beta: oauth-2025-04-20' \
                -o "$tmp" \
                && jq -e '.limits | type == "array"' "$tmp" >/dev/null 2>&1; then
                chmod 600 "$tmp"
                mv -f "$tmp" "$cache"
            else
                rm -f "$tmp"
            fi
        fi
    fi

    [[ -r $cache ]] || return 0
    response_pct=$(jq -r '
        [.limits[]?
          | select(.kind == "weekly_scoped")
          | select((.scope.model.display_name // "" | ascii_downcase) == "fable")
          | .percent] | first // empty
    ' "$cache" 2>/dev/null)
    response_reset=$(jq -r '
        [.limits[]?
          | select(.kind == "weekly_scoped")
          | select((.scope.model.display_name // "" | ascii_downcase) == "fable")
          | .resets_at] | first // empty
    ' "$cache" 2>/dev/null)
    if [[ -n $response_reset ]]; then
        response_reset=$(date -d "$response_reset" +%s 2>/dev/null || printf '')
    fi
    [[ -n $response_pct ]] && printf '%s\t%s\n' "$response_pct" "$response_reset"
}

# Build a compact path. Narrow terminals favor repository and leaf names.
short_cwd=${cwd/#$HOME/\~}
if (( columns < 100 )); then
    leaf=${cwd##*/}
    if [[ -n $repo_name && $repo_name != "$leaf" ]]; then
        short_cwd="$repo_name/$leaf"
    elif [[ -n $repo_name ]]; then
        short_cwd=$repo_name
    else
        short_cwd=$leaf
    fi
fi
path_max=$(( columns >= 120 ? 52 : (columns >= 80 ? 34 : 24) ))
short_cwd=$(truncate_middle "$short_cwd" "$path_max")

# One bounded Git command supplies branch, dirty counts, and ahead/behind state.
git_branch=$worktree_branch
git_status_text=""
if [[ -n $cwd ]]; then
    if command -v timeout >/dev/null 2>&1; then
        git_output=$(GIT_OPTIONAL_LOCKS=0 timeout 1s git -C "$cwd" status --porcelain=v1 --branch --untracked-files=normal 2>/dev/null)
    else
        git_output=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" status --porcelain=v1 --branch --untracked-files=normal 2>/dev/null)
    fi
    if [[ -n $git_output ]]; then
        staged=0
        modified=0
        untracked=0
        ahead=0
        behind=0
        while IFS= read -r status_line; do
            if [[ $status_line == '## '* ]]; then
                branch_header=${status_line#'## '}
                [[ -z $git_branch ]] && git_branch=${branch_header%%...*}
                [[ $branch_header =~ ahead[[:space:]]+([0-9]+) ]] && ahead=${BASH_REMATCH[1]}
                [[ $branch_header =~ behind[[:space:]]+([0-9]+) ]] && behind=${BASH_REMATCH[1]}
            elif [[ ${status_line:0:2} == '??' ]]; then
                ((untracked++))
            else
                [[ ${status_line:0:1} != ' ' ]] && ((staged++))
                [[ ${status_line:1:1} != ' ' ]] && ((modified++))
            fi
        done <<<"$git_output"
        (( staged > 0 )) && git_status_text+=" +$staged"
        (( modified > 0 )) && git_status_text+=" ~$modified"
        (( untracked > 0 )) && git_status_text+=" ?$untracked"
        (( ahead > 0 )) && git_status_text+=" a$ahead"
        (( behind > 0 )) && git_status_text+=" b$behind"
    fi
fi

line1_parts=("${dim}[WORK]${reset}" "${cyan}${short_cwd}${reset}")
if [[ -n $git_branch ]]; then
    branch_max=$(( columns >= 100 ? 30 : 18 ))
    git_branch=$(truncate_middle "$git_branch" "$branch_max")
    line1_parts+=("${yellow}${git_branch}${reset}${git_status_text}")
fi
if [[ -n $pr_number && $columns -ge 80 ]]; then
    pr_text="PR #$pr_number"
    [[ -n $pr_state ]] && pr_text+=" $pr_state"
    line1_parts+=("${blue}${pr_text}${reset}")
fi

line2_parts=("${dim}[MODEL]${reset}")
model_text=$model
[[ -n $effort ]] && model_text+=" $effort"
[[ $thinking == true && $columns -ge 100 ]] && model_text+=" think"
[[ -n $model_text ]] && line2_parts+=("${magenta}${model_text}${reset}")
line2_parts+=("CTX $(context_segment)")

fable_weekly_pct=$(jq -r '.rate_limits.seven_day_fable.used_percentage // empty' <<<"$input")
fable_weekly_reset=$(jq -r '.rate_limits.seven_day_fable.resets_at // empty' <<<"$input")
if [[ -z $fable_weekly_pct ]]; then
    IFS=$'\t' read -r fable_weekly_pct fable_weekly_reset < <(fable_weekly_limit)
fi

line3_parts=(
    "${dim}[LIMIT]${reset}"
    "$(rate_segment '5h' "$five_hour_pct" "$five_hour_reset")"
    "$(rate_segment '7d All' "$seven_day_pct" "$seven_day_reset")"
)
[[ -n $fable_weekly_pct ]] && line3_parts+=("$(rate_segment '7d Fable' "$fable_weekly_pct" "$fable_weekly_reset")")

identity=""
if [[ -n $agent_name ]]; then
    identity="agent:$agent_name"
elif [[ -n $session_name ]]; then
    identity="session:$session_name"
elif [[ -n $worktree_name ]]; then
    identity="wt:$worktree_name"
fi
runtime_target=""
# AgentTower needs the exact tmux session name for `tmux attach -t`.
if [[ -n ${TMUX:-} ]] && command -v tmux >/dev/null 2>&1; then
    tmux_session=$(tmux display-message -p '#S' 2>/dev/null || true)
    if [[ -n $tmux_session ]]; then
        runtime_target="tmux:${tmux_session}"
        [[ -n ${TMUX_PANE:-} ]] && runtime_target+="/${TMUX_PANE}"
    fi
fi
[[ -z $runtime_target && -n $identity ]] && runtime_target=$identity
[[ -n $runtime_target ]] && line1_parts+=("${blue}${runtime_target}${reset}")

weekly_reset=${fable_weekly_reset:-$seven_day_reset}
line4_parts=(
    "${dim}[RESET]${reset}"
    "$(countdown_segment '5h' "$five_hour_reset" 18000 minutes)"
    "$(countdown_segment '7d' "$weekly_reset" 604800 days)"
)

printf '%s\n' "$(join_parts "${line1_parts[@]}")"
printf '%s\n' "$(join_parts "${line2_parts[@]}")"
printf '%s\n' "$(join_parts "${line3_parts[@]}")"
printf '%s\n' "$(join_parts "${line4_parts[@]}")"
