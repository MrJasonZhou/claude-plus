#!/usr/bin/env bash
# Claude Plus - enhancements for Claude Code
# Copyright (C) 2026 Jason Zhou
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. See the LICENSE file for details.
set -euo pipefail

BASE="$HOME/.claude/claude-plus"
STATE="$BASE/state"
PENDING="$STATE/pending"
STALE="$STATE/stale"
BIN="$BASE/claude-plus.sh"
ORIG="$BASE/original-statusline-command"
NOTIFY="$BASE/notify.sh"
SETTINGS="$HOME/.claude/settings.json"
MARKER="/claude-plus/claude-plus.sh"

# Check the commands we depend on
for cmd in claude jq at atq atrm flock date timeout tmux; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command not found: $cmd" >&2
        exit 1
    fi
done

mkdir -p "$HOME/.claude"

# Start from an empty object when there is no settings.json yet
if [[ ! -f "$SETTINGS" ]]; then
    printf '{}\n' > "$SETTINGS"
fi

# Refuse to touch a settings.json that is not valid JSON
jq empty "$SETTINGS"

STAMP="$(date +%Y%m%d-%H%M%S)"
SETTINGS_BACKUP="$SETTINGS.claude-plus-install-backup.$STAMP"
cp -p "$SETTINGS" "$SETTINGS_BACKUP"

PRESERVED_ORIG=""
if [[ -s "$ORIG" ]]; then
    PRESERVED_ORIG="$(mktemp)"
    cp -p "$ORIG" "$PRESERVED_ORIG"
fi

# The notify script carries the user's own credentials, so a reinstall
# must not throw it away along with the rest of the directory
PRESERVED_NOTIFY=""
if [[ -f "$NOTIFY" ]]; then
    PRESERVED_NOTIFY="$(mktemp)"
    cp -p "$NOTIFY" "$PRESERVED_NOTIFY"
fi

cleanup_temp() {
    if [[ -n "$PRESERVED_ORIG" && -f "$PRESERVED_ORIG" ]]; then
        rm -f "$PRESERVED_ORIG"
    fi

    if [[ -n "$PRESERVED_NOTIFY" && -f "$PRESERVED_NOTIFY" ]]; then
        rm -f "$PRESERVED_NOTIFY"
    fi
}
trap cleanup_temp EXIT

