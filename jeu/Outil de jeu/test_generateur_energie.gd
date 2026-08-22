extends SceneTree

# TEST TEMPORAIRE : instancier generateur_energie.tscn, appliquer 3 frappes
# de 1 degat, verifier que la mort N'EST PAS queue_free :
#   - noeud toujours valide
#   - sorti du groupe "generateur_energie"
#   - inscrit au groupe "ressource"
#   - freeze = true (RigidBody immobile)
#   - fraction barre = 0

func _init() -> void:
	var scene: PackedScene = load("res://jeu/Outil de jeu/generateur_energie.tscn")
	if scene == null:
		printerr("TEST FAIL : impossible de charger la scene")
		quit(1)
		return
	var g = scene.instantiate()
	root.add_child(g)
	await process_frame

	print("vie initiale = ", g.entite.proprietes.reserves.vie.reserve)
	print("dans generateur_energie = ", g.is_in_group("generateur_energie"))
	print("dans ressource = ", g.is_in_group("ressource"))
	print("freeze initial = ", g.freeze)

	g.subir_frappe(1.0)
	g.subir_frappe(1.0)
	g.subir_frappe(1.0)
	await process_frame

	print("--- APRES 3 FRAPPES + 1 frame ---")
	print("valide = ", is_instance_valid(g))
	print("vie = ", g.entite.proprietes.reserves.vie.reserve)
	print("dans generateur_energie = ", g.is_in_group("generateur_energie"))
	print("dans ressource = ", g.is_in_group("ressource"))
	print("freeze = ", g.freeze)

	quit(0)
