# BANC DE PEUPLEMENT ARBRE (COQUILLE).
#
# Node de la scene `.tscn` du banc. Rôle strictement limite : monter la
# scene (sol, MultiMesh, lumiere, camera, joueur en mode isole), lire le
# catalogue local JSON, instancier les instances coeur (`Monde`,
# `ChampSaturationPlatGd`, `AttenteSeuil`) et le module de simulation
# (`SimulationArbreGd`), puis a chaque frame gerer la cadence de simulation
# et deleguer le pas a `_sim.avancer(pas)`. Une porte, une commande.
#
# Aucune ligne de logique de simulation ne vit ici. Les colonnes de la
# population, les structures de travail par-tick, la config figee, le
# RNG et les refs coeur vivent tous dans `SimulationArbreGd`. `monde.gd`
# et `champ_saturation_plat.gd` sont appeles UNIQUEMENT depuis le
# module (jamais depuis la coquille) : les instances sont construites
# ici puis injectees a `_sim.attacher(...)`.
#
# @export hote_actif / carte_terrain_ref restent sur la coquille (le
# Node est l'entree du .tscn, ces champs se posent dans l'inspecteur
# Godot). En mode hote, la scene apporte deja sol/lumiere/camera/joueur,
# la coquille ne monte que les MultiMesh de rendu. En mode isole
# (defaut), la coquille monte son propre decor.
#
# ECART FRAMEWORK : ce banc + son catalogue local sont neufs, voir
# CLAUDE.md § Frontiere.

extends Node3D

const Monde = preload("res://scripts/monde.gd")
const ChampSaturationPlatGd = preload("res://scripts/champ_saturation_plat.gd")
const AttenteSeuil = preload("res://scripts/attente_seuil.gd")
const JoueurBanc = preload("res://jeu/bancs/joueur_banc.gd")
const SimulationArbreGd = preload("res://jeu/bancs/simulation_arbre.gd")

const CHEMIN_CATALOGUE_LOCAL := "res://data/banc_peuplement_arbre.json"
const CHEMIN_TYPES := "res://data/types.json"

# Hauteur du sol visuel monte par `_monter_scene`. Meme constante que
# `SimulationArbreGd.Y_SOL` -- doublage assume (la coquille ne dependrait
# sinon de la sim que pour lire une constante scenographique).
const Y_SOL := 12.0

# Capacite initiale des deux MultiMesh, doit correspondre a
# `SimulationArbreGd.CAPACITE_INITIALE` -- l'init des colonnes de la sim
# repose sur cette taille de buffer.
const CAPACITE_INITIALE := 8

# MODE HOTE : le banc tourne dans une scene qui apporte deja son sol, sa
# lumiere, sa camera, son joueur (par exemple `jeu/Proto/verification.tscn`).
# `hote_actif = true` : la coquille SAUTE `_monter_scene` et
# `_monter_joueur`, derive `_demi_carte` de `carte_terrain_ref.metres()`
# (surcharge la valeur JSON). Le monde data (`_monde`) continue de
# stocker `y = Y_SOL` constant : distance XZ preservee, gate/banque/
# reveils bit-a-bit identiques au mode isole. Doctrine CLAUDE.md « Les
# donnees sont la verite, la physique est un rendu » : le monde ne
# connait pas le relief, le rendu si.
@export var hote_actif: bool = false
# En mode hote, ressource carte_terrain injectee par la scene hote (par
# exemple `res://jeu/Proto/proto_carte.tres`). Doit exposer `sommet(x, z)`
# (Y du sol en unites monde) et `metres()` (etendue en unites monde).
# `null` en mode isole (jamais lu).
@export var carte_terrain_ref: Resource = null

# Cadence de simulation (Hz) : la boucle du banc (age, stade, reproduction,
# competition, ecriture MultiMesh) tourne a cette cadence lente, jamais
# a 60 fps. Le delta accumule est passe en `pas` a `_sim.avancer(pas)`.
# Le joueur (physics_process) garde son framerate plein.
var _cadence_simulation_hz: float = 4.0
# Multiplicateur x4 sur `pas` (observation du cycle). Lue du JSON.
var _mode_test_rapide: bool = false
var _temps_depuis_maj: float = 0.0

# Refs vers les MultiMesh crees par la coquille et injectes a la sim.
# Aucun autre usage local -- la sim ecrit `set_instance_transform` /
# `set_instance_color` a chaque tick via les refs.
var _mm_tronc: MultiMesh = null
var _mm_feuillage: MultiMesh = null
var _noeud_tronc: MultiMeshInstance3D = null
var _noeud_feuillage: MultiMeshInstance3D = null