remove_old_installation() {
    local found=0

    if [[ -e "$BASE" ]]; then
        found=1
    fi

    if jq -e --arg marker "$MARKER" '
        ((.statusLine.command? // "") | contains($marker))
        or
        ([.hooks? // {} | to_entries[]? | .value[]? | .hooks[]? | (.command? // "") | contains($marker)] | any)
    ' "$SETTINGS" >/dev/null 2>&1; then
        found=1
    fi

    if (( found == 0 )); then
        return 0
    fi

    echo "Existing installation detected. Removing it first..."

    # Only remove at jobs this tool registered
    while read -r job_id _; do
        [[ -n "$job_id" ]] || continue
        if at -c "$job_id" 2>/dev/null | grep -Fq "$MARKER"; then
            atrm "$job_id" >/dev/null 2>&1 || true
        fi
    done < <(atq 2>/dev/null || true)

    # Strip only our own entries rather than restoring the whole backup
    local tmp
    tmp="$(mktemp)"

    jq --arg marker "$MARKER" '
        def clean_hook_groups:
            if type != "array" then .
            else
                map(
                    .hooks = (
                        (.hooks // [])
                        | map(
                            select(
                                (((.command // "") | contains($marker)) | not)
                            )
                        )
                    )
                )
                | map(select(((.hooks // []) | length) > 0))
            end;

        if ((.statusLine.command? // "") | contains($marker)) then
            del(.statusLine)
        else
            .
        end
        |
        if (.hooks? | type) == "object" then
            .hooks |= with_entries(.value |= clean_hook_groups)
            | .hooks |= with_entries(select((.value | type) != "array" or (.value | length) > 0))
            | if (.hooks | length) == 0 then del(.hooks) else . end
        else
            .
        end
    ' "$SETTINGS" > "$tmp"

    jq empty "$tmp"
    mv "$tmp" "$SETTINGS"

    # Remove the script and its state
    rm -rf "$BASE"
}

remove_old_installation

mkdir -p "$BASE" "$STATE" "$PENDING" "$STALE"

# Put the user's notify script back after the directory was cleared
if [[ -n "$PRESERVED_NOTIFY" && -f "$PRESERVED_NOTIFY" ]]; then
    cp -p "$PRESERVED_NOTIFY" "$NOTIFY"
fi

# Install the notifier samples when they are reachable from this script.
# npx puts a symlink in node_modules/.bin, so resolve that first.
SCRIPT_SRC="${BASH_SOURCE[0]}"
if [[ -L "$SCRIPT_SRC" ]]; then
    SCRIPT_SRC="$(readlink -f "$SCRIPT_SRC" 2>/dev/null || readlink "$SCRIPT_SRC")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SRC")" && pwd)"

if compgen -G "$SCRIPT_DIR/notify/*.sample" >/dev/null; then
    mkdir -p "$BASE/notify"
    cp -p "$SCRIPT_DIR/notify"/*.sample "$BASE/notify/"
fi

CURRENT_STATUS_COMMAND="$(jq -r '.statusLine.command // empty' "$SETTINGS")"

# A statusLine already in settings.json wins over anything saved earlier
if [[ -n "$CURRENT_STATUS_COMMAND" ]]; then
    printf '%s\n' "$CURRENT_STATUS_COMMAND" > "$ORIG"
elif [[ -n "$PRESERVED_ORIG" && -s "$PRESERVED_ORIG" ]]; then
    # Carry a saved statusLine over as the wrapped command, not back into settings
    cp -p "$PRESERVED_ORIG" "$ORIG"
fi

cat > "$BIN" <<'CLAUDE_PLUS'
#!/usr/bin/env bash
# Claude Plus - enhancements for Claude Code
# Copyright (C) 2026 Jason Zhou
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. See the LICENSE file for details.
set -u

VERSION="2.2.1"

BASE="$HOME/.claude/claude-plus"
STATE="$BASE/state"
PENDING="$STATE/pending"
STALE="$STATE/stale"
ORIG="$BASE/original-statusline-command"
NOTIFY="$BASE/notify.sh"
LOG="$BASE/claude-plus.log"
SELF="$BASE/claude-plus.sh"

mkdir -p "$STATE" "$PENDING" "$STALE"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# Hand the event to whatever notifier the user installed. A broken or slow
# notifier must never take the run down with it.
notify() {
    [[ -x "$NOTIFY" ]] || return 0

    CP_EVENT="$1" CP_MESSAGE="$2" CP_HOST="$(uname -n)" \
        timeout 20 "$NOTIFY" >/dev/null 2>&1 ||
        log "Notify script failed event=$1"
}

# Notify on the way into a state, not on every retry inside it
notify_once() {
    local flag="$STATE/notified-$1"

    [[ -e "$flag" ]] && return 0
    : > "$flag"

    notify "$2" "$3"
}

# Announce the recovery only to those who heard about the problem
notify_recovered() {
    local key flag cleared=0

    for key in auth failing; do
        flag="$STATE/notified-$key"

        if [[ -e "$flag" ]]; then
            rm -f "$flag"
            cleared=1
        fi
    done

    if (( cleared == 1 )); then
        notify "recovered" "Claude Plus is back to normal; warmups are succeeding again."
    fi
}

job_exists() {
    local job_id="${1:-}"

    [[ -n "$job_id" ]] || return 1

    atq 2>/dev/null |
        awk '{print $1}' |
        grep -qx "$job_id"
}

arm_job() {
    local target="$1"
    local reason="${2:-unknown}"

    exec 9>"$STATE/schedule.lock"
    flock 9

    local now old_job old_target
    now="$(date +%s)"
    old_job="$(cat "$STATE/at_job" 2>/dev/null || true)"
    old_target="$(cat "$STATE/at_target" 2>/dev/null || true)"

    # A target in the past would never fire; push it a few seconds out
    if (( target <= now )); then
        target=$((now + 5))
    fi

    # Same target and the job is still queued: nothing to do
    if [[ "$target" == "$old_target" ]] && job_exists "$old_job"; then
        return 0
    fi

    # Drop the job scheduled last time
    if job_exists "$old_job"; then
        atrm "$old_job" >/dev/null 2>&1 || true
    fi

    local timespec output job_id
    timespec="$(date -d "@$target" '+%Y%m%d%H%M.%S')"

    output="$(
        printf '%q scheduled\n' "$SELF" |
            LC_ALL=C at -t "$timespec" 2>&1
    )" || {
        log "Failed to schedule at job: $output"
        return 1
    }

    job_id="$(
        printf '%s\n' "$output" |
            awk '/^job [0-9]+ / {print $2; exit}'
    )"

    if [[ -z "$job_id" ]]; then
        log "Could not determine at job id: $output"
        return 1
    fi

    printf '%s\n' "$job_id" > "$STATE/at_job"
    printf '%s\n' "$target" > "$STATE/at_target"
    printf '%s\n' "$reason" > "$STATE/at_reason"

    log "Scheduled job=$job_id target=$(date -d "@$target" '+%Y-%m-%d %H:%M:%S') reason=$reason"
}

is_weekly_limited() {
    local now seven_reset seven_pct
    now="$(date +%s)"
    seven_reset="$(cat "$STATE/seven_day_reset" 2>/dev/null || true)"
    seven_pct="$(cat "$STATE/seven_day_pct" 2>/dev/null || true)"

    [[ "$seven_reset" =~ ^[0-9]+$ ]] || return 1
    [[ -n "$seven_pct" ]] || return 1
    (( seven_reset > now )) || return 1

    awk -v p="$seven_pct" 'BEGIN { exit !(p >= 99.9) }'
}

observe() {
    local input
    input="$(cat)"

    local five_reset five_pct seven_reset seven_pct
    five_reset="$(
        printf '%s' "$input" |
            jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null
    )"
    five_pct="$(
        printf '%s' "$input" |
            jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null
    )"
    seven_reset="$(
        printf '%s' "$input" |
            jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null
    )"
    seven_pct="$(
        printf '%s' "$input" |
            jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null
    )"

    if [[ "$seven_reset" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$seven_reset" > "$STATE/seven_day_reset"
    fi

    if [[ -n "$seven_pct" ]]; then
        printf '%s\n' "$seven_pct" > "$STATE/seven_day_pct"
    fi

    if [[ "$five_reset" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$five_reset" > "$STATE/five_hour_reset"

        if [[ -n "$five_pct" ]]; then
            printf '%s\n' "$five_pct" > "$STATE/five_hour_pct"
        fi

        # Trust the official reset time, plus 15s of slack
        arm_job "$((five_reset + 15))" "official-five-hour-reset"
    fi
}

statusline() {
    local input
    input="$(cat)"

    # Feed the reset times into our own state
    printf '%s' "$input" | "$SELF" observe >/dev/null 2>&1 || true

    # With a wrapped command, render exactly what it renders
    if [[ -s "$ORIG" ]]; then
        local original
        original="$(cat "$ORIG")"
        printf '%s' "$input" | bash -c "$original"
        return
    fi

    # Only fall back to a minimal line when nothing is wrapped
    local pct reset
    pct="$(
        printf '%s' "$input" |
            jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null
    )"
    reset="$(
        printf '%s' "$input" |
            jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null
    )"

    if [[ "$reset" =~ ^[0-9]+$ ]]; then
        printf '5h %s%% | reset %s\n' \
            "${pct:-?}" \
            "$(date -d "@$reset" '+%H:%M')"
    fi
}

pending_path() {
    local session_id="$1"
    local safe
    safe="$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9._-' '_')"
    printf '%s/%s.json\n' "$PENDING" "$safe"
}

remove_pending() {
    local session_id="$1"
    local file
    [[ -n "$session_id" ]] || return 0
    file="$(pending_path "$session_id")"
    rm -f "$file"
}

rate_limit() {
    local input
    input="$(cat)"

    local session_id cwd transcript now
    session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
    transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
    now="$(date +%s)"

    if [[ -z "$session_id" ]]; then
        log "StopFailure(rate_limit) received without session_id"
        return 0
    fi

    # Outside tmux there is no pane to type into, so only record it
    if [[ -z "${TMUX:-}" || -z "${TMUX_PANE:-}" ]]; then
        log "Rate limit detected session=$session_id but session is not running in tmux"
        return 0
    fi

    local socket pane tmux_session window_index pane_index pane_command pane_pid
    socket="${TMUX%%,*}"
    pane="$TMUX_PANE"

    tmux_session="$(tmux -S "$socket" display-message -p -t "$pane" '#S' 2>/dev/null || true)"
    window_index="$(tmux -S "$socket" display-message -p -t "$pane" '#I' 2>/dev/null || true)"
    pane_index="$(tmux -S "$socket" display-message -p -t "$pane" '#P' 2>/dev/null || true)"
    pane_command="$(tmux -S "$socket" display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null || true)"
    pane_pid="$(tmux -S "$socket" display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null || true)"

    if [[ -z "$tmux_session" ]]; then
        log "Rate limit detected session=$session_id but tmux pane could not be resolved"
        return 0
    fi

    local five_reset seven_reset seven_pct file tmp
    five_reset="$(cat "$STATE/five_hour_reset" 2>/dev/null || true)"
    seven_reset="$(cat "$STATE/seven_day_reset" 2>/dev/null || true)"
    seven_pct="$(cat "$STATE/seven_day_pct" 2>/dev/null || true)"
    file="$(pending_path "$session_id")"
    tmp="$file.tmp.$$"

    jq -n \
        --arg session_id "$session_id" \
        --arg cwd "$cwd" \
        --arg transcript_path "$transcript" \
        --arg socket "$socket" \
        --arg pane "$pane" \
        --arg tmux_session "$tmux_session" \
        --arg window_index "$window_index" \
        --arg pane_index "$pane_index" \
        --arg pane_command "$pane_command" \
        --arg pane_pid "$pane_pid" \
        --arg five_reset "$five_reset" \
        --argjson hit_at "$now" \
        '{
            session_id: $session_id,
            cwd: $cwd,
            transcript_path: $transcript_path,
            tmux_socket: $socket,
            tmux_pane: $pane,
            tmux_session: $tmux_session,
            window_index: $window_index,
            pane_index: $pane_index,
            pane_command: $pane_command,
            pane_pid: $pane_pid,
            five_hour_reset: $five_reset,
            hit_at: $hit_at,
            resume_attempts: 0
        }' > "$tmp"

    mv "$tmp" "$file"

    log "Rate limit detected session=$session_id tmux=$tmux_session pane=$pane command=$pane_command"

    # A weekly limit outranks the five-hour one
    if [[ "$seven_reset" =~ ^[0-9]+$ ]] &&
       [[ -n "$seven_pct" ]] &&
       awk -v p="$seven_pct" 'BEGIN { exit !(p >= 99.9) }' &&
       (( seven_reset > now )); then
        arm_job "$((seven_reset + 15))" "seven-day-reset"
        return 0
    fi

    # Schedule the resume for the known reset time
    if [[ "$five_reset" =~ ^[0-9]+$ ]] && (( five_reset > now )); then
        arm_job "$((five_reset + 15))" "pending-rate-limit"
    else
        # Without a known reset, retry soon rather than breaking the chain
        arm_job "$((now + 60))" "pending-reset-unknown"
    fi
}

prompt_submit() {
    local input session_id
    input="$(cat)"
    session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"

    if [[ -n "$session_id" ]]; then
        remove_pending "$session_id"
        log "Pending state cleared by UserPromptSubmit session=$session_id"
    fi
}

session_end() {
    local input session_id
    input="$(cat)"
    session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"

    if [[ -n "$session_id" ]]; then
        remove_pending "$session_id"
        log "Pending state cleared by SessionEnd session=$session_id"
    fi
}

archive_stale() {
    local file="$1"
    local reason="$2"
    local dest
    dest="$STALE/$(basename "$file").$(date +%s)"
    mv "$file" "$dest" 2>/dev/null || true
    log "Pending session archived as stale file=$(basename "$file") reason=$reason"
}

resume_pending() {
    local sent=0
    local file

    shopt -s nullglob

    for file in "$PENDING"/*.json; do
        local session_id socket pane expected_session expected_command attempts
        local current_session current_command tmp

        session_id="$(jq -r '.session_id // empty' "$file" 2>/dev/null)"
        socket="$(jq -r '.tmux_socket // empty' "$file" 2>/dev/null)"
        pane="$(jq -r '.tmux_pane // empty' "$file" 2>/dev/null)"
        expected_session="$(jq -r '.tmux_session // empty' "$file" 2>/dev/null)"
        expected_command="$(jq -r '.pane_command // empty' "$file" 2>/dev/null)"
        attempts="$(jq -r '.resume_attempts // 0' "$file" 2>/dev/null)"

        [[ "$attempts" =~ ^[0-9]+$ ]] || attempts=0

        # Give up after two unanswered attempts
        if (( attempts >= 2 )); then
            continue
        fi

        if [[ -z "$session_id" || -z "$socket" || -z "$pane" ]]; then
            archive_stale "$file" "missing-tmux-metadata"
            continue
        fi

        current_session="$(
            tmux -S "$socket" display-message -p -t "$pane" '#S' 2>/dev/null ||
                true
        )"

        if [[ -z "$current_session" ]]; then
            archive_stale "$file" "tmux-pane-not-found"
            continue
        fi

        if [[ "$current_session" != "$expected_session" ]]; then
            archive_stale "$file" "tmux-session-changed"
            continue
        fi

        current_command="$(
            tmux -S "$socket" display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null ||
                true
        )"

        # The pane may have gone back to a shell; never type into that
        if [[ -n "$expected_command" &&
              -n "$current_command" &&
              "$current_command" != "$expected_command" ]]; then
            archive_stale "$file" "pane-command-changed:$expected_command->$current_command"
            continue
        fi

        # Count the attempt before sending, so UserPromptSubmit cannot race us
        tmp="$file.tmp.$$"
        jq \
            --argjson attempts "$((attempts + 1))" \
            --argjson sent_at "$(date +%s)" \
            '.resume_attempts = $attempts | .last_resume_sent_at = $sent_at' \
            "$file" > "$tmp" &&
            mv "$tmp" "$file"

        if tmux -S "$socket" send-keys -t "$pane" -l "continue" 2>/dev/null &&
           tmux -S "$socket" send-keys -t "$pane" Enter 2>/dev/null; then
            sent=$((sent + 1))
            log "Sent continue session=$session_id tmux=$expected_session pane=$pane attempt=$((attempts + 1))"
        else
            log "Failed to send continue session=$session_id tmux=$expected_session pane=$pane"
        fi

        # Spread sends out across sessions
        sleep 1
    done

    shopt -u nullglob

    printf '%s\n' "$sent"
}

do_warmup() {
    exec 8>"$STATE/warmup.lock"

    # Never let two warmups run at once
    if ! flock -n 8; then
        return 0
    fi

    local now seven_reset
    now="$(date +%s)"
    seven_reset="$(cat "$STATE/seven_day_reset" 2>/dev/null || true)"

    if is_weekly_limited; then
        log "Seven-day limit reached; waiting until weekly reset"
        arm_job "$((seven_reset + 15))" "seven-day-reset"
        return 0
    fi

    local started output rc
    started="$(date +%s)"

    set +e
    output="$(
        timeout 180 \
            claude \
            --safe-mode \
            -p \
            --model haiku \
            --tools "" \
            --no-session-persistence \
            --max-turns 1 \
            'Reply only OK.' \
            2>&1
    )"
    rc=$?
    set -e

    if (( rc == 0 )); then
        printf '%s\n' "$started" > "$STATE/last_success"
        printf '0\n' > "$STATE/failure_count"
        rm -f "$STATE/auth_required"
        notify_recovered

        log "Warmup succeeded output=$(printf '%s' "$output" | tr '\n' ' ' | cut -c1-200)"

        # safe-mode runs no statusLine, so estimate the next window from this request
        arm_job "$((started + 5 * 3600 + 15))" "estimated-next-reset"
        return 0
    fi

    if printf '%s\n' "$output" |
        grep -Eqi 'login expired|please run /login|authentication_failed|not logged in|oauth[^[:alnum:]]+.*expired'; then
        printf '%s\n' "$(date +%s)" > "$STATE/auth_required"
        log "Authentication required; automatic warmup paused output=$(printf '%s' "$output" | tr '\n' ' ' | cut -c1-300)"

        notify_once auth "auth-required" \
            "Claude Code is no longer authenticated, so Claude Plus has stopped opening windows. Sign in again with: claude /login"

        # Leave room to recover on its own if the failure was temporary
        arm_job "$((now + 3600))" "auth-recheck"
        return 1
    fi

    local failures delay
    failures="$(cat "$STATE/failure_count" 2>/dev/null || printf '0')"
    [[ "$failures" =~ ^[0-9]+$ ]] || failures=0

    failures=$((failures + 1))
    printf '%s\n' "$failures" > "$STATE/failure_count"

    case "$failures" in
        1) delay=60 ;;
        2) delay=120 ;;
        3) delay=300 ;;
        *) delay=600 ;;
    esac

    log "Warmup failed rc=$rc retry=${delay}s output=$(printf '%s' "$output" | tr '\n' ' ' | cut -c1-300)"

    # Three failures means the backoff has stretched to minutes; worth a word
    if (( failures >= 3 )); then
        notify_once failing "warmup-failing" \
            "Claude Plus has failed $failures warmups in a row and is retrying every ${delay}s. See ~/.claude/claude-plus/claude-plus.log"
    fi

    arm_job "$((now + delay))" "warmup-retry"
    return 1
}

scheduled() {
    local now seven_reset sent
    now="$(date +%s)"
    seven_reset="$(cat "$STATE/seven_day_reset" 2>/dev/null || true)"

    if is_weekly_limited; then
        log "Scheduled run postponed because seven-day limit is active"
        arm_job "$((seven_reset + 15))" "seven-day-reset"
        return 0
    fi

    # Real work that stopped on a limit comes before any warmup
    sent="$(resume_pending)"

    if [[ "$sent" =~ ^[0-9]+$ ]] && (( sent > 0 )); then
        # Give UserPromptSubmit and the next statusLine refresh time to land
        arm_job "$((now + 90))" "resume-verification"
        return 0
    fi

    # Nothing to resume, or two attempts went unanswered
    do_warmup || true
}

show_status() {
    local five_reset at_target at_job last_success reason failures pending_count auth_status

    five_reset="$(cat "$STATE/five_hour_reset" 2>/dev/null || true)"
    at_target="$(cat "$STATE/at_target" 2>/dev/null || true)"
    at_job="$(cat "$STATE/at_job" 2>/dev/null || true)"
    last_success="$(cat "$STATE/last_success" 2>/dev/null || true)"
    reason="$(cat "$STATE/at_reason" 2>/dev/null || true)"
    failures="$(cat "$STATE/failure_count" 2>/dev/null || printf '0')"
    pending_count="$(find "$PENDING" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"

    if [[ -f "$STATE/auth_required" ]]; then
        auth_status="RELOGIN MAY BE REQUIRED"
    else
        auth_status="OK"
    fi

    echo "Version         : $VERSION"

    if [[ "$five_reset" =~ ^[0-9]+$ ]]; then
        echo "Official reset  : $(date -d "@$five_reset" '+%Y-%m-%d %H:%M:%S')"
    else
        echo "Official reset  : unknown"
    fi

    if [[ "$at_target" =~ ^[0-9]+$ ]]; then
        echo "Scheduled       : $(date -d "@$at_target" '+%Y-%m-%d %H:%M:%S')"
    else
        echo "Scheduled       : none"
    fi

    echo "at job          : ${at_job:-none}"
    echo "Reason          : ${reason:-none}"
    echo "Pending         : $pending_count"
    echo "Failures        : $failures"
    echo "Auth status     : $auth_status"

    if [[ -x "$NOTIFY" ]]; then
        echo "Notify          : $NOTIFY"
    else
        echo "Notify          : not configured"
    fi

    if [[ "$last_success" =~ ^[0-9]+$ ]]; then
        echo "Last warmup     : $(date -d "@$last_success" '+%Y-%m-%d %H:%M:%S')"
    else
        echo "Last warmup     : none"
    fi
}

notify_test() {
    if [[ ! -x "$NOTIFY" ]]; then
        echo "No executable notify script at $NOTIFY" >&2
        echo "Copy one of $BASE/notify/*.sample there and edit it." >&2
        return 1
    fi

    # Run it in the open so the user sees why it failed
    CP_EVENT="test" \
    CP_MESSAGE="Test notification from Claude Plus." \
    CP_HOST="$(uname -n)" \
        "$NOTIFY"

    local rc=$?
    echo "Notify script exited with $rc"
    return "$rc"
}

show_pending() {
    local file found=0

    shopt -s nullglob

    for file in "$PENDING"/*.json; do
        found=1

        jq -r '
            "session        : \(.session_id // "-")",
            "tmux session   : \(.tmux_session // "-")",
            "tmux pane      : \(.tmux_pane // "-")",
            "cwd            : \(.cwd // "-")",
            "pane command   : \(.pane_command // "-")",
            "resume attempts: \(.resume_attempts // 0)",
            "hit at (epoch) : \(.hit_at // "-")",
            ""
        ' "$file"
    done

    shopt -u nullglob

    if (( found == 0 )); then
        echo "No pending sessions."
    fi
}

case "${1:-}" in
    statusline)
        statusline
        ;;
    observe)
        observe
        ;;
    rate-limit)
        rate_limit
        ;;
    prompt-submit)
        prompt_submit
        ;;
    session-end)
        session_end
        ;;
    warmup)
        do_warmup
        ;;
    scheduled)
        scheduled
        ;;
    status)
        show_status
        ;;
    pending)
        show_pending
        ;;
    notify-test)
        notify_test
        ;;
    version)
        echo "$VERSION"
        ;;
    *)
        echo "Usage: $0 {statusline|observe|rate-limit|prompt-submit|session-end|warmup|scheduled|status|pending|notify-test|version}" >&2
        exit 2
        ;;
esac
CLAUDE_PLUS

chmod +x "$BIN"

# Make sure the script just generated parses
bash -n "$BIN"

TMP_SETTINGS="$(mktemp)"

jq \
    --arg marker "$MARKER" \
    --arg status_cmd "$BIN statusline" \
    --arg rate_cmd "$BIN rate-limit" \
    --arg prompt_cmd "$BIN prompt-submit" \
    --arg end_cmd "$BIN session-end" \
    '
    def clean_wk:
        map(
            .hooks = (
                (.hooks // [])
                | map(select(((.command // "") | contains($marker)) | not))
            )
        )
        | map(select((.hooks | length) > 0));

    .statusLine = (
        (.statusLine // {})
        + {
            "type": "command",
            "command": $status_cmd
        }
    )
    |
    .hooks = (.hooks // {})
    |
    .hooks.StopFailure = (
        ((.hooks.StopFailure // []) | clean_wk)
        + [
            {
                "matcher": "rate_limit",
                "hooks": [
                    {
                        "type": "command",
                        "command": $rate_cmd
                    }
                ]
            }
        ]
    )
    |
    .hooks.UserPromptSubmit = (
        ((.hooks.UserPromptSubmit // []) | clean_wk)
        + [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": $prompt_cmd
                    }
                ]
            }
        ]
    )
    |
    .hooks.SessionEnd = (
        ((.hooks.SessionEnd // []) | clean_wk)
        + [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": $end_cmd
                    }
                ]
            }
        ]
    )
    ' \
    "$SETTINGS" > "$TMP_SETTINGS"

jq empty "$TMP_SETTINGS"
mv "$TMP_SETTINGS" "$SETTINGS"

echo
echo "Claude Plus installed."
echo "Settings backup : $SETTINGS_BACKUP"
echo "Main script     : $BIN"
echo
echo "Check:"
echo "  $BIN status"
echo "  $BIN pending"
echo
echo "Inside Claude Code, check /hooks for StopFailure(rate_limit), UserPromptSubmit and SessionEnd."

