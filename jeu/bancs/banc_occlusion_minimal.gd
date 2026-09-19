# BANC D'OCCLUSION MINIMAL (delta debugging).
#
# N arbres poses en grille, aucune sim, aucun RNG, aucune croissance.
# Isole le test d'occlusion de tout le reste. Instancie SimulationArbre C++
# directement (pas la coquille simulation_arbre.gd) et appelle
# mettre_a_jour_buffers_rendu chaque frame pour exercer le pipeline
# frustum + buffer 2D + hysteresis sur N slots fixes.
#
# Entree : nombre_arbres (@export), un joueur_banc.tscn.
# Sortie : rendu MultiMesh de N arbres + instrumentation occlusion.
# Regle : ne touche aucun fichier existant, ne modifie aucune colonne sim.

extends Node3D

const JoueurBanc = preload("res://jeu/bancs/joueur_banc.gd")

const Y_SOL := 12.0
const ESPACEMENT := 5.0
const CENTRE_X := 10.0
const CENTRE_Z := 0.0

@export var nombre_arbres: int = 2:
	set(v):
		if v == nombre_arbres:
			return
		nombre_arbres = v
		if _sim != null:
			_capacite = v
			_generer_colonnes()
			_sim.invalider_cache_rendu()
			_mm_tronc.instance_count = v
			_mm_feuillage.instance_count = v
			var demi_grille: float = int(ceil(sqrt(float(v)))) * ESPACEMENT * 0.5 + 50.0
			var aabb := AABB(Vector3(CENTRE_X - demi_grille, -5.0, CENTRE_Z - demi_grille), Vector3(demi_grille * 2.0, 100.0, demi_grille * 2.0))
			_noeud_tronc.custom_aabb = aabb
			_noeud_feuillage.custom_aabb = aabb
@export_range(1.0, 3.0, 0.01) var marge_frustum: float = 1.8
@export_range(0.0, 1.0, 0.01) var seuil_couverture: float = 0.39
@export_range(0.0, 10.0, 0.05) var marge_profondeur_m: float = 3.7
@export_range(1, 255, 1) var hysteresis_repos: int = 30
@export_range(1, 60, 1) var hysteresis_min: int = 3
@export_range(0.1, 20.0, 0.1) var vitesse_seuil_lin: float = 3.0
@export_range(0.1, 10.0, 0.1) var vitesse_seuil_ang: float = 1.5
@export_range(0.0, 1.0, 0.01) var anticipation_s: float = 0.15
@export_range(20.0, 1000.0, 1.0) var rayon_rendu_m: float = 223.0

# Colonnes plates (construites dans _ready, jamais mutees apres).
var _capacite: int = 2
var _libres := PackedByteArray()
var _ages := PackedFloat32Array()
var _slot_stade := PackedInt32Array()
var _positions_x := PackedFloat32Array()
var _positions_y := PackedFloat32Array()
var _positions_z := PackedFloat32Array()

# Dimensions par arbre (stade 8 = terminal, valeurs figees).
# Arbre A : tronc h=15 l=3, feuillage h=10 l=8.
# Arbre B : memes dimensions (meme stade), positions differentes.
const HT := 15.0
const LT := 3.0
const HF := 10.0
const LF := 8.0

var _mm_tronc: MultiMesh = null
var _mm_feuillage: MultiMesh = null
var _noeud_tronc: MultiMeshInstance3D = null
var _noeud_feuillage: MultiMeshInstance3D = null

var _sim: RefCounted = null
var _camera_active: bool = false

var _pos_cam_prec: Vector3 = Vector3.ZERO
var _forward_cam_prec: Vector3 = Vector3.FORWARD
var _cam_prec_valide: bool = false
var _n_adaptatif: int = 30

var _dump_demande: bool = false
var _acc_bascules: int = 0
var _acc_frames: int = 0
var _temps_affichage: float = 0.0
const INSTR_INTERVALLE_S := 1.0


func _ready() -> void:
	assert(ClassDB.class_exists("SimulationArbre"),
		"banc_occlusion_minimal : SimulationArbre C++ absente -- DLL non chargee")
	_capacite = nombre_arbres
	_generer_colonnes()
	_monter_scene()
	_monter_multimesh()
	_monter_joueur()
	_monter_sim()


func _generer_colonnes() -> void:
	var n: int = _capacite
	_libres.resize(n)
	_ages.resize(n)
	_slot_stade.resize(n)
	_positions_x.resize(n)
	_positions_y.resize(n)
	_positions_z.resize(n)
	var cote: int = int(ceil(sqrt(float(n))))
	var demi: float = (cote - 1) * ESPACEMENT * 0.5
	var k: int = 0
	for row in range(cote):
		for col in range(cote):
			if k >= n:
				break
			_libres[k] = 0
			_ages[k] = 1.0
			_slot_stade[k] = 8
			_positions_x[k] = CENTRE_X + col * ESPACEMENT - demi
			_positions_y[k] = Y_SOL
			_positions_z[k] = CENTRE_Z + row * ESPACEMENT - demi
			k += 1


