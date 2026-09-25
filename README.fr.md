# Claude Plus

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [Deutsch](README.de.md) | Français | [Italiano](README.it.md) | [Português](README.pt.md) | [العربية](README.ar.md)

Deux choses que votre agent de code ne fait pas pour vous, prises en charge pendant que vous êtes loin du clavier.

- **Fenêtre toujours ouverte** — une nouvelle fenêtre d'usage s'ouvre dès que la précédente est réinitialisée, même si personne ne travaille : à votre retour, un quota plein est déjà en cours.
- **Alerte** — quand cela ne fonctionne plus, il vous prévient : Bark, ntfy, e-mail, ou tout autre canal que vous voudrez brancher.

Reprendre une session après une limite d'usage, les agents le font désormais eux-mêmes ; Claude Plus le leur laisse.

## Agents

Claude Code, Codex et Antigravity comptabilisent un abonnement de la même façon : une fenêtre courte qui démarre à votre première requête, et une plus longue par-dessus. Claude Plus entretient ceux que vous avez installés.

| Agent | D'où viennent ses limites | Modifications de sa configuration |
|---|---|---|
| Claude Code | sa status line, à chaque rafraîchissement | une entrée de status line |
| Codex | ses journaux de session, lus au besoin | aucune |
| Antigravity | sa status line, à chaque rafraîchissement | une entrée de status line |

Chaque agent a sa propre fenêtre, sa propre planification et ses propres alertes ; rien n'est partagé. En ajouter un autre tient en un fichier — voir [docs/PROVIDERS.md](docs/PROVIDERS.md). Si l'interface précise le mode de comptage, c'est pour une raison : chez Kimi Code, la fenêtre courte limite le débit des requêtes plutôt qu'un quota, et Grok Build n'a qu'un pot hebdomadaire sans fenêtre courte — dans ces cas-là, il n'y aurait aucune fenêtre à garder ouverte.

## À quoi cela sert

**L'heure d'ouverture de la fenêtre décide de son heure de fin.** Une fenêtre démarre à votre première requête, pas à une heure fixe. Avec une fenêtre de cinq heures : commencez à 9h00 et elle court de 9h00 à 14h00 ; épuisez le quota à 11h00 et vous êtes bloqué jusqu'à 14h00. Si une minuscule requête avait ouvert la fenêtre à 6h00, celle-ci expirerait à 11h00 — précisément quand vous êtes à sec — avec un quota neuf déjà prêt. Avec une fenêtre toujours active, il y en a déjà une en cours quand vous commencez : ce qu'il en reste est du quota qui serait sinon perdu, et un quota neuf arrive au plus dans une fenêtre, généralement bien moins.

**Une journée de travail contient plus de fenêtres quand elles commencent tôt.** Commencez à 9h00 et les fenêtres courent de 9h00 à 14h00 puis de 14h00 à 19h00 : deux avant la fin de votre journée. Si l'une s'était ouverte à 6h00, la journée serait couverte par 6h00-11h00, 11h00-16h00 et 16h00-21h00 — trois, pour les mêmes heures au bureau. C'est à cela que sert l'heure fixe, plus bas.

**Savoir quand il a cessé d'aider.** Garder des fenêtres ouvertes ne fonctionne que tant qu'une authentification est valide et que le planificateur tourne ; si l'un des deux s'arrête, plus rien ne se passe. Claude Plus repère l'un comme l'autre et vous le dit, au lieu d'échouer en silence tout un week-end.

## Prérequis

Linux, avec `jq`, `at` (avec `atd` démarré), `flock`, `timeout`, GNU `date`, et au moins l'un de `claude`, `codex` ou `agy`.

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

Pour chaque agent doté d'une status line, l'installateur enveloppe celle que vous aviez déjà, qui s'affiche exactement comme avant ; c'est la seule modification apportée aux réglages de cet agent, et chaque fichier de réglages est sauvegardé au préalable. Codex ne demande aucune configuration. Relancer l'installateur revient à une mise à jour propre plutôt qu'à une seconde installation, et conserve pour chaque agent sa prochaine exécution planifiée, son état et votre notificateur.

