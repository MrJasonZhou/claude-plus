# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | Français | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Des extensions pour Claude Code, pilotées par des tâches `at` :

- **Reprise** — lorsqu'une session s'arrête sur une limite d'usage dans tmux, `continue` est saisi dans ce pane dès que la limite est réinitialisée.
- **Maintien** — s'il n'y a rien à reprendre, une minuscule requête Haiku ouvre une nouvelle fenêtre de 5 heures.

## À quoi cela sert

**Repartir après une limite de 5 heures.** D'ordinaire, atteindre le plafond signifie que la session s'arrête net et que vous revenez plus tard la relancer à la main. Ici, `continue` est saisi dans le pane à l'instant même où la limite est réinitialisée : le travail repart où il s'était arrêté, y compris pendant votre sommeil ou votre absence.

**L'heure d'ouverture de la fenêtre décide de son heure de fin.** Une fenêtre de 5 heures démarre à votre première requête, pas à une heure fixe. Commencez à 9h00 et la fenêtre court de 9h00 à 14h00 ; épuisez le quota à 11h00 et vous êtes bloqué jusqu'à 14h00. Si une minuscule requête avait ouvert la fenêtre à 6h00, celle-ci expirerait à 11h00 — précisément quand vous êtes à sec — avec un quota neuf déjà prêt. Garder une fenêtre toujours active pousse sa réinitialisation avant vos heures de travail plutôt qu'en plein milieu.

## Fonctionnement

1. L'installation réécrit `~/.claude/settings.json` : `statusLine` et trois hooks — `StopFailure` (matcher `rate_limit`), `UserPromptSubmit`, `SessionEnd`. Votre commande de status line existante est sauvegardée et toujours affichée.
2. Chaque rafraîchissement de la status line lit `rate_limits.five_hour.resets_at` et planifie une tâche `at` pour la réinitialisation + 15 s.
3. Atteindre une limite enregistre la session (socket tmux, pane, fenêtre, `pane_current_command`, cwd) sous `state/pending/` et planifie la même tâche.
4. À la réinitialisation, la tâche exécute `scheduled` :
   - Sessions en attente → `send-keys continue` vers chaque pane, 2 tentatives au maximum par session, puis nouvelle vérification après 90 s.
   - Rien en attente → `claude -p --model haiku --safe-mode --tools "" 'Reply only OK.'`, et la tâche suivante est estimée à 5 h + 15 s après le début de la requête.
5. Les entrées en attente sont effacées dès que vous saisissez quelque chose vous-même (`UserPromptSubmit`) ou que la session se termine (`SessionEnd`).
6. Limite de 7 jours à 100 % → tout attend la réinitialisation hebdomadaire.

### Garde-fous

Un `continue` n'est envoyé que si le pane existe toujours, appartient toujours à la même session tmux et exécute toujours la même commande qu'au moment de la limite. Sinon l'entrée est archivée dans `state/stale/` et rien n'est saisi. Les sessions hors tmux sont seulement journalisées — il n'y a aucun pane où écrire.

Un warm-up en échec est retenté après 60 s / 120 s / 300 s / 600 s. Si la sortie ressemble à une connexion expirée, le warm-up automatique se met en pause, `state/auth_required` est écrit (`status` affiche `RELOGIN MAY BE REQUIRED`) et une nouvelle vérification a lieu une heure plus tard.

## Prérequis

`claude`, `jq`, `at` (avec `atd` démarré), `flock`, `timeout`, `tmux`, GNU `date`.

```bash
sudo systemctl enable --now atd
```

## Installation

```bash
npx @mrjasonzhou/claude-plus
```

Ou depuis un clone :

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

Toute installation précédente est retirée d'abord — ses tâches `at`, ses entrées `statusLine` et de hooks, ainsi que `~/.claude/claude-plus/` — relancer l'installateur revient donc à une mise à jour propre. Les hooks d'autres outils ne sont pas touchés. `settings.json` est sauvegardé sous `settings.json.claude-plus-install-backup.<horodatage>`.

Ensuite, vérifiez avec `/hooks` dans Claude Code la présence de `StopFailure`, `UserPromptSubmit` et `SessionEnd`.

## Utilisation

```bash
~/.claude/claude-plus/claude-plus.sh status   # version, planification, en attente, état d'authentification
~/.claude/claude-plus/claude-plus.sh pending  # sessions attendant une reprise
~/.claude/claude-plus/claude-plus.sh notify-test  # s'envoyer une notification de test
tail -f ~/.claude/claude-plus/claude-plus.log # journal
```

## Notifications

Claude Plus reste silencieux tant que rien ne requiert votre attention. Il exécute
`~/.claude/claude-plus/notify.sh` — n'importe quel exécutable — sur trois événements :

| Événement | Quand |
|-----------|-------|
| `auth-required` | Claude Code est déconnecté, aucune fenêtre ne peut être ouverte |
| `warmup-failing` | Trois warm-ups ont échoué d'affilée |
| `recovered` | Les warm-ups réussissent de nouveau après l'un des deux cas |

Chaque événement se déclenche une seule fois à l'entrée dans cet état, pas à chaque
nouvelle tentative : un problème nocturne vous coûte un message et non huit.

Des exemples pour Bark, ntfy et l'e-mail SMTP sont installés dans
`~/.claude/claude-plus/notify/`. Choisissez-en un, renseignez votre clé ou votre
serveur, puis testez :

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh
chmod +x notify.sh          # 700 pour celui de l'e-mail, il contient un mot de passe
$EDITOR notify.sh
./claude-plus.sh notify-test
```

Le script est lancé avec `CP_EVENT`, `CP_MESSAGE` et `CP_HOST` dans son environnement ;
tout le reste — Telegram, Slack, un webhook, `mail` — se résume à réécrire cette seule
commande `curl`. Une réinstallation conserve votre `notify.sh`.

Les limites d'usage elles-mêmes ne donnent jamais lieu à notification : elles sont
courantes, la reprise s'en charge, et un message à chaque fois ne serait que du bruit.

## Fichiers

| Chemin | Description |
|--------|-------------|
| `~/.claude/claude-plus/claude-plus.sh` | Script principal |
| `~/.claude/claude-plus/state/` | Heures de réinitialisation, id de tâche, compteur d'échecs, drapeau d'authentification |
| `~/.claude/claude-plus/state/pending/` | Sessions arrêtées sur une limite, en attente de reprise |
| `~/.claude/claude-plus/state/stale/` | Entrées abandonnées parce que le pane a changé |
| `~/.claude/claude-plus/original-statusline-command` | Votre commande de status line précédente |
| `~/.claude/claude-plus/notify.sh` | Votre script de notification, si vous en avez installé un |
| `~/.claude/claude-plus/notify/` | Exemples de scripts à copier |
| `~/.claude/claude-plus/claude-plus.log` | Journal |

## Désinstallation

```bash
atrm "$(cat ~/.claude/claude-plus/state/at_job)"
cp ~/.claude/settings.json.claude-plus-install-backup.<horodatage> ~/.claude/settings.json
rm -rf ~/.claude/claude-plus
```

## Licence

GPL-3.0-or-later. Voir [LICENSE](LICENSE).
