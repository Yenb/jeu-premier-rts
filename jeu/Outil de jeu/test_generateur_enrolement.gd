extends SceneTree

# TEST : generateur enrole -- cycle ATTENTE -> VERS_SOURCE -> COLLE ->
# POND -> retour ATTENTE. Utilise un geniteur MOCKE (Node3D inscrit au
# monde partage avec stock_puisable) pour ne pas monter tout le banc
# test_ennemi2. Accelere avec secondes_ponte=0.5s.

const MondePartageScript = preload("res://jeu/Outil de jeu/monde_partage.gd")

# MOCK GENITEUR : Node3D inscrit au monde partage comme source de matiere.
# Le generateur enrole doit le PERCEVOIR (via canaux vue), pas via groupe.
class MockGeniteur extends Node3D:
	var stock_retire_total: float = 0.0
	var _appels_retirer: int = 0
	var entite: Dictionary
	var _monde_partage: Node

	func _ready() -> void:
		add_to_group("geniteur")
		entite = {
			"id": str(get_instance_id()),
			"position": global_position,
			"proprietes": {"stock_puisable": 1000.0},  # stock illimite pour le test
			"noeud": self,
		}
		_monde_partage = get_tree().get_first_node_in_group("monde_partage")
		if _monde_partage != null:
			_monde_partage.monde.ajouter(entite, "geniteur", global_position)

	# API UNIFORME (memes signatures que le vrai geniteur.gd).
	func preleve_stock_puisable(quantite: float) -> float:
		stock_retire_total += quantite
		_appels_retirer += 1
		return quantite

	func preleve_stock_accessible(quantite: float) -> float:
		return preleve_stock_puisable(quantite)

	func retirer_stock(quantite: float) -> void:
		stock_retire_total += quantite

	func stock_courant() -> float:
		return 300.0

	func chercher_nouvelle_cible() -> void:
		pass

func _init() -> void:
	var mp := Node.new()
	mp.set_script(MondePartageScript)
	root.add_child(mp)
	await process_frame

	var geniteur := MockGeniteur.new()
	root.add_child(geniteur)
	await process_frame

	var scene_ge: PackedScene = load("res://jeu/Outil de jeu/generateur_energie.tscn")
	var ge = scene_ge.instantiate()
	ge.position = Vector3(10, 0, 0)
	ge.set("secondes_ponte", 0.5)
	root.add_child(ge)
	await process_frame

	print("--- ETAT INITIAL ---")
	print("generateur position=", ge.global_position)
	print("etat=", ge._etat, " (0=ATTENTE 1=VERS_SOURCE 2=COLLE 3=POND)")
	print("cout paye=", ge._cout_paye_pour_ce_cycle)

	var carres_apparus: int = 0
	var etat_prec: int = -1
	for i in 800:
		await process_frame
		if ge._etat != etat_prec:
			print("frame %d : etat=%d pos=(%.1f,%.1f,%.1f)" % [i, ge._etat, ge.global_position.x, ge.global_position.y, ge.global_position.z])
			etat_prec = ge._etat
		var actuels := root.get_children().filter(func(n): return n.is_in_group("carre_rouge"))
		if actuels.size() > carres_apparus:
			carres_apparus = actuels.size()
			print("frame %d : nouveau carre rouge (total=%d), cout total retire=%.1f" % [i, carres_apparus, geniteur.stock_retire_total])

	print("--- APRES ~800 frames ---")
	print("carres_rouges dans l'arbre=", carres_apparus)
	print("cout total retire au geniteur=", geniteur.stock_retire_total)
	print("nombre d'appels preleve=", geniteur._appels_retirer)
	print("generateur position finale=", ge.global_position)
	print("etat final=", ge._etat)

	quit(0)
