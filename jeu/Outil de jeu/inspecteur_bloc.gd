extends Node3D

# BANC "test_ennemi2 Mother box" -- OUTIL DE DEBUG. Trois choses :
#  1. Une croix "+" au centre de l'ecran (viseur).
#  2. Un HALO jaune emissif qui suit le bloc pointe en temps reel
#     (raycast par frame, cout microscopique).
#  3. Un LABEL debug qui affiche position + type + reserve du bloc
#     actif, en deux modes :
#       AUTO (defaut) : le label suit le bloc pointe. Quand le
#           viseur quitte tout bloc, le label garde la derniere
#           info visible (pas de clignotement).
#       LOCKED (touche I) : le label reste sur UN bloc precis meme
#           quand la camera tourne. Utile pour observer un bloc
#           pendant qu'il se vide/remplit.
#       ESC : deverrouille, retour en mode AUTO.
#
# COUT : un raycast par frame + une lecture Dict par frame. Rien
# d'autre.

@onready var _label: Label = $HUD/Label
@onready var _halo: MeshInstance3D = $Halo

var _ressources: Node = null
var _stock_joueur: Node = null
var _cellule_active: Variant = null  # Vector3i ou null
var _grille_active: GridMap = null   # pour convertir cellule -> monde
var _nom_item_actif: String = ""
var _verrouille: bool = false

# PORTEE D'EXTRACTION : le joueur ne peut collecter que dans un rayon de N
# cases autour de lui. Au-dela, l'inspecteur affiche la cellule (halo + label)
# mais preleve() est refuse silencieusement.
const PORTEE_EXTRACTION_CASES := 3

# EXTRACTION AU CLIC GAUCHE : 1 unite au moment du clic, puis 1
# unite par seconde tant qu'il est maintenu. `_extract_maintenu` reste
# vrai pendant tout le maintien ; `_extract_accumule` mesure le temps
# passe depuis la derniere unite extraite en continu.
var _extract_maintenu: bool = false
var _extract_accumule: float = 0.0

# TOGGLE INSPECTEUR : touche I active/desactive tout. Inactif = halo et
# label caches, aucun raycast, aucune extraction. Actif par defaut.
var _actif: bool = true

func _ready() -> void:
	_label.visible = false
	_halo.visible = false
	_ressources = get_tree().get_first_node_in_group("ressources_terrain")
	if _ressources == null:
		push_warning("inspecteur_bloc.gd : RessourcesTerrain absent, l'inspecteur affichera 0 partout")
	_stock_joueur = get_tree().get_first_node_in_group("stock_joueur")
	if _stock_joueur == null:
		push_warning("inspecteur_bloc.gd : StockJoueur absent, l'extraction sera perdue")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I:
			# Toggle actif/inactif.
			_actif = not _actif
			if not _actif:
				_label.visible = false
				_halo.visible = false
				_verrouille = false
				_extract_maintenu = false
			return
		if not _actif:
			return
		if event.keycode == KEY_L:
			_verrouille = true
		elif event.keycode == KEY_ESCAPE and _verrouille:
			_verrouille = false
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not _actif:
			return
		if event.pressed:
			_extract_maintenu = true
			_extract_accumule = 0.0
			_extraire_une_unite()
		else:
			_extract_maintenu = false
			_extract_accumule = 0.0

func _extraire_une_unite() -> void:
	if _cellule_active == null:
		return
	if _ressources == null:
		return
	# Portee : refuse si le joueur est a plus de PORTEE_EXTRACTION_CASES du
	# centre de la cellule. Distance 3D en metres.
	if _grille_active == null:
		return
	var observateur := get_tree().get_first_node_in_group(&"observateur") as Node3D
	if observateur == null:
		return
	var centre_cellule := _grille_active.to_global(_grille_active.map_to_local(_cellule_active))
	var portee_metres: float = float(PORTEE_EXTRACTION_CASES) * _grille_active.cell_size.x
	if (centre_cellule - observateur.global_position).length() > portee_metres:
		return
	var pris := float(_ressources.preleve(_cellule_active, 1.0))
	if pris <= 0.0:
		return
	if _stock_joueur != null:
		_stock_joueur.ajouter(pris)
	# NOURRIR LE PERSONNAGE : chaque unite prelevee sur un bloc profile
	# donne un forfait de faim au joueur (et reset son compteur inanition).
	# Ce bloc couvre TOUS les profils, bloc_bleu compris -- pas de branche
	# specifique par nom d'item (voir doctrine ADN : le moteur ne connait
	# aucune categorie du monde).
	if observateur.has_method("nourrir"):
		observateur.call("nourrir", 15.0)

func _process(delta: float) -> void:
	if not _actif:
		return
	# MAINTIEN DU CLIC GAUCHE : 1 unite par seconde apres le clic initial.
	if _extract_maintenu:
		_extract_accumule += delta
		while _extract_accumule >= 1.0:
			_extract_accumule -= 1.0
			_extraire_une_unite()

	var cible := _raycast_bloc_sous_viseur()
	# HALO : suit le bloc pointe (independant du verrouillage du label).
	if cible.is_empty():
		_halo.visible = false
	else:
		_halo.visible = true
		_halo.global_position = _centre_cellule(cible.grille, cible.cellule)

	# Mode AUTO : mise a jour de la cellule active si le viseur voit un bloc.
	# Mode LOCKED : ignore ce que voit le viseur, garde la cellule verrouillee.
	# Persistance : quand le viseur quitte un bloc, on garde la derniere info.
	if not _verrouille and not cible.is_empty():
		_cellule_active = cible.cellule
		_grille_active = cible.grille
		var item: int = cible.grille.get_cell_item(cible.cellule)
		if item == GridMap.INVALID_CELL_ITEM:
			# Case creusee : le raycast a frappe une cellule videe. Aucun item
			# a nommer -- get_item_name(-1) rale.
			_nom_item_actif = "(vide)"
		else:
			_nom_item_actif = cible.grille.mesh_library.get_item_name(item) if cible.grille.mesh_library != null else "?"

	if _cellule_active == null:
		_label.visible = false
		return

	var q := 0
	if _ressources != null:
		q = _ressources.quantite_a(_cellule_active)
	var etat := "verrouille" if _verrouille else "pointe"
	_label.text = "Bloc %s : %s\ntype : %s\nreserve : %d" % [
		etat, str(_cellule_active), _nom_item_actif, q]
	_label.visible = true

# Rend {} ou { grille: GridMap, cellule: Vector3i } selon le raycast au
# centre de l'ecran.
func _raycast_bloc_sous_viseur() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var taille := get_viewport().get_visible_rect().size
	var centre := taille * 0.5
	var origine := camera.project_ray_origin(centre)
	var direction := camera.project_ray_normal(centre)
	var espace := get_world_3d().direct_space_state
	var requete := PhysicsRayQueryParameters3D.create(origine, origine + direction * 1000.0)
	var frappe := espace.intersect_ray(requete)
	if frappe.is_empty():
		return {}
	if not (frappe.collider is GridMap):
		return {}
	var grid: GridMap = frappe.collider
	# Reculer d'un iota dans le sens inverse de la normale pour tomber pile
	# dans la cellule touchee, pas la voisine.
	var point := (frappe.position as Vector3) - (frappe.normal as Vector3) * 0.01
	var cellule := grid.local_to_map(grid.to_local(point))
	return {"grille": grid, "cellule": cellule}

# Centre monde d'une cellule d'un GridMap donne.
func _centre_cellule(grid: GridMap, cellule: Vector3i) -> Vector3:
	return grid.to_global(grid.map_to_local(cellule))
