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
PROVIDERS="$BASE/providers"
NOTIFY="$BASE/notify.sh"
ANCHOR="$BASE/anchor"
MARKER="/claude-plus/claude-plus.sh"

# Agents that run a status line command of our choosing, and where each keeps
# its settings. Wrapping one means editing that file, so only agents actually
# installed here are ever touched.
agent_settings() {
    case "$1" in
        claude) printf '%s\n' "$HOME/.claude/settings.json" ;;
        agy)    printf '%s\n' "$HOME/.gemini/antigravity-cli/settings.json" ;;
        *)      return 1 ;;
    esac
}

wrapped_agents() {
    local id
    for id in claude agy; do
        command -v "$id" >/dev/null 2>&1 && printf '%s\n' "$id"
    done
    return 0
}

# The command that agent used to run, saved with its own state
agent_orig() {
    printf '%s\n' "$STATE/$1/original-statusline-command"
}

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

    local id file
    for id in $(wrapped_agents); do
        file="$(agent_settings "$id")" || continue
        [[ -f "$file" ]] || continue
        jq -e --arg marker "$MARKER" --arg orig "" ". as \$in | ($STRIP_FILTER) != \$in" "$file" >/dev/null 2>&1 &&
            return 0
    done

    return 1
}

status_command() {
    [[ -f "$1" ]] || return 0
    jq -r 'if (.statusLine | type) == "object" then .statusLine.command // empty else empty end' "$1"
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
        # The caller names the agent, so the right command is rendered
        printf 'state=%q\n' "$STATE"
        echo 'if [[ "${1:-}" == statusline ]]; then'
        echo '    orig="$state/${2:-claude}/original-statusline-command"'
        echo '    [[ -s "$orig" ]] && exec bash -c "$(cat "$orig")"'
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

    local id file orig tmp

    for id in $(wrapped_agents); do
        file="$(agent_settings "$id")" || continue
        [[ -f "$file" ]] || continue

        orig=""
        [[ -s "$(agent_orig "$id")" ]] && orig="$(cat "$(agent_orig "$id")")"

        tmp="$(mktemp)"
        jq --arg marker "$MARKER" --arg orig "$orig" "$STRIP_FILTER" "$file" > "$tmp"

        # Rewrite only when there was something of ours to take out
        if cmp -s <(jq -S . "$file") <(jq -S . "$tmp"); then
            rm -f "$tmp"
        else
            mv "$tmp" "$file"
        fi
    done

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

# Versions before 4.0.0 handled one agent, keeping its state flat in state/
# and the wrapped command at the top of the directory. Move both into place
# before anything reads them.
migrate_to_providers() {
    local f from to

    [[ -d "$STATE" ]] || return 0
    [[ -e "$STATE/at_target" || -e "$BASE/original-statusline-command" ]] || return 0

    mkdir -p "$STATE/claude"

    for f in at_job at_target at_reason auth_required failure_count last_run \
             last_success notified-auth notified-failing schedule.lock warmup.lock; do
        [[ -e "$STATE/$f" ]] && mv -f "$STATE/$f" "$STATE/claude/$f"
    done

    # The same numbers, under the names the provider interface uses
    while read -r from to; do
        [[ -e "$STATE/$from" ]] && mv -f "$STATE/$from" "$STATE/claude/$to"
    done <<'RENAMES'
five_hour_reset resets_at
five_hour_pct used_percent
seven_day_reset long_resets_at
seven_day_pct long_used_percent
RENAMES

    [[ -e "$BASE/original-statusline-command" ]] &&
        mv -f "$BASE/original-statusline-command" "$STATE/claude/original-statusline-command"

    return 0
}

migrate_to_providers

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

# Refuse to touch settings that are not valid JSON
for _id in $(wrapped_agents); do
    _file="$(agent_settings "$_id")" || continue
    if [[ -f "$_file" ]] && ! jq empty "$_file" 2>/dev/null; then
        echo "$_file is not valid JSON. Fix it first; Claude Plus will not edit it." >&2
        exit 1
    fi
done
unset _id _file

# Agents whose status line another program has wrapped around ours: we stay
# inside those chains rather than wrapping the wrapper. Filled in below.
CHAINED=""

in_chain() {
    [[ " $CHAINED " == *" $1 "* ]]
}

# Probe each agent's current status line, and back its settings up
survey_agents() {
    local suffix="$1" id file cmd
    BACKUPS=""

    for id in $(wrapped_agents); do
        file="$(agent_settings "$id")" || continue
        [[ -f "$file" ]] || continue

        cmd="$(status_command "$file")"
        if chain_calls_us "$cmd"; then
            CHAINED="$CHAINED $id"
            CHAIN_COMMANDS="$CHAIN_COMMANDS$id: $cmd"$'\n'
        fi

        cp -p "$file" "$file.claude-plus-$suffix-backup.$STAMP"
        BACKUPS="$BACKUPS$file.claude-plus-$suffix-backup.$STAMP"$'\n'
    done
}

CHAIN_COMMANDS=""
BACKUPS=""

STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ "$ACTION" == "uninstall" ]]; then
    if ! is_installed; then
        # Sweep anyway: an interrupted removal can leave an at job behind
        remove_installation
        echo "Claude Plus is not installed; nothing to remove."
        exit 0
    fi

    survey_agents uninstall

    # The commands any surviving chain has to keep rendering
    SAVED=""
    for _id in $CHAINED; do
        [[ -s "$(agent_orig "$_id")" ]] &&
            SAVED="$SAVED$_id"$'\t'"$(cat "$(agent_orig "$_id")")"$'\n'
    done

    remove_installation

    if [[ -n "$CHAINED" ]]; then
        while IFS=$'\t' read -r _id _cmd; do
            [[ -n "$_id" ]] || continue
            mkdir -p "$(dirname "$(agent_orig "$_id")")"
            printf '%s\n' "$_cmd" > "$(agent_orig "$_id")"
        done <<< "$SAVED"

        write_passthrough "$BIN"
    fi

    echo "Claude Plus uninstalled."
    if [[ -n "$BACKUPS" ]]; then
        echo "Settings were edited in place. Their state just before:"
        printf '%s' "$BACKUPS" | sed 's/^/  /'
    fi

    if [[ -n "$CHAINED" ]]; then
        echo
        echo "A status line belonging to another program still calls Claude Plus:"
        printf '%s' "$CHAIN_COMMANDS" | sed 's/^/  /'
        echo "A pass-through was left at $BIN so it keeps working."
        echo "Once that program stops calling it, run uninstall again to remove it."
    fi
    exit 0
