# SESSION SUIVANTE

Document de passation, NON permanent. À lire une fois au début de la
prochaine session Claude, puis à mettre à jour ou supprimer. Il ne
duplique rien qui vit ailleurs (`CLAUDE.md`, `SUIVI.md`, `LOGBOOK.md`,
`CARNET_DE_JEU.md`, git log) — il donne juste le POINT DE REPRISE.

## Où on en est

Le banc `jeu/Outil de jeu/test_ennemi.tscn` est complet et jouable. Un
écosystème émergent y tourne : cube violet → transporteurs → gisement →
mode combat au coup → soldat qui chasse le joueur → joueur avec vie et
mort. Framework composé partout (`Perception`, `Proximite`, `Frappe`,
`Consommer`, `Gestation`, `LienPersonnel`). Aucun mécanisme neuf écrit,
seulement de la composition.

Un banc jouet `test_ennemi2 Mother box.tscn` a été dupliqué en secours
avant refonte — c'est là que doit se construire la Ruche mère.

## La prochaine étape voulue par Yael

Construire la RUCHE MÈRE (queen pattern) — voir `LOGBOOK.md § L'explosion
en zone riche` pour le problème qu'elle résout. Résumé design déjà validé
en session :

- Cube MASSIF (~3 m de côté), très visible
- Vie 1000 (choix stratégique du joueur : attaquer la ruche à long
  terme, ou nettoyer les cubes rapidement)
- Produit des cubes violets à cadence fixe GRATUITE (garantit un flux
  minimum même sans ressources — c'est le pattern qui résout le
  démarrage exponentiel trop lent)
- Plafond de 10 cubes violets vivants max
- Répond au signal d'attaque comme les autres cubes

Six questions restent ouvertes, listées dans le log de la session
précédente — reformuler avec Yael avant d'écrire une ligne.

Emplacement : dans `jeu/Outil de jeu/test_ennemi2 Mother box.tscn`.

## Décisions de design prises aujourd'hui, non écrites ailleurs

- **Le mode combat est PERSISTANT** (pas de timer) : il ne s'éteint
  qu'après la naissance d'un soldat, `sortir_du_mode_combat()` appelée
  par `gestation_soldat`. Un timer rendait la production mathématiquement
  impossible (5 dépôts + 30 s de gestation > 30 s de timer). Voir
  `vie_ennemi.gd` en-tête.
- **Les transporteurs choisissent leur cube de dépôt via perception +
  saillance**, pas via référence en dur — voir `transporteur.gd:
  _chercher_cube_disponible_autre_que_mere`. Le jour où on ajoute une
  Ruche mère qui accepte aussi des dépôts, elle porte juste le profil
  `cube_violet_disponible` et ça marche.
- **Le rayon défensif s'applique à la CIBLE, pas au soldat** en chasse
  (`soldat.gd`). Sans cette distinction : yo-yo permanent au bord du
  rayon.
- **Deux insights de communication** (voir échanges de fin de session) :
  choisir un TERRAIN D'ÎLES pour révéler l'émergence lointaine ; ne
  jamais communiquer publiquement sur la RECETTE (systèmes composés),
  seulement sur l'EFFET (moments vécus).

## Pièges à éviter (déjà payés)

- `is Node3D` sur une référence libérée = crash Godot 4. TOUJOURS
  `is_instance_valid(x) and x is ...`.
- Filtrer les perceptions AVANT `Proximite.evaluer` — sinon
  `push_error` spam pour tout profil de saillance absent du catalogue
  local (le soldat percevait les cubes violets alors qu'il ne connaît
  que `joueur_menace`).
- `_foyer` d'un transporteur/soldat fixé dans `_ready` = position par
  défaut (0,0,0) car le repositionnement du garde arrive APRÈS.
  Différer d'une frame.
- Avec Jolt Physics (utilisé ici), les Area3D détectent les
  CharacterBody3D par défaut. Un projectile spawné devant le tireur
  déclenche `body_entered` sur le corps du tireur immédiatement. Il
  faut exclure le tireur dans le raycast ET dans `_sur_impact`.
- Godot déplace physiquement les fichiers quand tu drag-and-drop dans
  le panneau système — ce qui casse les preload en dur. Sur toute
  réorganisation, vérifier les paths avec `grep -rl "res://..."` et
  rewrite avec `sed` avant de tester.

## Comportement attendu de moi, prochaine session

Voir `CLAUDE.md § Discipline de travail` points 1 à 11. En particulier :

- Point 11 : livraison en trois blocs **Fait / Anticipé / Non fait**
  à chaque ajout de comportement. Systématique.
- Point 10 : distinguer un clic éditeur d'un défaut de code.
- Feedback mémoire : ralentir avant de retenter, expliquer avant.

## Ce que je ne suis PAS censé faire d'entrée

- Toucher au framework (`scripts/`) sans le dire d'abord — c'est
  l'exception `CLAUDE.md § Frontière`, jamais un réflexe.
- Créer un nouveau banc pour la Ruche mère : Yael a dupliqué le fichier
  test_ennemi2 lui-même, c'est là qu'il faut travailler.
- Écrire des documents sans nécessité — la doctrine du projet est
  stricte sur la croissance de la doc (5 questions avant chaque phrase,
  plafond en octets par `test_volume_docs.gd`).
