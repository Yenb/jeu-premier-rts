# PREP M1 — Ennemis data-pure + MultiMesh, cible 10 000 unités à 60 FPS

Constat préalable, cité par lecture réelle. Aucun bloc de code : `fichier:ligne` partout.

---

## A. État actuel des ennemis

Deux couches coexistent : la donnée (`jeu/Proto/ennemis.gd`, RefCounted) et le rendu/glue (`jeu/Proto/manager_proto.gd`, Node).

**Structure de données.** Un ennemi est un `Dictionary` ajouté à `_ennemis: Array` — voir `ennemis.gd:143-173` (`_spawner_un_ennemi`) et `ennemis.gd:182-212` (`ajouter_statique`). Champs : `position`, `vie`, `noeud`, `est_mort`, `nourriture`, `famine`, `etat`, `cible_cellule`, `derniere_cible_creusee`, `sc_porte`, `cooldown_creusage`, `cooldown_grimpe`, `derniere_direction_chasse`, plus un sous-dict `proprietes` (contrat framework `Tick` + `Mouvement` profil `"simple"`).

**Boucle IA.** `Ennemis.tick(delta)` — `ennemis.gd:98-101` — appelle **chaque frame** trois passes :
1. `_tick_spawn_ennemis` (`ennemis.gd:103-115`) — horloge `_intervalle_spawn` (défaut 1 s), max `_max_ennemis`, `ennemis_par_cycle` par salve.
2. `_tick_ia_ennemis` (`ennemis.gd:214-359`) — parcourt tous les `_ennemis`. Pour chaque : gestion mort, cooldowns, calcul vecteur vers joueur, match d'état (`chasse`/`creuse`/`cherche_sc`/`pose`), pose de l'intention de mouvement, puis `Tick.tick_entite(...)` qui délègue gravité/snap/blocage terrain à `Mouvement` (`ennemis.gd:338`). Ensuite coût nourriture selon distance parcourue et dénivelé (`ennemis.gd:340-348`), gestion famine (`ennemis.gd:349-358`).
3. `_repousser_ennemis` (`ennemis.gd:361-391`) — buckets 2D par colonne d'arête `RAYON_REPOUSSE_ENNEMI = 0.9 m` (`ennemis.gd:51`), test pair-à-pair intra-bucket et voisinage 4-connexité, séparation instantanée (`_appliquer_repousse_ennemis` `ennemis.gd:393-420`).

Fréquence : `manager_proto.gd:251` (`_ennemis.tick(delta)`) — dans `_process(delta)`, **60 Hz** (rythme rendu).

**Représentation visuelle.** Un ennemi entré dans `rayon_rendu_entrer` (défaut 60 m — `manager_proto.gd:20`) instancie un noeud complet dans `_creer_visuel_ennemi` (`manager_proto.gd:1554-1586`) : **un `StaticBody3D` racine, un `MeshInstance3D` cube, un `MeshInstance3D` barre-vie, un `CollisionShape3D` + `BoxShape3D`, un `MeshInstance3D` barre-nourriture**. Streamé par distance dans `_bascule_rendu_ennemis` (`manager_proto.gd:1519-1552`), hystérésis 60/65. Mise à jour de position chaque frame : `(e.noeud as Node3D).global_position = e.position` (`manager_proto.gd:1552`).

**Détection cible.** Direct : vecteur `pos_obs - pos` calculé chaque tick, `pos_obs` fourni par le percepteur (`ennemis.gd:214-220`). Aucun index spatial pour la cible : la cible EST le joueur (unique).

**Collision entre ennemis.** Buckets 2D O(N × k) — `_repousser_ennemis`, `ennemis.gd:361-391`. Arête `0.9 m`. Chaque tick, reconstruction complète du dictionnaire de buckets.

