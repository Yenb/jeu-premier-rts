extends StaticBody3D

# BANC "test_ennemi" -- la vie d'un cube : une reserve, une barre au-dessus,
# rien d'autre. NE REINVENTE PAS LE CALCUL DE DEGATS : Frappe.frapper()
# (scripts/frappe.gd) soustrait la reserve, bornee a zero -- ce fichier ne
# fait que lui donner une reserve a frapper, lire ce qu'il en reste, et
# afficher/detruire en consequence.
#
# Entree : subir_frappe(degats), appelee par interaction_destruction.gd sur
# tout ce qui porte le groupe "destructible" et expose cette methode.
# Sortie : la barre se met a jour ; le noeud se detruit lui-meme des que la
# reserve atteint zero.

const Frappe = preload("res://scripts/frappe.gd")

@export var vie_max: float = 10.0

var _entite: Dictionary
var _barre: MeshInstance3D
# UN MATERIAU PROPRE A CE CUBE : le sub_resource pose dans cube_ennemi.tscn
# est PARTAGE par toute instance de la scene. Sans dupliquer, changer la
# fraction d'un cube changerait la barre de TOUS LES AUTRES au meme instant.
var _materiau: ShaderMaterial

func _ready() -> void:
	_entite = {
		"id": str(get_instance_id()),
		"proprietes": {"reserves": {"vie": {"reserve": vie_max, "capacite": vie_max}}},
	}
	_barre = get_node("BarreDeVie/Barre") as MeshInstance3D
	_materiau = _barre.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre.set_surface_override_material(0, _materiau)
	_rafraichir_barre()

func subir_frappe(degats: float) -> void:
	Frappe.frapper(_entite, degats, "vie")
	_rafraichir_barre()
	var reserve: float = _entite.proprietes.reserves.vie.reserve
	if reserve <= 0.0:
		queue_free()

func _rafraichir_barre() -> void:
	var reserve: float = _entite.proprietes.reserves.vie.reserve
	var fraction := clampf(reserve / vie_max, 0.0, 1.0)
	_materiau.set_shader_parameter("fraction", fraction)
