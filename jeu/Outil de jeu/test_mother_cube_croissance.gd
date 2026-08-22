extends SceneTree

# TEST morceau 3b : croissance mother cube via nourrir().
# - scale initial = 1
# - vitesse_courante initiale = vitesse_petite (10)
# - apres 10 nourrir : scale ~= 1.05^10, ratio > 0, vitesse < 10
# - apres 200 nourrir : cap scale_max (~233), vitesse ~= vitesse_adulte (2.5)

const MondePartageScript = preload("res://jeu/Outil de jeu/monde_partage.gd")

func _init() -> void:
	var mp := Node.new()
	mp.set_script(MondePartageScript)
	root.add_child(mp)
	await process_frame

	var scene_mc: PackedScene = load("res://jeu/Outil de jeu/mother_cube.tscn")
	var mc = scene_mc.instantiate()
	root.add_child(mc)
	await process_frame

	var scale_max: float = mc._scale_max()
	print("--- CONFIG ---")
	print("taille_base_m=%.2f taille_max_m=%.1f scale_max=%.1f" % [mc.taille_base_m, mc.taille_max_m, scale_max])
	print("vitesse_petite=%.1f vitesse_adulte=%.1f gain_par_manger_pct=%.1f" % [mc.vitesse_petite, mc.vitesse_adulte, mc.gain_par_manger_pct])

	print("--- ETAT INITIAL ---")
	print("scale=%.3f ratio=%.4f vitesse=%.3f" % [mc.scale.x, mc._ratio_taille(), mc._vitesse_courante()])

	# 10 nourrir : scale = 1 * 1.05^10 ~= 1.628
	for i in 10:
		mc.nourrir(5.0)
	print("--- APRES 10 NOURRIR ---")
	print("scale=%.3f (attendu ~1.629)" % mc.scale.x)
	print("ratio=%.4f" % mc._ratio_taille())
	print("vitesse=%.3f" % mc._vitesse_courante())

	# 200 nourrir : capping
	for i in 200:
		mc.nourrir(5.0)
	print("--- APRES 210 NOURRIR TOTAL ---")
	print("scale=%.3f (cap attendu = %.1f)" % [mc.scale.x, scale_max])
	print("ratio=%.4f (attendu ~1.0)" % mc._ratio_taille())
	print("vitesse=%.3f (attendu ~%.2f)" % [mc._vitesse_courante(), mc.vitesse_adulte])
	print("gain_effectif_pct=%.4f (attendu ~0)" % (mc.gain_par_manger_pct * (1.0 - mc._ratio_taille())))

	quit(0)
