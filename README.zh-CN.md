# Claude Plus

[English](README.md) | 简体中文 | [日本語](README.ja.md)

对 Claude Code 的增强，均由 `at` 任务驱动：

- **续跑** —— tmux 里的会话撞到用量上限而中断时，等限额重置后自动向该 pane 输入 `continue`。
- **保温** —— 没有待续跑的会话时，发送一个极小的 Haiku 请求，开启新的 5 小时窗口。

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
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

本项目原名 `claude-window-keeper`。从旧版升级无需额外操作：安装脚本会识别旧名称，移除它的 `at` 任务、设置条目和 `~/.claude/window-keeper/`，并继承你保存的 status line 命令。

安装前会先移除旧版本 —— 它的 `at` 任务、`statusLine` 与 hook 条目，以及 `~/.claude/claude-plus/` —— 所以重复执行安装脚本就是一次干净的升级。其他人的 hook 不受影响。`settings.json` 会备份为 `settings.json.claude-plus-install-backup.<时间戳>`。

安装后请在 Claude Code 内用 `/hooks` 确认 `StopFailure`、`UserPromptSubmit`、`SessionEnd`。

## 使用

```bash
~/.claude/claude-plus/claude-plus.sh status   # 版本、调度、待续跑数量、认证状态
~/.claude/claude-plus/claude-plus.sh pending  # 等待续跑的会话
tail -f ~/.claude/claude-plus/claude-plus.log # 查看日志
```

## 文件

| 路径 | 说明 |
|------|------|
| `~/.claude/claude-plus/claude-plus.sh` | 主脚本 |
| `~/.claude/claude-plus/state/` | 重置时间、任务 ID、失败次数、认证标记 |
| `~/.claude/claude-plus/state/pending/` | 撞限后等待续跑的会话 |
| `~/.claude/claude-plus/state/stale/` | 因 pane 已变化而放弃的待续跑记录 |
| `~/.claude/claude-plus/original-statusline-command` | 原有的 status line 命令 |
| `~/.claude/claude-plus/claude-plus.log` | 日志 |

## 卸载

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<时间戳> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```
