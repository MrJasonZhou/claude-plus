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
BIN="$BASE/claude-plus.sh"
ORIG="$BASE/original-statusline-command"
NOTIFY="$BASE/notify.sh"
SETTINGS="$HOME/.claude/settings.json"
MARKER="/claude-plus/claude-plus.sh"

usage() {
    cat >&2 <<USAGE
Usage: $(basename "$0") [install|uninstall]

  install     Install or upgrade Claude Plus (the default)
  uninstall   Remove Claude Plus and leave the rest of settings.json alone
USAGE
}

require() {
    local cmd

    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Required command not found: $cmd" >&2
            exit 1
        fi
    done
}

# The one definition of "what Claude Plus added to settings.json", used by
# both upgrade and uninstall so the two can never disagree.
#
# It works on the current file rather than restoring a backup, because the
# user and other tools may have changed settings.json since we installed.
# The statusLine wrapper turns back into the user's own command (or goes away
# if there was none), hooks that run our script are dropped, and a hook group
# or event is only removed when taking ours out left it empty. Everything
# else passes through untouched.
STRIP_FILTER='
def ours: type == "string" and contains($marker);

def has_ours_group:
    type == "object" and (.hooks | type) == "array" and any(.hooks[]; .command | ours);

def has_ours_event:
    type == "array" and any(.[]; has_ours_group);

if (.statusLine | type) == "object" and (.statusLine.command | ours) then
    # Never restore a command that is itself our wrapper, or it would call itself
    if $orig != "" and ($orig | ours | not) then
        .statusLine.command = $orig
    else
        del(.statusLine)
    end
else
    .
end
|
if (.hooks | type) == "object" and any(.hooks[]; has_ours_event) then
    .hooks |= with_entries(
        if (.value | has_ours_event) then
            .value |= map(
                if has_ours_group then
                    .hooks |= map(select((.command | ours) | not))
                    | if (.hooks | length) == 0 then empty else . end
                else
                    .
                end
            )
            | if (.value | length) == 0 then empty else . end
        else
            .
        end
    )
    | if (.hooks | length) == 0 then del(.hooks) else . end
else
    .
end
'

is_installed() {
    [[ -e "$BASE" ]] && return 0

    [[ -f "$SETTINGS" ]] &&
        jq -e --arg marker "$MARKER" --arg orig "" ". as \$in | ($STRIP_FILTER) != \$in" "$SETTINGS" >/dev/null 2>&1
}

status_command() {
    [[ -f "$SETTINGS" ]] || return 0
    jq -r 'if (.statusLine | type) == "object" then .statusLine.command // empty else empty end' "$SETTINGS"
}

# What uninstall leaves at our script's path when another program still calls
# it: a stand-in that only renders the status line we used to wrap.
write_passthrough() {
    local dest="$1" tmp

    tmp="$(mktemp "$BASE/.passthrough.XXXXXX")"

    {
        echo '#!/usr/bin/env bash'
        echo '# Claude Plus was uninstalled, but another program had wrapped the status'
        echo '# line around it and still calls this path. This pass-through keeps that'
        echo '# chain working by rendering the command Claude Plus used to wrap. Run the'
        echo '# uninstaller again once nothing calls it, and it goes away for good.'

        # Same loop guard as the real script
        echo '[[ -z "${CLAUDE_PLUS_IN_STATUSLINE:-}" ]] || exit 0'
        echo 'export CLAUDE_PLUS_IN_STATUSLINE=1'
        printf 'orig=%q\n' "$ORIG"
        echo 'if [[ "${1:-}" == statusline && -s "$orig" ]]; then'
        echo '    exec bash -c "$(cat "$orig")"'
        echo 'fi'
    } > "$tmp"

    chmod +x "$tmp"

    # Rename over the old file so a copy that is running right now keeps its inode
    mv "$tmp" "$dest"
}

PROBE_INPUT='{"hook_event_name":"Status","session_id":"claude-plus-probe","transcript_path":"/dev/null","cwd":"/tmp","model":{"id":"claude","display_name":"Claude"},"workspace":{"current_dir":"/tmp","project_dir":"/tmp"},"version":"0","output_style":{"name":"default"}}'

# Does this status line command end up running our script?
#
# settings.json alone cannot tell "another program wrapped us" from "another
# program replaced us", and guessing wrong is costly both ways: remove our
# script from under a wrapper and its status line breaks; wrap a wrapper that
# calls us and the two call each other on every refresh. So ask directly:
# swap our script for a probe, run the command once, and swap it back.
#
# Hooks and scheduled runs keep calling our script while the probe is in
# place. So the probe counts only a statusline call as a hit, and hands every
# call, that one included, on to the real script: nothing is swallowed, and a
# hook firing meanwhile cannot pass for a wrapper. The real script goes back
# however this ends, including HUP (an SSH session dropping mid-install) and
# TERM, which would otherwise leave the probe in place for good.
PROBE_DIR=""
PROBE_SAVED=""

