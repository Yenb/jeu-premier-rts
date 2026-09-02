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

`monde.choses_dans_rayon(centre, r)`, `r = demi-diagonale AABB entité +
demi-diagonale max du voisinage + vitesse*delta` (marge swept). Filtre
`masque_collision` puis recouvrement des AABB **balayées**.

Limite : `monde.gd` indexe un POINT, pas une AABB. Valable tant que les tailles
restent comparables. Des entités de tailles très différentes exigeraient
d'étendre `monde.gd` (chantier framework, Orion) — hors de ce prototype.

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
