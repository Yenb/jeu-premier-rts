extends SceneTree

# TEST ECOSYSTEME central. Verifie 5 comportements croisant les 4 scripts
# principaux (carre_rouge, mother_cube, generateur_energie, monde_partage).
# Si tous verts -> ecrit .claude/last_test_ok pour lever le verrou de
# modification (hook require_test). Exigence 2026-08-22 : preuve
# d'execution CROISEE avant toute modif.

const MondePartageScript = preload("res://jeu/Outil de jeu/monde_partage.gd")

var _mp: Node = null
var _echecs: int = 0

func _init() -> void:
	print("=== TEST ECOSYSTEME ===")
	_mp = Node.new()
	_mp.set_script(MondePartageScript)
	root.add_child(_mp)
	await process_frame

	await _test_carre_rouge()
	await _test_mother_cube_perception()
	_test_mother_cube_croissance()
	await _test_generateur_mort()

	print("=== RESULTAT ===")
	if _echecs == 0:
		print("ECOSYSTEME VERT (0 echec) -- ecriture du verrou .claude/last_test_ok")
		_ecrire_verrou()
	else:
		print("ECOSYSTEME ROUGE : %d echec(s) -- verrou NON ecrit" % _echecs)
	quit(0)

func _ecrire_verrou() -> void:
	var chemin := "res://.claude/last_test_ok"
	var f := FileAccess.open(chemin, FileAccess.WRITE)
	if f == null:
		printerr("Impossible d'ecrire ", chemin, " : ", FileAccess.get_open_error())
		return
	f.store_string("OK\n")
	f.close()

func _echec(msg: String) -> void:
	printerr("ECHEC : ", msg)
	_echecs += 1

func _test_carre_rouge() -> void:
	print("- carre_rouge")
	var scene: PackedScene = load("res://jeu/Outil de jeu/carre_rouge.tscn")
	var c = scene.instantiate()
	root.add_child(c)
	await process_frame
	var id_avant: String = c.entite.id
	if not c.is_in_group("carre_rouge"):
		_echec("carre_rouge pas dans groupe")
	if _mp.monde.par_id(id_avant) == null:
		_echec("carre_rouge pas inscrit au monde")
	for i in 5:
		c.subir_frappe(1.0)
	await process_frame
	if is_instance_valid(c):
		_echec("carre_rouge encore valide apres 5 frappes")
	if _mp.monde.par_id(id_avant) != null:
		_echec("carre_rouge encore inscrit au monde apres mort")

func _test_mother_cube_perception() -> void:
	print("- mother_cube perception")
	var scene_cr: PackedScene = load("res://jeu/Outil de jeu/carre_rouge.tscn")
	var cr = scene_cr.instantiate() as Node3D
	cr.position = Vector3(15, 0, 0)
	root.add_child(cr)
	await process_frame
	var scene_mc: PackedScene = load("res://jeu/Outil de jeu/mother_cube.tscn")
	var mc = scene_mc.instantiate()
	root.add_child(mc)
	await process_frame
	await process_frame
	var vus: Array = mc.percevoir_nourriture()
	if vus.size() != 1:
		_echec("perception attendait 1 percept, obtenu %d" % vus.size())
	elif abs(vus[0].distance - 15.0) > 0.5:
		_echec("distance percept != 15 : %.2f" % vus[0].distance)
	cr.queue_free()
	mc.queue_free()
	await process_frame

func _test_mother_cube_croissance() -> void:
	print("- mother_cube croissance")
	var scene: PackedScene = load("res://jeu/Outil de jeu/mother_cube.tscn")
	var mc = scene.instantiate()
	root.add_child(mc)
	if abs(mc.scale.x - 1.0) > 0.001:
		_echec("scale initial != 1 : %.4f" % mc.scale.x)
	for i in 10:
		mc.nourrir(5.0)
	var attendu := pow(1.05, 10)
	if abs(mc.scale.x - attendu) > 0.01:
		_echec("scale apres 10 nourrir != 1.629 : %.4f" % mc.scale.x)
	for i in 500:
		mc.nourrir(5.0)
	var scale_max: float = mc._scale_max()
	if mc.scale.x > scale_max + 0.01:
		_echec("cap depasse : scale=%.2f max=%.2f" % [mc.scale.x, scale_max])
	mc.queue_free()

func _test_generateur_mort() -> void:
	print("- generateur mort civile")
	var scene: PackedScene = load("res://jeu/Outil de jeu/generateur_energie.tscn")
	var g = scene.instantiate()
	root.add_child(g)
	await process_frame
	if not g.is_in_group("generateur_energie"):
		_echec("generateur pas dans generateur_energie")
	for i in 3:
		g.subir_frappe(1.0)
	await process_frame
	if not is_instance_valid(g):
		_echec("generateur queue_free avant phase cadavre")
		return
	if not g._est_cadavre:
		_echec("pas passe en cadavre apres 3 frappes")
	if not g.is_in_group("ressource"):
		_echec("cadavre pas dans groupe ressource")
	if not g.freeze:
		_echec("cadavre pas freeze")
	for i in 7:
		g.subir_frappe(1.0)
	await process_frame
	if is_instance_valid(g):
		_echec("cadavre pas detruit apres 7 frappes finales")
