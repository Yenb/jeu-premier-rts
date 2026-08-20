extends StaticBody3D

# BANC "test_ennemi" -- la vie et le stock d'un cube violet. Deux barres :
# vie (verte, subir_frappe) et stock_metal (bleue, alimentee par les
# transporteurs via Consommer.transferer -- voir transporteur.gd).
#
# NE REINVENTE PAS LE CALCUL DE DEGATS : Frappe.frapper() (framework)
# soustrait la reserve, bornee a zero -- ce fichier ne fait que lui donner
# une reserve a frapper, lire ce qu'il en reste, et afficher/detruire.
# LE STOCK N'EST PAS UNE VIE : la barre bleue peut atteindre 30 sans que
# rien ne meure ni ne naisse ici. C'est gestation_stock.gd (frere) qui
# surveille ce stock et decide de la reproduction.

const Frappe = preload("res://scripts/frappe.gd")

@export var vie_max: float = 10.0
# LE SEUIL AFFICHE : la barre bleue est a 100% quand stock atteint ce
# nombre, meme si le stock peut theoriquement monter plus haut. C'est le
# meme nombre que gestation_stock.gd utilise comme seuil de reproduction ;
# les deux DOIVENT rester d'accord, mais on ne peut pas les partager
# proprement sans coupler ce fichier a l'autre -- decision au reglage.
@export var seuil_stock_affiche: float = 30.0

var entite: Dictionary

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
				"stock_metal": {"reserve": 0.0, "capacite": 999.0},
			},
		},
		"noeud": self,
	}

	_barre_vie = get_node("BarreDeVie/Barre") as MeshInstance3D
	# UN MATERIAU PROPRE A CE CUBE : le sub_resource pose dans la scene est
	# PARTAGE par toute instance. Sans dupliquer, changer la fraction d'un
	# cube changerait la barre de TOUS les autres au meme instant.
	_materiau_vie = _barre_vie.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_vie.set_surface_override_material(0, _materiau_vie)

	_barre_stock = get_node("BarreDeStock/Barre") as MeshInstance3D
	_materiau_stock = _barre_stock.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_stock.set_surface_override_material(0, _materiau_stock)

	_rafraichir_barres()

func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	_rafraichir_barres()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		queue_free()

func _rafraichir_barres() -> void:
	var fraction_vie := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau_vie.set_shader_parameter("fraction", fraction_vie)
	var fraction_stock := clampf(
		entite.proprietes.reserves.stock_metal.reserve / seuil_stock_affiche, 0.0, 1.0)
	_materiau_stock.set_shader_parameter("fraction", fraction_stock)
