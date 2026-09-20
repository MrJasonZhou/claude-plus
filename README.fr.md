# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | Français | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Deux choses que Claude Code ne fait pas pour vous, prises en charge pendant que vous êtes loin du clavier.

- **Fenêtre toujours ouverte** — une nouvelle fenêtre de 5 heures s'ouvre dès que la précédente est réinitialisée, même si personne n'utilise Claude Code : à votre retour, un quota plein est déjà en cours.
- **Alerte** — quand cela ne fonctionne plus, il vous prévient : Bark, ntfy, e-mail, ou tout autre canal que vous voudrez brancher.

Reprendre une session après une limite d'usage, Claude Code le fait désormais lui-même : voir « Continue automatically at usage limit » dans `/config`. Claude Plus le faisait aussi avant la 3.0.0, et le laisse depuis à Claude Code.

## À quoi cela sert

**L'heure d'ouverture de la fenêtre décide de son heure de fin.** Une fenêtre de 5 heures démarre à votre première requête, pas à une heure fixe. Commencez à 9h00 et la fenêtre court de 9h00 à 14h00 ; épuisez le quota à 11h00 et vous êtes bloqué jusqu'à 14h00. Si une minuscule requête avait ouvert la fenêtre à 6h00, celle-ci expirerait à 11h00 — précisément quand vous êtes à sec — avec un quota neuf déjà prêt. Avec une fenêtre toujours active, il y en a déjà une en cours quand vous commencez : ce qu'il en reste est du quota qui serait sinon perdu, et un quota neuf arrive dans cinq heures au plus, généralement bien moins.

**Savoir quand il a cessé d'aider.** Garder des fenêtres ouvertes ne fonctionne que tant que votre authentification est valide et que le planificateur tourne ; si l'un des deux s'arrête, plus rien ne se passe. Claude Plus repère l'un comme l'autre et vous le dit, au lieu d'échouer en silence tout un week-end.

## Prérequis

Linux, avec `claude`, `jq`, `at` (avec `atd` démarré), `flock`, `timeout`, GNU `date`.

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

L'installateur enveloppe votre status line existante, qui s'affiche exactement comme avant ; c'est la seule modification qu'il apporte à vos réglages. Votre `settings.json` est sauvegardé au préalable, et relancer l'installateur revient à une mise à jour propre plutôt qu'à une seconde installation. Une mise à jour conserve la prochaine exécution planifiée, son état et votre notificateur. Une mise à jour depuis la 2.x retire aussi les hooks que ces versions ajoutaient pour reprendre les sessions.

## Utilisation

Au quotidien, il n'y a rien à lancer — il travaille tout seul. Quand vous voulez regarder :

```bash
~/.claude/claude-plus/claude-plus.sh status   # le planificateur tourne-t-il, ce qui est planifié, l'authentification est-elle valide
tail -f ~/.claude/claude-plus/claude-plus.log # ce qu'il a fait
```

## Ouvrir à une heure fixe

Par défaut, une fenêtre s'ouvre dès que la précédente est réinitialisée : la chaîne suit donc l'heure à laquelle vous avez épuisé votre quota la dernière fois. Pour la fixer à une heure de la journée :

```bash
~/.claude/claude-plus/claude-plus.sh anchor 06:00   # ouvrir à 06h00
~/.claude/claude-plus/claude-plus.sh anchor         # afficher le réglage
~/.claude/claude-plus/claude-plus.sh anchor off     # revenir à une ouverture dès que possible
```

Une fenêtre qui courrait par-dessus cette heure l'attend : celle prévue à 03h00 couvrirait 03h00-08h00 et avalerait 06h00, elle s'ouvre donc à 06h00. Les heures qui précèdent restent alors sans fenêtre — si vous travaillez à ce moment-là, votre propre première requête en ouvre une comme d'habitude.

## Alertes

Claude Plus reste silencieux tant que rien ne requiert votre attention, et ne signale que quatre choses :

| | |
|---|---|
| **Déconnecté** | Votre authentification Claude Code a expiré : rien ne peut être ouvert tant que vous ne vous reconnectez pas |
| **Échecs répétés** | Plusieurs warm-ups d'affilée ont échoué |
| **Planificateur arrêté** | Une exécution prévue a largement dépassé son heure : aucune fenêtre n'est maintenue ouverte ; en général `atd` ne tourne pas |
| **Retour à la normale** | Il s'est remis de l'un des cas ci-dessus |

Chaque cas est signalé une seule fois, pas à chaque nouvelle tentative : un problème nocturne vous coûte un unique message. Les limites d'usage elles-mêmes ne sont jamais annoncées : elles sont courantes, et Claude Code reprend ensuite de lui-même.

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
| `anchor` | L'heure d'ouverture des fenêtres, si vous en avez défini une |
| `claude-plus.log` | Ce qu'il a fait |
| `state/` | Comptabilité interne |

## Désinstallation

```bash
npx @claude-plus/claude-plus uninstall
```

Ou depuis un clone : `bash install-claude-plus.sh uninstall`.

Elle modifie votre `settings.json` actuel sur place et n'en retire que ce que Claude Plus y a ajouté : votre propre status line revient, et tous les autres réglages et hooks restent exactement tels quels — y compris ceux ajoutés après l'installation de Claude Plus. Ses tâches planifiées sont annulées et `~/.claude/claude-plus/` est supprimé, votre `notify.sh` avec. La relancer une seconde fois ne fait aucun mal.

Si un autre programme a depuis enveloppé votre status line autour de Claude Plus, la désinstallation ne le casse pas. Un petit script relais est laissé en place pour que ce programme continue de fonctionner, et le désinstallateur vous le signale ; relancez-le quand plus rien n'en a besoin. Une mise à jour dans la même situation reste à l'intérieur de la chaîne de ce programme au lieu de l'envelopper à son tour.

Une copie de `settings.json` datant de juste avant la désinstallation est conservée à côté, tout comme les copies faites à l'installation, au cas où vous voudriez un jour revenir en arrière à la main.

## Licence

GPL-3.0-or-later. Voir [LICENSE](LICENSE).