**Interaction avec la carte.** Lectures `_carte.sommet_max_colonne`, `_carte.sommet`, `_carte.est_pleine`, `_carte.item_de`, `_carte.ajouter_pv_sous_cube`, `_carte.couche_base` (`ennemis.gd:128-138`, `ennemis.gd:480-511`, `ennemis.gd:513-554`). Écritures via `_effondrer.call(...)` (callback vers `manager_proto._effondrer_selon_materiau` — `manager_proto.gd:750-772`) et via `_tas.monde().ajouter/retirer`, `_tas.index_ajouter/index_retirer` pour les sous-cubes portés/posés (`ennemis.gd:271-280`, `ennemis.gd:431-453`).

**Compteur `max_ennemis`.** `manager_proto.gd:48` — `max_ennemis: int = 2500`, `ennemis_par_cycle: int = 5` (`manager_proto.gd:50`). Aucune conception au-delà de ~2500 aujourd'hui.

**Doctrine violée.** `_creer_visuel_ennemi` **crée un StaticBody3D + CollisionShape3D par ennemi** (`manager_proto.gd:1554-1574`) et ajoute chaque racine au SceneTree (`manager_proto.gd:1548`). C'est exactement le pattern interdit par `CLAUDE.md.bak-20260823-212417:159-203` (CANEVAS DE BASE DES POPULATIONS MASSIVES).

---

## B. Patron cible depuis `manager_proto_2.gd` et `tas.gd`

**`manager_proto_2.gd` (cubes verts errants).** Stockage identique : `_ennemis: Array` de `Dictionary` (`manager_proto_2.gd:80`). Chaque cube porte `id`, `position`, `proprietes` (canaux perception, formes de collision data, `aabb_cache`, masques, `velocite`, `orientation`), `noeud`, `direction`, `cap_horloge` (`manager_proto_2.gd:256-277`). **Inscrit au `Monde`** (`scripts/monde.gd`) via `_monde.ajouter(cube, "cube_vert", cube.position)` (`manager_proto_2.gd:285`).

**Boucle tick.** `_physics_process(delta)` — `manager_proto_2.gd:190` — 60 Hz. Appelle : `_tick_spawn`, `_tick_errance`, `_pas_joueur`, `_bascule_rendu`, plus horloge `INTERVALLE_PERCEPTION = 0.1` (`manager_proto_2.gd:57`) pour `_tick_perception` (encore vide). Chaque cube qui bouge appelle `_monde.deplacer(cube)` (`manager_proto_2.gd:310`).

**Rendu.** **Un `MeshInstance3D` par cube**, instancié par `_creer_visuel()` (`manager_proto_2.gd:406-410`) au streaming (`_bascule_rendu` `manager_proto_2.gd:383-404`). Le mesh partagé `_mesh_ennemi: BoxMesh` est réutilisé (`manager_proto_2.gd:81`, `_preparer_mesh` `manager_proto_2.gd:205-210`) mais **le noeud n'est PAS un MultiMesh** — c'est un noeud par cube dans le SceneTree. Même violation du canevas, à petite échelle (`max_cubes: int = 10` — `manager_proto_2.gd:70`). C'est donc un patron data-pure côté simulation, mais pas côté rendu.

**Terrain commun.** `_deplacement_horizontal_valide` (`manager_proto_2.gd:323-330`) : critère générique bord de carte + marche max. À réutiliser tel quel pour un ennemi.

**Ce que `tas.gd` fait bien.**
- Owne son propre `Monde` — `tas.gd:43`, `tas.gd:53` — au lieu d'utiliser un `Monde` externe. Index séparé (`_index_sc_par_colonne` — `tas.gd:44`) pour `sommet_effectif` (`tas.gd:96-113`), disjoint du Monde spatial : deux indices coopèrent, chacun pour une requête différente.
- Boucles data-only, aucune référence au SceneTree — RefCounted pur (`tas.gd:1`).
- Rendu délégué : `mesh_pour_matiere` / `ajouter_collision_cube_libre` (`tas.gd:313-330`) sont des fabriques appelées par le manager, jamais par `tas.gd` lui-même.

