# Collision généraliste en donnée pure (prototype Orion)

Module : `jeu/Proto/collision.gd` (RefCounted, tout statique, aucun état
interne). AUCUNE physique Godot (PhysicsServer3D / StaticBody3D /
CollisionShape3D). Prototypé ici, destiné à Orion : à réutiliser pour tout futur
objet interactif — la collision passe par `Collision.tick`/`resoudre` sur des
Dictionary d'entités, jamais par des nœuds.

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

## Broadphase

**100 % locale, aucun appel à `monde.gd`**. Le tick construit sa propre grille
par **counting sort** à partir du cache colonnes : `cell_id` linéaire par
entité, `PackedInt32Array` d'indices triés par cell + `offsets` (start par
cell). Voisinage d'une cell = elle-même + les 26 cases adjacentes (3×3×3),
lecture directe dans `sorted_idx[offsets[vc]..offsets[vc+1]]`. C'est la
structure exacte du portage C++ à venir (cell-id array + sorted index +
start/end offsets).

**Arête** = `max r_i × 1.0001` avec `r_i = demi-diagonale AABB + rayon max +
vitesse × delta`. La marge 1.0001 garantit que la sphère de rayon `r_i` autour
d'une entité tient dans 3×3×3 cases (sans la marge, cas dégénéré `r_i = arete`
et `p` au bord d'une case → `case(q)` peut être `case(p)+2`).

**Contrat** : toutes les entités collisionnables doivent être dans `entites`.
Le tick ne regarde plus le monde — une entité présente dans `monde` mais
absente d'`entites` n'apparaît jamais comme candidat.

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

`_ecrire_cache(idx, e, delta, ...)` écrit par index — plus d'`append`. Lecture
directe `pr.get(cle, defaut)` (pr = `e.proprietes` tenu en local), sans passer
par `_prop` — les 5 champs `velocite`/`orientation`/`masque_collision`/
`masque_reponse`/`reponse` sont toujours dans `proprietes` chez les callers.

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

## tick / resoudre

- `tick(monde, entites, delta)` → Array de contacts. Broadphase + swept +
  narrowphase GJK→EPA par paire de formes ; dédup de paires par ids.
  Swept : `N = ceil(vitesse*delta / (taille_min*0.5))` sous-pas sur le trajet
  `[position - vitesse*delta, position]`, premier contact depuis l'endpoint.
  (`delta` ajouté à la signature — le swept en a besoin.)
- `resoudre(contacts, entites)` : pour `reponse == "bloque"` des deux ET
  `masque_reponse` compatibles → écarte le long de la normale de la profondeur.
  Immobile (`velocite == 0`) fixe / l'autre encaisse ; deux mobiles ou deux
  immobiles 50/50. Passe unique.

## Ordre par tick

broadphase → (sous-pas swept) GJK → EPA → contacts → `resoudre` → recopie de la
position corrigée du joueur dans `_observateur`.

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
