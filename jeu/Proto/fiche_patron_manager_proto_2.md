# Fiche patron manager_proto_2

Prérequis M0 pour la migration M1 (ennemis en pure data + MultiMesh). Décrit le
patron data-pure de [manager_proto_2.gd](manager_proto_2.gd) que M1 doit
répliquer pour porter les ennemis actuellement dans [ennemis.gd](ennemis.gd),
sans les violations doctrinales de [manager_proto.gd](manager_proto.gd).

## 1. Structure de données des entités

**Stockage : `Array` de `Dictionary`.** Une variable de manager par population.

- Cubes verts : [manager_proto_2.gd:80](manager_proto_2.gd:80) `var _ennemis: Array = []`.
- Joueur : [manager_proto_2.gd:88](manager_proto_2.gd:88) `var _entite_joueur: Dictionary = {}` (entité unique, pas de tableau).

**Champs top-level d'une entité** (visible sur `_spawner_un_cube`,
[manager_proto_2.gd:256-277](manager_proto_2.gd:256)) :

| Clé | Type | Rôle |
|---|---|---|
| `id` | String | identifiant unique, pattern `"cube_vert_%d"` |
| `position` | Vector3 | SEULE autorité de position (le nœud de rendu suit) |
| `proprietes` | Dictionary | sous-dict contrat perception/collision/mouvement (voir plus bas) |
| `noeud` | Node3D ou null | référence au visuel courant (null hors rayon de rendu) |
| `direction` | Vector3 | cap d'errance horizontal |
| `cap_horloge` | float | secondes restantes avant changement de cap |

**Sous-dict `proprietes`** — CONTRAT partagé avec `scripts/perception.gd`,
`jeu/Proto/collision.gd` et `scripts/mouvement_kinematic.gd`. Pour un cube
d'errance ([manager_proto_2.gd:259-273](manager_proto_2.gd:259)) :

| Clé | Type | Rôle |
|---|---|---|
| `canaux` | Array[String] | canaux de perception exposés (`"vue"`, …) |
| `canaux_config` | Dictionary | portée/angle/sensibilité par canal |
| `formes` | Array[Dict] | formes de collision (`type`, `transform_locale`, `parametres`) |
| `masque_collision` | int | bitmask émis |
| `masque_reponse` | int | bitmask reçu |
| `reponse` | String | `"bloque"` ou autre |
| `velocite` | Vector3 | vitesse effective, lue/écrite par le pas partagé |
| `orientation` | Basis | orientation courante |
| `aabb_cache` | AABB | AABB monde recalculée à la construction, source du broad-phase |

Pour le joueur ([manager_proto_2.gd:130-166](manager_proto_2.gd:130)),
`proprietes` porte en plus le contrat Mouvement+Tick : `profil` (`"complet"`
ou `"simple"`), `cadence_tick`, `saut_demande`, `velocite_desiree_horizontale`,
`vitesse_saut`, `rayon_capsule`, `hauteur_capsule`, `gravite`, `au_sol`,
`y_appui_entite`, `profil_saillance`.

**Indexation spatiale : `scripts/monde.gd`.** Le manager instancie un `Monde`
([manager_proto_2.gd:117](manager_proto_2.gd:117) `_monde = Monde.new()`), y
ajoute chaque entité (`_monde.ajouter(cube, "cube_vert", cube.position)`,
[manager_proto_2.gd:285](manager_proto_2.gd:285)), et pousse la position à
chaque déplacement (`_monde.deplacer(cube)`,
[manager_proto_2.gd:310](manager_proto_2.gd:310)). Le monde expose
`choses_dans_rayon(pos, rayon)` pour la broad-phase — c'est le patron cité en
CLAUDE.md « LOCALITÉ SPATIALE, monde indexé (c) ».

## 2. Boucle de tick