**Comment `monde.gd` est utilisé.** Index spatial multi-résolution par cases cubiques : chaque rayon demandé ouvre une résolution `2^n` couvrant ce rayon (`monde.gd:302-305`, entête `monde.gd:19-32`). `choses_dans_rayon(pos, r)` (`monde.gd:233-257`) lit uniquement les cases touchées, distance carrée. Subdivision adaptative des buckets (`SEUIL_SPLIT=20`, `SEUIL_MERGE=5`, `PROFONDEUR_MAX=3` — `monde.gd:166-168`), essentielle pour un empilement local (`monde.gd:54-62`). Coût mesurable par `requetes`/`cases_lues`/`candidats_mesures` (`monde.gd:120-127`).

---

## C. Architecture proposée pour M1

**Structure de données.** `Array` de `Dictionary` — même patron que `manager_proto_2.gd:256-277`, `tas.gd:127-134`. Justification : les PackedArrays parallèles (SoA) sont mesurés plus rapides quand la boucle scanne tous les champs d'un seul type (SIMD-friendly), mais en GDScript la vectorisation n'existe pas et le coût dominant est l'allocation/hash (voir `strayspark.studio/blog/godot-3d-optimization-guide-2026`). Le Dictionary a l'avantage d'être compatible avec le contrat de `monde.gd` (position lue par `chose.position`), avec `Tick.tick_entite` (`ennemis.gd:338`), et avec `collision.gd` (`.proprietes.formes`). Migration SoA envisageable si M1 dépasse le budget après mesures — le canevas CLAUDE ne l'exige pas.

**Rendu.** UN `MultiMesh` par forme d'ennemi (M1 : une forme), rendu via **instance `RenderingServer` directe** — patron `rendu_terrain_multimesh.gd:853-870` (`_creer_instance_rs`) : `RenderingServer.instance_create` + `instance_set_base` + `instance_set_scenario` + `instance_set_transform` + `instance_set_custom_aabb`. Update par frame : `set_instance_transform` en boucle, ou passage à `RenderingServer.multimesh_set_buffer(rid, PackedFloat32Array)` si mesure de coût le justifie (docs Godot : « il est possible de définir l'état entier via mémoire linéaire, efficacité cache élevée »). **1 draw call** pour la forme unique de M1. Buffer plein alloué à la création (`multimesh.instance_count = max_ennemis`), `visible_instance_count` sert à cacher les slots inactifs (docs Godot).

**Index spatial.** Réutiliser `scripts/monde.gd` — déjà en place, subdivision adaptative documentée pour tenir un attroupement local (voir `monde.gd:54-62`). Rayon typique par tick : `RAYON_REPOUSSE_ENNEMI = 0.9 m` (repousse) et `RAYON_ENNEMI_CHERCHE_BLOC = 3 cellules = 6 m` (IA cible bloc). L'exposant naturel serait `2^0 = 1 m` pour la repousse et `2^3 = 8 m` pour la cible : 2 résolutions ouvertes en parallèle, coût borné à 8 cases lues par requête (entête `monde.gd:22-27`). Écarté : hash grid uniforme neuf — `monde.gd` porte déjà le multi-résolution et les compteurs, dupliquer casse la doctrine « LOCALITÉ SPATIALE ».

**Tick scheduler LOD.** Trois tiers, distance à l'observateur mesurée à distance carrée :
- Tier 0 (proche, `d² < 40²`) : tick à **60 Hz** — IA + collision + rendu MultiMesh update.
- Tier 1 (moyen, `40² ≤ d² < 120²`) : tick IA à **10 Hz** (1 frame sur 6), rendu MultiMesh update à 60 Hz (transform seul).
- Tier 2 (lointain, `d² ≥ 120²`) : tick IA à **1 Hz**, position figée entre ticks, pas de rendu (hors rayon MultiMesh de toute façon).
Distribution round-robin sur les frames pour lisser (patron RimWorld HugsLib : « spread updates across frames »). Réévaluation du tier au tick 1 Hz suffit — une entité ne change pas de tier en 100 ms utiles.

