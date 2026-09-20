# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | Português | [العربية](README.ar.md)

Duas coisas que o Claude Code não faz por você, resolvidas enquanto você está longe do teclado.

- **Janela sempre aberta** — uma nova janela de 5 horas é aberta assim que a anterior é reiniciada, mesmo sem ninguém usando o Claude Code, então quando você volta já há uma cota cheia em andamento.
- **Aviso** — quando isso deixa de funcionar, ele avisa: Bark, ntfy, e-mail, ou qualquer outro canal que você queira ligar.

Retomar uma sessão depois de um limite de uso é algo que o Claude Code agora faz sozinho: veja "Continue automatically at usage limit" em `/config`. O Claude Plus também fazia isso antes da 3.0.0 e, a partir dela, deixa isso para o Claude Code.

## Para que serve

**Quando a janela abre decide quando ela termina.** Uma janela de 5 horas começa no seu primeiro pedido, não numa hora fixa. Comece a trabalhar às 9h e a janela vai das 9h às 14h; esgote a cota às 11h e você fica travado até as 14h. Se em vez disso um pedido mínimo tivesse aberto a janela às 6h, ela expiraria às 11h — exatamente quando você fica sem nada — com uma cota nova já esperando. Com uma janela sempre aberta, já há uma em andamento quando você começa: o que resta dela é cota que de outro modo se perderia, e uma nova chega em no máximo cinco horas, geralmente bem antes.

**Saber quando ele parou de ajudar.** Manter janelas abertas só funciona enquanto seu login for válido e o agendador estiver rodando; se um dos dois parar, nada acontece. O Claude Plus percebe qualquer um dos casos e avisa, em vez de falhar em silêncio o fim de semana inteiro.

## Requisitos

Linux, com `claude`, `jq`, `at` (com `atd` em execução), `flock`, `timeout`, GNU `date`.

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

O instalador envolve a sua status line existente, que continua aparecendo exatamente como antes; é a única mudança que ele faz nas suas configurações. Seu `settings.json` é salvo antes, e rodar o instalador de novo é uma atualização limpa, não uma segunda cópia. Uma atualização preserva a próxima execução agendada, o estado dela e o seu notificador. Atualizar a partir da 2.x também remove os hooks que essas versões adicionavam para retomar sessões.

## Uso

No dia a dia não há nada para executar — ele trabalha sozinho. Quando quiser olhar:

```bash
~/.claude/claude-plus/claude-plus.sh status   # o agendador está rodando, o que está agendado, a autenticação ainda vale
tail -f ~/.claude/claude-plus/claude-plus.log # o que ele andou fazendo
```

## Abrir em um horário fixo

Por padrão, uma janela abre assim que a anterior é reiniciada, então a cadeia segue o horário em que você esgotou a cota da última vez. Para fixá-la em um horário do dia:

```bash
~/.claude/claude-plus/claude-plus.sh anchor 06:00   # abrir às 06h
~/.claude/claude-plus/claude-plus.sh anchor         # mostrar a configuração
~/.claude/claude-plus/claude-plus.sh anchor off     # voltar a abrir assim que possível
```

Uma janela que passaria por cima desse horário espera por ele: a prevista para 03h cobriria 03h-08h e engoliria as 06h, então ela abre às 06h. As horas antes ficam sem janela — se você trabalhar nesse período, seu próprio primeiro pedido abre uma normalmente.

## Avisos

O Claude Plus fica quieto enquanto nada precisa de você, e informa quatro coisas:

| | |
|---|---|
| **Desconectado** | Seu login do Claude Code expirou; nada pode ser aberto até você entrar de novo |
| **Falhas repetidas** | Vários warm-ups seguidos falharam |
| **Agendador parado** | Uma execução agendada está muito atrasada, então nenhuma janela está sendo mantida aberta; geralmente o `atd` não está rodando |
| **De volta ao normal** | Ele se recuperou de qualquer um dos casos acima |

Cada um é anunciado uma única vez, não a cada nova tentativa: um problema durante a noite custa uma só mensagem. Os limites de uso em si nunca são anunciados: são rotina, e o Claude Code retoma sozinho depois deles.

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
| `anchor` | O horário em que as janelas abrem, se você definir um |
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
