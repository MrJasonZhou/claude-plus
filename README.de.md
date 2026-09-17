# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | Deutsch | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Drei Dinge, die Claude Code nicht für Sie erledigt — erledigt, während Sie nicht an der Tastatur sitzen.

- **Fortsetzen** — eine Sitzung, die an einem Limit gestoppt ist, startet sich in dem Moment neu, in dem das Limit zurückgesetzt wird, und führt die begonnene Arbeit weiter.
- **Fenster offen halten** — gibt es nichts fortzusetzen, wird trotzdem ein neues 5-Stunden-Fenster geöffnet, damit sein Reset außerhalb Ihrer Arbeitszeit liegt statt mittendrin.
- **Benachrichtigen** — kommt es allein nicht weiter, sagt es Ihnen Bescheid: Bark, ntfy, E-Mail oder was immer Sie anschließen möchten.

## Wozu das gut ist

**Erholung von einem 5-Stunden-Limit.** Normalerweise bleibt die Sitzung am Limit einfach stehen, und Sie starten sie später von Hand neu. Claude Plus startet sie in dem Augenblick neu, in dem das Limit zurückgesetzt wird, sodass die Arbeit dort weiterläuft, wo sie aufgehört hat — auch während Sie schlafen oder nicht am Schreibtisch sind.

**Wann das Fenster öffnet, entscheidet, wann es endet.** Ein 5-Stunden-Fenster beginnt mit Ihrer ersten Anfrage, nicht zu einer festen Uhrzeit. Beginnen Sie um 9:00 zu arbeiten, läuft das Fenster von 9:00 bis 14:00; ist das Kontingent um 11:00 aufgebraucht, sind Sie bis 14:00 ausgesperrt. Hätte stattdessen eine winzige Anfrage das Fenster um 6:00 geöffnet, liefe es um 11:00 ab — genau dann, wenn Ihnen der Vorrat ausgeht — und ein frisches Kontingent stünde bereit. Ein dauerhaft laufendes Fenster schiebt seinen Reset vor Ihre Arbeitszeit statt mitten hinein.

**Erkennen, wann es nicht mehr hilft.** Die automatische Wiederaufnahme funktioniert nur, solange Ihre Anmeldung gültig ist; läuft sie ab, geht gar nichts mehr. Claude Plus bemerkt diesen Fall und sagt es Ihnen, statt ein ganzes Wochenende lang still zu scheitern.

## Was es nicht tut

Fortsetzen heißt, in das Terminal zu tippen, in dem Sie gearbeitet haben — deshalb ist es sehr vorsichtig damit, wohin es tippt. Eine Sitzung wird nur fortgesetzt, wenn sie noch da ist, unberührt und genau so, wie das Limit sie hinterlassen hat. Haben Sie sie geschlossen, sich anderem zugewandt oder in jenem Terminal etwas anderes gestartet, lässt Claude Plus sie in Ruhe und bleibt still. Sitzungen außerhalb von tmux werden überhaupt nie fortgesetzt — dort gibt es nichts, wohin getippt werden könnte.

Über die Limits selbst wird nie berichtet. Sie sind Alltag, die Wiederaufnahme kümmert sich darum, und eine Nachricht pro Fall wäre nur Lärm.

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

Der Installer übernimmt Ihre Status Line und fügt eigene Hooks hinzu; Ihre bisherige Status Line bleibt erhalten und fremde Hooks bleiben unangetastet. `settings.json` wird zuvor gesichert, und ein erneuter Lauf ist ein sauberes Upgrade statt einer zweiten Installation.

## Verwendung

Im Alltag gibt es nichts auszuführen — es arbeitet von selbst. Wenn Sie nachsehen möchten:

```bash
~/.claude/claude-plus/claude-plus.sh status   # was geplant ist, was wartet, ob die Anmeldung noch gilt
~/.claude/claude-plus/claude-plus.sh pending  # Sitzungen, die auf Fortsetzung warten
tail -f ~/.claude/claude-plus/claude-plus.log # was es getan hat
```

## Benachrichtigungen

Claude Plus bleibt still, solange nichts Ihre Aufmerksamkeit braucht, und meldet genau drei Dinge:

| | |
|---|---|
| **Abgemeldet** | Ihre Claude-Code-Anmeldung ist abgelaufen; bis Sie sich neu anmelden, lässt sich nichts öffnen |
| **Wiederholt fehlgeschlagen** | Mehrere Warm-ups hintereinander sind fehlgeschlagen |
| **Wieder normal** | Es hat sich von einem der beiden Fälle erholt |

Jede Meldung kommt einmal, nicht bei jedem Wiederholungsversuch — ein nächtliches Problem kostet Sie also eine einzige Nachricht.

Um zu wählen, wie Sie davon erfahren, kopieren Sie eine der Vorlagen und tragen Ihren eigenen Schlüssel oder Server ein:

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh      # oder ntfy.sh.sample, email.sh.sample
chmod +x notify.sh                      # für die E-Mail-Variante 700, sie enthält ein Passwort
$EDITOR notify.sh
./claude-plus.sh notify-test            # prüfen, ob es Sie erreicht
```

Der Benachrichtiger ist nur eine ausführbare Datei, die `CP_EVENT`, `CP_MESSAGE` und `CP_HOST` erhält. Telegram, Slack, ein Webhook oder `mail` sind daher eine Frage einer einzigen Zeile. Ihre Fassung übersteht Neuinstallationen.

## Dateien

Alles liegt unter `~/.claude/claude-plus/`:

| | |
|---|---|
| `claude-plus.sh` | Das Skript selbst |
| `notify.sh` | Ihr Benachrichtiger, sobald Sie einen einrichten |
| `notify/` | Vorlagen zum Kopieren |
| `claude-plus.log` | Was es getan hat |
| `state/` | Interne Buchführung |

## Deinstallation

```bash
npx @claude-plus/claude-plus uninstall
```

Oder aus einem Klon: `bash install-claude-plus.sh uninstall`.

Es bearbeitet Ihre aktuelle `settings.json` direkt und entfernt nur, was Claude Plus hinzugefügt hat: Ihre eigene Status Line kommt zurück, und alle anderen Einstellungen und Hooks bleiben genau so, wie sie sind — auch solche, die nach der Installation von Claude Plus dazugekommen sind. Die geplanten Jobs werden abgebrochen und `~/.claude/claude-plus/` wird gelöscht, Ihre `notify.sh` mit ihm. Ein zweiter Aufruf richtet keinen Schaden an.

Hat inzwischen ein anderes Programm Ihre Status Line um Claude Plus herum gelegt, macht die Deinstallation es nicht kaputt. Ein kleines Durchreich-Skript bleibt zurück, damit jenes Programm weiter funktioniert, und der Deinstaller weist darauf hin; führen Sie ihn erneut aus, sobald es nicht mehr gebraucht wird. Ein Upgrade in derselben Lage bleibt innerhalb der Kette jenes Programms, statt es seinerseits einzuwickeln.

Eine Kopie der `settings.json` von unmittelbar vor der Deinstallation bleibt daneben liegen, ebenso die bei der Installation angelegten Kopien — für den Fall, dass Sie je von Hand zurückwollen.

## Lizenz

GPL-3.0-or-later. Siehe [LICENSE](LICENSE).
