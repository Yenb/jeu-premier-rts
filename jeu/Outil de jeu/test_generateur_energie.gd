extends SceneTree

# TEST : cycle complet vivant -> cadavre -> destruction finale.
# Phase 1 : 3 frappes -> _mourir() (vie=3, freeze, groupe ressource, barre cachee)
# Phase 2 : 7 frappes -> queue_free (destruction finale)

func _init() -> void:
	var scene: PackedScene = load("res://jeu/Outil de jeu/generateur_energie.tscn")
	var g = scene.instantiate()
	root.add_child(g)
	await process_frame

	print("--- ETAT INITIAL ---")
	print("vie=", g.entite.proprietes.reserves.vie.reserve, " capacite=", g.entite.proprietes.reserves.vie.capacite)
	print("est_cadavre=", g._est_cadavre, " freeze=", g.freeze)
	print("dans generateur_energie=", g.is_in_group("generateur_energie"), " dans ressource=", g.is_in_group("ressource"))
	print("barre visible=", (g.get_node_or_null("BarreDeVie") as Node3D).visible)

	# Phase 1 : 3 frappes
	g.subir_frappe(1.0); g.subir_frappe(1.0); g.subir_frappe(1.0)
	await process_frame

	print("--- APRES 3 FRAPPES ---")
	print("valide=", is_instance_valid(g))
	print("vie=", g.entite.proprietes.reserves.vie.reserve, " capacite=", g.entite.proprietes.reserves.vie.capacite)
	print("est_cadavre=", g._est_cadavre, " freeze=", g.freeze)
	print("dans generateur_energie=", g.is_in_group("generateur_energie"), " dans ressource=", g.is_in_group("ressource"))
	print("barre visible=", (g.get_node_or_null("BarreDeVie") as Node3D).visible)

	# Phase 2 : 7 frappes supplementaires
	for i in 7:
		g.subir_frappe(1.0)
		print("cadavre apres frappe %d : vie=%.1f valide=%s" % [i+1, g.entite.proprietes.reserves.vie.reserve, str(is_instance_valid(g))])
	await process_frame
	print("--- APRES 7 FRAPPES CADAVRE ---")
	print("valide=", is_instance_valid(g))

	quit(0)
