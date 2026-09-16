# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | Italiano | [Português](README.pt.md) | [العربية](README.ar.md)

Estensioni per Claude Code, guidate da job `at`:

- **Ripresa** — quando una sessione si ferma su un limite d'uso dentro tmux, `continue` viene digitato in quel pane appena il limite si azzera.
- **Mantenimento** — se non c'è nulla da riprendere, una minuscola richiesta Haiku apre una nuova finestra da 5 ore.

## A cosa serve

**Ripartire dopo un limite di 5 ore.** Di norma toccare il tetto significa che la sessione si ferma e basta, e più tardi torni a riavviarla a mano. Qui `continue` viene digitato nel pane nell'istante in cui il limite si azzera, così il lavoro riprende da dove si era interrotto — anche mentre dormi o sei lontano dalla scrivania.

**Quando si apre la finestra decide quando finisce.** Una finestra da 5 ore parte dalla tua prima richiesta, non a un'ora fissa. Inizi a lavorare alle 9:00 e la finestra va dalle 9:00 alle 14:00; esaurisci la quota alle 11:00 e resti fuori fino alle 14:00. Se invece una minuscola richiesta avesse aperto la finestra alle 6:00, questa scadrebbe alle 11:00 — esattamente quando rimani a secco — con una quota nuova già pronta. Tenere sempre una finestra aperta sposta il suo azzeramento prima dell'orario di lavoro invece che nel bel mezzo.

## Come funziona

1. L'installazione riscrive `~/.claude/settings.json`: `statusLine` più tre hook — `StopFailure` (matcher `rate_limit`), `UserPromptSubmit`, `SessionEnd`. Il comando di status line già presente viene salvato e continua a essere mostrato.
2. Ogni aggiornamento della status line legge `rate_limits.five_hour.resets_at` e pianifica un job `at` per l'azzeramento + 15 s.
3. Il raggiungimento di un limite registra la sessione (socket tmux, pane, finestra, `pane_current_command`, cwd) sotto `state/pending/` e pianifica lo stesso job.
4. All'azzeramento il job esegue `scheduled`:
   - Sessioni in attesa → `send-keys continue` verso ogni pane, al massimo 2 tentativi per sessione, poi nuova verifica dopo 90 s.
   - Niente in attesa → `claude -p --model haiku --safe-mode --tools "" 'Reply only OK.'`, e il job successivo viene stimato a 5 h + 15 s dall'inizio della richiesta.
5. Le voci in attesa vengono cancellate appena digiti qualcosa tu (`UserPromptSubmit`) o la sessione termina (`SessionEnd`).
6. Limite di 7 giorni al 100% → tutto attende invece l'azzeramento settimanale.

### Protezioni

Un `continue` viene inviato solo se il pane esiste ancora, appartiene ancora alla stessa sessione tmux ed esegue ancora lo stesso comando di quando è scattato il limite. Altrimenti la voce finisce archiviata in `state/stale/` e non viene digitato nulla. Le sessioni fuori da tmux vengono solo registrate nel log — non c'è alcun pane in cui scrivere.

Un warm-up fallito viene ritentato dopo 60 s / 120 s / 300 s / 600 s. Se l'output sembra un login scaduto, il warm-up automatico si mette in pausa, viene scritto `state/auth_required` (`status` mostra `RELOGIN MAY BE REQUIRED`) e si ricontrolla dopo un'ora.

## Requisiti

`claude`, `jq`, `at` (con `atd` attivo), `flock`, `timeout`, `tmux`, GNU `date`.

```bash
sudo systemctl enable --now atd
```

## Installazione

```bash
npx @mrjasonzhou/claude-plus
```

Oppure da un clone:

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

Ogni installazione precedente viene rimossa per prima — i suoi job `at`, le sue voci `statusLine` e di hook, e `~/.claude/claude-plus/` — così rieseguire l'installatore equivale a un aggiornamento pulito. Gli hook di altri strumenti restano intatti. `settings.json` viene salvato come `settings.json.claude-plus-install-backup.<timestamp>`.

Poi, dentro Claude Code, verifica con `/hooks` la presenza di `StopFailure`, `UserPromptSubmit` e `SessionEnd`.

## Uso

```bash
~/.claude/claude-plus/claude-plus.sh status   # versione, pianificazione, in attesa, stato autenticazione
~/.claude/claude-plus/claude-plus.sh pending  # sessioni in attesa di ripresa
~/.claude/claude-plus/claude-plus.sh notify-test  # inviarsi una notifica di prova
tail -f ~/.claude/claude-plus/claude-plus.log # log
```

## Notifiche

Claude Plus resta in silenzio finché non serve il tuo intervento. Esegue
`~/.claude/claude-plus/notify.sh` — un eseguibile qualsiasi — su tre eventi:

| Evento | Quando |
|--------|--------|
| `auth-required` | Claude Code è disconnesso, non si può aprire nessuna finestra |
| `warmup-failing` | Tre warm-up falliti di fila |
| `recovered` | I warm-up tornano a riuscire dopo uno dei due casi |

Ogni evento scatta una sola volta all'ingresso in quello stato, non a ogni nuovo
tentativo: un problema notturno ti costa un messaggio invece di otto.

Esempi per Bark, ntfy e email SMTP vengono installati in
`~/.claude/claude-plus/notify/`. Scegline uno, inserisci la tua chiave o il tuo
server e provalo:

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh
chmod +x notify.sh          # 700 per quello email, contiene una password
$EDITOR notify.sh
./claude-plus.sh notify-test
```

Lo script viene eseguito con `CP_EVENT`, `CP_MESSAGE` e `CP_HOST` nel suo ambiente,
quindi qualsiasi altra cosa — Telegram, Slack, un webhook, `mail` — si riduce a
riscrivere quell'unico `curl`. Una reinstallazione conserva il tuo `notify.sh`.

I limiti d'uso in sé non vengono mai notificati: sono ordinaria amministrazione, ci
pensa la ripresa, e un messaggio ogni volta sarebbe solo rumore.

## File

| Percorso | Descrizione |
|----------|-------------|
| `~/.claude/claude-plus/claude-plus.sh` | Script principale |
| `~/.claude/claude-plus/state/` | Orari di azzeramento, id del job, conteggio fallimenti, flag di autenticazione |
| `~/.claude/claude-plus/state/pending/` | Sessioni fermate da un limite, in attesa di ripresa |
| `~/.claude/claude-plus/state/stale/` | Voci scartate perché il pane è cambiato |
| `~/.claude/claude-plus/original-statusline-command` | Il tuo precedente comando di status line |
| `~/.claude/claude-plus/notify.sh` | Il tuo script di notifica, se ne hai installato uno |
| `~/.claude/claude-plus/notify/` | Esempi di script da copiare |
| `~/.claude/claude-plus/claude-plus.log` | Log |

## Disinstallazione

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<timestamp> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```

## Licenza

GPL-3.0-or-later. Vedi [LICENSE](LICENSE).
