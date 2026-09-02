# Audit — l'exception joueur (CharacterBody3D / move_and_slide / fantôme `_entite_joueur`)

BUT : cartographier tout ce qui, dans le dépôt du jeu, dépend de l'exception
joueur, pour savoir ce qui devra suivre quand cette exception disparaîtra (le
joueur simulé comme une entité data pure via `jeu/Proto/collision.gd`, à l'égal
des cubes).

Référence : `HEAD` = `6ae7494` (working tree porteur de modifications d'autres
chantiers en cours, aucune de cet audit). Aucun fichier de code modifié par cet
audit — seul ce `.md` est écrit.

Motifs recherchés dans tous les `*.gd` du dépôt : `CharacterBody3D`,
`move_and_slide`, `_entite_joueur`, et le nom de nœud du joueur `Personnage`.
Les propriétés/méthodes de l'API `CharacterBody3D` employées par le script
joueur (`velocity`, `is_on_floor()`) sont incluses là où elles portent la
dépendance réelle, même quand le motif littéral ne les nomme pas.

---

## 0. Le partage central : exception vs couplage-observateur

Le joueur est atteint par le reste du dépôt de DEUX façons, à ne pas confondre :

- **L'EXCEPTION** — le code touche l'API physique Godot du joueur :
  `extends CharacterBody3D`, `move_and_slide()`, `velocity`, `is_on_floor()`, ou
  la recopie de la position corrigée data → `_observateur.global_position`.
  C'est CE QUI DOIT SUIVRE quand l'exception tombe. Elle est concentrée dans
  **deux** fichiers de production : `jeu/unites/personnage.gd` et
  `jeu/Proto/manager_proto_2.gd`.

- **LE COUPLAGE-OBSERVATEUR** — une douzaine de fichiers lisent le joueur par le
  groupe `observateur` et n'en prennent que `global_position` : ils le traitent
  comme un simple `Node3D`. Ils ne nomment jamais `CharacterBody3D` ni
  `move_and_slide` et NE DÉPENDENT PAS de l'exception. Concernés (aucun dans la
  liste des motifs, listés ici pour lever le doute) : `terrain_visible.gd`,
  `rendu_terrain_multimesh.gd`, `terrain_streame.gd`, `couvert.gd`,
  `objets_visibles.gd`, `Outil de jeu/inspecteur_bloc.gd`,
  `Outil de jeu/vie_joueur.gd`, `Proto/manager_proto.gd`. Le jour où le joueur
  n'est plus un `CharacterBody3D` mais un `Node3D` piloté par la data, il suffit
  que ce nœud reste dans le groupe `observateur` et expose `global_position` :
  **rien à changer chez eux.**

C'est le résultat structurant de l'audit : la surface à reprendre est petite et
localisée ; le reste lit une position, pas une physique.

---

## 1. Inventaire par fichier, ligne exacte, classé L(ecture) / E(criture) / H(ook)

Convention : **L** le code LIT l'exception (état, position, prédicat) ; **E** le
code ÉCRIT sur l'exception (pose une vélocité, appelle le déplacement, force une
position) ; **H** point-pont bidirectionnel où l'exception est l'autorité qui
relie data et rendu (traité en §3).

### 1.1 `jeu/unites/personnage.gd` — LE joueur, incarnation de l'exception

| ligne | code | classe |
|---|---|---|
| `personnage.gd:1` | `extends CharacterBody3D` | E — définit le joueur comme corps physique Godot |
| `personnage.gd:301` | `velocity.x = horizontale.x` | E — pose la vélocité (API CharacterBody3D) |
| `personnage.gd:302` | `velocity.z = horizontale.z` | E |
| `personnage.gd:307` | `if is_on_floor():` | L — prédicat sol (API CharacterBody3D) |
| `personnage.gd:308` | `velocity.y = 0.0` | E |
| `personnage.gd:310` | `velocity.y -= gravite * delta` | E — gravité appliquée à la vélocité du corps |
| `personnage.gd:312` | `is_on_floor()` (garde du saut) | L |
| `personnage.gd:313` | `velocity.y = vitesse_saut` | E — impulsion de saut |
| `personnage.gd:315` | `move_and_slide()` | E/H — le moteur physique Godot déplace le joueur : autorité à retirer |

Note : `personnage.gd` « n'est appelé par personne » (son propre en-tête, l.63) ;
il lit des touches et pose une vélocité, le moteur fait le reste. Toute la
dépendance à l'exception y est. `depenser_pour_travail`, `nourrir`, les barres
HUD, le pivot souris : indépendants de `CharacterBody3D`.