**Point d'entrée : `_physics_process(delta)`** ([manager_proto_2.gd:190](manager_proto_2.gd:190)),
**pas** `_process`.
Raison documentée en tête de fonction : `physics_interpolation=true` dans
`project.godot` — tout transform doit être posé dans le pas physique sinon
Godot interpole depuis une source idle et avertit. Le rendu est lissé
gratuitement entre deux pas physiques.

**Fréquence : 30 Hz** (project.godot `common/physics_ticks_per_second=30`,
commit `d88b65a`). `cadence_tick: 1` sur les entités = un pas par
`_physics_process`.

**Découpe interne** ([manager_proto_2.gd:190-203](manager_proto_2.gd:190)) :

1. `_tick_spawn(delta)` — un lot toutes les `intervalle_spawn` s, jusqu'au plafond.
2. `_tick_errance(delta)` — mouvement des cubes.
3. `_pas_joueur(delta)` — intention Personnage → entité joueur → `Tick.tick_entite`.
4. `_bascule_rendu()` — streaming visuel par distance.
5. Horloge perception (`INTERVALLE_PERCEPTION = 0.1` s) → `_tick_perception` (VIDE aujourd'hui).
6. Recopie `_entite_joueur.position` → `_observateur.global_position` (rendu suit la donnée).

**Aucune coalescence, aucun étalement inter-tuile.** Le monde tenu ici est
petit (≤ `max_cubes = 10` par défaut). Un futur besoin M1 avec `_max_ennemis = 2500`
demandera peut-être une coalescence à concevoir.

## 3. Rendu / visuel

**Aujourd'hui : UN `MeshInstance3D` PAR ENTITÉ.** Pas de MultiMesh.

- Mesh partagé (`_mesh_ennemi: BoxMesh` préparé en `_preparer_mesh`,
  [manager_proto_2.gd:205-210](manager_proto_2.gd:205)).
- Fabrication : `_creer_visuel()` ([manager_proto_2.gd:406-410](manager_proto_2.gd:406))
  → `MeshInstance3D` neuf, `cast_shadow off`.
- Streaming par distance ([manager_proto_2.gd:383-404](manager_proto_2.gd:383)) :
  hystérésis `rayon_rendu_entrer` / `rayon_rendu_sortir` sur `d² < r²` ; entre
  → `add_child` + `noeud = n` ; sort → `queue_free` + `noeud = null`. Dans le
  rayon, `noeud.global_position = e.position` chaque tick.
- Aucune allocation d'index d'instance — chaque nœud est indépendant.

**Ce que M1 doit concevoir pour le rendu MultiMesh :**

- Le patron cible est `jeu/plantes/vegetation.gd` + `jeu/plantes/couvert.gd`
  (cité par CLAUDE.md § « CANEVAS DE BASE DES POPULATIONS MASSIVES »).
- Trois composants séparés obligatoires :
  1. Manager (Node) qui itère `Array` de dicts en une boucle `_process`/`_physics_process`.
  2. Champ scalaire (RefCounted) pour la densité par case (double-gate à la reproduction).
  3. Visuel (`MultiMeshInstance3D`) qui rend tous les individus en un draw call.
- Chiffres cités en CLAUDE.md : Node3D pèse 1 320 octets, un pattern
  Node3D+Timer×N à 22 000 individus = 72 Mo et 4 M dispatches/s ; canevas
  MultiMesh = 4,4 Mo et 60 dispatches/s (gain ×66 000).
- Allocation/libération d'index d'instance : PAS le mode « free-list intra-tuile »
  de `rendu_terrain_multimesh.gd` (tuile monolithique). Ici la population
  naît/meurt à l'individu — plus proche du patron `couvert.gd` avec free-list.
- Barres de vie/nourriture (aujourd'hui `MeshInstance3D` enfants du nœud
  ennemi, [ennemis.gd:605](ennemis.gd:605), [ennemis.gd:618](ennemis.gd:618)) :
  M1 doit choisir → soit MultiMesh séparé pour les barres, soit shader
  per-instance sur le mesh principal, soit dropper les barres visuelles au
  profit d'un HUD.

**Streaming visuel + MultiMesh :** décision de conception ouverte — voir
questions ouvertes en fin de fiche.

## 4. Collision au sol

**API physique Godot BANNIE.** Aucun `PhysicsRayQueryParameters3D`, aucun
`intersect_ray`, aucun `body_test_motion`, aucun `Area3D` pour la logique.
Grep confirme sur `manager_proto_2.gd` : 0 occurrence.

**Mécanisme sol-cube :** lecture directe de `carte.sommet(x, z)`
([manager_proto_2.gd:301](manager_proto_2.gd:301)) puis snap Y :
`cube.position = Vector3(r.xz.x, float(r.sol) + 0.4, r.xz.z)` (le cube COLLE au sol,
pas de gravité, [manager_proto_2.gd:308](manager_proto_2.gd:308)).

**Blocage horizontal :** `_deplacement_horizontal_valide(pos, dep, hauteur_ref, marche_max)`
([manager_proto_2.gd:323-330](manager_proto_2.gd:323)). Bloqué si (a) bord de
carte (`carte.sommet` rend null) ou (b) `y_sol_candidat - hauteur_ref > marche_max`.
Rend `{bloque, xz, sol}`. TERRAIN COMMUN cubes + joueur.

**Mécanisme sol-joueur :** ne vit PAS ici. Délégué à `Tick.tick_entite` →
`scripts/mouvement_kinematic.gd` profil `"complet"`
([manager_proto_2.gd:354](manager_proto_2.gd:354)). Le pas partagé fait
gravité, blocage terrain au rayon de la capsule, snap-sol borné, calcul
`y_appui_entite`. Voir aussi le patch S8 récent
([mouvement_kinematic.gd:428-436](../../scripts/mouvement_kinematic.gd:428))
qui lève la garde de pente en l'air.

## 5. Collision entre entités

**Deux niveaux séparés :**

**(a) Broad-phase spatiale — `scripts/monde.gd`.**
Chaque entité inscrite au monde à `_spawner_un_cube` ; `_monde.deplacer(cube)`
appelé à chaque changement de position ; `_monde.choses_dans_rayon(pos, r)`
utilisée par la perception (à venir) et par `jeu/Proto/collision.gd` pour ses
requêtes de voisinage.

**(b) Narrow-phase — `jeu/Proto/collision.gd` (GJK/EPA data-pur).**
Instance construite via `Collision.aabb_forme(forme, transform)` pour le
`aabb_cache` ([manager_proto_2.gd:167-169](manager_proto_2.gd:167),
[manager_proto_2.gd:278-280](manager_proto_2.gd:278)).
La résolution vit dans le pas partagé `scripts/mouvement_kinematic.gd` (voir
son bloc « B.11–B.13 multipass collision inter-entités » qui appelle
`Collision.tick(monde, [entite], dt)`) — le manager ne la déclenche PAS à part.

**Scalabilité :** l'index spatial du monde est du bucket/hash spatial (par
implementation de `scripts/monde.gd`, cité comme patron `monde indexé (c)` en
CLAUDE.md). Une requête `choses_dans_rayon(pos, r)` ne balaie que les cases
touchées → O(k), k = nombre de voisins proches, indépendant de N total.

