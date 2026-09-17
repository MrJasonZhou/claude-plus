#!/usr/bin/env bash
# Integration tests for Claude Plus.
#
#   bash tests/run.sh
#
# Everything runs inside a throwaway directory: its own HOME, and fake claude,
# at, atq, atrm, systemctl and pgrep on PATH. The real at queue and
# settings.json are never touched. Needs jq, flock and timeout, which Claude
# Plus needs anyway.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/install-claude-plus.sh"
MARKER="/claude-plus/claude-plus.sh"

export CP_TEST
CP_TEST="$(mktemp -d)"
FAKES="$CP_TEST/bin"
QUEUE="$CP_TEST/queue"
mkdir -p "$FAKES" "$QUEUE"
trap 'rm -rf "$CP_TEST"' EXIT

PASS=0
FAIL=0

check() {
    if eval "$2"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $1"
    fi
}

section() {
    echo "== $1"
}

# ------------------------------------------------------------------ fakes

# at: -c prints a queued job, -t queues stdin and answers like the real one
cat > "$FAKES/at" <<'EOF'
#!/usr/bin/env bash
q="$CP_TEST/queue"
if [[ "$1" == -c ]]; then
    cat "$q/$2" 2>/dev/null
    exit
fi
last="$(ls "$q" | sort -n | tail -1)"
n=$(( ${last:-0} + 1 ))
cat > "$q/$n"
echo "job $n at $2"
EOF

