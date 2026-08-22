extends Node3D

# BANC "test_ennemi2 Mother box" -- LE LICHEN : ressource primitive qui
# pousse en aplats plus larges et plus rapides que l'herbe, moins dense
# localement. Meme patron que cube_herbe.gd, seules les valeurs changent.
#
# COMPTAGE DES VOISINS PAR CHAMP SCALAIRE (voir champ_spatial.gd,
# champ_lichen.gd, CLAUDE.md § LOCALITE SPATIALE). Aucune requete de
# voisinage, aucune Area3D, aucune liste. Le monde tient un champ
# `case -> densite` maintenu a jour aux naissances et morts. La saturation
# est une simple lecture.

const Gestation = preload("res://scripts/gestation.gd")
const CHEMIN_SCENE := "res://jeu/Outil de jeu/cube_lichen.tscn"

@export var duree_gestation: float = 10.0
@export var duree_vie: float = 60.0
@export var seuil_voisins: int = 12
@export var rayon_cases: int = 1
@export var rayon_pose: float = 0.30
@export var y_min: float = -1000.0
@export var y_max: float = 1000.0
@export var age_initial: float = 0.0

const GROUPE := "lichen"

static var _prochaine_graine := 20261122
var _rng := RandomNumberGenerator.new()
var _champ: RefCounted = null
var _visuel: Node = null
var _index_visuel: int = -1
var _timer_ponte: Timer
var _timer_mort: Timer

func _ready() -> void:
	add_to_group(GROUPE)
	_rng.seed = _prochaine_graine
	_prochaine_graine += 1

	var noeud_champ := get_tree().get_first_node_in_group("champ_lichen")
	if noeud_champ != null:
		_champ = noeud_champ.champ
		_champ.inscrire(global_position)

	_visuel = get_tree().get_first_node_in_group("visuel_lichen")
	if _visuel != null:
		_index_visuel = _visuel.inscrire(global_position)

	_timer_mort = Timer.new()
	_timer_mort.wait_time = maxf(0.1, duree_vie - age_initial)
	_timer_mort.one_shot = true
	_timer_mort.autostart = true
	_timer_mort.timeout.connect(_mourir)
	add_child(_timer_mort)

	_timer_ponte = Timer.new()
	_timer_ponte.wait_time = duree_gestation
	_timer_ponte.one_shot = false
	_timer_ponte.autostart = true
	_timer_ponte.timeout.connect(_tenter_ponte)
	add_child(_timer_ponte)

func _tenter_ponte() -> void:
	_pondre()

func _pondre() -> void:
	# CONTRAINTE SUR L'ENDROIT DE POSE, pas sur la mere (voir cube_herbe.gd).
	var angle := _rng.randf_range(0.0, TAU)
	var candidate := global_position + Vector3(cos(angle) * rayon_pose, 0.0, sin(angle) * rayon_pose)
	if _champ != null and _champ.voisins_dans(candidate, rayon_cases) >= seuil_voisins:
		return
	var y_sol: Variant = _hauteur_sol_sous(candidate)
	if y_sol == null:
		return
	if float(y_sol) < y_min or float(y_sol) > y_max:
		return

	var accueil := get_parent()
	if accueil == null:
		return
	var scene: PackedScene = load(CHEMIN_SCENE)
	if scene == null:
		return
	var nouveau := scene.instantiate() as Node3D
	# POSITION POSEE AVANT add_child (voir semeur.gd, meme piege).
	nouveau.position = Vector3(candidate.x, float(y_sol), candidate.z)
	accueil.add_child(nouveau)

func _hauteur_sol_sous(point: Vector3) -> Variant:
	# Raycast restreint au GridMap (voir semeur.gd, meme piege : la Hitbox
	# du personnage pose le bebe a sa hauteur au lieu du sol -- cubes
	# flottants "dans le ciel").
	var espace := get_world_3d().direct_space_state
	if espace == null:
		return null
	var depart := point + Vector3(0.0, 1000.0, 0.0)
	var arrivee := point + Vector3(0.0, -1000.0, 0.0)
	var requete := PhysicsRayQueryParameters3D.create(depart, arrivee)
	var frappe := espace.intersect_ray(requete)
	if frappe.is_empty():
		return null
	if not (frappe.collider is GridMap):
		return null
	return (frappe.position as Vector3).y

func _mourir() -> void:
	if _champ != null:
		_champ.retirer(global_position)
	if _visuel != null:
		_visuel.retirer(_index_visuel)
	queue_free()
