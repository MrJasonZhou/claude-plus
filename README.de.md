# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | Deutsch | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Zwei Dinge, die Ihr Coding-Agent nicht für Sie erledigt — erledigt, während Sie nicht an der Tastatur sitzen.

- **Fenster offen halten** — sobald das letzte Nutzungsfenster zurückgesetzt wird, öffnet sich ein neues, auch wenn gerade niemand arbeitet; wenn Sie zurückkommen, läuft schon ein volles Kontingent.
- **Benachrichtigen** — funktioniert das nicht mehr, sagt es Ihnen Bescheid: Bark, ntfy, E-Mail oder was immer Sie anschließen möchten.

Eine Sitzung nach einem Nutzungslimit wieder aufzunehmen, erledigen die Agenten inzwischen selbst, also überlässt Claude Plus ihnen das.

## Agenten

Claude Code, Codex und Antigravity messen ein Abo auf dieselbe Weise: ein kurzes Fenster, das mit Ihrer ersten Anfrage beginnt, und darüber ein längeres. Claude Plus hält offen, was bei Ihnen installiert ist.

| Agent | Woher die Limits kommen | Änderungen an seiner Konfiguration |
|---|---|---|
| Claude Code | seine Status Line, bei jeder Aktualisierung | ein Status-Line-Eintrag |
| Codex | seine Sitzungsprotokolle, bei Bedarf gelesen | keine |
| Antigravity | seine Status Line, bei jeder Aktualisierung | ein Status-Line-Eintrag |

Jeder Agent bekommt sein eigenes Fenster, seinen eigenen Zeitplan und seine eigenen Meldungen; nichts wird geteilt. Einen weiteren hinzuzufügen ist eine Datei — siehe [docs/PROVIDERS.md](docs/PROVIDERS.md). Dass die Schnittstelle die Art der Messung ausdrücklich nennt, hat einen Grund: Bei Kimi Code begrenzt das kurze Fenster die Rate der Anfragen statt ein Kontingent zu messen, und Grok Build hat einen Wochentopf und gar kein kurzes Fenster — da gäbe es nichts offen zu halten.

## Wozu das gut ist

**Wann das Fenster öffnet, entscheidet, wann es endet.** Ein Fenster beginnt mit Ihrer ersten Anfrage, nicht zu einer festen Uhrzeit. Bei einem Fünf-Stunden-Fenster: Beginnen Sie um 9:00 zu arbeiten, läuft es von 9:00 bis 14:00; ist das Kontingent um 11:00 aufgebraucht, sind Sie bis 14:00 ausgesperrt. Hätte stattdessen eine winzige Anfrage das Fenster um 6:00 geöffnet, liefe es um 11:00 ab — genau dann, wenn Ihnen der Vorrat ausgeht — und ein frisches Kontingent stünde bereit. Läuft ständig ein Fenster, ist beim Arbeitsbeginn schon eines im Gang: Was davon übrig ist, wäre sonst ungenutzt verfallen, und ein frisches Kontingent ist höchstens ein Fenster entfernt, meist viel weniger.

**Erkennen, wann es nicht mehr hilft.** Fenster offen zu halten funktioniert nur, solange eine Anmeldung gültig ist und der Planer läuft; fällt eines davon aus, passiert gar nichts. Claude Plus bemerkt beides und sagt es Ihnen, statt ein ganzes Wochenende lang still zu scheitern.

## Voraussetzungen

Linux mit `jq`, `at` (mit laufendem `atd`), `flock`, `timeout`, GNU `date` und mindestens einem von `claude`, `codex` oder `agy`.

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

Für jeden Agenten mit einer Status Line legt sich der Installer um die, die Sie bereits hatten, und die wird genau wie bisher angezeigt; das ist die einzige Änderung an den Einstellungen jenes Agenten, und jede Einstellungsdatei wird zuvor gesichert. Codex braucht überhaupt keine Konfiguration. Ein erneuter Lauf ist ein sauberes Upgrade statt einer zweiten Installation und übernimmt für jeden Agenten den nächsten geplanten Lauf, seinen Zustand und Ihren Benachrichtiger.

## Verwendung

Im Alltag gibt es nichts auszuführen — es arbeitet von selbst. Wenn Sie nachsehen möchten:

```bash
~/.claude/claude-plus/claude-plus.sh status    # je Agent: Fenster, Zeitplan, Fehlschläge
~/.claude/claude-plus/claude-plus.sh providers # welche Agenten installiert sind
tail -f ~/.claude/claude-plus/claude-plus.log  # was es getan hat
```

## Zu einer festen Uhrzeit öffnen

Standardmäßig öffnet ein Fenster, sobald das letzte zurückgesetzt wird; die Kette folgt also dem Zeitpunkt, an dem Sie zuletzt nichts mehr hatten. Um sie stattdessen an eine Uhrzeit zu binden:

```bash
~/.claude/claude-plus/claude-plus.sh anchor 06:00   # um 06:00 öffnen
~/.claude/claude-plus/claude-plus.sh anchor         # die Einstellung anzeigen
~/.claude/claude-plus/claude-plus.sh anchor off     # wieder öffnen, sobald es geht
```

Ein Fenster, das über diese Uhrzeit hinweglaufen würde, wartet stattdessen auf sie: eines, das um 03:00 fällig wäre, deckte 03:00-08:00 ab und verschlänge 06:00, also öffnet es um 06:00. Die Stunden davor bleiben dann ohne Fenster — arbeiten Sie darin, öffnet Ihre eigene erste Anfrage wie gewohnt eines. Die Uhrzeit gilt für alle Agenten.

## Benachrichtigungen

Claude Plus bleibt still, solange nichts Ihre Aufmerksamkeit braucht, und meldet vier Dinge:

| | |
|---|---|
| **Abgemeldet** | Die Anmeldung eines Agenten ist abgelaufen; für ihn lässt sich nichts öffnen, bis Sie sich neu anmelden |
| **Wiederholt fehlgeschlagen** | Mehrere Warm-ups hintereinander sind für einen Agenten fehlgeschlagen |
| **Planer steht** | Ein geplanter Lauf ist längst überfällig, es wird also kein Fenster offen gehalten; meist läuft `atd` nicht |
| **Wieder normal** | Es hat sich von einem der obigen Fälle erholt |

Jede Meldung kommt einmal je Agent, nicht bei jedem Wiederholungsversuch — ein nächtliches Problem kostet Sie also eine einzige Nachricht. Über Nutzungslimits selbst wird nie berichtet: Sie sind Alltag, und die Agenten machen danach von selbst weiter.

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
| `providers/` | Eine Datei je Agent |
| `state/<Agent>/` | Fenster, Zeitplan und Meldungszustand jenes Agenten |
| `notify.sh` | Ihr Benachrichtiger, sobald Sie einen einrichten |
| `notify/` | Vorlagen zum Kopieren |
| `anchor` | Die Uhrzeit, zu der Fenster öffnen, falls gesetzt |
| `claude-plus.log` | Was es getan hat |

## Deinstallation

```bash
npx @claude-plus/claude-plus uninstall
```

Oder aus einem Klon: `bash install-claude-plus.sh uninstall`.

Es bearbeitet die Einstellungen jedes Agenten direkt und entfernt nur, was Claude Plus hinzugefügt hat: Ihre Status Line kommt zurück, und alle anderen Einstellungen bleiben genau so, wie sie sind — auch solche, die nach der Installation dazugekommen sind. Die geplanten Jobs werden abgebrochen und `~/.claude/claude-plus/` wird gelöscht, Ihre `notify.sh` mit ihm. Ein zweiter Aufruf richtet keinen Schaden an.

Hat inzwischen ein anderes Programm eine Status Line um Claude Plus herum gelegt, macht die Deinstallation es nicht kaputt. Ein kleines Durchreich-Skript bleibt zurück, damit jenes Programm weiter funktioniert, und der Deinstaller weist darauf hin; führen Sie ihn erneut aus, sobald es nicht mehr gebraucht wird. Ein Upgrade in derselben Lage bleibt innerhalb der Kette jenes Programms, statt es seinerseits einzuwickeln.

Eine Kopie jeder Einstellungsdatei von unmittelbar vor der Deinstallation bleibt daneben liegen, ebenso die bei der Installation angelegten Kopien — für den Fall, dass Sie je von Hand zurückwollen.

## Lizenz

GPL-3.0-or-later. Siehe [LICENSE](LICENSE).