**Pattern répulsion mutuelle : PAS présent dans manager_proto_2.**
[ennemis.gd:361-420](ennemis.gd:361) implémente une répulsion O(N + k) via
bucket 2D à `RAYON_REPOUSSE_ENNEMI` (0,9 m) — chaque ennemi ne teste que
buckets courant + 4 voisins diagonaux+cardinaux. Pattern à reprendre pour M1
(voir section 7).

## 6. Interaction avec le monde (carte_terrain)

**Lectures seulement, aucune écriture depuis manager_proto_2 :**

- `carte.sommet(x, z)` — sommet du sol par colonne
  ([manager_proto_2.gd:251](manager_proto_2.gd:251),
  [manager_proto_2.gd:301](manager_proto_2.gd:301),
  [manager_proto_2.gd:325](manager_proto_2.gd:325)).
- `carte.cote` (attribut) — arête cellule
  ([manager_proto_2.gd:106-107](manager_proto_2.gd:106)).

**Autres systèmes utilisés :**

- `scripts/monde.gd` — index spatial partagé (voir section 5).
- `jeu/Proto/collision.gd` — GJK/EPA sur `formes` (section 5).
- `scripts/tick.gd` — ordonnanceur `tick_entite(entite, politique, delta, monde, carte)`.
- `scripts/mouvement_kinematic.gd` — pas partagé (profil complet/simple/minimal).
- `data/canaux.json` + `data/profils_saillance.json` — catalogues perception
  chargés en direct via `_charger_json`
  ([manager_proto_2.gd:113-114](manager_proto_2.gd:113)).

