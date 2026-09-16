# Claude Plus

[English](README.md) | 简体中文 | [日本語](README.ja.md)

对 Claude Code 的增强，均由 `at` 任务驱动：

- **续跑** —— tmux 里的会话撞到用量上限而中断时，等限额重置后自动向该 pane 输入 `continue`。
- **保温** —— 没有待续跑的会话时，发送一个极小的 Haiku 请求，开启新的 5 小时窗口。

## 为什么有用

**撞到 5 小时上限后自动恢复。** 平时撞限意味着会话就停在那儿，你得回来手动重启。这里限额一重置就把 `continue` 敲回那个 pane，工作从断点继续 —— 包括你在睡觉或不在座位的时候。

**窗口什么时候开，决定它什么时候结束。** 5 小时窗口从你的第一个请求开始算，不是固定钟点。9 点上班就开始用，窗口是 9:00-14:00；11 点把额度烧完，就只能干等到 14:00。但如果 6 点已经有个极小的请求把窗口开好了，它 11:00 到期 —— 正好是你额度见底的时刻 —— 新额度已经在那儿等着。让窗口一直转下去，就是把重置时间推到工作时段之前，而不是卡在中间。

## 工作原理

1. 安装时改写 `~/.claude/settings.json`：写入 `statusLine`，以及三个 hook —— `StopFailure`（matcher 为 `rate_limit`）、`UserPromptSubmit`、`SessionEnd`。原有的 status line 命令会被保存并照常显示。
2. 每次 status line 刷新时读取 `rate_limits.five_hour.resets_at`，注册一个在重置时间 + 15 秒执行的 `at` 任务。
3. 撞到用量上限时，把该会话（tmux socket、pane、window、`pane_current_command`、cwd）记录到 `state/pending/`，并注册同样的任务。
4. 重置时任务执行 `scheduled`：
   - 有待续跑的会话 → 向各 pane `send-keys continue`，每个会话最多 2 次，之后 90 秒再复查。
   - 没有待续跑的会话 → 执行 `claude -p --model haiku --safe-mode --tools "" 'Reply only OK.'`，并以请求开始时刻为基准，把下一次任务估算在 5 小时 + 15 秒后。
5. 你自己输入内容（`UserPromptSubmit`）或会话结束（`SessionEnd`）时，对应的待续跑记录会被清除。
6. 7 天限额已用满时，一切等到每周重置后再执行。

### 安全措施

只有当 pane 仍然存在、仍属于同一个 tmux session、且运行的命令与撞限时相同，才会发送 `continue`。否则该记录会被归档到 `state/stale/`，不做任何输入。tmux 之外的会话只记录日志 —— 没有可输入的 pane。

保温失败按 60 秒 / 120 秒 / 300 秒 / 600 秒重试。若输出像是登录已过期，则暂停自动保温，写入 `state/auth_required`（`status` 会显示 `RELOGIN MAY BE REQUIRED`），并在 1 小时后重新检查。

## 依赖

`claude`、`jq`、`at`（需运行 `atd`）、`flock`、`timeout`、`tmux`、GNU `date`。

```bash
sudo systemctl enable --now atd
```

## 安装

```bash
npx @mrjasonzhou/claude-plus
```

或者从源码安装：

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

安装前会先移除旧版本 —— 它的 `at` 任务、`statusLine` 与 hook 条目，以及 `~/.claude/claude-plus/` —— 所以重复执行安装脚本就是一次干净的升级。其他人的 hook 不受影响。`settings.json` 会备份为 `settings.json.claude-plus-install-backup.<时间戳>`。

安装后请在 Claude Code 内用 `/hooks` 确认 `StopFailure`、`UserPromptSubmit`、`SessionEnd`。

## 使用

```bash
~/.claude/claude-plus/claude-plus.sh status   # 版本、调度、待续跑数量、认证状态
~/.claude/claude-plus/claude-plus.sh pending  # 等待续跑的会话
~/.claude/claude-plus/claude-plus.sh notify-test  # 给自己发一条测试通知
tail -f ~/.claude/claude-plus/claude-plus.log # 查看日志
```

## 通知

Claude Plus 平时不出声，只在需要你处理时才响。它会执行
`~/.claude/claude-plus/notify.sh`（任何可执行文件都行），触发事件有三个：

| 事件 | 什么时候 |
|------|----------|
| `auth-required` | Claude Code 已登出，无法开启窗口 |
| `warmup-failing` | 连续三次保温失败 |
| `recovered` | 上述状态恢复正常 |

每个事件只在**进入**该状态时发一次，不会每次重试都发，所以过夜出问题只会收到一条消息，而不是八条。

Bark、ntfy 和 SMTP 邮件的示例脚本会装到 `~/.claude/claude-plus/notify/`。挑一个，填上你自己的 key 或服务器，然后测试：

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh
chmod +x notify.sh          # 邮件那个用 700，里面有密码
$EDITOR notify.sh
./claude-plus.sh notify-test
```

脚本运行时环境里有 `CP_EVENT`、`CP_MESSAGE`、`CP_HOST`，所以换成 Telegram、Slack、webhook 或 `mail`，无非是改那一条 `curl`。重新安装不会覆盖你的 `notify.sh`。

撞到用量上限本身不会通知：那是常态，自动续跑会处理，每次都提醒只会变成噪音。

## 文件

| 路径 | 说明 |
|------|------|
| `~/.claude/claude-plus/claude-plus.sh` | 主脚本 |
| `~/.claude/claude-plus/state/` | 重置时间、任务 ID、失败次数、认证标记 |
| `~/.claude/claude-plus/state/pending/` | 撞限后等待续跑的会话 |
| `~/.claude/claude-plus/state/stale/` | 因 pane 已变化而放弃的待续跑记录 |
| `~/.claude/claude-plus/original-statusline-command` | 原有的 status line 命令 |
| `~/.claude/claude-plus/notify.sh` | 你配置的通知脚本（如果有） |
| `~/.claude/claude-plus/notify/` | 可拷贝的通知脚本示例 |
| `~/.claude/claude-plus/claude-plus.log` | 日志 |

## 卸载

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<时间戳> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```

## 许可证

GPL-3.0-or-later，详见 [LICENSE](LICENSE)。
