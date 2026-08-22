extends SceneTree

# TEST : mother cube inscrite au monde + perception via canaux vue.
# Verifie :
#  - inscription au monde a _ready
#  - percevoir_nourriture() rend un carre rouge a 15 m
#  - percevoir_nourriture() ignore un carre rouge a 40 m (hors portee 30)
#  - retrait du monde apres 3 frappes -> _mourir

const MondePartageScript = preload("res://jeu/Outil de jeu/monde_partage.gd")

func _init() -> void:
	# 1. Monde partage.
	var mp := Node.new()
	mp.set_script(MondePartageScript)
	root.add_child(mp)
	await process_frame

	# 2. Deux carres rouges : un a 15 m (dans portee), un a 40 m (hors).
	# ORDRE CRITIQUE : position AVANT add_child, sinon _ready lit
	# global_position=Vector3.ZERO et inscrit tout a l'origine.
	var scene_cr: PackedScene = load("res://jeu/Outil de jeu/carre_rouge.tscn")
	var cr_proche = scene_cr.instantiate() as Node3D
	cr_proche.position = Vector3(15, 0, 0)
	root.add_child(cr_proche)
	var cr_loin = scene_cr.instantiate() as Node3D
	cr_loin.position = Vector3(40, 0, 0)
	root.add_child(cr_loin)
	await process_frame

	# 3. Mother cube a l'origine (position par defaut = ZERO, pas besoin de setter).
	var scene_mc: PackedScene = load("res://jeu/Outil de jeu/mother_cube.tscn")
	var mc = scene_mc.instantiate()
	root.add_child(mc)
	await process_frame

	print("--- INSCRIPTION MONDE ---")
	var id_mc: String = mc.entite.id
	var trouve = mp.monde.par_id(id_mc)
	print("mother cube inscrite au monde=", trouve != null)
	if trouve != null:
		print("type dans monde=", trouve.get("type", "?"))
	print("canaux=", mc.entite.proprietes.get("canaux", []))
	print("portee vue=", mc.entite.proprietes.canaux_config.vue.portee)

	print("--- PERCEPTION ---")
	var vus: Array = mc.percevoir_nourriture()
	print("nombre de nourritures percues=", vus.size())
	for v in vus:
		print("  percept type=%s distance=%.1f nourriture=%.1f" % [v.type, v.distance, v.chose.proprietes.get("nourriture", 0.0)])

	# Assertion attendue : 1 seul percept (le carre a 15m). Celui a 40m est
	# hors portee 30m.

	print("--- MORT ---")
	mc.subir_frappe(1.0); mc.subir_frappe(1.0); mc.subir_frappe(1.0)
	await process_frame
	print("valide apres 3 frappes+frame=", is_instance_valid(mc))
	var trouve_apres = mp.monde.par_id(id_mc)
	print("encore inscrite au monde=", trouve_apres != null)

	quit(0)