# OCCLUSION ARBRE (2026-09-15). Un OccluderInstance3D dedie au peuplement,
# alimente par les troncs deja dans le cercle de rendu (les MEMES arbres
# que ceux poses dans _mm_tronc.buffer -- le C++ compact les a filtres
# par distance). Un tronc = deux quads verticaux en croix (XY et ZY),
# fusionnes en UN seul ArrayOccluder3D. Patron : `rendu_terrain_multimesh.gd`
# _occludeur_de_cubes / _phase_baker_occluder l.838-873 (ArrayOccluder3D
# double-face, set_arrays(sommets, indices), OccluderInstance3D.occluder = occ).
# NE TOUCHE AUCUNE colonne de sim, aucun RNG, aucune cadence. Aucun cout
# ajoute au tick sim ; seule la coquille rebake.
var _noeud_occludeur: OccluderInstance3D = null
# Rebake AMORTI a intervalle fixe. Sans amortissement, le cout CPU de
# construction du ArrayOccluder3D (N=8000 troncs -> 64k sommets + 96k
# indices + set_arrays) tomberait dans chaque frame et mangerait le gain
# d'occlusion. 0.5 s = 2 rebake/s : la composition du cercle change lente
# ment (l'observateur bouge de quelques m par seconde), la latence
# visuelle est negligeable.
const INTERVALLE_BAKE_OCCL_S := 0.5
# Un tronc plus petit que ce seuil ne participe pas au maillage occludeur :
# la geometrie ajoutee ne bloquerait presque rien (jeune arbre) et
# gaspillerait le budget CPU rasterizer.
const HAUTEUR_MIN_TRONC_OCCL := 1.0
const HAUTEUR_MIN_FEUILLAGE_OCCL := 1.0
var _temps_depuis_bake_occl: float = 0.0

# CONE DE VISION (streaming, 2026-09-15). Demi-angle du cone de filtrage
# rendu, EN DEGRES. Volontairement plus large que le demi-FOV horizontal
# reel (~45-50 degres a FOV 75 vertical + aspect 16:9) pour offrir une
# marge : un arbre au bord de l'ecran ne clignote pas quand le joueur
# pivote entre deux ticks. Cos precompute a `_ready`.
const CONE_DEMI_ANGLE_DEG := 55.0
var _cone_cos_demi_angle: float = cos(deg_to_rad(CONE_DEMI_ANGLE_DEG))

# CONE PROGRESSIF -> COUPURE FRANCHE (2026-09-15). |fwd.y| = sin(tangage).
# Sous SEUIL_BAS : cone actif normal (rendu econome, vue horizontale).
# Au-dessus de SEUIL_HAUT : cone desactive, tout le cercle rendu -- on
# coupe AVANT la zone d'instabilite de dir_xz (quand length² <= 0.0001,
# vers tangage ~89.4°, la garde declenche un basculement brutal du
# vecteur). Entre les deux : bande de transition etroite (smoothstep)
# pour eviter un saut visible. Bande 0.60..0.75 = tangage 37°..49° :
# le cone se ferme bien avant que la direction XZ devienne bruitee.
const CONE_TANGAGE_SEUIL_BAS := 0.64
const CONE_TANGAGE_SEUIL_HAUT := 0.95

# STREAMING RENDU 60 Hz (2026-09-15). Le rebuild du buffer compact suit
# la CAMERA (position + orientation XZ), pas la cadence sim. Sans ce
# rebuild par frame, quand la camera pivote entre deux ticks sim (250 ms
# a 4 Hz), les arbres qui entrent dans le champ n'apparaissent qu'au
# prochain tick -> pop visible. La sim ne re-tourne PAS : seul le filtre
# cercle+cone se recalcule. Gate par SEUIL_* pour ne pas rebuilder quand
# la camera est immobile (economie a N=100000).
const REBUILD_SEUIL_POS_M := 0.25   # 25 cm de deplacement
const REBUILD_SEUIL_COS := 0.9998   # ~1.1 degre d'ecart d'orientation XZ
var _pos_bake_prec: Vector2 = Vector2.INF * Vector2.ONE
var _dir_bake_prec: Vector2 = Vector2.ZERO
var _bake_prec_valide: bool = false

# Module de simulation. Instancie au `_ready`, appele par `_process`.
# `null` avant init : `_process` gate en tete pour ne pas appeler avancer
# sur rien -- au moindre echec de config, la sim reste null et le banc
# noop.
var _sim: RefCounted = null


