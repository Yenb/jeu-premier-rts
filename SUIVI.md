# SUIVI

Journal de bord de la programmation du jeu. SEUL document que Claude Code
modifie au fil des sessions.

Cinq sections, jamais d'autre. FAIT : une ligne par étape terminée, la plus
récente en tête, hash de commit si applicable — sinon la date — puis quoi, en
une phrase. EN COURS : ce qui est ouvert maintenant, un tiret par point.
DÉCISIONS : les choix pris en session qui ne sont écrits ni dans `CLAUDE.md` ni
dans le code ; une décision SORT d'ici dès qu'elle est écrite ailleurs.
PROCHAINES ÉTAPES : ce qui vient après, dans l'ordre. PIÈGES DÉJÀ PAYÉS :
autorisé explicitement par Yael, contre la règle du récit — un piège coûte deux
fois si personne ne l'a écrit. Symptôme, cause, règle. Jamais l'histoire.

## FAIT

- 2026-09-06 — ETAPE (b) du portage C++ de `_phase_parser` : MINI-CUBES et NON-CUBES ajoutes a `MesheurTuile::bake_tuile_a`. Portage face-par-face identique -- mini-cube (cote/3) par bit du masque sous-cube, couleur blanc->noir selon pv/MAX_PV_SOUS_CUBE ; non-cube (rampe, cylindre, sphere) = base_orthogonale x mesh_transform, une instance par cellule. Contrat de blob etendu cote GDScript (`_blob_tuile_a`) : `pv_par_cellule` (quintuples x,y,z,sous_idx,pv, remplace l'ancien triple `cellules_pv`), `bases_orthogonales` (PackedFloat32Array 24x9 precalculee via `_regle.get_basis_with_orthogonal_index`), `mesh_transforms` (Dictionary item->Transform3D pour les items NON-cubiques via `mesh_library.get_item_mesh_transform`), `max_pv_sous_cube`. Retour C++ : `par_forme_mini` (Dict {item -> Array<Dictionary{transform, couleur}>}, meme format que `_ajouter_mini_cubes` GDScript, injection directe dans `par_forme_mini` du bucket) ; non-cubes fusionnes dans `par_forme` (memes items ids que le chemin GDScript). Cote GDScript, les branches `_ajouter_mini_cubes` et non-cube (`else:` de _phase_parser) sont GATEES derriere `utilise_cpp_phase0` -- flag OFF garde le chemin historique complet pour comparaison visuelle et rollback safe (option C tranchee par Yael, l'etape (d) retirera les chemins morts apres validation). Recompilation clean, `verification.tscn` charge sans erreur flag off. Test visuel flag on = a faire par Yael (basculer le @export sur le noeud de rendu de la scene testee, notamment casser un bloc et voir les mini-cubes, regarder une rampe).
- 2026-09-06 — ETAPE (a) du portage C++ de `_phase_parser` (rendu_terrain_multimesh.gd). `MesheurTuile::bake_tuile_a(entree)` (extension_terrain/src/mesheur_tuile.{h,cpp}) prend en charge les faces cubiques PROPRES d'une tuile (sous_cubes plein, aucun PV), algo face-par-face IDENTIQUE au GDScript (visible_bits_col, _voisin_couvre reduit a un test de bit sur les couvrants, hauteur par item, Y-scale des faces laterales, dessus abaissee pour un item plus court). Contrat de blob assemble UNE fois par tuile (frontiere franchie une seule fois) : masques + couvrants 12x12 (tuile + 4 anneaux), particularites/sous_cubes_partiels/cellules_pv linearises en PackedInt32Array restreints a la tuile, tables item->cubique / item->hauteur, centre_offset (`_regle.map_to_local(Vector3i(0,0,0))`). Sortie : Dict { par_forme, par_forme_sol } avec, par item, { transforms: Array of Transform3D, cellules: PackedInt32Array parallele }. Le C++ monte les entrees en std::unordered_map/set a l'entree, calcule sur std::vector<Transform3D>, convertit UNE fois a la fin (patron godot_voxel, pas de SurfaceTool). Gate cote GDScript par `@export utilise_cpp_phase0` (defaut FAUX -- chemin historique intact) : les 6 `_ajouter_face` du bloc "cube propre" sont sautes quand le flag est vrai, la teinte est repoussee apres la boucle dans `_appliquer_cpp_a` a partir du mapping face->cellule que le C++ rend et de `_cache_profil_cellule` (peuple par la boucle quel que soit le flag). Mini-cubes, non-cubes, occluder cells, cache profil restent en GDScript pour cette etape. Recompilation clean (`python -m SCons platform=windows arch=x86_64 target=template_debug`), .dll charge, `bonjour()` OK, verification.tscn charge sans erreur (flag off = comportement identique). Test visuel flag on : a faire par Yael a l'ecran (basculer `utilise_cpp_phase0` sur le noeud de rendu de la scene testee).
- 2026-09-04 — `carte_terrain.masque()` sans appel de fonction interne : `dans_emprise` inlinee (test direct des bornes) et `masque_de_base` remplacee par le cache `_masque_base` (recompute uniquement quand `couches_pleines` change, via son setter -- robuste au chargement de ressource, contre le piege @tool + _init). `dans_emprise()` et `masque_de_base()` restent publiques.
- 2026-09-04 — HOT PATH BANC PEUPLEMENT APLATI. `banc_peuplement._physics_process` appelle `Mouvement.pas_simple` et `Peuplement.ecrire_transform_index` en direct — plus de `Tick.tick_entite`, plus de `Callable.call`, plus de `match profil` String, plus de lookup `id_to_index` par String. `Mouvement._pas_simple`/`_pas_minimal` deviennent publiques (`pas_simple`/`pas_minimal`) — `pas()` avec match reste pour les appelants qui passent un profil String. `Peuplement.ecrire_transform_index(pool, index)` sauté le hash. `carte_terrain.sommet` et `sommet_sous` cachent `masque(col)` une fois en tête et lisent `_masques_sous_cube` en direct (plus de rappel de `masque` / `est_pleine` / `sous_cubes` en boucle). Comportement du banc identique.
- 59c2fb0 — RENDU PROTO : hystérésis de rayon (`rayon_rendu_entrer`/`_sortir`, idem balles) dans les deux managers — le nœud s'instancie SOUS le rayon d'entrée, se libère AU-DELÀ du rayon de sortie ; l'écart tue le flip-flop au bord. + ENNEMIS DE TEST STATIQUES : `ennemis.ajouter_statique(pos)` + capture des marqueurs de scène « ennemi_test_statique » (`manager_proto._capturer_ennemis_statiques_test`) — immobiles (gravité + snap sol via Tick+Mouvement profil « simple », zéro IA) pour éprouver le pipeline rendu/streaming/hystérésis sans que l'IA les bouge. Producteurs et cubes : vertical exclusivement via `Mouvement.pas`.
- 8504a51 / 8c2b9c5 / 7d90e8e — MOUVEMENT KINEMATIC PARTAGÉ : `scripts/mouvement_kinematic.gd` + `scripts/tick.gd` factorisent gravité, snap au sol, blocage terrain/pente et plafond voxel (fin du saut à travers un bloc) en UN pas partagé (profil « simple »). Joueur, cubes ennemis et producteurs délèguent leur vertical au framework au lieu de le recalculer chacun. Écrit dans `scripts/` (cœur) au su de Yael — exception frontière (voir `CLAUDE.md` § Frontière).
- 2026-09-02 — EXCEPTION JOUEUR RETIRÉE : `collision.gd` est désormais l'autorité de déplacement du joueur. `jeu/unites/personnage.gd` passe de `CharacterBody3D` à `Node3D` — plus de `move_and_slide`, `velocity` ni `is_on_floor`. Le joueur est une ENTITÉ DATA du Monde comme les cubes : sa position est mue chaque frame (60 Hz) par `manager_proto_2._pas_joueur` en donnée pure — intention lue par APPEL DIRECT au Personnage (`intention_mouvement(delta)`, pas de course d'ordre entre `_physics_process`), gravité+saut data, TERRAIN par `_deplacement_horizontal_valide` (factorisé cubes+joueur, `carte.sommet` + blocage pente), et collision joueur↔cubes par `collision.gd` (GJK/EPA) à 60 Hz (à re-mesurer si N grand). Le manager est SEUL écrivain de la position (recopiée dans le nœud en fin de `_process`) ; le Personnage ne pilote que lacet/tangage/HUD. Dimensions et vitesses en donnée (capsule r0.4 h1.8, yeux 1.7, marche 4, saut 8.5, gravité 18), injectées au nœud par `configurer_depuis_donnees`. `personnage.tscn` : `Node3D`, `Hitbox` retiré, `Corps`→`corps_visible`, `marqueur_debug` (cube rouge à l'origine = position data exacte). Bug latent fermé : la forme capsule data porte `transform_locale` +hauteur/2 (origine aux pieds), sinon elle cognait les cubes par le sol. Fichiers dans `jeu/` seulement, aucun script du cœur touché. Vérifié : `test_personnage` VERT (nouveau contrat Node3D/1.8 m/marqueur à l'origine), `verification.tscn` compile et tourne, trace `joueur pos/vel/au_sol` 1/s prouve la position data ; rendu à vérifier à l'écran. Rouges préexistants inchangés (`test_carte`, `test_collision_terrain`, `test_scene_carte` — famille emprise 64/150 ; `test_carte_prototype` hang headless). DETTE : `jeu/CARNET_DE_JEU.md` §3.5 (capsule « 1 m », CharacterBody3D) et le commentaire `arme_tir.gd:8` (« parent = CharacterBody3D ») sont à actualiser ; l'orientation du joueur reste locale (capsule Y-symétrique) — à revoir si le joueur porte une forme orientée.
- 2c39564 — COLLISION GÉNÉRALISTE EN DONNÉE PURE : `jeu/Proto/collision.gd` (RefCounted, statique, aucune physique Godot) — fonction de SUPPORT unifiée (sphere/boite/capsule/hull, dispatch au seul endroit), GJK, EPA, `tick` (broadphase via `monde.choses_dans_rayon` + swept), `resoudre` (séparation le long de la normale). À réutiliser pour tout objet interactif ; spec complète dans `jeu/Proto/COLLISION.md`. Câblée dans `manager_proto_2` (cubes = boîte, joueur = capsule), et sert d'autorité de collision joueur↔cubes (voir entrée « exception joueur retirée » ci-dessus).
- 2026-09-02 — EXTRACTION DE `manager_proto.gd` EN DEUX MODULES RefCounted : `jeu/Proto/tas.gd` (matière granulaire — spawn, empilement, sandpile, index de colonne, meshes) et `jeu/Proto/ennemis.gd` (spawn, IA chasse/creuse/ramasse/pose, faim, repousse, corps-à-corps, barres). Déplacement pur, aucun comportement changé ; le manager garde le rendu, le dégât de contact, l'effondrement et l'HUD, et itère `_ennemis.ennemis()`. Le passage RefCounted (pas de `get_tree()`) impose des injections : Callables `fournisseur_limite`/`effondrer`/`percepteur_position`, API tas élargie (`monde`/`sommet_effectif`/`spawn_sous_cube_libre`/`index_ajouter`/`index_retirer`/`mesh_pour_matiere`/`ajouter_collision_cube_libre` publics), compteur d'id des outils (pelle/bêche) repris au manager. `_pas_permis` et `_ennemi_a_obstacle_devant` étaient morts — le premier supprimé, le second déplacé mais toujours inutilisé. Contenu uniquement dans `jeu/Proto/`, aucun script du cœur touché. Vérifié : compile + scène principale 240 frames headless, zéro erreur/warning ; comportements à valider à l'écran.
- 2026-09-02 — PROTOTYPE ENNEMI (`manager_proto.gd`) VALIDÉ PUIS ARRÊTÉ. Les ennemis fonctionnent correctement en jeu : déplacement en data pur, chute/gravité, répulsion inter-ennemis, et creusage du terrain (coups sur les sous-cubes via `carte_terrain`). Le prototype d'IA ennemie du `manager_proto` s'arrête ici — la suite part sur le type d'IA prévu (classifieur ancré LLM, voir `CLAUDE.md` § Connexion LLM). Aucun nouveau développement d'IA ennemie dans `manager_proto`.
- 352f8a0 — `couvert.gd` apparition sans gaspillage : la pose initiale des plantes n'a lieu que SANS observateur. Avant, `_ready` posait les milliers de plantes dans les lots MMI puis cherchait l'observateur à la ligne suivante, et `_bascule_rendu` radiait à la frame d'après tout ce qui était hors rayon — deux autorités de rendu qui se contredisent. Mesuré sur `verification.tscn` : 1000 lignes / 619 MultiMeshInstance3D posées au chargement, 100 % radiées ; après correctif, `_ready` pose 0 ligne / 0 lot, état stable identique. Observateur trouvé AVANT la pose ; graines toujours posées (non streamées) ; `_liberer_les_semis_disparus` lit la survie dans `_etat.plantes` (plus dans `_poses`, désormais conditionnel) ; `get_tree()` null-safe (`_ready` détaché des tests ne plante plus) ; fonction morte `_plante_par_id` retirée. Verts : test_plante, test_couvert_carte, test_cache_vivantes, test_arbre_massif.
- 9888199 — RENDU DU TERRAIN LOINTAIN REFONDU en MultiMesh PAR FORME + FACE CULLING. `jeu/terrain/rendu_terrain_multimesh.gd` remplace le rendu par tuiles de GridMap (`Proto/terrain_streame.gd`, debranche de `verification.tscn`) : un MultiMeshInstance3D par forme × par tuile ; chaque cube (`BoxMesh`) pose UN QUAD par face EXPOSEE au lieu d'un cube plein de 12 triangles — une face n'est cachee que par un CUBE plein (une rampe/cylindre/sphere, qui ne remplit pas sa cellule, laisse la face visible). Position/orientation par les conversions natives d'un GridMap de reference (`map_to_local`, `get_basis_with_orthogonal_index`, `get_item_mesh_transform`) — jamais calculees a la main. Formes lues dans `bloc.tres` (ajouter une forme = un item, zero ligne ici) ; rampe/cylindre/sphere gardent leur mesh complet. `custom_aabb` serre a la hauteur reelle de la tuile (frustum culling — un AABB haut de toutes les couches ne se cullait jamais). Occlusion culling activee (`project.godot`) : `ArrayOccluder3D` sur le relief emergent (couche > sommet de base) dans le terrain, et sur les canopees d'arbres dans `couvert.gd` (reconstruit seulement quand la population rendue change). LOD par distance (`visibility_range_end`) et taille de tuile 10 (culling plus fin), les deux reglables sur le noeud. Mesure : primitives dessinees 181254 → 41514 (face culling), 82 draw calls. `terrain_visible.gd` (GridMap proche, rayon 15) ne DESSINE plus (`sans_mesh`) — il ne porte QUE la collision qui suit le joueur.
- f9b1e2c — `couvert.gd:_bascule_rendu` throttle : le scan `choses_dans_rayon` ne se relance qu'au tick (`joues > 0`) ou quand l'observateur s'ecarte de `seuil_rescan_metres` (4 m), plus a chaque frame. Meme defaut deja evite ailleurs (tick sorti de la frequence d'images).
- 6273e08 — `bloc.tres` : formes cylindre (id 7) et sphere (id 8), vraies primitives (`CylinderMesh`/`SphereMesh`) avec leurs `CollisionShape`. Doc `jeu/terrain/AJOUTER_UNE_FORME.md` : recette et pieges pour ajouter une forme sans casser l'existant.
- 2026-08-25 — INSPECTEUR RESSOURCES sur terrain dynamique : `manager_proto.gd` expose `quantite_a`/`preleve` (public, O(1), défaut `capacite_case`) et rejoint le groupe `ressources_terrain` ; `InspecteurBloc` + `StockJoueur` + `BarreRessource` ajoutés à `verification.tscn`. La réserve par cellule vit en donnée (défaut + Dict des écarts), sans le scan GridMap statique de `ressources_terrain.gd`. Aucun surcoût par frame : lecture Dict O(1), crédit au clic seul.
- 2026-08-25 — CEINTURE DE CARTE : GridMap de cellules → StaticBody3D + 4 BoxShape3D, sur les trois scènes qui la portaient : `Proto/verification.tscn`, `Proto/proto_terrain.tscn`, `terrain/carte_prototype.tscn`. `jeu/terrain/murs_limite_boite.gd` (`@tool`, quatre boîtes déduites de l'emprise par `faces()` : faces internes à ±`demi_cote·cote`, épaisseur 10 m poussée VERS L'EXTÉRIEUR — la barrière ne bouge pas, seule la face externe recule —, hauteur 22 couches = 44 m). `murs_limite.gd` RETIRÉ DÉFINITIVEMENT (plus aucune référence code). Mesuré sur verification (demi_cote 250) : mémoire de la ceinture 15,7 → 0,68 Mo (~23×), 44088 formes de collision → 4. Verrouillé par `test_ceinture_infranchissable.gd` (barrière 4 côtés, tunneling projectile 100 m/s CCD, jitter, glissement), paramétrable `-- scene=` ; couvre trois bugs Godot loin de l'origine, dont AUCUN ne se manifeste (variance 0, glissement libre) ni sur GridMap avant ni sur boîtes après : #75537 (jitter CharacterBody vs grande StaticBody à ±500 m), #39095 (tunneling corps multi-formes), #69683 (snapping). DETTE : `test_carte_prototype.gd:113-177` vérifie encore la ceinture EN GridMap (early-return si pas un GridMap) → obsolète depuis ce refactor, à réécrire en contrôle fonctionnel.
- 2026-08-25 — RENAME `TerrainLointain` → `TerrainStreame`, fichier `terrain_visible_multimesh.gd` → `terrain_streame.gd` : le nom disait « horizon » alors que le système rend le sol streamé AUTOUR du joueur (rayon 120 = 240 m, sans collision). Nœud dans `verification.tscn` et `proto_terrain.tscn`, fichier + uid, preload de `test_ecosysteme.gd`, commentaires de `terrain_visible.gd`, refs docs `PROTOCOLE_MULTIMESH.md` et `METHODE_DIAGNOSTIC_PERF.md`.
- c571a3d — compte de voisins passé en SIGNAL EN ÉCRITURE (incrémental), pas seulement en lecture. Avant : `rafraichir_plante` rescannait `voisinage()` → `choses_dans_rayon()` à chaque foyer (naissance, mort, ET changement de stade). Après : `rafraichir_plante` ne fait plus que l'ombre ; le compte est maintenu par `maj_voisins_naissances` (+1 par naissance sur les voisins, le nouveau-né pose son compte par un scan) et `_maj_voisins_incremental` (−1 par mort), appelés une fois par tick à §8 ; `poser_voisins_initial` scanne une fois à `etat_initial` ; `retirer` fait le −1. Changement de stade = zéro écriture du compteur. `couvert.gd` Peuplement appelle `maj_voisins_naissances` (source unique). Mesuré : requêtes `choses_dans_rayon`/tick 185 → 10, candidats mesurés 13247 → 659, temps tick 28 → 24 ms. Verrouillé par `test_compteur_voisins.gd` (compteur == scan de contrôle après chaque naissance/mort/stade/retirer/séquence longue). Commentaire `vegetation.gd:445` corrigé — il prétendait faussement « AUCUNE requête », il disait signal en lecture mais scan en écriture ; il dit maintenant le vrai.
- c571a3d — cache des vivantes : `etat.plantes` devient la liste toujours-propre (purge immédiate des mortes en §2b via `assign` en place, rejets intégrés après la boucle §7, plus de purge paresseuse à §8). `encore` alias `plantes` directement — L.666 passe de scan O(N) à O(1). §7 refactoré : les rejets s'accumulent dans `nouveaux`, intégrés après la boucle (sinon ils seraient itérés/reproduits le même tick). Verrouillé par `test_cache_vivantes.gd` (aucune morte dans `etat.plantes` après chaque opération). Gain sur `vivantes` : 11.7% → 2.3% au profileur ; sur le temps de tick, dans le bruit (les scans `vivantes` n'étaient pas le goulot — c'était `choses_dans_rayon`, voir entrée du dessus).
- c571a3d — PIÈGE : un commentaire de code peut mentir sur le coût réel. `vegetation.gd:445` affirmait le compte de voisins « porté en signal, AUCUNE requête », alors que la LECTURE seule l'était — l'ÉCRITURE était un scan. La règle « signal, pas question » de la doctrine ne s'appliquait qu'à la moitié. Leçon : tracer l'écriture, pas croire le commentaire. Symptôme : `choses_dans_rayon` à 34% du tick au profileur. Cause : `voisinage().size()` recalculé à chaque foyer. Corrigé (entrée du dessus).
- c571a3d — arbre du couvert monté à 6 stades (enfant/ado/jeune/adulte/vieux/pourri) via `espece.gd` ouvert de 3 à 6 stades optionnels ; silhouette procédurale `maillage_arbre` (CylinderMesh tronc + cône canopée) ; collision proportionnelle au stade (rayon = rayon_collision × stature/stature_max) ; `utilise_ombre` @export défaut false (court-circuite le calcul d'ombre pour une espèce isolée) ; noeud `Peuplement` (`peuplement.gd`) qui pose N plantes déjà à un stade cible, étalé par `budget_par_frame` avec aléa d'apparition, câblé dans `couvert.gd:_consommer_file_peuplement`. Posé dans `jeu/Proto/verification.tscn` sous `Terrain/Couvert`.
- c571a3d — troncs du couvert migrés de StaticBody3D vers PhysicsServer3D pur (RID, aucun nœud d'arbre de scène). `couvert.gd` : shape RID par stade fabriquée au `_ready` et partagée par tous les corps de cette espèce, body RID créé par `_poser_corps` (mode STATIC, layer/mask 1 explicites, `body_set_space(get_world_3d().space)`), free_rid immédiat par `_liberer_corps`, purge finale au `NOTIFICATION_PREDELETE`. Suppression : `_corps_solide`, `_poser_tronc`, `_liberer_tronc`, `_porteur`, `_liberer_porteur`, var `_noeuds`, var `_troncs_actifs`, const `NOM_TRONC`. Gain mesuré : ~3 ms/frame vs ~16 ms/frame pour 2827 corps actifs (banc `banc_collision_serveur.gd`, isolation --sb / --ps). Verrouillé par `banc_migration_tronc.gd` : `body_get_space` rend un RID égal à `world_3d.space` (7a), `intersect_ray` touche le tronc (7b), `body_get_space` après `free_rid` rend un RID invalide (7d). 7c (Frappe.subir_frappe) non applicable — les troncs n'ont ni vie ni méthode subir_frappe, la destruction externe passe par `vegetation.gd:retirer(id)` sur un id data. Commentaire dans le code pour le futur : ajouter `body_attach_object_instance_id` si un raycast doit un jour identifier l'arbre touché.
- c571a3d — méthodologie du chantier collision, à recopier pour tout futur chantier de perf : (1) mesurer avant de trancher entre plusieurs options — banc synthétique dédié avant compromis gameplay ; (2) isoler les mesures dans des runs séparés (arguments CLI --sb/--ps) pour distinguer warm-up moteur vs interférence entre approches ; (3) instrumenter le compte réel d'objets (`_racine.get_child_count()`, `bodies_rid.size()`) plutôt que le compteur générique `PHYSICS_3D_ACTIVE_OBJECTS` qui vaut 0 pour bodies statiques ; (4) copier la signature exacte de chaque méthode PhysicsServer3D depuis la doc officielle avant d'écrire la ligne, jamais de mémoire ; (5) pairer strictement `body_create` → `free_rid` et `shape_create` → `free_rid` au `NOTIFICATION_PREDELETE`, un RID orphelin fuit invisiblement ; (6) `body_set_space(get_world_3d().space)` obligatoire immédiatement après `body_create`, sans quoi le corps existe mais n'est dans aucune simulation, silencieusement.
- c571a3d — culling collision et rendu MMI par distance à l'observateur dans `couvert.gd` : hors du rayon `rayon_collision_metres` (60 m défaut), la ligne MMI est radiée et le corps physique libéré. La donnée continue de vivre dans `vegetation.gd`. Utilise `monde.choses_dans_rayon` (indexé par case, coût suit le rayon pas la population). Sortie du rayon = `_radier` + `_liberer_corps`. Rendu MMI et collision cyclés dans `_bascule_rendu` par tick.
- c571a3d — collision proportionnelle au stade dans `couvert.gd:_preparer_les_rendus` : rayon effectif du cylindre = `rayon_collision × stature_stade / stature_max_espece`. Adulte (stature max) garde `rayon_collision`, enfant à stature 2 m descend à ~0.21 m au lieu de 1.5 m. Élimine l'aberration "arbrisseau qui bloque 3 m de diamètre".
- c571a3d — silhouette arbre stylisée procédurale dans `couvert.gd:maillage_arbre` : `CylinderMesh` builtin Godot pour tronc + cône (top_radius=0) pour canopée, deux surfaces séparées dans un ArrayMesh, deux matériaux (marron `Color(0.35,0.22,0.13)` + couleur de l'espèce). Auto-sélection dans `_preparer_les_rendus` : `rayon_collision > 0` → arbre stylisé, sinon touffe. Aucun @export ajouté sur `espece.gd`, gate arithmétique.
- c571a3d — `espece.gd` ouvert de 3 à 6 stades (stades 4-6 optionnels, ignorés si nom vide OU durée nulle) pour permettre à l'espèce arbre d'exposer les 6 étapes de Yael (enfant/ado/jeune/adulte/vieux/pourri, statures 2/5/9/14/10/7). `champs()` filtre les stades vides pour rester générique. Tests existants intacts : `test_plante.gd`, `test_couvert_carte.gd` continuent avec 3 stades sans changement.
- 2026-08-24 — hook TSCN INTERDIT (bloc F de `on-pre-tool.sh`) retiré sur ordre de Yael. Checks 2 et 3 de `on-stop.sh` (completion sans bash / livraison 3 blocs) aussi retirés. Backups datés dans `~/.claude/hooks/premier-rts/*.bak-20260824-*`. Mémoires correspondantes nettoyées.
- 2026-08-23 — audit `Proto/terrain_visible_multimesh.gd` : masque de visibilité par colonne cale `r_start` sur `r_top` voisin (rang du bit le plus haut), pas sur la contiguïté du masque → faces latérales absentes dès qu'un voisin porte grotte/pont/surplomb, contredit `terrain/carte_terrain.gd:34-38` ; audit seul, aucun correctif appliqué.
- 2026-08-23 — pattern CHUNKS/TUILES pour MultiMesh grande zone : Godot 4 n'a pas de frustum culling par instance (godot-proposals#10669), un MultiMesh unique sur 300 k+ instances vertex-shade tout à chaque frame (mesuré : fps 8 en V1 naïve). Solution éprouvée (plugin Spatial Gardener) = découper l'espace en chunks carrés, un MultiMeshInstance3D par chunk avec `custom_aabb` serré à sa boîte → Godot cull chaque chunk indépendamment via frustum. Recette dans `jeu/PROTOCOLE_MULTIMESH.md`, implémentation dans `jeu/Proto/terrain_visible_multimesh.gd`.
- 2026-08-23 — frise en marche réglée : terrain lointain repasse d'un GridMap dynamique (retarget = reconstruction d'octants, pics 80–115 ms mesurés au profileur) à un `terrain_visible_multimesh.gd` (chunks MultiMeshInstance3D, un mesh unifié par chunk, couleur par instance via `use_colors` + `vertex_color_use_as_albedo`, `custom_aabb` serré au chunk). Balayage taille_chunk mesuré : draw_calls chutent 791→115 sans gain fps → confirme que le volume géométrique est le vrai mur, pas les draw calls. À l'écran, la frise est absente.
- 2026-08-23 — rayon rendu entités découplé de rayon terrain visuel : `manager_proto.rayon_rendu=60` (skins entités), `TerrainLointain.rayon_cellules=120` (240 m sol visible), `Terrain.rayon_cellules=15` (30 m sol physique). Trois rayons indépendants pour trois fonctions : voir loin, marcher, interagir.
- 2026-08-23 — terrain split visuel/physique via deux GridMap frères : `Terrain` (biblio avec collision, rayon 15) + `TerrainLointain` (biblio dépouillée via `set_item_shapes([])`, rayon 120, `rayon_interne` aligné dynamiquement sur Terrain par NodePath). Boot 14,4 s → 1,9 s mesuré (316k corps physiques → 5k). Écart framework documenté dans `jeu/terrain/terrain_visible.gd` (second écart après `scripts/monde.gd:retirer`).
- 2026-08-23 — balles simulées en donnée dans `manager_proto` : `_balles: Array`, `spawn_balle(pos, dir)` appelée depuis `arme_tir.gd`, `_tick_balles` avance et teste collision segment (anti-tunneling) contre carrés en data, purge cible touchée. Peau visuelle `balle_violette.tscn` avec `set_script(null)` pilotée par le manager, cyclée dans rayon_rendu. Aucune logique dépend du rendu.
- 2026-08-23 — collision inter-carrés en donnée via spatial hash (bucket cellule `RAYON_REPOUSSE=0.6 m`) : paires internes + voisins droite/bas sans double-comptage, push-apart horizontal seul (gravité gère Y). Scale O(N·k) tenable N=1000. Ne s'applique pas aux carrés physique-actifs (le RigidBody gère). Particules d'impact code-only (fade+shrink 0,35 s) au hit, exclusion tireur↔balle sur 1 m depuis point de départ.
- 2026-08-23 — chantiers de design tranchés notés dans `jeu/Proto/A_PREVOIR.md` : rayon englobant par entité, buckets par ordre de grandeur pour filtre visibilité, cycle skin différencié petit/géant, cas géant animé évité, décor statique intégré au système sans exception, LOD terrain, cache directionnel absent dans retarget, gestion pop-in téléport.
- 2026-08-23 — patron entités split donnée/rendu documenté dans `jeu/Proto/PATRON_ENTITES.md` : recette pas-à-pas pour ajouter futurs ennemis/ressources sans dupliquer l'infrastructure. Helpers réutilisables (`_gerer_freeze_kinematic`, `_snap_sol_via_carte`, `_sol_present_sous`) + patrons de bascule rendu (data mobile via velocity, data statique). Invariants listés (KINEMATIC obligatoire, signal detruit, pathfinding consulte carte)
- 2026-08-23 — producteur pilote par velocity + freeze conditionnel (patron scalable N=1000) : téléport par frame remplacé par `linear_velocity` en zone safe, `noeud.global_position = data.position` uniquement en zone buffer (freeze KINEMATIC). Évite 60k `set_global_position`/s à l'échelle
- 2026-08-23 — pattern extensible split donnée/rendu dans `manager_proto.gd` : helper `_gerer_freeze_kinematic(rb, data, en_zone_safe)` réutilisable pour toute entité physique. Trois zones (hors safe / safe+sol / safe+timeout+snap). Applicable aux futurs ennemis mobiles avec sync données→nœud chaque frame (patron producteur déjà en place) + `carte_terrain.est_pleine(colonne, couche)` consultée pour éviter pathfinding dans les murs
- 2026-08-23 — split donnée/rendu du terrain (cubes verts sculptés dans `proto_carte.tres`) : vérifié fonctionnel via framework `terrain_visible` + `carte_terrain`. Item `bloc_vert` (id 6) stocké dans `particularites` de la carte, restitué à l'identique après cycle éloignement/retour du joueur. Sculpture persistante entre sessions, aucune régression, aucune intervention du proto nécessaire
- 2026-08-22 — géniteur v2 : copie du géniteur SANS gestation mother cube (`geniteur_v2.gd/.tscn`) ; banc `test_ennemi2 Mother box` bascule sur v2 ; v1 intact sur disque (piste mother cube en stock)
- 2026-08-22 — stocks du géniteur renommés : `perso → privee` (barre violette), `accessible → public` (barre bleue) ; API `stock_public_courant()` + `preleve_stock_public()` ajoutée
- 2026-08-22 — gestation des générateurs passe sur le stock PUBLIC : `gestation_generateur_public.gd` (seuil 15 = 10 % public, coût 15, max 8 vivants, durée 60 s) ; l'ancien gestation_energie reste inutilisé mais sur disque
- 2026-08-22 — stockeur ajouté : `stockeur.gd/.tscn` cube orange 1 m, vie 3, 20 min de vie, capacité 100 nourritures ; `gestation_stockeur.gd` sur stock PRIVÉ (seuil 30 = 20 %, coût 30, max 4, durée 60 s) ; chasse carrés rouges dans 30 m, patrouille vers géniteur au-delà de 50 m, suit à 10 m quand plein
- 2026-08-22 — cadavre de générateur PÉRISSABLE : Timer 300 s (5 min) au `_mourir()` déclenche `_decomposer()` (retrait monde + queue_free), fenêtre courte de cannibalisation
- 2026-08-22 — carré rouge PÉRISSABLE : Timer 600 s (10 min) au `_ready()` déclenche `_mourir()`, empêche accumulation infinie
- 2026-08-22 — fix boucle silencieuse « générateur mange cadavre plein » : dans `_faire_colle`, source invalide + `_cout_paye_pour_ce_cycle = true` → transition ETAT_POND (ponte anticipée qui reset matiere_cumulee) au lieu d'ETAT_ATTENTE ; sans ce shortcut, prochain cycle demande reste = 0 → pris = 0 → boucle géniteur↔ATTENTE
- 2026-08-22 — exception collision géniteur↔générateur POSÉE AU `_ready()` du générateur (pas seulement au `_mourir()` cadavre) ; sans elle, RigidBody masse 5 pousse RigidBody masse 30 non-freeze au contact. Même patron dans `stockeur.gd:_ready` avec groupes `geniteur/generateur_energie/ressource/stockeur/protogeniteur`
- 2026-08-22 — accélérateur `controle_vitesse.gd` : touches `+` / `-` (×2 / ÷2), `0` reset, plafond ×10, plancher ×0.25, OSD Label jaune haut-gauche
- 2026-08-22 — protogéniteur ÉCRIT mais NON BRANCHÉ : `protogeniteur.gd/.tscn` (cube bleu 3×3×3, auto-produit 2/s de stock_public, suit géniteur à 60 m) + `gestation_protogeniteur.gd` (seuil 120 = 80 % privé, coût 120, max 3, durée 240 s = 4 min) ; le nœud n'est pas dans `geniteur_v2.tscn`, à cabler quand la boucle vers guerrier sera fermée
- d09a008 — écosystème ennemi, bugs latents fermés : `monde.deplacer` appelé par toute entité mouvante (géniteur, mother cube, carré rouge), `MondePartage` posé au banc `test_ennemi2 Mother box` (sans lui perception morte), collision géniteur↔cadavre exclue, perception mother cube et générateur throttlées à 2/s, barre de vie mother cube compensée du scale, propriété `rayon` publiée sur l'entité
- 8818c58 — cadavre-mange : le générateur enrolé perçoit la source la plus proche parmi géniteur et cadavres (filtre `stock_puisable > 0`), cumule matière sur plusieurs sources jusqu'à `cout_prelevement`
- 8d69362 — mother cube perception + mange + croissance : vue 30 m sur `nourriture > 0`, une frappe par seconde au contact, scale lerp base → 70 m (gain 5 % décroissant avec la taille), vitesse lerp 10 → 2,5 m/s ; géniteur devient double-stock (`_stock_perso` 150 + `_stock_accessible` 150, extraction 50/50, barre violette visible)
- a3b3337 — banc `test_ennemi2 Mother box` : générateur enrolé marche vers le géniteur, prélève 10 stock au contact, pond un carré rouge derrière lui toutes les 60 s ; premier morceau de la mother cube (3 vies, inscrit au monde)
- 1215c83 — générateur d'énergie à deux phases : 3 vies vivant → cadavre 7 vies (mesh terni, freeze, groupe `ressource`, inscrit au monde avec `stock_puisable = stock_cadavre_initial`) → `queue_free` à 0
- b44cfb4 — figeage géniteur fermé : `_choisir_cible` filtre distance ≥ 4 m et écart vertical ≤ 5 m, exclut l'emprise 3×3 (la case sur laquelle il vient d'arriver n'est plus une cible valide)
- c797e78 — générateur d'énergie RigidBody3D amorti (masse 5, damping 2/2, `lock_rotation`) ; gestation en couronne libre autour du géniteur (essais sur 8 angles avec décalage random, rayon 6-8 m) → géniteur cherche nouvelle cible en cas d'échec
- 2140f0a — géniteur : extraction bloquée tant qu'il n'est pas au sol (garde `HAUTEUR_MAX_AU_SOL = 3.5 m`) ; banc de gestation générateur d'énergie enfant (seuil 20, gestation 20 s, coût 20, max vivants 4)
- bbab9b6 — BANC TEST_ENNEMI complet : gisement (500 métal, se détruit à zéro),
  transporteurs qui prospectent (perception+saillance, vision 5 m, marche
  aléatoire, cognent, rapportent), cube violet (vie 50, stock 200 max) qui se
  reproduit à 30 métal, transporteur qui cherche un autre cube quand sa mère est
  pleine, mode combat DÉCLENCHÉ à la frappe et PERSISTANT jusqu'à la naissance
  du soldat (aucun timer), signal aux voisins dans 15 m, soldat rouge (20 vie,
  vitesse 3, dégâts 10) territorial (rayon 10 m du cube parent), mémoire de
  cible via `scripts/lien_personnel.gd` du framework (magnitude 1.0, décroissance
  0.4/s, plancher 0.05 → ~3 s de traque après perte de vue), joueur (100 vie,
  barre HUD 2D, reload de scène à zéro). Composant `PresenceDansMonde`
  générique. Framework composé partout, rien inventé sur les mécaniques.
- LOGBOOK.md : le mécanisme qui nommera au joueur ce que le système produit,
  décide les 4 conditions (rare, composé, conséquent, nommable) et écarte deux
  fausses pistes (IA narrateur, journal joueur). Rien d'implémenté encore
- `jeu/Ennemie/` et `jeu/terrain/test_ennemi.tscn` déplacés dans
  `jeu/Outil de jeu/` (regroupement du banc), tous les paths mis à jour dans les
  13 fichiers concernés. Vérifié : la scène charge, ses 14 nœuds sont là
- LE RAFRAICHISSEMENT DU TERRAIN EN JEU S'ETALE SUR PLUSIEURS IMAGES.
  `terrain_visible.gd` posait et effaçait toute la couronne d'un seuil franchi
  en un seul appel synchrone — MESURÉ à 12,5 ms pour 796 colonnes au rayon et
  au pas de jeu (rayon 50, pas 4), soit les trois quarts d'une image à 60
  i/s, à CHAQUE fois que le joueur avance de huit mètres : le freeze régulier
  en marchant. `_retargeter`/`_avancer_file` mettent deux files (`_a_poser`,
  `_a_effacer`) à jour sans jamais les vider ni les recréer — un demi-tour
  avant la fin d'un étalement annule le travail en attente au lieu de le
  refaire — et `_process` n'en draine que `colonnes_par_image` (120, sous
  2 ms) par image. `rafraichir()` reste inchangée, synchrone, verrouillée par
  les tests existants ; c'est elle qui pose le tout premier affichage
- L'ARCHIVISTE MANQUAIT DANS `carte_100km2.tscn` : aucun noeud ne portait
  `archiviste.gd`, donc rien de ce qui était sculpté ne s'écrivait jamais sur
  le disque, quel que soit le temps passé — seul `Ctrl+S` de la scène
  transportait quoi que ce soit, et de façon coûteuse (voir plus bas). Nœud
  ajouté, cablé sur `carte_100km2.tres`
- LA MAQUETTE N'A PLUS DE RELIEF PAR DEFAUT : `relief` (faux par defaut) pose
  chaque echantillon au sommet par defaut de la carte, quelle que soit la
  sculpture reelle. Personne ne marche sur la maquette, elle sert a s'orienter,
  pas a previsualiser un denivele. Avant ce drapeau, un ecart de quelques
  couches sur une carte presque plate s'etirait sur toute la gamme de couleur
  et se peignait en blanc pur, comme un sommet. `etendue_minimale` (plancher
  d'ecart avant d'atteindre la teinte du haut) reste pour le jour ou `relief`
  repasse a vrai
- 4c1116c — LE CURSEUR CHARGE ENCORE APRES REOUVERTURE : `fenetre_chargee`
  redevient exporte ; la protection contre le creusement automatique n'est plus
  le drapeau mais `_colonnes_chargees`, transmis à `enregistrer_ce_qui_est_pose`
  pour n'effacer que ce qu'on sait avoir charge. Corrige l'effet de bord de
  9500437 : tirer le repere ne chargeait plus rien apres reouverture de la
  scene, sans aucune erreur pour le dire
- 2026-08-20 — CARNET DE JEU : `jeu/CARNET_DE_JEU.md`, l'index de ce que le jeu
  sait faire — les quatre couches, les scènes lançables, les cinq domaines, les
  leviers de réglage, ce qui est écrit sans être appelé, et où se prend chaque
  décision
- e1371d7 — CE QUE LA SCÈNE PORTE EST REPRIS AU LANCEMENT. `terrain_visible`
  effaçait le GridMap sans le lire : tout ce qui n'avait pas transité par
  l'éditeur était perdu, et ce transit tenait à quatre conditions dont aucune ne
  se signale quand elle manque. Il PREND, il écrit dans la carte, PUIS il
  efface. Sculpter sans avoir chargé de fenêtre s'enregistre aussi
- 4b09b41 — UNE SEULE COUCHE ÉCRIT LE MONDE : `jeu/monde/registre.gd` porte
  « ai-je changé ? », `archiviste.gd` porte « alors je t'écris ». Ajouter une
  sorte de donnée au monde ne demande aucune ligne d'écriture — voir
  MANUEL_CARTE.md
- 21393bb — LA CARTE EST UN VOLUME : chaque colonne porte le MASQUE de ses
  couches pleines, pas sa hauteur. Grottes, ponts, surplombs et niveaux séparés
  deviennent représentables, ce dont dépend tout le terrain destructible
- 5f41a86 — ENREGISTRER CONSERVE CE QUI EST SCULPTÉ HORS DES COLONNES CHARGÉES.
  La garde de a054506 bloquait toute colonne non chargée, y compris celles que
  la grille PORTE : le bouton creusait avant, il oubliait après. Elle ne
  s'applique plus qu'aux colonnes absentes de la grille. Mode d'emploi et index
  du terrain : `jeu/terrain/MANUEL_CARTE.md`
- a054506 — ENREGISTRER NE CREUSE PLUS CE QUI N'A JAMAIS ÉTÉ CHARGÉ. Le
  chargement retient les colonnes qu'il a réellement traitées ; l'enregistrement
  n'écrit que celles-là. Une colonne absente du GridMap comptait comme VIDE, et
  « absente » avait deux causes que rien ne distinguait — creusée par le
  sculpteur, ou jamais chargée. Voir PIÈGES
- e39ef42 — CARTE DE 100 km² : `carte_terrain.gd` porte l'emprise et le sommet
  de chaque colonne, sans nœud ni GridMap ; vierge elle pèse 185 octets pour
  25 millions de colonnes, contre 16,5 octets par cellule pour un GridMap plein.
  `terrain_visible.gd` ne rend qu'un disque autour de l'observateur — traverser
  9,6 km laisse 19 747 cellules, du premier au dernier pas. `outil_fenetre.gd`
  sculpte par fenêtre de 600 m, posée LÀ OÙ ELLE EST sur la carte, et déplacer
  le curseur enregistre la zone quittée avant de rendre la suivante ;
  `maquette.gd` montre les 100 km² d'un coup en ne relisant que ce qui est
  sculpté. `jeu/objets/objets_visibles.gd` fait basculer un objet de donnée à
  nœud près de l'observateur : 10 000 objets semés, 5 nœuds vivants au plus.
  Chaque carte porte son emprise, ce qui ferme le premier point EN COURS

- 2026-08-19 — DISTANCE DE RENDU PAR ESPÈCE : `espece.gd` porte un
  `distance_rendu` que `couvert.gd` pose en `visibility_range_end` sur CHAQUE
  `GeometryInstance3D` du corps instancié — un `.glb` est un `Node3D` qui en
  porte plusieurs plus bas, la poser sur la racine ne toucherait rien. Godot
  cesse de dessiner au-delà et c'est la CAMÉRA qui décide : aucun objet n'a
  besoin de savoir où est le joueur, donc rien à remplir sur mille types. À zéro
  rien n'est écrit — une scène existante ne change pas de comportement. Elle ne
  libère AUCUN nœud et ne touche PAS le tronc solide : un arbre qu'on ne voit
  plus barre toujours le passage. Mesuré à côté : un nœud de plante pèse 5,1 Ko
  (herbe) à 9,6 Ko (arbre), et `visibility_range_end` n'en rend pas un octet
- 2026-08-19 — GRANDE CARTE 300×300 : `jeu/terrain/grande_carte.tscn`, scène
  NEUVE — 630 000 cellules d'emprise plus 26 488 de ceinture, 10,7 Mo. Aucun
  outil neuf : `DEMI_COTE` passe de 64 à 150 et les quatre outils s'ouvrent d'un
  coup, c'est la seule déclaration de l'emprise. Deux outils gagnent
  `vers=<chemin>` — sans lui, une carte d'une autre taille ne s'obtient qu'en
  écrasant celle qui existe. Et `generer_carte.gd` RELIT la bibliothèque quand
  elle est sur le disque au lieu de la réécrire : il ne sait construire qu'un
  item, `bloc.tres` en porte trois, et les écraser aurait vidé toute cellule
  portant `limite` ou `rampe` — dans `carte.tscn` comme ailleurs. Mesuré :
  chargement 710 ms, instanciation 508 ms, relevé 217 ms pour 91 204 colonnes,
  contre 306/105/40 et 16 900 sur l'ancienne. Coût de démarrage, jamais de tick
- 2026-08-19 — VISÉE À LA SOURIS : le déplacement horizontal fait pivoter le
  CORPS, le vertical incline les YEUX SEULS — une capsule inclinée glisse sur le
  terrain au lieu de s'y tenir. L'inclinaison s'accumule (une souris rend un
  déplacement, jamais une position) et reste sous le quart de tour, sinon
  l'image se retourne et le lacet part à l'envers de ce que le joueur voit. Le
  curseur se prend au PREMIER CLIC et jamais au démarrage — capturé d'office il
  est pris avant qu'on ait rien demandé, à chaque lancement ; Échap le rend.
  Quatre fonctions statiques de plus, verrouillées sans souris ni moteur physique