func _monter_scene() -> void:
	var sol := MeshInstance3D.new()
	var plan := PlaneMesh.new()
	plan.size = Vector2(200.0, 200.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.3)
	plan.material = mat
	sol.mesh = plan
	sol.position = Vector3(0.0, Y_SOL, 0.0)
	add_child(sol)
	var sol_corps := StaticBody3D.new()
	sol_corps.position = Vector3(0.0, Y_SOL - 0.1, 0.0)
	var sol_col := CollisionShape3D.new()
	var sol_forme := BoxShape3D.new()
	sol_forme.size = Vector3(200.0, 0.2, 200.0)
	sol_col.shape = sol_forme
	sol_corps.add_child(sol_col)
	add_child(sol_corps)
	var lumiere := DirectionalLight3D.new()
	lumiere.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	lumiere.light_energy = 1.0
	lumiere.shadow_enabled = false
	add_child(lumiere)


func _monter_multimesh() -> void:
	# Tronc : cylindre unitaire (h=1, r=0.5).
	var tronc_mesh := CylinderMesh.new()
	tronc_mesh.top_radius = 0.5
	tronc_mesh.bottom_radius = 0.5
	tronc_mesh.height = 1.0
	tronc_mesh.radial_segments = 8
	tronc_mesh.rings = 1
	tronc_mesh.cap_top = false
	tronc_mesh.cap_bottom = true
	var mat_tronc := StandardMaterial3D.new()
	mat_tronc.albedo_color = Color(0.35, 0.22, 0.12)
	mat_tronc.vertex_color_use_as_albedo = true
	tronc_mesh.material = mat_tronc
	_mm_tronc = MultiMesh.new()
	_mm_tronc.transform_format = MultiMesh.TRANSFORM_3D
	_mm_tronc.use_colors = true
	_mm_tronc.mesh = tronc_mesh
	_mm_tronc.instance_count = _capacite
	_noeud_tronc = MultiMeshInstance3D.new()
	_noeud_tronc.multimesh = _mm_tronc
	_noeud_tronc.top_level = true
	_noeud_tronc.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var demi_grille: float = int(ceil(sqrt(float(_capacite)))) * ESPACEMENT * 0.5 + 50.0
	var aabb_arbres := AABB(
		Vector3(CENTRE_X - demi_grille, -5.0, CENTRE_Z - demi_grille),
		Vector3(demi_grille * 2.0, 100.0, demi_grille * 2.0))
	_noeud_tronc.custom_aabb = aabb_arbres
	add_child(_noeud_tronc)
	# Feuillage : cone unitaire (h=1, r_bas=0.5, r_haut=0).
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 8
	cone.rings = 1
	cone.cap_bottom = true
	var mat_f := StandardMaterial3D.new()
	mat_f.albedo_color = Color(0.15, 0.45, 0.2)
	mat_f.vertex_color_use_as_albedo = true
	cone.material = mat_f
	_mm_feuillage = MultiMesh.new()
	_mm_feuillage.transform_format = MultiMesh.TRANSFORM_3D
	_mm_feuillage.use_colors = true
	_mm_feuillage.mesh = cone
	_mm_feuillage.instance_count = _capacite
	_noeud_feuillage = MultiMeshInstance3D.new()
	_noeud_feuillage.multimesh = _mm_feuillage
	_noeud_feuillage.top_level = true
	_noeud_feuillage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_noeud_feuillage.custom_aabb = _noeud_tronc.custom_aabb
	add_child(_noeud_feuillage)


func _monter_joueur() -> void:
	var joueur := JoueurBanc.new()
	joueur.position = Vector3(0.0, Y_SOL + 1.0, -5.0)
	joueur.add_to_group(&"observateur")
	add_child(joueur)


func _monter_sim() -> void:
	_sim = ClassDB.instantiate("SimulationArbre")
	# Tables de stades : 9 stades (indices 0-8), 8 durees.
	# Toutes les durees courtes (0.001) pour que age=1.0 soit terminal.
	# Stade 8 = terminal avec les dimensions voulues.
	var n_stades := 9
	var n_durees := n_stades - 1
	var durees := PackedFloat32Array()
	durees.resize(n_durees)
	for i in range(n_durees):
		durees[i] = 0.001
	var tr_h := PackedFloat32Array()
	var tr_l := PackedFloat32Array()
	var fe_h := PackedFloat32Array()
	var fe_l := PackedFloat32Array()
	tr_h.resize(n_stades)
	tr_l.resize(n_stades)
	fe_h.resize(n_stades)
	fe_l.resize(n_stades)
	for i in range(n_stades):
		tr_h[i] = HT
		tr_l[i] = LT
		fe_h[i] = HF
		fe_l[i] = LF
	var col_tronc := PackedColorArray()
	var col_feuillage := PackedColorArray()
	col_tronc.resize(n_stades)
	col_feuillage.resize(n_stades)
	for i in range(n_stades):
		col_tronc[i] = Color(0.35, 0.22, 0.12)
		col_feuillage[i] = Color(0.15, 0.45, 0.2)
	_sim.initialiser_stable_rendu(
		durees,
		tr_h, tr_l,
		fe_h, fe_l,
		col_tronc, col_feuillage,
		Color(0.35, 0.22, 0.12),
		Color(0.15, 0.45, 0.2),
		Y_SOL
	)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F9:
		_dump_demande = true


