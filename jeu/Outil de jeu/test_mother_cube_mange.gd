extends SceneTree

# TEST morceau 3a : mother cube percoit un carre rouge, s'y deplace,
# le mange (5 frappes a 1/s), puis revient a ETAT_ATTENTE.
# Scenario : mother cube a l'origine, carre rouge a 15m sur X.

const MondePartageScript = preload("res://jeu/Outil de jeu/monde_partage.gd")

func _init() -> void:
	var mp := Node.new()
	mp.set_script(MondePartageScript)
	root.add_child(mp)
	await process_frame

	var scene_cr: PackedScene = load("res://jeu/Outil de jeu/carre_rouge.tscn")
	var cr = scene_cr.instantiate() as Node3D
	cr.position = Vector3(15, 0, 0)
	root.add_child(cr)
	await process_frame

	var scene_mc: PackedScene = load("res://jeu/Outil de jeu/mother_cube.tscn")
	var mc = scene_mc.instantiate()
	# ACCELERE le test : cadence de frappe 0.3s (au lieu de 1.0s).
	mc.set("secondes_par_frappe", 0.3)
	root.add_child(mc)
	await process_frame

	print("--- ETAT INITIAL ---")
	print("mc pos=", mc.global_position, " etat=", mc._etat, " (0=ATTENTE 1=VERS 2=MANGE)")
	print("cr pos=", cr.global_position, " vie=", cr.entite.proprietes.reserves.vie.reserve)

	var etat_prec: int = -1
	var carre_mort_frame: int = -1
	for i in 700:
		await process_frame
		if mc._etat != etat_prec:
			var d: float = ((cr.global_position - mc.global_position).length() if is_instance_valid(cr) else -1.0)
			print("frame %d : mc etat=%d pos=(%.1f,%.1f,%.1f) dist_cr=%.2f" % [i, mc._etat, mc.global_position.x, mc.global_position.y, mc.global_position.z, d])
			etat_prec = mc._etat
		if not is_instance_valid(cr) and carre_mort_frame < 0:
			carre_mort_frame = i
			print("frame %d : CARRE ROUGE DETRUIT (mange complet)" % i)
		if carre_mort_frame > 0 and i > carre_mort_frame + 30:
			break

	print("--- APRES ~%d frames ---" % 700)
	print("carre_rouge encore valide=", is_instance_valid(cr))
	if is_instance_valid(cr):
		print("carre_rouge vie restante=", cr.entite.proprietes.reserves.vie.reserve)
	print("mc etat final=", mc._etat)

	quit(0)
