# Claude Plus

English | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Three things Claude Code does not do for you, handled while you are away from the keyboard.

- **Resume** — a session stopped by a rate limit starts itself again the moment the limit resets, continuing the work it was in the middle of.
- **Keep the window open** — with nothing to resume, a new 5-hour window is opened anyway, so its reset lands outside your working hours instead of inside them.
- **Alert** — when it cannot carry on by itself, it tells you: Bark, ntfy, email, or anything else you care to wire up.

## Why it helps

**Recovering from a 5-hour limit.** Hitting the cap normally means the session just stops, and you come back later to restart it by hand. Claude Plus restarts it for you the moment the limit resets, so the work picks up where it left off — including while you are asleep or away from the desk.

**When the window opens decides when it ends.** A 5-hour window starts at your first request, not at a fixed hour. Begin work at 9:00 and the window runs 9:00-14:00; burn through the quota by 11:00 and you are locked out until 14:00. Had a tiny request opened the window at 6:00 instead, it would expire at 11:00 — exactly when you run dry — with a fresh quota already waiting. Keeping a window always running pushes its reset ahead of your working hours instead of into the middle of them.

**Knowing when it has stopped helping.** Automatic recovery works until your login expires, and then nothing works. Claude Plus notices that case and says so, rather than failing quietly all weekend.

## What it will not do

Resuming means typing into the terminal you were working in, so it is careful about where it types. A session is only resumed if it is still there, untouched, exactly as the limit left it. If you have closed it, moved on, or started something else in that terminal, Claude Plus leaves it alone and stays silent. Sessions running outside tmux are never resumed at all — there is nowhere to type.

Rate limits themselves are never announced. They are routine, the resume handles them, and a message each time would only be noise.

## Requirements

Linux, with `claude`, `jq`, `at` (with `atd` running), `flock`, `timeout`, `tmux`, GNU `date`.

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

The installer wraps your existing status line, which keeps showing exactly as before, and adds its own hooks, leaving other tools' hooks untouched. Your `settings.json` is backed up first, and re-running the installer is a clean upgrade rather than a second copy. An upgrade carries over whatever is in progress: sessions waiting to resume, the next scheduled run, and your notifier.

## Usage

Day to day there is nothing to run — it works on its own. When you want to look:

```bash
~/.claude/claude-plus/claude-plus.sh status   # is the scheduler running, what is planned, what is waiting, is auth still good
~/.claude/claude-plus/claude-plus.sh pending  # sessions waiting to be resumed
tail -f ~/.claude/claude-plus/claude-plus.log # what it has been doing
```

## Alerts

Claude Plus stays quiet unless something needs you, and tells you about four things:

| | |
|---|---|
| **Signed out** | Your Claude Code login has expired, so nothing can be opened until you sign in again |
| **Repeatedly failing** | Several warm-ups in a row have failed |
| **Scheduler stopped** | A planned run is long overdue, so nothing is being kept open or resumed; usually `atd` is not running |
| **Back to normal** | It recovered from any of the above |

Each one is announced once, not on every retry, so a problem overnight costs you a single message.

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
