# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | 繁體中文 | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Claude Code 不會替你做的三件事，在你不在鍵盤前的時候完成。

- **續跑** —— 因用量上限而中斷的工作階段，在額度重設的那一刻自己重新開始，接著原本做到一半的事往下做。
- **讓視窗一直開著** —— 沒有需要續跑的工作階段時，也照樣開啟一個新的 5 小時視窗，好讓它的重設時間落在你的工作時段之外，而不是當中。
- **提醒** —— 當它自己撐不下去時會通知你：Bark、ntfy、郵件，或任何你願意接上的管道。

## 為什麼有用

**撞到 5 小時上限後自動恢復。** 平時撞上限意味著工作階段就停在那裡，你得回來手動重啟。Claude Plus 會在額度重設的那一刻替你重啟，工作從斷點繼續 —— 包括你在睡覺或不在座位的時候。

**視窗什麼時候開，決定它什麼時候結束。** 5 小時視窗從你的第一個請求開始算，不是固定鐘點。9 點上班就開始用，視窗是 9:00-14:00；11 點把額度燒完，就只能乾等到 14:00。但如果 6 點已經有個極小的請求把視窗開好了，它 11:00 到期 —— 正好是你額度見底的時刻 —— 新額度已經在那裡等著。讓視窗一直轉下去，就是把重設時間推到工作時段之前，而不是卡在中間。

**知道它什麼時候幫不上忙了。** 自動恢復只在登入有效時管用，一旦登入過期就全都不靈了。Claude Plus 認得出這種情況並告訴你，而不是整個週末默默地失敗下去。

## 它不會做的事

續跑意味著往你原本工作的終端機裡敲字，所以它對敲在哪裡非常謹慎。只有當工作階段還在那裡、原封未動、和撞上限時一模一樣，才會被續跑。如果你已經關掉它、走開了，或在那個終端機裡做起了別的事，Claude Plus 就不碰，也不出聲。跑在 tmux 之外的工作階段根本不會被續跑 —— 沒有可以敲字的地方。

撞上限本身從不通知。那是常態，續跑會處理，每次都提醒只會變成雜訊。

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

安裝指令碼會接管你的 status line 並加入自己的 hook，同時保留你原有的 status line，也不動其他工具的 hook。`settings.json` 會先備份；重複執行安裝指令碼是一次乾淨的升級，而不是裝第二份。

## 使用

日常什麼都不用執行 —— 它自己會做事。想看看情況時：

```bash
~/.claude/claude-plus/claude-plus.sh status   # 排了什麼、有誰在等、認證還有效嗎
~/.claude/claude-plus/claude-plus.sh pending  # 等待續跑的工作階段
tail -f ~/.claude/claude-plus/claude-plus.log # 它都做了些什麼
```

## 提醒

Claude Plus 平時不出聲，只在需要你處理時才響，而且只報告三件事：

| | |
|---|---|
| **已登出** | Claude Code 的登入已過期，在你重新登入之前什麼都開不了 |
| **連續失敗** | 接連幾次保溫都失敗了 |
| **恢復正常** | 從上面兩種情況中恢復了 |

每件事只通報一次，不會每次重試都響，所以過夜出問題只會收到一則訊息。

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

解除安裝前那一刻的 `settings.json` 會留一份副本在旁邊，安裝時留下的副本也都還在，萬一需要手動回退可以用。

## 授權條款

GPL-3.0-or-later，詳見 [LICENSE](LICENSE)。
