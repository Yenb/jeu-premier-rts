extends StaticBody3D

# BANC "test_ennemi" -- la vie et le stock d'un cube violet. Deux barres :
# vie (verte, subir_frappe) et stock_metal (bleue, alimentee par les
# transporteurs via Consommer.transferer -- voir transporteur.gd).
#
# NE REINVENTE PAS LE CALCUL DE DEGATS : Frappe.frapper() (framework)
# soustrait la reserve, bornee a zero -- ce fichier ne fait que lui donner
# une reserve a frapper, lire ce qu'il en reste, et afficher/detruire.
# LE STOCK N'EST PAS UNE VIE : la barre bleue peut atteindre `capacite_stock`
# sans que rien ne meure ni ne naisse ici. gestation_stock.gd (frere)
# surveille ce stock et decide de la reproduction, seuil bien plus bas.
#
# ENREGISTRE DANS LE MONDE PARTAGE : profil "cube_violet_disponible", pour
# qu'un transporteur DONT LA MERE EST PLEINE puisse en trouver un autre non
# plein a proximite et y deposer. La saillance/perception est faite dans
# transporteur.gd ; ce fichier ne fait que declarer sa presence.

const Frappe = preload("res://scripts/frappe.gd")

@export var vie_max: float = 50.0
# CAPACITE DU STOCK : au-dela, un transporteur cherche un autre cube ou
# deposer. La barre bleue est plein a ce nombre.
@export var capacite_stock: float = 200.0

# MODE COMBAT : declenche par une frappe (ou par le signal d'un voisin
# frappe), PERSISTE jusqu'a ce qu'un soldat naisse. Sortie du mode combat
# NON basee sur un timer : gestation_soldat.gd appelle sortir_du_mode_combat()
# apres la naissance. Le mode combat gele gestation_stock (plus de nouveaux
# cubes violets) et deverrouille gestation_soldat.
#
# POURQUOI PAS DE TIMER : avec un timer de 30 s, la production etait
# impossible en pratique -- il fallait 5 voyages de transporteurs pour
# amasser 50 metal + 30 s de gestation soldat, bien plus que 30 s. La
# gestation etait toujours abandonnee. Sans timer, le cube tient l'etat
# de guerre jusqu'a ce qu'il ait vraiment produit son soldat.

# RAYON DU SIGNAL D'ALERTE : quand ce cube est frappe, il previent tous
# les autres cubes violets a moins de ce rayon -- ils passent aussi en
# mode combat, sans avoir ete frappes eux-memes.
@export var rayon_signal_alerte: float = 15.0

var entite: Dictionary
var mode_combat := false
var _monde_partage: Node = null

var _barre_vie: MeshInstance3D
var _materiau_vie: ShaderMaterial
var _barre_stock: MeshInstance3D
var _materiau_stock: ShaderMaterial

func _ready() -> void:
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"reserves": {
				"vie": {"reserve": vie_max, "capacite": vie_max},
				"stock_metal": {"reserve": 0.0, "capacite": capacite_stock},
			},
			"profil_saillance": "cube_violet_disponible",
		},
		"noeud": self,
	}

	_barre_vie = get_node("BarreDeVie/Barre") as MeshInstance3D
	_materiau_vie = _barre_vie.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_vie.set_surface_override_material(0, _materiau_vie)

	_barre_stock = get_node("BarreDeStock/Barre") as MeshInstance3D
	_materiau_stock = _barre_stock.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_stock.set_surface_override_material(0, _materiau_stock)

	_rafraichir_barres()

	_monde_partage = get_tree().get_first_node_in_group("monde_partage")
	if _monde_partage != null:
		_monde_partage.monde.ajouter(entite, "cube_violet", global_position)
	# LE CUBE VIOLET NE BOUGE PAS : pas besoin de resynchroniser sa position
	# dans le monde apres l'ajout.
	add_to_group("cube_violet")

func est_plein() -> bool:
	return entite.proprietes.reserves.stock_metal.reserve >= capacite_stock

func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	_rafraichir_barres()
	entrer_en_mode_combat()
	# LE SIGNAL AUX VOISINS -- balayage direct du groupe, plus simple qu'un
	# vrai mecanisme de propagation (propagation.gd fait des delais
	# d'exposition, disproportionne pour un signal instantane).
	for autre in get_tree().get_nodes_in_group("cube_violet"):
		if autre == self or not autre.has_method("entrer_en_mode_combat"):
			continue
		if global_position.distance_to(autre.global_position) <= rayon_signal_alerte:
			autre.entrer_en_mode_combat()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		if _monde_partage != null:
			_monde_partage.monde.retirer(entite.id)
		queue_free()

# ENTRE EN MODE COMBAT : la porte d'entree, appelee par soi-meme (frappe
# subie) ou par un voisin (via son signal). Idempotente. Reste vrai
# jusqu'a ce que sortir_du_mode_combat soit appelee -- par
# gestation_soldat.gd apres la naissance d'un soldat.
func entrer_en_mode_combat() -> void:
	mode_combat = true

# SORT DU MODE COMBAT : appelee UNIQUEMENT par gestation_soldat apres
# qu'un soldat est ne. La reproduction normale (gestation_stock) reprend
# des le prochain tick.
func sortir_du_mode_combat() -> void:
	mode_combat = false

func _rafraichir_barres() -> void:
	var fraction_vie := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau_vie.set_shader_parameter("fraction", fraction_vie)
	var fraction_stock := clampf(
		entite.proprietes.reserves.stock_metal.reserve / capacite_stock, 0.0, 1.0)
	_materiau_stock.set_shader_parameter("fraction", fraction_stock)
