# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | Deutsch | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Erweiterungen für Claude Code, angetrieben von `at`-Jobs:

- **Fortsetzen** — stirbt eine Sitzung innerhalb von tmux an einem Limit, tippt Claude Plus `continue` in genau dieses Pane, sobald das Limit zurückgesetzt wird.
- **Offenhalten** — gibt es nichts fortzusetzen, öffnet eine winzige Haiku-Anfrage ein frisches 5-Stunden-Fenster.

## Wozu das gut ist

**Erholung von einem 5-Stunden-Limit.** Normalerweise bleibt die Sitzung am Limit einfach stehen, und Sie starten sie später von Hand neu. Hier wird `continue` in dem Moment ins Pane getippt, in dem das Limit zurückgesetzt wird, sodass die Arbeit dort weiterläuft, wo sie aufgehört hat — auch während Sie schlafen oder nicht am Schreibtisch sind.

**Wann das Fenster öffnet, entscheidet, wann es endet.** Ein 5-Stunden-Fenster beginnt mit Ihrer ersten Anfrage, nicht zu einer festen Uhrzeit. Beginnen Sie um 9:00 zu arbeiten, läuft das Fenster von 9:00 bis 14:00; ist das Kontingent um 11:00 aufgebraucht, sind Sie bis 14:00 ausgesperrt. Hätte stattdessen eine winzige Anfrage das Fenster um 6:00 geöffnet, liefe es um 11:00 ab — genau dann, wenn Ihnen der Vorrat ausgeht — und ein frisches Kontingent stünde bereit. Ein dauerhaft laufendes Fenster schiebt seinen Reset vor Ihre Arbeitszeit statt mitten hinein.

## Funktionsweise

1. Die Installation schreibt `~/.claude/settings.json` um: `statusLine` plus drei Hooks — `StopFailure` (Matcher `rate_limit`), `UserPromptSubmit`, `SessionEnd`. Ihr vorhandener Status-Line-Befehl wird gesichert und weiterhin angezeigt.
2. Jede Aktualisierung der Status Line liest `rate_limits.five_hour.resets_at` und plant einen `at`-Job für Reset + 15 s.
3. Beim Erreichen eines Limits wird die Sitzung (tmux-Socket, Pane, Fenster, `pane_current_command`, cwd) unter `state/pending/` festgehalten und derselbe Job geplant.
4. Zum Reset führt der Job `scheduled` aus:
   - Wartende Sitzungen → `send-keys continue` an jedes Pane, höchstens 2 Versuche pro Sitzung, danach erneute Prüfung nach 90 s.
   - Nichts wartet → `claude -p --model haiku --safe-mode --tools "" 'Reply only OK.'`, und der nächste Job wird auf 5 h + 15 s ab Anfragebeginn geschätzt.
5. Wartende Einträge werden gelöscht, sobald Sie selbst etwas eingeben (`UserPromptSubmit`) oder die Sitzung endet (`SessionEnd`).
6. 7-Tage-Limit bei 100 % → alles wartet stattdessen auf den wöchentlichen Reset.

### Schutz vor Fehleingaben

Ein `continue` wird nur gesendet, wenn das Pane noch existiert, noch zur selben tmux-Sitzung gehört und noch denselben Befehl ausführt wie zum Zeitpunkt des Limits. Andernfalls wandert der Eintrag nach `state/stale/` und es wird nichts getippt. Sitzungen außerhalb von tmux werden nur protokolliert — es gibt kein Pane, in das getippt werden könnte.

Fehlgeschlagene Warm-ups werden nach 60 s / 120 s / 300 s / 600 s wiederholt. Sieht die Ausgabe nach einer abgelaufenen Anmeldung aus, pausiert das automatische Warm-up, `state/auth_required` wird geschrieben (`status` zeigt `RELOGIN MAY BE REQUIRED`) und nach einer Stunde erneut geprüft.

## Voraussetzungen

`claude`, `jq`, `at` (mit laufendem `atd`), `flock`, `timeout`, `tmux`, GNU `date`.

