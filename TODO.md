# TODO

Analysis of 2.3.1, 2026-09-17. Nothing here has been started. Code is
referred to by function name rather than line number, since lines move.

## Features

### High priority

#### Anchor Keep to a time of day

After a successful warmup, `do_warmup` schedules the next one at
`started + 5h + 15s`. The chain's phase is therefore set by whenever the user
last ran out, not by their working hours.

Example: quota runs out at 23:30, resets at 04:30, Keep opens a window at
04:30, which resets at 09:30. Someone starting work at 09:00 lands in the last
half hour of an old window, exactly what the README says Keep avoids. The
README's "open at 06:00, reset at 11:00" example only holds when the phase
happens to line up.

Direction: a setting such as "open a window at 06:00". A warmup overnight
whose window would run across the anchor is pushed back to the anchor.

#### Detect a scheduler that is not running

The installer checks that `at` exists, not that `atd` is running. With `atd`
stopped, `at` still accepts jobs that never run: Keep and Resume silently stop,
while `status` keeps showing a scheduled time.

Direction:
- Check at install time that `atd` is running, and warn if not.
- Show in `status` when a scheduled run last actually executed.
- On a status line refresh, if `at_target` is several minutes in the past and
  the job is still queued, send a `scheduler-stalled` alert.

#### Tell the user when a resume did not happen

Two cases only write to the log:
- `resume_pending` gives up after two unanswered attempts
  (`resume-attempts-exhausted`).
- `rate_limit` sees a session outside tmux and cannot resume it.

The second is the common "I left a plain terminal open" case. An alert such as
"session hit the limit outside tmux and cannot be resumed; quota resets at
14:20" tells the user when to come back.

### Medium priority

#### Estimated resets can shift the chain by five hours

Warmups run with `--safe-mode`, so no status line runs and no official
`resets_at` is seen. While Claude Code is closed, the chain runs on estimates
alone. If an estimate is early, the warmup lands before the old window has
reset: it is counted against the old window, no new window opens, yet the
warmup reports success and the next one is set five hours later. The phase is
now off by five hours.

Needs research: a way to read current usage or the next reset without the
interactive UI (see Open questions).

#### Keep state private

`state/pending/*.json` holds working directories and transcript paths, and
`original-statusline-command` is run through `bash -c`. Everything inherits the
default umask and is typically readable by other local users. `umask 077` in
the installer and the generated script would close this.

#### Skip the extra warmup after a successful resume

A sent `continue` already opens the new window. The `resume-verification` run
90 seconds later finds nothing pending and falls through to `do_warmup`,
spending one more Haiku request and moving the estimate base 90 seconds later.
Harmless, but wasted.

### Low priority

- `rate_limit` rewrites the pending entry with `resume_attempts: 0` on every
  hit. If a resumed session hits the limit again straight away (for example the
  weekly quota at 99.5%, under the 99.9% threshold), it is resumed once per
  window. That is at most every five hours, so it cannot run away, but it
  deserves a test.
- `state/stale/` and `claude-plus.log` are never pruned. Both grow slowly.
- `--model haiku` is hard-coded. If that alias ever stops working, the only
  signal is the repeated-failure alert.

## Platforms

### Current platform dependencies

| Dependency | Used for | Uses | macOS | Windows (native) |
|---|---|---|---|---|
| GNU `date -d` | time conversion | 6 | BSD `date -r` instead | n/a |
| `at` / `atq` / `atrm` | scheduling | 8 | `atrun` disabled by default; launchd is native | Task Scheduler |
| `flock` | locking | 3 | missing | missing |
| `timeout` | time limits | 3 | missing (`gtimeout` via coreutils) | present in Git Bash |
| `/proc/<pid>/stat` | process start time | 1 | `ps -o lstart=` | n/a |
| `ps -o tpgid=` | foreground process group | 1 | present | no equivalent |
| `tmux` | resume | 14 | via Homebrew | missing |
| bash >= 4.4 | empty arrays under `set -u` | 8 | system bash is 3.2 | Git Bash is 5.x |

### WSL

If Claude Code runs inside WSL, Claude Plus already works: it is Linux. Two
things to verify and document:
- WSL shuts its VM down when idle. With no terminal open, the VM may be gone
  when an `at` job is due, and the job does not run.
- WSL does not run systemd by default, so `atd` has to be started by hand or
  systemd enabled.

Expected work: testing on a real machine and documentation; little or no code.

### macOS

All three features look feasible. Needed:
- The platform layer below, with Linux and macOS implementations.
- bash 3.2 compatibility, or a requirement for Homebrew bash.
- Scheduling through launchd.

Two things must be verified first; if either fails, the approach does not work:
1. Whether `claude -p` started in the background (launchd or `at`) can read the
   login credentials in the Keychain. If not, Keep cannot run on macOS at all.
2. What happens to a run that falls due while the lid is closed.

GitHub Actions has macOS runners, so the test suite can cover it.

### Windows (native)

- Resume is not feasible. There is no equivalent of tmux `send-keys`; the only
  option is synthesising keystrokes into the foreground window, which does
  nothing on a locked screen and can type into the wrong window. Not safe.
- Keep and Alert are possible, but scheduling, locking, process identity and
  the settings path all need different implementations. How Claude Code runs
  hook commands on native Windows needs checking. In practice this is a second
  implementation in PowerShell or Node.

Recommendation: not now.

### Groundwork: a platform layer

Before any port, gather the platform-bound calls into a handful of functions
(time formatting, schedule, cancel jobs, lock, run with timeout, process
identity), keeping Linux behaviour identical under the existing tests. This
makes the Linux code clearer on its own and is the prerequisite for macOS.

The runtime script, currently a ~700-line heredoc in the installer, could also
ship as its own file in the package and be copied into place.

A rewrite in Node is not recommended for now. It would drop jq and unify JSON
and subprocess handling, but scheduling, the hardest part, would still depend
on each platform, and installing from a git clone would start to require Node.

## Open questions

- Can `claude -p` started by launchd or `at` on macOS read Keychain credentials?
- How does WSL's idle VM shutdown affect `at` jobs in practice?
- Which shell does Claude Code use for hook commands on native Windows?
- Can `claude -p`, or anything else outside the interactive UI, report the
  next quota reset?
- Are five-hour reset times aligned to a fixed granularity? One observed value
  was exactly on the minute (18:20:00).

## Suggested order

1. Anchor Keep to a time of day.
2. Scheduler self-check and stall alert; alerts for abandoned resumes and
   limits hit outside tmux.
3. `umask 077`.
4. WSL: verify on a real machine, then document.
5. Research reading usage without the interactive UI.
6. macOS: verify Keychain access first; build the platform layer only if it
   works.
7. Native Windows: not now.