### 1.2 `jeu/Proto/manager_proto_2.gd` — le fantôme `_entite_joueur` et la recopie

| ligne | code | classe |
|---|---|---|
| `manager_proto_2.gd:28` | en-tête « position corrigée du joueur recopiée dans `_observateur` » | (doc) |
| `manager_proto_2.gd:69` | `var _entite_joueur: Dictionary = {}` | déclaration du fantôme data |
| `manager_proto_2.gd:98-110` | construction de l'entité joueur (capsule, masques, `profil_saillance`) | E (data) — depuis `_observateur.global_position` (L, l.100) |
| `manager_proto_2.gd:111-113` | `Collision.aabb_forme(...)` sur la forme joueur | E (data) |
| `manager_proto_2.gd:114` | `_pos_joueur_prec = _entite_joueur.position` | E (data) |
| `manager_proto_2.gd:115` | `_monde.ajouter(_entite_joueur, "joueur", ...)` | E (data) — inscrit le joueur au Monde |
| `manager_proto_2.gd:121` | `_maj_entite_joueur()` (dans `_process`) | appel |
| `manager_proto_2.gd:122-123` | `_monde.deplacer(_entite_joueur)` | E (data) |
| `manager_proto_2.gd:253-256` | `_maj_entite_joueur` : `_entite_joueur.position = _observateur.global_position` | **L** — lit la position du CharacterBody3D |
| `manager_proto_2.gd:271-275` | `_tick_collision` : `_observateur.global_position` lu (l.273), vélocité déduite (l.274) | **L** — vélocité du joueur déduite du déplacement réel du corps |
| `manager_proto_2.gd:280-282` | `_observateur.global_position = _entite_joueur.position` (l.282) | **E/H** — recopie de la correction data → CharacterBody3D |
| `manager_proto_2.gd:283-284` | `_monde.deplacer(_entite_joueur)` ; `_pos_joueur_prec = _entite_joueur.position` | E (data) |

`_observateur` ici EST le `CharacterBody3D` joueur (récupéré l.77 par le groupe
`observateur`). Les lignes 253-256 et 271-282 sont le pont entre la physique
Godot du joueur et la collision data : c'est le cœur de l'exception côté manager.

### 1.3 `jeu/Proto/arme_tir.gd` — couplage documenté (commentaire)

| ligne | code | classe |
|---|---|---|
| `arme_tir.gd:8` | commentaire « parent = Personnage = CharacterBody3D est exclu des raycasts » | L (couplage) |

L'exclusion effective n'est pas dans ce fichier (le tir est délégué à
`manager_proto` via `spawn_balle`, l.169) ; c'est une note de couplage à la
capsule du joueur. À noter : `arme_tir.gd` s'adresse au groupe `manager_proto`
(manager 1), pas à `manager_proto_2`.

### 1.4 `jeu/Outil de jeu/projectile.gd` — couplage physique documenté (commentaires)

| ligne | code | classe |
|---|---|---|
| `projectile.gd:21` | « touche immédiatement le corps du personnage (CharacterBody3D…) » | L (couplage) |
| `projectile.gd:60` | « la caméra entre en collision avec le CharacterBody3D du personnage » | L (couplage) |
| `projectile.gd:61` | « (Jolt fait détecter les CharacterBody3D par les Area3D) » | L (couplage) |

Banc `Outil de jeu` (arme à projectile physique). Ces trois lignes sont des
commentaires ; le couplage réel est l'Area3D du projectile qui détecte la
capsule du joueur. Dépend de l'exception seulement si ce banc reste sur des
projectiles physiques ; hors du modèle data pur de `collision.gd`.

### 1.5 Tests — CharacterBody3D TÉMOINS (pas le joueur) et lecture du nœud joueur

| ligne | code | classe | nature |
|---|---|---|---|
| `jeu/unites/test_personnage.gd:223` | `noeud is CharacterBody3D` (assertion) | L | verrou : la scène joueur EST un CharacterBody3D |
| `jeu/unites/test_personnage.gd:231` | commentaire (tangage sur le CharacterBody3D) | L | doc |
| `jeu/terrain/test_ceinture_infranchissable.gd:13,16` | commentaires (témoin lancé) | L | doc |
| `jeu/terrain/test_ceinture_infranchissable.gd:146,200,222` | `body.move_and_slide()` | E | **témoin de test**, pas le joueur |
| `jeu/terrain/test_ceinture_infranchissable.gd:230-232` | `_perso()` fabrique un `CharacterBody3D.new()` | E | **témoin de test** |
| `jeu/terrain/test_carte_prototype.gd:105` | `racine.get_node_or_null("Personnage") as Node3D` | L | lit le nœud joueur COMME Node3D (vérifie le groupe) |
| `jeu/terrain/test_carte_prototype.gd:338` | `CharacterBody3D.new()` | E | **témoin de test** |
| `jeu/terrain/test_carte_prototype.gd:352` | `corps.move_and_slide()` | E | **témoin de test** |
| `jeu/terrain/test_scene_carte.gd:97` | `racine.get_node_or_null("Personnage") as Node3D` | L | lit le nœud joueur COMME Node3D |