- 1a764b4 — PERSONNAGE ARPENTEUR : `jeu/unites/personnage.tscn`, une capsule d'un
  mètre — une demi-cellule, et c'est ce rapport qui donne l'échelle à tout le
  reste. Haut/bas avancent, gauche/droite TOURNENT ; sans souris, tourner est le
  seul moyen de regarder ailleurs. Le calcul sort de `_physics_process` en
  fonctions statiques, verrouillées sans clavier ni moteur physique
- 45b3a4a — TRONC SOLIDE : une espèce qui déclare un `rayon_collision` reçoit un
  cylindre de ce rayon, haut comme la stature de son stade, échangé avec le
  modèle. C'est le fût, pas l'arbre — on circule sous la canopée. À rayon nul
  aucun corps n'est posé, et c'est le défaut : l'herbe reste traversable sans
  qu'une ligne ne la nomme
- 8818c26 — DISPERSION ET DENSITÉ PAR ESPÈCE : où tombent les rejets et combien
  de voisines une plante supporte étaient communs, si bien qu'un tapis d'herbe
  serré aurait fait des arbres serrés. Le rayon de comptage reste commun — il
  choisit le rayon de rafraîchissement de tout le couvert
- 7b715cb — REQUETE SPATIALE corrigee dans `scripts/monde.gd` : les choses sont
  rangees par case, a plusieurs resolutions nees a la demande, et une requete ne
  lit plus que les cases que son rayon touche. Mesure : 512 076 tests de distance
  par tick a 1 000 plantes, tombes a ~7 100. Le contrat change — une chose qui
  bouge le declare par `deplacer()`. Mesures completes :
  `jeu/plantes/MESURES_COUVERT.md`
