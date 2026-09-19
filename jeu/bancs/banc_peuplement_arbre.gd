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

# Marge multiplicative du frustum radar cote C++ (tan_h/tan_v * marge).
# > 1.0 elargit le cone d'inclusion : evite qu'un arbre au bord du champ
# soit filtre alors qu'il devrait etre rendu (piste : sur-occlusion quand
# la camera regarde vers le haut). Poussee au C++ chaque frame via
# _sim.definir_marge_frustum. Bornes recadrees cote C++ (1.0..3.0).
@export_range(1.0, 3.0, 0.01) var marge_frustum: float = 1.15
# Masque de couverture Intel MOC (test d'occlusion buffer 2D). Fraction min
# de pixels de l'empreinte STRICTEMENT plus proches que la face de l'arbre
# pour occulter. 1.0 = pas d'occlusion (100% requis), 0.5 = moitie de
# l'empreinte suffit. Poussee au C++ chaque frame via
# _sim.definir_seuil_couverture. Bornes recadrees cote C++ (0.0..1.0).
@export_range(0.0, 1.0, 0.01) var seuil_couverture: float = 0.90
# Marge (metres) absorbee dans le seuil de profondeur : un pixel n'est
# considere couvrant que si son buffer est < depth_min_arbre - marge.
# Poussee au C++ chaque frame. Bornes recadrees cote C++ (0.0..10.0).
@export_range(0.0, 10.0, 0.05) var marge_profondeur_m: float = 0.5
@export_range(1, 255, 1) var hysteresis_frames: int = 60
# HYSTERESIS ADAPTATIVE A LA VITESSE CAMERA. `hysteresis_frames` est la
# valeur de REPOS (camera immobile) ; plus la camera bouge vite (lineaire
# ou angulaire), plus N descend vers `hysteresis_min` -- le filtre reagit
# vite quand la scene change vite, se stabilise quand elle est calme. Les
# deux seuils fixent la vitesse a laquelle N atteint le plancher.
@export_range(1, 60, 1) var hysteresis_min: int = 3
@export_range(0.1, 20.0, 0.1) var vitesse_seuil_lin: float = 3.0
@export_range(0.1, 10.0, 0.1) var vitesse_seuil_ang: float = 1.5
# Rayon de rendu / bloqueurs (metres). Pousse a la sim via donnees JSON
# (surcharge cle `rayon_rendu_m` avant configurer). Distingue "arbre non
# dessine car trop loin" (> rayon_rendu_m) de "arbre occulte" dans les
# instrumentations.
@export_range(20.0, 1000.0, 1.0) var rayon_rendu_m: float = 200.0

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
	# Surcharges JSON des @export d'occlusion : le fichier data/banc_*.json
	# pilote par defaut (Yael edite le JSON) ; l'inspecteur Godot reste une
	# alternative live (Yael peut aussi cocher/regler dans l'editeur -- la
	# valeur JSON gagne quand la cle est presente).
	if donnees.has("marge_frustum"):
		marge_frustum = float(donnees.marge_frustum)
	if donnees.has("seuil_couverture"):
		seuil_couverture = float(donnees.seuil_couverture)
	if donnees.has("marge_profondeur_m"):
		marge_profondeur_m = float(donnees.marge_profondeur_m)
	if donnees.has("hysteresis_frames"):
		hysteresis_frames = int(donnees.hysteresis_frames)
	if donnees.has("rayon_rendu_m"):
		rayon_rendu_m = float(donnees.rayon_rendu_m)
	# Pousse rayon_rendu_m a la sim via donnees (la sim relit sa cle
	# `rayon_rendu_m` dans configurer -- surcharge apres surcharge JSON).
	donnees["rayon_rendu_m"] = rayon_rendu_m
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
# DUMP FRAME D'OCCLUSION (2026-09-18). Arme par F9 dans _unhandled_input,
# consomme dans _process avant rafraichir_buffer_rendu.
var _dump_demande_gd: bool = false
var _acc_bascules: int = 0
var _acc_frames: int = 0
# Etat camera de la frame precedente, pour deriver la vitesse (lin/ang) et
# en tirer le N adaptatif. `_cam_prec_valide` reste faux la premiere frame
# (pas de precedent), N vaut alors `hysteresis_frames`.
var _pos_cam_prec: Vector3 = Vector3.ZERO
var _forward_cam_prec: Vector3 = Vector3.FORWARD
var _cam_prec_valide: bool = false
# Recopies membres pour l'instrumentation (le print tourne dans un gate
# distinct du calcul camera, il lit ces valeurs de la derniere frame).
var _n_adaptatif_instr: int = 60
var _v_lin_instr: float = 0.0
var _v_ang_instr: float = 0.0
const INSTR_INTERVALLE_S: float = 1.0


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F9:
		_dump_demande_gd = true


