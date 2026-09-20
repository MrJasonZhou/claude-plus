# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | 日本語 | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Claude Code が代わりにやってくれない 2 つのことを、あなたがキーボードの前にいない間に片づけます。

- **窓を開けておく** —— 前の 5 時間の窓がリセットされたらすぐ新しい窓を開けます。誰も Claude Code を使っていなくても同じです。戻ってきたときには、満タンの枠がすでに動き出しています。
- **通知** —— それがうまくいかなくなったときに知らせます。Bark、ntfy、メール、そのほか繋ぎたいものは何でも。

利用制限で止まったセッションの続きは、今では Claude Code 自身が引き受けます。`/config` の "Continue automatically at usage limit" を参照してください。Claude Plus も 3.0.0 より前はこれを行っていましたが、3.0.0 からは Claude Code に任せています。

## 何が嬉しいか

**窓をいつ開けたかが、いつ終わるかを決める。** 5 時間の窓は固定の時刻ではなく、最初のリクエストから始まります。9 時に仕事を始めてそのまま使えば窓は 9:00〜14:00。11 時に枠を使い切れば 14:00 まで待つしかありません。もし 6 時に小さなリクエストが窓を開けていれば、その窓は 11:00 に期限切れ —— ちょうど枠が尽きる時刻 —— で、新しい枠がすでに用意されています。窓が常に回っていれば、仕事を始めるときにはもう 1 つ動いています。その残りは本来使われずに消える枠で、次の新しい枠は長くても 5 時間後、たいていはもっと早く来ます。

**助けにならなくなった時がわかる。** 窓を開けておけるのは、ログインが有効でスケジューラが動いている間だけで、どちらかが止まれば何も起きません。Claude Plus はどちらも見分けて知らせます。週末じゅう黙って失敗し続けたりはしません。

## 必要なもの

Linux 上で、`claude`、`jq`、`at`（`atd` 起動済み）、`flock`、`timeout`、GNU `date`。

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

インストーラは既存の statusLine を包み込みます（表示はこれまでとまったく同じです）。設定への変更はこれだけです。`settings.json` は先にバックアップされ、再実行は二重インストールではなくクリーンな更新になります。更新しても、次に予約された実行とその状態、そしてあなたの通知スクリプトは引き継がれます。2.x からの更新では、それらのバージョンがセッション再開のために追加したフックも取り除きます。

## 使い方

普段は何も実行する必要がありません —— ひとりでに働きます。様子を見たいときは：

```bash
~/.claude/claude-plus/claude-plus.sh status   # スケジューラは動いているか、何が予約され、認証は有効か
tail -f ~/.claude/claude-plus/claude-plus.log # 何をしてきたか
```

## 決まった時刻に開ける

既定では前の窓がリセットされ次第すぐ開くので、連鎖は最後に枠を使い切った時刻に従います。毎日の決まった時刻に固定するには：

```bash
~/.claude/claude-plus/claude-plus.sh anchor 06:00   # 毎日 06:00 に開ける
~/.claude/claude-plus/claude-plus.sh anchor         # 現在の設定を表示
~/.claude/claude-plus/claude-plus.sh anchor off     # すぐ開ける動作に戻す
```

その時刻をまたいでしまう窓は、代わりにその時刻まで待ちます。03:00 に開く予定の窓は 03:00〜08:00 を覆って 06:00 を飲み込むので、06:00 に開きます。そのぶん時刻の手前の数時間は窓がありません。その時間帯に作業すれば、いつもどおりあなたの最初のリクエストが窓を開けます。

## 通知

Claude Plus は普段は黙っていて、あなたの対応が要るときだけ知らせます。伝えるのは次の 4 つだけです。

| | |
|---|---|
| **サインアウト** | Claude Code のログインが切れており、入り直すまで何も開けない |
| **連続して失敗** | warm-up が何度か続けて失敗した |
| **スケジューラ停止** | 予約した実行が大きく遅れており、窓が開けられていない。たいていは `atd` が動いていない |
| **復旧** | 上のいずれかから元に戻った |

それぞれ一度だけ知らせ、リトライのたびには鳴りません。夜間に問題が起きても届くのは 1 通です。利用制限そのものは決して知らせません。あれは日常的なもので、Claude Code が自分で続きを引き受けます。

受け取り方を選ぶには、見本をひとつコピーして自分のキーやサーバーを書き入れます。

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh      # ntfy.sh.sample、email.sh.sample でも可
chmod +x notify.sh                      # メール版はパスワードを持つので 700 に
$EDITOR notify.sh
./claude-plus.sh notify-test            # 実際に届くか確かめる
```

通知スクリプトは単なる実行可能ファイルで、`CP_EVENT`、`CP_MESSAGE`、`CP_HOST` を受け取ります。Telegram でも Slack でも webhook でも `mail` でも、書き換えるのは一行です。あなたが用意したものは再インストールしても残ります。

## ファイル

すべて `~/.claude/claude-plus/` の下にあります。

| | |
|---|---|
| `claude-plus.sh` | スクリプト本体 |
| `notify.sh` | あなたが用意した通知スクリプト |
| `notify/` | コピー元の見本 |
| `anchor` | 設定した窓を開ける時刻（設定していれば） |
| `claude-plus.log` | 何をしてきたか |
| `state/` | 内部の記録 |

## アンインストール

```bash
npx @claude-plus/claude-plus uninstall
```

クローンからの場合：`bash install-claude-plus.sh uninstall`。

現在の `settings.json` をその場で編集し、Claude Plus が追加したものだけを取り除きます。元の statusLine は戻り、それ以外の設定やフックはすべてそのまま残ります —— Claude Plus をインストールした後に追加されたものも含めて。予約されたジョブは取り消され、`~/.claude/claude-plus/` は削除されます。あなたの `notify.sh` も一緒です。二度実行しても害はありません。

その後に別のプログラムが Claude Plus の外側から statusLine を包んでいても、アンインストールでそれを壊すことはありません。そのプログラムが動き続けるよう小さな中継スクリプトを残し、その旨を表示します。不要になったらもう一度アンインストールしてください。同じ状況での更新も、そのプログラムを包み返すのではなく、その連鎖の内側に留まります。

アンインストール直前の `settings.json` のコピーがすぐ隣に残り、インストール時のコピーもそのまま残るので、手で戻す必要があれば使えます。

## ライセンス

GPL-3.0-or-later。詳細は [LICENSE](LICENSE) を参照してください。
