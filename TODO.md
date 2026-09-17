# TODO

Analysis of 2.3.1, 2026-09-17, revised the same day after discussion. The
scheduler check that was listed here is implemented in 2.4.0; nothing else has
been started. Code is referred to by function name rather than line number,
since lines move.

## Features

### High priority

#### Let Resume defer to Claude Code's own auto-continue

Claude Code now continues a session by itself when a usage limit resets:

- **CLI**: verified in the 2.1.274 binary. `/config` has "Continue automatically
  at usage limit" (`autoContinueAtUsageLimit`), on by default and stored with
  the account rather than in `settings.json`. The row only appears when some
  condition holds, which could not be determined from the binary. While
  waiting the UI shows `Usage limit reached · continuing automatically at
  HH:MM · esc to cancel`. It needs no tmux, only a running session.
- **Desktop**: the session-limit card in the Code tab has an "Auto-continue
  when limits reset" checkbox ([docs, week 33](https://code.claude.com/docs/en/whats-new/2026-w33)).
  The weekly-limit card does not offer it.

So Resume is redundant most of the time, and it can collide with the native
feature: Claude Code continues at the reset, then Claude Plus types
`continue` + Enter into the pane 15 seconds later. If the native continuation
does not fire `UserPromptSubmit`, the pending entry is still there, and the
extra `continue` is queued behind the work already running.

Where Resume still helps, because the native feature does not cover it:
- Weekly limits: native does not wait for a reset more than 24 hours out.
- Sleeping through the reset: native drops to "press enter to continue"
  (`sleptThroughReset`); Claude Plus can press it inside tmux.
- The setting is off, or not offered on the account.
- Older Claude Code versions.

**Decision: keep Resume as a fallback, and let the transcript decide.**
`rate_limit` already records `transcript_path`. The plan:

1. When the limit is hit, also record a baseline: the transcript's line count.
2. Wait longer after the reset before checking, so the native continuation
   (which fires with random jitter) goes first.
3. Before sending, read the transcript past the baseline. Any `type: "user"`
   entry, or any `type: "assistant"` entry without `isApiErrorMessage: true`,
   means the session has already moved on. Archive the entry as
   `session-already-continued` and send nothing. `system` and `attachment`
   entries do not count.
4. A session found to have continued has also opened a new window, so that
   scheduled run should not fall through to a warmup either.

API errors are written as `type: "assistant"` with `isApiErrorMessage: true`
and an `error` kind (seen locally: `authentication_failed`), so the limit
error itself is excluded by rule 3.

To verify on a real limit hit before settling the details (no sample exists
locally yet):
- The `error` kind a usage limit is written with.
- How the native continuation is written: `type`, `isMeta`, its text.
- The jitter range, which sets how long step 2 has to wait.
- Whether the native continuation fires `UserPromptSubmit`. If it does, the
  collision above cannot happen, and rule 3 is a second line of defence.
- Whether hitting the weekly limit writes anything different.

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

`state/pending/*.json` holds working directories and transcript paths, and
`original-statusline-command` is run through `bash -c`. Everything inherits the
default umask and is typically readable by other local users. `umask 077` in
the installer and the generated script would close this.

#### Skip the extra warmup after a successful resume

A sent `continue` already opens the new window. The `resume-verification` run
90 seconds later finds nothing pending and falls through to `do_warmup`,
spending one more Haiku request and moving the estimate base 90 seconds later.
Harmless, but wasted. Point 4 of the Resume plan above covers the native case;
this is the same fix for a continue Claude Plus sent itself.

### Low priority

- `rate_limit` rewrites the pending entry with `resume_attempts: 0` on every
  hit. If a resumed session hits the limit again straight away (for example the
  weekly quota at 99.5%, under the 99.9% threshold), it is resumed once per
  window. That is at most every five hours, so it cannot run away, but it
  deserves a test.
- Alert when Resume gives up after two unanswered attempts
  (`resume-attempts-exhausted`). Less useful now that the native feature
  handles most sessions.
- `state/stale/` and `claude-plus.log` are never pruned. Both grow slowly.
- `--model haiku` is hard-coded. If that alias ever stops working, the only
  signal is the repeated-failure alert.

### Decided against

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
- **Alerting on a limit hit outside tmux.** Claude Code's own auto-continue now
  resumes such sessions, so the alert would mostly report a non-problem.

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

- Resume is not feasible from outside, as there is no equivalent of tmux
  `send-keys`; the only option is synthesising keystrokes into the foreground
  window, which does nothing on a locked screen and can type into the wrong
  window. Claude Code's own auto-continue now covers most of this anyway.
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

- On a real usage limit hit: the `error` kind written to the transcript, how
  the native continuation is written, its jitter range, and whether it fires
  `UserPromptSubmit`. See the Resume plan.
- Can `claude -p` started by launchd or `at` on macOS read Keychain credentials?
- How does WSL's idle VM shutdown affect `at` jobs in practice?
- Which shell does Claude Code use for hook commands on native Windows?
- Can `claude -p`, or anything else outside the interactive UI, report the
  next quota reset?
- Are five-hour reset times aligned to a fixed granularity? One observed value
  was exactly on the minute (18:20:00).

## Suggested order

1. Collect a real limit hit (the log and transcript around it), then make
   Resume defer to the native auto-continue using the transcript.
2. `umask 077`.
3. WSL: verify on a real machine, then document.
4. Research reading usage without the interactive UI.
5. macOS: verify Keychain access first; build the platform layer only if it
   works.
6. Native Windows: not now.