restore_probed_bin() {
    if [[ -n "$PROBE_SAVED" && -f "$PROBE_SAVED" ]]; then
        mv -f "$PROBE_SAVED" "$BIN"
    fi

    if [[ -n "$PROBE_DIR" ]]; then
        rm -rf "$PROBE_DIR"
    fi

    # A probe interrupted before it was renamed into place
    rm -f "$BASE"/.probe.*

    PROBE_SAVED=""
    PROBE_DIR=""
}

write_probe() {
    local tmp

    tmp="$(mktemp "$BASE/.probe.XXXXXX")"

    {
        echo '#!/usr/bin/env bash'
        echo '# Temporary: Claude Plus is checking whether another status line program'
        echo '# calls it. See chain_calls_us() in the installer.'
        echo 'if [[ "${1:-}" == statusline ]]; then'
        printf '    : > %q\n' "$PROBE_DIR/called"
        echo 'fi'
        # The real script may be moved back while this starts; then use it there
        echo 'shopt -s execfail'
        printf 'exec %q "$@"\n' "$PROBE_SAVED"
        printf 'exec %q "$@"\n' "$BIN"
    } > "$tmp"

    chmod +x "$tmp"
    mv "$tmp" "$BIN"
}

chain_calls_us() {
    local cmd="$1" rc=1 saved_traps

    [[ -n "$cmd" && "$cmd" != *"$MARKER"* && -f "$BIN" ]] || return 1

    # Traps first, so nothing below can be left behind. Nothing else in the
    # installer sets these today; whatever is set comes back afterwards.
    saved_traps="$(trap -p EXIT HUP INT TERM)"
    trap restore_probed_bin EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    PROBE_DIR="$(mktemp -d)"
    PROBE_SAVED="$(mktemp "$BASE/.saved.XXXXXX")"
    cp -p "$BIN" "$PROBE_SAVED"

    write_probe
    printf '%s' "$PROBE_INPUT" | timeout 10 bash -c "$cmd" >/dev/null 2>&1 || true

    if [[ -e "$PROBE_DIR/called" ]]; then
        rc=0
    fi

    restore_probed_bin
    trap - EXIT HUP INT TERM
    eval "$saved_traps"

    return "$rc"
}

# Take Claude Plus off this machine: our entries in the current settings.json,
# our at jobs, and our directory. Each step touches only what is ours and does
# nothing when that part is already gone, so this is safe to run again, and
# safe to run on an installation that is only half there.
#
# Settings and at jobs are always cleared. Files are where upgrade and
# uninstall part ways: names passed as arguments survive inside
# ~/.claude/claude-plus, and with none the whole directory goes. Uninstall
# keeps nothing (or only what a pass-through needs); upgrade keeps the runtime
# state and the user's notifier, then schedules the next run again itself.
remove_installation() {
    local keep=("$@")

    if [[ -f "$SETTINGS" ]]; then
        local orig="" tmp

        if [[ -s "$ORIG" ]]; then
            orig="$(cat "$ORIG")"
        fi

        tmp="$(mktemp)"
        jq --arg marker "$MARKER" --arg orig "$orig" "$STRIP_FILTER" "$SETTINGS" > "$tmp"

        # Rewrite only when there was something of ours to take out
        if cmp -s <(jq -S . "$SETTINGS") <(jq -S . "$tmp"); then
            rm -f "$tmp"
        else
            mv "$tmp" "$SETTINGS"
        fi
    fi

    if command -v atq >/dev/null 2>&1; then
        local job_id

        while read -r job_id _; do
            [[ -n "$job_id" ]] || continue

            # Read the job from a file descriptor, not a pipe: grep -q quitting
            # early would SIGPIPE `at` and pipefail would call the match a miss
            if grep -Fq "$MARKER" < <(at -c "$job_id" 2>/dev/null); then
                atrm "$job_id" >/dev/null 2>&1 || true
            fi
        done < <(atq 2>/dev/null || true)
    fi

    if (( ${#keep[@]} == 0 )); then
        rm -rf "$BASE"
    elif [[ -d "$BASE" ]]; then
        local name spare=()

        for name in "${keep[@]}"; do
            spare+=(! -name "$name")
        done

        find "$BASE" -mindepth 1 -maxdepth 1 "${spare[@]}" -exec rm -rf {} +
    fi
}

ACTION="${1:-install}"

case "$ACTION" in
    install|uninstall)
        ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        usage
        exit 2
        ;;
esac

require jq

# Refuse to touch a settings.json that is not valid JSON
if [[ -f "$SETTINGS" ]] && ! jq empty "$SETTINGS" 2>/dev/null; then
    echo "$SETTINGS is not valid JSON. Fix it first; Claude Plus will not edit it." >&2
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ "$ACTION" == "uninstall" ]]; then
    if ! is_installed; then
        # Sweep anyway: an interrupted removal can leave an at job behind
        remove_installation
        echo "Claude Plus is not installed; nothing to remove."
        exit 0
    fi

    CURRENT_STATUS_COMMAND="$(status_command)"
    KEEP_CHAIN=0
    if chain_calls_us "$CURRENT_STATUS_COMMAND"; then
        KEEP_CHAIN=1
    fi

    SETTINGS_BACKUP=""
    if [[ -f "$SETTINGS" ]]; then
        SETTINGS_BACKUP="$SETTINGS.claude-plus-uninstall-backup.$STAMP"
        cp -p "$SETTINGS" "$SETTINGS_BACKUP"
    fi

    if (( KEEP_CHAIN )); then
        # Leave the path the other program calls, rendering what we used to wrap
        remove_installation "$(basename "$ORIG")"
        write_passthrough "$BIN"
    else
        remove_installation
    fi

    echo "Claude Plus uninstalled."
    if [[ -n "$SETTINGS_BACKUP" ]]; then
        echo "settings.json was edited in place. Its state just before: $SETTINGS_BACKUP"
    fi

    if (( KEEP_CHAIN )); then
        echo
        echo "Your status line belongs to another program, which still calls Claude Plus:"
        echo "  $CURRENT_STATUS_COMMAND"
        echo "A pass-through was left at $BIN so it keeps working."
        echo "Once that program stops calling it, run uninstall again to remove it."
    fi
    exit 0
