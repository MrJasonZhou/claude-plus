# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português](README.pt.md) | العربية

إضافات لـ Claude Code تعمل عبر مهام `at`:

- **الاستئناف** — عندما تتوقف جلسة داخل tmux بسبب بلوغ حد الاستخدام، تُكتب `continue` في تلك اللوحة فور إعادة تعيين الحد.
- **إبقاء النافذة مفتوحة** — إن لم يكن هناك ما يُستأنف، يفتح طلب Haiku صغير نافذة جديدة مدتها خمس ساعات.

## ما الفائدة

**التعافي بعد بلوغ حد الخمس ساعات.** في العادة يعني بلوغ الحد أن الجلسة تتوقف ببساطة، فتعود لاحقًا لتشغيلها يدويًا. هنا تُكتب `continue` في اللوحة في اللحظة التي يُعاد فيها تعيين الحد، فيستأنف العمل من حيث توقف — حتى وأنت نائم أو بعيد عن مكتبك.

**وقت فتح النافذة هو ما يحدد وقت انتهائها.** تبدأ نافذة الخمس ساعات من أول طلب لك، لا من ساعة ثابتة. ابدأ العمل في التاسعة صباحًا فتمتد النافذة من 9:00 إلى 14:00؛ وإذا استنفدت الحصة عند 11:00 بقيت محجوبًا حتى 14:00. أما لو كان طلب صغير قد فتح النافذة عند 6:00، لانتهت عند 11:00 — أي في اللحظة نفسها التي تنفد فيها حصتك — وكانت حصة جديدة في انتظارك. إبقاء نافذة تعمل دائمًا يدفع موعد إعادة التعيين إلى ما قبل ساعات عملك بدلًا من منتصفها.

## آلية العمل

1. التثبيت يعيد كتابة `~/.claude/settings.json`: يضبط `statusLine` وثلاثة خطافات — `StopFailure` (بالمطابق `rate_limit`) و`UserPromptSubmit` و`SessionEnd`. أمر شريط الحالة الحالي لديك يُحفظ ويظل يُعرض كما هو.
2. مع كل تحديث لشريط الحالة تُقرأ `rate_limits.five_hour.resets_at` وتُجدول مهمة `at` عند موعد إعادة التعيين + 15 ثانية.
3. عند بلوغ الحد تُسجَّل الجلسة (مقبس tmux واللوحة والنافذة و`pane_current_command` ودليل العمل) في `state/pending/`، وتُجدول المهمة نفسها.
4. عند إعادة التعيين تنفذ المهمة الأمر `scheduled`:
   - وجود جلسات منتظرة ← إرسال `send-keys continue` إلى كل لوحة، بحد أقصى محاولتان لكل جلسة، ثم إعادة الفحص بعد 90 ثانية.
   - لا شيء منتظر ← تنفيذ `claude -p --model haiku --safe-mode --tools "" 'Reply only OK.'`، وتُقدَّر المهمة التالية بعد 5 ساعات و15 ثانية من بدء الطلب.
5. تُمسح السجلات المنتظرة بمجرد أن تكتب أنت شيئًا (`UserPromptSubmit`) أو تنتهي الجلسة (`SessionEnd`).
6. بلوغ حد الأيام السبعة 100% ← ينتظر كل شيء إعادة التعيين الأسبوعية.

### الحماية من الإرسال الخاطئ

لا تُرسل `continue` إلا إذا كانت اللوحة ما تزال موجودة، وتابعة لجلسة tmux نفسها، وتشغّل الأمر نفسه الذي كانت تشغّله لحظة بلوغ الحد. وإلا يُنقل السجل إلى `state/stale/` ولا يُكتب شيء. أما الجلسات خارج tmux فتُسجَّل في السجل فقط — إذ لا توجد لوحة يمكن الكتابة فيها.

يُعاد المحاولة بعد فشل الإحماء بفواصل 60 و120 و300 و600 ثانية. وإذا بدا المخرج كأن تسجيل الدخول قد انتهت صلاحيته، يتوقف الإحماء التلقائي مؤقتًا، ويُكتب `state/auth_required` (ويُظهر `status` عبارة `RELOGIN MAY BE REQUIRED`)، ثم تُعاد المحاولة بعد ساعة.

## المتطلبات