**PAS utilisés depuis manager_proto_2 (mais utilisés dans ennemis.gd — à
migrer) :**

- `jeu/Proto/tas.gd` — module matière (sous-cubes, cadavres, sommets effectifs).
- `carte.masque`, `carte.est_pleine`, `carte.item_de`, `carte.ajouter_pv_sous_cube`,
  `carte.est_sous_cube_plein`, `carte.sommet_max_colonne`, `carte.couche_base`,
  `carte.ITEM_DEFAUT` — API creusage/destruction utilisée par ennemis.gd.
- `_effondrer` (Callable délégué au manager) — déclenche l'effondrement d'un
  bloc creusé selon son matériau (le manager seul connaît `RessourcesTerrain`).

## 7. Ce qui MANQUE dans manager_proto_2 pour porter les ennemis

Comparaison avec [ennemis.gd](ennemis.gd) — inventaire fonctionnel à
recréer/adapter :

**Machine à états IA** ([ennemis.gd:257-332](ennemis.gd:257)) :

- État `chasse` — poursuivre le joueur (`derniere_direction_chasse`), tester
  blocage terrain, basculer en `creuse` si mur creusable proche, sinon
  `cooldown_grimpe = 3.0`.
- État `creuse` — attaquer un sous-cube (`_ennemi_creuser`), cadence
  `CADENCE_ENNEMI_CREUSAGE = 0.5 s`, `PV_ENNEMI_CREUSAGE_PAR_COUP = 20`.
- État `cherche_sc` — ramasser un sous-cube libre proche
  (`_ennemi_ramasser_sc_proche`, `RAYON_ENNEMI_RAMASSE = 2.0 m`).
- État `pose` — poser le sous-cube porté en escalier vers la cellule creusée
  (`_ennemi_poser_sc_devant`).

**Faim et mort par famine** ([ennemis.gd:343-358](ennemis.gd:343)) :

- Nourriture consommée au déplacement (`COUT_NOURRITURE_PAR_M = 1.0`) et à la
  montée (`COUT_NOURRITURE_PAR_M_MONTEE = 5.0`) et au creusage
  (`COUT_NOURRITURE_CREUSAGE_PAR_COUP = 3.0`).
- Compteur `famine` incrémenté quand `nourriture <= 0`, retire 1 PV par
  `INTERVALLE_FAMINE = 5 s`.

**Corps-à-corps** ([ennemis.gd:570-597](ennemis.gd:570)) — `frapper_melee(origine,
direction, portee, degat)` : segment 3D vs distance point-segment, hit le plus
proche `<= RAYON_HIT_ENNEMI = 0.5`. Utilisé côté joueur.

**Barres de vie/nourriture visuelles** ([ennemis.gd:602-623](ennemis.gd:602)) :
child `MeshInstance3D` du nœud ennemi, shader avec paramètre `fraction`.

**Répulsion mutuelle O(N)** ([ennemis.gd:361-420](ennemis.gd:361)) — pattern
bucket 2D décrit section 5. Testé pour `_max_ennemis = 2500`.

