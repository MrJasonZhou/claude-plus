# Claude Plus

English | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Two things Claude Code does not do for you, handled while you are away from the keyboard.

- **Keep the window open** — a new 5-hour window is opened as soon as the last one resets, even while nobody is using Claude Code, so a full quota is already under way when you come back.
- **Alert** — when that stops working, it tells you: Bark, ntfy, email, or anything else you care to wire up.

Picking a session back up after a usage limit is something Claude Code now does itself: see "Continue automatically at usage limit" in `/config`. Claude Plus did this too before 3.0.0, and leaves it to Claude Code from then on.

## Why it helps

**When the window opens decides when it ends.** A 5-hour window starts at your first request, not at a fixed hour. Begin work at 9:00 and the window runs 9:00-14:00; burn through the quota by 11:00 and you are locked out until 14:00. Had a tiny request opened the window at 6:00 instead, it would expire at 11:00 — exactly when you run dry — with a fresh quota already waiting. With a window always running, one is already under way when you start: whatever is left of it is quota that would otherwise go unused, and a fresh one is at most five hours off, usually much less.

**Knowing when it has stopped helping.** Keeping windows open works until your login expires or the scheduler stops, and then nothing happens at all. Claude Plus notices either and says so, rather than failing quietly all weekend.

## Requirements

Linux, with `claude`, `jq`, `at` (with `atd` running), `flock`, `timeout`, GNU `date`.

```bash
sudo systemctl enable --now atd
```

## Install

```bash
npx @claude-plus/claude-plus
```

Or from a clone:

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

The installer wraps your existing status line, which keeps showing exactly as before; that is the only change it makes to your settings. Your `settings.json` is backed up first, and re-running the installer is a clean upgrade rather than a second copy. An upgrade carries over the next scheduled run, its state and your notifier. Upgrading from 2.x also removes the hooks those versions added to resume sessions.

## Usage

Day to day there is nothing to run — it works on its own. When you want to look:

```bash
~/.claude/claude-plus/claude-plus.sh status   # is the scheduler running, what is planned, is auth still good
tail -f ~/.claude/claude-plus/claude-plus.log # what it has been doing
```

## Opening at a fixed time

By default a window opens as soon as the last one resets, so the chain follows whenever you last ran out. To pin it to a time of day instead:

```bash
~/.claude/claude-plus/claude-plus.sh anchor 06:00   # open at 06:00
~/.claude/claude-plus/claude-plus.sh anchor         # show the setting
~/.claude/claude-plus/claude-plus.sh anchor off     # back to opening as soon as it can
```

A window that would run across the anchor waits for it instead: one due at 03:00 would cover 03:00-08:00 and swallow 06:00, so it opens at 06:00. The hours before the anchor are then left without a window — if you work in them, your own first request opens one as usual.

## Alerts

Claude Plus stays quiet unless something needs you, and tells you about four things:

| | |
|---|---|
| **Signed out** | Your Claude Code login has expired, so nothing can be opened until you sign in again |
| **Repeatedly failing** | Several warm-ups in a row have failed |
| **Scheduler stopped** | A planned run is long overdue, so no window is being kept open; usually `atd` is not running |
| **Back to normal** | It recovered from any of the above |

Each one is announced once, not on every retry, so a problem overnight costs you a single message. Usage limits themselves are never announced: they are routine, and Claude Code picks up after them on its own.

To choose how you hear about it, copy one of the samples and fill in your own key or server:

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh      # or ntfy.sh.sample, email.sh.sample
chmod +x notify.sh                      # use 700 for the email one, it holds a password
$EDITOR notify.sh
./claude-plus.sh notify-test            # make sure it reaches you
```

The notifier is just an executable that receives `CP_EVENT`, `CP_MESSAGE` and `CP_HOST`, so Telegram, Slack, a webhook or `mail` are all a matter of rewriting one line. Your copy survives reinstalls.

## Files

Everything lives in `~/.claude/claude-plus/`:

| | |
|---|---|
| `claude-plus.sh` | The script itself |
| `notify.sh` | Your notifier, once you set one up |
| `notify/` | Samples to copy from |
| `anchor` | The time of day windows open at, if you set one |
| `claude-plus.log` | What it has been doing |
| `state/` | Internal bookkeeping |

## Uninstall

```bash
npx @claude-plus/claude-plus uninstall
```

Or from a clone: `bash install-claude-plus.sh uninstall`.

It edits your current `settings.json` in place and takes out only what Claude Plus added: your own status line comes back, and every other setting and hook stays exactly as it is — including ones added after Claude Plus was installed. Its scheduled jobs are cancelled and `~/.claude/claude-plus/` is deleted, your `notify.sh` along with it. Running it a second time does no harm.

If another program has since wrapped your status line around Claude Plus, uninstalling will not break it. A small pass-through is left behind so that program keeps working, and the uninstaller tells you so; run it again once nothing needs it any more. Upgrading in the same situation stays inside that program's chain rather than wrapping it.

A copy of `settings.json` from just before uninstalling is kept next to it, as are the copies made at install time, in case you ever need to go back by hand.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