## Utilisation

Au quotidien, il n'y a rien à lancer — il travaille tout seul. Quand vous voulez regarder :

```bash
~/.claude/claude-plus/claude-plus.sh status    # par agent : fenêtre, planification, échecs
~/.claude/claude-plus/claude-plus.sh providers # quels agents sont installés
tail -f ~/.claude/claude-plus/claude-plus.log  # ce qu'il a fait
```

## Ouvrir à une heure fixe

Par défaut, une fenêtre s'ouvre dès que la précédente est réinitialisée : la chaîne suit donc l'heure à laquelle vous avez épuisé votre quota la dernière fois. Pour la fixer à une heure de la journée :

```bash
~/.claude/claude-plus/claude-plus.sh anchor 06:00   # ouvrir à 06h00
~/.claude/claude-plus/claude-plus.sh anchor         # afficher le réglage
~/.claude/claude-plus/claude-plus.sh anchor off     # revenir à une ouverture dès que possible
```

Une fenêtre qui courrait par-dessus cette heure l'attend : celle prévue à 03h00 couvrirait 03h00-08h00 et avalerait 06h00, elle s'ouvre donc à 06h00. Les heures qui précèdent restent alors sans fenêtre — si vous travaillez à ce moment-là, votre propre première requête en ouvre une comme d'habitude. Le réglage vaut pour tous les agents.

## Alertes

Claude Plus reste silencieux tant que rien ne requiert votre attention, et ne signale que quatre choses :

| | |
|---|---|
| **Déconnecté** | L'authentification d'un agent a expiré : rien ne peut être ouvert pour lui tant que vous ne vous reconnectez pas |
| **Échecs répétés** | Plusieurs warm-ups d'affilée ont échoué pour un agent |
| **Planificateur arrêté** | Une exécution prévue a largement dépassé son heure : aucune fenêtre n'est maintenue ouverte ; en général `atd` ne tourne pas |
| **Retour à la normale** | Il s'est remis de l'un des cas ci-dessus |

Chaque cas est signalé une seule fois par agent, pas à chaque nouvelle tentative : un problème nocturne vous coûte un unique message. Les limites d'usage elles-mêmes ne sont jamais annoncées : elles sont courantes, et les agents reprennent ensuite d'eux-mêmes.

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
| `providers/` | Un fichier par agent |
| `state/<agent>/` | Fenêtre, planification et état des alertes de cet agent |
| `notify.sh` | Votre notificateur, une fois configuré |
| `notify/` | Exemples à copier |
| `anchor` | L'heure d'ouverture des fenêtres, si vous en avez défini une |
| `claude-plus.log` | Ce qu'il a fait |

## Désinstallation

```bash
npx @claude-plus/claude-plus uninstall
```

Ou depuis un clone : `bash install-claude-plus.sh uninstall`.

Elle modifie les réglages de chaque agent sur place et n'en retire que ce que Claude Plus y a ajouté : votre status line revient, et tous les autres réglages restent exactement tels quels — y compris ceux ajoutés après l'installation. Ses tâches planifiées sont annulées et `~/.claude/claude-plus/` est supprimé, votre `notify.sh` avec. La relancer une seconde fois ne fait aucun mal.

Si un autre programme a depuis enveloppé une status line autour de Claude Plus, la désinstallation ne le casse pas. Un petit script relais est laissé en place pour que ce programme continue de fonctionner, et le désinstallateur vous le signale ; relancez-le quand plus rien n'en a besoin. Une mise à jour dans la même situation reste à l'intérieur de la chaîne de ce programme au lieu de l'envelopper à son tour.

Une copie de chaque fichier de réglages datant de juste avant la désinstallation est conservée à côté, tout comme les copies faites à l'installation, au cas où vous voudriez un jour revenir en arrière à la main.

## Licence

GPL-3.0-or-later. Voir [LICENSE](LICENSE).
