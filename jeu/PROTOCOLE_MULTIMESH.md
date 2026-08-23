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

## Interdit associé

Ne PAS utiliser un GridMap dynamique pour une population massive à
grand rayon : chaque `set_cell_item` invalide l'octant, reconstruit
son batch de meshes, coûte des millisecondes par insertion. Pour un
terrain streamé 240 m, ~960 colonnes par seuil franchi = pics 80-115
ms mesurés en profileur. Un MultiMesh est le seul patron scalable.

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
