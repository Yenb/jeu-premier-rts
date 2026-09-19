# INTERDITS ABSOLUS DE DESTRUCTION — À VIOLER = SUPPRESSION DE CLAUDE CODE PAR L'UTILISATEUR

Les commandes suivantes sont interdites à Claude Code sur ce projet, quelle que soit la raison, quel que soit le contexte, y compris quand elles semblent réparer un problème :

- `Remove-Item -Recurse -Force` (sur toute cible)
- `Remove-Item` sur un dossier (`.git`, `projet godot`, `jeu`, `extension_terrain`, `data`, `scripts`, `addons`, `godot-cpp`, `documents`)
- `Move-Item` sur un dossier de plus de 10 fichiers
- `git init` dans un dossier qui n'était pas déjà un dépôt
- `git reset --hard`, `git clean -fd`, `git checkout --` sur des fichiers non lus
- Toute création, suppression ou déplacement de `.git`
- Toute modification de la structure de dossiers du projet (déplacer un dossier, aplatir une hiérarchie, réorganiser)

Le 18/09/2026 à 17:06, Claude Code (opus-4-6) a exécuté `Remove-Item -Recurse -Force ".git"` avec sa propre description « Remove the broken .git I created ». L'incident a coûté une journée entière de récupération à l'utilisateur. Cette règle existe à cause de ça.

En cas de doute : ARRÊTE, DEMANDE. Ne bricole pas.