Les `CharacterBody3D` de `test_ceinture_infranchissable` et `test_carte_prototype`
sont des CORPS-TÉMOINS créés pour éprouver la barrière / le terrain ; ils ne sont
pas le joueur et ne suivent pas la disparition de l'exception joueur (ils suivront
seulement si l'on décide de tester la barrière/terrain en collision data). Les
deux `get_node("Personnage")` traitent déjà le joueur comme `Node3D` : ils
survivront tels quels.

---

## 2. Synthèse du classement

- **ÉCRITURES sur l'exception (à retirer/remplacer)** : `personnage.gd:1, 301,
  302, 308, 310, 313, 315` (définition + vélocité + move_and_slide) ;
  `manager_proto_2.gd:282` (recopie position corrigée → CharacterBody3D).
- **LECTURES de l'exception (à re-router vers la data)** : `personnage.gd:307,
  312` (`is_on_floor`) ; `manager_proto_2.gd:256, 273-274` (position/vélocité du
  corps). Plus les lectures-COMME-Node3D déjà neutres : `test_carte_prototype.gd:105`,
  `test_scene_carte.gd:97`.
- **HOOKS / ponts** (détail §3) : `personnage.gd:315` (`move_and_slide` =
  autorité de déplacement) ; `manager_proto_2.gd:256`+`273-274`+`282` (le
  triangle lire-position / déduire-vélocité / réécrire-position).
- **Couplages en commentaire, hors modèle data** : `arme_tir.gd:8`,
  `projectile.gd:21, 60, 61`.
- **Témoins de test, indépendants du joueur** : `test_ceinture_infranchissable.gd`
  (146, 200, 222, 230-232), `test_carte_prototype.gd` (338, 352).

Aucun vrai signal Godot (`connect`/`emit`) n'est branché sur le joueur : le
couplage est en polling dans `_process`/`_physics_process`. « Hook » est donc
entendu au sens de point-pont data↔physique, pas de callback de signal.

---

## 3. Les hooks et leur remplaçant une fois l'exception retirée

Le modèle cible est déjà écrit et documenté : `jeu/Proto/collision.gd`
(GJK/EPA, data pure) + `jeu/Proto/COLLISION.md`. Le joueur y a déjà sa forme
capsule et sa réponse `"bloque"` (COLLISION.md §« Câblage manager 2 »). Ce qui
manque est de faire du joueur une entité data qui NE passe plus par le corps
Godot.

**H1 — `personnage.gd:315` `move_and_slide()` (+ `velocity`, `is_on_floor`).**
Autorité actuelle : le moteur physique Godot déplace le joueur et gère sol,
pente, glissement.
Remplaçant : `personnage.gd` devient un `Node3D` (ou garde `CharacterBody3D`
comme simple porteur de caméra sans `move_and_slide`) qui LIT les touches et POSE
une vélocité voulue DANS l'entité data du joueur. Le déplacement, la collision
terrain et la séparation inter-entités sont calculés par `Collision.tick` /
`Collision.resoudre` et par `carte.sommet(colonne)` — exactement le patron déjà
appliqué aux cubes de `manager_proto_2` et aux ennemis (`CLAUDE.md` § « Liste
exhaustive des interactions physiques à coder en data pure »). `is_on_floor` /
gravité `velocity.y` sont remplacés par gravité data + snap au sol via
`carte.sommet`, déjà en place pour les cubes (`manager_proto_2.gd:232-240`).

**H2 — `manager_proto_2.gd:256` + `273-274` (LIRE la position/vélocité du corps).**
Actuellement le manager DÉDUIT la vélocité du joueur du déplacement réel du
`CharacterBody3D` (car c'est Godot qui l'a bougé).
Remplaçant : la vélocité du joueur devient une ENTRÉE (posée par `personnage.gd`
depuis les inputs), plus une déduction a posteriori. `_maj_entite_joueur` et la
lecture `_pos_joueur_prec` disparaissent : la position du joueur est la position
data, faisant autorité.

**H3 — `manager_proto_2.gd:282` (RÉÉCRIRE `_observateur.global_position`).**
Actuellement le manager recopie la position corrigée par la collision data DANS
le `CharacterBody3D`, pour que Godot rende le joueur au bon endroit.
Remplaçant : une fois le joueur data pur, il n'y a plus de corps à corriger. Le
sens s'inverse : la couche de rendu (caméra + capsule visuelle) LIT la position
data et s'y pose, comme `couvert.gd`/`objets_visibles.gd` posent un nœud à la
position d'une donnée. Le nœud observateur reste dans le groupe `observateur` et
expose `global_position` en lecture pour le couplage-observateur (§0), qui ne
bouge pas.

Effet net des trois : le triangle lire-corps / déduire-vélocité / réécrire-corps
(l.256, 273-274, 282) s'effondre en un flux unique data → rendu, et
`personnage.gd` cesse d'appeler `move_and_slide`.

---

## 4. Scènes `.tscn` contenant le nœud CharacterBody3D du joueur

Définition du type (le nœud « Personnage » y est déclaré `type="CharacterBody3D"`) :

- `jeu/unites/personnage.tscn:17` — `[node name="Personnage" type="CharacterBody3D"]` (source ; porte `personnage.gd`).

Scènes qui INSTANCIENT `personnage.tscn` (elles embarquent donc une instance du
nœud CharacterBody3D joueur, via `ExtResource` vers `res://jeu/unites/personnage.tscn`) :