func _ready() -> void:
	var donnees: Dictionary = _charger_json_local()
	if donnees.is_empty():
		return
	# Reglages de cadence : tenus par la coquille (gate `_process`).
	if donnees.has("cadence_simulation_hz"):
		_cadence_simulation_hz = float(donnees.cadence_simulation_hz)
	if donnees.has("mode_test_rapide"):
		_mode_test_rapide = bool(donnees.mode_test_rapide)
	# En mode hote, on SURCHARGE la cle `demi_carte` du JSON avant de la
	# passer a la sim, pour que la garde de semis (`abs(x) > _demi_carte`)
	# corresponde a l'emprise reelle du terrain fourni par la scene hote.
	# Preservation bit-a-bit : les bornes de `ChampSaturationPlatGd` restent
	# calculees sur la valeur JSON (comme avant refonte) via
	# `demi_carte_couvert` ci-dessous ; seul le champ `_demi_carte` de la
	# sim recoit la valeur derivee du terrain.
	var demi_carte_couvert: float = float(donnees.get("demi_carte", 300.0))
	if hote_actif:
		if carte_terrain_ref == null:
			push_error("banc_peuplement_arbre : hote_actif = true mais carte_terrain_ref manquant, banc inerte")
			return
		var etendue_m: float = float(carte_terrain_ref.metres())
		donnees["demi_carte"] = etendue_m * 0.5
	# ChampSaturationPlatGd : bornes derivees de `demi_carte / taille_case` +
	# marge = ceil(max_rayon_ombre_m / taille_case), pour couvrir les
	# depots pres du bord.
	var taille_case: float = float(donnees.get("taille_case", 20.0))
	var ombrage: Array = donnees.get("ombrage_par_stade", [])
	var max_rayon_ombre_m: float = 0.0
	for entree in ombrage:
		if entree is Dictionary:
			max_rayon_ombre_m = maxf(max_rayon_ombre_m, float(entree.get("rayon_ombre_m", 0.0)))
	var demi_cases: int = int(ceil(demi_carte_couvert / taille_case))
	var marge_cases: int = int(ceil(max_rayon_ombre_m / taille_case))
	var borne_cases: int = demi_cases + marge_cases
	var couvert = ChampSaturationPlatGd.new()
	# ETAPE 9 : bascule couvert vers ChampSaturationPlatGd C++ (miroir
	# bit-a-bit). L'oracle GDScript reste comme fallback pour tests.
	couvert.activer_cpp()
	couvert.configurer(-borne_cases, -borne_cases, borne_cases, borne_cases)
	var monde = Monde.new()
	monde.structure_simple = true
	var banque = AttenteSeuil.new()
	# Paquet `dynamique` du framework (data/types.json), extrait ici et
	# passe a la sim : le module ne relit jamais le disque.
	var types_dynamique = _lire_types_dynamique()
	if types_dynamique == null:
		return
	if hote_actif:
		# Zones d'exclusion : DIFFERE le chargement a la fin du frame.
		# Un noeud d'exclusion frere dans la scene s'inscrit au groupe
		# `&"exclusion_arbre"` dans SON `_ready` -- Godot execute les
		# `_ready` dans l'ordre des freres du .tscn, la coquille peut
		# ainsi lire le groupe AVANT que les zones s'y soient inscrites.
		# `call_deferred` execute apres TOUS les `_ready` du frame et
		# avant le premier `_process` -- l'ordre des noeuds dans le
		# `.tscn` devient indifferent.
		call_deferred(&"_charger_zones_exclusion")
	else:
		var joueur_a: bool = bool(donnees.get("joueur_actif", true))
		_monter_scene(demi_carte_couvert, joueur_a)
		if joueur_a:
			_monter_joueur()
	_monter_population_nodes()
	# Instancie la sim et lui injecte tout.
	_sim = SimulationArbreGd.new()
	_sim.configurer(donnees)
	_sim.attacher(_mm_tronc, _mm_feuillage, monde, couvert, banque, hote_actif, carte_terrain_ref, types_dynamique)
	# BASCULE C++ activee par defaut (etape 2 : passe 1 senescence + stade
	# + detection + mort vieillesse tourne cote C++). Silencieux si
	# l'extension n'est pas chargee (push_warning + retombe sur l'oracle).
	_sim.configurer_cpp(true)
	# Position monde de l'arbre INITIAL : lit `global_position.xz` du
	# noeud de la coquille pose dans la scene. Mode isole : le tscn du
	# banc n'a pas de transform, `global_position = Vector3.ZERO`, donc
	# arbre initial en (0, Y_SOL, 0) -- comportement inchange. Mode
	# hote : le noeud est positionne dans verification.tscn, l'arbre
	# initial est plante a cette position.
	_sim.naitre_initial(global_position.x, global_position.z)


var _instr_temps_depuis_affichage: float = 0.0
const INSTR_INTERVALLE_S: float = 1.0
# INSTRUMENTATION diagnostic buf2D=0 (aucune correction, comptage pur) :
#   _instr_rebuilds_fenetre  : nb d'appels rafraichir_buffer_rendu dans la
#                              fenetre INSTR_INTERVALLE_S en cours.
#   _instr_frames_fenetre    : nb d'appels _process dans la meme fenetre.
#   _instr_rebuild_frame_prec: rebuild declenche a la frame precedente (0/1).
# Le print rapporte rebuilds_par_sec = _rebuilds_fenetre / INSTR_INTERVALLE_S
# et frames_sans_rebuild_par_sec = (_frames_fenetre - _rebuilds_fenetre) /
# INSTR_INTERVALLE_S, plus rebuild_ce_tick = _rebuild_frame_prec.
var _instr_rebuilds_fenetre: int = 0
var _instr_frames_fenetre: int = 0
var _instr_rebuild_frame_prec: int = 0


