# claude-plus

## Conventions

**Code comments are English.** This covers `install-claude-plus.sh`, the
`claude-plus.sh` it generates via the heredoc, and every script under
`notify/`. User-facing output from the scripts is English too.

**Documentation is multilingual and stays in sync.** Nine READMEs: `README.md`
(English), `.zh-CN` (Simplified Chinese), `.zh-TW` (Traditional Chinese), `.ja`
(Japanese), `.de` (German), `.fr` (French), `.it` (Italian), `.pt` (Portuguese),
`.ar` (Arabic). Any change to one must land in all nine in the same commit — no
"translate it later". They stay structurally identical: same sections in the
same order, and the language nav row on line 3 differs only in which entry is
left unlinked.

**Providers are the only place an agent is named.** The core knows a short
window and a long one, and asks a provider for everything else; see
`docs/PROVIDERS.md` for the contract. Adding an agent means adding
`providers/<id>.sh` (written by the installer's heredoc), an observer in the
installer if it can push readings, and a case in `tests/run.sh`. No core
function should ever test for a particular id.

**Tests.** `bash tests/run.sh` runs the integration suite in a throwaway
`HOME` with fake agents (`claude`, `codex`, `agy`), fake `at`, `atq`, `atrm`,
`systemctl`, `pgrep` and a notifier, so the real at queue, settings and
subscriptions are never touched. Run it before committing any change to the
installer or the script it generates, and add a case when fixing a bug.
GitHub Actions runs it on Ubuntu for every push.
