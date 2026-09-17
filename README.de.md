# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | Deutsch | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Zwei Dinge, die Claude Code nicht für Sie erledigt — erledigt, während Sie nicht an der Tastatur sitzen.

- **Fenster offen halten** — sobald das letzte 5-Stunden-Fenster zurückgesetzt wird, öffnet sich ein neues, auch wenn gerade niemand Claude Code benutzt; wenn Sie zurückkommen, läuft schon ein volles Kontingent.
- **Benachrichtigen** — funktioniert das nicht mehr, sagt es Ihnen Bescheid: Bark, ntfy, E-Mail oder was immer Sie anschließen möchten.

Eine Sitzung nach einem Nutzungslimit wieder aufzunehmen, erledigt Claude Code inzwischen selbst: siehe „Continue automatically at usage limit“ in `/config`. Claude Plus hat das vor 3.0.0 ebenfalls getan und überlässt es seitdem Claude Code.

## Wozu das gut ist

**Wann das Fenster öffnet, entscheidet, wann es endet.** Ein 5-Stunden-Fenster beginnt mit Ihrer ersten Anfrage, nicht zu einer festen Uhrzeit. Beginnen Sie um 9:00 zu arbeiten, läuft das Fenster von 9:00 bis 14:00; ist das Kontingent um 11:00 aufgebraucht, sind Sie bis 14:00 ausgesperrt. Hätte stattdessen eine winzige Anfrage das Fenster um 6:00 geöffnet, liefe es um 11:00 ab — genau dann, wenn Ihnen der Vorrat ausgeht — und ein frisches Kontingent stünde bereit. Läuft ständig ein Fenster, ist beim Arbeitsbeginn schon eines im Gang: Was davon übrig ist, wäre sonst ungenutzt verfallen, und ein frisches Kontingent ist höchstens fünf Stunden entfernt, meist viel weniger.

**Erkennen, wann es nicht mehr hilft.** Fenster offen zu halten funktioniert nur, solange Ihre Anmeldung gültig ist und der Planer läuft; fällt eines davon aus, passiert gar nichts. Claude Plus bemerkt beides und sagt es Ihnen, statt ein ganzes Wochenende lang still zu scheitern.

## Voraussetzungen

Linux mit `claude`, `jq`, `at` (mit laufendem `atd`), `flock`, `timeout`, GNU `date`.

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

Der Installer legt sich um Ihre bestehende Status Line, die genau wie bisher angezeigt wird; das ist die einzige Änderung an Ihren Einstellungen. `settings.json` wird zuvor gesichert, und ein erneuter Lauf ist ein sauberes Upgrade statt einer zweiten Installation. Ein Upgrade übernimmt den nächsten geplanten Lauf, seinen Zustand und Ihren Benachrichtiger. Beim Upgrade von 2.x werden außerdem die Hooks entfernt, die jene Versionen zum Fortsetzen von Sitzungen angelegt haben.

## Verwendung

Im Alltag gibt es nichts auszuführen — es arbeitet von selbst. Wenn Sie nachsehen möchten:

```bash
~/.claude/claude-plus/claude-plus.sh status   # ob der Planer läuft, was geplant ist, ob die Anmeldung noch gilt
tail -f ~/.claude/claude-plus/claude-plus.log # was es getan hat
```

## Benachrichtigungen

Claude Plus bleibt still, solange nichts Ihre Aufmerksamkeit braucht, und meldet vier Dinge:

| | |
|---|---|
| **Abgemeldet** | Ihre Claude-Code-Anmeldung ist abgelaufen; bis Sie sich neu anmelden, lässt sich nichts öffnen |
| **Wiederholt fehlgeschlagen** | Mehrere Warm-ups hintereinander sind fehlgeschlagen |
| **Planer steht** | Ein geplanter Lauf ist längst überfällig, es wird also kein Fenster offen gehalten; meist läuft `atd` nicht |
| **Wieder normal** | Es hat sich von einem der obigen Fälle erholt |

Jede Meldung kommt einmal, nicht bei jedem Wiederholungsversuch — ein nächtliches Problem kostet Sie also eine einzige Nachricht. Über Nutzungslimits selbst wird nie berichtet: Sie sind Alltag, und Claude Code macht danach von selbst weiter.

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
