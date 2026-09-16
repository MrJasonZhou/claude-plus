# Claude Plus

[English](README.md) | 简体中文 | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Claude Code 不会替你做的三件事，在你不在键盘前的时候完成。

- **续跑** —— 因用量上限而中断的会话，在额度重置的那一刻自己重新开始，接着原来做到一半的事往下做。
- **保持窗口开着** —— 没有需要续跑的会话时，也照样开启一个新的 5 小时窗口，好让它的重置时间落在你的工作时段之外，而不是当中。
- **提醒** —— 当它自己撑不下去时会通知你：Bark、ntfy、邮件，或任何你愿意接上的渠道。

## 为什么有用

**撞到 5 小时上限后自动恢复。** 平时撞上限意味着会话就停在那儿，你得回来手动重启。Claude Plus 会在额度重置的那一刻替你重启，工作从断点继续 —— 包括你在睡觉或不在座位的时候。

**窗口什么时候开，决定它什么时候结束。** 5 小时窗口从你的第一个请求开始算，不是固定钟点。9 点上班就开始用，窗口是 9:00-14:00；11 点把额度烧完，就只能干等到 14:00。但如果 6 点已经有个极小的请求把窗口开好了，它 11:00 到期 —— 正好是你额度见底的时刻 —— 新额度已经在那儿等着。让窗口一直转下去，就是把重置时间推到工作时段之前，而不是卡在中间。

**知道它什么时候帮不上忙了。** 自动恢复只在登录有效时管用，一旦登录过期就全都不灵了。Claude Plus 认得出这种情况并告诉你，而不是整个周末默默地失败下去。

## 它不会做的事

续跑意味着往你原来工作的终端里敲字，所以它对敲在哪儿非常谨慎。只有当会话还在那儿、原封未动、和撞上限时一模一样，才会被续跑。如果你已经关掉它、走开了，或在那个终端里干起了别的事，Claude Plus 就不碰，也不出声。跑在 tmux 之外的会话根本不会被续跑 —— 没有可以敲字的地方。

撞上限本身从不通知。那是常态，续跑会处理，每次都提醒只会变成噪音。

## 依赖

`claude`、`jq`、`at`（需运行 `atd`）、`flock`、`timeout`、`tmux`、GNU `date`。

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

安装脚本会接管你的 status line 并加入自己的 hook，同时保留你原有的 status line，也不动其他工具的 hook。`settings.json` 会先备份；重复执行安装脚本是一次干净的升级，而不是装第二份。

## 使用

日常什么都不用运行 —— 它自己会干活。想看看情况时：

```bash
~/.claude/claude-plus/claude-plus.sh status   # 排了什么、有谁在等、认证还有效吗
~/.claude/claude-plus/claude-plus.sh pending  # 等待续跑的会话
tail -f ~/.claude/claude-plus/claude-plus.log # 它都做了些什么
```

## 提醒

Claude Plus 平时不出声，只在需要你处理时才响，而且只报告三件事：

| | |
|---|---|
| **已登出** | Claude Code 的登录已过期，在你重新登录之前什么都开不了 |
| **连续失败** | 连着几次保温都失败了 |
| **恢复正常** | 从上面两种情况中恢复了 |

每件事只通报一次，不会每次重试都响，所以过夜出问题只会收到一条消息。

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
| `claude-plus.log` | 它都做了些什么 |
| `state/` | 内部记账 |

## 卸载

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<时间戳> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```

## 许可证

GPL-3.0-or-later，详见 [LICENSE](LICENSE)。
