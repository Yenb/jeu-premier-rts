# PROTOCOLE — MultiMeshInstance3D : free-list obligatoire

Toute population rendue via MultiMeshInstance3D DOIT gérer ses
instances par free-list. Cette règle vaut pour l'herbe, le lichen, le
terrain lointain, les futures populations de projectiles, particules
persistantes, cellules décoratives, etc.

## Pourquoi

Le MultiMesh de Godot exige un `instance_count` FIXE, alloué à
l'init. On ne SUPPRIME pas une instance — on la CACHE (scale zéro ou
transform hors écran) et son slot d'index redevient disponible pour
la prochaine naissance. Une réallocation du `instance_count` réserve
un nouveau buffer GPU et copie les transforms — coût proportionnel à
N, gouffre à performance si fait à la naissance/mort d'individus.

## Comment

Pattern déjà en place, à recopier :
- `jeu/Outil de jeu/visuel_herbe.gd` — 82 lignes, tout est là.
- Structure : `MAX_INSTANCES` alloué au `_ready`, `_libres: Array[int]`
  peuplé de 0..MAX à l'init, chaque instance cachée par
  `Transform3D(Basis(), Vector3(0, -10000, 0))`.
- `inscrire(pos)` → `_libres.pop_back()` + `set_instance_transform(i, ...)`.
- `retirer(i)` → `set_instance_transform(i, transform_cache)` + `_libres.append(i)`.

## Trois pièges connus, tous adressés par le pattern

1. **Instances cachées visibles à l'origine** si on ne pousse pas de
   transform initial → set toutes les instances hors écran au `_ready`.
2. **AABB automatique concentré à l'origine** → toutes les instances
   invisibles hors du champ de départ. Solution : `mmi.custom_aabb`
   fixé à la zone de jeu possible (voir `visuel_herbe.gd:61`).
3. **Saturation silencieuse** (`MAX_INSTANCES` atteint) → `inscrire`
   rend -1 et `push_warning`. La simulation continue, seul le rendu
   manque. Non bloquant, mais alarme visible.

## Interdit associé, nuance

GridMap dynamique UNIQUE à grand rayon reste INTERDIT : chaque
`set_cell_item` invalide l'octant, reconstruit son batch de meshes,
coûte des millisecondes par insertion. Pour un terrain streamé 240 m,
~960 colonnes par seuil franchi = pics 80-115 ms mesurés en profileur.

En revanche GridMap dynamique DÉCOUPÉ EN TUILES (un GridMap par
chunk) reste viable à rayon modeste (chantier 2026-08-23, voir bas
de ce document) — un GridMap par chunk = ses propres octants,
invalidation locale, aucun refresh 240 m. Mesuré à rayon 15
cellules × 30 m avec tuiles 20 : 60 fps stable, 604 580 prims,
1 089 draws.

## Deuxième piège, majeur : pas de MultiMesh unique sur grande zone