fi

require claude at atq atrm flock date timeout

mkdir -p "$HOME/.claude"

# Start from an empty object when there is no settings.json yet
if [[ ! -f "$SETTINGS" ]]; then
    printf '{}\n' > "$SETTINGS"
fi

SETTINGS_BACKUP="$SETTINGS.claude-plus-install-backup.$STAMP"
cp -p "$SETTINGS" "$SETTINGS_BACKUP"

# If another program has wrapped the status line around ours, stay inside
# that chain: keep what we render and do not wrap the wrapper
KEEP_CHAIN=0
if chain_calls_us "$(status_command)"; then
    KEEP_CHAIN=1
fi

if is_installed; then
    echo "Existing installation detected. Removing it first..."
fi

# Upgrade clears settings and at jobs exactly as uninstall does, but keeps
# what is still running (reset times, failure and notification state), the
# user's notifier (it holds their credentials) and the log
KEEP=("$(basename "$STATE")" "$(basename "$NOTIFY")" "claude-plus.log")
if (( KEEP_CHAIN )); then
    KEEP+=("$(basename "$ORIG")")
fi
remove_installation "${KEEP[@]}"

# Versions before 3.0.0 resumed rate-limited sessions themselves. Claude Code
# now does that on its own, so their queue of sessions has no reader.
rm -rf "$STATE/pending" "$STATE/stale"

mkdir -p "$BASE" "$STATE"

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

# Removal has already turned any old wrapper of ours back into the user's own
# command, so whatever statusLine is there now is the one to wrap. Inside
# another program's chain, removal kept the command we render instead.
if (( KEEP_CHAIN == 0 )); then
    CURRENT_STATUS_COMMAND="$(status_command)"

    if [[ -n "$CURRENT_STATUS_COMMAND" && "$CURRENT_STATUS_COMMAND" != *"$MARKER"* ]]; then
        printf '%s\n' "$CURRENT_STATUS_COMMAND" > "$ORIG"
    fi
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

VERSION="3.0.0"

BASE="$HOME/.claude/claude-plus"
STATE="$BASE/state"
ORIG="$BASE/original-statusline-command"
NOTIFY="$BASE/notify.sh"
LOG="$BASE/claude-plus.log"
SELF="$BASE/claude-plus.sh"

mkdir -p "$STATE"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# Hand the event to whatever notifier the user installed. Succeeds only when
# the message actually went out: no notifier configured counts as not sent,
# so the event is still delivered once one is set up. A broken or slow
# notifier only fails this call; it never takes the run down with it.
notify() {
    [[ -x "$NOTIFY" ]] || return 1

    if CP_EVENT="$1" CP_MESSAGE="$2" CP_HOST="$(uname -n)" \
        timeout 20 "$NOTIFY" >/dev/null 2>&1; then
        return 0
    fi

    log "Notify script failed event=$1"
    return 1
}