**Collision entre ennemis.** Buckets réutilisables du patron existant (`ennemis.gd:361-391`) mais adossés à `monde.choses_dans_rayon(pos, 0.9)` par ennemi tier 0. Coût O(N × k), k ≈ 4 voisins moyens à densité normale, k ≥ 20 en attroupement où la subdivision de `monde.gd` intervient (`monde.gd:166`). Pas de GJK/EPA sur ennemi-ennemi (surdimensionné) : la repousse instantanée à seuil = ce qui marche déjà pour les carrés (`manager_proto.gd:696-709`) et pour les ennemis (`ennemis.gd:393-420`).

**IA réactive.** Steering behaviors : chaque ennemi calcule un vecteur `direction = normalize(pos_joueur - pos)` puis `velocite_desiree = direction × vitesse`, exactement l'état `chasse` actuel (`ennemis.gd:258-292`). Pas de flow field pour M1 — un flow field prend son sens quand N cibles distinctes ou quand un obstacle statique nécessite un contournement collectif ; le joueur est unique et le terrain déjà géré par `Mouvement.tick_entite` + `_mouvement_bloque_par_terrain` (`ennemis.gd:422-429`). Flow field noté en questions ouvertes (voir H).

**Interaction carte.** Conservée : `_carte.sommet`, `_carte.sommet_max_colonne`, `_carte.est_pleine`, `_carte.item_de`. Mise en cache par ennemi de la colonne courante `col = Vector2i(floor(x/cote), floor(z/cote))` recalculée seulement au franchissement (patron `objets_visibles.gd:70-82` où `_centre_pose` mémorise la dernière position ; ici la clé est la colonne, pas la position). `_effondrer_selon_materiau` reste au manager (déjà appelé via Callable — `ennemis.gd:16-17`).

---

## D. Budget pour 10 000 ennemis à 60 FPS

Frame = **16.67 ms**. Budget alloué au tick ennemis : **5 ms max** (30 % de la frame, laisse 11.67 ms au rendu terrain, joueur, tas, HUD).

**Ventilation LOD (hypothèse 10 000 ennemis, joueur en zone dense) :**

| Tier | Population | Fréquence | Ennemis tick/frame |
|---|---|---|---|
| 0 (`d < 40`) | ~500 | 60 Hz | 500 |
| 1 (`d < 120`) | ~3000 | 10 Hz | 500 (1/6) |
| 2 (`d ≥ 120`) | ~6500 | 1 Hz | 108 (1/60) |
| **Total tick IA / frame** | | | **~1108** |

À 5 ms / 1108 ennemis tick/frame : **4.5 µs par ennemi et par tick**. Ventilation cible par ennemi :
- Mouvement (steering + `Tick.tick_entite`) : 1.5 µs
- IA (état + comparaison distance) : 0.5 µs
- Collision (1 `choses_dans_rayon(0.9)` + repousse pair-à-pair k≈4) : 1.5 µs
- Update MultiMesh (`set_instance_transform` — tier 0 et 1 seulement, ~3500 slots) : 1.0 µs

**Verdict.** Atteignable **avec réserves fortes**, sourcé sur `slashskill.com/godot-4-characterbody3d-vs-multimesh` : « 5000 unités : 30-45 FPS » côté MultiMesh, avec la note « au-delà de 5000, boucle GDScript devient goulot ». Le LOD tick (RimWorld HugsLib) et `multimesh_set_buffer` (docs Godot) sont les deux leviers indispensables pour passer de 5k GDScript à 10k. Si mesure M1a montre > 5 µs par ennemi tier 0, migrer l'update MultiMesh vers `multimesh_set_buffer(PackedFloat32Array)` puis, si toujours insuffisant, alléger le Dictionary vers PackedArrays parallèles pour les champs chauds (position, velocite, vie).

---

## E. Contraintes doctrinales

Sources : `CLAUDE.md.bak-20260823-212417:159-241` (canevas + localité spatiale), `jeu/Proto/COLLISION.md`, `jeu/Proto/PATRON_ENTITES.md:112-125` (règle absolue « tout est donnée »).

**Interdits absolus pour M1.**