Godot 4 n'a **pas de frustum culling par instance** dans un MultiMesh
(godot-proposals #10669). Un MultiMesh unique avec 300 000 instances
= 300 000 transforms vertex-shadées à CHAQUE frame, même celles
hors du frustum caméra. Mesuré : **fps 8** à ce volume.

## Solution : CHUNKS de MultiMeshInstance3D

Découper l'espace en chunks carrés (ex. 20×20 m), **un
MultiMeshInstance3D par chunk**, chaque chunk avec son
`custom_aabb` serré à sa boîte. Godot cull chaque chunk
indépendamment via le frustum standard. Les chunks hors champ ne
sont pas vertex-shadés du tout.

Pattern éprouvé par le plugin Spatial Gardener. Recette :
- `taille_chunk` : compromis entre nombre de chunks (draw calls) et
  granularité du culling. 10-40 cellules pour une carte typique.
- `custom_aabb` OBLIGATOIRE, calculé exactement à la taille du chunk
  (largeur = `taille_chunk × cote_cellule`, hauteur = plage verticale
  de la carte + marge).
- Chunk créé quand il entre dans le rayon streamé, `queue_free` quand
  il en sort. Pas de free-list intra-chunk nécessaire (le chunk est
  monolithique, créé/détruit d'un bloc).

Implémentation : `jeu/Proto/terrain_visible_multimesh.gd`.

## Mesure à faire AVANT de coder une optimisation

Instrumenter `RenderingServer.get_rendering_info(RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)`
et `RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME` dans la boucle de mesure.
Sans ces chiffres réels, on optimise à l'aveugle. Balayer d'abord les
paramètres triviaux (taille_chunk, rayon) avant de refactorer la
structure : trois relances de scène coûtent moins qu'une refonte.
Mesure typique : baisser draw_calls 791→115 sans gain fps = le
goulot est ailleurs (volume géométrique, pas batching).

Cf. section « CANEVAS DE BASE DES POPULATIONS MASSIVES » de
`CLAUDE.md` — même règle, cette page ajoute le POURQUOI free-list.

## Chantier terrain lointain 2026-08-23 : rendu IDENTIQUE au GridMap

Objectif atteint : `jeu/Proto/terrain_visible_multimesh.gd` est
maintenant un GridMap dynamique par tuile. Un GridMap enfant par
tuile, populé par `set_cell_item` avec la MeshLibrary du proche
(dépouillée de collision via `Outil.sans_collision`). Streaming par
masque de visibilité par couche (bitwise `visible_bits_col`) : seules
les cellules exposées sont posées. Point de sauvegarde : commit
`4da4613`.

### Pistes ÉCARTÉES, à ne pas réintroduire

Le nom du fichier reste `terrain_visible_multimesh.gd` pour ne pas
casser les références, MAIS le rendu n'utilise plus MultiMesh. Cinq
approches ont été essayées et abandonnées :

1. **MultiMeshInstance3D de cubes complets** (chunks Spatial Gardener-
   like). Rendu VISUELLEMENT DIFFÉRENT du GridMap : instances MMI
   adjacentes touchent leurs faces sans gap → arêtes perdues, shading
   uniforme, cubes fusionnent en une masse lisse. Le "PATTERN CHUNKS/
   TUILES" décrit plus haut vaut pour l'herbe/particules mais pas pour
   reproduire le rendu GridMap.

2. **ArrayMesh procédural via SurfaceTool + vertex colors**. Couleurs
   traitées comme sRGB par défaut, double conversion vers linéaire →
   rendu quasi noir. `vertex_color_is_srgb = false` corrige, MAIS le
   shading directionnel reste différent d'un GridMap sur les mêmes
   meshes.

3. **Greedy meshing** (fusion des faces coplanaires même matériau en
   quads plus grands). Transforme les marches en dalles lisses,
   détruit l'identité cubique du terrain. Bande verte horizontale au
   lieu d'escalier de cubes.

4. **HFC entre voisins** (skip des faces contre un voisin plein) seul.
   Compatible visuellement avec GridMap MAIS le rendu reste différent
   à cause du point 1 ci-dessus (MultiMesh vs GridMap sur mêmes
   meshes). Retiré aussi.

5. **Retirer `visible = false` du GridMap Terrain proche AVANT** de
   prouver que le remplaçant rend la zone 0-rayon_interne. Sol
   invisible sous les pieds du joueur (Y=14.18 → tombe à Y=-22 en 3s,
   mesuré). Retirer aussi la collision du GridMap proche
   (`sans_collision` sur le GridMap Terrain) casse le sol physique.

### Piège documenté sur `create_trimesh_collision`

Sur un mesh procédural (SurfaceTool), `create_trimesh_collision()`
crée bien un `StaticBody3D` + `ConcavePolygonShape3D` enfant du MI
(vérifié : 113/113 MI ont un StaticBody3D enfant), MAIS le joueur
tombe quand même à travers. Cause non identifiée à ce chantier. La
collision native GridMap reste le seul sol physique fiable
aujourd'hui — ne PAS retirer `Outil.sans_collision` de
`terrain_visible.gd` avant d'avoir une alternative prouvée.

### Ce qu'il ne faut PAS refaire

- Croire qu'un mesh utilisé dans un MultiMesh rend identique au
  GridMap qui l'utilise. Shading et arêtes diffèrent.
- Fabriquer un mesh procédural par cube (SurfaceTool) pour un aspect
  "cubes visibles". Coûte les arêtes.
- Fusionner les faces coplanaires (greedy) pour un aspect cubique.
  Détruit les marches.
- Retirer la visibilité OU la collision du GridMap proche sans
  preuve qu'un autre système couvre la zone.

### Ce qui RESTE valide dans l'optim rendu

- Streaming par masque de visibilité par couche (`visible_bits_col`) :
  bitwise, compatible avec GridMap dynamique. Chaque colonne itère
  seulement les rangs qui ont une face exposée. Verrouillé par 6
  tests dans `test_ecosysteme.gd`.
- Un GridMap par tuile (pas un GridMap unique à grand rayon).
- `Outil.sans_collision` sur la MeshLibrary d'un GridMap secondaire
  quand la collision est déjà portée par le GridMap principal —
  évite le doublage de shapes.
