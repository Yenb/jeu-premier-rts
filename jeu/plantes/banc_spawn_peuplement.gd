extends SceneTree

# Banc de mesure du pic Peuplement.
# godot --headless --script jeu/plantes/banc_spawn_peuplement.gd
#
# MESURE deux scenarios distincts :
# - SCENARIO A : observateur AU CENTRE du Peuplement -> tous les corps
#   physiques candidats se posent d'un coup dans le rayon de culling.
#   Pire cas : pic PHYSICS + PROCESS + RENDU cumules.
# - SCENARIO B : observateur LOIN du Peuplement -> aucun corps physique
#   pose, aucune ligne MMI. Isole le cout "donnees seules"
#   (Vegetation.fabriquer_plante 1000x + monde indexe + ombres).
#
# Le pic mesure est TIME_PHYSICS_PROCESS et TIME_PROCESS sur les 5 premieres
# frames apres _ready du couvert. La premiere frame contient le spawn.

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"
const Couvert = preload("res://jeu/plantes/couvert.gd")
const EspeceScript = preload("res://jeu/plantes/espece.gd")
const PeuplementScript = preload("res://jeu/plantes/peuplement.gd")

const COTE := 100
const COUCHE := 0
const NOM_ESPECE := "arbre"
const NOMBRE_ARBRES := 1000
const FRAMES_APRES_SPAWN := 50

var _racine: Node3D

func _init() -> void:
	_tout.call_deferred()

func _tout() -> void:
	print("=== BANC SPAWN PEUPLEMENT (1000 arbres adultes) ===")
	await _mesurer("A obs au centre", Vector3(50.0, 1.0, 50.0), Vector3(50.0, 1.0, 50.0))
	await _mesurer("B obs loin", Vector3(50.0, 1.0, 50.0), Vector3(300.0, 1.0, 300.0))
	quit(0)

func _mesurer(nom: String, position_peuplement: Vector3, position_observateur: Vector3) -> void:
	_racine = Node3D.new()
	get_root().add_child(_racine)
	var grille := _terrain_plat()
	_racine.add_child(grille)

	var observateur := Node3D.new()
	observateur.name = "obs"
	observateur.position = position_observateur
	observateur.add_to_group("observateur")
	_racine.add_child(observateur)

	var couvert = Couvert.new()
	couvert.name = "Couvert"
	couvert.ticks_prechauffage = 0
	couvert.pas_simulation = 2.0
	couvert.rayon_collision_metres = 60.0
	couvert.add_child(_espece_arbre())

	var peuplement := Node3D.new()
	peuplement.set_script(PeuplementScript)
	peuplement.name = "PeuplementTest"
	peuplement.position = position_peuplement
	peuplement.set("espece", NOM_ESPECE)
	peuplement.set("rayon_dispersion", 20.0)
	peuplement.set("seed_rng", 42)
	var nombres: Array[int] = [0, 0, 0, NOMBRE_ARBRES, 0, 0]
	peuplement.set("nombres_par_stade", nombres)
	couvert.add_child(peuplement)

	print("-- %s --" % nom)
	# Wall-clock entre "avant grille.add_child(couvert)" et fin de la 1ere
	# frame apres. Ce delta CONTIENT le pic complet (creation semis via
	# _semis + preparer_les_rendus + etat_initial + poser_plante x N +
	# _process qui pose corps + lignes MMI).
	print("frame | wall ms depuis pose")
	var debut_us := Time.get_ticks_usec()
	grille.add_child(couvert)
	for i in range(FRAMES_APRES_SPAWN):
		await process_frame
		var ecoule_ms := float(Time.get_ticks_usec() - debut_us) / 1000.0
		print("%d | %.3f" % [i, ecoule_ms])
		debut_us = Time.get_ticks_usec()
	var corps_actifs: Dictionary = couvert.get("_corps_actifs")
	var etat: Dictionary = couvert.get("_etat")
	var plantes_size: int = (etat.plantes as Array).size() if not etat.is_empty() else 0
	print("bilan : %d plantes dans etat, %d corps physiques actifs" % [plantes_size, corps_actifs.size()])

	_racine.queue_free()
	for _n in range(30):
		await process_frame

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
