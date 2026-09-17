# TODO

Analysis of 2.3.1, 2026-09-17, revised since. The scheduler check listed here
first went into 2.4.0, and 3.0.0 removed Resume (see Decided against); nothing
else has been started. Code is referred to by function name rather than line
number, since lines move.

## Features

### Medium priority

#### Estimated resets can shift the chain by five hours

Warmups run with `--safe-mode`, so no status line runs and no official
`resets_at` is seen. While Claude Code is closed, the chain runs on estimates
alone. If an estimate is early, the warmup lands before the old window has
reset: it is counted against the old window, no new window opens, yet the
warmup reports success and the next one is set five hours later. The chain is
then idle for a window it could have used.

Needs research: a way to read current usage or the next reset without the
interactive UI (see Open questions).

#### Keep state private

`original-statusline-command` is run through `bash -c`, and `state/` and the
log describe when the user works. Everything inherits the default umask and is
typically readable by other local users. `umask 077` in the installer and the
generated script would close this.

### Low priority

- `claude-plus.log` is never pruned. It grows slowly.
- `--model haiku` is hard-coded. If that alias ever stops working, the only
  signal is the repeated-failure alert.

### Decided against

- **Resume, removed in 3.0.0.** Claude Code resumes a session by itself when a
  usage limit resets: the CLI's `/config` has "Continue automatically at usage
  limit" (`autoContinueAtUsageLimit`, on by default), and Desktop has an
  "Auto-continue when limits reset" checkbox. It runs inside the session, needs
  no tmux, and can be cancelled with Esc.
  Two real limit hits on 2026-09-16 and 09-17 showed Resume getting in its
  way. Both `continue` prompts in the transcript carry
  `origin: {kind: "human"}` and `promptSource: "typed"`, and arrived when atd
  ran the job at the top of the minute (0.26 s and 10 s after the reset), so
  Claude Plus's tmux keystrokes went first each time. On the second, the user
  had pressed Esc - the transcript records `Automatic continue cancelled` - and
  Resume continued anyway.
  What the native feature does not cover (weekly limits more than a day out,
  sleeping through the reset, the setting turned off, older Claude Code) is
  either reachable through `/rate-limit-options`, a single keypress, or a
  choice the user made. Not worth tmux, three hooks and the process-identity
  checks that came with it.
- **Anchoring Keep to a time of day.** The worry was that the chain's phase is
  set by when the user last ran out, so work might start in the last half hour
  of a window. That is not a loss: an overnight window is unused, so that half
  hour is quota that would otherwise go to waste, and the next full window is
  only half an hour away. With r hours left in the current window when work
  starts, a smaller r is better; the worst case, r close to five hours, is the
  same as having no Keep at all. Whatever the phase, Keep is never worse, so an
  anchor adds complexity for little gain. This only holds while the chain keeps
  running, which is what the scheduler check is for.
- **A watchdog independent of `at`.** The scheduler check runs on status line
  refreshes, so a scheduler that stops overnight is only noticed the next time
  Claude Code starts. Catching it sooner would take cron or a systemd timer,
  one more dependency; the delay is acceptable.

## Platforms

### Current platform dependencies

| Dependency | Used for | Uses | macOS | Windows (native) |
|---|---|---|---|---|
| GNU `date -d` | time conversion | 9 | BSD `date -r` instead | n/a |
| `at` / `atq` / `atrm` | scheduling | 9 | `atrun` disabled by default; launchd is native | Task Scheduler |
| `flock` | locking | 4 | missing | missing |
| `timeout` | time limits | 3 | missing (`gtimeout` via coreutils) | present in Git Bash |
| `systemctl` / `pgrep` | is atd running (optional) | 5 | `launchctl` | n/a |
| bash >= 4.4 | empty arrays under `set -u` | 8 | system bash is 3.2 | Git Bash is 5.x |

### WSL

If Claude Code runs inside WSL, Claude Plus already works: it is Linux. Two
things to verify and document:
- WSL shuts its VM down when idle. With no terminal open, the VM may be gone
  when an `at` job is due, and the job does not run. The scheduler check would
  then report a stall the next time Claude Code starts.
- WSL does not run systemd by default, so `atd` has to be started by hand or
  systemd enabled.

Expected work: testing on a real machine and documentation; little or no code.

### macOS

Both features look feasible, and with Resume gone the tmux and `/proc`
dependencies are gone too. Needed:
- The platform layer below, with Linux and macOS implementations.
- bash 3.2 compatibility, or a requirement for Homebrew bash.
- Scheduling through launchd.

Two things must be verified first; if either fails, the approach does not work:
1. Whether `claude -p` started in the background (launchd or `at`) can read the
   login credentials in the Keychain. If not, Keep cannot run on macOS at all.
2. What happens to a run that falls due while the lid is closed.

GitHub Actions has macOS runners, so the test suite can cover it.

### Windows (native)

Keep and Alert are possible, but scheduling, locking and the settings path all
need different implementations, and how Claude Code runs hook commands on
native Windows needs checking. In practice this is a second implementation in
PowerShell or Node.

Recommendation: not now.

### Groundwork: a platform layer

Before any port, gather the platform-bound calls into a handful of functions
(time formatting, schedule, cancel jobs, lock, run with timeout, scheduler
health), keeping Linux behaviour identical under the existing tests. This makes
the Linux code clearer on its own and is the prerequisite for macOS.

The runtime script, a heredoc in the installer, could also ship as its own file
in the package and be copied into place.

A rewrite in Node is not recommended for now. It would drop jq and unify JSON
and subprocess handling, but scheduling, the hardest part, would still depend
on each platform, and installing from a git clone would start to require Node.

## Open questions

- Can `claude -p` started by launchd or `at` on macOS read Keychain credentials?
- How does WSL's idle VM shutdown affect `at` jobs in practice?
- Which shell does Claude Code use for hook commands on native Windows?
- Can `claude -p`, or anything else outside the interactive UI, report the
  next quota reset?
- Are five-hour reset times aligned to a fixed granularity? Every observed
  value so far has been at twenty past the hour (14:20, 18:20, 19:20 JST).

## Suggested order

1. `umask 077`.
2. WSL: verify on a real machine, then document.
3. Research reading usage without the interactive UI.
4. macOS: verify Keychain access first; build the platform layer only if it
   works.
5. Native Windows: not now.
