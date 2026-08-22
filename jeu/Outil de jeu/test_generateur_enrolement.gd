extends SceneTree

# TEST morceau 2 : generateur enrole -- cycle POSE -> VERS_GENITEUR -> COLLE
# -> POND -> retour VERS_GENITEUR, jusqu'a ce qu'un carre rouge apparaisse.
# Utilise un geniteur MOCKE (Node3D + groupe + methode retirer_stock) pour
# ne pas monter tout le banc test_ennemi2. Le vrai geniteur necessite
# ressources_terrain + GridMap freres, hors scope de ce test.
#
# ACCELERE le test en reduisant secondes_ponte a 0.5s (au lieu de 60s).

const MondePartageScript = preload("res://jeu/Outil de jeu/monde_partage.gd")

# MOCK GENITEUR : Node3D avec groupe et compteur de retirer_stock appele.
class MockGeniteur extends Node3D:
	var stock_retire_total: float = 0.0
	var _appels_retirer: int = 0

	func _ready() -> void:
		add_to_group("geniteur")

	func retirer_stock(quantite: float) -> void:
		stock_retire_total += quantite
		_appels_retirer += 1

	# API MOCKE : le vrai geniteur retourne la quantite REELLEMENT prise.
	# Ici on considere stock illimite -> retourne toujours la quantite
	# demandee. Compteur incremente comme retirer_stock.
	func preleve_stock_accessible(quantite: float) -> float:
		stock_retire_total += quantite
		_appels_retirer += 1
		return quantite

	func stock_courant() -> float:
		return 300.0

	func chercher_nouvelle_cible() -> void:
		pass

func _init() -> void:
	# 1. Monde partage.
	var mp := Node.new()
	mp.set_script(MondePartageScript)
	root.add_child(mp)
	await process_frame

	# 2. Mock geniteur a l'origine.
	var geniteur := MockGeniteur.new()
	root.add_child(geniteur)
	await process_frame

	# 3. Generateur d'energie a 10m du geniteur. secondes_ponte accelere.
	var scene_ge: PackedScene = load("res://jeu/Outil de jeu/generateur_energie.tscn")
	var ge = scene_ge.instantiate()
	ge.position = Vector3(10, 0, 0)
	ge.set("secondes_ponte", 0.5)
	root.add_child(ge)
	await process_frame

	print("--- ETAT INITIAL ---")
	print("generateur position=", ge.global_position)
	print("etat=", ge._etat, " (0=VERS_GENITEUR, 1=COLLE, 2=POND)")
	print("cout paye=", ge._cout_paye_pour_ce_cycle)

	# Boucler ~5 secondes en attendant les process_frame de la SceneTree.
	# En headless, ~60 fps -> 300 frames = 5s. On log a chaque nouvelle
	# apparition de carre rouge dans l'arbre.
	var carres_apparus: int = 0
	var etat_prec: int = -1
	for i in 800:
		await process_frame
		if ge._etat != etat_prec:
			print("frame %d : etat=%d (0=VERS_GENITEUR 1=COLLE 2=POND)  pos=(%.1f,%.1f,%.1f)" % [i, ge._etat, ge.global_position.x, ge.global_position.y, ge.global_position.z])
			etat_prec = ge._etat
		var actuels := root.get_children().filter(func(n): return n.is_in_group("carre_rouge"))
		if actuels.size() > carres_apparus:
			carres_apparus = actuels.size()
			print("frame %d : nouveau carre rouge (total=%d), cout total retire=%.1f" % [i, carres_apparus, geniteur.stock_retire_total])

	print("--- APRES ~5 s ---")
	print("carres_rouges dans l'arbre=", carres_apparus)
	print("cout total retire au geniteur=", geniteur.stock_retire_total)
	print("nombre d'appels retirer_stock=", geniteur._appels_retirer)
	print("generateur position finale=", ge.global_position)
	print("etat final=", ge._etat)

	quit(0)