- `jeu/Proto/verification.tscn` — scène active du manager 2 (porte `manager_proto_2.gd`).
- `jeu/Proto/proto_terrain.tscn`
- `jeu/terrain/carte.tscn`
- `jeu/terrain/carte_100km2.tscn`
- `jeu/terrain/carte_prototype.tscn`
- `jeu/Outil de jeu/test_ennemi.tscn`
- `jeu/Outil de jeu/test_ennemi2 Mother box.tscn`
- `jeu/Archive carte/verificationarchi.tscn`
- `jeu/le model par defaut de la carte/molde opti max.tscn`

Les corps-témoins de `test_ceinture_infranchissable.gd` et
`test_carte_prototype.gd` sont créés EN CODE (`CharacterBody3D.new()`), non portés
par une scène — hors de cette liste.

---

## 5. État des tests au moment de l'audit (référence, aucun code modifié)

Commande : `& "<godot>" --headless --path . --script jeu/<...>/test_xxx.gd`.
34 tests/bancs lancés en headless.

VERTS (aucun échec) : `Proto/test_ligne_de_vue`, `objets/test_objets_visibles`,
`objets/test_semer_objets`, `plantes/test_arbre_massif`,
`plantes/test_cache_vivantes`, `plantes/test_couvert_carte`, `plantes/test_plante`,
`terrain/test_carte_sous_cube`, `terrain/test_carte_terrain`,
`terrain/test_ceinture_infranchissable`, `terrain/test_maquette`,
`terrain/test_outil_fenetre`, `terrain/test_outil_remplissage`,
`terrain/test_outil_sculpture`, `terrain/test_persistance`, `terrain/test_rampe`,
`terrain/test_repere_fenetre`, `terrain/test_terrain_visible`,
`unites/test_personnage`, `monde/test_archiviste` (ses `[1] _echecs` l.130/140
sont des échecs PROVOQUÉS par le test, verdict final `OK`),
`Outil de jeu/test_ecosysteme`, et les 6 autres bancs `Outil de jeu`
(`test_carre_rouge`, `test_generateur_energie`, `test_generateur_enrolement`,
`test_mother_cube`, `test_mother_cube_croissance`, `test_mother_cube_mange`) qui
sortent RC=0.

ROUGES PRÉEXISTANTS (famille « emprise `DEMI_COTE` 64 vs 150 », déjà consignée
dans `SUIVI.md` § EN COURS) : `terrain/test_carte` (ECHEC 13),
`terrain/test_collision_terrain` (ECHEC 1), `terrain/test_scene_carte` (ECHEC 1,
même cause : câblage de la carte).

INSTABLE EN HEADLESS : `terrain/test_carte_prototype` — ne rend pas la main de
façon fiable (dépasse 120-250 s, bloque après `couvert.gd:_ready`). Préexistant,
indépendant de cet audit.

Aucun de ces états n'est causé par l'audit : aucun fichier de code n'a été
touché ; ce document est le seul écrit. Le test qui verrouille l'exception
elle-même, `unites/test_personnage`, est VERT.