**Cadavres → sous-cubes** ([ennemis.gd:224-235](ennemis.gd:224)) : à la mort,
snap XZ à la colonne SC (`_cote_cellule / 3`) puis
`_tas.spawn_sous_cube_libre(pos_cadavre, "cadavre", false)` — pile les
cadavres proches dans une même colonne.

**Ennemis statiques de test** ([ennemis.gd:182-212](ennemis.gd:182)) —
`ajouter_statique(pos)` : marqueurs pour tester le pipeline de rendu / hystérésis
sans que l'IA les fasse bouger. Flag `statique: true` court-circuite le match
d'IA.

**Effondrement de bloc creusé** — Callable `_effondrer(cellule, idx, pos_impact)`
délégué au manager. À concevoir en M1.

**Passage par `Tick.tick_entite` avec profil `"simple"`** — pour la gravité
continue, snap sol borné, blocage terrain, appliqués sur l'intention posée par
l'IA ([ennemis.gd:338](ennemis.gd:338)). Actuellement les cubes de manager_proto_2
n'utilisent PAS le pas partagé — ils collent au sol sans gravité. M1 doit
adopter le profil `"simple"` pour la gravité (tomber si sol effondré).

**Rendu massif MultiMesh** — voir section 3 et questions ouvertes.

**Note thread-safety :** aucun code actuel ne parle de threads. Le patron
`Array` de `Dictionary` sur un seul thread `_physics_process` n'a pas de
verrou. Un futur besoin de spawn massif hors thread principal demanderait de
concevoir : (a) buffer d'entrées seedées produites hors thread, (b) fusion sur
le thread principal au prochain tick. Pas urgent.

## 8. Différences doctrinales confirmées avec manager_proto.gd

**Violations doctrinales de manager_proto que manager_proto_2 corrige :**

- **RigidBody3D + freeze KINEMATIC** — [manager_proto.gd:202-204](manager_proto.gd:202),
  [manager_proto.gd:431-432](manager_proto.gd:431), [manager_proto.gd:497-500](manager_proto.gd:497),
  [manager_proto.gd:511-529](manager_proto.gd:511). Producteurs, carrés rouges,
  gestion `_gerer_freeze_kinematic`. → data pure, aucun RigidBody3D dans
  manager_proto_2.
- **PhysicsRayQueryParameters3D + intersect_ray** — [manager_proto.gd:549-566](manager_proto.gd:549)
  `_sol_present_sous`. → remplacé par `carte.sommet()` lecture data
  ([manager_proto_2.gd:301](manager_proto_2.gd:301)).
- **StaticBody3D + CollisionShape3D par ramassable** — [manager_proto.gd:808-817](manager_proto.gd:808)
  `_ajouter_collision_ramassable`. → pas de collision physique par entité, tout
  passe par `formes` data et `collision.gd` GJK/EPA.
- **Camera raycast pour ramassage** — [manager_proto.gd:842-875](manager_proto.gd:842)
  `_objet_ramassable_sous_viseur`. → à réimplémenter côté data si M1 en a
  besoin, mais hors périmètre ennemis.
- **PhysicsRayQueryParameters3D pour creusage** — [manager_proto.gd:908-940](manager_proto.gd:908)
  `_sous_cube_sous_viseur`. Idem, hors périmètre ennemis M1.
- **Mesh de barre de vie porté par le nœud MMi** — pattern MeshInstance3D
  child par ennemi ([ennemis.gd:602-623](ennemis.gd:602)) reste à porter en
  MultiMesh (voir section 3).
- **Conversion des producteurs préexistants en freeze KINEMATIC** —
  [manager_proto.gd:185-230](manager_proto.gd:185) `_convertir_producteurs_initiaux`.
  → obsolète, plus de producteurs pré-placés en scène.

**Mécanismes de manager_proto à ré-écrire en M1 (pour les ennemis) :**

