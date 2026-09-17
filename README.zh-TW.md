# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | 繁體中文 | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Claude Code 不會替你做的兩件事，在你不在鍵盤前的時候完成。

- **讓視窗一直開著** —— 上一個 5 小時視窗一重設就開一個新的，就算沒人在用 Claude Code 也一樣，這樣你回來時已經有一份滿額度在跑了。
- **提醒** —— 這件事沒做成時會通知你：Bark、ntfy、郵件，或任何你願意接上的管道。

撞到用量上限後接著做事，Claude Code 現在自己就會處理：見 `/config` 裡的 "Continue automatically at usage limit"。Claude Plus 在 3.0.0 之前也做這件事，從 3.0.0 起交給 Claude Code。

## 為什麼有用

**視窗什麼時候開，決定它什麼時候結束。** 5 小時視窗從你的第一個請求開始算，不是固定鐘點。9 點上班就開始用，視窗是 9:00-14:00；11 點把額度燒完，就只能乾等到 14:00。但如果 6 點已經有個極小的請求把視窗開好了，它 11:00 到期 —— 正好是你額度見底的時刻 —— 新額度已經在那裡等著。視窗一直在轉的話，你開始工作時總有一個已經在跑：它剩下的部分是本來會浪費掉的額度，而新的一份最多 5 小時就到，通常早得多。

**知道它什麼時候幫不上忙了。** 讓視窗一直開著，只在登入有效、排程器在跑時管用，任何一個出問題就什麼都不會發生。Claude Plus 兩種情況都認得出來並告訴你，而不是整個週末默默地失敗下去。

## 相依套件

Linux，並需要 `claude`、`jq`、`at`（需執行 `atd`）、`flock`、`timeout`、GNU `date`。

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

安裝指令碼會包裝你現有的 status line（顯示和原本完全一樣），這是它對設定做的唯一改動。`settings.json` 會先備份；重複執行安裝指令碼是一次乾淨的升級，而不是裝第二份。升級會保留下一次排好的工作、它的狀態，以及你的通知指令碼。從 2.x 升級時，還會移除那些版本為續跑工作階段加入的 hook。

## 使用

日常什麼都不用執行 —— 它自己會做事。想看看情況時：

```bash
~/.claude/claude-plus/claude-plus.sh status   # 排程器在不在跑、排了什麼、認證還有效嗎
tail -f ~/.claude/claude-plus/claude-plus.log # 它都做了些什麼
```

## 提醒

Claude Plus 平時不出聲，只在需要你處理時才響，而且只報告四件事：

| | |
|---|---|
| **已登出** | Claude Code 的登入已過期，在你重新登入之前什麼都開不了 |
| **連續失敗** | 接連幾次保溫都失敗了 |
| **排程停了** | 排好的工作過了很久還沒執行，視窗沒有被保持開著；通常是 `atd` 沒在執行 |
| **恢復正常** | 從上面任一情況中恢復了 |

每件事只通報一次，不會每次重試都響，所以過夜出問題只會收到一則訊息。撞到用量上限本身從不通知：那是常態，Claude Code 會自己接著做。

想選擇用什麼方式收到訊息，複製一個範例過去，填上你自己的金鑰或伺服器：

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh      # 也可以是 ntfy.sh.sample、email.sh.sample
chmod +x notify.sh                      # 郵件那個用 700，裡面有密碼
$EDITOR notify.sh
./claude-plus.sh notify-test            # 確認收得到
```

通知指令碼不過是個可執行檔，執行時會拿到 `CP_EVENT`、`CP_MESSAGE`、`CP_HOST`，所以換成 Telegram、Slack、webhook 或 `mail`，無非是改一行。你的這份副本在重新安裝後依然保留。

## 檔案

全都在 `~/.claude/claude-plus/` 底下：

| | |
|---|---|
| `claude-plus.sh` | 指令碼本體 |
| `notify.sh` | 你設定的通知指令碼 |
| `notify/` | 可複製的範例 |
| `claude-plus.log` | 它都做了些什麼 |
| `state/` | 內部記帳 |

## 解除安裝

```bash
npx @claude-plus/claude-plus uninstall
```

或者從原始碼：`bash install-claude-plus.sh uninstall`。

它直接在目前的 `settings.json` 上修改，只拿掉 Claude Plus 自己加的東西：你原本的 status line 會回來，其他所有設定和 hook 原樣保留 —— 包括安裝 Claude Plus 之後才加進去的。它排下的工作會被取消，`~/.claude/claude-plus/` 會被刪除，你的 `notify.sh` 也在其中。重複執行不會有任何壞處。

如果之後有別的程式又把你的 status line 包在了 Claude Plus 外面，解除安裝不會把它弄壞：會留下一個小的透傳指令碼讓那個程式繼續運作，解除安裝時也會告訴你；等不再需要它時再執行一次解除安裝即可。同樣情況下升級，會留在那個程式的鏈裡，而不是反過來把它包起來。

解除安裝前那一刻的 `settings.json` 會留一份副本在旁邊，安裝時留下的副本也都還在，萬一需要手動回退可以用。

## 授權條款

GPL-3.0-or-later，詳見 [LICENSE](LICENSE)。
