extends SceneTree

# Banc de preuve pour la migration StaticBody3D -> PhysicsServer3D des troncs.
# godot --headless --script jeu/plantes/banc_migration_tronc.gd
#
# Verifie que le contrat physique du tronc tient apres la migration :
#
# 7a : chaque body cree par _poser_corps est bien rattache a un space
#      (body_get_space rend un RID valide).
# 7b : un raycast depuis au-dessus du tronc touche un collider non-null
#      (intersect_ray du direct_space_state trouve le corps).
# 7d : apres free_rid, le body est retire du space (body_get_space rend
#      un RID invalide).
#
# 7c non applicable : les troncs du couvert n'ont ni "vie" ni subir_frappe.
# Leur destruction externe passera par vegetation.gd:retirer(id) sur un id
# data, jamais via Frappe sur le body.

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"
const Couvert = preload("res://jeu/plantes/couvert.gd")
const EspeceScript = preload("res://jeu/plantes/espece.gd")
const PlanteScene = preload("res://jeu/plantes/plante.tscn")

const COTE := 40
const COUCHE := 0
const NOM_ESPECE := "arbre"

var _racine: Node3D
var _echecs: int = 0

func _init() -> void:
	_tout.call_deferred()

func _tout() -> void:
	_racine = Node3D.new()
	get_root().add_child(_racine)
	var grille := _terrain_plat()
	_racine.add_child(grille)
	await process_frame

	var couvert = Couvert.new()
	couvert.name = "Couvert"
	couvert.ticks_prechauffage = 30
	couvert.delta_prechauffage = 10.0
	couvert.pas_simulation = 2.0
	couvert.rayon_collision_metres = 100.0
	couvert.add_child(_espece_arbre())
	var observateur := Node3D.new()
	observateur.name = "obs"
	observateur.add_to_group("observateur")
	_racine.add_child(observateur)

	var semis := PlanteScene.instantiate() as Node3D
	semis.name = "semis_test"
	semis.type = NOM_ESPECE
	semis.position = Vector3(20.0, 1.0, 20.0)
	couvert.add_child(semis)

	grille.add_child(couvert)
	for _i in range(10):
		await process_frame

	var corps_actifs: Dictionary = couvert.get("_corps_actifs")
	print("=== BANC MIGRATION TRONC ===")
	print("corps_actifs.size() = %d" % corps_actifs.size())
	if corps_actifs.is_empty():
		_juger(false, "7 aucun corps actif pose apres 10 frames")
		_conclure()
		return

	var id_test: String = corps_actifs.keys()[0]
	var entree: Dictionary = corps_actifs[id_test]
	var body_rid: RID = entree.rid

	var space_du_body: RID = PhysicsServer3D.body_get_space(body_rid)
	var space_attendu: RID = grille.get_world_3d().space
	_juger(space_du_body.is_valid(),
		"7a body_get_space rend un RID invalide")
	_juger(space_du_body == space_attendu,
		"7a body_get_space rend un space different de world_3d.space")

	var poses: Dictionary = couvert.get("_poses")
	var pos_plante: Vector3 = poses.get(id_test, Vector3.ZERO)
	var depart := pos_plante + Vector3(0.0, 30.0, 0.0)
	var arrivee := pos_plante + Vector3(0.0, -2.0, 0.0)
	var etat_space := PhysicsServer3D.space_get_direct_state(space_du_body)
	var params := PhysicsRayQueryParameters3D.create(depart, arrivee)
	var frappe: Dictionary = etat_space.intersect_ray(params)
	print("frappe = %s" % [frappe])
	_juger(not frappe.is_empty(),
		"7b intersect_ray n'a rien touche")

	PhysicsServer3D.free_rid(body_rid)
	corps_actifs.erase(id_test)
	var space_apres: RID = PhysicsServer3D.body_get_space(body_rid)
	_juger(not space_apres.is_valid(),
		"7d body_get_space apres free_rid rend un RID encore valide")

	_conclure()

func _terrain_plat() -> GridMap:
	var g := GridMap.new()
	g.mesh_library = load(CHEMIN_BIBLIOTHEQUE) as MeshLibrary
	for x in range(COTE):
		for z in range(COTE):
			g.set_cell_item(Vector3i(x, COUCHE, z), 0)
	return g

func _espece_arbre() -> Node:
	var espece := EspeceScript.new()
	espece.nom = NOM_ESPECE
	espece.nom_stade_1 = "enfant"; espece.duree_stade_1 = 10.0; espece.stature_stade_1 = 2.0
	espece.nom_stade_2 = "ado"; espece.duree_stade_2 = 15.0; espece.stature_stade_2 = 5.0
	espece.nom_stade_3 = "jeune"; espece.duree_stade_3 = 30.0; espece.stature_stade_3 = 9.0
	espece.nom_stade_4 = "adulte"; espece.duree_stade_4 = 240.0; espece.stature_stade_4 = 14.0
	espece.nom_stade_5 = "vieux"; espece.duree_stade_5 = 20.0; espece.stature_stade_5 = 10.0
	espece.nom_stade_6 = "pourri"; espece.duree_stade_6 = 10.0; espece.stature_stade_6 = 7.0
	espece.marge_couches = 8
	espece.trouee_max_voisins = 99
	espece.rayon_dispersion_min = 2; espece.rayon_dispersion_max = 5
	espece.max_voisins = 99
	espece.stade_reproduction_min = 4; espece.stade_reproduction_max = 4
	espece.intervalle_reproduction = 40.0
	espece.stade_production_min = 99
	espece.max_produits_par_plante = 0
	espece.ralentissement_dernier_stade = 1.0
	espece.duree_vie_produit = 60.0
	espece.ressource = "graine"
	espece.rayon_collision = 1.5
	return espece

func _juger(condition: bool, message: String) -> void:
	if condition:
		print("  OK ", message.substr(0, 3))
	else:
		printerr("  ECHEC ", message)
		_echecs += 1

func _conclure() -> void:
	if _racine != null:
		_racine.queue_free()
	if _echecs > 0:
		print("ECHEC: %d assertion(s) rouge(s)" % _echecs)
		quit(1)
		return
	print("OK: migration tronc PhysicsServer3D verrouillee (7a, 7b, 7d)")
	quit(0)
