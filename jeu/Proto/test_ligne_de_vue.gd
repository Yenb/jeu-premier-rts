extends SceneTree

# Test manuel :
# godot --headless --script jeu/Proto/test_ligne_de_vue.gd
#
# Verrouille ManagerProto.ligne_de_vue_libre_statique : ray-marching data
# pur sur carte.est_pleine, sans dependance streaming ni physique.

const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const ManagerProto = preload("res://jeu/Proto/manager_proto.gd")

func _init() -> void:
	var carte := CarteTerrain.new()
	carte.demi_cote = 10
	var cote: float = 2.0

	carte.sculpter(Vector2i(5, 0), carte.couche_base + 3)

	var y_test: float = float(carte.couche_base + 1) * cote + cote * 0.5
	var pos_a := Vector3(2.0 * cote + cote * 0.5, y_test, 0.5)
	var pos_b := Vector3(14.0 * cote + cote * 0.5, y_test, 0.5)

	var libre_1: bool = ManagerProto.ligne_de_vue_libre_statique(carte, cote, pos_a, pos_b)
	print("[TEST 1] mur entre A et B, meme Y -> libre=", libre_1, " (attendu false)")

	var y_haut: float = float(carte.couche_base + 10) * cote + cote * 0.5
	var pos_c := Vector3(2.0 * cote + cote * 0.5, y_haut, 0.5)
	var pos_d := Vector3(14.0 * cote + cote * 0.5, y_haut, 0.5)
	var libre_2: bool = ManagerProto.ligne_de_vue_libre_statique(carte, cote, pos_c, pos_d)
	print("[TEST 2] au-dessus du mur, aucun obstacle -> libre=", libre_2, " (attendu true)")

	var libre_3: bool = ManagerProto.ligne_de_vue_libre_statique(carte, cote, pos_a, pos_a)
	print("[TEST 3] distance nulle -> libre=", libre_3, " (attendu true)")

	var ok: bool = (libre_1 == false) and (libre_2 == true) and (libre_3 == true)
	if ok:
		print("OK: ligne_de_vue_libre_statique bloque quand mur, passe sinon")
		quit(0)
	else:
		push_error("ECHEC : voir prints ci-dessus")
		quit(1)