1. **Zéro `StaticBody3D` par ennemi.** Justification : canevas `CLAUDE.md.bak:180-192` — un Node3D pèse 1320 octets, 10 000 × 3 nœuds × 60 fps = 1.8 M dispatches/s avant logique. Contre-exemple à supprimer : `manager_proto.gd:1554-1574` (`_creer_visuel_ennemi`).
2. **Zéro `CollisionShape3D` / `BoxShape3D` par ennemi.** Même justification. Collision entre ennemis passe par la repousse buckets data-pure (patron `ennemis.gd:361-420`). Collision ennemi↔joueur envisageable via `collision.gd` (data pure GJK/EPA), mais dimensionnée dans M1c seulement. Contre-exemple à supprimer : `manager_proto.gd:1570-1574`.
3. **Zéro `intersect_ray` / `PhysicsRayQueryParameters3D` dans la boucle ennemis.** Justification : `PATRON_ENTITES.md` § « Ce que le système NE fait PAS ». Le sol se lit par `_carte.sommet` ou `_tas.sommet_effectif`, jamais raycast. `ennemis.gd` respecte déjà — vérifier que M1 n'introduit rien via nouveau helper.
4. **Zéro `RigidBody3D` pour ennemi.** Même justification.
5. **Zéro `Node3D` individuel par ennemi dans le SceneTree.** Le rendu passe par UN MultiMesh partagé. Contre-exemples à supprimer : `manager_proto.gd:1548` (`parent.add_child(n)`) et `manager_proto_2.gd:400` (à titre pédagogique — même faute à petite échelle).
6. **Zéro `get_nodes_in_group` suivi de balayage distance.** `CLAUDE.md.bak:238-241` (piège documenté récurrent). L'index `monde.gd` est la seule voie.
7. **Zéro `class_name`.** `CLAUDE.md.bak:243-253`. Tout par `preload`.
8. **RNG toujours seedé.** `CLAUDE.md.bak:147`. Patron déjà en place (`ennemis.gd:90` : `_rng_ennemis.seed = 20260827`).
9. **Simulation indépendante du rendu.** `PATRON_ENTITES.md:112-125` — un ennemi mort en data reste mort, hors rayon rendu la sim continue.

---

## F. Découpe M1a / M1b / M1c

**M1a — Structure data + rendu MultiMesh, sans IA.**
- Nouveau module `jeu/Proto/ennemis_pure.gd` (RefCounted). Copie stricte du contrat entête de `ennemis.gd:1-35` adapté.
- `Array` de `Dictionary` : `id`, `position`, `velocite`, `vie`, `est_mort`.
- Spawn de 100 ennemis à des positions aléatoires seedées dans la zone de spawn, direction initiale linéaire (cap constant).
- Nouveau module `jeu/Proto/rendu_ennemis_multimesh.gd` (Node3D). UN `MultiMesh` de `BoxMesh` 0.8×0.8×0.8, `instance_count = max_ennemis`. Instance RS via patron `rendu_terrain_multimesh.gd:853-870`. Update `set_instance_transform` chaque frame pour les slots actifs.
- Streaming : `visible_instance_count = nb_ennemis_actifs`.
- **Fini quand** : 100 ennemis se déplacent en ligne droite, visibles à l'écran via 1 draw call, aucun `StaticBody3D`/`Node` per-entité, `_ennemis.size() == 100` stable, aucun push_error.

**M1b — Index spatial + collision entre ennemis.**
- Inscription au `Monde` (patron `manager_proto_2.gd:285`). `deplacer` après chaque tick de position (patron `manager_proto_2.gd:310`).
- Repousse ennemi↔ennemi via `monde.choses_dans_rayon(pos, 0.9)` par ennemi tier 0 (patron `ennemis.gd:393-420` adossé à `monde` au lieu de rebâtir les buckets chaque frame).
- Passage à 1000 ennemis. Mesure : compteurs `monde.requetes` / `monde.cases_lues` (`monde.gd:120-123`), `Engine.get_frames_per_second()`.
- **Fini quand** : 1000 ennemis marchent, aucun ne se traverse, FPS ≥ 60, `cases_lues / requetes` reste borné (< 4 en moyenne).