`claude` و`jq` و`at` (مع تشغيل `atd`) و`flock` و`timeout` و`tmux` و`date` من GNU.

```bash
sudo systemctl enable --now atd
```

## التثبيت

```bash
npx @claude-plus/claude-plus
```

أو من نسخة مستنسخة:

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

يُزال أي تثبيت سابق أولًا — مهام `at` الخاصة به ومدخلات `statusLine` والخطافات ومجلد `~/.claude/claude-plus/` — لذا فإن إعادة تشغيل المثبِّت ترقية نظيفة. أما خطافات الأدوات الأخرى فتبقى دون مساس. ويُحفظ `settings.json` باسم `settings.json.claude-plus-install-backup.<الطابع الزمني>`.

بعد ذلك تحقق داخل Claude Code عبر `/hooks` من وجود `StopFailure` و`UserPromptSubmit` و`SessionEnd`.

## الاستخدام

```bash
~/.claude/claude-plus/claude-plus.sh status   # الإصدار والجدولة وعدد المنتظرين وحالة المصادقة
~/.claude/claude-plus/claude-plus.sh pending  # الجلسات التي تنتظر الاستئناف
~/.claude/claude-plus/claude-plus.sh notify-test  # إرسال إشعار تجريبي إلى نفسك
tail -f ~/.claude/claude-plus/claude-plus.log # السجل
```

## الإشعارات

يبقى Claude Plus صامتًا ما لم يكن هناك ما يستدعي تدخلك. وهو ينفذ
`~/.claude/claude-plus/notify.sh` — أي ملف تنفيذي تختاره — عند ثلاثة أحداث:

| الحدث | متى |
|-------|-----|
| `auth-required` | Claude Code خارج نطاق تسجيل الدخول، فلا يمكن فتح أي نافذة |
| `warmup-failing` | فشل الإحماء ثلاث مرات متتالية |
| `recovered` | عودة الإحماء إلى النجاح بعد أي من الحالتين أعلاه |

ينطلق كل حدث مرة واحدة عند الدخول في تلك الحالة، لا مع كل محاولة إعادة، فمشكلة تقع
أثناء الليل تكلفك رسالة واحدة بدل ثماني رسائل.

تُثبَّت نماذج لـ Bark وntfy والبريد عبر SMTP في `~/.claude/claude-plus/notify/`.
اختر أحدها، واملأ مفتاحك أو خادمك، ثم جرّبه:

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh
chmod +x notify.sh          # استخدم 700 لنموذج البريد لأنه يحتوي على كلمة مرور
$EDITOR notify.sh
./claude-plus.sh notify-test
```

يُشغَّل السكربت ومعه `CP_EVENT` و`CP_MESSAGE` و`CP_HOST` في بيئته، لذا فإن أي قناة أخرى
— Telegram أو Slack أو خطاف ويب أو `mail` — ليست سوى إعادة كتابة لأمر `curl` الوحيد ذاك.
وإعادة التثبيت تُبقي ملف `notify.sh` الخاص بك.

أما حدود الاستخدام نفسها فلا يُرسل عنها إشعار أبدًا: فهي أمر معتاد، والاستئناف يتكفل بها،
ورسالة في كل مرة لن تكون سوى ضجيج.

## الملفات

| المسار | الوصف |
|--------|-------|
| `~/.claude/claude-plus/claude-plus.sh` | السكربت الرئيسي |
| `~/.claude/claude-plus/state/` | أوقات إعادة التعيين ومعرّف المهمة وعدد الإخفاقات وعلم المصادقة |
| `~/.claude/claude-plus/state/pending/` | جلسات توقفت عند الحد وتنتظر الاستئناف |
| `~/.claude/claude-plus/state/stale/` | سجلات أُهملت لأن اللوحة تغيّرت |
| `~/.claude/claude-plus/original-statusline-command` | أمر شريط الحالة السابق لديك |
| `~/.claude/claude-plus/notify.sh` | سكربت الإشعارات الخاص بك، إن أعددته |
| `~/.claude/claude-plus/notify/` | نماذج سكربتات للنسخ منها |
| `~/.claude/claude-plus/claude-plus.log` | السجل |

## إلغاء التثبيت

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<الطابع الزمني> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```

## الرخصة

GPL-3.0-or-later. انظر [LICENSE](LICENSE).