func _process(delta: float) -> void:
	if _sim == null:
		return
	# Chantier occlusion par cellules, etape 2/8 : log de la cellule courante.
	_instr_temps_depuis_affichage += delta
	_instr_frames_fenetre += 1
	if _instr_temps_depuis_affichage >= INSTR_INTERVALLE_S:
		var rebuilds_par_sec: float = float(_instr_rebuilds_fenetre) / _instr_temps_depuis_affichage
		var frames_sans_par_sec: float = float(_instr_frames_fenetre - _instr_rebuilds_fenetre) / _instr_temps_depuis_affichage
		_instr_temps_depuis_affichage = 0.0
		_instr_rebuilds_fenetre = 0
		_instr_frames_fenetre = 0
		_instr_rebuild_frame_prec = 0
		print("bloq=", _sim.instr_nb_bloqueurs_camera(), " buf2D=", _sim.instr_pixels_couverts_2d(), "/2048 occ=", _sim.instr_occultes_2d(), " self=", _sim.instr_self_occ(), " proches=", _sim.instr_faux_pos_proches(), " buf(min=", _sim.instr_buf2d_min(), " med=", _sim.instr_buf2d_med(), " max=", _sim.instr_buf2d_max(), ") dump=i(", _sim.instr_dump_i(), ") rectX=", _sim.instr_dump_rect_x(), " rectY=", _sim.instr_dump_rect_y(), " arbre=", _sim.instr_dump_d_arbre(), "m minBuf=", _sim.instr_dump_d_min_buf(), "m maxBuf=", _sim.instr_dump_d_max_buf(), "m rebuild_ce_tick=", _instr_rebuild_frame_prec, " rebuilds/s=", "%.1f" % rebuilds_par_sec, " sans_rebuild/s=", "%.1f" % frames_sans_par_sec, " nb_remplissages_buf=", _sim.instr_nb_remplissages_buffer())
	# STREAMING RENDU ARBRE, ETAPE 1/4 : pousser la position de
	# l'observateur (joueur) a la sim CHAQUE FRAME, avant le gate de
	# cadence -- que la sim ait tourne ce tick ou non, la position reste
	# fraiche. Patron identique a terrain_visible.gd (l.245-250) :
	# `get_first_node_in_group(&"observateur")`. Mode isole (pas de joueur
	# dans la scene) : aucun push, le drapeau `_observateur_actif` cote sim
	# reste false (cas neutre, pas une panne).
	# CAMERA suivie a 60 Hz : position XZ + direction XZ. Pousse a la sim
	# CHAQUE FRAME (cout : 3 float stores + bool), utile a la fois pour
	# avancer(pas) au prochain tick sim et pour rafraichir_buffer_rendu()
	# entre deux ticks quand la camera bouge.
	var pos_obs_xz := Vector2.ZERO
	var dir_obs_xz := Vector2.ZERO
	var obs_present: bool = false
	var obs_cone_present: bool = false
	var obs := get_tree().get_first_node_in_group(&"observateur")
	if obs != null and obs is Node3D:
		var noeud_obs: Node3D = obs as Node3D
		var pos_obs: Vector3 = noeud_obs.global_position
		pos_obs_xz = Vector2(pos_obs.x, pos_obs.z)
		obs_present = true
		_sim.definir_observateur(pos_obs.x, pos_obs.z)
		# CUSTOM_AABB RECENTREE SUR LE JOUEUR (2026-09-15). Godot culle un
		# MultiMesh comme UN objet via son AABB globale ; l'AABB auto n'est
		# pas rafraichie de maniere fiable apres reecriture des transforms
		# du buffer, donc les arbres en bord d'ecran disparaissent quand la
		# camera tourne. `top_level = true` -> transform du noeud = identite
		# -> l'AABB locale posee ici est deja en coordonnees monde. Rayon
		# rendu 80 m + marge 10 m ; Y garde -5 a +60 (origine -5, taille 65).
		var demi := 90.0
		var aabb_arbres := AABB(Vector3(pos_obs.x - demi, -5.0, pos_obs.z - demi), Vector3(demi * 2.0, 65.0, demi * 2.0))
		_noeud_tronc.custom_aabb = aabb_arbres
		_noeud_feuillage.custom_aabb = aabb_arbres
		# CONE VISION (2026-09-15) : direction XZ du regard = -basis.z du
		# noeud observateur, projetee sur XZ puis normalisee. Le joueur
		# (JoueurBanc CharacterBody3D) porte son lacet sur son propre basis
		# (le tangage vit dans _yeux, indifferent pour un cone XZ). Camera
		# fixe (banc mode isole, joueur inactif) : -basis.z pointe vers
		# l'origine, meme convention. Direction quasi-verticale (regard au
		# sol ou au ciel) -> pas de cone (dir_xz trop courte a normaliser).
		# Lire fwd sur la CAMERA ACTIVE, pas sur le body : le body ne porte
		# que le lacet (joueur_banc.gd:81), le tangage vit sur la camera
		# enfant (_yeux.rotation.x). Lire basis.z du body -> fwd.y ~= 0 quel
		# que soit le regard vertical, le lerp cos_eff plus bas ne s'active
		# jamais. get_viewport().get_camera_3d() rend la camera courante
		# quelle que soit la scene ; fallback body si aucune camera active.
		var cam := get_viewport().get_camera_3d()
		var fwd: Vector3 = -cam.global_transform.basis.z if cam != null else -noeud_obs.global_transform.basis.z
		# COUPURE FRANCHE SELON TANGAGE (2026-09-15). Le lerp lineaire
		# precedent ouvrait le cone TROP TARD : la transition finissait
		# vers tangage 90° alors que dir_xz devient bruite bien avant.
		# Nouvelle logique : sous SEUIL_BAS le cone est normal, au-dessus
		# de SEUIL_HAUT il est desactive (cos_eff=-1 = tout le cercle),
		# bande smoothstep etroite au milieu. La coupure arrive AVANT que
		# dir_xz devienne instable -> aucun saut au moment ou la garde
		# length² > 0.0001 finit par se declencher (le cone est deja off).
		# Frustum radar cote C++ (dans_cercle) filtre lui-meme le tangage via
		# up_v vs tan(FOV_V/2) : la coupure par tangage qui rendait tout le
		# cercle au sol/ciel est neutralisee ; cos_eff reste au demi-angle
		# constant. Les constantes SEUIL_BAS/HAUT restent declarees en tete.
		var cos_eff: float = _cone_cos_demi_angle
		var dir_xz := Vector2(fwd.x, fwd.z)
		if dir_xz.length_squared() > 0.0001:
			dir_xz = dir_xz.normalized()
			dir_obs_xz = dir_xz
			obs_cone_present = true
			_sim.definir_observateur_cone(dir_xz.x, dir_xz.y, cos_eff)
		# Etape 3/8 occlusion 2D projete camera : hauteur camera + fwd.y.
		_sim.definir_observateur_3d(pos_obs.y, fwd.y)
		# Canal FOV camera -> buffer occlusion : le buffer 2D doit couvrir
		# AU MOINS le champ rendu (75 vertical, aspect ecran) + une marge
		# laterale pour eviter que les arbres au bord du champ echappent au
		# test. Sans ce canal, le buffer restait fige a 115/80 en dur, plus
		# etroit que le rendu -> arbres de bordure jamais occultes.
		if cam != null:
			var fov_v_cam: float = cam.fov
			var vp: Viewport = get_viewport()
			var vps: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(16.0, 9.0)
			var aspect_ecran: float = vps.x / vps.y if vps.y > 0.0 else 16.0 / 9.0
			const MARGE_FOV_BUFFER := 1.0
			_sim.definir_fov_buffer(fov_v_cam * MARGE_FOV_BUFFER, aspect_ecran)
	# CADENCE DE SIMULATION DECOUPLEE DU FRAMERATE : la sim ne tourne
	# pas 60 fois par seconde. Le delta accumule est passe en `pas` a
	# `_sim.avancer(pas)` -- proba stochastique / cadence banque /
	# competition dependent de `pas`, donc leur cadence moyenne reste
	# identique.
	_temps_depuis_maj += delta
	var intervalle_maj: float = 1.0 / _cadence_simulation_hz if _cadence_simulation_hz > 0.0 else 0.0
	var sim_a_tourne: bool = false
	if _temps_depuis_maj >= intervalle_maj:
		var pas: float = _temps_depuis_maj
		_temps_depuis_maj = 0.0
		if _mode_test_rapide:
			pas *= 4.0
		_sim.avancer(pas)
		sim_a_tourne = true
	# STREAMING RENDU 60 Hz (2026-09-15). Si la sim n'a pas tourne ce frame
	# ET que la camera a bouge/tourne au-dela des seuils, rafraichir le
	# buffer compact SANS avancer la sim. Cout : un rebuild O(cap) borne
	# cercle+cone, aucune mutation de colonne sim. Camera immobile : rien.
	if obs_present and not sim_a_tourne:
		var doit_rebuild: bool = not _bake_prec_valide
		if not doit_rebuild:
			var d_pos: float = (pos_obs_xz - _pos_bake_prec).length()
			if d_pos >= REBUILD_SEUIL_POS_M:
				doit_rebuild = true
		if not doit_rebuild and obs_cone_present:
			var d_cos: float = dir_obs_xz.dot(_dir_bake_prec)
			if d_cos < REBUILD_SEUIL_COS:
				doit_rebuild = true
		if doit_rebuild:
			_sim.rafraichir_buffer_rendu()
			_pos_bake_prec = pos_obs_xz
			_dir_bake_prec = dir_obs_xz
			_bake_prec_valide = true
			_instr_rebuilds_fenetre += 1
			_instr_rebuild_frame_prec = 1
	elif sim_a_tourne and obs_present:
		# DECOUPLAGE RENDU (prompt 2026-09-16). avancer() ne rebuild plus
		# le buffer -- c'est ici que la coquille declenche le rebuild apres
		# un tick sim, pour que la mutation (ages, stades, morts, naissances)
		# soit propagee au rendu. Sans ce rebuild, les nouveaux arbres
		# resteraient invisibles jusqu'au premier deplacement camera.
		_sim.rafraichir_buffer_rendu()
		_pos_bake_prec = pos_obs_xz
		_dir_bake_prec = dir_obs_xz
		_bake_prec_valide = true
		_instr_rebuilds_fenetre += 1
		_instr_rebuild_frame_prec = 1
	# OCCLUSION ARBRE : rebake amorti a INTERVALLE_BAKE_OCCL_S. Independant
	# de la cadence sim -- le buffer de rendu est toujours a jour du dernier
	# tick, on rebake sur son etat actuel. Le noeud occludeur ne change rien
	# a la sim ; l'occlusion est un ajout de rendu pur.
	_temps_depuis_bake_occl += delta
	if _temps_depuis_bake_occl >= INTERVALLE_BAKE_OCCL_S:
		_temps_depuis_bake_occl = 0.0
		_rebake_occludeur_arbre()


