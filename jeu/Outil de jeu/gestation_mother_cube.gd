extends Node3D

# BANC "test_ennemi2 Mother box" -- LE GENITEUR pond UNE mother cube (voir
# mother_cube.gd) des que TROIS conditions sont reunies :
#   1. Prerequis : `prerequis_generateurs` generateurs d'energie deja
#      vivants (par defaut 4 -- ceux pondus par gestation_energie.gd).
#   2. Stock du geniteur >= `seuil_ponte` (par defaut 100).
#   3. Aucune mother cube encore en vie (max_vivants = 1 par defaut).
# Coute `cout_ponte` (100) a la naissance ; si le spawn echoue, aucun
# debit -- meme convention que gestation_energie.gd / gestation_stock.gd.
#
# COMPOSE gestation.gd DU FRAMEWORK -- meme patron que gestation_energie.gd
# et gestation_stock.gd. Trois gates au lieu de deux (prerequis en plus).
#
# COMPTE VIVANTES PAR GROUPE, PAS PAR REFERENCE : chaque mother cube
# s'inscrit dans "mother_cube" a son _ready. Une mort automatique
# (queue_free) la retire du groupe, la prochaine ponte redeviendra
# possible. Meme patron bus/group que gestation_energie.gd.
#
# LA NOUVELLE MOTHER CUBE EST POSEE COMME FRERE du geniteur, pas enfant :
# un enfant meurt avec son parent. La mother cube doit survivre au
# geniteur.
#
# POSITION DE PONTE : couronne autour du geniteur, essais_max angles
# repartis, rayon [rayon_pose_min, rayon_pose_max]. Meme algo que
# gestation_energie.gd (intersect_shape, exclusions par RID). Si aucune
# place libre autour -> ponte echoue, geniteur prie de bouger.

const Gestation = preload("res://scripts/gestation.gd")
const CHEMIN_SCENE := "res://jeu/Outil de jeu/mother_cube.tscn"

# PARAMETRES DE GESTATION -- exportes pour reglage dans l'inspecteur du
# noeud enfant du geniteur (meme convention que gestation_energie.gd).
@export var seuil_ponte: float = 100.0
@export var duree_gestation: float = 60.0
@export var cout_ponte: float = 100.0
@export var max_vivants: int = 1
@export var prerequis_generateurs: int = 4
# COURONNE : la mother cube fait 0.30 m, un rayon plus petit que pour les
# generateurs (6-8 m) suffit -- 3-4 m garde la mother cube pres du geniteur
# mais dehors de son collider 6x6.
@export var rayon_pose_min: float = 3.5
@export var rayon_pose_max: float = 4.5
@export var essais_max: int = 8

const REF_REPRODUCTION := "mother_cube"
const NOM_GROUPE_VIVANTES := "mother_cube"
const NOM_GROUPE_PREREQUIS := "generateur_energie"
# HAUTEUR_CENTRE_CUBE = 0.15 : mother cube 0.30 m centree, face basse a
# -0.15. Poser sur le sol -> global_position.y = sol_y + 0.15.
const HAUTEUR_CENTRE_CUBE := 0.15

static var _prochaine_graine := 20261225
var _rng := RandomNumberGenerator.new()

var _catalogue: Dictionary
var _mere: Dictionary
var _geniteur: Node = null
# UNE SEULE MOTHER CUBE DANS LA VIE DU GENITEUR. max_vivants=1 seul ne
# suffit pas : si la mother cube meurt, une nouvelle serait pondue (le
# groupe se vide). Ce flag une-fois-passe-a-true bloque toute nouvelle
# gestation, definitivement, meme apres la mort de la mother cube. Regle
# gameplay explicitement demandee par Yael.
var _a_pondu_mother_cube: bool = false

func _ready() -> void:
	_rng.seed = _prochaine_graine
	_prochaine_graine += 1
	_geniteur = get_parent()
	if _geniteur == null:
		push_error("gestation_mother_cube.gd : aucun parent -- doit etre enfant du geniteur")
		return
	if not _geniteur.has_method("stock_courant") or not _geniteur.has_method("retirer_stock"):
		push_error("gestation_mother_cube.gd : le parent n'expose pas stock_courant()/retirer_stock() -- pas le bon type de parent ?")
		return

	_catalogue = {REF_REPRODUCTION: {"duree_gestation": duree_gestation}}
	_mere = {
		"id": str(_geniteur.get_instance_id()),
		"proprietes": {"reproduction_ref": REF_REPRODUCTION},
	}

	var minuteur := Timer.new()
	minuteur.wait_time = 1.0
	minuteur.one_shot = false
	minuteur.autostart = true
	minuteur.timeout.connect(_tick)
	add_child(minuteur)

