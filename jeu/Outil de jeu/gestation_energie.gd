extends Node3D

# BANC "test_ennemi2 Mother box" -- LE GENITEUR OBSERVE SON PROPRE STOCK
# et pond un generateur d'energie (voir generateur_energie.gd) des que
# stock >= seuil_ponte ET nombre de vivants < max_vivants. Coute
# `cout_ponte` unites de stock a la naissance ; si le generateur meurt
# pendant la gestation, le cout n'a pas ete debite (patron
# gestation_stock.gd).
#
# COMPOSE gestation.gd DU FRAMEWORK -- meme patron que gestation_stock.gd
# et garde_transporteurs.gd. Deux gates specifiques ici : STOCK SUFFISANT
# et MAX_VIVANTS non atteint. Meme mecanisme framework, deux gates
# differentes. Rien de neuf ecrit sur "compter le temps" ou "declencher
# au seuil".
#
# COMPTE LES VIVANTS PAR GROUPE, PAS PAR REFERENCE : chaque generateur
# s'inscrit dans "generateur_energie" a son _ready. On lit la taille du
# groupe, jamais un tableau interne -- si un generateur meurt (queue_free),
# il quitte le groupe automatiquement. Le prochain tick voit le trou et
# relance la ponte. Meme patron bus/group que le CLAUDE.md interdit
# explicitement de contourner par des signal+connect par instance.
#
# LE NOUVEAU GENERATEUR EST POSE COMME FRERE du geniteur, pas enfant : un
# enfant meurt avec son parent (queue_free en cascade). Un enfant de la
# genese ne doit pas s'evanouir quand son geniteur meurt.
#
# POSITION DE PONTE = X/Z du geniteur (colonne verticale de sa position),
# Y RESOLU PAR RAYCAST vers le bas pour poser le generateur sur le sol.
# Sans raycast, le generateur (StaticBody3D) apparait au centre du geniteur
# (Y ~= 17) et reste flottant a 2.5 m au-dessus du sol -- contrainte Yael
# revisee apres capture d'ecran. Le raycast exclut le geniteur pour ne
# pas frapper son propre collider.
# HAUTEUR_CENTRE_CUBE = 0.5 : le generateur est un cube 1x1x1 centre en
# (0,0,0). Sa face basse est a y_local = -0.5, donc pour poser la face
# basse sur le sol : global_position.y = frappe.position.y + 0.5.
const HAUTEUR_CENTRE_CUBE := 0.5

const Gestation = preload("res://scripts/gestation.gd")
# LA SCENE DU GENERATEUR EST CHARGEE A LA DEMANDE, jamais en preload :
# meme raison que gestation_stock.gd -- Godot 4.7 refuse le cycle strict
# quand une modif ailleurs declenche un rescan (Parse Error: Busy).
const CHEMIN_SCENE := "res://jeu/Outil de jeu/generateur_energie.tscn"

# PARAMETRES DE GESTATION -- exportes pour que Yael les regle dans
# l'inspecteur, directement sur le nœud enfant du geniteur.
@export var seuil_ponte: float = 20.0
@export var duree_gestation: float = 20.0
@export var cout_ponte: float = 20.0
@export var max_vivants: int = 4
# ANNEAU DE PONTE : les candidats sont tires en couronne autour du geniteur,
# 8 angles regulierement repartis, rayon random dans [min, max]. Meme
# principe que cube_herbe.gd:_pondre (angle random autour, teste si libre),
# adapte au geniteur (peu d'individus -> pas de champ scalaire, on utilise
# intersect_shape physique). Si aucun des 8 candidats n'est libre, la
# ponte echoue silencieusement ET le geniteur est prie de bouger --
# apres un deplacement, une nouvelle couronne est teste au tick suivant.
@export var rayon_pose_min: float = 6.0
@export var rayon_pose_max: float = 8.0
@export var essais_max: int = 8

const REF_REPRODUCTION := "generateur_energie"
const NOM_GROUPE_VIVANTS := "generateur_energie"

# RNG SEEDE (regle CLAUDE.md : aucun hasard non-seede). Meme patron que
# gestation_stock.gd : chaque instance recoit sa propre graine incrementale.
static var _prochaine_graine := 20260930
var _rng := RandomNumberGenerator.new()

var _catalogue: Dictionary
var _mere: Dictionary
var _geniteur: Node = null

