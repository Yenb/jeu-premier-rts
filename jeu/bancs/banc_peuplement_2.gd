extends Node

# BANC DE PEUPLEMENT 2 : JUMEAU indépendant de jeu/bancs/banc_peuplement.gd.
# Monte la même scène d'observation minimale, dépose le même lot d'individus
# errants, mais orchestre par scripts/peuplement_2.gd. Cohabite avec
# l'original : lancer banc_peuplement.tscn ou banc_peuplement_2.tscn met en
# scène deux implémentations comparables au moniteur.
#
# LE BANC TIENT L'ETAT DU POOL. Peuplement_2 est static ; le Dictionary
# retourné par creer_pool est détenu ici, itéré en _physics_process, détruit
# en _exit_tree.
#
# CATEGORIE NOMMEE PAR UN BANC (exception ADN documentée dans CLAUDE.md).
# "mobile_test" et "boite_simple" apparaissent dans data/banc_peuplement_2.json
# et sont lus ici — jamais dans un mécanisme du cœur.
#
# CATALOGUE LOCAL. data/banc_peuplement_2.json surcharge les @export au
# _ready : nombre_individus, type_id, mesh_ref, demi_zone_spawn, graine_rng.
# Aucune autre clé.
#
# ERRANCE. Chaque tick physique, pour chaque individu :
# 1. cap_horloge -= delta ; à <= 0, tirer une nouvelle direction et une
#    nouvelle horloge dans [3, 8] s.
# 2. Poser velocite_desiree_horizontale = direction * proprietes.vitesse.
# 3. Tick.tick_entite(individu, politique_intrinseque, delta, monde, carte).
# 4. Peuplement_2.ecrire_transform(_pool, id).
#
# ECART FRAMEWORK : fichier neuf dans le jeu, jumeau temporaire.

const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const Monde = preload("res://scripts/monde.gd")
const Peuplement_2 = preload("res://scripts/peuplement_2.gd")
const MeshCatalogue = preload("res://scripts/mesh_catalogue.gd")
const Tick = preload("res://scripts/tick.gd")

const CHEMIN_CATALOGUE_LOCAL := "res://data/banc_peuplement_2.json"

@export var nombre_individus: int = 100
@export var type_id: String = "mobile_test"
@export var mesh_ref: String = "boite_simple"
@export var demi_zone_spawn: float = 40.0
@export var graine_rng: int = 20260904

var _pool: Dictionary = {}
var _monde = null
var _carte: Resource = null
var _catalogue: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _errance: Dictionary = {}
var _politique: Callable


func _ready() -> void:
	_charger_reglages_locaux()
	_rng.seed = graine_rng
	_politique = Callable(Tick, "politique_intrinseque")
	_monter_scene()
	_monter_pool()
	_fabriquer_lot()


func _charger_reglages_locaux() -> void:
	if not FileAccess.file_exists(CHEMIN_CATALOGUE_LOCAL):
		return
	var texte := FileAccess.get_file_as_string(CHEMIN_CATALOGUE_LOCAL)
	if texte.is_empty():
		push_warning("banc_peuplement_2 : catalogue local vide (%s)" % CHEMIN_CATALOGUE_LOCAL)
		return
	var donnees = JSON.parse_string(texte)
	if not (donnees is Dictionary):
		push_warning("banc_peuplement_2 : catalogue local invalide (pas un objet)")
		return
	if donnees.has("nombre_individus"):
		nombre_individus = int(donnees.nombre_individus)
	if donnees.has("type_id"):
		type_id = String(donnees.type_id)
	if donnees.has("mesh_ref"):
		mesh_ref = String(donnees.mesh_ref)
	if donnees.has("demi_zone_spawn"):
		demi_zone_spawn = float(donnees.demi_zone_spawn)
	if donnees.has("graine_rng"):
		graine_rng = int(donnees.graine_rng)


func _monter_scene() -> void:
	# CarteTerrain plate au défaut neutre : demi_cote=150, couches_pleines=7,
	# donc sommet = y=12.
	_carte = CarteTerrain.new()

	var sol := MeshInstance3D.new()
	var plan := PlaneMesh.new()
	plan.size = Vector2(600.0, 600.0)
	var mat_sol := StandardMaterial3D.new()
	mat_sol.albedo_color = Color(0.3, 0.3, 0.3)
	plan.material = mat_sol
	sol.mesh = plan
	sol.position = Vector3(0.0, 12.0, 0.0)
	add_child(sol)

	var lumiere := DirectionalLight3D.new()
	lumiere.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	lumiere.light_energy = 1.0
	lumiere.shadow_enabled = false
	add_child(lumiere)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 55.0, 55.0)
	camera.current = true
	camera.add_to_group(&"observateur")
	add_child(camera)
	camera.look_at(Vector3(0.0, 12.0, 0.0), Vector3.UP)