func _process(delta: float) -> void:
	if _sim == null:
		return
	# Chantier occlusion par cellules, etape 2/8 : log de la cellule courante.
	_instr_temps_depuis_affichage += delta
	if _instr_temps_depuis_affichage >= INSTR_INTERVALLE_S:
		_instr_temps_depuis_affichage = 0.0
		print(
			"bloq=", _sim.instr_nb_bloqueurs_camera(),
			" occ=", _sim.instr_occultes_2d(),
			" self=", _sim.instr_self_occ(),
			" | frames=", _acc_frames,
			" bascules_stable=", _acc_bascules,
			" hyst=", _n_adaptatif_instr,
			" v_lin=", snapped(_v_lin_instr, 0.01),
			" v_ang=", snapped(_v_ang_instr, 0.01)
		)
		_acc_bascules = 0
		_acc_frames = 0
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
	# Canal camera unique : Transform3D affichee + Projection de la camera
	# active, poussees chaque frame. Le C++ lit droite/haut/avant/oeil dans
	# la base, le FOV dans la projection. Plus aucune reconstruction manuelle.
	var obs_present: bool = false
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		obs_present = true
		# Transform AFFICHEE (interpolation physique active : joueur_banc.gd
		# l.21-22 ; doc Node3D.get_global_transform_interpolated).
		var xf: Transform3D = cam.get_global_transform_interpolated()
		# Projection reellement utilisee pour rendre (doc Camera3D).
		var proj: Projection = cam.get_camera_projection()
		# Vitesse camera (lineaire et angulaire) derivee de la frame
		# precedente, puis N adaptatif entre repos et plancher.
		var pos_cam: Vector3 = xf.origin
		var forward_cam: Vector3 = -xf.basis.z
		var v_lin_vec: Vector3 = Vector3.ZERO
		var v_ang: float = 0.0
		if _cam_prec_valide and delta > 0.0:
			v_lin_vec = (pos_cam - _pos_cam_prec) / delta
			var cos_angle: float = clamp(forward_cam.dot(_forward_cam_prec), -1.0, 1.0)
			v_ang = acos(cos_angle) / delta
		var n_adaptatif: int = hysteresis_frames
		if _cam_prec_valide:
			var facteur_lin: float = clamp(v_lin_vec.length() / vitesse_seuil_lin, 0.0, 1.0)
			var facteur_ang: float = clamp(v_ang / vitesse_seuil_ang, 0.0, 1.0)
			var facteur: float = max(facteur_lin, facteur_ang)
			n_adaptatif = int(round(lerp(float(hysteresis_frames), float(hysteresis_min), facteur)))
		_pos_cam_prec = pos_cam
		_forward_cam_prec = forward_cam
		_cam_prec_valide = true
		_n_adaptatif_instr = n_adaptatif
		_v_lin_instr = v_lin_vec.length()
		_v_ang_instr = v_ang
		_sim.definir_camera(xf, proj)
		var pos_obs: Vector3 = xf.origin
		# CUSTOM_AABB recentree (inchange, origine = oeil).
		var demi := 90.0
		var aabb_arbres := AABB(Vector3(pos_obs.x - demi, -5.0, pos_obs.z - demi), Vector3(demi * 2.0, 65.0, demi * 2.0))
		_noeud_tronc.custom_aabb = aabb_arbres
		_noeud_feuillage.custom_aabb = aabb_arbres
		# Marge du frustum radar C++ : poussee chaque frame pour que le
		# slider inspecteur / la surcharge JSON prennent effet a chaud.
		_sim.definir_marge_frustum(marge_frustum)
		# Masque de couverture Intel MOC (test occlusion). Slider a chaud
		# pour trouver le point de calage sans recompiler.
		_sim.definir_seuil_couverture(seuil_couverture)
		_sim.definir_marge_profondeur(marge_profondeur_m)
		_sim.definir_hysteresis_frames(n_adaptatif)
		# Rayon de rendu / occlusion : pousse chaque frame pour que le
		# slider @export rayon_rendu_m ait un effet a chaud (sinon fige a
		# la valeur d'init lue une seule fois par sim.configurer()).
		_sim.definir_rayon_rendu(rayon_rendu_m)
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
	# Visibilite/occlusion recalculees a chaque frame rendue (Intel MOC,
	# GPU Gems 29.4.2). La sim reste a 4 Hz ; seul le filtre rendu suit la
	# camera. HYSTERESIS_FRAMES compte desormais des frames rendues.
	if obs_present and _dump_demande_gd:
		# DUMP FRAME D'OCCLUSION (2026-09-18). Ecrit camera.json + viewport.png
		# cote GD, puis arme le C++ pour qu'il ecrive frame.json + buffer_2d.pgm
		# + 4 CSV sur ce meme frame (avant rafraichir_buffer_rendu ci-dessous).
		var dossier: String = ProjectSettings.globalize_path("res://dumps_occlusion/") \
			+ Time.get_datetime_string_from_system(false, true).replace(":", "-")
		DirAccess.make_dir_recursive_absolute(dossier)
		var cam_dump := get_viewport().get_camera_3d()
		if cam_dump != null:
			var gt := cam_dump.global_transform
			var gti := cam_dump.get_global_transform_interpolated()
			var proj := cam_dump.get_camera_projection()
			# Basis en GDScript : .x = colonne 0, .y = colonne 1, .z = colonne 2.
			var basis_dump := {
				"col0": [gt.basis.x.x, gt.basis.x.y, gt.basis.x.z],
				"col1": [gt.basis.y.x, gt.basis.y.y, gt.basis.y.z],
				"col2": [gt.basis.z.x, gt.basis.z.y, gt.basis.z.z],
				"origin": [gt.origin.x, gt.origin.y, gt.origin.z]
			}
			var basis_dump_i := {
				"col0": [gti.basis.x.x, gti.basis.x.y, gti.basis.x.z],
				"col1": [gti.basis.y.x, gti.basis.y.y, gti.basis.y.z],
				"col2": [gti.basis.z.x, gti.basis.z.y, gti.basis.z.z],
				"origin": [gti.origin.x, gti.origin.y, gti.origin.z]
			}
			var proj_arr: Array = []
			for c_i in range(4):
				var col_p: Vector4 = proj[c_i]
				proj_arr.append([col_p.x, col_p.y, col_p.z, col_p.w])
			var vps: Vector2 = get_viewport().get_visible_rect().size
			var cam_json := {
				"global_transform": basis_dump,
				"global_transform_interpolated": basis_dump_i,
				"projection_columns": proj_arr,
				"fov": cam_dump.fov,
				"keep_aspect": int(cam_dump.keep_aspect),
				"near": cam_dump.near,
				"far": cam_dump.far,
				"viewport": [vps.x, vps.y],
				"ticks_msec": Time.get_ticks_msec()
			}
			var f_cam := FileAccess.open(dossier + "/camera.json", FileAccess.WRITE)
			if f_cam != null:
				f_cam.store_string(JSON.stringify(cam_json))
			var img := get_viewport().get_texture().get_image()
			if img != null:
				img.save_png(dossier + "/viewport.png")
		_sim.demander_dump_occlusion(dossier)
		_dump_demande_gd = false
	if obs_present:
		_sim.rafraichir_buffer_rendu()
		_acc_bascules += _sim.instr_bascules_stable_total()
		_acc_frames += 1
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