func _process(delta: float) -> void:
	if _sim == null:
		return
	_temps_affichage += delta
	if _temps_affichage >= INSTR_INTERVALLE_S:
		_temps_affichage = 0.0
		var res_instr: Dictionary = _dernier_res if _dernier_res != null else {}
		print(
			"bloq=", int(res_instr.get("nb_bloqueurs_camera", 0)),
			" occ=", int(res_instr.get("occultes_2d", 0)),
			" self=", int(res_instr.get("self_occ", 0)),
			" pop=", int(res_instr.get("pop", 0)),
			" bascules_stable=", _acc_bascules,
			" hyst=", _n_adaptatif,
			" antic=", anticipation_s
		)
		_acc_bascules = 0
		_acc_frames = 0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_camera_active = true
	var xf: Transform3D = cam.get_global_transform_interpolated()
	var proj: Projection = cam.get_camera_projection()
	var pos_cam: Vector3 = xf.origin
	var forward_cam: Vector3 = -xf.basis.z
	var v_lin_vec: Vector3 = Vector3.ZERO
	var v_ang: float = 0.0
	if _cam_prec_valide and delta > 0.0:
		v_lin_vec = (pos_cam - _pos_cam_prec) / delta
		var cos_angle: float = clamp(forward_cam.dot(_forward_cam_prec), -1.0, 1.0)
		v_ang = acos(cos_angle) / delta
	var n_adaptatif: int = hysteresis_repos
	if _cam_prec_valide:
		var facteur_lin: float = clamp(v_lin_vec.length() / vitesse_seuil_lin, 0.0, 1.0)
		var facteur_ang: float = clamp(v_ang / vitesse_seuil_ang, 0.0, 1.0)
		var facteur: float = max(facteur_lin, facteur_ang)
		n_adaptatif = int(round(lerp(float(hysteresis_repos), float(hysteresis_min), facteur)))
	var xf_anticipe: Transform3D = xf
	if _cam_prec_valide and anticipation_s > 0.0:
		xf_anticipe.origin = pos_cam + v_lin_vec * anticipation_s
		if v_ang > 0.001:
			var axe: Vector3 = _forward_cam_prec.cross(forward_cam)
			if axe.length_squared() > 1e-8:
				axe = axe.normalized()
				var angle_extra: float = v_ang * anticipation_s
				xf_anticipe.basis = Basis(axe, angle_extra) * xf.basis
	_pos_cam_prec = pos_cam
	_forward_cam_prec = forward_cam
	_cam_prec_valide = true
	_n_adaptatif = n_adaptatif
	_sim.definir_marge_frustum(marge_frustum)
	_sim.definir_seuil_couverture(seuil_couverture)
	_sim.definir_marge_profondeur(marge_profondeur_m)
	_sim.definir_hysteresis_frames(n_adaptatif)
	if _dump_demande:
		var dossier: String = ProjectSettings.globalize_path("res://dumps_occlusion/") \
			+ Time.get_datetime_string_from_system(false, true).replace(":", "-")
		DirAccess.make_dir_recursive_absolute(dossier)
		_sim.demander_dump(dossier)
		_dump_demande = false
	var rayon_carre: float = rayon_rendu_m * rayon_rendu_m
	var res: Dictionary = _sim.mettre_a_jour_buffers_rendu(
		_capacite,
		_libres,
		_ages,
		_slot_stade,
		_positions_x,
		_positions_y,
		_positions_z,
		true,
		rayon_carre,
		_camera_active,
		xf_anticipe,
		proj
	)
	_dernier_res = res
	_acc_bascules += int(res.get("bascules_stable_total", 0))
	_acc_frames += 1
	var pop_i: int = int(res.get("pop", 0))
	if _mm_tronc.instance_count != pop_i:
		_mm_tronc.instance_count = pop_i
	if _mm_feuillage.instance_count != pop_i:
		_mm_feuillage.instance_count = pop_i
	if pop_i > 0:
		_mm_tronc.buffer = res.buffer_tronc
		_mm_feuillage.buffer = res.buffer_feuillage
	_mm_tronc.visible_instance_count = pop_i
	_mm_feuillage.visible_instance_count = pop_i


var _dernier_res: Dictionary = {}
