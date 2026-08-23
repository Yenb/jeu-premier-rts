# PROTO -- producteur : creature qui extrait l'energie du sol (blocs marron),
# pond un carre rouge des que son cumul atteint le seuil, et se DEPLACE vers
# la case marron pleine la plus proche quand la sienne est vide.
#
# COMPOSITION recopiee de deux patrons du depot :
#   - EXTRACTION + DEPLACEMENT : `_tenter_extraction` + `_choisir_cible` +
#     `_avancer_vers_cible`. Reprise condensee de geniteur_v2.gd, adaptee
#     a un cube 2x2x2 (une seule case sous, pas 3x3). Le sol regenere via
#     ressources_terrain.gd (patron bloc_marron : +2 par 60s).
#   - PONTE : au seuil, instancie CarreRougeScene a un offset lateral fixe
#     et decremente. Recopie condensee de generateur_energie.gd:_faire_pond.

extends RigidBody3D

const CarreRougeScene = preload("res://jeu/Outil de jeu/carre_rouge.tscn")

@export var intervalle_extraction: float = 1.0
@export var quantite_par_tick: float = 1.0
@export var seuil_ponte: float = 5.0
@export var capacite_stock: float = 50.0
@export var offset_carre_rouge: float = 1.5
@export var rayon_detection: float = 30.0
@export var vitesse_sol: float = 3.0
@export var nom_ressource_cible: String = "bloc"

const HAUTEUR_MAX_AU_SOL := 1.5
const TICKS_ROUGE_AVANT_DEPART := 2
const DISTANCE_MIN_CIBLE := 4.0
const ECART_VERTICAL_MAX_CIBLE := 5.0

var _stock: float = 0.0
var _ressources: Node = null
var _timer: Timer
var _ticks_vides: int = 0
var _cible_deplacement: Variant = null
var _grille_connue: GridMap = null
var _cellule_courante: Variant = null

@onready var _barre: MeshInstance3D = get_node_or_null("BarreDeStock/Barre") as MeshInstance3D
var _materiau_barre: ShaderMaterial

# PASSIF : quand `true`, ce noeud ne simule plus rien -- il est juste une
# PEAU visuelle instanciee par manager_proto.gd. Pas de Timer, pas
# d'extraction, pas de deplacement, pas de ponte. Le stock affiche par la
# barre est pousse depuis l'exterieur via set_stock_visuel(). Cf.
# CARNET_DE_JEU.md § COUCHE VISIBLE : le rendu est une couche temporaire,
# la simulation vit dans la donnee.
var _passif: bool = false

func set_passif(valeur: bool) -> void:
	_passif = valeur
	# Peut etre appele APRES _ready (cas du manager qui recupere un
	# producteur existant) : dans ce cas, le Timer et _process ont deja
	# demarre -- il faut les couper explicitement.
	if valeur:
		if _timer != null and is_instance_valid(_timer):
			_timer.stop()
			_timer.queue_free()
			_timer = null
		_cible_deplacement = null
		linear_velocity = Vector3.ZERO
		set_process(false)

func set_stock_visuel(nouveau: float) -> void:
	_stock = nouveau
	_rafraichir_barre()

func _ready() -> void:
	add_to_group("producteur")
	if _barre != null and _barre.mesh != null:
		var mat = _barre.mesh.surface_get_material(0)
		if mat != null:
			_materiau_barre = mat.duplicate() as ShaderMaterial
			_barre.set_surface_override_material(0, _materiau_barre)
			_rafraichir_barre()
	# PASSIF : ne demarre ni Timer d'extraction ni processus de deplacement.
	# La simulation est portee par manager_proto.gd sur la donnee, pas ici.
	if _passif:
		set_process(false)
		return
	_ressources = get_tree().get_first_node_in_group("ressources_terrain")
	if _ressources == null:
		push_warning("producteur.gd : RessourcesTerrain absent, extraction desactivee")
	_timer = Timer.new()
	_timer.wait_time = intervalle_extraction
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(_tenter_extraction)
	add_child(_timer)

func _process(delta: float) -> void:
	_avancer_vers_cible(delta)

func _rafraichir_barre() -> void:
	if _materiau_barre == null:
		return
	_materiau_barre.set_shader_parameter("fraction",
		clampf(_stock / capacite_stock, 0.0, 1.0))

func _avancer_vers_cible(_delta: float) -> void:
	if _cible_deplacement == null:
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	var vers: Vector3 = _cible_deplacement - global_position
	vers.y = 0.0
	if vers.length() <= 1.0:
		_cible_deplacement = null
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	var direction := vers.normalized()
	linear_velocity = Vector3(direction.x * vitesse_sol, linear_velocity.y, direction.z * vitesse_sol)

func _tenter_extraction() -> void:
	if _ressources == null:
		return
	if _cible_deplacement != null:
		return
	var espace := get_world_3d().direct_space_state
	if espace == null:
		return
	var depart := global_position
	var arrivee := depart + Vector3(0, -100.0, 0)
	var requete := PhysicsRayQueryParameters3D.create(depart, arrivee)
	requete.exclude = [get_rid()]
	var frappe: Dictionary = espace.intersect_ray(requete)
	if frappe.is_empty():
		_marquer_tick_vide_sans_grille()
		return
	if not (frappe.collider is GridMap):
		_marquer_tick_vide_sans_grille()
		return
	var grille: GridMap = frappe.collider
	_grille_connue = grille
	if global_position.y - float((frappe.position as Vector3).y) > HAUTEUR_MAX_AU_SOL:
		return
	var point := (frappe.position as Vector3) - (frappe.normal as Vector3) * 0.01
	var cellule := grille.local_to_map(grille.to_local(point))
	_cellule_courante = cellule
	var pris := float(_ressources.preleve(cellule, quantite_par_tick))
	if pris > 0.0:
		_ticks_vides = 0
		_stock = minf(_stock + pris, capacite_stock)
		while _stock >= seuil_ponte:
			_stock -= seuil_ponte
			_pondre()
		_rafraichir_barre()
		return
	_ticks_vides += 1
	if _ticks_vides >= TICKS_ROUGE_AVANT_DEPART:
		_ticks_vides = 0
		_choisir_cible(grille)

func _marquer_tick_vide_sans_grille() -> void:
	_ticks_vides += 1
	if _ticks_vides >= TICKS_ROUGE_AVANT_DEPART:
		_ticks_vides = 0
		if _grille_connue != null:
			_choisir_cible(_grille_connue)

func _choisir_cible(grille: GridMap) -> void:
	var cases: Array[Vector3i] = _ressources.cellules_par_nom_dans_rayon(
		global_position, rayon_detection, nom_ressource_cible)
	var pos_ici := global_position
	for c in cases:
		if _ressources.quantite_a(c) <= 0:
			continue
		if _cellule_courante != null and c == (_cellule_courante as Vector3i):
			continue
		var pos_c := grille.to_global(grille.map_to_local(c))
		if absf(pos_c.y - pos_ici.y) > ECART_VERTICAL_MAX_CIBLE:
			continue
		var dx := pos_c.x - pos_ici.x
		var dz := pos_c.z - pos_ici.z
		if sqrt(dx * dx + dz * dz) < DISTANCE_MIN_CIBLE:
			continue
		_cible_deplacement = pos_c
		return

func _pondre() -> void:
	var cr := CarreRougeScene.instantiate() as Node3D
	var pose: Vector3 = global_position + global_transform.basis.x * offset_carre_rouge
	cr.position = pose
	var accueil := get_parent()
	if accueil != null:
		accueil.add_child(cr)
