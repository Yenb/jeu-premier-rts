# Collision généraliste en donnée pure (prototype Orion)

Module : `jeu/Proto/collision.gd` (RefCounted, tout statique, aucun état
interne). AUCUNE physique Godot (PhysicsServer3D / StaticBody3D /
CollisionShape3D). Prototypé ici, destiné à Orion : à réutiliser pour tout futur
objet interactif — la collision passe par `Collision.detecter`/`resoudre` sur
des Dictionary d'entités, jamais par des nœuds. **Une seule voie** : `detecter`
rend les contacts, `resoudre` les applique. `detecter` n'interroge AUCUN index
externe — l'appelant fournit la liste complète des entités à tester (voir
Broadphase ci-dessous).

## Modèle de donnée

Entité = Dictionary :
- `position` : Vector3, **top-level** (requis par `scripts/monde.gd`).
- `proprietes` :
  - `formes` : Array de forme (voir plus bas).
  - `aabb_cache` : AABB monde (rafraîchie par `tick`).
  - `masque_collision` : int (bitmask ; paire testée si `a & b != 0`).
  - `masque_reponse` : int (bitmask ; séparée si `a & b != 0`).
  - `reponse` : String (`"bloque"` sépare ; autre = détecté non résolu).
  - `velocite` : Vector3.
  - `orientation` : Basis.

