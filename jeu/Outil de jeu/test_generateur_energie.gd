extends SceneTree

# TEST TEMPORAIRE morceau 1 : instancier generateur_energie.tscn, appliquer
# 3 frappes de 1 degat, verifier la sequence vie = 2 -> 1 -> 0 -> mort
# (queue_free). Aucune verification de rendu -- headless.

func _init() -> void:
	var scene: PackedScene = load("res://jeu/Outil de jeu/generateur_energie.tscn")
	if scene == null:
		printerr("TEST FAIL : impossible de charger la scene")
		quit(1)
		return
	var g = scene.instantiate()
	root.add_child(g)
	# Laisser _ready() s'executer (add_to_group, entite, barre)
	await process_frame

	print("vie initiale = ", g.entite.proprietes.reserves.vie.reserve)
	print("dans le groupe generateur_energie = ", g.is_in_group("generateur_energie"))

	g.subir_frappe(1.0)
	print("apres frappe 1 : vie = ", g.entite.proprietes.reserves.vie.reserve, " valide = ", is_instance_valid(g))

	g.subir_frappe(1.0)
	print("apres frappe 2 : vie = ", g.entite.proprietes.reserves.vie.reserve, " valide = ", is_instance_valid(g))

	g.subir_frappe(1.0)
	# Apres la troisieme frappe, queue_free est appelee -- l'objet reste
	# valide jusqu'a la fin de la frame courante, mais sa reserve doit
	# etre a 0.
	print("apres frappe 3 : vie = ", g.entite.proprietes.reserves.vie.reserve, " valide = ", is_instance_valid(g))
	await process_frame
	print("apres 1 frame : valide = ", is_instance_valid(g))

	quit(0)
