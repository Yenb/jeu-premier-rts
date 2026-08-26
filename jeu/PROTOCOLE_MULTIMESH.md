# PROTOCOLE — rendre une population massive en MultiMesh

Deux régimes, deux patrons. Ne pas les confondre.

## 1. Population individu-par-individu → FREE-LIST

Herbe, lichen, particules, projectiles : des individus qui naissent et meurent
UN À UN. Patron : `jeu/Outil de jeu/visuel_herbe.gd`.

Le MultiMesh exige un `instance_count` FIXE, alloué à l'init. On ne SUPPRIME pas
une instance — on la CACHE (transform hors écran) et son index redevient libre.
`MAX_INSTANCES` alloué au `_ready`, `_libres: Array[int]` peuplé de 0..MAX.
`inscrire(pos)` → `pop_back` + `set_instance_transform`. `retirer(i)` →
transform hors écran + `append(i)`. Réallouer `instance_count` recopie tout le
tampon GPU : gouffre si fait à la naissance/mort. D'où la free-list.

Trois pièges, tous adressés par le patron : instances cachées visibles à
l'origine (pousser un transform hors écran au `_ready`) ; AABB automatique
concentré à l'origine (`custom_aabb` couvrant la zone de jeu) ; saturation
silencieuse (`inscrire` rend -1 + `push_warning`).

## 2. Grande zone statique streamée → CHUNKS, PAS de free-list

Le terrain. Une tuile se CRÉE et se DÉTRUIT d'un bloc — aucune free-list
intra-tuile (les instances ne naissent pas une à une, la tuile entière apparaît
ou disparaît selon la distance).

### Le POURQUOI des chunks, invariant

Godot 4 n'a **pas de frustum culling par instance** dans un MultiMesh
(godot-proposals #10669). Un MultiMesh unique de 300 000 instances vertex-shade
TOUT à chaque frame, hors champ compris (mesuré : fps 8). Solution éprouvée
(plugin Spatial Gardener) : découper en chunks carrés, **un MultiMeshInstance3D
par chunk** avec `custom_aabb` serré à sa boîte → Godot cull chaque chunk par
le frustum standard.

- `custom_aabb` OBLIGATOIRE, serré à la boîte RÉELLE du chunk (largeur ×
  hauteur réellement posée). Un AABB haut de toutes les couches possibles ne se
  ferait jamais culler.
- Chunk créé quand il entre dans le rayon, `queue_free` quand il en sort.

### Le rendu du terrain : `jeu/terrain/rendu_terrain_multimesh.gd`

- **Un MultiMeshInstance3D par FORME × par tuile.** Les formes se lisent dans
  `jeu/terrain/bloc.tres` — ajouter une forme = un item, zéro ligne ici (voir
  `jeu/terrain/AJOUTER_UNE_FORME.md`).
- **FACE CULLING.** Un cube (`BoxMesh`) ne pose PAS un cube plein (12 triangles) :
  il pose un QUAD par face EXPOSÉE. Une face n'est cachée que si le voisin de ce
  côté est un CUBE plein ; une rampe, un cylindre, une sphère ne remplissent pas
  leur cellule et laissent la face visible. Sol plat = 1 quad (2 triangles) par
  colonne au lieu de 12.
- Rampe/cylindre/sphère gardent leur mesh COMPLET (le face culling n'a de sens
  que pour un cube).
- Position/orientation par les conversions natives d'un GridMap de référence
  (`map_to_local`, `get_basis_with_orthogonal_index`, `get_item_mesh_transform`),
  jamais calculées à la main.
- **Occlusion** (`occlusion_culling/use_occlusion_culling` dans `project.godot`) :
  un `ArrayOccluder3D` sur le relief émergent (couche > sommet de base) ; ce qui
  est entièrement derrière n'est plus dessiné. Même geste sur les canopées
  d'arbres dans `couvert.gd`.
- **LOD par distance** (`visibility_range_end`) et **taille de tuile** réglables
  sur le nœud.

## Écartés — interdit de reproposer

- **MultiMesh UNIQUE sur grande zone.** Perd le frustum culling par instance
  (#10669) : tout est vertex-shadé. C'est la raison d'être des chunks.
- **GREEDY MESHING** (fusionner les faces coplanaires en grands quads). Deux
  interdits en un : il abandonne le MultiMesh (quads de tailles variables →
  `ArrayMesh` reconstruit par tuile) ; et il CASSE la destructibilité — détruire
  un cube au milieu d'un grand quad fusionné force à refaire tout le bloc. Le
  face culling par cube garde chaque face indépendante → destruction locale, la
  tuile se recalcule depuis les masques.
- **Descendre les draw calls à « un seul ».** Impossible sans un unique mesh +
  matériau global pour tout le terrain, ce qui supprime le culling par tuile ET
  le tri par forme. Les draw calls sont un PLANCHER structurel : somme des
  formes présentes sur les tuiles visibles.

## Le compromis draw calls ↔ primitives

Tuiles PETITES : culling plus fin → moins de primitives, mais PLUS de draw
calls. Tuiles GRANDES : l'inverse. Les deux compteurs tirent en sens opposés via
`taille_tuile_cellules`. On équilibre en MESURANT, jamais les deux au minimum en
même temps. Il n'y a pas de troisième voie dans le MultiMesh.

## Piège `create_trimesh_collision`

Sur un mesh procédural, `create_trimesh_collision()` crée bien un `StaticBody3D`
+ `ConcavePolygonShape3D` enfant, MAIS le joueur tombe quand même à travers
(cause non identifiée). La collision native GridMap reste le seul sol physique
fiable : `terrain_visible.gd` (GridMap proche) ne dessine plus rien (`sans_mesh`)
mais garde SES formes de collision. Ne pas retirer cette collision sans une
alternative prouvée.

## Mesurer avant d'optimiser

`RenderingServer.get_rendering_info` (draw calls, primitives, objets). Sans le
chiffre réel, on optimise à l'aveugle. Balayer d'abord les réglages triviaux
(taille de tuile, rayon, LOD) avant de refondre la structure. Détail dans
`jeu/METHODE_DIAGNOSTIC_PERF.md`.