- 7b715cb — Premier commit du contenu, et depot distant du jeu :
  `https://github.com/Yenb/jeu-premier-rts`

- 2026-08-18 — Couvert MULTI-ESPÈCES et pression écologique : une RESSOURCE par
  espèce (`jeu/plantes/arbre.tres`, `herbe.tres`, décrites par `espece.gd` et
  `stade.gd`), déclarées sur le nœud Couvert et réglées à l'inspecteur —
  sélecteur de fichier compris pour les modèles ; un semis les réclame par son
  champ `Type`. Trois contraintes distinctes — la densité borne le
  nombre, l'OMBRE PAR STATURE tranche qui l'emporte, la TROUÉE décide qui peut
  s'installer où. Une herbe basse n'ombrage jamais un arbre et se fige sous
  n'importe lequel ; un rejet d'arbre renonce dans un tapis d'herbe dense, un
  rejet d'herbe non. Plafond de couche par espèce, et touffe fabriquée à
  l'exécution pour une espèce sans modèle
- 2026-08-18 — SUCCESSION : la mort ne regarde plus la lumière. Deux horloges —
  l'âge de CROISSANCE se fige à l'ombre et commande le stade, l'âge RÉEL avance
  toujours et commande la fin. Les confondre rendait les dominées IMMORTELLES
  (mesuré : une herbe sous un arbre encore vivante dix vies plus tard, âge zéro) :
  elles occupaient leur colonne et le plafond de densité pour toujours, et la
  forêt ne pouvait plus reprendre un sous-bois qui ne se vidait jamais. Mesuré
  après : à réglages identiques, les arbres passent de 0 à 4, et de 0 à 30 en
  desserrant leur trouée — la prairie s'installe vite, la forêt la remplace
  lentement, et une trouée d'arbre mort se recouvre d'herbe avant de redevenir
  forêt