fi

require at atq atrm flock date timeout

if [[ -z "$(wrapped_agents)" ]] && ! command -v codex >/dev/null 2>&1; then
    echo "None of the agents Claude Plus knows about are installed here." >&2
    echo "Looked for: claude, codex, agy" >&2
    exit 1
fi

mkdir -p "$HOME/.claude"

# Claude Code may not have written its settings yet
if command -v claude >/dev/null 2>&1 && [[ ! -f "$(agent_settings claude)" ]]; then
    printf '{}\n' > "$(agent_settings claude)"
fi

survey_agents install

if is_installed; then
    echo "Existing installation detected. Removing it first..."
fi

# Upgrade clears settings and at jobs exactly as uninstall does, but keeps
# what is still running (reset times, failure and notification state), the
# user's notifier (it holds their credentials), the anchor and the log
# The wrapped commands live under state/, which is kept anyway
KEEP=("$(basename "$STATE")" "$(basename "$NOTIFY")" "$(basename "$ANCHOR")" "claude-plus.log")
remove_installation "${KEEP[@]}"

# Versions before 3.0.0 resumed rate-limited sessions themselves. Claude Code
# now does that on its own, so their queue of sessions has no reader.
rm -rf "$STATE/pending" "$STATE/stale"

mkdir -p "$BASE" "$STATE" "$PROVIDERS"

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
# command, so whatever statusLine each agent has now is the one to wrap.
# Inside another program's chain, removal kept the command we render instead.
for _id in $(wrapped_agents); do
    in_chain "$_id" && continue
    _file="$(agent_settings "$_id")" || continue
    [[ -f "$_file" ]] || continue

    _current="$(status_command "$_file")"
    if [[ -n "$_current" && "$_current" != *"$MARKER"* ]]; then
        mkdir -p "$STATE/$_id"
        printf '%s\n' "$_current" > "$(agent_orig "$_id")"
    fi
done
unset _id _file _current

cat > "$BIN" <<'CLAUDE_PLUS'
#!/usr/bin/env bash
# Claude Plus - enhancements for coding agents
# Copyright (C) 2026 Jason Zhou
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. See the LICENSE file for details.
set -u

VERSION="4.0.0"

BASE="$HOME/.claude/claude-plus"
STATE="$BASE/state"
PROVIDERS="$BASE/providers"
NOTIFY="$BASE/notify.sh"
ANCHOR="$BASE/anchor"
LOG="$BASE/claude-plus.log"
SELF="$BASE/claude-plus.sh"