# Notify once per stay in a state, where once means delivered once. The flag
# is written only after a successful send, so a send that failed is tried
# again on the next retry rather than counted as done.
notify_once() {
    local flag="$STATE/notified-$1"

    [[ -e "$flag" ]] && return 0

    if notify "$2" "$3"; then
        : > "$flag"
    fi
    return 0
}

# Announce a recovery only to those who heard about the problem: $1 is the
# message, the rest are the notify_once keys it clears. Their flags stay until
# the announcement is delivered, so it is retried too.
notify_recovered() {
    local message="$1" key flags=()
    shift

    for key in "$@"; do
        if [[ -e "$STATE/notified-$key" ]]; then
            flags+=("$STATE/notified-$key")
        fi
    done

    (( ${#flags[@]} )) || return 0

    if notify "recovered" "$message"; then
        rm -f "${flags[@]}"
    fi
    return 0
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

# Is atd running? 0 yes, 1 no, 2 cannot tell. systemd first, then the process
# itself, for systems without systemd (WSL, containers) or an atd started by hand.
scheduler_running() {
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet atd 2>/dev/null; then
        return 0
    fi

    if command -v pgrep >/dev/null 2>&1; then
        pgrep -x atd >/dev/null 2>&1 && return 0
        return 1
    fi

    return 2
}

STALL_GRACE=300

# A run well past its time and still queued means atd is not running it.
#
# This is called on every status line refresh, which can be every second, so
# the common case must cost nothing: two comparisons, and out. Only when the
# target is overdue and the last look was a while ago does a background check
# run, one at a time, so the status line never waits on atq or a notifier, and
# the log and any notification retry happen at most every STALL_GRACE seconds.
maybe_check_stall() {
    local now target last

    target="$(cat "$STATE/at_target" 2>/dev/null || true)"
    [[ "$target" =~ ^[0-9]+$ ]] || return 0

    now="$(date +%s)"
    (( now > target + STALL_GRACE )) || return 0

    last="$(cat "$STATE/stall_checked_at" 2>/dev/null || true)"
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    (( now >= last + STALL_GRACE )) || return 0

    (
        exec 7>"$STATE/stall.lock"
        flock -n 7 || exit 0
        check_stall "$target"
    ) </dev/null >/dev/null 2>&1 &
}

check_stall() {
    local target="$1" job

    # Another refresh may have looked while this one waited for the lock
    local last
    last="$(cat "$STATE/stall_checked_at" 2>/dev/null || true)"
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    (( $(date +%s) >= last + STALL_GRACE )) || return 0
    date +%s > "$STATE/stall_checked_at"

    job="$(cat "$STATE/at_job" 2>/dev/null || true)"
    job_exists "$job" || return 0

    log "Scheduled run is overdue and still queued: job=$job target=$(date -d "@$target" '+%Y-%m-%d %H:%M:%S')"
    notify_once stalled "scheduler-stalled" \
        "Claude Plus's run scheduled for $(date -d "@$target" '+%H:%M') has not happened, so nothing is being kept or resumed. Is atd running? Start it with: sudo systemctl enable --now atd"
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

    maybe_check_stall
}

statusline() {
    # Two status line programs that each wrap the other would call each other
    # on every refresh; the inner call stops here instead
    if [[ -n "${CLAUDE_PLUS_IN_STATUSLINE:-}" ]]; then
        cat >/dev/null
        return 0
    fi
    export CLAUDE_PLUS_IN_STATUSLINE=1

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

    if (( rc == 0 )); then
        printf '%s\n' "$started" > "$STATE/last_success"
        printf '0\n' > "$STATE/failure_count"
        rm -f "$STATE/auth_required"
        notify_recovered "Claude Plus is back to normal; warmups are succeeding again." auth failing

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

# Put back the run an earlier version had planned, after an upgrade removed
# its at job. The target was computed then; one already missed runs now.
reschedule() {
    local target reason

    target="$(cat "$STATE/at_target" 2>/dev/null || true)"
    reason="$(cat "$STATE/at_reason" 2>/dev/null || true)"

    [[ "$target" =~ ^[0-9]+$ ]] || return 0
    arm_job "$target" "${reason:-rescheduled}"
}

scheduled() {
    # atd ran us, so whatever stall was reported is over
    printf '%s\n' "$(date +%s)" > "$STATE/last_run"
    notify_recovered "Claude Plus's scheduled runs are happening again." stalled

    # do_warmup waits out a weekly limit itself
    do_warmup || true
}

show_status() {
    local five_reset at_target at_job last_success reason failures auth_status
    local last_run scheduler overdue=""

    five_reset="$(cat "$STATE/five_hour_reset" 2>/dev/null || true)"
    at_target="$(cat "$STATE/at_target" 2>/dev/null || true)"
    at_job="$(cat "$STATE/at_job" 2>/dev/null || true)"
    last_success="$(cat "$STATE/last_success" 2>/dev/null || true)"
    last_run="$(cat "$STATE/last_run" 2>/dev/null || true)"
    reason="$(cat "$STATE/at_reason" 2>/dev/null || true)"
    failures="$(cat "$STATE/failure_count" 2>/dev/null || printf '0')"

    if [[ -f "$STATE/auth_required" ]]; then
        auth_status="RELOGIN MAY BE REQUIRED"
    else
        auth_status="OK"
    fi

    scheduler_running
    case $? in
        0) scheduler="atd running" ;;
        1) scheduler="ATD NOT RUNNING - nothing scheduled will run" ;;
        *) scheduler="unknown" ;;
    esac

    echo "Version         : $VERSION"
    echo "Scheduler       : $scheduler"

    if [[ "$five_reset" =~ ^[0-9]+$ ]]; then
        echo "Official reset  : $(date -d "@$five_reset" '+%Y-%m-%d %H:%M:%S')"
    else
        echo "Official reset  : unknown"
    fi

    if [[ "$at_target" =~ ^[0-9]+$ ]]; then
        if (( $(date +%s) > at_target + STALL_GRACE )) && job_exists "$at_job"; then
            overdue=" (OVERDUE, still queued)"
        fi
        echo "Scheduled       : $(date -d "@$at_target" '+%Y-%m-%d %H:%M:%S')$overdue"
    else
        echo "Scheduled       : none"
    fi

    echo "at job          : ${at_job:-none}"
    echo "Reason          : ${reason:-none}"
    echo "Failures        : $failures"
    echo "Auth status     : $auth_status"

    if [[ -x "$NOTIFY" ]]; then
        echo "Notify          : $NOTIFY"
    else
        echo "Notify          : not configured"
    fi

    if [[ "$last_run" =~ ^[0-9]+$ ]]; then
        echo "Last run        : $(date -d "@$last_run" '+%Y-%m-%d %H:%M:%S')"
    else
        echo "Last run        : none"
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

case "${1:-}" in
    statusline)
        statusline
        ;;
    observe)
        observe
        ;;
    warmup)
        do_warmup
        ;;
    scheduled)
        scheduled
        ;;
    reschedule)
        reschedule
        ;;
    scheduler-check)
        scheduler_running
        ;;
    status)
        show_status
        ;;
    notify-test)
        notify_test
        ;;
    version)
        echo "$VERSION"
        ;;
    *)
        echo "Usage: $0 {statusline|observe|warmup|scheduled|reschedule|scheduler-check|status|notify-test|version}" >&2
        exit 2
        ;;
