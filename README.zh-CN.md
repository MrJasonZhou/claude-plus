# Claude Plus

[English](README.md) | 简体中文 | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Claude Code 不会替你做的两件事，在你不在键盘前的时候完成。

- **保持窗口开着** —— 上一个 5 小时窗口一重置就开一个新的，哪怕没人在用 Claude Code，这样你回来时已经有一份满额度在跑了。
- **提醒** —— 这件事没做成时会通知你：Bark、ntfy、邮件，或任何你愿意接上的渠道。

撞到用量上限后接着干活，Claude Code 现在自己就会做：见 `/config` 里的 "Continue automatically at usage limit"。Claude Plus 在 3.0.0 之前也做这件事，从 3.0.0 起交给 Claude Code。

## 为什么有用

**窗口什么时候开，决定它什么时候结束。** 5 小时窗口从你的第一个请求开始算，不是固定钟点。9 点上班就开始用，窗口是 9:00-14:00；11 点把额度烧完，就只能干等到 14:00。但如果 6 点已经有个极小的请求把窗口开好了，它 11:00 到期 —— 正好是你额度见底的时刻 —— 新额度已经在那儿等着。窗口一直在转的话，你开始干活时总有一个已经在跑：它剩下的部分是本来会浪费掉的额度，而新的一份最多 5 小时就到，通常早得多。

**知道它什么时候帮不上忙了。** 保持窗口开着，只在登录有效、调度器在跑时管用，任何一个出问题就什么都不会发生。Claude Plus 两种情况都认得出来并告诉你，而不是整个周末默默地失败下去。

## 依赖

Linux，并需要 `claude`、`jq`、`at`（需运行 `atd`）、`flock`、`timeout`、GNU `date`。

```bash
sudo systemctl enable --now atd
```

## 安装

```bash
npx @claude-plus/claude-plus
```

或者从源码安装：

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

安装脚本会包装你现有的 status line（显示和原来完全一样），这是它对设置做的唯一改动。`settings.json` 会先备份；重复执行安装脚本是一次干净的升级，而不是装第二份。升级会保留下一次排好的任务、它的状态，以及你的通知脚本。从 2.x 升级时，还会移除那些版本为续跑会话添加的 hook。

## 使用

日常什么都不用运行 —— 它自己会干活。想看看情况时：

```bash
~/.claude/claude-plus/claude-plus.sh status   # 调度器在不在跑、排了什么、认证还有效吗
tail -f ~/.claude/claude-plus/claude-plus.log # 它都做了些什么
```

## 在固定时刻开启

默认情况下，上一个窗口一重置就开新的，所以整条链跟着你上次用完额度的时刻走。想把它钉在每天某个时刻：

```bash
~/.claude/claude-plus/claude-plus.sh anchor 06:00   # 每天 06:00 开
~/.claude/claude-plus/claude-plus.sh anchor         # 查看当前设置
~/.claude/claude-plus/claude-plus.sh anchor off     # 恢复成一重置就开
```

会横跨这个时刻的窗口，改成等到那时再开：本来 03:00 要开的窗口覆盖 03:00-08:00，把 06:00 吞掉了，于是推迟到 06:00 开。这样设定时刻之前的那几个小时就没有窗口 —— 如果你那时候在干活，你自己的第一个请求照常会开一个。

## 提醒

Claude Plus 平时不出声，只在需要你处理时才响，而且只报告四件事：

| | |
|---|---|
| **已登出** | Claude Code 的登录已过期，在你重新登录之前什么都开不了 |
| **连续失败** | 连着几次保温都失败了 |
| **调度停了** | 排好的任务过了很久还没执行，窗口没有被保持开着；通常是 `atd` 没在运行 |
| **恢复正常** | 从上面任一情况中恢复了 |

每件事只通报一次，不会每次重试都响，所以过夜出问题只会收到一条消息。撞到用量上限本身从不通知：那是常态，Claude Code 会自己接着干。

想选择用什么方式收到消息，拷一个示例过去，填上你自己的 key 或服务器：

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh      # 也可以是 ntfy.sh.sample、email.sh.sample
chmod +x notify.sh                      # 邮件那个用 700，里面有密码
$EDITOR notify.sh
./claude-plus.sh notify-test            # 确认能收到
```

通知脚本不过是个可执行文件，运行时会拿到 `CP_EVENT`、`CP_MESSAGE`、`CP_HOST`，所以换成 Telegram、Slack、webhook 或 `mail`，无非是改一行。你的这份副本在重新安装后依然保留。

## 文件

全都在 `~/.claude/claude-plus/` 下：

| | |
|---|---|
| `claude-plus.sh` | 脚本本体 |
| `notify.sh` | 你配置的通知脚本 |
| `notify/` | 可拷贝的示例 |
| `anchor` | 你设定的窗口开启时刻（如果设了） |
| `claude-plus.log` | 它都做了些什么 |
| `state/` | 内部记账 |

## 卸载

```bash
npx @claude-plus/claude-plus uninstall
```

或者从源码：`bash install-claude-plus.sh uninstall`。

它直接在当前的 `settings.json` 上修改，只拿掉 Claude Plus 自己加的东西：你原来的 status line 会回来，其他所有设置和 hook 原样保留 —— 包括安装 Claude Plus 之后才加进去的。它排下的任务会被取消，`~/.claude/claude-plus/` 会被删除，你的 `notify.sh` 也在其中。重复执行不会有任何坏处。

如果之后有别的程序又把你的 status line 包在了 Claude Plus 外面，卸载不会把它弄坏：会留下一个小的透传脚本让那个程序继续工作，卸载时也会告诉你；等不再需要它时再执行一次卸载即可。同样情况下升级，会留在那个程序的链里，而不是反过来把它包起来。

卸载前那一刻的 `settings.json` 会留一份副本在旁边，安装时留下的副本也都还在，万一需要手动回退可以用。

## 许可证

GPL-3.0-or-later，详见 [LICENSE](LICENSE)。