- 2026-08-18 — UN SEMIS PAR ESPÈCE : `jeu/plantes/arbre.tscn` et `herbe.tscn`,
  scènes dérivées de `plante.tscn`, chacune avec son espèce déjà renseignée et son
  propre carré coloré. Le game designer choisit ce qu'il plante en choisissant la
  scène, plus en tapant un nom — une faute de frappe retombait en silence sur
  l'espèce par défaut. Les RÉGLAGES restent sur le nœud d'espèce sous le Couvert,
  un seul endroit par espèce : poser cent semis ne fait pas cent copies d'une
  durée à tenir d'accord
- 2026-08-18 — Couvert OPTIMISÉ d'un facteur ~4000 : le tick passe de la
  fréquence d'images à un pas FIXE de 2 s (mesuré : les éclaircies durent 9 s en
  médiane, un pas plus grand les raterait et ferait sous-pousser les plantes en
  concurrence), et l'ombre devient une valeur PORTÉE par chaque plante, relue
  seulement autour des trois événements qui peuvent la changer — mort, changement
  de stade, naissance. Mesuré : 1,1 ombre relue par tick au lieu de toutes.
  `vegetation.gd:retirer` est le geste qui ôte une plante du dehors en prévenant
  son voisinage ; `test_plante.gd` compare à chaque tick l'ombre portée à l'ombre
  recalculée entièrement. Le compte de voisins est porté de la même façon et
  vérifié par le même test — `peut_pousser` ne fait plus aucune requête