esac
CLAUDE_PLUS

chmod +x "$BIN"

# Make sure the script just generated parses
bash -n "$BIN"

# Removal above has already taken out every entry of ours; the status line
# wrapper is all Claude Plus adds. Inside another program's chain, not even that.
if (( KEEP_CHAIN == 0 )); then
    TMP_SETTINGS="$(mktemp)"

    jq --arg status_cmd "$BIN statusline" '
        .statusLine = (
            (.statusLine // {})
            + {
                "type": "command",
                "command": $status_cmd
            }
        )
    ' "$SETTINGS" > "$TMP_SETTINGS"

    jq empty "$TMP_SETTINGS"
    mv "$TMP_SETTINGS" "$SETTINGS"
fi

# Removal dropped the old at job; put the run the previous version had
# planned back on the new one
if ! "$BIN" reschedule; then
    echo "Warning: could not schedule the next run; it will be set on the next status line refresh." >&2
fi

# `at` accepts jobs whether or not atd runs them, so check the daemon itself
SCHEDULER_RC=0
"$BIN" scheduler-check || SCHEDULER_RC=$?

echo
echo "Claude Plus installed."
if (( SCHEDULER_RC == 1 )); then
    echo "Warning: atd is not running, so nothing Claude Plus schedules will run." >&2
    echo "         Start it with: sudo systemctl enable --now atd" >&2
fi
if (( KEEP_CHAIN )); then
    echo "Your status line belongs to another program that calls Claude Plus; it was left as it is."
fi
echo "Settings backup : $SETTINGS_BACKUP"
echo "Main script     : $BIN"
echo
echo "Check:"
echo "  $BIN status"