DEFAULT_WINDOW=18000
STALL_GRACE=300

mkdir -p "$STATE"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# ----------------------------------------------------------------- providers
#
# One file per agent under providers/, each defining functions prefixed with
# its id. See docs/PROVIDERS.md for the contract. Nothing below this section
# knows which agents exist.

for _p in "$PROVIDERS"/*.sh; do
    [[ -e "$_p" ]] && source "$_p"
done
unset _p

provider_ids() {
    local f
    shopt -s nullglob
    for f in "$PROVIDERS"/*.sh; do
        basename "$f" .sh
    done
    shopt -u nullglob
}

provider_defines() {
    declare -F "$1_$2" >/dev/null 2>&1
}

# Call a provider function, falling back to the default where there is one
provider_call() {
    local id="$1" fn="$2"
    shift 2

    if provider_defines "$id" "$fn"; then
        "${id}_${fn}" "$@"
    else
        "default_$fn" "$@"
    fi
}

default_label() {
    printf '%s\n' "unknown"
}

default_capabilities() {
    printf 'alert\n'
}

# Most agents word an expired login much the same way
default_auth_failed() {
    grep -Eqi 'login expired|please run /login|log ?in again|authentication_failed|not logged in|unauthorized|oauth[^[:alnum:]]+.*expired'
}

default_warmup() {
    return 1
}

default_parse_limits() {
    cat >/dev/null
    printf '{}\n'
}

provider_can() {
    provider_call "$1" capabilities 2>/dev/null | tr ' ' '\n' | grep -qx "$2"
}

# Providers the core should act on: installed here, and known to us
active_providers() {
    local id
    for id in $(provider_ids); do
        provider_defines "$id" available || continue
        "${id}_available" 2>/dev/null && printf '%s\n' "$id"
    done
}

pstate() {
    printf '%s\n' "$STATE/$1"
}

pget() {
    cat "$STATE/$1/$2" 2>/dev/null || true
}

pset() {
    mkdir -p "$STATE/$1"
    printf '%s\n' "$3" > "$STATE/$1/$2"
}

# How long a short window lasts for this provider, as last observed
window_seconds() {
    local w
    w="$(pget "$1" window_seconds)"
    [[ "$w" =~ ^[0-9]+$ ]] && printf '%s\n' "$w" || printf '%s\n' "$DEFAULT_WINDOW"
}

# ------------------------------------------------------------------- notify

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
# again on the next retry rather than counted as done. $1 is the directory
# holding the flag, so providers keep their own.
notify_once() {
    local flag="$1/notified-$2"

    [[ -e "$flag" ]] && return 0
    mkdir -p "$1"

    if notify "$3" "$4"; then
        : > "$flag"
    fi
    return 0
}

# Announce a recovery only to those who heard about the problem: $2 is the
# message, the rest are the keys it clears. Their flags stay until the
# announcement is delivered, so it is retried too.
notify_recovered() {
    local dir="$1" message="$2" key flags=()
    shift 2

    for key in "$@"; do
        if [[ -e "$dir/notified-$key" ]]; then
            flags+=("$dir/notified-$key")
        fi
    done

    (( ${#flags[@]} )) || return 0

    if notify "recovered" "$message"; then
        rm -f "${flags[@]}"
    fi
    return 0
}

# --------------------------------------------------------------- at jobs

job_exists() {
    local job_id="${1:-}"

    [[ -n "$job_id" ]] || return 1

    atq 2>/dev/null |
        awk '{print $1}' |
        grep -qx "$job_id"
}

# Schedule `scheduled <id>` at $2, replacing whatever this provider had
arm_job() {
    local id="$1" target="$2" reason="${3:-unknown}"
    local dir
    dir="$(pstate "$id")"
    mkdir -p "$dir"

    exec 9>"$dir/schedule.lock"
    flock 9

    local now old_job old_target
    now="$(date +%s)"
    old_job="$(pget "$id" at_job)"
    old_target="$(pget "$id" at_target)"

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
        printf '%q scheduled %q\n' "$SELF" "$id" |
            LC_ALL=C at -t "$timespec" 2>&1
    )" || {
        log "[$id] Failed to schedule at job: $output"
        return 1
    }

    job_id="$(
        printf '%s\n' "$output" |
            awk '/^job [0-9]+ / {print $2; exit}'
    )"

    if [[ -z "$job_id" ]]; then
        log "[$id] Could not determine at job id: $output"
        return 1
    fi

    pset "$id" at_job "$job_id"
    pset "$id" at_target "$target"
    pset "$id" at_reason "$reason"

    log "[$id] Scheduled job=$job_id target=$(date -d "@$target" '+%Y-%m-%d %H:%M:%S') reason=$reason"
}

# --------------------------------------------------------------- the anchor

# The first time of day $2 (HH:MM) falls at or after the moment $1
anchor_after() {
    local from="$1" anchor="$2" day today

    day="$(date -d "@$from" '+%Y-%m-%d')" || return 1
    today="$(date -d "$day $anchor" +%s 2>/dev/null)" || return 1

    if (( today >= from )); then
        printf '%s\n' "$today"
        return 0
    fi

    # Tomorrow's date, then the time: `date -d "<date> <time> + 1 day"` reads
    # the "+ 1" as a UTC offset instead of a day, which silently shifts the hour
    day="$(date -d "@$((from + 86400))" '+%Y-%m-%d')" || return 1
    date -d "$day $anchor" +%s 2>/dev/null
}

# Hold a window back so that none ever runs across the anchor time.
#
# A window opened at $2 covers the next $1 seconds. If the anchor falls inside
# that stretch, opening at the anchor itself is no longer possible, so wait for
# it instead: a window due at 03:00 would cover 03:00-08:00 and swallow 06:00,
# so it opens at 06:00. Leaves the target alone when no anchor is set, when the
# window starts exactly on it, or when the anchor is beyond its end.
apply_anchor() {
    local window="$1" target="$2" anchor next

    anchor="$(cat "$ANCHOR" 2>/dev/null || true)"

    if [[ ! "$anchor" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] ||
       ! next="$(anchor_after "$target" "$anchor")" ||
       [[ ! "$next" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$target"
        return 0
    fi

    if (( next > target && next < target + window )); then
        printf '%s\n' "$next"
    else
        printf '%s\n' "$target"
    fi
}

# Schedule the opening of a new window, honouring the anchor
arm_window() {
    local id="$1" target="$2" reason="$3" anchored

    anchored="$(apply_anchor "$(window_seconds "$id")" "$target")"

    if (( anchored != target )); then
        log "[$id] Holding the next window until the anchor at $(date -d "@$anchored" '+%H:%M')"
        target="$anchored"
        reason="anchor-hold"
    fi

    arm_job "$id" "$target" "$reason"
}

# ------------------------------------------------------------ the scheduler

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

# A run well past its time and still queued means atd is not running it.
#
# This is called on every status line refresh, which can be every second, so
# the common case must cost nothing: two comparisons, and out. Only when a
# target is overdue and the last look was a while ago does a background check
# run, one at a time, so the status line never waits on atq or a notifier, and
# the log and any notification retry happen at most every STALL_GRACE seconds.
maybe_check_stall() {
    local id="$1" now target last

    target="$(pget "$id" at_target)"
    [[ "$target" =~ ^[0-9]+$ ]] || return 0

    now="$(date +%s)"
    (( now > target + STALL_GRACE )) || return 0

    last="$(cat "$STATE/stall_checked_at" 2>/dev/null || true)"
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    (( now >= last + STALL_GRACE )) || return 0

    (
        exec 7>"$STATE/stall.lock"
        flock -n 7 || exit 0
        check_stall "$id" "$target"
    ) </dev/null >/dev/null 2>&1 &
}

check_stall() {
    local id="$1" target="$2" job last

    # Another refresh may have looked while this one waited for the lock
    last="$(cat "$STATE/stall_checked_at" 2>/dev/null || true)"
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    (( $(date +%s) >= last + STALL_GRACE )) || return 0
    date +%s > "$STATE/stall_checked_at"

    job="$(pget "$id" at_job)"
    job_exists "$job" || return 0

    log "[$id] Scheduled run is overdue and still queued: job=$job target=$(date -d "@$target" '+%Y-%m-%d %H:%M:%S')"
    notify_once "$STATE" stalled "scheduler-stalled" \
        "Claude Plus's run scheduled for $(date -d "@$target" '+%H:%M') has not happened, so nothing is being kept open. Is atd running? Start it with: sudo systemctl enable --now atd"
}

# ------------------------------------------------------------- observations

# Take one reading from a provider: its own JSON on stdin, normalised through
# the provider, stored, and the next window scheduled from it.
observe() {
    local id="$1" input parsed key value reset

    input="$(cat)"
    parsed="$(printf '%s' "$input" | provider_call "$id" parse_limits 2>/dev/null)" || return 0
    [[ -n "$parsed" ]] || return 0

    for key in window_seconds used_percent resets_at long_used_percent long_resets_at; do
        value="$(
            printf '%s' "$parsed" |
                jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
        )"
        [[ -n "$value" ]] && pset "$id" "$key" "$value"
    done

    reset="$(pget "$id" resets_at)"

    if [[ "$reset" =~ ^[0-9]+$ ]] && provider_can "$id" keep; then
        # Trust the reported reset time, plus 15s of slack
        arm_window "$id" "$((reset + 15))" "official-reset"
    fi

    maybe_check_stall "$id"
}

# For providers that cannot push, fetch a reading on demand
refresh_limits() {
    local id="$1" native

    provider_defines "$id" pull_limits || return 0
    native="$(provider_call "$id" pull_limits 2>/dev/null)" || return 0
    [[ -n "$native" ]] || return 0

    printf '%s' "$native" | observe "$id"
}

# A status line wrapper: feed the payload to observe, then render whatever the
# user had before us. The original command lives with the provider's state.
statusline() {
    local id="$1" input original orig_file

    # Two status line programs that each wrap the other would call each other
    # on every refresh; the inner call stops here instead
    if [[ -n "${CLAUDE_PLUS_IN_STATUSLINE:-}" ]]; then
        cat >/dev/null
        return 0
    fi
    export CLAUDE_PLUS_IN_STATUSLINE=1

    input="$(cat)"
    printf '%s' "$input" | "$SELF" observe "$id" >/dev/null 2>&1 || true

    orig_file="$(pstate "$id")/original-statusline-command"

    if [[ -s "$orig_file" ]]; then
        original="$(cat "$orig_file")"
        printf '%s' "$input" | bash -c "$original"
        return
    fi

    # Only fall back to a minimal line when nothing is wrapped
    local pct reset
    pct="$(pget "$id" used_percent)"
    reset="$(pget "$id" resets_at)"

    if [[ "$reset" =~ ^[0-9]+$ ]]; then
        printf '%s%% used | resets %s\n' "${pct:-?}" "$(date -d "@$reset" '+%H:%M')"
    fi
}

# ------------------------------------------------------------------- warmup

# Is the long window (weekly, monthly) full? Then a new short window is no use.
is_long_limited() {
    local id="$1" now reset pct
    now="$(date +%s)"
    reset="$(pget "$id" long_resets_at)"
    pct="$(pget "$id" long_used_percent)"

    [[ "$reset" =~ ^[0-9]+$ ]] || return 1
    [[ -n "$pct" ]] || return 1
    (( reset > now )) || return 1

    awk -v p="$pct" 'BEGIN { exit !(p >= 99.9) }'
}

do_warmup() {
    local id="$1" dir
    dir="$(pstate "$id")"
    mkdir -p "$dir"

    exec 8>"$dir/warmup.lock"

    # Never let two warmups run at once
    if ! flock -n 8; then
        return 0
    fi

    local now
    now="$(date +%s)"

    if is_long_limited "$id"; then
        local long_reset
        long_reset="$(pget "$id" long_resets_at)"
        log "[$id] Long window is full; waiting for it to reset"
        arm_job "$id" "$((long_reset + 15))" "long-window-reset"
        return 0
    fi

    local started output rc
    started="$(date +%s)"

    output="$(provider_call "$id" warmup)"
    rc=$?

    if (( rc == 0 )); then
        pset "$id" last_success "$started"
        pset "$id" failure_count 0
        rm -f "$dir/auth_required"
        notify_recovered "$dir" "Claude Plus is back to normal for $(provider_call "$id" label); windows are opening again." auth failing

        log "[$id] Warmup succeeded output=$(printf '%s' "$output" | tr '\n' ' ' | cut -c1-200)"

        # A warmup usually reports nothing about limits, so estimate the next
        # window from this request and let the next reading correct it
        arm_window "$id" "$((started + $(window_seconds "$id") + 15))" "estimated-next-reset"
        return 0
    fi

    if printf '%s\n' "$output" | provider_call "$id" auth_failed; then
        pset "$id" auth_required "$(date +%s)"
        log "[$id] Authentication required; warmups paused output=$(printf '%s' "$output" | tr '\n' ' ' | cut -c1-300)"

        notify_once "$dir" auth "auth-required" \
            "$(provider_call "$id" label) is no longer authenticated, so Claude Plus has stopped opening windows for it. Sign in again."

        # Leave room to recover on its own if the failure was temporary
        arm_job "$id" "$((now + 3600))" "auth-recheck"
        return 1
    fi

    local failures delay
    failures="$(pget "$id" failure_count)"
    [[ "$failures" =~ ^[0-9]+$ ]] || failures=0

    failures=$((failures + 1))
    pset "$id" failure_count "$failures"

    case "$failures" in
        1) delay=60 ;;
        2) delay=120 ;;
        3) delay=300 ;;
        *) delay=600 ;;
    esac

    log "[$id] Warmup failed rc=$rc retry=${delay}s output=$(printf '%s' "$output" | tr '\n' ' ' | cut -c1-300)"

    # Three failures means the backoff has stretched to minutes; worth a word
    if (( failures >= 3 )); then
        notify_once "$dir" failing "warmup-failing" \
            "Claude Plus has failed $failures warmups in a row for $(provider_call "$id" label), and is retrying every ${delay}s. See ~/.claude/claude-plus/claude-plus.log"
    fi

    arm_job "$id" "$((now + delay))" "warmup-retry"
    return 1
}

# ---------------------------------------------------------------- scheduling

# Put back the run an earlier version had planned, after an upgrade removed
# its at job. The target was computed then; one already missed runs now.
reschedule() {
    local id target reason

    for id in $(active_providers); do
        provider_can "$id" keep || continue

        target="$(pget "$id" at_target)"
        reason="$(pget "$id" at_reason)"

        if [[ "$target" =~ ^[0-9]+$ ]]; then
            arm_job "$id" "$target" "${reason:-rescheduled}"
        else
            # Nothing planned yet. A provider we can poll starts right away;
            # one that pushes waits for its first reading.
            refresh_limits "$id"
        fi
    done
}

scheduled() {
    local id="$1"

    # atd ran us, so whatever stall was reported is over
    pset "$id" last_run "$(date +%s)"
    notify_recovered "$STATE" "Claude Plus's scheduled runs are happening again." stalled

    # A provider that cannot push its limits gets read now, so the decision
    # below and the next estimate start from something current
    refresh_limits "$id"

    do_warmup "$id" || true
}

# ------------------------------------------------------------------- status

show_status() {
    local scheduler anchor id label dir target reason job last_run last_success
    local failures pct reset long_pct overdue window

    scheduler_running
    case $? in
        0) scheduler="atd running" ;;
        1) scheduler="ATD NOT RUNNING - nothing scheduled will run" ;;
        *) scheduler="unknown" ;;
    esac

    anchor="$(cat "$ANCHOR" 2>/dev/null || true)"

    echo "Version         : $VERSION"
    echo "Scheduler       : $scheduler"
    echo "Anchor          : ${anchor:-not set}"

    if [[ -x "$NOTIFY" ]]; then
        echo "Notify          : $NOTIFY"
    else
        echo "Notify          : not configured"
    fi

    for id in $(active_providers); do
        label="$(provider_call "$id" label)"
        dir="$(pstate "$id")"
        target="$(pget "$id" at_target)"
        reason="$(pget "$id" at_reason)"
        job="$(pget "$id" at_job)"
        last_run="$(pget "$id" last_run)"
        last_success="$(pget "$id" last_success)"
        failures="$(pget "$id" failure_count)"
        pct="$(pget "$id" used_percent)"
        reset="$(pget "$id" resets_at)"
        long_pct="$(pget "$id" long_used_percent)"
        window="$(window_seconds "$id")"
        overdue=""

        echo
        echo "[$id] $label"

        if ! provider_can "$id" keep; then
            echo "  Keep          : not supported by this agent"
        fi

        if [[ "$reset" =~ ^[0-9]+$ ]]; then
            echo "  Window        : ${pct:-?}% used, $((window / 60))min, resets $(date -d "@$reset" '+%Y-%m-%d %H:%M:%S')"
        else
            echo "  Window        : unknown"
        fi

        [[ -n "$long_pct" ]] && echo "  Long window   : ${long_pct}% used"

        if [[ "$target" =~ ^[0-9]+$ ]]; then
            if (( $(date +%s) > target + STALL_GRACE )) && job_exists "$job"; then
                overdue=" (OVERDUE, still queued)"
            fi
            echo "  Scheduled     : $(date -d "@$target" '+%Y-%m-%d %H:%M:%S')$overdue"
            echo "  Reason        : ${reason:-none}   at job: ${job:-none}"
        else
            echo "  Scheduled     : none"
        fi

        echo "  Failures      : ${failures:-0}   auth: $([[ -f "$dir/auth_required" ]] && echo 'RELOGIN MAY BE REQUIRED' || echo OK)"

        if [[ "$last_run" =~ ^[0-9]+$ ]]; then
            echo "  Last run      : $(date -d "@$last_run" '+%Y-%m-%d %H:%M:%S')"
        fi
        if [[ "$last_success" =~ ^[0-9]+$ ]]; then
            echo "  Last warmup   : $(date -d "@$last_success" '+%Y-%m-%d %H:%M:%S')"
        fi
    done
}

show_providers() {
    local id
    shopt -s nullglob

    for id in $(provider_ids); do
        printf '%-10s %-18s %-12s %s\n' \
            "$id" \
            "$(provider_call "$id" label)" \
            "$(provider_defines "$id" available && { "${id}_available" && echo installed || echo "not found"; })" \
            "$(provider_call "$id" capabilities)"
    done

    shopt -u nullglob
}

# ------------------------------------------------------------------ anchor

# Show, set or clear the time of day windows should open at
set_anchor() {
    local value="${1:-}" id target

    if [[ -z "$value" ]]; then
        if [[ -s "$ANCHOR" ]]; then
            echo "Anchor: $(cat "$ANCHOR")"
        else
            echo "Anchor: not set"
        fi
        return 0
    fi

    if [[ "$value" == off ]]; then
        rm -f "$ANCHOR"
        echo "Anchor cleared; windows open as soon as they can again."
    elif [[ "$value" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        printf '%s\n' "$value" > "$ANCHOR"
        echo "Anchor set to $value; no window will run across it."
    else
        echo "Usage: $0 anchor [HH:MM|off]" >&2
        return 2
    fi

    # Re-plan what is already scheduled under the new setting
    for id in $(active_providers); do
        provider_can "$id" keep || continue
        target="$(pget "$id" at_target)"
        [[ "$target" =~ ^[0-9]+$ ]] || continue
        arm_window "$id" "$target" "$(pget "$id" at_reason || echo rescheduled)"
    done
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

# --------------------------------------------------------------------- main

# Subcommands that act on one provider default to the first active one, so
# that jobs and hooks written by older versions still work.
default_provider() {
    active_providers | head -1
}

case "${1:-}" in
    statusline)
        statusline "${2:-$(default_provider)}"
        ;;
    observe)
        observe "${2:-$(default_provider)}"
        ;;
    warmup)
        do_warmup "${2:-$(default_provider)}"
        ;;
    scheduled)
        scheduled "${2:-$(default_provider)}"
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
    providers)
        show_providers
        ;;
    anchor)
        set_anchor "${2:-}"
        ;;
    notify-test)
        notify_test
        ;;
    version)
        echo "$VERSION"
        ;;
    *)
        echo "Usage: $0 {statusline|observe|warmup|scheduled} [provider]" >&2
        echo "       $0 {reschedule|scheduler-check|status|providers|notify-test|version}" >&2
        echo "       $0 anchor [HH:MM|off]" >&2
        exit 2
        ;;
esac
CLAUDE_PLUS

chmod +x "$BIN"

# Make sure the script just generated parses
bash -n "$BIN"

# One file per agent. See docs/PROVIDERS.md for what these have to answer.
cat > "$PROVIDERS/claude.sh" <<'PROVIDER_CLAUDE'
# Claude Code. Its status line hook hands over both windows on every refresh,
# so this provider pushes: no polling needed.
claude_label() {
    printf 'Claude Code\n'
}

claude_available() {
    command -v claude >/dev/null 2>&1
}

claude_capabilities() {
    printf 'keep alert\n'
}

# The status line payload, as Claude Code writes it
claude_parse_limits() {
    jq -c '{
        window_seconds: 18000,
        used_percent: .rate_limits.five_hour.used_percentage,
        resets_at: .rate_limits.five_hour.resets_at,
        long_used_percent: .rate_limits.seven_day.used_percentage,
        long_resets_at: .rate_limits.seven_day.resets_at
    } | with_entries(select(.value != null))' 2>/dev/null
}

# The smallest request that still opens a window: one Haiku turn, no tools,
# nothing written to session history
claude_warmup() {
    timeout 180 claude \
        --safe-mode \
        -p \
        --model haiku \
        --tools "" \
        --no-session-persistence \
        --max-turns 1 \
        'Reply only OK.' \
        2>&1
}
PROVIDER_CLAUDE

cat > "$PROVIDERS/codex.sh" <<'PROVIDER_CODEX'
# Codex. It has no status line hook to push readings, but it records its
# limits in every session log, so this provider is polled instead.
codex_label() {
    printf 'Codex\n'
}

codex_available() {
    command -v codex >/dev/null 2>&1
}

codex_capabilities() {
    printf 'keep alert\n'
}

# primary is the short window, secondary the long one; both carry their own
# length, so nothing here assumes five hours
codex_parse_limits() {
    jq -c '{
        window_seconds: (if .rate_limits.primary.window_minutes
                         then .rate_limits.primary.window_minutes * 60 else null end),
        used_percent: .rate_limits.primary.used_percent,
        resets_at: .rate_limits.primary.resets_at,
        long_used_percent: .rate_limits.secondary.used_percent,
        long_resets_at: .rate_limits.secondary.resets_at
    } | with_entries(select(.value != null))' 2>/dev/null
}

# The last limits written to the newest session log. As current as the user's
# last turn, which is enough: a warmup corrects the estimate afterwards.
codex_pull_limits() {
    local newest

    newest="$(ls -t "$HOME"/.codex/sessions/*/*/*/rollout-*.jsonl 2>/dev/null | head -1)"
    [[ -n "$newest" ]] || return 1

    tac "$newest" |
        jq -cR 'fromjson? | select(.payload.rate_limits != null) | {rate_limits: .payload.rate_limits}' 2>/dev/null |
        head -1
}

codex_warmup() {
    timeout 180 codex exec \
        --skip-git-repo-check \
        -s read-only \
        'Reply only OK.' \
        2>&1
}
PROVIDER_CODEX

cat > "$PROVIDERS/agy.sh" <<'PROVIDER_AGY'
# Antigravity. Its status line hook pushes quota on every refresh, like Claude
# Code, but reports what is left rather than what is used, as RFC 3339 times,
# split across several buckets.
agy_label() {
    printf 'Antigravity\n'
}

agy_available() {
    command -v agy >/dev/null 2>&1
}

agy_capabilities() {
    printf 'keep alert\n'
}

# Buckets are named by the window they belong to (gemini-5h, 3p-weekly, ...).
# Take the tightest of each kind: whichever runs out first is what stops you.
agy_parse_limits() {
    jq -c '
        def buckets(suffix):
            (.quota // {}) | to_entries | map(select(.key | endswith(suffix))) | map(.value);
        def pct(bs): 100 - (([bs[].remaining_fraction] | min) * 100) | . * 100 | round / 100;
        def first_reset(bs): [bs[].reset_time | fromdateiso8601] | min;

        buckets("-5h") as $short
        | buckets("-weekly") as $long
        | {
            window_seconds: 18000,
            used_percent: (if ($short | length) > 0 then pct($short) else null end),
            resets_at: (if ($short | length) > 0 then first_reset($short) else null end),
            long_used_percent: (if ($long | length) > 0 then pct($long) else null end),
            long_resets_at: (if ($long | length) > 0 then first_reset($long) else null end)
          }
        | with_entries(select(.value != null))' 2>/dev/null
}

agy_warmup() {
    timeout 180 agy -p 'Reply only OK.' 2>&1
}
PROVIDER_AGY

for _provider in "$PROVIDERS"/*.sh; do
    bash -n "$_provider"
done

# Removal above has already taken out every entry of ours; a status line
# wrapper is all Claude Plus adds, and inside another program's chain not even
# that. Each agent gets its own id on the command, so the wrapper knows whose
# reading it is handling.
for _id in $(wrapped_agents); do
    in_chain "$_id" && continue
    _file="$(agent_settings "$_id")" || continue
    [[ -f "$_file" ]] || continue

    TMP_SETTINGS="$(mktemp)"

    jq --arg status_cmd "$BIN statusline $_id" '
        .statusLine = (
            (.statusLine // {})
            + {
                "type": "command",
                "command": $status_cmd
            }
        )
    ' "$_file" > "$TMP_SETTINGS"

    jq empty "$TMP_SETTINGS"
    mv "$TMP_SETTINGS" "$_file"
done
unset _id _file

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
if [[ -n "$CHAINED" ]]; then
    echo "A status line belonging to another program already calls Claude Plus; it was left as it is:"
    printf '%s' "$CHAIN_COMMANDS" | sed 's/^/  /'
fi
echo "Agents          : $("$BIN" providers | awk '/installed/ {printf "%s ", $1}')"
echo "Main script     : $BIN"
echo
echo "Check:"
echo "  $BIN status"