**M1c — IA réactive + interaction carte + LOD tick.**
- Steering vers `_percepteur.call()` (patron `ennemis.gd:214-292`).
- Sol par `_carte.sommet` + `_mouvement_bloque_par_terrain` (patron `ennemis.gd:422-429`).
- Tick scheduler LOD 3 tiers (§ C). Distribution round-robin par bucket `id % N`.
- Passage à 10 000 ennemis. Mesure : ms de `_tick_ia_ennemis`, ms de `_bascule_rendu_ennemis`, FPS.
- **Fini quand** : 10 000 ennemis se dirigent vers le joueur, tick IA total < 5 ms/frame, rendu update < 2 ms/frame, FPS ≥ 60 en scène chargée.

---

## G. Filets de sécurité

**Flag `@export`.** OUI, indispensable — patron `rendu_terrain_multimesh.gd:89` (`utilise_rs_direct: bool = false`). Proposition :
- `@export var utilise_ennemis_pure_data: bool = false` sur `manager_proto.gd`. Faux (défaut) : chemin actuel `Ennemis.new(...)` + `_creer_visuel_ennemi` intact. Vrai : bascule sur `EnnemisPure.new(...)` + `RenduEnnemisMultiMesh` (M1). Tests headless existants ne bougent pas.
- Bascule dans un commit séparé de la validation en jeu, patron `rendu_terrain_multimesh.gd:82-88` cité tel quel.

**Coexistence.** Deux `Array` disjoints : `_ennemis` (legacy, `ennemis.gd`) et `_ennemis_pure` (M1). `_process` appelle l'un OU l'autre selon le flag. Chemins d'interaction (frappe, dégâts contact joueur, hit balle) : sous le flag, la balle `_tick_balles` (`manager_proto.gd:617-632`) et `_tick_pv_joueur` (`manager_proto.gd:1641-1656`) itèrent `_ennemis_pure` au lieu de `_ennemis.ennemis()`. Contrat du dict pure conserve `est_mort`, `vie`, `position` — signatures compatibles.

**Test à petite échelle.** M1a démarre à `max_ennemis = 100`, M1b à 1000, M1c à 10 000. Chaque palier commit séparé. Mesures intermédiaires via `Performance.get_monitor(Performance.TIME_PROCESS)`, comparaison avant/après.

---

## H. Questions ouvertes que Yael doit trancher

