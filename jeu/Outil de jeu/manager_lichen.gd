extends Node

# BANC "test_ennemi2 Mother box" -- LE MANAGER DE LICHEN. Meme patron que
# manager_herbe.gd, seuls les reglages diffèrent (cube 30 cm, rayon de
# pose 30 cm, seuil de saturation plus lache). Voir CLAUDE.md § « Canevas
# de base des populations massives » pour le pourquoi.
#
# COMPOSE : ChampLichen (champ_lichen.gd) + VisuelLichen (visuel_lichen.gd).

@export var duree_gestation: float = 10.0
@export var duree_vie: float = 60.0
@export var seuil_mere: int = 10
@export var seuil_cible: int = 12
@export var rayon_cases: int = 1
@export var rayon_pose: float = 0.30
@export var y_min: float = 0.0
@export var y_max: float = 30.0

@export var nombre_initial: int = 500
@export var rayon_dispersion: float = 100.0
@export var seed_rng: int = 20261127

var _brins: Array = []
var _rng := RandomNumberGenerator.new()
var _champ: RefCounted = null
var _visuel: Node = null

func _ready() -> void:
	_rng.seed = seed_rng
	for _i in range(5):
		await get_tree().physics_frame
	var noeud_c := get_tree().get_first_node_in_group("champ_lichen")
	if noeud_c != null:
		_champ = noeud_c.champ
	else:
		push_warning("manager_lichen.gd : ChampLichen absent, saturation desactivee")
	_visuel = get_tree().get_first_node_in_group("visuel_lichen")
	if _visuel == null:
		push_warning("manager_lichen.gd : VisuelLichen absent, brins invisibles")
	_semis_initial()

func _semis_initial() -> void:
	if nombre_initial <= 0 or rayon_dispersion <= 0.0:
		return
	var origine := Vector3.ZERO
	var parent := get_parent()
	if parent is Node3D:
		origine = (parent as Node3D).global_position
	for _i in range(nombre_initial):
		var angle := _rng.randf_range(0.0, TAU)
		var rayon := sqrt(_rng.randf()) * rayon_dispersion
		var candidate := origine + Vector3(cos(angle) * rayon, 0.0, sin(angle) * rayon)
		_tenter_ajouter(candidate)

func _process(delta: float) -> void:
	if _brins.is_empty():
		return
	for i in range(_brins.size() - 1, -1, -1):
		var brin: Dictionary = _brins[i]
		brin["age"] = float(brin.age) + delta
		if float(brin.age) >= duree_vie:
			_retirer(i)
			continue
		brin["ecoule"] = float(brin.ecoule) + delta
		if float(brin.ecoule) >= duree_gestation:
			brin["ecoule"] = 0.0
			if _champ != null and _champ.voisins_dans(brin.pos, rayon_cases) >= seuil_mere:
				continue
			_pondre_depuis(brin)

func _pondre_depuis(mere: Dictionary) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var candidate := (mere.pos as Vector3) + Vector3(cos(angle) * rayon_pose, 0.0, sin(angle) * rayon_pose)
	_tenter_ajouter(candidate)

func _tenter_ajouter(candidate: Vector3) -> void:
	var y_sol: Variant = _hauteur_sol_sous(candidate)
	if y_sol == null:
		return
	if float(y_sol) < y_min or float(y_sol) > y_max:
		return
	var pos := Vector3(candidate.x, float(y_sol), candidate.z)
	if _champ != null and _champ.voisins_dans(pos, rayon_cases) >= seuil_cible:
		return
	_ajouter(pos)

func _ajouter(pos: Vector3) -> void:
	var index_v := -1
	if _visuel != null:
		index_v = _visuel.inscrire(pos)
	if _champ != null:
		_champ.inscrire(pos)
	_brins.append({
		"pos": pos,
		"age": 0.0,
		"ecoule": 0.0,
		"index_visuel": index_v,
	})

func _retirer(index: int) -> void:
	var brin: Dictionary = _brins[index]
	if _champ != null:
		_champ.retirer(brin.pos)
	if _visuel != null and int(brin.index_visuel) >= 0:
		_visuel.retirer(int(brin.index_visuel))
	_brins.remove_at(index)

func _hauteur_sol_sous(point: Vector3) -> Variant:
	var espace := get_tree().root.get_world_3d().direct_space_state
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

func compte() -> int:
	return _brins.size()
