# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | Português | [العربية](README.ar.md)

Três coisas que o Claude Code não faz por você, resolvidas enquanto você está longe do teclado.

- **Retomada** — uma sessão parada por um limite de uso volta a andar sozinha no instante em que o limite é reiniciado, seguindo o trabalho que estava pela metade.
- **Janela sempre aberta** — se não há nada a retomar, uma nova janela de 5 horas é aberta mesmo assim, para que seu reinício caia fora do seu horário de trabalho em vez de no meio dele.
- **Aviso** — quando não consegue mais seguir sozinho, ele avisa: Bark, ntfy, e-mail, ou qualquer outro canal que você queira ligar.

## Para que serve

**Recuperar de um limite de 5 horas.** Normalmente, atingir o teto significa que a sessão simplesmente para e você volta mais tarde para reiniciá-la à mão. O Claude Plus reinicia por você no instante em que o limite é reiniciado, então o trabalho segue de onde parou — inclusive enquanto você dorme ou está longe da mesa.

**Quando a janela abre decide quando ela termina.** Uma janela de 5 horas começa no seu primeiro pedido, não numa hora fixa. Comece a trabalhar às 9h e a janela vai das 9h às 14h; esgote a cota às 11h e você fica travado até as 14h. Se em vez disso um pedido mínimo tivesse aberto a janela às 6h, ela expiraria às 11h — exatamente quando você fica sem nada — com uma cota nova já esperando. Manter uma janela sempre aberta empurra o reinício para antes do seu horário de trabalho, em vez de deixá-lo no meio dele.

**Saber quando ele parou de ajudar.** A recuperação automática funciona enquanto seu login for válido; assim que expira, nada mais funciona. O Claude Plus percebe esse caso e avisa, em vez de falhar em silêncio o fim de semana inteiro.

## O que ele não vai fazer

Retomar significa digitar no terminal em que você estava trabalhando, por isso ele é cuidadoso quanto a onde digita. Uma sessão só é retomada se ainda estiver lá, intacta, exatamente como o limite a deixou. Se você a fechou, seguiu para outra coisa, ou iniciou outra coisa naquele terminal, o Claude Plus não mexe e fica calado. Sessões fora do tmux nunca são retomadas — não há onde digitar.

Os limites de uso em si nunca são anunciados. São rotina, a retomada cuida deles, e uma mensagem a cada vez seria apenas ruído.

## Requisitos

Linux, com `claude`, `jq`, `at` (com `atd` em execução), `flock`, `timeout`, `tmux`, GNU `date`.

```bash
sudo systemctl enable --now atd
```

## Instalação

```bash
npx @claude-plus/claude-plus
```

Ou a partir de um clone:

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

O instalador envolve a sua status line existente, que continua aparecendo exatamente como antes, e adiciona os próprios hooks, sem tocar nos de outras ferramentas. Seu `settings.json` é salvo antes, e rodar o instalador de novo é uma atualização limpa, não uma segunda cópia. Uma atualização preserva o que está em andamento: sessões esperando retomada, a próxima execução agendada e o seu notificador.

## Uso

No dia a dia não há nada para executar — ele trabalha sozinho. Quando quiser olhar:

```bash
~/.claude/claude-plus/claude-plus.sh status   # o agendador está rodando, o que está agendado, o que espera, a autenticação ainda vale
~/.claude/claude-plus/claude-plus.sh pending  # sessões esperando retomada
tail -f ~/.claude/claude-plus/claude-plus.log # o que ele andou fazendo
```

## Avisos

O Claude Plus fica quieto enquanto nada precisa de você, e informa quatro coisas:

| | |
|---|---|
| **Desconectado** | Seu login do Claude Code expirou; nada pode ser aberto até você entrar de novo |
| **Falhas repetidas** | Vários warm-ups seguidos falharam |
| **Agendador parado** | Uma execução agendada está muito atrasada, então nada está sendo mantido nem retomado; geralmente o `atd` não está rodando |
| **De volta ao normal** | Ele se recuperou de qualquer um dos casos acima |

Cada um é anunciado uma única vez, não a cada nova tentativa: um problema durante a noite custa uma só mensagem.

Para escolher como receber o aviso, copie um dos exemplos e preencha sua chave ou servidor:

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh      # ou ntfy.sh.sample, email.sh.sample
chmod +x notify.sh                      # use 700 no de e-mail, ele guarda uma senha
$EDITOR notify.sh
./claude-plus.sh notify-test            # confirme que chega até você
```

O notificador é apenas um executável que recebe `CP_EVENT`, `CP_MESSAGE` e `CP_HOST`, então Telegram, Slack, um webhook ou `mail` são questão de reescrever uma linha. Sua cópia sobrevive a reinstalações.

## Arquivos

Está tudo em `~/.claude/claude-plus/`:

| | |
|---|---|
| `claude-plus.sh` | O script em si |
| `notify.sh` | Seu notificador, depois de configurado |
| `notify/` | Exemplos para copiar |
| `claude-plus.log` | O que ele andou fazendo |
| `state/` | Controle interno |

## Desinstalação

```bash
npx @claude-plus/claude-plus uninstall
```

Ou a partir de um clone: `bash install-claude-plus.sh uninstall`.

Ela edita o seu `settings.json` atual no próprio lugar e retira apenas o que o Claude Plus adicionou: sua própria status line volta, e todas as outras configurações e hooks ficam exatamente como estão — inclusive os adicionados depois de instalar o Claude Plus. As tarefas agendadas são canceladas e `~/.claude/claude-plus/` é apagado, junto com o seu `notify.sh`. Rodar de novo não causa nenhum dano.

Se depois outro programa envolveu a sua status line por fora do Claude Plus, desinstalar não o quebra. Fica para trás um pequeno script de repasse para que esse programa continue funcionando, e o desinstalador avisa; rode de novo quando nada mais precisar dele. Uma atualização na mesma situação permanece dentro da cadeia desse programa em vez de envolvê-lo por sua vez.

Uma cópia do `settings.json` de logo antes da desinstalação fica ao lado dele, assim como as cópias feitas na instalação, caso você precise voltar atrás à mão.

## Licença

GPL-3.0-or-later. Veja [LICENSE](LICENSE).