1. **IA — steering pur ou flow field ?** M1c propose steering pur (joueur unique). Un flow field global vers le joueur est plus cher à construire (grille + BFS) mais uniforme (10 000 ennemis lisent 10 000 vecteurs pré-calculés). Trancher si M1c ne tient pas 60 FPS, ou d'entrée si Yael veut la trajectoire d'évitement propre (contournement d'un mur épais).
2. **Une espèce ou plusieurs ?** Le mesh, la taille, la vitesse, la vie, la portée de dégât — tous varient. Une espèce en M1 = 1 MultiMesh. Plusieurs = 1 MultiMesh par espèce (patron `rendu_terrain_multimesh.gd:107` — un MMi par forme). Trancher avant M1a pour dimensionner le module rendu.
3. **Interaction joueur — contact, tir, corps-à-corps.** Aujourd'hui : dégât par contact via `_tick_pv_joueur` (`manager_proto.gd:1633-1656`), hit balle dans `_tick_balles` (`manager_proto.gd:617-632`), hit corps-à-corps par `frapper_melee` (`ennemis.gd:570-597`). Tous itèrent `_ennemis.ennemis()`. Sous le flag, doivent itérer `_ennemis_pure` — signatures à préserver.
4. **Mort d'un ennemi — cadavre ou disparition ?** Aujourd'hui : `_tas.spawn_sous_cube_libre(..., "cadavre", false)` (`ennemis.gd:231`), donc un sous-cube brun ajouté au tas. M1 conserve-t-il ? Impact budget : 10 000 morts en série = 10 000 spawn de sc au tas, plafond `MAX_TAS = 2000` (`tas.gd:35`) fait rouler l'anneau — à valider.
5. **Creusage / pose de sous-cubes conservés ?** Toute l'IA `creuse`/`cherche_sc`/`pose` (`ennemis.gd:293-332`) coûte des lectures/écritures carte + tas. Si conservé à 10 000, budget § D à recompter (probable dépassement). Option : M1 ne porte que `chasse` + `repousse` ; creusage réservé à un sous-ensemble « fouisseur » explicitement marqué.
6. **Faim / famine conservées ?** `NOURRITURE_MAX_ENNEMI = 500`, `COUT_NOURRITURE_PAR_M = 1.0` (`ennemis.gd:46-48`) — deux barres par ennemi (`manager_proto.gd:1560-1585`). Barres via MultiMesh = un 2e MultiMesh de quads, ~20 000 instances si conservé. Simplification : pas de barres visibles en M1, réintroduire au cas par cas.
7. **Zone de spawn.** `spawn_demi_cote = 10.0` (`manager_proto.gd:45`) — trop petit pour 10 000. Augmenter à 100 m ? Ou plusieurs zones ?
8. **Ratio tier 0/1/2 réaliste.** Les hypothèses (§ D : 500/3000/6500) supposent une distribution spatiale. Si les 10 000 se regroupent tous dans le rayon 40 m, tier 0 explose. Fallback : plafond `MAX_TIER0 = 1000`, au-delà les ennemis proches en excédent basculent tier 1 même s'ils sont proches. Doctrine à valider.

---

## Verdict et confiance

La fiche permet d'exécuter M1a **mécaniquement** (nouvelle boucle + nouveau rendu MultiMesh sous flag, cible 100 ennemis). M1b et M1c dépendent de décisions H1, H2, H4, H5, H8 : sans tranchage, un exécutant devra deviner et risque de refaire le chantier. Le budget § D est atteignable **si** `multimesh_set_buffer` est disponible en fallback et si le LOD tick est appliqué — les deux sont sourcés mais aucun n'est mesuré sur ce projet. Un banc de mesure `test_perf_ennemis_10k` en fin de M1a est le seul filet qui rende la suite prévisible.

---

## Sources

- [Godot 4 MultiMesh docs — using_multimesh.rst](https://github.com/godotengine/godot-docs/blob/master/tutorials/performance/using_multimesh.rst)
- [Godot 3D Optimization Guide 2026 — StraySpark](https://www.strayspark.studio/blog/godot-3d-optimization-guide-2026)
- [Godot 4 CharacterBody3D vs MultiMesh — SlashSkill](https://www.slashskill.com/godot-4-characterbody3d-vs-multimesh-scaling-hundreds-of-units-without-killing-performance/)
- [MeshInstance3D vs MultiMesh — BitSoulHosting](https://bitsoulhosting.com/marketplace/blog/meshinstance3d-vs-multimesh-godot-4-rendering-guide)
- [godot-proposals#957 — Partial region multimesh updates](https://github.com/godotengine/godot-proposals/issues/957)
- [How to RTS — Basic Flow Fields (howtorts.github.io)](https://howtorts.github.io/2014/01/04/basic-flow-fields.html)
- [jdxdev — RTS Pathfinding Flowfields](https://www.jdxdev.com/blog/2020/05/03/flowfields/)
- [KamilVDono/ECS_Units — Unity DOTS RTS 1000 units](https://github.com/KamilVDono/ECS_Units)
- [Unity DOTS RTS Collision System](https://github.com/unitycoder/Unity-DOTS-RTS-Collision-System)
- [vonWolfehaus/flow-field — flow field + steering behaviors](https://github.com/vonWolfehaus/flow-field)
- [RimWorld HugsLib — Custom Tick Scheduling (round-robin LOD)](https://github.com/UnlimitedHugs/RimworldHugsLib/wiki/Custom-Tick-Scheduling)
- [Performance — Slower Pawn Tick Rate (RimWorld Steam Workshop)](https://steamcommunity.com/sharedfiles/filedetails/?id=3524116050)
- [Factorio Wiki — Diagnosing performance issues](https://wiki.factorio.com/Tutorial:Diagnosing_performance_issues)
- [Dubs Performance Analyzer — RimWorld profiling](https://github.com/simplyWiri/Dubs-Performance-Analyzer)