- L'IA multi-états déjà data-pure dans [ennemis.gd](ennemis.gd) → reprendre
  telle quelle, elle respecte la doctrine (aucun raycast, tout sur
  `carte.sommet`/`tas.sommet_effectif`/`Tick`).
- Le rendu des ennemis (MeshInstance3D + barres) actuellement dans
  manager_proto → migrer en MultiMesh (voir section 3).
- Le `_ennemis.tick(delta)` de [manager_proto.gd:250](manager_proto.gd:250) →
  bascule vers `_physics_process` du manager qui appelle `_ennemis.tick(delta)`
  (déjà data-pure, aucun refactor doctrinal nécessaire dedans).

---

## Rapport final — questions ouvertes pour Yael avant M1

1. **Rendu MultiMesh — un ou plusieurs ?** Un MultiMesh unique pour tous les
   ennemis (simple, un seul mesh cube), ou plusieurs selon un futur besoin
   (variantes visuelles) ? Impact sur le code manager.

2. **Rendu MultiMesh — streaming par visibilité ou global ?** Le streaming
   actuel (`_bascule_rendu` par distance) libère le nœud hors rayon. En
   MultiMesh, deux options : (a) tenir toutes les entités dans le MM et
   compter sur le custom_aabb + culling Godot, (b) réserver un slot d'instance
   uniquement pour les entités dans le rayon et laisser les hors-rayon sans
   slot. (a) est plus simple, (b) économise du VRAM à N=2500.

3. **Barres de vie/nourriture visuelles — garder ou dropper ?** Aujourd'hui
   MeshInstance3D enfants par ennemi. Trois options : (a) MultiMesh séparé
   pour les barres, (b) shader per-instance qui écrit une couleur/hauteur de
   barre dans le mesh principal, (c) suppression des barres visuelles au
   profit d'un HUD/mini-map. Décision de design, pas de code.

4. **Le profil `simple` pour les cubes de manager_proto_2 aujourd'hui ?** Les
   cubes actuels COLLENT au sol (pas de gravité). Les ennemis M1 doivent
   TOMBER si le sol s'effondre — passage au profil `simple` obligatoire. Pas
   une question ouverte au sens strict, mais à confirmer que M1 remplace bien
   ce comportement.

5. **Corps-à-corps joueur→ennemi — où vit-il ?** Aujourd'hui `frapper_melee`
   dans [ennemis.gd:570](ennemis.gd:570), déclenché par `arme_tir.gd` côté
   joueur. Le manager M1 doit-il exposer une méthode publique équivalente, ou
   c'est un module séparé ?

6. **Cadavres — laisser passer par `tas.gd` ou concevoir un module cadavre ?**
   Aujourd'hui `_tas.spawn_sous_cube_libre(pos, "cadavre", false)` réutilise
   l'infrastructure sous-cube. Cohérent avec la doctrine ADN (le cadavre est
   « une chose du monde », inflammable/traversable comme tout autre sous-cube).
   Sauf raison contraire, garder ce chemin.

7. **Perception (canaux, saillance) — brancher en M1 ou plus tard ?**
   `_tick_perception` est vide aujourd'hui. Les cubes portent déjà le contrat
   (`canaux`, `canaux_config`). Décision : M1 branche la perception ou reste
   sur l'IA « chasse la position joueur brute » ?

8. **Coalescence à N=2500 ?** Aucune coalescence dans manager_proto_2 (`max_cubes
   = 10`). À N=2500 ennemis + IA multi-états + tick à 30 Hz, un balayage plein
   de `_tick_ia_ennemis` pourrait dépasser le budget frame. À mesurer une fois
   M1 debout ; pas de décision préventive nécessaire.

9. **Statique de test à conserver ?** `ajouter_statique(pos)` sert au test
   S6-style. Si M1 garde le mécanisme, il faut l'exposer sur le nouveau
   manager. Sinon on peut retirer.