Transform monde d'une forme = `Transform3D(orientation, position) *
transform_locale`.

## Formes

Forme = `{ type: String, transform_locale: Transform3D, parametres: Dictionary }`.
Dispatch par type UNIQUEMENT dans `_support_local` (un 5e type = un `case`).

| type | parametres |
| --- | --- |
| `sphere` | `{ rayon: float }` |
| `boite` | `{ demi_taille: Vector3 }` |
| `capsule` | `{ rayon, hauteur }` — axe Y, segment central de longueur `hauteur - 2*rayon` |
| `hull` | `{ points: Array[Vector3] }` — sommets locaux |

## Support / AABB

- `support(forme, tf_monde, dir_monde)` → point le plus loin dans `dir` (dir
  ramenée en local par `basis.inverse()`, point remis en monde).
- `aabb_forme(forme, tf_monde)` → AABB par 6 supports (±X ±Y ±Z), générique.

**Caches par-forme (AABB locale + taille min)** : `_cacher_forme(forme)`
calcule `aabb_forme(forme, forme.transform_locale)` ET `_taille_min_forme(forme)`
UNE fois, les indexe dans `_cache_aabb_locale: Array[AABB]` et
`_cache_taille_min_forme: PackedFloat32Array` (parallèles, même id) via un id
INT injecté dans la forme (`forme["_aabb_id"]`). Une population qui partage la
même instance de forme (1600 unités du peuplement, même boîte) ne recalcule ni
l'AABB locale ni la taille min. `_aabb_from` : orient IDENTITY (cas dominant)
→ translation de l'AABB locale cachée ; orient tournée → recalcul complet par
`aabb_forme` (l'AABB monde d'une AABB locale tournée n'est PAS la
translation). `_taille_min_formes_cache(formes)` : `min` sur les tailles
cachées.

Point noir : cache jamais invalidé. Si une forme change de contenu en gardant
la référence (hitbox d'animation, morph), les deux caches restent sur les
anciennes valeurs. Formes stables pour l'instant, invalidation hors scope.

## Broadphase

**100 % locale, aucun appel à un index externe**. `detecter` construit sa
propre grille par **counting sort** à partir du cache colonnes : `cell_id`
linéaire par entité, `PackedInt32Array` d'indices triés par cell + `offsets`
(start par cell). Voisinage d'une cell = elle-même + les 26 cases adjacentes
(3×3×3), lecture directe dans `sorted_idx[offsets[vc]..offsets[vc+1]]`. C'est
la structure exacte du portage C++ à venir (cell-id array + sorted index +
start/end offsets).

**Arête** = `max r_i × 1.0001` avec `r_i = demi-diagonale AABB + rayon max +
vitesse × delta`. La marge 1.0001 garantit que la sphère de rayon `r_i` autour
d'une entité tient dans 3×3×3 cases (sans la marge, cas dégénéré `r_i = arete`
et `p` au bord d'une case → `case(q)` peut être `case(p)+2`).

**Contrat** : toutes les entités à tester doivent être dans `entites`.
`detecter` n'interroge JAMAIS d'index externe — un appelant qui veut tester
une entité contre ses voisins collecte les voisins lui-même (typiquement
`monde.choses_dans_rayon(pos, rayon_collecte)`) et compose la liste avant
l'appel.

**Demi-voisinage** : chaque paire (i, j) est visitée UNE seule fois. Intra-cellule
`j > i`, inter-cellules les 13 offsets (dx, dy, dz) `>` (0, 0, 0) en ordre
lexicographique. Le filtre distance est `d² ≤ max(r_i, r_j)²` — équivalent à
l'ancien pipeline OU (les deux visites précédentes acceptaient la paire si
au moins une passait `d² ≤ r_source²`). Pas de hashmap `vus` : rien à dédupliquer.

**Tri stable des contacts** en fin de `detecter` (C++ ET oracle GDScript), clé
`(min(idx_a, idx_b), max(idx_a, idx_b))` — rend `resoudre` déterministe par
construction, indépendant de l'ordre de parcours. Prépare M2 (multithread) où
l'ordre de parcours n'est plus garanti. `std::stable_sort` C++ + décorateur
`[lo, hi, k_insertion, contact]` GDScript (Array.sort_custom n'est pas garanti
stable). Ce partage tient les deux appelants : le peuplement passe sa
population fermée (`_entites_collision` stable), le joueur passe
`[entite] + voisins collectés` (voir `scripts/mouvement_kinematic.gd` B.12).

**Filtres per-paire** dans l'ordre : distance (`dist ≤ r_a`, reproduit
l'ancien filtre `choses_dans_rayon`), dédup (`vus[cle]`), masque
(`masque_a & masque_b`), AABB **balayée**, narrowphase.

**Garde case saturée** (plat, sans subdivision) : masque et AABB balayée
AVANT le narrowphase — même sur une case avec beaucoup d'occupants, gjk/epa
ne tourne que sur les paires qui ont passé le filtre AABB. Pas de recursion.

Limite : grille dense de plus de 1M cases (Nx × Ny × Nz) → `push_error`. Signe
d'une position aberrante ; la broadphase reste correcte mais consomme.

## Cache en colonnes

`tick` construit 12 colonnes **typées et pré-dimensionnées** (`resize(N)` UNE
fois, aucune réallocation, aucun boxing Variant sur les scalaires/vecteurs) :
- `PackedVector3Array` : `col_vel`
- `PackedFloat32Array` : `col_vel_len`, `col_taille_min`
- `PackedInt32Array` : `col_masque_c`, `col_masque_r`
- `PackedByteArray` : `col_vel_nz` (0/1)
- `PackedStringArray` : `col_reponse`
- `Array[Basis]` : `col_orient`
- `Array[AABB]` : `col_aabb`, `col_swept`
- `Array[Dictionary]` : `col_ent`
- `Array` générique : `col_formes` (Array[Array] non supporté par GDScript)

Le remplissage de ces colonnes est **inline** dans la boucle principale de
`tick` (plus d'appel de fonction par entité). Lecture directe
`pr.get(cle, defaut)` (pr = `e.proprietes` tenu en local), sans passer par
`_prop` — les 5 champs `velocite`/`orientation`/`masque_collision`/
`masque_reponse`/`reponse` sont toujours dans `proprietes` chez les callers.

Chemin rapide AABB dans la même boucle : si `orient == Basis.IDENTITY` (cas
dominant peuplement), l'AABB monde d'une forme = AABB locale cachée + position,
sans composer `Transform3D`. Fallback complet (`_aabb_from` avec projection)
sur orient tournée.

Le hot path lit `col_x[i]` par int, sans allocation ni conversion.

## GJK

`gjk(fa, ta, fb, tb)` → `{ intersecte: bool, simplexe: Array[Vector3] }`. Support
de Minkowski `sA(d) - sB(-d)` ; simplexe ligne → triangle → tétraèdre ; 32
itérations. Sur intersection, le simplexe est un tétraèdre contenant l'origine.

## EPA

`epa(simplexe, fa, ta, fb, tb)` → `{ normale, profondeur }`. Expansion du
polytope, face la plus proche de l'origine, convergence à `1e-4`, 32 itérations.
Normale unitaire, sens **A→B** (pour A en 0 et B en +X, normale = +X).

## Contact

`{ a, b, normale (A→B), profondeur }`.

## detecter / resoudre

- `detecter(entites, delta)` → Array de contacts. Broadphase + swept +
  narrowphase GJK→EPA par paire de formes ; dédup de paires par ids.
  Swept : `N = ceil(vitesse*delta / (taille_min*0.5))` sous-pas sur le trajet
  `[position - vitesse*delta, position]`, premier contact depuis l'endpoint.
- `resoudre(contacts, entites)` : pour `reponse == "bloque"` des deux ET
  `masque_reponse` compatibles → écarte le long de la normale de la profondeur.
  Immobile (`velocite == 0`) fixe / l'autre encaisse ; deux mobiles ou deux
  immobiles 50/50. Passe unique.

## Ordre par frame chez l'appelant

collecte voisins (si liste ouverte) → `detecter` → `resoudre` (ou séparation
custom SAFE_MARGIN pour le joueur, voir `mouvement_kinematic.gd` B.12).

## Portage C++ — CollisionLot (extension_terrain)

`extension_terrain/src/collision_lot.h/.cpp` porte `detecter` + `resoudre` en
C++, généraliste dès M1 (sphère, boîte, capsule, hull ; orientation ≠ Identity ;
raccourci boîte-boîte AABB alignée = chemin rapide interne). Une seule voie de
prod : `banc_peuplement.gd` appelle **CollisionLot**, `jeu/Proto/collision.gd`
reste l'oracle de parité appelé uniquement par
`scripts/test_collision_lot_cpp.gd` (égalité EXACTE des flottants, peuplement +
multi-formes). Convention de type : composantes Vector3 en `real_t` (float 32),
scalaires temporaires en `double` avec promotion explicite `(double)vec.dot()`
aux mêmes points que GDScript. Frontière SoA (le hot path évite tout boxing
Variant) : positions/velocites/orientations aplaties/masques/reponses + pool
de formes plat `formes_debut/formes_type/formes_tf_locale/formes_params` +
`hull_points`. Chronos temporaires `derniers_chronos() → {prepasse, tri, parcours,
narrowphase, resoudre}` en microsecondes — cinq postes qui couvrent tout le
corps sans chevauchement ni trou. `now()` pris aux bornes de bloc uniquement,
JAMAIS par paire : le parcours pousse les paires retenues dans un batch, le
narrowphase les consomme après. Compteurs temporaires `derniers_compteurs() →
{paires_distance, paires_dedup, appels_nf, contacts}` — disent si le coût
vient du nombre de paires ou du coût par paire. `banc_peuplement.gd` imprime
ces mesures toutes `CADENCE_RELEVE_COLLISION_FRAMES` frames sous
`actif_releve`. Mono-thread. Multithread : morceau ultérieur.

## Ce que le système NE fait PAS

Friction, rotation en réponse, masse/restitution, résolution itérative
multi-contacts, repos stable garanti, résolution parfaite d'un tunneling profond
(le swept **détecte** ; la remise au point d'impact n'est pas faite).

## Coût

Broadphase : une requête grille par entité (coût suit le rayon, pas la
population). Narrowphase : GJK/EPA bornés (32 itérations) par paire.

## Câblage manager 2 (`manager_proto_2.gd`)

- Cubes : forme `boite` demi 0.4, masques 1, `reponse "bloque"`, `velocite`
  ZERO (ancre immobile — le joueur encaisse la séparation).
- Joueur : forme `capsule` rayon 0.4 hauteur 1.8, masques 1, `reponse "bloque"`,
  `velocite` déduite du déplacement réel de l'observateur.
- Horloge `INTERVALLE_COLLISION = 0.05` ; position corrigée recopiée dans
  `_observateur.global_position` en fin de tick.
