# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | Italiano | [Português](README.pt.md) | [العربية](README.ar.md)

Due cose che Claude Code non fa al posto tuo, sbrigate mentre sei lontano dalla tastiera.

- **Finestra sempre aperta** — appena l'ultima finestra da 5 ore si azzera se ne apre una nuova, anche se nessuno sta usando Claude Code: quando torni, una quota piena è già in corso.
- **Avviso** — quando questo smette di funzionare te lo dice: Bark, ntfy, email o qualunque altro canale tu voglia collegare.

Riprendere una sessione dopo un limite d'uso è una cosa che ora Claude Code fa da solo: vedi "Continue automatically at usage limit" in `/config`. Claude Plus lo faceva anche prima della 3.0.0, e da allora lo lascia a Claude Code.

## A cosa serve

**Quando si apre la finestra decide quando finisce.** Una finestra da 5 ore parte dalla tua prima richiesta, non a un'ora fissa. Inizi a lavorare alle 9:00 e la finestra va dalle 9:00 alle 14:00; esaurisci la quota alle 11:00 e resti fuori fino alle 14:00. Se invece una minuscola richiesta avesse aperto la finestra alle 6:00, questa scadrebbe alle 11:00 — esattamente quando rimani a secco — con una quota nuova già pronta. Con una finestra sempre attiva, quando inizi ce n'è già una in corso: ciò che ne resta è quota che altrimenti andrebbe sprecata, e una nuova arriva al massimo tra cinque ore, di solito molto prima.

**Sapere quando ha smesso di aiutarti.** Tenere aperte le finestre funziona solo finché il tuo accesso è valido e il pianificatore è attivo; se uno dei due si ferma, non succede più nulla. Claude Plus riconosce entrambi i casi e te lo dice, invece di fallire in silenzio per tutto il fine settimana.

## Requisiti

Linux, con `claude`, `jq`, `at` (con `atd` attivo), `flock`, `timeout`, GNU `date`.

```bash
sudo systemctl enable --now atd
```

## Installazione

```bash
npx @claude-plus/claude-plus
```

Oppure da un clone:

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

L'installatore avvolge la tua status line esistente, che si vede esattamente come prima; è l'unica modifica che fa alle tue impostazioni. Il `settings.json` viene salvato prima, e rieseguire l'installatore è un aggiornamento pulito anziché una seconda copia. Un aggiornamento conserva la prossima esecuzione pianificata, il suo stato e il tuo notificatore. L'aggiornamento dalla 2.x rimuove anche gli hook che quelle versioni aggiungevano per riprendere le sessioni.

## Uso

Nel quotidiano non c'è nulla da eseguire — lavora da solo. Quando vuoi dare un'occhiata:

```bash
~/.claude/claude-plus/claude-plus.sh status   # il pianificatore è attivo, cosa è pianificato, l'accesso è ancora valido
tail -f ~/.claude/claude-plus/claude-plus.log # cosa ha fatto
```

## Aprire a un'ora fissa

Per impostazione predefinita una finestra si apre appena la precedente si azzera, quindi la catena segue l'ora in cui hai finito la quota l'ultima volta. Per fissarla a un'ora del giorno:

```bash
~/.claude/claude-plus/claude-plus.sh anchor 06:00   # apri alle 06:00
~/.claude/claude-plus/claude-plus.sh anchor         # mostra l'impostazione
~/.claude/claude-plus/claude-plus.sh anchor off     # torna ad aprire appena possibile
```

Una finestra che passerebbe sopra quell'ora la aspetta: quella prevista alle 03:00 coprirebbe 03:00-08:00 inghiottendo le 06:00, quindi si apre alle 06:00. Le ore prima restano senza finestra — se lavori in quel momento, la tua prima richiesta ne apre una come sempre.

## Avvisi

Claude Plus resta in silenzio finché non serve il tuo intervento, e segnala quattro cose:

| | |
|---|---|
| **Disconnesso** | Il tuo accesso a Claude Code è scaduto: finché non rientri non si può aprire nulla |
| **Fallimenti ripetuti** | Diversi warm-up di fila sono falliti |
| **Pianificatore fermo** | Un'esecuzione pianificata è molto in ritardo, quindi nessuna finestra viene tenuta aperta; di solito `atd` non è in esecuzione |
| **Tornato normale** | Si è ripreso da uno dei casi sopra |

Ogni cosa viene segnalata una volta sola, non a ogni nuovo tentativo: un problema notturno ti costa un unico messaggio. I limiti d'uso in sé non vengono mai annunciati: sono ordinaria amministrazione, e Claude Code riprende da solo dopo di essi.

Per scegliere come riceverlo, copia uno degli esempi e inserisci la tua chiave o il tuo server:

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh      # oppure ntfy.sh.sample, email.sh.sample
chmod +x notify.sh                      # 700 per quello email, contiene una password
$EDITOR notify.sh
./claude-plus.sh notify-test            # verifica che ti arrivi
```

Il notificatore è solo un eseguibile che riceve `CP_EVENT`, `CP_MESSAGE` e `CP_HOST`, quindi Telegram, Slack, un webhook o `mail` si riducono a riscrivere una riga. La tua copia sopravvive alle reinstallazioni.

## File

Sta tutto sotto `~/.claude/claude-plus/`:

| | |
|---|---|
| `claude-plus.sh` | Lo script stesso |
| `notify.sh` | Il tuo notificatore, una volta configurato |
| `notify/` | Esempi da copiare |
| `anchor` | L'ora a cui si aprono le finestre, se ne hai impostata una |
| `claude-plus.log` | Cosa ha fatto |
| `state/` | Contabilità interna |

## Disinstallazione

```bash
npx @claude-plus/claude-plus uninstall
```

Oppure da un clone: `bash install-claude-plus.sh uninstall`.

Modifica sul posto il tuo `settings.json` attuale e toglie solo ciò che Claude Plus ha aggiunto: la tua status line torna com'era, e ogni altra impostazione e hook resta esattamente com'è — compresi quelli aggiunti dopo aver installato Claude Plus. I suoi job pianificati vengono annullati e `~/.claude/claude-plus/` viene eliminato, insieme al tuo `notify.sh`. Eseguirla una seconda volta non fa alcun danno.

Se nel frattempo un altro programma ha avvolto la tua status line attorno a Claude Plus, la disinstallazione non lo rompe. Resta un piccolo script di passaggio perché quel programma continui a funzionare, e il disinstallatore te lo segnala; eseguilo di nuovo quando non serve più a nulla. Un aggiornamento nella stessa situazione resta dentro la catena di quel programma invece di avvolgerlo a sua volta.

Una copia di `settings.json` di subito prima della disinstallazione resta lì accanto, così come le copie fatte all'installazione, nel caso ti serva mai tornare indietro a mano.

## Licenza

GPL-3.0-or-later. Vedi [LICENSE](LICENSE).
