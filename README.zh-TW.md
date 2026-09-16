# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | 繁體中文 | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

對 Claude Code 的增強，均由 `at` 工作驅動：

- **續跑** —— tmux 裡的工作階段撞到用量上限而中斷時，等額度重設後自動向該 pane 輸入 `continue`。
- **保溫** —— 沒有待續跑的工作階段時，送出一個極小的 Haiku 請求，開啟新的 5 小時視窗。

## 為什麼有用

**撞到 5 小時上限後自動恢復。** 平時撞上限意味著工作階段就停在那裡，你得回來手動重啟。這裡額度一重設就把 `continue` 敲回那個 pane，工作從斷點繼續 —— 包括你在睡覺或不在座位的時候。

**視窗什麼時候開，決定它什麼時候結束。** 5 小時視窗從你的第一個請求開始算，不是固定鐘點。9 點上班就開始用，視窗是 9:00-14:00；11 點把額度燒完，就只能乾等到 14:00。但如果 6 點已經有個極小的請求把視窗開好了，它 11:00 到期 —— 正好是你額度見底的時刻 —— 新額度已經在那裡等著。讓視窗一直轉下去，就是把重設時間推到工作時段之前，而不是卡在中間。

## 運作原理

1. 安裝時改寫 `~/.claude/settings.json`：寫入 `statusLine`，以及三個 hook —— `StopFailure`（matcher 為 `rate_limit`）、`UserPromptSubmit`、`SessionEnd`。原有的 status line 指令會被保存並照常顯示。
2. 每次 status line 更新時讀取 `rate_limits.five_hour.resets_at`，登錄一個在重設時間 + 15 秒執行的 `at` 工作。
3. 撞到用量上限時，把該工作階段（tmux socket、pane、window、`pane_current_command`、cwd）記錄到 `state/pending/`，並登錄同樣的工作。
4. 重設時工作執行 `scheduled`：
   - 有待續跑的工作階段 → 向各 pane `send-keys continue`，每個工作階段最多 2 次，之後 90 秒再複查。
   - 沒有待續跑的工作階段 → 執行 `claude -p --model haiku --safe-mode --tools "" 'Reply only OK.'`，並以請求開始時刻為基準，把下一次工作估算在 5 小時 + 15 秒後。
5. 你自己輸入內容（`UserPromptSubmit`）或工作階段結束（`SessionEnd`）時，對應的待續跑記錄會被清除。
6. 7 天額度已用滿時，一切等到每週重設後再執行。

### 防誤送

只有當 pane 仍然存在、仍屬於同一個 tmux 工作階段、且執行的指令與撞上限時相同，才會送出 `continue`。否則該記錄會被歸檔到 `state/stale/`，不做任何輸入。tmux 之外的工作階段只記錄日誌 —— 沒有可輸入的 pane。

保溫失敗按 60 秒 / 120 秒 / 300 秒 / 600 秒重試。若輸出看起來像登入已過期，則暫停自動保溫，寫入 `state/auth_required`（`status` 會顯示 `RELOGIN MAY BE REQUIRED`），並在 1 小時後重新檢查。

## 相依套件

`claude`、`jq`、`at`（需執行 `atd`）、`flock`、`timeout`、`tmux`、GNU `date`。

```bash
sudo systemctl enable --now atd
```

## 安裝

```bash
npx @claude-plus/claude-plus
```

或者從原始碼安裝：

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

安裝前會先移除舊版本 —— 它的 `at` 工作、`statusLine` 與 hook 項目，以及 `~/.claude/claude-plus/` —— 所以重複執行安裝指令碼就是一次乾淨的升級。其他工具的 hook 不受影響。`settings.json` 會備份為 `settings.json.claude-plus-install-backup.<時間戳記>`。

安裝後請在 Claude Code 內用 `/hooks` 確認 `StopFailure`、`UserPromptSubmit`、`SessionEnd`。

## 使用

```bash
~/.claude/claude-plus/claude-plus.sh status   # 版本、排程、待續跑數量、認證狀態
~/.claude/claude-plus/claude-plus.sh pending  # 等待續跑的工作階段
~/.claude/claude-plus/claude-plus.sh notify-test  # 給自己送一則測試通知
tail -f ~/.claude/claude-plus/claude-plus.log # 查看日誌
```

## 通知

Claude Plus 平時不出聲，只在需要你處理時才響。它會執行
`~/.claude/claude-plus/notify.sh`（任何可執行檔都行），觸發事件有三個：

| 事件 | 什麼時候 |
|------|----------|
| `auth-required` | Claude Code 已登出，無法開啟視窗 |
| `warmup-failing` | 連續三次保溫失敗 |
| `recovered` | 上述狀態恢復正常 |

每個事件只在**進入**該狀態時送一次，不會每次重試都送，所以過夜出問題只會收到一則訊息，而不是八則。

Bark、ntfy 和 SMTP 郵件的範例指令碼會裝到 `~/.claude/claude-plus/notify/`。挑一個，填上你自己的金鑰或伺服器，然後測試：

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh
chmod +x notify.sh          # 郵件那個用 700，裡面有密碼
$EDITOR notify.sh
./claude-plus.sh notify-test
```

指令碼執行時環境裡有 `CP_EVENT`、`CP_MESSAGE`、`CP_HOST`，所以換成 Telegram、Slack、webhook 或 `mail`，無非是改那一條 `curl`。重新安裝不會覆蓋你的 `notify.sh`。

撞到用量上限本身不會通知：那是常態，自動續跑會處理，每次都提醒只會變成雜訊。

## 檔案

| 路徑 | 說明 |
|------|------|
| `~/.claude/claude-plus/claude-plus.sh` | 主指令碼 |
| `~/.claude/claude-plus/state/` | 重設時間、工作 ID、失敗次數、認證旗標 |
| `~/.claude/claude-plus/state/pending/` | 撞上限後等待續跑的工作階段 |
| `~/.claude/claude-plus/state/stale/` | 因 pane 已變化而放棄的待續跑記錄 |
| `~/.claude/claude-plus/original-statusline-command` | 原有的 status line 指令 |
| `~/.claude/claude-plus/notify.sh` | 你設定的通知指令碼（如果有） |
| `~/.claude/claude-plus/notify/` | 可複製的通知指令碼範例 |
| `~/.claude/claude-plus/claude-plus.log` | 日誌 |

## 解除安裝

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<時間戳記> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```

## 授權條款

GPL-3.0-or-later，詳見 [LICENSE](LICENSE)。