# Charge le JSON du banc (donnees + config). Rend un Dictionary vide en
# cas d'echec -- l'appelant (`_ready`) court-circuite le montage.
func _charger_json_local() -> Dictionary:
	if not FileAccess.file_exists(CHEMIN_CATALOGUE_LOCAL):
		push_error("banc_peuplement_arbre : catalogue local absent (%s)" % CHEMIN_CATALOGUE_LOCAL)
		return {}
	var texte := FileAccess.get_file_as_string(CHEMIN_CATALOGUE_LOCAL)
	if texte.is_empty():
		push_error("banc_peuplement_arbre : catalogue local vide (%s)" % CHEMIN_CATALOGUE_LOCAL)
		return {}
	var donnees = JSON.parse_string(texte)
	if not (donnees is Dictionary):
		push_error("banc_peuplement_arbre : catalogue local invalide (pas un objet)")
		return {}
	return donnees


# Lit `data/types.json` et rend le paquet `dynamique`. Passe a la sim
# pour construire le catalogue combine.
func _lire_types_dynamique() -> Variant:
	if not FileAccess.file_exists(CHEMIN_TYPES):
		push_error("banc_peuplement_arbre : %s absent" % CHEMIN_TYPES)
		return null
	var texte_types := FileAccess.get_file_as_string(CHEMIN_TYPES)
	var types = JSON.parse_string(texte_types)
	if not (types is Dictionary):
		push_error("banc_peuplement_arbre : %s invalide" % CHEMIN_TYPES)
		return null
	if not types.has("dynamique"):
		push_error("banc_peuplement_arbre : paquet `dynamique` absent de %s" % CHEMIN_TYPES)
		return null
	return types.dynamique