- 2026-08-18 — PRÉCHAUFFAGE du couvert : `couvert.gd` exporte un nombre de ticks
  joués avant la première image, rendu compris ; le joueur arrive sur une
  végétation déjà vécue au lieu d'un terrain nu. Aucune mécanique neuve — c'est la
  fonction de tick existante appelée en boucle. `test_plante.gd` verrouille que
  N ticks d'avance plus M normaux rendent le même état que N+M normaux, ce qui
  prouve surtout que `_process` ne simule rien de son côté. Le pas de temps est
  DÉCOUPÉ en tranches déduites des durées les plus courtes (`pas_maximal`) :
  sans ça un pas de 30 s rendait trois fois plus d'herbe qu'un pas de 1 s et
  sautait des stades — accélérer changeait le monde. Le premier test comparait
  N + M ticks à N+M ticks au MÊME pas : il prouvait une tautologie
- 2026-08-18 — Couvert VÉGÉTAL, premier gameplay du jeu : `jeu/plantes/` — des
  graines posées à la main qui traversent trois stades, changent de modèle 3D à
  chacun, déposent une graine ramassable au sol, se reproduisent au seul stade
  mature et meurent de vieillesse ; une plante dominée par une voisine plus
  avancée se fige et repart quand celle-ci meurt ; aucune mécanique écrite,
  `vegetation.gd`
  compose `senescence.gd` (dont le facteur nul fige un dominé), `stade.gd`,
  `seuil_etat.gd`, `gestation.gd` et
  `monde.gd` sur des catalogues LOCAUX au format des partagés, et
  `surface_terrain.gd` traduit le GridMap en cases une seule fois. Tous les
  réglages sont exportés par `couvert.gd` et surchargent `vegetation.json` sans
  que la simulation connaisse le nœud ; verrouillé par
  `jeu/plantes/test_plante.gd`, qui refuse aussi que l'inspecteur et le fichier
  divergent
- 2026-08-17 — Bloc RAMPE : `jeu/terrain/bloc.tres` porte un troisième item, un
  prisme triangulaire de 2 m plus sombre que le bloc plein, avec une
  ConvexPolygonShape3D qui épouse ses six sommets ; verrouillé par
  `jeu/terrain/test_rampe.gd`, qui mesure la pente au rayon sur une rampe posée
  et exige que le demi-tour du GridMap l'inverse
- 2026-08-17 — Limite de carte INVISIBLE : `jeu/terrain/generer_murs.gd`, script
  headless relançable qui pose 22 couches de murs sur les quatre bords, une
  cellule au-delà de l'emprise sculptable, avec l'item qui collisionne sans se
  rendre ; il relit la scène pour prouver que la sculpture est intacte
- 2026-08-17 — Terrain solide : `jeu/terrain/bloc.tres` porte deux items, le
  bloc visible et la limite sans maillage, tous deux avec une BoxShape3D de 2 m
  que le GridMap applique à toutes ses cellules d'un coup ; verrouillé par
  `jeu/terrain/test_collision_terrain.gd`, un témoin qui tombe et un témoin
  lancé vers le bord
- 2026-08-17 — Philosophie de facturation, personnalisation des unités, races
  comme pente et asymétrie des cartes documentées : `jeu/GAME_DESIGN.md`
- 2026-08-17 — Mécaniques du terrain destructible documentées (conservation
  des masses, cohésion par matériau, fissure puis effondrement, étayage) :
  `jeu/GAME_DESIGN.md` § Terrain destructible
- 2026-08-17 — Remplissage des contours : `jeu/terrain/outil_remplissage.gd`,
  script `@tool` qui lit une couche et comble les zones qu'elle enferme ;
  gestes partagés des outils dans `jeu/terrain/terrain_commun.gd`
- 2026-08-17 — Sculpture en masse : `jeu/terrain/outil_sculpture.gd`, script
  `@tool` qui remplit ou creuse une boîte de cellules depuis l'inspecteur
- 2026-08-16 — Terrain sculptable : GridMap de cubes de 2 m centré sur
  l'origine, bloc plein de 128×128×7 couches, `jeu/terrain/` — scène
  principale du projet
- 2026-08-16 — Création de `jeu/GAME_DESIGN.md`, principes fondateurs posés
- 2026-08-16 — Création du `CLAUDE.md` et du `SUIVI.md` du jeu
- 2026-08-16 — Architecture LLM décidée : micro-modèle stratégie + micro-modèle
  discussion (plus tard) + agents mémoire côté code
- 2026-08-16 — Modèle choisi : Llama 3.2 3B via Ollama
- 2026-08-16 — Connexion LLM prouvée (`banc_llm_connexion.gd`, réponse reçue)

## EN COURS

