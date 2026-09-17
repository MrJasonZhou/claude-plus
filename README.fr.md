# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | Français | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Trois choses que Claude Code ne fait pas pour vous, prises en charge pendant que vous êtes loin du clavier.

- **Reprise** — une session arrêtée par une limite d'usage repart d'elle-même à l'instant où la limite est réinitialisée, et poursuit le travail en cours.
- **Fenêtre toujours ouverte** — s'il n'y a rien à reprendre, une nouvelle fenêtre de 5 heures est tout de même ouverte, afin que sa réinitialisation tombe en dehors de vos heures de travail plutôt qu'en plein milieu.
- **Alerte** — lorsqu'il ne peut plus continuer seul, il vous prévient : Bark, ntfy, e-mail, ou tout autre canal que vous voudrez brancher.

## À quoi cela sert

**Repartir après une limite de 5 heures.** D'ordinaire, atteindre le plafond signifie que la session s'arrête net et que vous revenez plus tard la relancer à la main. Claude Plus la relance pour vous à l'instant même où la limite est réinitialisée : le travail repart où il s'était arrêté, y compris pendant votre sommeil ou votre absence.

**L'heure d'ouverture de la fenêtre décide de son heure de fin.** Une fenêtre de 5 heures démarre à votre première requête, pas à une heure fixe. Commencez à 9h00 et la fenêtre court de 9h00 à 14h00 ; épuisez le quota à 11h00 et vous êtes bloqué jusqu'à 14h00. Si une minuscule requête avait ouvert la fenêtre à 6h00, celle-ci expirerait à 11h00 — précisément quand vous êtes à sec — avec un quota neuf déjà prêt. Garder une fenêtre toujours active pousse sa réinitialisation avant vos heures de travail plutôt qu'en plein milieu.

**Savoir quand il a cessé d'aider.** La reprise automatique ne fonctionne que tant que votre session d'authentification est valide ; une fois expirée, plus rien ne marche. Claude Plus repère ce cas et vous le dit, au lieu d'échouer en silence tout un week-end.

## Ce qu'il ne fera pas

Reprendre, c'est écrire dans le terminal où vous travailliez : il fait donc très attention à l'endroit où il écrit. Une session n'est reprise que si elle est toujours là, intacte, exactement telle que la limite l'a laissée. Si vous l'avez fermée, êtes passé à autre chose, ou avez lancé autre chose dans ce terminal, Claude Plus n'y touche pas et reste silencieux. Les sessions hors de tmux ne sont jamais reprises — il n'y a nulle part où écrire.

Les limites d'usage elles-mêmes ne sont jamais annoncées. Elles sont courantes, la reprise s'en charge, et un message à chaque fois ne serait que du bruit.

## Prérequis

`claude`, `jq`, `at` (avec `atd` démarré), `flock`, `timeout`, `tmux`, GNU `date`.

```bash
sudo systemctl enable --now atd
```

## Installation

```bash
npx @claude-plus/claude-plus
```

Ou depuis un clone :

```bash
git clone https://github.com/MrJasonZhou/claude-plus.git
cd claude-plus
bash install-claude-plus.sh
```

L'installateur reprend votre status line et ajoute ses propres hooks, tout en conservant la status line que vous aviez déjà et sans toucher aux hooks des autres outils. Votre `settings.json` est sauvegardé au préalable, et relancer l'installateur revient à une mise à jour propre plutôt qu'à une seconde installation.

## Utilisation

Au quotidien, il n'y a rien à lancer — il travaille tout seul. Quand vous voulez regarder :

```bash
~/.claude/claude-plus/claude-plus.sh status   # ce qui est planifié, ce qui attend, l'authentification est-elle valide
~/.claude/claude-plus/claude-plus.sh pending  # sessions attendant une reprise
tail -f ~/.claude/claude-plus/claude-plus.log # ce qu'il a fait
```

## Alertes

Claude Plus reste silencieux tant que rien ne requiert votre attention, et ne signale que trois choses :

| | |
|---|---|
| **Déconnecté** | Votre authentification Claude Code a expiré : rien ne peut être ouvert tant que vous ne vous reconnectez pas |
| **Échecs répétés** | Plusieurs warm-ups d'affilée ont échoué |
| **Retour à la normale** | Il s'est remis de l'un ou l'autre des cas ci-dessus |

Chaque cas est signalé une seule fois, pas à chaque nouvelle tentative : un problème nocturne vous coûte un unique message.

Pour choisir comment en être informé, copiez l'un des exemples et renseignez votre clé ou votre serveur :

```bash
cd ~/.claude/claude-plus
cp notify/bark.sh.sample notify.sh      # ou ntfy.sh.sample, email.sh.sample
chmod +x notify.sh                      # 700 pour celui de l'e-mail, il contient un mot de passe
$EDITOR notify.sh
./claude-plus.sh notify-test            # vérifier que cela vous parvient
```

Le notificateur n'est qu'un exécutable qui reçoit `CP_EVENT`, `CP_MESSAGE` et `CP_HOST` ; Telegram, Slack, un webhook ou `mail` se résument donc à réécrire une ligne. Votre version survit aux réinstallations.

## Fichiers

Tout se trouve dans `~/.claude/claude-plus/` :

| | |
|---|---|
| `claude-plus.sh` | Le script lui-même |
| `notify.sh` | Votre notificateur, une fois configuré |
| `notify/` | Exemples à copier |
| `claude-plus.log` | Ce qu'il a fait |
| `state/` | Comptabilité interne |

## Désinstallation

```bash
npx @claude-plus/claude-plus uninstall
```

Ou depuis un clone : `bash install-claude-plus.sh uninstall`.

Elle modifie votre `settings.json` actuel sur place et n'en retire que ce que Claude Plus y a ajouté : votre propre status line revient, et tous les autres réglages et hooks restent exactement tels quels — y compris ceux ajoutés après l'installation de Claude Plus. Ses tâches planifiées sont annulées et `~/.claude/claude-plus/` est supprimé, votre `notify.sh` avec. La relancer une seconde fois ne fait aucun mal.

Une copie de `settings.json` datant de juste avant la désinstallation est conservée à côté, tout comme les copies faites à l'installation, au cas où vous voudriez un jour revenir en arrière à la main.

## Licence

GPL-3.0-or-later. Voir [LICENSE](LICENSE).
