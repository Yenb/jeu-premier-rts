extends SceneTree

# Banc de mesure du temps de tick en regime etabli.
# godot --headless --script jeu/plantes/banc_tick_regime.gd
#
# Construit N plantes d'age disperse (regime, pas une cohorte synchrone),
# joue TICKS_MESURE ticks a pas fixe, et mesure le temps moyen par tick
# (Time.get_ticks_usec autour de Vegetation.avancer). Baseline avant/apres
# pour tout fix du pipeline.

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"
const Vegetation = preload("res://jeu/plantes/vegetation.gd")
const Surface = preload("res://jeu/plantes/surface_terrain.gd")
const EspeceScript = preload("res://jeu/plantes/espece.gd")

const COTE := 260
const COUCHE := 0
const NOM_ESPECE := "arbre"
const TICKS_CHAUFFE := 5
const TICKS_MESURE := 60
const REPETITIONS := 20
const TAILLES := [1000, 5000, 10000]

var _racine: Node3D

func _init() -> void:
	_tout.call_deferred()

func _tout() -> void:
	_racine = Node3D.new()
	get_root().add_child(_racine)
	var grille := _terrain_plat()
	_racine.add_child(grille)
	await process_frame

	var config := Vegetation.charger_config()
	var reglage := _espece_arbre()
	var type := Vegetation.preparer_depuis_champs(String(reglage.nom), reglage.champs(), config)
	reglage.free()
	var types := {NOM_ESPECE: type}
	var releve := Surface.relever(grille)
	var pas_max := Vegetation.pas_maximal(types, config)
	var pas := minf(2.0, pas_max) if pas_max > 0.0 else 2.0

	# INSTRUMENTATION DES COMPTEURS monde.gd : un seul scenario N=1000 (qui
	# croit vers ~1700), chauffe, puis on remet les compteurs a zero et on
	# joue UN tick pour lire requetes / cases_lues / candidats_mesures.
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var semis: Array = []
	var longevite := float(type.longevite)
	var cote_sem := int(sqrt(1000)) + 1
	for i in range(1000):
		var cx := (i % cote_sem) * 2 + 2
		var cz := (i / cote_sem) * 2 + 2
		semis.append({
			"id": "arbre_%d" % i,
			"colonne": Vector2i(cx, cz),
			"type": NOM_ESPECE,
			"age_initial": rng.randf_range(0.0, longevite * 0.9),
		})
	var etat := Vegetation.etat_initial(semis, releve, config, types)
	for _c in range(TICKS_CHAUFFE):
		Vegetation.avancer(etat, config, types, releve, pas)

	var vivantes := Vegetation.vivantes(etat.plantes, config).size()
	var monde = etat.monde
	monde.remettre_les_compteurs()
	var t0 := Time.get_ticks_usec()
	Vegetation.avancer(etat, config, types, releve, pas)
	var us := Time.get_ticks_usec() - t0

	print("=== COMPTEURS monde.gd SUR UN TICK ===")
	print("vivantes                 : %d" % vivantes)
	print("temps du tick            : %.3f ms" % (float(us) / 1000.0))
	print("requetes (choses_dans_rayon) : %d" % monde.requetes)
	print("cases_lues                   : %d" % monde.cases_lues)
	print("candidats_mesures            : %d" % monde.candidats_mesures)
	if monde.requetes > 0:
		print("cases par requete            : %.2f" % (float(monde.cases_lues) / float(monde.requetes)))
		print("candidats par requete        : %.2f" % (float(monde.candidats_mesures) / float(monde.requetes)))
		print("candidats par case           : %.2f" % (float(monde.candidats_mesures) / float(maxi(monde.cases_lues, 1))))

	_racine.queue_free()
	quit(0)

func _une_repetition(config: Dictionary, types: Dictionary, releve: Dictionary,
		type: Dictionary, n: int, pas: float) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var semis: Array = []
	var longevite := float(type.longevite)
	var cote_sem := int(sqrt(n)) + 1
	for i in range(n):
		var cx := (i % cote_sem) * 2 + 2
		var cz := (i / cote_sem) * 2 + 2
		semis.append({
			"id": "arbre_%d" % i,
			"colonne": Vector2i(cx, cz),
			"type": NOM_ESPECE,
			"age_initial": rng.randf_range(0.0, longevite * 0.9),
		})
	var etat := Vegetation.etat_initial(semis, releve, config, types)
	for _c in range(TICKS_CHAUFFE):
		Vegetation.avancer(etat, config, types, releve, pas)
	var temps: Array = []
	for _m in range(TICKS_MESURE):
		var t0 := Time.get_ticks_usec()
		Vegetation.avancer(etat, config, types, releve, pas)
		temps.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	temps.sort()
	return temps[temps.size() / 2]  # mediane par tick de cette repetition

func _rapporter(n: int, echantillons: Array) -> void:
	echantillons.sort()
	var somme := 0.0
	for e in echantillons:
		somme += e
	var moyenne := somme / float(echantillons.size())
	var mediane: float = echantillons[echantillons.size() / 2]
	var var_somme := 0.0
	for e in echantillons:
		var_somme += (e - moyenne) * (e - moyenne)
	var ecart_type := sqrt(var_somme / float(echantillons.size()))
	print("%d | %.3f | %.3f | %.3f | %.3f | %.3f" % [
		n, moyenne, mediane, ecart_type, echantillons[0], echantillons[echantillons.size() - 1]])

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
	espece.nom_stade_1 = "enfant"; espece.duree_stade_1 = 60.0; espece.stature_stade_1 = 2.0
	espece.nom_stade_2 = "ado"; espece.duree_stade_2 = 120.0; espece.stature_stade_2 = 5.0
	espece.nom_stade_3 = "jeune"; espece.duree_stade_3 = 180.0; espece.stature_stade_3 = 9.0
	espece.nom_stade_4 = "adulte"; espece.duree_stade_4 = 240.0; espece.stature_stade_4 = 14.0
	espece.nom_stade_5 = "vieux"; espece.duree_stade_5 = 300.0; espece.stature_stade_5 = 10.0
	espece.nom_stade_6 = "pourri"; espece.duree_stade_6 = 200.0; espece.stature_stade_6 = 7.0
	espece.marge_couches = 8
	espece.trouee_max_voisins = 99
	espece.rayon_dispersion_min = 2; espece.rayon_dispersion_max = 5
	espece.max_voisins = 99
	espece.stade_reproduction_min = 4; espece.stade_reproduction_max = 4
	espece.intervalle_reproduction = 40.0
	espece.stade_production_min = 4; espece.intervalle_production = 120.0
	espece.max_produits_par_plante = 50
	espece.ralentissement_dernier_stade = 1.0
	espece.duree_vie_produit = 300.0
	espece.ressource = "graine"
	espece.rayon_collision = 1.5
	return espece
