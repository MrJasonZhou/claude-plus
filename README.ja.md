# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | 日本語

`at` ジョブで動く Claude Code の拡張機能です。

- **再開** —— tmux 内のセッションが利用制限で停止した場合、制限がリセットされ次第その pane に `continue` を入力します。
- **維持** —— 再開対象がなければ、小さな Haiku リクエストを送って新しい 5 時間枠を開始します。

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
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

本プロジェクトの旧名称は `claude-window-keeper` です。旧版からの更新に追加手順は要りません。インストーラが旧名称を検出し、その `at` ジョブ、設定項目、`~/.claude/window-keeper/` を削除したうえで、保存済みの statusLine コマンドを引き継ぎます。

旧バージョンがあれば先に削除します —— その `at` ジョブ、`statusLine` とフックの項目、`~/.claude/claude-plus/` —— のため、インストーラの再実行がそのままクリーンな更新になります。他のフックには手を触れません。`settings.json` は `settings.json.claude-plus-install-backup.<タイムスタンプ>` としてバックアップされます。

インストール後、Claude Code 内の `/hooks` で `StopFailure`、`UserPromptSubmit`、`SessionEnd` を確認してください。

## 使い方

```bash
~/.claude/claude-plus/claude-plus.sh status   # バージョン、スケジュール、再開待ち件数、認証状態
~/.claude/claude-plus/claude-plus.sh pending  # 再開待ちのセッション
tail -f ~/.claude/claude-plus/claude-plus.log # ログ確認
```

## ファイル

| パス | 説明 |
|------|------|
| `~/.claude/claude-plus/claude-plus.sh` | メインスクリプト |
| `~/.claude/claude-plus/state/` | リセット時刻、ジョブ ID、失敗回数、認証フラグ |
| `~/.claude/claude-plus/state/pending/` | 制限で停止し再開を待つセッション |
| `~/.claude/claude-plus/state/stale/` | pane が変化したため破棄された再開待ち記録 |
| `~/.claude/claude-plus/original-statusline-command` | 既存の statusLine コマンド |
| `~/.claude/claude-plus/claude-plus.log` | ログ |

## アンインストール

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<タイムスタンプ> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```

## ライセンス

GPL-3.0-or-later。詳細は [LICENSE](LICENSE) を参照してください。