```bash
sudo systemctl enable --now atd
```

## Installation

```bash
npx @claude-plus/claude-plus
```

Oder aus einem Klon:

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

Eine vorhandene Installation wird zuerst entfernt — ihre `at`-Jobs, ihre `statusLine`- und Hook-Einträge sowie `~/.claude/claude-plus/` — ein erneuter Lauf des Installers ist also ein sauberes Upgrade. Fremde Hooks bleiben unangetastet. `settings.json` wird als `settings.json.claude-plus-install-backup.<Zeitstempel>` gesichert.

Prüfen Sie danach in Claude Code mit `/hooks`, ob `StopFailure`, `UserPromptSubmit` und `SessionEnd` eingetragen sind.

## Verwendung

```bash
~/.claude/claude-plus/claude-plus.sh status   # Version, Zeitplan, Wartende, Auth-Status
~/.claude/claude-plus/claude-plus.sh pending  # Sitzungen, die auf Fortsetzung warten
~/.claude/claude-plus/claude-plus.sh notify-test  # Testbenachrichtigung an sich selbst
tail -f ~/.claude/claude-plus/claude-plus.log # Protokoll
```

## Benachrichtigungen

Claude Plus bleibt still, solange nichts Ihre Aufmerksamkeit braucht. Es führt
`~/.claude/claude-plus/notify.sh` aus — eine beliebige ausführbare Datei — bei drei Ereignissen:

| Ereignis | Wann |
|----------|------|
| `auth-required` | Claude Code ist abgemeldet, es lässt sich kein Fenster öffnen |
| `warmup-failing` | Drei Warm-ups sind hintereinander fehlgeschlagen |
| `recovered` | Die Warm-ups laufen nach einem der beiden Fälle wieder |

Jedes Ereignis feuert einmal beim Eintritt in diesen Zustand, nicht bei jedem
Wiederholungsversuch. Ein Problem über Nacht kostet Sie also eine Nachricht statt acht.

Vorlagen für Bark, ntfy und SMTP-E-Mail werden unter
`~/.claude/claude-plus/notify/` installiert. Wählen Sie eine aus, tragen Sie
Ihren eigenen Schlüssel oder Server ein und testen Sie sie:

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh
chmod +x notify.sh          # für die E-Mail-Variante 700, sie enthält ein Passwort
$EDITOR notify.sh
./claude-plus.sh notify-test
```

Das Skript läuft mit `CP_EVENT`, `CP_MESSAGE` und `CP_HOST` in seiner Umgebung.
Alles andere — Telegram, Slack, ein Webhook, `mail` — ist eine Frage des Umschreibens
dieses einen `curl`. Eine Neuinstallation behält Ihre `notify.sh`.

Über die Limits selbst wird nie benachrichtigt: Sie sind Alltag, die Fortsetzung
kümmert sich darum, und eine Nachricht pro Fall wäre nur Lärm.

## Dateien

| Pfad | Beschreibung |
|------|--------------|
| `~/.claude/claude-plus/claude-plus.sh` | Hauptskript |
| `~/.claude/claude-plus/state/` | Reset-Zeiten, Job-ID, Fehlerzähler, Auth-Flag |
| `~/.claude/claude-plus/state/pending/` | Am Limit gestoppte Sitzungen, die auf Fortsetzung warten |
| `~/.claude/claude-plus/state/stale/` | Verworfene Einträge, weil sich das Pane geändert hat |
| `~/.claude/claude-plus/original-statusline-command` | Ihr bisheriger Status-Line-Befehl |
| `~/.claude/claude-plus/notify.sh` | Ihr Benachrichtigungsskript, falls eingerichtet |
| `~/.claude/claude-plus/notify/` | Vorlagen zum Kopieren |
| `~/.claude/claude-plus/claude-plus.log` | Protokoll |

## Deinstallation

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<Zeitstempel> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```

## Lizenz

GPL-3.0-or-later. Siehe [LICENSE](LICENSE).
