extends RigidBody3D

# BANC "test_ennemi2 Mother box" -- LE GENITEUR. Machine 6x6x6 (3 cases
# GridMap) qui tombe du ciel, extrait la ressource des 9 cases marrons
# sous son emprise, et se DEPLACE au sol vers une nouvelle zone marron
# quand la sienne est epuisee. Meme pattern de deplacement horizontal
# que soldat.gd (avance sur X/Z, la gravite maintient au sol).
#
# COMPORTEMENT :
#  A. Extraction locale : un raycast central trouve la cellule sous le
#     geniteur ; les 9 cellules autour (3x3) sont prelevees a chaque
#     tick, `quantite_par_case` unites chacune.
#  B. Detection : `chercher_cases_marrons()` interroge RessourcesTerrain
#     pour lister les cases marrons dans `rayon_detection`, triees par
#     distance croissante.
#  C. Deplacement : quand le tick d'extraction n'a rien pris (toutes les
#     cases sous lui sont a zero), le geniteur cherche la case marron la
#     plus proche AYANT du stock et se met a `_cible_deplacement`. Dans
#     `_process`, il avance en LIGNE DROITE horizontale a `vitesse_sol`
#     m/s. La gravite du RigidBody3D le maintient au sol pendant le
#     deplacement -- pas de vol, pas de teleportation.
#
# FEEDBACK VISUEL : un decal PlaneMesh 6x6 sous le geniteur (nœud
# ZoneExtraction) montre visuellement les 9 cellules d'emprise. VERT
# quand extraction en cours, ROUGE quand rien a pris (signal "je vais
# bouger"). Materiau `no_depth_test = true` pour s'afficher par-dessus
# la Base opaque.

@export var capacite: int = 300
@export var intervalle_extraction: float = 3.0
@export var quantite_par_case: int = 1
@export var rayon_detection: float = 30.0
@export var nom_ressource_cible: String = "bloc"
@export var vitesse_sol: float = 3.0

const COULEUR_ACTIVE := Color(0.2, 0.9, 0.25, 0.35)
const COULEUR_EMISSION_ACTIVE := Color(0.2, 0.9, 0.25, 1.0)
const COULEUR_VIDE := Color(0.9, 0.15, 0.15, 0.4)
const COULEUR_EMISSION_VIDE := Color(0.9, 0.15, 0.15, 1.0)
# DELAI ROUGE AVANT DEPLACEMENT : le decal reste rouge pendant N ticks
# consecutifs sans extraction avant que le geniteur ne se mette en marche.
# Sans ce delai, le rouge apparait 1 frame puis disparait.
const TICKS_ROUGE_AVANT_DEPART := 2

var _stock: float = 0.0
var _ressources: Node = null
var _timer: Timer
var _ticks_vides: int = 0
# _cible_deplacement : null = immobile, Vector3 = position monde a atteindre.
var _cible_deplacement: Variant = null
@onready var _zone: MeshInstance3D = $ZoneExtraction
var _zone_material: StandardMaterial3D
@onready var _barre_stock: MeshInstance3D = $BarreDeStock/Barre
var _materiau_stock: ShaderMaterial

func _ready() -> void:
	add_to_group("geniteur")
	_ressources = get_tree().get_first_node_in_group("ressources_terrain")
	if _ressources == null:
		push_warning("geniteur.gd : RessourcesTerrain absent, extraction desactivee")
	# DUPLIQUE materiaux (decal + barre) pour ne pas partager entre plusieurs
	# geniteurs -- teindre l'un ne teint pas les autres.
	_zone_material = _zone.mesh.surface_get_material(0).duplicate()
	_zone.set_surface_override_material(0, _zone_material)
	_materiau_stock = _barre_stock.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_stock.set_surface_override_material(0, _materiau_stock)
	_materiau_stock.set_shader_parameter("fraction", 0.0)
	_teindre_zone(true)

	_timer = Timer.new()
	_timer.wait_time = intervalle_extraction
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(_tenter_extraction)
	add_child(_timer)

func _process(delta: float) -> void:
	_avancer_vers_cible(delta)