- Push du tampon MultiMesh via `RenderingServer.multimesh_set_buffer(mm.get_rid(), buffer)` au lieu de `mm.buffer = buffer` (setter de noeud). Aux 5 sites : `creer_pool`/`spawn`/`retirer`/`pousser_buffer` cote peuplement, et `_physics_process` cote banc. Comportement identique, gain marginal (evite l'intermediaire du setter).
- `pas_simple_lot` aligne sur `physique_et_buffer` : `floori()` + precalcul `inv_cote = 1.0/cote` et `trois_sur_cote = 3.0/cote`, aux 3 lectures de sol. Perf-neutre (hors chemin chaud, mais evite la divergence avec la copie du banc).
- HOT PATH ROUND 11 (revise) : physique + buffer fusionnes en UNE passe via `Banc.physique_et_buffer(cols, buffer, count, gravite, delta, carte)`, l'intention (errance) reste sa propre passe (deviendra couche IA hors tick dans le vrai jeu). Optim errance : `desiree[i]` reecrit UNIQUEMENT a l'expiration de l'horloge -- `_remplir_colonnes_depuis_individus` initialise `desiree = direction * vitesse` au spawn pour preserver l'invariant frame 1. Reglages : `floori()` au lieu de `int(floor())`, precalcul `inv_cote = 1.0/cote` et `trois_sur_cote = 3.0/cote`. `pas_simple_lot` inchange (commentaire MIROIR aux deux endroits). Verrouille par `scripts/test_tick_fusionne.gd` : parite bit-a-bit 3-passes vs 2-passes, 200 agents x 30 frames.
- HOT PATH ROUND 9 : `_cache_sommet` (Dict) converti en `_table_sommet` (`PackedFloat32Array` de taille `(2·demi_cote)² · 9`, NAN = case non calculee). Index arithmetique `lin*9 + ix + iz*3`, `lin = (cx+demi_cote) + (cz+demi_cote)*(2*demi_cote)`. `marquer_sale` fait `fill(NAN)`, setter sur `demi_cote` reallouee. Accesseur `table_sommet()` expose la table en lecture. `pas_simple_lot` lit la table en INLINE pour ses 3 requetes de sol (`sommet_sous` seulement en repli sur miss/plafonne). Couplage index carte<->mouvement commente aux deux sites. Test `_juger_demi_cote_realloue` ajoute.
- HOT PATH ROUND 8 (jeu) : les colonnes paralleles vivent dans `peuplement.pool.colonnes` (nom -> PackedArray typé), declarees par le consommateur, alignees au spawn (append defaut) et au retrait (swap-remove sur chaque colonne). `Mouvement.pas_simple_lot(cols, count, gravite, delta, carte)` fait une passe unique sur ces colonnes. Peuplement reste agnostique (aucun nom, aucune lecture). Piege CoW tenu partout. Verrouille par `scripts/test_peuplement_colonnes.gd` (alignement apres retrait du milieu) et `scripts/test_pas_simple_lot.gd` (parite bit-a-bit vs `pas_simple` sur 10 frames, 3 agents).
- HOT PATH ROUND 8 : tick en passe unique `Mouvement.pas_simple_lot(state Dict, gravite, delta, carte)` sur PackedArrays paralleles (`positions`/`velocites`/`desirees`/`au_sols`) ; le banc construit `_etat_mouvement` au `_fabriquer_lot` et n'accede plus a `proprietes` ni n'appelle `pas_simple` par agent dans le hot loop. Piege CoW tenu par depack en tete / repack en queue (Packed*Array passe par valeur). Ordre fixe -- ce banc ne spawn/retire pas pendant le run.
- HOT PATH ROUND 7 : transforms MultiMesh ecrites dans un `PackedFloat32Array` partage cote `Peuplement.creer_pool` (`pool.buffer`, layout `TRANSFORM_3D` : 12 floats/slot, `[xx,xy,xz,ox,yx,yy,yz,oy,zx,zy,zz,oz]`). Le banc ecrit seulement les 3 floats d'origine par agent dans la boucle puis pousse le tampon UNE FOIS au `mm.buffer` en fin de `_physics_process`. `spawn`/`retirer` posent la base identite / vident le slot dans le meme tampon. `pousser_buffer(pool)` disponible pour d'autres consommateurs. Piege CoW tenu : `pool.buffer` reassigne apres chaque mutation locale.
- HOT PATH ROUND 6 : `_cache_sommet` dans `carte_terrain.gd` -- cle `Vector3i(cx, cz, ix+iz*3)`, valeur = hauteur reelle du sommet de la sous-cellule. Lu par `sommet` et `sommet_sous` en tete. Vide par `marquer_sale()` (surcharge, `super.marquer_sale()` + `clear`). Exclusions : profil `_hauteur_profil` (surface continue), sommet_sous plafonne (y_max coupe le vrai sommet). Verrouille par `jeu/terrain/test_cache_sommet.gd` : plat, sculpte (invalidation), rampe (continuite), surplomb (garde y_max).
- HOT PATH ROUND 5b : errance rangee dans `individu.proprietes` (`errance_direction`, `errance_cap_horloge`) au lieu d'un dict membre `_errance` indexe par id String -- fin du hash de id par frame et de la fuite latente au retrait. Determinisme RNG preserve (meme ordre de tirage : direction puis horloge, au spawn).
- HOT PATH ROUND 5 : `monde.deplacer` coupe cote banc (index spatial non lu par ce banc -- `pas_simple` recoit `null`). Boucle du banc en `for individu in individus`, plus de `range()`. Dans `sommet` / `sommet_sous` : boucles `for iy in range(2,-1,-1)` remplacees par `while` decroissant, et fast-path `_masques_sous_cube.is_empty()` qui court-circuite le `dict.get` par couche.
- HOT PATH ROUND 4 : `_hauteur_profil` n'est plus appele sur cellule sans particularite -- garde inline `if masque_sc == PLEIN and particularites.has(cellule)` dans `sommet` et `sommet_sous`. Terrain plat = 0 appel.
- HOT PATH ROUND 3 : `masque`, `rang_le_plus_haut`, `item_de` inlinés dans `sommet` / `sommet_sous` / `_hauteur_profil` ; `ecrire_transform_index` inliné dans la boucle du banc (`mm` caché hors boucle, `set_instance_transform` en direct). Ces quatre noms doivent disparaître du top profiler pour la boucle physique.
- OMBRES : À OPTIMISER, JAMAIS À COUPER (décision Yael). Le `DirectionalLight3D`
  en PSSM 4 splits fait rendre chaque objet jusqu'à 5× (compté par « primitives
  dessinées » du moniteur). Optimiser = alléger la géométrie qui projette +
  régler cascades/distance/résolution ; SUPPRIMER l'ombre ou baisser les splits
  en dur est ÉCARTÉ. Lié au chantier rendu terrain/arbres (cubes pleins GridMap
  du sol + `couvert.gd:maillage_arbre` à 64 segments par défaut).