cat > "$FAKES/atq" <<'EOF'
#!/usr/bin/env bash
for f in "$CP_TEST/queue"/*; do
    [[ -e "$f" ]] && printf '%s\tThu Jan  1 00:00:00 2099 a user\n' "$(basename "$f")"
done
EOF

cat > "$FAKES/atrm" <<'EOF'
#!/usr/bin/env bash
rm -f "$CP_TEST/queue/$1"
EOF

# claude: behaviour picked by a file, so a test can change it between runs
cat > "$FAKES/claude" <<'EOF'
#!/usr/bin/env bash
echo run >> "$CP_TEST/claude-runs"
case "$(cat "$CP_TEST/claude-mode" 2>/dev/null)" in
    auth) echo "OAuth token has expired. Please run /login" >&2; exit 1 ;;
    fail) echo "API Error: Overloaded" >&2; exit 1 ;;
    *)    echo OK ;;
esac
EOF

# The user's own status line
cat > "$FAKES/cs" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf CS
EOF

# Another program that wraps whatever status line it finds
cat > "$FAKES/xwrap" <<'EOF'
#!/usr/bin/env bash
s="$HOME/.claude/settings.json"
d="$HOME/.xwrap-downstream"
case "$1" in
    install)
        jq -r .statusLine.command "$s" > "$d"
        jq --arg c "$CP_TEST/bin/xwrap render" '.statusLine.command = $c' "$s" > "$s.t" && mv "$s.t" "$s"
        ;;
    uninstall)
        jq --arg c "$(cat "$d")" '.statusLine.command = $c' "$s" > "$s.t" && mv "$s.t" "$s"
        rm -f "$d"
        ;;
    render)
        printf 'X['
        bash -c "$(cat "$d")"
        printf ']'
        ;;
esac
EOF

# Another program that replaces the status line and calls nothing
cat > "$FAKES/yreplace" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf Y
EOF

# Same, but slow, so the chain probe stays in place long enough to race with
cat > "$FAKES/slowreplace" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
sleep 2
printf Y
EOF

# systemctl and pgrep report atd up or down, as the test switches it
cat > "$FAKES/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "is-active --quiet atd" ]] || exit 1
[[ "$(cat "$CP_TEST/atd" 2>/dev/null)" == up ]]
EOF

cat > "$FAKES/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "-x atd" ]] || exit 1
[[ "$(cat "$CP_TEST/atd" 2>/dev/null)" == up ]]
EOF

chmod +x "$FAKES"/*

# ---------------------------------------------------------------- helpers

new_home() {
    H="$CP_TEST/home-$1"
    rm -rf "$H"
    mkdir -p "$H/.claude"
    S="$H/.claude/settings.json"
    BASE="$H/.claude/claude-plus"
    CP="$BASE/claude-plus.sh"
    rm -f "$QUEUE"/* "$CP_TEST"/claude-mode "$CP_TEST"/claude-runs "$CP_TEST"/notify-*
    echo up > "$CP_TEST/atd"
}

# Poll a condition for up to three seconds, for work done in the background
wait_until() {
    local i
    for i in $(seq 1 60); do
        eval "$1" && return 0
        sleep 0.05
    done
    return 1
}

in_home() {
    HOME="$H" PATH="$FAKES:$PATH" "$@"
}

install_cp() {
    in_home bash "$INSTALLER" "$@"
}

cp_run() {
    in_home "$CP" "$@"
}

render() {
    printf '{"model":{"display_name":"x"},"workspace":{"current_dir":"/tmp"}}' |
        in_home timeout 5 bash -c "$(jq -r .statusLine.command "$S")"
}

our_jobs() {
    grep -lF "$MARKER" "$QUEUE"/* 2>/dev/null | wc -l
}

make_notifier() {
    mkdir -p "$BASE"
    cat > "$BASE/notify.sh" <<'EOF'
#!/usr/bin/env bash
echo "$CP_EVENT" >> "$CP_TEST/notify-attempts"
n="$(cat "$CP_TEST/notify-fail" 2>/dev/null || echo 0)"
if (( n > 0 )); then
    echo $((n - 1)) > "$CP_TEST/notify-fail"
    exit 1
fi
echo "$CP_EVENT" >> "$CP_TEST/notify-delivered"
EOF
    chmod +x "$BASE/notify.sh"
}

# How many lines of $2 are exactly $1; 0 when the file does not exist yet
count() {
    local n
    n="$(grep -cx "$1" "$CP_TEST/$2" 2>/dev/null)" || true
    echo "${n:-0}"
}

with_cs() {
    printf '{"statusLine":{"type":"command","command":"%s","refreshInterval":1}}\n' "$FAKES/cs" > "$S"
}

# ======================================================================
section "install and uninstall keep everything that is not ours"

new_home basic
cat > "$S" <<EOF
{"model":"opus",
 "statusLine":{"type":"command","command":"$FAKES/cs","refreshInterval":1},
 "hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"rtk hook claude"}]}],
          "UserPromptSubmit":[{"hooks":[{"type":"command","command":"/opt/audit"}]}]}}
EOF
install_cp >/dev/null
check "wraps the status line"      '[[ $(jq -r .statusLine.command "$S") == "$CP statusline" ]]'
check "saves the original"         '[[ $(cat "$BASE/original-statusline-command") == "$FAKES/cs" ]]'
check "keeps statusLine siblings"  '[[ $(jq .statusLine.refreshInterval "$S") == 1 ]]'
check "adds only the status line"  '[[ $(grep -o "$MARKER" "$S" | wc -l) == 1 ]] && ! jq -e ".hooks.StopFailure" "$S" >/dev/null'
check "renders through wrapper"    '[[ $(render) == CS ]]'

jq '.env = {"FOO":"1"} | .hooks.SessionEnd += [{"hooks":[{"type":"command","command":"/opt/save"}]}]' "$S" > "$S.t" && mv "$S.t" "$S"
# What versions before 3.0.0 also registered, to resume sessions themselves
jq --arg cp "$CP" '
    .hooks.StopFailure += [{"matcher":"rate_limit","hooks":[{"type":"command","command":($cp + " rate-limit")}]}]
    | .hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":($cp + " prompt-submit")}]}]
    | .hooks.SessionEnd += [{"hooks":[{"type":"command","command":($cp + " session-end")}]}]
' "$S" > "$S.t" && mv "$S.t" "$S"
mkdir -p "$BASE/state/pending" "$BASE/state/stale"
echo '{"session_id":"old"}' > "$BASE/state/pending/old.json"
echo "2026-01-01 00:00:00 an earlier line" > "$BASE/claude-plus.log"
make_notifier
{ echo "$CP scheduled"; head -c 1048576 /dev/zero | tr '\0' x; } > "$QUEUE/1"
echo "/usr/local/bin/nightly" > "$QUEUE/2"

install_cp >/dev/null
check "upgrade: original not doubled"  '[[ $(cat "$BASE/original-statusline-command") == "$FAKES/cs" ]]'
check "upgrade: later edits survive"   '[[ $(jq -r .env.FOO "$S") == 1 ]]'
check "upgrade: old resume hooks gone"  '[[ $(grep -o "$MARKER" "$S" | wc -l) == 1 && $(jq -c ".hooks | keys" "$S") == "[\"PreToolUse\",\"SessionEnd\",\"UserPromptSubmit\"]" ]]'
check "upgrade: user hooks in those events kept" '[[ $(jq -r ".hooks.UserPromptSubmit[0].hooks[0].command, .hooks.SessionEnd[0].hooks[0].command" "$S" | tr "\n" " ") == "/opt/audit /opt/save " ]]'
check "upgrade: old resume queue removed"  '[[ ! -e "$BASE/state/pending" && ! -e "$BASE/state/stale" ]]'
check "upgrade: log kept"              'grep -q "an earlier line" "$BASE/claude-plus.log"'
check "upgrade: notifier survives"     '[[ -x "$BASE/notify.sh" ]]'
check "upgrade: big job of ours gone"  '[[ ! -e "$QUEUE/1" ]]'
check "upgrade: foreign job kept"      '[[ -e "$QUEUE/2" ]]'

out="$(install_cp uninstall)"
check "uninstall: says so"             '[[ $out == *"uninstalled"* ]]'
check "uninstall: original restored"   '[[ $(jq -c .statusLine "$S") == "{\"type\":\"command\",\"command\":\"$FAKES/cs\",\"refreshInterval\":1}" ]]'
check "uninstall: no trace of ours"    '! grep -qF "$MARKER" "$S"'
check "uninstall: other hooks intact"  '[[ $(jq -c "[.hooks[][] .hooks[] .command] | sort" "$S") == "[\"/opt/audit\",\"/opt/save\",\"rtk hook claude\"]" ]]'
check "uninstall: later edits survive" '[[ $(jq -r .env.FOO "$S") == 1 && $(jq -r .model "$S") == opus ]]'
check "uninstall: directory gone"      '[[ ! -e "$BASE" ]]'
check "uninstall: no jobs of ours"     '[[ $(our_jobs) == 0 && -e "$QUEUE/2" ]]'
check "uninstall: backup made"         'compgen -G "$S.claude-plus-uninstall-backup.*" >/dev/null'

before="$(md5sum < "$S")"
out="$(install_cp uninstall)"
rc=$?
check "uninstall again: exit 0"          '[[ $rc == 0 ]]'
check "uninstall again: not installed"   '[[ $out == *"not installed"* ]]'
check "uninstall again: file untouched"  '[[ $(md5sum < "$S") == "$before" ]]'

new_home nosettings
install_cp uninstall >/dev/null
check "no settings.json: none created"   '[[ ! -e "$S" ]]'

new_home badjson
echo '{broken' > "$S"
before="$(md5sum < "$S")"
install_cp uninstall >/dev/null 2>&1
rc=$?
check "invalid JSON: refused"            '[[ $rc == 1 && $(md5sum < "$S") == "$before" ]]'

install_cp --help >/dev/null 2>&1; rc=$?
check "--help exits 0"                   '[[ $rc == 0 ]]'
install_cp bogus >/dev/null 2>&1; rc=$?
check "unknown action exits 2"           '[[ $rc == 2 ]]'

# ======================================================================
section "strip filter edge cases"

STRIP_FILTER="$(sed -n "/^STRIP_FILTER='$/,/^'$/p" "$INSTALLER" | sed '1d;$d')"
strip() {
    jq -cS --arg marker "$MARKER" --arg orig "${2:-}" "$STRIP_FILTER" <<< "$1"
}
norm() {
    jq -cS . <<< "$1"
}
W="/h/.claude/claude-plus/claude-plus.sh"

check "never restores our own wrapper" \
    '[[ $(strip "{\"statusLine\":{\"command\":\"$W statusline\"}}" "$W statusline") == "{}" ]]'
check "shared group keeps the foreign hook" \
    '[[ $(strip "{\"hooks\":{\"E\":[{\"hooks\":[{\"command\":\"/opt/a\"},{\"command\":\"$W x\"}]}]}}") == "$(norm "{\"hooks\":{\"E\":[{\"hooks\":[{\"command\":\"/opt/a\"}]}]}}")" ]]'
check "pre-existing empty group kept" \
    '[[ $(strip "{\"hooks\":{\"E\":[{\"hooks\":[]}]}}") == "$(norm "{\"hooks\":{\"E\":[{\"hooks\":[]}]}}")" ]]'
check "user empty hooks object kept" \
    '[[ $(strip "{\"hooks\":{}}") == "{\"hooks\":{}}" ]]'
for odd in '{"statusLine":"text"}' '{"hooks":[]}' '{"hooks":{"X":"s"}}' '{"hooks":{"X":[1,null]}}' '{"hooks":{"X":[{"hooks":"n"}]}}'; do
    check "odd shape passes through: $odd" '[[ $(strip "$odd") == "$(norm "$odd")" ]]'
done

# ======================================================================
section "another program wraps the status line around ours"

new_home chain
with_cs
install_cp >/dev/null
in_home "$FAKES/xwrap" install
check "chain renders"                  '[[ $(render) == "X[CS]" ]]'

out="$(install_cp)"
check "upgrade: wrapper left alone"    '[[ $(jq -r .statusLine.command "$S") == "$FAKES/xwrap render" ]]'
check "upgrade: still renders cs"      '[[ $(cat "$BASE/original-statusline-command") == "$FAKES/cs" ]]'
check "upgrade: full script"           'grep -q "^observe()" "$CP"'
check "upgrade: renders, no loop"      '[[ $(render) == "X[CS]" ]]'

out="$(install_cp uninstall)"
check "uninstall: leaves pass-through" '[[ $out == *pass-through* ]] && grep -q "was uninstalled" "$CP"'
check "uninstall: chain still renders" '[[ $(render) == "X[CS]" ]]'
check "uninstall: runtime state gone"  '[[ ! -e "$BASE/state" ]]'
before="$(md5sum < "$S")"
install_cp uninstall >/dev/null
check "uninstall again: still renders" '[[ $(render) == "X[CS]" && $(md5sum < "$S") == "$before" ]]'
in_home "$FAKES/xwrap" uninstall
install_cp uninstall >/dev/null
check "wrapper gone: original back"    '[[ $(jq -r .statusLine.command "$S") == "$FAKES/cs" && ! -e "$BASE" ]]'

new_home replaced
with_cs
install_cp >/dev/null
jq --arg c "$FAKES/yreplace" '.statusLine.command = $c' "$S" > "$S.t" && mv "$S.t" "$S"
out="$(install_cp uninstall)"
check "replaced, not wrapped: no stub" '[[ $out != *pass-through* && ! -e "$BASE" ]]'

new_home loop
with_cs
install_cp >/dev/null
in_home "$FAKES/xwrap" install
printf '%s\n' "$FAKES/xwrap render" > "$BASE/original-statusline-command"
jq --arg c "$CP statusline" '.statusLine.command = $c' "$S" > "$S.t" && mv "$S.t" "$S"
render >/dev/null
rc=$?
check "hand-made loop terminates"      '[[ $rc == 0 ]]'

# ======================================================================
section "the chain probe swallows nothing and never outlives the installer"

use_slow_replacement() {
    new_home "$1"
    with_cs
    install_cp >/dev/null
    jq --arg c "$FAKES/slowreplace" '.statusLine.command = $c' "$S" > "$S.t" && mv "$S.t" "$S"
    rm -f "$CP_TEST/claude-runs"
}

wait_for_probe() {
    local i
    for i in $(seq 1 60); do
        # The real script has been swapped out (true of old and new probes)
        [[ -f "$CP" ]] && ! grep -q "^observe()" "$CP" && return 0
        sleep 0.05
    done
    return 1
}

use_slow_replacement probe-race
install_cp uninstall > "$CP_TEST/probe.out" 2>&1 &
installer=$!
wait_for_probe
check "probe is in place for the race"          '[[ $? == 0 ]]'
cp_run scheduled >/dev/null
cp_run status >/dev/null
wait "$installer"
check "scheduled run during probe still ran"    '[[ -s "$CP_TEST/claude-runs" ]]'
check "other calls during probe are not a hit"   '[[ $(cat "$CP_TEST/probe.out") != *pass-through* && ! -e "$BASE" ]]'

for sig in HUP TERM INT; do
    use_slow_replacement "probe-$sig"
    # Job control gives the background installer its own process group and
    # keeps SIGINT from being ignored, as it would be from a terminal
    set -m
    HOME="$H" PATH="$FAKES:$PATH" bash "$INSTALLER" uninstall >/dev/null 2>&1 &
    installer=$!
    set +m
    wait_for_probe
    kill -"$sig" "$installer"
    wait "$installer"
    rc=$?
    check "SIG$sig during probe: installer stops"          '[[ $rc != 0 ]]'
    check "SIG$sig during probe: real script restored"     'grep -q "^observe()" "$CP"'
    check "SIG$sig during probe: no temporary files left"  '! compgen -G "$BASE/.saved.*" >/dev/null && ! compgen -G "$BASE/.probe.*" >/dev/null'
    check "SIG$sig during probe: still installed"          '[[ -d "$BASE/state" ]]'
done

# ======================================================================
section "upgrade keeps runtime state; uninstall removes it"

new_home state
with_cs
install_cp >/dev/null
now="$(date +%s)"
target=$((now + 3600))
echo $((now + 3585))            > "$BASE/state/five_hour_reset"
echo 42                          > "$BASE/state/five_hour_pct"
echo $((now + 86400))           > "$BASE/state/seven_day_reset"
echo 10                          > "$BASE/state/seven_day_pct"
echo 2                           > "$BASE/state/failure_count"
echo "$now"                      > "$BASE/state/last_success"
: > "$BASE/state/notified-failing"
echo "$target"                   > "$BASE/state/at_target"
echo pending-rate-limit          > "$BASE/state/at_reason"
echo "$CP scheduled"             > "$QUEUE/7"
echo 7                           > "$BASE/state/at_job"
make_notifier

install_cp >/dev/null
check "reset times kept"           '[[ $(cat "$BASE/state/five_hour_reset") == $((now + 3585)) && $(cat "$BASE/state/seven_day_pct") == 10 ]]'
check "failure state kept"         '[[ $(cat "$BASE/state/failure_count") == 2 && -e "$BASE/state/notified-failing" ]]'
check "last success kept"          '[[ $(cat "$BASE/state/last_success") == "$now" ]]'
check "notifier kept"              '[[ -x "$BASE/notify.sh" ]]'
check "old job replaced"           '[[ ! -e "$QUEUE/7" && $(our_jobs) == 1 ]]'
check "same target re-armed"       '[[ $(cat "$BASE/state/at_target") == "$target" ]]'
check "same reason kept"           '[[ $(cat "$BASE/state/at_reason") == pending-rate-limit ]]'

echo $((now - 600)) > "$BASE/state/at_target"
install_cp >/dev/null
t="$(cat "$BASE/state/at_target")"
check "missed target runs now"     '(( t >= now && t <= $(date +%s) + 30 )) && [[ $(our_jobs) == 1 ]]'

new_home fresh
with_cs
install_cp >/dev/null
check "fresh install: no job yet"  '[[ $(our_jobs) == 0 ]]'

install_cp uninstall >/dev/null
check "uninstall: state removed"   '[[ ! -e "$BASE" && $(our_jobs) == 0 ]]'

check "generated script never turns errexit on" \
    '! sed -n "/^cat > \"\$BIN\" <<.CLAUDE_PLUS.\$/,/^CLAUDE_PLUS\$/p" "$INSTALLER" | grep -qE "^\s*set -e"'

# ======================================================================
section "alerts are marked sent only once delivered"

new_home alert
echo '{}' > "$S"
install_cp >/dev/null
echo auth > "$CP_TEST/claude-mode"

cp_run warmup >/dev/null
check "no notifier: nothing marked"      '[[ ! -e "$BASE/state/notified-auth" ]]'

make_notifier
echo 1 > "$CP_TEST/notify-fail"
cp_run warmup >/dev/null
check "failed send: attempted"           '[[ $(count auth-required notify-attempts) == 1 ]]'
check "failed send: not marked"          '[[ ! -e "$BASE/state/notified-auth" ]]'

cp_run warmup >/dev/null
check "retry: delivered"                 '[[ $(count auth-required notify-delivered) == 1 ]]'
check "retry: now marked"                '[[ -e "$BASE/state/notified-auth" ]]'

cp_run warmup >/dev/null
check "marked: not sent again"           '[[ $(count auth-required notify-attempts) == 2 ]]'

echo ok > "$CP_TEST/claude-mode"
echo 1 > "$CP_TEST/notify-fail"
cp_run warmup >/dev/null
check "recovery send failed: flag kept"  '[[ -e "$BASE/state/notified-auth" && $(count recovered notify-delivered) == 0 ]]'

cp_run warmup >/dev/null
check "recovery retried and delivered"   '[[ $(count recovered notify-delivered) == 1 && ! -e "$BASE/state/notified-auth" ]]'

cp_run warmup >/dev/null
check "recovery announced once"          '[[ $(count recovered notify-attempts) == 2 ]]'

echo fail > "$CP_TEST/claude-mode"
for _ in 1 2; do cp_run warmup >/dev/null; done
check "two failures: quiet"              '[[ $(count warmup-failing notify-attempts) == 0 ]]'
cp_run warmup >/dev/null
check "third failure: announced"         '[[ $(count warmup-failing notify-delivered) == 1 && -e "$BASE/state/notified-failing" ]]'

# ======================================================================
section "a scheduler that is not running gets noticed"

new_home sched
with_cs
echo down > "$CP_TEST/atd"
out="$(install_cp 2>&1)"
check "install warns when atd is down"      '[[ $out == *"atd is not running"* ]]'
check "status says atd is down"             '[[ $(cp_run status) == *"ATD NOT RUNNING"* ]]'
echo up > "$CP_TEST/atd"
out="$(install_cp 2>&1)"
check "no warning when atd is up"           '[[ $out != *"atd is not running"* ]]'
check "status says atd is running"          '[[ $(cp_run status) == *"Scheduler       : atd running"* ]]'
check "status: no run yet"                  '[[ $(cp_run status) == *"Last run        : none"* ]]'

make_notifier
refresh() {
    printf '{}' | cp_run observe >/dev/null
}

echo $(( $(date +%s) + 600 )) > "$BASE/state/at_target"
refresh
sleep 0.5
check "target in the future: not looked at"  '[[ ! -e "$BASE/state/stall_checked_at" ]]'

echo $(( $(date +%s) - 400 )) > "$BASE/state/at_target"
echo 99 > "$BASE/state/at_job"
refresh
wait_until '[[ -e "$BASE/state/stall_checked_at" ]]'
sleep 0.3
check "overdue but no longer queued: quiet" '[[ $(count scheduler-stalled notify-attempts) == 0 ]]'

echo "$CP scheduled" > "$QUEUE/5"
echo 5 > "$BASE/state/at_job"
rm -f "$BASE/state/stall_checked_at"
echo 1 > "$CP_TEST/notify-fail"
refresh
wait_until '[[ $(count scheduler-stalled notify-attempts) == 1 ]]'
check "overdue and queued: alert attempted" '[[ $(count scheduler-stalled notify-attempts) == 1 ]]'
check "failed send: not marked"             '[[ ! -e "$BASE/state/notified-stalled" ]]'
check "status flags the overdue run"        '[[ $(cp_run status) == *OVERDUE* ]]'

refresh
sleep 0.5
check "throttled: no second look straight away" '[[ $(count scheduler-stalled notify-attempts) == 1 ]]'

echo 0 > "$BASE/state/stall_checked_at"
refresh
wait_until '[[ $(count scheduler-stalled notify-delivered) == 1 ]]'
check "retry after grace: delivered, marked" '[[ $(count scheduler-stalled notify-delivered) == 1 && -e "$BASE/state/notified-stalled" ]]'

echo 0 > "$BASE/state/stall_checked_at"
refresh
wait_until '[[ $(cat "$BASE/state/stall_checked_at") != 0 ]]'
sleep 0.3
check "marked: not sent again"              '[[ $(count scheduler-stalled notify-attempts) == 2 ]]'

echo ok > "$CP_TEST/claude-mode"
cp_run scheduled >/dev/null
check "a run clears the stall, says so"     '[[ ! -e "$BASE/state/notified-stalled" && $(count recovered notify-delivered) == 1 ]]'
check "status shows the last run"           '[[ $(cp_run status) == *"Last run        : 20"* ]]'

# ======================================================================
echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