func _ready() -> void:
	_rng.seed = _prochaine_graine
	_prochaine_graine += 1
	_geniteur = get_parent()
	if _geniteur == null:
		push_error("gestation_energie.gd : aucun parent -- doit etre enfant du geniteur")
		return
	# Contrat : le geniteur expose stock_courant() (lecture) et
	# retirer_stock(quantite) (mutation). Verifie a chaud, une seule fois.
	if not _geniteur.has_method("stock_courant") or not _geniteur.has_method("retirer_stock"):
		push_error("gestation_energie.gd : le parent n'expose pas stock_courant()/retirer_stock() -- pas le bon type de parent ?")
		return

	_catalogue = {REF_REPRODUCTION: {"duree_gestation": duree_gestation}}
	# LE GENITEUR AGIT COMME "MERE" au sens de reproduction. Aucune
	# gestation n'est posee ici tant que les deux gates ne sont pas
	# franchies.
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

	var stock: float = float(_geniteur.stock_courant())
	var vivants: int = get_tree().get_nodes_in_group(NOM_GROUPE_VIVANTS).size()

	# 1. GATE MAX_VIVANTS : au-dessus, on bloque, meme si une gestation
	# est deja entamee (on l'annule pour ne pas depenser du stock au
	# moment de la naissance dans un slot inexistant). Symetrique au
	# gele du mode_combat dans gestation_stock.gd.
	if vivants >= max_vivants:
		if _mere.proprietes.has("gestation"):
			_mere.proprietes.erase("gestation")
		return

	# 2. GATE STOCK : sous le seuil, rien a faire. Une gestation deja
	# entamee reste en place (stock a pu redescendre entre-temps, on ne
	# casse pas ce qui a demarre -- meme convention que gestation_stock).
	if stock < seuil_ponte and not _mere.proprietes.has("gestation"):
		return

	# 3. ENTAMER LA GESTATION AU FRANCHISSEMENT, pas avant.
	if not _mere.proprietes.has("gestation"):
		Gestation.poser(_mere, null, _catalogue)

	# 4. AVANCER D'UNE SECONDE, meme rythme que le Timer.
	Gestation.avancer(_mere, _catalogue, 1.0)

	# 5. NAISSANCE PRETE : pondre, retirer la gestation, payer le cout.
	var gestation: Dictionary = _mere.proprietes.get("gestation", {})
	if gestation.get("naissance_prete", false):
		_mere.proprietes.erase("gestation")
		if _pondre_un_generateur():
			# LE COUT SE PAIE ICI, jamais avant : voir en-tete. Si le
			# spawn a echoue (contenant nul), on ne debite pas.
			_geniteur.retirer_stock(cout_ponte)

func _pondre_un_generateur() -> bool:
	var accueil := _geniteur.get_parent()
	if accueil == null:
		push_error("gestation_energie.gd : aucun contenant pour poser le generateur (geniteur sans parent ?)")
		return false
	var scene: PackedScene = load(CHEMIN_SCENE)
	if scene == null:
		push_error("gestation_energie.gd : impossible de charger %s" % CHEMIN_SCENE)
		return false
	var geniteur3d := _geniteur as Node3D
	if geniteur3d == null:
		return false
	# Cherche une pose libre dans la couronne autour du geniteur. Aucune
	# place libre apres essais_max angles -> la ponte echoue silencieusement
	# ET le geniteur est prie de bouger vers une nouvelle case marron.
	# Meme principe que cube_herbe.gd:_pondre (angle, teste si libre,
	# sinon rien) -- outil de test different (intersect_shape physique,
	# adapte a peu d'individus, au lieu du champ scalaire de l'herbe).
	var pose_libre: Variant = _chercher_pose_libre(geniteur3d)
	if pose_libre == null:
		if _geniteur.has_method("chercher_nouvelle_cible"):
			_geniteur.chercher_nouvelle_cible()
		return false
	var nouveau := scene.instantiate() as Node3D
	accueil.add_child(nouveau)
	nouveau.global_position = pose_libre as Vector3
	return true

# Cherche un emplacement libre pour le generateur autour du geniteur.
# Rend Vector3 (pose trouvee) ou null (aucune place libre apres essais_max).
# essais_max angles regulierement repartis, rayon random dans [min, max]
# (patron gestation_stock.gd). Chaque candidat : raycast au sol pour la Y,
# puis intersect_shape pour verifier qu'aucun objet ne bloque.
func _chercher_pose_libre(geniteur3d: Node3D) -> Variant:
	var espace: PhysicsDirectSpaceState3D = geniteur3d.get_world_3d().direct_space_state
	if espace == null:
		return null
	var exclusions: Array = _exclusions_communes()
	var forme := BoxShape3D.new()
	forme.size = Vector3(1, 1, 1)
	for i in essais_max:
		var angle: float = float(i) * TAU / float(essais_max)
		var rayon: float = _rng.randf_range(rayon_pose_min, rayon_pose_max)
		var xz := geniteur3d.global_position + Vector3(cos(angle) * rayon, 0.0, sin(angle) * rayon)
		var y_sol: Variant = _hauteur_sol_sous(xz, espace, exclusions)
		if y_sol == null:
			continue
		var candidat := Vector3(xz.x, float(y_sol) + HAUTEUR_CENTRE_CUBE, xz.z)
		if _pose_libre(forme, candidat, espace, exclusions):
			return candidat
	return null

# RIDs a exclure du raycast et du test de forme : le geniteur (RigidBody3D)
# et tous les generateurs deja nes (RigidBody3D). Sans exclure, le raycast
# frappe le toit d'un ancien generateur (observe le 2026-08-22, ponte 2
# Y=15.5 au lieu de Y=14.5) et intersect_shape declare "occupe" a cause du
# geniteur lui-meme.
func _exclusions_communes() -> Array:
	var ex: Array = []
	var geniteur_co := _geniteur as CollisionObject3D
	if geniteur_co != null:
		ex.append(geniteur_co.get_rid())
	for autre in get_tree().get_nodes_in_group(NOM_GROUPE_VIVANTS):
		var autre_co := autre as CollisionObject3D
		if autre_co != null:
			ex.append(autre_co.get_rid())
	return ex

# Rend la Y de la GridMap sous `point`, ou null si le raycast rate ou ne
# frappe pas de GridMap (bord de carte, trou). Meme patron que
# semeur.gd:_hauteur_sol_sous.
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

# Rend true si aucun collider autre que la GridMap n'occupe la position
# candidate. Le sol (GridMap) est tolere -- la face basse du cube candidat
# repose dessus par construction (voir HAUTEUR_CENTRE_CUBE).
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
