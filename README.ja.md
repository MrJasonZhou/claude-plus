# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | 日本語 | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

`at` ジョブで動く Claude Code の拡張機能です。

- **再開** —— tmux 内のセッションが利用制限で停止した場合、制限がリセットされ次第その pane に `continue` を入力します。
- **維持** —— 再開対象がなければ、小さな Haiku リクエストを送って新しい 5 時間枠を開始します。

## 何が嬉しいか

**5 時間の上限に達しても自動で復帰する。** 通常は上限に当たった時点でセッションが止まり、戻ってきて手動で再開することになります。ここではリセットと同時に `continue` をその pane へ打ち込むので、寝ている間や離席中でも作業が続きから再開します。

**窓をいつ開けたかが、いつ終わるかを決める。** 5 時間の窓は固定の時刻ではなく、最初のリクエストから始まります。9 時に仕事を始めてそのまま使えば窓は 9:00-14:00。11 時に枠を使い切れば 14:00 まで待つしかありません。もし 6 時に小さなリクエストが窓を開けていれば、その窓は 11:00 に期限切れ —— ちょうど枠が尽きる時刻 —— で、新しい枠がすでに用意されています。窓を回し続けるとは、リセット時刻を勤務時間の真ん中ではなく手前へ押し出すということです。

## 仕組み

1. インストール時に `~/.claude/settings.json` を書き換えます。`statusLine` に加えて 3 つのフック —— `StopFailure`（matcher は `rate_limit`）、`UserPromptSubmit`、`SessionEnd` —— を登録します。既存の statusLine コマンドは保存され、そのまま表示されます。
2. statusLine の更新ごとに `rate_limits.five_hour.resets_at` を読み取り、リセット時刻 + 15 秒に `at` ジョブを登録します。
3. 利用制限に達すると、そのセッション（tmux socket、pane、window、`pane_current_command`、cwd）を `state/pending/` に記録し、同じジョブを登録します。
4. リセット時刻にジョブが `scheduled` を実行します。
   - 再開対象あり → 各 pane へ `send-keys continue`。セッションごとに最大 2 回まで送信し、90 秒後に再確認します。
   - 再開対象なし → `claude -p --model haiku --safe-mode --tools "" 'Reply only OK.'` を実行し、リクエスト開始時刻を基準に次回を 5 時間 + 15 秒後と見積もって登録します。
5. 自分で入力した場合（`UserPromptSubmit`）やセッション終了時（`SessionEnd`）に、該当する再開待ち記録は削除されます。
6. 7 日制限に達している場合は、すべて週次リセットまで待機します。

### 誤送信の防止

`continue` を送るのは、pane が今も存在し、同じ tmux セッションに属し、制限時と同じコマンドを実行している場合だけです。そうでなければ記録は `state/stale/` へ退避され、何も入力しません。tmux 外のセッションはログに残すだけです —— 入力先の pane がありません。

warm-up の失敗は 60 秒 / 120 秒 / 300 秒 / 600 秒後に再試行します。出力がログイン切れらしい場合は自動 warm-up を一時停止し、`state/auth_required` を書き込み（`status` に `RELOGIN MAY BE REQUIRED` と表示）、1 時間後に再確認します。

## 必要なもの

`claude`、`jq`、`at`（`atd` 起動済み）、`flock`、`timeout`、`tmux`、GNU `date`。

```bash
sudo systemctl enable --now atd
```

## インストール

```bash
npx @claude-plus/claude-plus
```

クローンから実行する場合：

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

旧バージョンがあれば先に削除します —— その `at` ジョブ、`statusLine` とフックの項目、`~/.claude/claude-plus/` —— のため、インストーラの再実行がそのままクリーンな更新になります。他のフックには手を触れません。`settings.json` は `settings.json.claude-plus-install-backup.<タイムスタンプ>` としてバックアップされます。

インストール後、Claude Code 内の `/hooks` で `StopFailure`、`UserPromptSubmit`、`SessionEnd` を確認してください。

## 使い方

```bash
~/.claude/claude-plus/claude-plus.sh status   # バージョン、スケジュール、再開待ち件数、認証状態
~/.claude/claude-plus/claude-plus.sh pending  # 再開待ちのセッション
~/.claude/claude-plus/claude-plus.sh notify-test  # テスト通知を自分に送る
tail -f ~/.claude/claude-plus/claude-plus.log # ログ確認
```

## 通知

Claude Plus は普段は黙っていて、あなたの対応が要るときだけ知らせます。
`~/.claude/claude-plus/notify.sh`（実行可能ファイルなら何でも構いません）を
次の 3 つのイベントで実行します。

| イベント | タイミング |
|----------|------------|
| `auth-required` | Claude Code がサインアウトしており、窓を開けられない |
| `warmup-failing` | warm-up が 3 回続けて失敗した |
| `recovered` | 上記の状態から復旧した |

各イベントはその状態に**入った時**に一度だけ発火し、リトライのたびには鳴りません。
夜間に問題が起きても、届くのは 8 通ではなく 1 通です。

Bark、ntfy、SMTP メールのサンプルが `~/.claude/claude-plus/notify/` に
インストールされます。ひとつ選び、自分のキーやサーバーを書いて試してください。

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh
chmod +x notify.sh          # メール版はパスワードを持つので 700 に
$EDITOR notify.sh
./claude-plus.sh notify-test
```

スクリプトには `CP_EVENT`、`CP_MESSAGE`、`CP_HOST` が環境変数として渡されるので、
Telegram、Slack、webhook、`mail` などへの変更はその `curl` 一本を書き換えるだけです。
再インストールしても `notify.sh` は残ります。

利用制限そのものは通知しません。あれは日常的なもので自動再開が処理しますし、
毎回知らせればただの雑音になります。

## ファイル

| パス | 説明 |
|------|------|
| `~/.claude/claude-plus/claude-plus.sh` | メインスクリプト |
| `~/.claude/claude-plus/state/` | リセット時刻、ジョブ ID、失敗回数、認証フラグ |
| `~/.claude/claude-plus/state/pending/` | 制限で停止し再開を待つセッション |
| `~/.claude/claude-plus/state/stale/` | pane が変化したため破棄された再開待ち記録 |
| `~/.claude/claude-plus/original-statusline-command` | 既存の statusLine コマンド |
| `~/.claude/claude-plus/notify.sh` | 設定した通知スクリプト（あれば） |
| `~/.claude/claude-plus/notify/` | コピー元の通知スクリプト見本 |
| `~/.claude/claude-plus/claude-plus.log` | ログ |

## アンインストール

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<タイムスタンプ> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```

## ライセンス

GPL-3.0-or-later。詳細は [LICENSE](LICENSE) を参照してください。
