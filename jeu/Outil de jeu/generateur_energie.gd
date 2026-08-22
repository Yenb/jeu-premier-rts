extends StaticBody3D

# BANC "test_ennemi2 Mother box" -- LE GENERATEUR D'ENERGIE, pondu par le
# geniteur (voir gestation_energie.gd, morceau suivant). Petit cube 1 m
# avec 3 vies. Recoit des frappes via Frappe.frapper (framework), affiche
# sa vie en barre 3D via barre_de_vie.gdshader (patron vie_ennemi.gd).
# Meurt a 0 (queue_free).
#
# NE COMPOSE PAS LA GESTATION : ce fichier ne connait pas son producteur.
# Il vit et meurt seul, s'inscrit dans le groupe "generateur_energie" pour
# que le banc de gestation du geniteur puisse compter les vivants sans
# reference explicite. Meme patron que "cube_violet" dans vie_ennemi.gd.
#
# NE REINVENTE PAS LE CALCUL DE DEGATS : Frappe.frapper() (framework)
# soustrait la reserve, bornee a zero -- ce fichier ne fait que fournir
# une reserve "vie" a frapper, lire ce qu'il en reste, rafraichir la
# barre et se detruire.

const Frappe = preload("res://scripts/frappe.gd")

@export var vie_max: float = 3.0

var entite: Dictionary
var _barre_vie: MeshInstance3D
var _materiau_vie: ShaderMaterial

func _ready() -> void:
	add_to_group("generateur_energie")
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
	# generateurs -- teindre l'un ne teint pas les autres. Meme patron que
	# geniteur.gd:_ready et vie_ennemi.gd:_ready.
	_materiau_vie = _barre_vie.mesh.surface_get_material(0).duplicate() as ShaderMaterial
	_barre_vie.set_surface_override_material(0, _materiau_vie)
	_rafraichir_barre()

# API publique -- appelee par ce qui frappe (arme, projectile, etc.).
# Le degat 1 = une vie perdue (patron 3 vies = 3 unites de reserve).
func subir_frappe(degats: float) -> void:
	Frappe.frapper(entite, degats, "vie")
	_rafraichir_barre()
	if entite.proprietes.reserves.vie.reserve <= 0.0:
		queue_free()

func _rafraichir_barre() -> void:
	var f := clampf(entite.proprietes.reserves.vie.reserve / vie_max, 0.0, 1.0)
	_materiau_vie.set_shader_parameter("fraction", f)