func _monter_scene(demi_carte: float, joueur_actif: bool) -> void:
	var sol := MeshInstance3D.new()
	var plan := PlaneMesh.new()
	plan.size = Vector2(demi_carte * 2.0, demi_carte * 2.0)
	var mat_sol := StandardMaterial3D.new()
	mat_sol.albedo_color = Color(0.3, 0.3, 0.3)
	plan.material = mat_sol
	sol.mesh = plan
	sol.position = Vector3(0.0, Y_SOL, 0.0)
	add_child(sol)
	# Collision statique du sol : sans elle, le CharacterBody3D du joueur
	# tomberait indefiniment. Une box tres plate (0.2 m) suffit et evite le
	# cas limite d'un plan infini a epaisseur nulle.
	var sol_corps := StaticBody3D.new()
	sol_corps.position = Vector3(0.0, Y_SOL - 0.1, 0.0)
	var sol_collision := CollisionShape3D.new()
	var sol_forme := BoxShape3D.new()
	sol_forme.size = Vector3(demi_carte * 2.0, 0.2, demi_carte * 2.0)
	sol_collision.shape = sol_forme
	sol_corps.add_child(sol_collision)
	add_child(sol_corps)
	var lumiere := DirectionalLight3D.new()
	lumiere.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	lumiere.light_energy = 1.0
	lumiere.shadow_enabled = false
	add_child(lumiere)
	# Camera plongeante conservee mais NON-current : le joueur reprend le
	# point de vue avec sa propre camera. Le groupe "observateur" est pose
	# sur la camera SEULEMENT quand le joueur est desactive -- sinon c'est
	# le JoueurBanc (CharacterBody3D mobile) qui porte le groupe (voir
	# `_monter_joueur`), pour que le streaming rendu suive la vraie
	# position du point de vue.
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 55.0, 55.0)
	# current = true si le joueur est desactive (JSON `joueur_actif`=false),
	# sinon false : le joueur mettra sa propre camera current au _ready.
	camera.current = not joueur_actif
	if not joueur_actif:
		camera.add_to_group(&"observateur")
	add_child(camera)
	camera.look_at(Vector3(0.0, Y_SOL, 0.0), Vector3.UP)


# Instancie le joueur jetable (CharacterBody3D + capsule + Camera3D). Pose
# a 8 m de l'arbre initial pour ne pas naitre coince dans le tronc, un
# metre au-dessus du sol pour retomber proprement au premier tick de
# gravite. Exception joueur du CLAUDE.md : seul pont autorise entre le
# monde data et le rendu Godot.
func _monter_joueur() -> void:
	var joueur := JoueurBanc.new()
	joueur.position = Vector3(8.0, Y_SOL + 1.0, 8.0)
	# STREAMING RENDU ARBRE, ETAPE 1/4 (2026-09-15) : le joueur est le
	# point de vue mobile -- c'est lui qui porte le groupe "observateur",
	# pas la camera plongeante fixe. Convention du framework
	# (terrain_visible.gd:245-250, banc_peuplement.gd:294).
	joueur.add_to_group(&"observateur")
	add_child(joueur)