- CANEVAS DE BASE APPLIQUÉ à l'herbe, au lichen et au préchauffeur.
  `manager_herbe.gd` + `manager_lichen.gd` remplacent `cube_herbe.gd` +
  `cube_lichen.gd` en scène active (fichiers cube gardés sur disque pour
  patron cube violet). Le préchauffeur pousse ses brins survivants dans
  le manager via `ajouter_avec_age(pos, age)` au lieu d'instancier des
  Node. Mesuré : 26 nœuds au total dans la scène (au lieu de ~90 000
  avec l'ancien pattern à 22 000+ individus), soit 1 560 dispatches/s
  d'engine au lieu de 5.4 M. Règle non négociable dans CLAUDE.md
  § « Canevas de base des populations massives ». Toute future
  dérogation exige un tableau justificatif chiffré et deux sources
  internet.
- CHANTIER LOCALITÉ SPATIALE FERMÉ pour l'herbe et le lichen. Le
  compteur de voisins passe par un CHAMP SCALAIRE
  (`jeu/Outil de jeu/champ_spatial.gd` + wrappers `champ_herbe.gd`,
  `champ_lichen.gd`) : chaque cube inscrit +1 à sa naissance, retire -1
  à sa mort, et LIT sa case et les 8 adjacentes pour tester la
  saturation. Pattern d'automate cellulaire, éprouvé depuis 40 ans en
  écologie computationnelle. Aucun `get_nodes_in_group`, aucune Area3D,
  aucun scan par tick. Coût par événement : O(1). Coût par lecture :
  O(1) constant (9 cases). Le fichier `prechauffeur_herbe.gd` garde
  son événementiel interne (compteur `voisins` maintenu aux naissances
  et morts dans sa liste de brins), à migrer vers `champ_spatial` le
  jour où il devient un vrai goulot.
- `jeu/plantes/vegetation.gd` EST MAL DIMENSIONNÉ POUR SON BESOIN — indexation
  par colonne GridMap, reconstruction complète du Monde à chaque événement, et
  requêtes spatiales imbriquées dans `rafraichir_autour` (`choses_dans_rayon`
  appelé, puis `ombragee` refait `choses_dans_rayon` pour chaque plante
  trouvée). Le système « marche » parce que le CPU encaisse, pas parce qu'il
  est bien pensé — à N=50 000 individus ou sur mobile, le mur arrive d'un
  coup. Chiffres à N=500 herbes, ~30 événements par tick :

  | Ce que le code FAIT | Coût |
  | --- | --- |
  | Reconstruction Monde (`monde_des_vivantes`) à chaque tick avec ≥1 mort/naissance | ~500 insertions |
  | `colonnes_prises` — balayage complet à chaque tick | ~500 |
  | Production : boucle sur TOUTES les plantes, chacune cherche colonne libre | ~500 × k_anneau |
  | Gestation posée : teste stade+voisins sur TOUTES | ~500 |
  | Gestation avancée : tick sur TOUTES | ~500 |
  | Rejets : pour chaque naissance, `trouee_suffisante` fait `choses_dans_rayon` | ~30 × k |
  | `rafraichir_autour` : 30 foyers × ~15 plantes touchées, ET pour CHACUNE des 15, `ombragee` refait un `choses_dans_rayon` — **requête imbriquée** | **~6 750** |
  | **Total code actuel** | **~10 000 op/tick** |

  | Ce qu'une herbe voudrait FAIRE | Coût |
  | --- | --- |
  | Chaque herbe qui tente de se reproduire (~50/500 par tick) fait UNE requête locale sur ses voisines dans son rayon (k≈30) | ~50 × 30 |
  | **Total logique locale** | **~1 500 op/tick** |

  Facteur ≈ 7× à N=500. Se dégrade avec N (reconstruction linéaire, requêtes
  imbriquées aussi) — à N=2 000 le rapport devient ~20×. La différence
  conceptuelle : le code actuel MAINTIENT un état spatial global pour
  répondre vite à toute question, alors que les herbes ne posent chacune
  qu'UNE question, locale, quand elles la posent. Sur des choses qui bougent
  peu et pondent rarement, maintenir coûte plus cher que recalculer à la
  demande. À restructurer avant tout chantier qui remet l'herbe en jeu

- LA CHAÎNE ÉDITEUR N'EST PARCOURUE PAR AUCUN TEST — voir PIÈGES, « ce qu'un
  banc headless ne voit pas ». Trois défauts s'y sont succédé sans qu'aucun ne
  rougisse
- DEUX FICHIERS DE `carte_prototype.tscn` NE VIENNENT PAS DE CETTE SESSION :
  `semer_objets.gd`, `carte_prototype.tres`. À rattacher à un chantier avant d'y
  écrire — un fichier, un écrivain. (`murs_limite.gd` rattaché puis retiré au
  refactor ceinture du 2026-08-25, voir FAIT.)
- `carte_100km2.tscn` embarque les cellules du GridMap dès qu'on enregistre la
  scène en cours de sculpture — 7,8 Mo par sauvegarde, pour un contenu que la
  carte reconstruit. « vider » avant Ctrl+S le ramène à 3 Ko ; rien ne le force
- LES TRACES DE DIAGNOSTIC sont actives : `journal` exporté sur les outils

- UNE EMPRISE, DEUX CARTES DE TAILLES DIFFÉRENTES — à trancher avant tout
  chantier de terrain. `DEMI_COTE` est un nombre unique et vaut désormais 150,
  alors que `carte.tscn` porte une ceinture à 64 : `test_collision_terrain.gd`
  passe de VERT à ROUGE parce qu'il cherche le mur de l'ancienne carte à la
  nouvelle emprise. Deux issues, aucune bricolable au passage — refaire
  `carte.tscn` à 300×300 et n'en garder qu'une, ou sortir l'emprise du
  générateur pour qu'elle se lise SUR LA SCÈNE, chaque carte portant la sienne
- `jeu/terrain/test_carte.gd` est ROUGE (12 échecs) : il verrouille le compte
  exact de cellules, l'absence de relief, l'emprise stricte et une bibliothèque
  à un seul item — que la carte actuelle dément point par point. À recentrer sur
  ce qui reste invariant : pas de grille, caméra,
  lumière, et chaque item de la bibliothèque porte sa forme de collision
- `jeu/terrain/generer_carte.gd` reconstruirait une bibliothèque à un seul item
  SANS collision : relancé avec « forcer », il rendrait le terrain traversable
  et effacerait la limite de carte, en silence

## DÉCISIONS

- STOCK DU GÉNITEUR : deux stocks nommés PRIVÉE (violet) et PUBLIC (bleu),
  jamais « perso » ni « accessible ». Le stock PRIVÉ finance les
  gestations qui restent proches du géniteur (stockeur, protogéniteur) ;
  le stock PUBLIC finance les générateurs et se puise par eux à distance.
- SEUIL = COÛT sur les gestations enfants du géniteur : le seuil de
  déclenchement d'une gestation est aussi son coût. 10 % pour un
  générateur (15 sur public), 20 % pour un stockeur (30 sur privé),
  80 % pour un protogéniteur (120 sur privé). Une gestation ne se
  déclenche qu'à saturation partielle du stock qui la finance.
- CADAVRE ET CARRÉ ROUGE SONT ÉPHÉMÈRES. Sinon la cannibalisation
  intra-espèce nourrit la colonie même quand le joueur en tue —
  transformant chaque kill du joueur en neutre pour la colonie. Le
  pourrissement (5 min cadavre / 10 min carré rouge) préserve la valeur
  tactique de l'attaque.
- LE STOCKEUR EST UN PRÉ-CÂBLAGE : sans consommateur final il empile
  100 nourritures qui ne servent à rien encore. Le CONSOMMATEUR PRÉVU
  est le GUERRIER (puise stockeur, va attaquer le joueur). Le stockeur
  est posé avant le guerrier pour que la chaîne de production existe
  déjà quand on cablera le guerrier.
- LE PROTOGÉNITEUR EST EN ATTENTE de la fermeture du cycle par le
  guerrier — sans consommateur final, empiler un producteur
  supplémentaire (auto-produit énergie, suit géniteur à 60 m) ne révèle
  rien. Les scripts sont écrits, le nœud n'est pas branché dans la scène.
- PHILOSOPHIE DE DEV : le projet appartient au genre SIMULATION
  ÉMERGENTE (Dwarf Fortress, RimWorld). Les systèmes se construisent
  AVANT que le gameplay se stabilise ; le gameplay ÉMERGE de leurs
  interactions. Pas de playtest à chaque itération unitaire, plutôt
  itération sur les systèmes puis observation périodique de ce qui sort.

- TOUT EST DONNÉE ; LE RENDU ET LA COLLISION SONT UNE COUCHE TEMPORAIRE. Vaut
  pour TOUT objet à venir, pas seulement le terrain. Loin du joueur, un objet
  n'a ni nœud ni corps physique : il est une position et des propriétés, et
  l'altitude du sol sous lui se LIT dans la carte — `carte_terrain.gd:sommet`,
  temps constant, mesuré à 0,66 µs, sans rien de chargé. Près du joueur il
  devient un nœud avec collision, posé à cette même altitude ; quand le joueur
  s'éloigne le nœud est libéré et la donnée reste. La simulation ne dépend
  d'aucune des deux couches et ne s'arrête jamais. `terrain_visible.gd`
  applique déjà exactement ça au terrain — traverser 10 km y laisse le compte
  de cellules identique au premier pas.
  CHARGER LA COLLISION PARTOUT EST ÉCARTÉ : c'est revenir aux 175 millions de
  cellules que toute cette architecture existe pour éviter.
  DEUX PIÈGES À TENIR LE JOUR OÙ UN OBJET BASCULE. La hauteur portée par la
  donnée et le sol rendu viennent de la MÊME source, sinon l'objet apparaît
  enfoncé ou en l'air. Et un objet qui devrait tomber pendant que personne ne
  le regarde n'a AUCUNE physique pour le faire : sa chute se calcule en
  données, ou elle n'a pas lieu — décision de game design, pas de technique.
  CE QUE ÇA COÛTE, ET POURQUOI C'EST TENABLE : le compte de nœuds vaut
  `π·r² × densité`, donc doubler le rayon coûte quatre fois et agrandir la carte
  coûte zéro. À la densité d'herbe mesurée (0,0185 plante/m²) : 23 plantes à
  20 m, 581 à 100 m. Deux millions d'agents portent le même nombre de nœuds que
  deux mille — le seul terme qui suive la population totale est la donnée.
  RIEN N'EST À DÉFAIRE POUR Y ARRIVER : `monde.gd` et `vegetation.gd` sont des
  Dictionary et des fonctions, sans Node ni `_process`. « Tout simulé, rien
  rendu » est l'état de DÉPART. Les couches à nœuds sont `couvert.gd`,
  `terrain_visible.gd` et `objets_visibles.gd` ; le nœud lit la donnée, la
  donnée n'a jamais connaissance du nœud.

- LE NŒUD COÛTE DE LA MÉMOIRE, ET C'EST TOUT. Mesuré sur les formes que
  `couvert.gd` fabrique : `Node3D` seul 1,4 Ko ; + `MeshInstance3D` (une herbe)
  5,1 Ko ; + `StaticBody3D` + `CollisionShape3D` (un arbre) 9,6 Ko. En temps,
  11,7 µs pour fabriquer un arbre — poser mille plantes coûte 12 ms, une fois.
  Donc le mur du rendu est la MÉMOIRE, jamais la fabrication
- `visibility_range_end` CACHE, IL NE LIBÈRE PAS. Propriété de tout
  `GeometryInstance3D`, la caméra décide seule, aucun objet n'a besoin de savoir
  qui est le joueur — c'est la réponse généraliste pour ne pas DESSINER. Mais le
  nœud reste, et ses 9,6 Ko avec lui. Tenir l'échelle demande de SUPPRIMER le
  nœud, ce qui exige de savoir où est l'observateur : par GROUPE
  (`get_first_node_in_group`), jamais un champ à remplir sur chaque type
- OPTIMISER EST UN CRITÈRE PERMANENT, pas un chantier de fin. Les cartes
  grandiront, et ce qui tient à cent objets casse à mille : toute mécanique
  écrite désormais s'évalue AUSSI sur son coût à grande échelle, et se mesure
  avant d'être déclarée tenable. Deux leçons déjà payées, à ne pas repayer — un
  tick calé sur la fréquence d'images faisait soixante évaluations par seconde
  pour des plantes qui changent toutes les vingt-cinq secondes ; et un état
  spatial redemandé à chaque tick découvrait 99,6 % du temps qu'il ne s'était
  rien passé. Les deux se voient en MESURANT, jamais en relisant le code

- Le terrain est un GridMap : un objet d'AFFICHAGE et d'édition, que la
  simulation ne lit pas. Le pont vers les cases-objets qu'exige `design.md` est
  écrit et tient dans un seul fichier — voir `jeu/plantes/surface_terrain.gd`,
  seul du jeu à connaître GridMap. Les cases n'entrent PAS dans le Monde — non
  plus parce que `monde.gd` balaierait tout, il range par case et son coût suit
  le rayon, mais parce qu'y verser le terrain mettrait une case-objet PAR
  COLONNE dans chaque case que le rayon touche : un comptage de plantes paierait
  le terrain de son rayon, où les colonnes dépassent les plantes de plusieurs
  ordres. Le relevé se lit par colonne, en temps constant, sans aucun rayon à
  parcourir. La collision du GridMap n'entame rien :
  elle n'est lue que par le moteur physique de Godot, jamais par un mécanisme
- Le résumé d'état est une photo complète à chaque appel, pas d'historique
  cumulé
- Le modèle de discussion est séparé du modèle de stratégie
- Plan de repli : si la machine du joueur ne tient pas, mêmes modèles sur
  serveur, même code d'appel

## PROCHAINES ÉTAPES

1. GÉNÉRALISER `prechauffeur_herbe.gd` — actuellement il ne préchauffe
   que ses propres graines (Marker3D enfants + N aléatoires autour de
   lui). Utile seul, sans intérêt à côté d'un `semeur.tscn` qui pose déjà
   500 graines réparties : le préchauffeur devrait pouvoir s'aligner sur
   les positions posées par le semeur et faire tourner leur simulation
   avant l'instanciation, plutôt qu'ajouter ses propres graines à côté.
   Fichier gardé sur disque, retiré de la scène en attendant. À faire
   quand on voudra un tapis avec une HISTOIRE (naissances, morts,
   trouées) plutôt qu'un semis uniforme
1. OBJETS EN DONNÉES, NŒUDS PRÈS DU JOUEUR : le mécanisme qui fait basculer un
   objet de donnée à nœud (rendu plus collision) quand le joueur approche, et
   l'inverse quand il s'éloigne. La règle est tranchée — voir DÉCISIONS, « tout
   est donnée » — et le terrain l'applique déjà ; rien ne le fait encore pour
   les objets. Patron à recopier : `couvert.gd`, seule couche à nœuds du jeu
1. Trancher le point ouvert de `jeu/GAME_DESIGN.md` § Terrain destructible :
   chercher si un mécanisme du cœur porte déjà la connexité de voisinage, sinon
   ouvrir le chantier framework
2. Câbler le ramassage des graines par les unités : `vegetation.gd:ramasser` et
   `couvert.gd:retirer_graine` sont posées et testées, personne ne les appelle —
   `consommer.gd` est le mécanisme qui attend, il transfère entre deux choses
3. Second banc LLM avec grammaire GBNF contrainte
4. Carré rouge (joueur) + carré violet (IA) + caméra scrollable
5. Premier Modelfile agent stratégie avec system prompt
6. Boucle complète : état → résumé → modèle → clé → action visible
7. GESTATION MOTHER CUBE MISE EN STOCK — `test_ennemi2 Mother box` pointe
   désormais vers `geniteur_v2.tscn` (copie sans nœud `GestationMother`).
   `geniteur.gd`, `geniteur.tscn` et `gestation_mother_cube.gd` restent
   intacts sur disque, réutilisables. Le gameplay mother cube est une
   piste à reprendre quand la lignée du géniteur v2 sera stabilisée

## PIÈGES DÉJÀ PAYÉS

- AUCUN ENNEMI NE SPAWN, LE CODE N'A RIEN BOUSILLÉ. Symptôme : le jeu tourne,
  aucun ennemi n'apparaît à la zone de spawn. Cause : case `Spawn Ennemis Actif`
  décochée dans l'inspecteur du nœud manager (celui qui porte `manager_proto.gd`),
  groupe **Ennemis**, juste au-dessus de `Intervalle Spawn Ennemi`. Décochée =
  `_tick_spawn_ennemis` early-return, aucun spawn. Règle : ouvrir l'inspecteur,
  recocher la case. Les ennemis déjà présents ne sont pas purgés par la case —
  décocher stoppe l'apparition, pas ce qui est là.
- LE GÉNÉRATEUR POUSSE LE GÉNITEUR AU CONTACT. Symptôme : les 4 générateurs
  s'enfoncent dans le collider du géniteur, le géniteur dérive lentement au
  lieu de rester posé. Cause : RigidBody masse 5 vs RigidBody masse 30
  non-freeze, `distance_contact_geniteur = 4 m` avec collider géniteur 3 m
  de demi-largeur — le check « arrivé » s'évalue par tick et la vélocité
  3 m/s avale les 0,5 m de marge avant que le stop ne s'applique. Règle :
  `add_collision_exception_with(self)` au `_ready()` du générateur — le
  patron existait déjà au `_mourir()` pour le cadavre, il fallait
  simplement l'appliquer aussi à la naissance. Généralisable : toute
  entité amie qui approche le géniteur ou une autre amie doit avoir
  l'exception croisée dès `_ready()`.
- GÉNÉRATEUR MANGE UN CADAVRE PLEIN PUIS RESTE BLOQUÉ EN BOUCLE
  SILENCIEUSE. Symptôme : après avoir vidé un cadavre (stock 10 =
  cout_prelevement 10), le générateur oscille au contact du géniteur sans
  pondre. Cause : `_matiere_cumulee = 10` et `_cout_paye_pour_ce_cycle =
  true` restent tels quels quand la source meurt en COLLE (jamais reset,
  intentionnel pour cumul multi-sources). Cycle suivant : le générateur
  arrive au géniteur avec `reste = cout_prelevement - matiere_cumulee =
  0`, `preleve(0) = 0`, `if pris <= 0: return ATTENTE`. Règle : dans
  `_faire_colle` branche source invalide, si `_cout_paye_pour_ce_cycle`
  est vrai, transition ETAT_POND (ponte anticipée qui reset dans
  `_faire_pond`) au lieu d'ETAT_ATTENTE. Préserve le cumul multi-sources
  quand cout_paye est faux.
- STOCKEUR RESTE PLANTÉ APRÈS AVOIR MANGÉ LOIN DU GÉNITEUR. Symptôme :
  stockeur mange un carré rouge éloigné, ne perçoit plus de nourriture,
  reste immobile indéfiniment ; pendant ce temps le géniteur s'est
  déplacé, les nouveaux carrés rouges sont hors perception. Cause :
  `_faire_cherche_nourriture` immobile si `vus.is_empty()`. Règle :
  `_appliquer_patrouille` qui fait revenir le stockeur vers le géniteur
  au-delà de `rayon_patrouille` (50 m). Le stockeur reste dans la zone
  de production, la perception 30 m suffit à repérer les carrés rouges
  quand il y retourne.
- GODOT FULLSCREEN BORDERLESS IGNORE `ShowWindow SW_MINIMIZE`. Symptôme :
  `IsIconic` retourne true mais la fenêtre reste peinte ; `CopyFromScreen`
  capture Godot quand même. Règle : ne pas dépendre du minimize pour
  isoler visuellement ; demander à l'utilisateur de mettre en arrière-plan
  volontairement si nécessaire.

- TROIS COPIES DE LA MÊME CHOSE, ET UNE SEULE QUE LE JEU LIT. Le GridMap de la
  scène, la carte, le fichier de scène : on sculpte dans le premier, le jeu ne
  lit que la deuxième, et Ctrl+S écrit la troisième. Symptôme : le travail
  disparaît au lancement, trois fois de suite, pour trois raisons différentes.
  Règle : ce qui n'est pas la source de vérité doit être REPRIS avant d'être
  effacé, jamais jeté — et le chemin de reprise ne doit dépendre d'aucune
  condition qui ne se signale pas quand elle manque.
- UN MÉCANISME QUI N'A DE SENS QU'À GRANDE ÉCHELLE NE DOIT PAS CONDITIONNER LE
  RESTE. L'enregistrement exigeait qu'une fenêtre soit chargée — un geste qui ne
  sert que sur une carte de 100 km². Sur 200 m, tout tient à l'écran, personne
  ne le fait, et le travail était perdu sans une erreur.
- ÉCRIRE UNE FENÊTRE ENTIÈRE CREUSE CE QU'ELLE NE PORTE PAS. Symptôme : le
  terrain devient un damier de zones vides, et tout ce qui est sculpté
  disparaît — mesuré à 259 530 colonnes creusées, zéro relief monté. Cause : une
  colonne absente du GridMap compte comme VIDE, et « absente » a deux causes
  qu'il faut distinguer — creusée par le sculpteur, ou jamais chargée. Règle :
  ce qu'un chargement n'a pas traité ne s'écrit pas ; l'ensemble des colonnes
  posées se retient, il ne se déduit pas de l'emprise demandée.
- UN CENTRE RELU APRÈS UNE ATTENTE N'EST PLUS CELUI QU'ON A POSÉ. Une pose
  étalée sur plusieurs frames rend la main entre deux tranches, et ce qui
  pilotait a pu changer pendant. Règle : figer au début ce sur quoi on travaille,
  et ne jamais le relire à la fin pour annoncer ce qu'on a fait. Aucun test ne
  tient ce point — lancé depuis un test, le chargement se termine avant qu'on
  ait pu bouger quoi que ce soit.
- UN TEST QUI VISE UN POINT FIXE FINIT PAR MESURER LE TRAVAIL DU SCULPTEUR. Un
  rayon tiré à l'origine, un plafond qui exige une carte vierge : les deux
  rougissent le jour où la carte est travaillée, sans qu'aucun code n'ait
  changé. Règle : mesurer un invariant du code — coût par colonne sculptée,
  sol sous le personnage — jamais un état du contenu.
- CE QU'UN BANC HEADLESS NE VOIT PAS. `Engine.is_editor_hint()` est faux hors
  éditeur : tout ce qui ne s'exécute que dans l'éditeur — construction d'une
  vue d'outil, script `@tool` sur une ressource — n'est parcouru par aucun test
  lancé en ligne de commande. Règle : le dire AVANT de montrer un test vert, et
  vérifier le mode du script (`Script.is_tool()`) au lieu d'attendre l'erreur
  « placeholder instance ».

Ce que le prochain chantier de couvert doit savoir avant d'écrire une ligne. Un
seul de ces pièges a coûté une demi-session ; tous ont été payés une fois.

- FAUX VERT — un test qui imprime `OK` alors qu'un objet ne s'est pas
  instancié. `Couvert.new()` rend `null` quand le script ne compile pas, et les
  jugements qui en dépendaient étaient SAUTÉS sans un mot. Règle : un objet qui
  ne s'instancie pas ROUGIT, il ne se saute jamais.
- SCRIPT QUI NE REND PAS LA MAIN — un `--headless --script` qui dépasse la
  minute n'est pas lent : il ne compile pas, le `SceneTree` ne quitte jamais.
  Ne pas attendre, lire l'erreur.
- TEST TAUTOLOGIQUE — le préchauffage comparé à lui-même AU MÊME PAS DE TEMPS
  prouvait seulement que l'addition est commutative. Mesuré ensuite : un pas de
  30 s donne TROIS FOIS plus d'herbe qu'un pas fin. Règle : un test
  d'équivalence qui ne fait pas varier ce qu'il prétend rendre indifférent ne
  teste rien. D'où `pas_maximal` et le découpage en tranches.
- MORT BRANCHÉE SUR LA MAUVAISE HORLOGE — voir la ligne FAIT du 2026-08-18.
  Symptôme trompeur : tous les tests verts, et zéro arbre à l'écran.
- CADAVRE QUI FAIT ENCORE DE L'OMBRE — `monde.gd` garde les disparues un tick.
  Toute lecture du monde double-filtre les mortes. Précédent framework :
  `banc_parasites_reproduction.gd`.
- FENÊTRE FERTILE PLUS COURTE QUE L'INTERVALLE — une espèce fertile à 25 s et
  morte à 100 s n'a que 75 s pour semer ; un intervalle de 80 la rend stérile,
  verte à tous les tests de cycle. Le test de reproduction exige une SECONDE
  plante, jamais un cycle qui se déroule bien.
- MODÈLE GLB NON CENTRÉ — les `.glb` sont sortis du modeleur avec l'origine à
  côté (jusqu'à 20 m), les plantes sautaient en grandissant. Invisible aux
  tests : `couvert.gd` n'en avait aucun. Recentrage à l'exécution, et une
  assertion de géométrie dans le test.
- UNE JUSTIFICATION RECOPIÉE PÉRIME EN SILENCE. « Les cases n'entrent pas dans
  le Monde parce que `monde.gd` balaie linéairement » vivait dans quatre
  fichiers ; l'index spatial a rendu la raison fausse partout d'un coup, et rien
  n'a rougi — aucun test ne lit un commentaire. Elle a servi une fois à conclure
  qu'une carte plus grande était hors de portée, sur des chiffres d'avant
  l'index. Règle : une décision cite le MÉCANISME qui la fonde à UN seul
  endroit ; les autres y renvoient. Et un relevé de mesures dit en tête sur quel
  moteur il a été pris — sans quoi il se relit comme un état courant.
- UN COÛT DOCUMENTÉ N'EST PAS UN COÛT CORRIGÉ. `monde.gd` portait en tête
  « COUT LINEAIRE par requete : signalé, jamais contourné en silence », et cette
  phrase est ce qui a laissé passer le défaut des mois : elle transforme un bug
  en état connu et assumé, et se lit comme une décision déjà prise. Règle : un
  coût se corrige, ou se plafonne par un test opposable — jamais par une note.
- AUCUN TEST NE MESURAIT UN COÛT. `test_volume_docs.gd` rougit quand un `.md`
  grossit de quelques milliers d'octets ; rien ne rougissait quand un tick passait
  de 1 ms à 500. Un test de correction ne peut pas voir ça — le résultat EST juste,
  il est seulement ruineux. D'où les compteurs exposés par `monde.gd` (requêtes,
  cases lues, candidats mesurés) : ils existent pour qu'un test puisse poser un
  plafond de coût.
- OPTIMISER SANS MESURER — l'hypothèse « les colonnes prises sont le goulot »
  était fausse : 163 ms → 155 ms. Mesurer d'abord, toujours.
- DEUX ÉCRIVAINS SUR `carte.tscn` — la sauvegarde de l'éditeur ouvert écrase le
  fichier écrit à côté. Quand Godot est ouvert, les valeurs se dictent, elles ne
  s'écrivent pas.