func _tick() -> void:
	if _geniteur == null or not is_instance_valid(_geniteur):
		return
	# 0. GATE VIE-ENTIERE : une seule mother cube pondue par geniteur,
	# jamais deux, meme si la premiere meurt. Une gestation deja entamee
	# reste en place (aucun sens de l'abandonner ici puisque cet etat
	# vient d'apres la premiere ponte, ce qui ne peut arriver).
	if _a_pondu_mother_cube:
		return

	var vivantes: int = get_tree().get_nodes_in_group(NOM_GROUPE_VIVANTES).size()
	# 1. GATE MAX_VIVANTES : une mother cube deja en vie -> pas d'autre.
	# Une gestation en cours est abandonnee (patron gestation_energie).
	if vivantes >= max_vivants:
		if _mere.proprietes.has("gestation"):
			_mere.proprietes.erase("gestation")
		return

	# 2. GATE PREREQUIS : il faut au moins prerequis_generateurs
	# generateurs d'energie vivants avant de pondre la mother cube.
	# Sans ce gate, la mother cube pourrait naitre avant les generateurs
	# et le contrat de gameplay ne serait pas respecte.
	var generateurs: int = get_tree().get_nodes_in_group(NOM_GROUPE_PREREQUIS).size()
	if generateurs < prerequis_generateurs:
		if _mere.proprietes.has("gestation"):
			_mere.proprietes.erase("gestation")
		return

	var stock: float = float(_geniteur.stock_courant())
	# 3. GATE STOCK : sous le seuil, rien a faire. Une gestation deja
	# entamee reste en place (patron gestation_energie).
	if stock < seuil_ponte and not _mere.proprietes.has("gestation"):
		return

	# 4. ENTAMER LA GESTATION AU FRANCHISSEMENT.
	if not _mere.proprietes.has("gestation"):
		Gestation.poser(_mere, null, _catalogue)

	# 5. AVANCER D'UNE SECONDE.
	Gestation.avancer(_mere, _catalogue, 1.0)

	# 6. NAISSANCE PRETE : pondre, retirer la gestation, payer le cout.
	var gestation: Dictionary = _mere.proprietes.get("gestation", {})
	if gestation.get("naissance_prete", false):
		_mere.proprietes.erase("gestation")
		if _pondre_une_mother_cube():
			_geniteur.retirer_stock(cout_ponte)
			_a_pondu_mother_cube = true  # une seule pour toujours

func _pondre_une_mother_cube() -> bool:
	var accueil := _geniteur.get_parent()
	if accueil == null:
		push_error("gestation_mother_cube.gd : aucun contenant pour poser la mother cube (geniteur sans parent ?)")
		return false
	var scene: PackedScene = load(CHEMIN_SCENE)
	if scene == null:
		push_error("gestation_mother_cube.gd : impossible de charger %s" % CHEMIN_SCENE)
		return false
	var geniteur3d := _geniteur as Node3D
	if geniteur3d == null:
		return false
	var pose_libre: Variant = _chercher_pose_libre(geniteur3d)
	if pose_libre == null:
		if _geniteur.has_method("chercher_nouvelle_cible"):
			_geniteur.chercher_nouvelle_cible()
		return false
	var nouveau := scene.instantiate() as Node3D
	accueil.add_child(nouveau)
	nouveau.global_position = pose_libre as Vector3
	return true

# Cherche un emplacement libre pour la mother cube. Meme algo que
# gestation_energie.gd:_chercher_pose_libre (couronne random autour, sol
# par raycast, intersect_shape pour verifier libre, GridMap tolere). Les
# exclusions couvrent le geniteur, les generateurs d'energie ET les
# mother cubes existantes -- une nouvelle mother cube ne doit pas etre
# rejetee a cause d'une ancienne (meme si max_vivants=1 rend ce cas rare
# aujourd'hui, le code doit rester coherent si max_vivants monte).
func _chercher_pose_libre(geniteur3d: Node3D) -> Variant:
	var espace: PhysicsDirectSpaceState3D = geniteur3d.get_world_3d().direct_space_state
	if espace == null:
		return null
	var exclusions: Array = _exclusions_communes()
	var forme := BoxShape3D.new()
	forme.size = Vector3(0.3, 0.3, 0.3)
	var decalage: float = _rng.randf_range(0.0, TAU)
	for i in essais_max:
		var angle: float = decalage + float(i) * TAU / float(essais_max)
		var rayon: float = _rng.randf_range(rayon_pose_min, rayon_pose_max)
		var xz := geniteur3d.global_position + Vector3(cos(angle) * rayon, 0.0, sin(angle) * rayon)
		var y_sol: Variant = _hauteur_sol_sous(xz, espace, exclusions)
		if y_sol == null:
			continue
		var candidat := Vector3(xz.x, float(y_sol) + HAUTEUR_CENTRE_CUBE, xz.z)
		if _pose_libre(forme, candidat, espace, exclusions):
			return candidat
	return null

func _exclusions_communes() -> Array:
	var ex: Array = []
	var geniteur_co := _geniteur as CollisionObject3D
	if geniteur_co != null:
		ex.append(geniteur_co.get_rid())
	for autre in get_tree().get_nodes_in_group(NOM_GROUPE_PREREQUIS):
		var co := autre as CollisionObject3D
		if co != null:
			ex.append(co.get_rid())
	for autre in get_tree().get_nodes_in_group(NOM_GROUPE_VIVANTES):
		var co := autre as CollisionObject3D
		if co != null:
			ex.append(co.get_rid())
	return ex

func _hauteur_sol_sous(point: Vector3, espace: PhysicsDirectSpaceState3D, exclusions: Array) -> Variant:
	var depart := point + Vector3(0, 100.0, 0)
	var arrivee := point + Vector3(0, -100.0, 0)
	var requete := PhysicsRayQueryParameters3D.create(depart, arrivee)
	requete.exclude = exclusions
	var frappe: Dictionary = espace.intersect_ray(requete)
	if frappe.is_empty():
		return null
	if not (frappe.collider is GridMap):
		return null
	return (frappe.position as Vector3).y

func _pose_libre(forme: BoxShape3D, candidat: Vector3, espace: PhysicsDirectSpaceState3D, exclusions: Array) -> bool:
	var requete := PhysicsShapeQueryParameters3D.new()
	requete.shape = forme
	requete.transform = Transform3D(Basis(), candidat)
	requete.exclude = exclusions
	var contacts: Array = espace.intersect_shape(requete, 4)
	for c in contacts:
		if not (c.collider is GridMap):
			return false
	return true