# Meshes UNITAIRES : CylinderMesh hauteur 1 rayon 0.5 (tronc droit,
# diametre 1 -- equivalent a l'ancienne BoxMesh de largeur 1, le scale
# par la largeur dans `_ecrire_slot` donne le meme diametre). CylinderMesh
# hauteur 1 rayon-bas 0.5 rayon-haut 0 (cone feuillage). L'init des
# COLONNES de la sim (tailles, sentinelles, ordre des `_ecrire_slot_vide`)
# se fait dans `SimulationArbreGd._monter_population_init`, appele par
# `_sim.attacher(...)` immediatement apres l'attachement des MultiMesh.
func _monter_population_nodes() -> void:
	var tronc_mesh := CylinderMesh.new()
	tronc_mesh.top_radius = 0.5
	tronc_mesh.bottom_radius = 0.5
	tronc_mesh.height = 1.0
	# Densite mesh volontairement basse pour la simulation de masse (defaut
	# Godot : radial_segments=64, rings=4 -> ~256 triangles par tronc x N,
	# 24M primitives a N=8500). 8 segments = compromis rondeur/cout pour
	# simulation de masse, ajustable. cap_top desactive car cache par feuillage.
	tronc_mesh.radial_segments = 8
	tronc_mesh.rings = 1
	tronc_mesh.cap_top = false
	tronc_mesh.cap_bottom = true
	var mat_tronc := StandardMaterial3D.new()
	mat_tronc.albedo_color = Color(0.35, 0.22, 0.12)
	# Couleur d'instance -> albedo (paire OBLIGATOIRE avec
	# `_mm_tronc.use_colors = true` : sans les deux, `set_instance_color`
	# est ignore silencieusement).
	mat_tronc.vertex_color_use_as_albedo = true
	tronc_mesh.material = mat_tronc
	_mm_tronc = MultiMesh.new()
	_mm_tronc.transform_format = MultiMesh.TRANSFORM_3D
	_mm_tronc.use_colors = true
	_mm_tronc.mesh = tronc_mesh
	_mm_tronc.instance_count = CAPACITE_INITIALE
	_noeud_tronc = MultiMeshInstance3D.new()
	_noeud_tronc.multimesh = _mm_tronc
	# TOP_LEVEL : le multimesh ne suit PAS la transform de la coquille
	# (les instances sont ecrites en coordonnees monde par leurs positions
	# _positions_x/z/y). Sans ce flag, deplacer le noeud Foret dans la
	# scene deplacerait aussi visuellement tous les arbres.
	_noeud_tronc.top_level = true
	# `_ecrire_slot` mute les transforms depuis `_process` (rendu par
	# frame), pas `_physics_process` : desactiver l'interpolation physique
	# evite le warning "MultiMesh interpolation triggered from outside
	# physics process" de Godot 4.5+, sans effet sur le rendu (arbres
	# statiques par nature).
	_noeud_tronc.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_noeud_tronc)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	# Densite mesh volontairement basse (meme raison que tronc). 8 segments =
	# compromis rondeur/cout, ajustable. cap_bottom actif (base visible par
	# en dessous a distance) ; top_radius=0 -> pas de cap_top possible.
	cone.radial_segments = 8
	cone.rings = 1
	cone.cap_bottom = true
	var mat_feuillage := StandardMaterial3D.new()
	mat_feuillage.albedo_color = Color(0.15, 0.45, 0.2)
	# Couleur d'instance -> albedo (paire OBLIGATOIRE avec use_colors,
	# meme raison que pour le tronc).
	mat_feuillage.vertex_color_use_as_albedo = true
	cone.material = mat_feuillage
	_mm_feuillage = MultiMesh.new()
	_mm_feuillage.transform_format = MultiMesh.TRANSFORM_3D
	_mm_feuillage.use_colors = true
	_mm_feuillage.mesh = cone
	_mm_feuillage.instance_count = CAPACITE_INITIALE
	_noeud_feuillage = MultiMeshInstance3D.new()
	_noeud_feuillage.multimesh = _mm_feuillage
	_noeud_feuillage.top_level = true
	_noeud_feuillage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_noeud_feuillage)
	# OCCLUSION ARBRE : noeud OccluderInstance3D dedie au peuplement.
	# top_level = true : les sommets du ArrayOccluder3D sont ecrits en
	# COORDONNEES MONDE (memes que _mm_tronc.buffer), le noeud reste a
	# l'origine, meme convention que _noeud_tronc/_noeud_feuillage.
	_noeud_occludeur = OccluderInstance3D.new()
	_noeud_occludeur.top_level = true
	_noeud_occludeur.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_noeud_occludeur)