func _monter_pool() -> void:
	_monde = Monde.new()
	_catalogue = _charger_types()

	var catalogue_mesh: Dictionary = MeshCatalogue.charger()
	if not catalogue_mesh.has(mesh_ref):
		push_error("banc_peuplement_2 : mesh_ref '%s' absent de data/mesh.json, aucun rendu possible" % mesh_ref)
		return
	var mesh: Mesh = MeshCatalogue.fabriquer_mesh(catalogue_mesh[mesh_ref])
	if mesh == null:
		push_error("banc_peuplement_2 : MeshCatalogue.fabriquer_mesh('%s') a rendu null" % mesh_ref)
		return

	# Node sans get_world_3d() direct : passer par le Viewport pour le scenario.
	# Taille du pool doublée par précaution pour des spawn/kill dynamiques
	# ultérieurs, alignée sur le patron du banc d'origine.
	_pool = Peuplement_2.creer_pool(nombre_individus * 2, mesh, get_viewport().get_world_3d().scenario)


func _fabriquer_lot() -> void:
	if _pool.is_empty():
		return
	var poses: int = 0
	var tentatives: int = 0
	var plafond_tentatives: int = nombre_individus * 10
	while poses < nombre_individus and tentatives < plafond_tentatives:
		tentatives += 1
		var x: float = _rng.randf_range(-demi_zone_spawn, demi_zone_spawn)
		var z: float = _rng.randf_range(-demi_zone_spawn, demi_zone_spawn)
		var y_sol_v: Variant = _carte.sommet(x, z)
		if y_sol_v == null:
			continue
		# +0.4 = demi-hauteur d'une boite_simple (0.8) ; ce réglage vit dans le
		# banc, jamais dans peuplement_2 (agnostique du mesh).
		var position := Vector3(x, float(y_sol_v) + 0.4, z)
		var id: String = Peuplement_2.spawn(_pool, _catalogue, type_id, position, _monde)
		if id.is_empty():
			push_error("banc_peuplement_2 : Peuplement_2.spawn a echoue a la tentative %d" % tentatives)
			return
		var individu: Dictionary = _pool.individus[_pool.id_to_index[id]]
		var p: Dictionary = individu.proprietes
		p["profil"] = "simple"
		p["cadence_tick"] = 1
		p["velocite"] = Vector3.ZERO
		p["velocite_desiree_horizontale"] = Vector3.ZERO
		p["au_sol"] = false
		p["gravite"] = 18.0
		_errance[id] = {
			"direction": _nouvelle_direction(),
			"cap_horloge": _rng.randf_range(3.0, 8.0),
		}
		poses += 1
	if poses < nombre_individus:
		push_error("banc_peuplement_2 : seulement %d/%d individus poses (%d tentatives)" % [poses, nombre_individus, tentatives])


func _physics_process(delta: float) -> void:
	if _pool.is_empty():
		return
	var individus: Array = _pool.individus
	var errances: Dictionary = _errance
	var politique: Callable = _politique
	var monde = _monde
	var carte = _carte
	for individu in individus:
		var id: String = String(individu.id)
		if not errances.has(id):
			continue
		var etat: Dictionary = errances[id]
		var horloge: float = float(etat.cap_horloge) - delta
		if horloge <= 0.0:
			etat["direction"] = _nouvelle_direction()
			horloge = _rng.randf_range(3.0, 8.0)
		etat["cap_horloge"] = horloge
		var p: Dictionary = individu.proprietes
		var vitesse: float = float(p.get("vitesse", 1.0))
		p["velocite_desiree_horizontale"] = (etat.direction as Vector3) * vitesse
		Tick.tick_entite(individu, politique, delta, monde, carte)
		Peuplement_2.ecrire_transform(_pool, id)


func _nouvelle_direction() -> Vector3:
	var angle: float = _rng.randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))


func _charger_types() -> Dictionary:
	if not FileAccess.file_exists("res://data/types.json"):
		push_error("banc_peuplement_2 : data/types.json introuvable")
		return {}
	var texte := FileAccess.get_file_as_string("res://data/types.json")
	var donnees = JSON.parse_string(texte)
	if not (donnees is Dictionary):
		push_error("banc_peuplement_2 : data/types.json invalide")
		return {}
	return donnees


func _exit_tree() -> void:
	Peuplement_2.detruire_pool(_pool)
