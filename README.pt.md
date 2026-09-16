# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | Português | [العربية](README.ar.md)

Extensões para o Claude Code, movidas por tarefas `at`:

- **Retomada** — quando uma sessão para num limite de uso dentro do tmux, `continue` é digitado nesse pane assim que o limite é reiniciado.
- **Manutenção** — se não há nada a retomar, um pedido Haiku mínimo abre uma nova janela de 5 horas.

## Para que serve

**Recuperar de um limite de 5 horas.** Normalmente, atingir o teto significa que a sessão simplesmente para e você volta mais tarde para reiniciá-la à mão. Aqui o `continue` é digitado no pane no instante em que o limite é reiniciado, então o trabalho segue de onde parou — inclusive enquanto você dorme ou está longe da mesa.

**Quando a janela abre decide quando ela termina.** Uma janela de 5 horas começa no seu primeiro pedido, não numa hora fixa. Comece a trabalhar às 9h e a janela vai das 9h às 14h; esgote a cota às 11h e você fica travado até as 14h. Se em vez disso um pedido mínimo tivesse aberto a janela às 6h, ela expiraria às 11h — exatamente quando você fica sem nada — com uma cota nova já esperando. Manter uma janela sempre aberta empurra o reinício para antes do seu horário de trabalho, em vez de deixá-lo no meio dele.

## Como funciona

1. A instalação reescreve `~/.claude/settings.json`: `statusLine` e três hooks — `StopFailure` (matcher `rate_limit`), `UserPromptSubmit`, `SessionEnd`. Seu comando de status line existente é guardado e continua sendo exibido.
2. Cada atualização da status line lê `rate_limits.five_hour.resets_at` e agenda uma tarefa `at` para o reinício + 15 s.
3. Atingir um limite registra a sessão (socket tmux, pane, janela, `pane_current_command`, cwd) em `state/pending/` e agenda a mesma tarefa.
4. No reinício a tarefa executa `scheduled`:
   - Sessões pendentes → `send-keys continue` para cada pane, no máximo 2 tentativas por sessão, depois nova verificação em 90 s.
   - Nada pendente → `claude -p --model haiku --safe-mode --tools "" 'Reply only OK.'`, e a próxima tarefa é estimada em 5 h + 15 s a partir do início do pedido.
5. As entradas pendentes são apagadas assim que você digita algo (`UserPromptSubmit`) ou a sessão termina (`SessionEnd`).
6. Limite de 7 dias em 100% → tudo espera o reinício semanal.

### Proteções

Um `continue` só é enviado se o pane ainda existe, ainda pertence à mesma sessão tmux e ainda executa o mesmo comando de quando o limite foi atingido. Caso contrário a entrada é arquivada em `state/stale/` e nada é digitado. Sessões fora do tmux apenas geram registro no log — não há pane onde escrever.

Um warm-up que falha é repetido após 60 s / 120 s / 300 s / 600 s. Se a saída parecer um login expirado, o warm-up automático pausa, `state/auth_required` é escrito (`status` mostra `RELOGIN MAY BE REQUIRED`) e há nova verificação em 1 hora.

## Requisitos

`claude`, `jq`, `at` (com `atd` em execução), `flock`, `timeout`, `tmux`, GNU `date`.

```bash
sudo systemctl enable --now atd
```

## Instalação

```bash
npx @mrjasonzhou/claude-plus
```

Ou a partir de um clone:

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

Qualquer instalação anterior é removida primeiro — suas tarefas `at`, suas entradas de `statusLine` e de hooks, e `~/.claude/claude-plus/` — de modo que rodar o instalador de novo é uma atualização limpa. Hooks de outras ferramentas ficam intactos. O `settings.json` é salvo como `settings.json.claude-plus-install-backup.<timestamp>`.

Depois, dentro do Claude Code, confira com `/hooks` se há `StopFailure`, `UserPromptSubmit` e `SessionEnd`.

## Uso

```bash
~/.claude/claude-plus/claude-plus.sh status   # versão, agendamento, pendentes, estado da autenticação
~/.claude/claude-plus/claude-plus.sh pending  # sessões esperando retomada
~/.claude/claude-plus/claude-plus.sh notify-test  # enviar a si mesmo uma notificação de teste
tail -f ~/.claude/claude-plus/claude-plus.log # log
```

## Notificações

O Claude Plus fica quieto enquanto nada precisa de você. Ele executa
`~/.claude/claude-plus/notify.sh` — qualquer executável — em três eventos:

| Evento | Quando |
|--------|--------|
| `auth-required` | O Claude Code está desconectado, nenhuma janela pode ser aberta |
| `warmup-failing` | Três warm-ups falharam seguidos |
| `recovered` | Os warm-ups voltaram a funcionar depois de um dos casos acima |

Cada evento dispara uma única vez ao entrar naquele estado, não a cada nova tentativa:
um problema durante a noite custa uma mensagem em vez de oito.

Exemplos para Bark, ntfy e e-mail SMTP são instalados em
`~/.claude/claude-plus/notify/`. Escolha um, preencha sua chave ou servidor e teste:

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh
chmod +x notify.sh          # use 700 no de e-mail, ele guarda uma senha
$EDITOR notify.sh
./claude-plus.sh notify-test
```

O script roda com `CP_EVENT`, `CP_MESSAGE` e `CP_HOST` no ambiente, então qualquer
outra coisa — Telegram, Slack, um webhook, `mail` — é questão de reescrever aquele
único `curl`. Reinstalar preserva o seu `notify.sh`.

Os limites de uso em si nunca geram notificação: são rotina, a retomada cuida deles,
e uma mensagem a cada vez seria apenas ruído.

## Arquivos

| Caminho | Descrição |
|---------|-----------|
| `~/.claude/claude-plus/claude-plus.sh` | Script principal |
| `~/.claude/claude-plus/state/` | Horários de reinício, id da tarefa, contagem de falhas, flag de autenticação |
| `~/.claude/claude-plus/state/pending/` | Sessões paradas por um limite, esperando retomada |
| `~/.claude/claude-plus/state/stale/` | Entradas descartadas porque o pane mudou |
| `~/.claude/claude-plus/original-statusline-command` | Seu comando de status line anterior |
| `~/.claude/claude-plus/notify.sh` | Seu script de notificação, se instalou um |
| `~/.claude/claude-plus/notify/` | Exemplos de scripts para copiar |
| `~/.claude/claude-plus/claude-plus.log` | Log |

## Desinstalação

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<timestamp> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```

## Licença

GPL-3.0-or-later. Veja [LICENSE](LICENSE).
