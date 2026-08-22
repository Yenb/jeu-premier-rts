extends SceneTree

# TEST morceau 1a : instancier un MondePartage + un carre rouge, verifier :
#   - inscription au monde a _ready (recherchable par monde.par_id)
#   - propriete nourriture = 5.0 visible sur l'entite du monde
#   - 5 frappes -> _mourir : queue_free ET retrait du monde
# Ce test verrouille le contrat de la couche perception cote emetteur :
# sans inscription au monde, la mother cube ne verrait rien.

const MondePartageScript = preload("res://jeu/Outil de jeu/monde_partage.gd")

func _init() -> void:
	var mp := Node.new()
	mp.set_script(MondePartageScript)
	root.add_child(mp)
	await process_frame

	var scene: PackedScene = load("res://jeu/Outil de jeu/carre_rouge.tscn")
	var c = scene.instantiate()
	root.add_child(c)
	await process_frame

	print("--- ETAT INITIAL ---")
	print("vie=", c.entite.proprietes.reserves.vie.reserve)
	print("nourriture=", c.entite.proprietes.get("nourriture", -1))
	print("groupe carre_rouge=", c.is_in_group("carre_rouge"))
	# Le monde doit lister l'entite par son id.
	var trouve = mp.monde.par_id(c.entite.id)
	print("inscrit au monde=", trouve != null)
	if trouve != null:
		print("type dans monde=", trouve.get("type", "?"))

	# Capturer l'id AVANT la destruction (post-queue_free, c.entite plante).
	var id_avant: String = c.entite.id
	# 5 frappes -> destruction
	for i in 5:
		c.subir_frappe(1.0)
		if is_instance_valid(c):
			print("frappe %d : vie=%.1f" % [i+1, c.entite.proprietes.reserves.vie.reserve])
		else:
			print("frappe %d : entite detruite" % (i+1))
	await process_frame

	print("--- APRES 5 FRAPPES + 1 frame ---")
	print("valide=", is_instance_valid(c))
	print("id garde=", id_avant)
	# Le monde ne doit plus contenir l'id.
	var trouve_apres = mp.monde.par_id(id_avant)
	print("encore inscrit au monde=", trouve_apres != null)

	quit(0)
