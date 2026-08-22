extends RigidBody3D

# BANC "test_ennemi2 Mother box" -- LA MOTHER CUBE, pondue par le geniteur
# apres 4 generateurs d'energie vivants + stock >= 100 (voir
# gestation_mother_cube.gd). Petit cube 0.30 m avec 3 vies par defaut.
# Recoit des frappes via Frappe.frapper (framework), affiche sa vie en
# barre 3D via barre_de_vie.gdshader (patron generateur_energie.gd /
# vie_ennemi.gd).
#
# EXTENSIBLE : Yael prevoit d'ajouter des parametres plus tard (croissance
# progressive, production, comportements). Le fichier est structure comme
# les autres bancs (entite Dictionary, reserves nommees, @export
# parametres) pour recevoir de nouveaux champs sans refonte.
#
# NE COMPOSE PAS LA GESTATION : ce fichier ne connait pas son producteur.
# Il vit et meurt seul, s'inscrit dans le groupe "mother_cube" pour que
# le banc de gestation du geniteur puisse compter les vivantes (max 1
# par defaut).
#
# NE REINVENTE PAS LE CALCUL DE DEGATS : Frappe.frapper() (framework)
# soustrait la reserve, bornee a zero.

const Frappe = preload("res://scripts/frappe.gd")

@export var vie_max: float = 3.0

var entite: Dictionary
var _barre_vie: MeshInstance3D
var _materiau_vie: ShaderMaterial

func _ready() -> void:
	add_to_group("mother_cube")
	entite = {
		"id": str(get_instance_id()),
		"position": global_position,
		"proprietes": {
			"reserves": {
				"vie": {"reserve": vie_max, "capacite": vie_max},
			},
		},
		"noeud": self,
	}
	_barre_vie = get_node("BarreDeVie/Barre") as MeshInstance3D
	# DUPLIQUE le materiau pour ne pas partager la fraction entre plusieurs
	# instances futures. Meme patron que generateur_energie.gd:_ready.
	_materiau_vie = _barre_vie.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_vie.set_surface_override_material(0, _materiau_vie)
	_rafraichir_barre()

# API publique -- appelee par ce qui frappe (arme, projectile, etc.).
func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	_rafraichir_barre()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		queue_free()

func _rafraichir_barre() -> void:
	var f := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau_vie.set_shader_parameter("fraction", f)