# Deplacement horizontal a vitesse constante vers _cible_deplacement.
# Applique une velocite horizontale au RigidBody, la gravite gere Y.
# Meme pattern que soldat.gd:_faire_vers_joueur.
func _avancer_vers_cible(_delta: float) -> void:
	if _cible_deplacement == null:
		# Immobile : stopper toute derive horizontale residuelle.
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	var vers: Vector3 = _cible_deplacement - global_position
	vers.y = 0.0
	if vers.length() <= 1.0:
		# Arrive.
		_cible_deplacement = null
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	var direction := vers.normalized()
	linear_velocity = Vector3(direction.x * vitesse_sol, linear_velocity.y, direction.z * vitesse_sol)

func _tenter_extraction() -> void:
	if _ressources == null:
		return
	# EN MOUVEMENT VOLONTAIRE vers une cible : pas d'extraction. Pas de
	# check de linear_velocity : un RigidBody3D pose garde une velocite
	# residuelle (~-2.7 m/s en Y) due au contact continu avec le sol qui
	# annule la gravite. Tester la velocity bloquait definitivement
	# l'extraction (mesure : _ticks_vides restait a 0 apres vidage).
	if _cible_deplacement != null:
		return
	var espace := get_world_3d().direct_space_state
	if espace == null:
		return
	# UN SEUL raycast central pour trouver la cellule sous le geniteur,
	# puis extraction des 9 cellules autour dans la grille. Independant
	# de l'alignement du geniteur sur la grille (voir memoire :
	# alignement objet, pas grille).
	var pt := global_position
	var arrivee := pt + Vector3(0, -100.0, 0)
	var requete := PhysicsRayQueryParameters3D.create(pt, arrivee)
	requete.exclude = [get_rid()]
	var frappe: Dictionary = espace.intersect_ray(requete)
	if frappe.is_empty():
		return
	if not (frappe.collider is GridMap):
		return
	var grille: GridMap = frappe.collider
	var point := (frappe.position as Vector3) - (frappe.normal as Vector3) * 0.01
	var cellule_centre := grille.local_to_map(grille.to_local(point))

	var pris_total := 0.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cellule := cellule_centre + Vector3i(dx, 0, dz)
			var pris := float(_ressources.preleve(cellule, float(quantite_par_case)))
			pris_total += pris
			if _stock + pris_total >= float(capacite):
				break
		if _stock + pris_total >= float(capacite):
			break
	_stock = minf(_stock + pris_total, float(capacite))
	_materiau_stock.set_shader_parameter("fraction", _stock / float(capacite))
	_teindre_zone(pris_total > 0.0)

	# ETAPE C : si RIEN pris ET stock non plein, on compte les ticks
	# vides. Apres N ticks consecutifs a zero (le rouge est reste visible
	# assez longtemps pour etre lu), on choisit une nouvelle cible sol.
	if pris_total > 0.0:
		_ticks_vides = 0
	elif _stock < float(capacite):
		_ticks_vides += 1
		if _ticks_vides >= TICKS_ROUGE_AVANT_DEPART:
			_ticks_vides = 0
			_choisir_cible(grille)

func _choisir_cible(grille: GridMap) -> void:
	var cases := chercher_cases_marrons()
	for c in cases:
		if _ressources.quantite_a(c) <= 0:
			continue
		_cible_deplacement = grille.to_global(grille.map_to_local(c))
		return

func _teindre_zone(active: bool) -> void:
	if _zone_material == null:
		return
	if active:
		_zone_material.albedo_color = COULEUR_ACTIVE
		_zone_material.emission = COULEUR_EMISSION_ACTIVE
	else:
		_zone_material.albedo_color = COULEUR_VIDE
		_zone_material.emission = COULEUR_EMISSION_VIDE

# API publique pour affichage / logique future.
func stock_courant() -> float:
	return _stock

# API publique -- rend les cellules de type `nom_ressource_cible` dans
# le rayon de detection, triees par distance croissante.
func chercher_cases_marrons() -> Array[Vector3i]:
	if _ressources == null:
		return []
	return _ressources.cellules_par_nom_dans_rayon(
		global_position, rayon_detection, nom_ressource_cible)
