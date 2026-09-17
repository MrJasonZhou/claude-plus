# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | Italiano | [Português](README.pt.md) | [العربية](README.ar.md)

Tre cose che Claude Code non fa al posto tuo, sbrigate mentre sei lontano dalla tastiera.

- **Ripresa** — una sessione fermata da un limite d'uso riparte da sola nell'istante in cui il limite si azzera, continuando il lavoro lasciato a metà.
- **Finestra sempre aperta** — se non c'è nulla da riprendere, viene comunque aperta una nuova finestra da 5 ore, così il suo azzeramento cade fuori dal tuo orario di lavoro anziché nel mezzo.
- **Avviso** — quando non riesce più ad andare avanti da solo te lo dice: Bark, ntfy, email o qualunque altro canale tu voglia collegare.

## A cosa serve

**Ripartire dopo un limite di 5 ore.** Di norma toccare il tetto significa che la sessione si ferma e basta, e più tardi torni a riavviarla a mano. Claude Plus la riavvia per te nell'istante in cui il limite si azzera, così il lavoro riprende da dove si era interrotto — anche mentre dormi o sei lontano dalla scrivania.

**Quando si apre la finestra decide quando finisce.** Una finestra da 5 ore parte dalla tua prima richiesta, non a un'ora fissa. Inizi a lavorare alle 9:00 e la finestra va dalle 9:00 alle 14:00; esaurisci la quota alle 11:00 e resti fuori fino alle 14:00. Se invece una minuscola richiesta avesse aperto la finestra alle 6:00, questa scadrebbe alle 11:00 — esattamente quando rimani a secco — con una quota nuova già pronta. Tenere sempre una finestra aperta sposta il suo azzeramento prima dell'orario di lavoro invece che nel bel mezzo.

**Sapere quando ha smesso di aiutarti.** Il recupero automatico funziona finché il tuo accesso è valido; una volta scaduto non funziona più nulla. Claude Plus riconosce questo caso e te lo dice, invece di fallire in silenzio per tutto il fine settimana.

## Cosa non farà

Riprendere significa scrivere nel terminale in cui stavi lavorando, perciò sta molto attento a dove scrive. Una sessione viene ripresa solo se è ancora lì, intatta, esattamente come il limite l'ha lasciata. Se l'hai chiusa, sei passato ad altro o hai avviato qualcos'altro in quel terminale, Claude Plus non la tocca e resta in silenzio. Le sessioni fuori da tmux non vengono mai riprese — non c'è alcun posto dove scrivere.

I limiti d'uso in sé non vengono mai annunciati. Sono ordinaria amministrazione, ci pensa la ripresa, e un messaggio ogni volta sarebbe solo rumore.

## Requisiti

Linux, con `claude`, `jq`, `at` (con `atd` attivo), `flock`, `timeout`, `tmux`, GNU `date`.

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

L'installatore avvolge la tua status line esistente, che si vede esattamente come prima, e aggiunge i propri hook, senza toccare quelli di altri strumenti. Il `settings.json` viene salvato prima, e rieseguire l'installatore è un aggiornamento pulito anziché una seconda copia. Un aggiornamento porta con sé tutto ciò che è in corso: le sessioni in attesa di ripresa, la prossima esecuzione pianificata e il tuo notificatore.

## Uso

Nel quotidiano non c'è nulla da eseguire — lavora da solo. Quando vuoi dare un'occhiata:

```bash
~/.claude/claude-plus/claude-plus.sh status   # cosa è pianificato, cosa attende, l'accesso è ancora valido
~/.claude/claude-plus/claude-plus.sh pending  # sessioni in attesa di ripresa
tail -f ~/.claude/claude-plus/claude-plus.log # cosa ha fatto
```

## Avvisi

Claude Plus resta in silenzio finché non serve il tuo intervento, e segnala esattamente tre cose:

| | |
|---|---|
| **Disconnesso** | Il tuo accesso a Claude Code è scaduto: finché non rientri non si può aprire nulla |
| **Fallimenti ripetuti** | Diversi warm-up di fila sono falliti |
| **Tornato normale** | Si è ripreso da uno dei due casi sopra |

Ogni cosa viene segnalata una volta sola, non a ogni nuovo tentativo: un problema notturno ti costa un unico messaggio.

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
