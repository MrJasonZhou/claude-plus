# Claude Plus

English | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

Enhancements for Claude Code, driven by `at` jobs:

- **Resume** — when a session dies on a rate limit inside tmux, it types `continue` back into that pane as soon as the limit resets.
- **Keep** — with nothing to resume, it opens a fresh 5-hour window with a tiny Haiku request.

## How it works

1. Install rewrites `~/.claude/settings.json`: `statusLine` plus three hooks — `StopFailure` (matcher `rate_limit`), `UserPromptSubmit`, `SessionEnd`. Your existing status line command is saved and still rendered.
2. Every status line refresh reads `rate_limits.five_hour.resets_at` and schedules an `at` job for reset + 15s.
3. Hitting a rate limit records the session (tmux socket, pane, window, `pane_current_command`, cwd) under `state/pending/`, and schedules the same job.
4. At reset the job runs `scheduled`:
   - Pending sessions → `send-keys continue` to each pane, max 2 attempts per session, then re-check in 90s.
   - Nothing pending → `claude -p --model haiku --safe-mode --tools "" 'Reply only OK.'`, and the next job is estimated at 5h + 15s from the request start.
5. Pending entries are cleared when you type anything yourself (`UserPromptSubmit`) or the session ends (`SessionEnd`).
6. 7-day limit at 100% → everything waits for the weekly reset instead.

### Safety

A `continue` is only sent if the pane still exists, is still the same tmux session, and is still running the same command it was when the limit hit. Otherwise the entry is archived to `state/stale/` and nothing is typed. Sessions outside tmux are logged only — there is no pane to type into.

Warmup failure retries after 60s / 120s / 300s / 600s. If the output looks like an expired login, automatic warmup pauses, `state/auth_required` is written (`status` shows `RELOGIN MAY BE REQUIRED`), and it re-checks in 1 hour.

## Requirements

`claude`, `jq`, `at` (with `atd` running), `flock`, `timeout`, `tmux`, GNU `date`.

```bash
sudo systemctl enable --now atd
```

## Install

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

Formerly `claude-window-keeper`. Upgrading from it needs no extra step: the installer detects the old name, removes its `at` jobs, settings entries and `~/.claude/window-keeper/`, and carries your saved status line command over.

Any previous installation is removed first — its `at` jobs, its `statusLine` and hook entries, and `~/.claude/claude-plus/` — so re-running the installer is a clean upgrade. Other people's hooks are left alone. `settings.json` is backed up as `settings.json.claude-plus-install-backup.<timestamp>`.

Afterwards, check `/hooks` inside Claude Code for `StopFailure`, `UserPromptSubmit` and `SessionEnd`.

## Usage

```bash
~/.claude/claude-plus/claude-plus.sh status   # version, schedule, pending count, auth status
~/.claude/claude-plus/claude-plus.sh pending  # sessions waiting to be resumed
tail -f ~/.claude/claude-plus/claude-plus.log # log
```

## Files

| Path | Description |
|------|-------------|
| `~/.claude/claude-plus/claude-plus.sh` | Main script |
| `~/.claude/claude-plus/state/` | Reset times, job id, failure count, auth flag |
| `~/.claude/claude-plus/state/pending/` | Rate-limited sessions waiting to be resumed |
| `~/.claude/claude-plus/state/stale/` | Pending entries dropped because the pane changed |
| `~/.claude/claude-plus/original-statusline-command` | Your previous status line command |
| `~/.claude/claude-plus/claude-plus.log` | Log |

## Uninstall

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<timestamp> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```