# Lit une fois le groupe `&"exclusion_arbre"` et copie chaque zone en
# dict data legere, puis passe la liste a la sim (aucune reference vivante
# au noeud dans le hot path). Appelee par `_ready` en mode hote via
# `call_deferred` -- garantit que TOUS les noeuds d'exclusion freres ont
# deja execute leur propre `_ready` (donc `add_to_group`) au moment ou
# on lit le groupe.
func _rebake_occludeur_arbre() -> void:
	# OCCLUSION ARBRE (2026-09-15). Reconstruit un ArrayOccluder3D neuf a
	# partir du BUFFER TRONC CERCLE SEUL (sim.buffer_tronc_occludeur()),
	# batie cote C++ avec le filtre cercle uniquement -- sans cone, sans
	# occlusion CPU. L'occludeur couvre donc tous les troncs du cercle de
	# rendu et NE CHANGE PAS quand la camera tourne : il ne varie qu'au
	# deplacement de l'observateur. Pour chaque tronc, deux quads verticaux
	# en croix (perpendiculaires a X et a Z) : occulte dans toutes les
	# directions horizontales sans depender de l'orientation (pas de
	# billboard, pas de rebake sur rotation).
	# ArrayOccluder3D est DOUBLE-FACE (voir rendu_terrain_multimesh.gd:838),
	# winding order libre.
	if _sim == null or _noeud_occludeur == null:
		return
	var pop: int = _sim.pop_occludeur()
	if pop <= 0:
		_noeud_occludeur.occluder = null
		return
	var buf: PackedFloat32Array = _sim.buffer_tronc_occludeur()
	if buf.size() < pop * 16:
		return
	var sommets := PackedVector3Array()
	var indices := PackedInt32Array()
	# Reserve approximative : 8 sommets et 12 indices par tronc valide.
	# Sur-allocation gerable, evite les realloc successives.
	sommets.resize(0)
	indices.resize(0)
	var k: int = 0
	while k < pop:
		var base: int = k * 16
		# Layout TRANSFORM_3D + color, 16 floats/instance. Buffer ecrit par
		# le C++ (simulation_arbre.cpp:mettre_a_jour_buffers_rendu). Basis
		# diagonale : rows[0].x = lt (largeur), rows[1].y = ht (hauteur),
		# origin = (buf[3], buf[7], buf[11]) avec y = y_sol + ht*0.5.
		var lt: float = buf[base + 0]
		var ht: float = buf[base + 5]
		if ht < HAUTEUR_MIN_TRONC_OCCL:
			k += 1
			continue
		var ox: float = buf[base + 3]
		var oy: float = buf[base + 7]
		var oz: float = buf[base + 11]
		var y_bas: float = oy - ht * 0.5
		var y_haut: float = oy + ht * 0.5
		var demi_l: float = lt * 0.5
		# Quad 1 : plan XY (perpendiculaire a Z).
		var s0: int = sommets.size()
		sommets.append(Vector3(ox - demi_l, y_bas, oz))
		sommets.append(Vector3(ox + demi_l, y_bas, oz))
		sommets.append(Vector3(ox + demi_l, y_haut, oz))
		sommets.append(Vector3(ox - demi_l, y_haut, oz))
		indices.append(s0 + 0); indices.append(s0 + 1); indices.append(s0 + 2)
		indices.append(s0 + 0); indices.append(s0 + 2); indices.append(s0 + 3)
		# Quad 2 : plan ZY (perpendiculaire a X).
		var s1: int = sommets.size()
		sommets.append(Vector3(ox, y_bas, oz - demi_l))
		sommets.append(Vector3(ox, y_bas, oz + demi_l))
		sommets.append(Vector3(ox, y_haut, oz + demi_l))
		sommets.append(Vector3(ox, y_haut, oz - demi_l))
		indices.append(s1 + 0); indices.append(s1 + 1); indices.append(s1 + 2)
		indices.append(s1 + 0); indices.append(s1 + 2); indices.append(s1 + 3)
		k += 1
	# Meme logique pour le FEUILLAGE : mêmes deux quads en croix, lus depuis
	# buffer_feuillage_occludeur(). Layout identique (TRANSFORM_3D + color,
	# 16 floats/instance) : rows[0].x = lf, rows[1].y = hf, origin.y =
	# y_sol + ht + hf/2 (le feuillage est pose sur le tronc, pas centre au
	# milieu de sa hauteur). Le feuillage devient bloqueur au meme titre
	# que le tronc.
	var buf_f: PackedFloat32Array = _sim.buffer_feuillage_occludeur()
	if buf_f.size() >= pop * 16:
		var kf: int = 0
		while kf < pop:
			var basef: int = kf * 16
			var lf: float = buf_f[basef + 0]
			var hf: float = buf_f[basef + 5]
			if hf < HAUTEUR_MIN_FEUILLAGE_OCCL:
				kf += 1
				continue
			var oxf: float = buf_f[basef + 3]
			var oyf: float = buf_f[basef + 7]
			var ozf: float = buf_f[basef + 11]
			var yf_bas: float = oyf - hf * 0.5
			var yf_haut: float = oyf + hf * 0.5
			var demi_lf: float = lf * 0.5
			# Quad 1 : plan XY (perpendiculaire a Z).
			var sf0: int = sommets.size()
			sommets.append(Vector3(oxf - demi_lf, yf_bas, ozf))
			sommets.append(Vector3(oxf + demi_lf, yf_bas, ozf))
			sommets.append(Vector3(oxf + demi_lf, yf_haut, ozf))
			sommets.append(Vector3(oxf - demi_lf, yf_haut, ozf))
			indices.append(sf0 + 0); indices.append(sf0 + 1); indices.append(sf0 + 2)
			indices.append(sf0 + 0); indices.append(sf0 + 2); indices.append(sf0 + 3)
			# Quad 2 : plan ZY (perpendiculaire a X).
			var sf1: int = sommets.size()
			sommets.append(Vector3(oxf, yf_bas, ozf - demi_lf))
			sommets.append(Vector3(oxf, yf_bas, ozf + demi_lf))
			sommets.append(Vector3(oxf, yf_haut, ozf + demi_lf))
			sommets.append(Vector3(oxf, yf_haut, ozf - demi_lf))
			indices.append(sf1 + 0); indices.append(sf1 + 1); indices.append(sf1 + 2)
			indices.append(sf1 + 0); indices.append(sf1 + 2); indices.append(sf1 + 3)
			kf += 1
	if indices.is_empty():
		_noeud_occludeur.occluder = null
		return
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(sommets, indices)
	_noeud_occludeur.occluder = occ


func _charger_zones_exclusion() -> void:
	var zones: Array = []
	for zone_node in get_tree().get_nodes_in_group(&"exclusion_arbre"):
		zones.append({
			"forme": int(zone_node.forme),
			"cx": float(zone_node.global_position.x),
			"cz": float(zone_node.global_position.z),
			"rayon": float(zone_node.rayon),
			"demi_x": float(zone_node.demi_x),
			"demi_z": float(zone_node.demi_z),
		})
	if _sim != null:
		_sim.definir_zones_exclusion(zones)
