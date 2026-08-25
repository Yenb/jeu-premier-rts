extends SceneTree

# Test manuel :
# godot --headless --script jeu/plantes/test_compteur_voisins.gd
#
# VERROU D'EXACTITUDE DU COMPTEUR DE VOISINS. Apres chaque operation qui peut
# affecter la population, il verifie que `proprietes.voisins` de CHAQUE plante
# vaut EXACTEMENT le vrai nombre de voisins, recalcule par un scan de controle
# independant. Un compteur incremental qui derive d'un cran fait rougir ce
# test.
#
# Passe sur le code actuel (scan a chaque ecriture, trivialement exact) ET
# doit passer apres le refactor incremental -- c'est sa raison d'etre.
#
# Points verifies :
#   - apres etat_initial
#   - apres chaque avancer() (naissances, morts, changements de stade)
#   - un tick a changement de stade SEUL doit laisser les compteurs identiques
#   - apres retirer() externe
#   - apres une longue sequence mixant les trois
#
# Regles tenues : positions Vector3, colonnes Vector2i. RNG seede. Rien de
# scripts/, data/ ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Vegetation = preload("res://jeu/plantes/vegetation.gd")
const Surface = preload("res://jeu/plantes/surface_terrain.gd")
const EspeceScript = preload("res://jeu/plantes/espece.gd")

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"
const NOM_ESPECE := "arbre"
const COTE := 80
const COUCHE := 0

var _v
var _config: Dictionary = {}
var _types: Dictionary = {}
var _releve: Dictionary = {}
var _rayon := 0.0
var _racine: Node3D

func _init() -> void:
	_v = Verif.new()
	_tout.call_deferred()

func _tout() -> void:
	_racine = Node3D.new()
	get_root().add_child(_racine)
	var grille := _terrain_plat()
	_racine.add_child(grille)
	await process_frame

	_config = Vegetation.charger_config()
	var reglage := _espece_arbre()
	_types = {NOM_ESPECE: Vegetation.preparer_depuis_champs(String(reglage.nom), reglage.champs(), _config)}
	reglage.free()
	_releve = Surface.relever(grille)
	_rayon = Surface.metres_par_cellules(float(_config.rayon_voisinage_cellules), _releve)

	var semis: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var cote_sem := 12
	for i in range(120):
		semis.append({
			"id": "a_%d" % i,
			"colonne": Vector2i((i % cote_sem) * 2 + 2, (i / cote_sem) * 2 + 2),
			"type": NOM_ESPECE,
			"age_initial": rng.randf_range(350.0, 720.0),
		})
	var etat := Vegetation.etat_initial(semis, _releve, _config, _types)
	_verifier(etat, "apres etat_initial")

	var pas := Vegetation.pas_maximal(_types, _config)
	if pas <= 0.0:
		pas = 2.0
	var vu_mort := false
	var vu_naissance := false
	var vu_stade_seul := false
	for t in range(60):
		var rapport := Vegetation.avancer(etat, _config, _types, _releve, pas)
		var m := not (rapport.morts as Array).is_empty()
		var n := not (rapport.naissances as Array).is_empty()
		var s := not (rapport.changements as Array).is_empty()
		if m: vu_mort = true
		if n: vu_naissance = true
		if s and not m and not n:
			vu_stade_seul = true
		_verifier(etat, "apres avancer #%d (morts=%s naissances=%s stade=%s)" % [t, m, n, s])

	_v.v(vu_mort, "aucun tick n'a produit de mort")
	_v.v(vu_naissance, "aucun tick n'a produit de naissance")
	_v.v(vu_stade_seul, "aucun tick n'a eu un changement de stade SANS mort ni naissance : le cas 'stade seul' n'est pas exerce")

	var vivantes := Vegetation.vivantes(etat.plantes, _config)
	_v.v(vivantes.size() > 0, "aucune vivante avant retirer()")
	if vivantes.size() > 0:
		var id_cut := String((vivantes[0] as Dictionary).id)
		_v.v(Vegetation.retirer(etat, id_cut, _config, _releve), "retirer() a echoue")
		_verifier(etat, "apres retirer()")

	for t in range(40):
		Vegetation.avancer(etat, _config, _types, _releve, pas)
		_verifier(etat, "sequence longue #%d" % t)

	_racine.queue_free()
	_conclure()

# LE VERROU : pour chaque plante vivante, proprietes.voisins doit valoir le
# scan de controle frais dans le MEME monde (etat.monde reflete la population
# apres le tick).
func _verifier(etat: Dictionary, ou: String) -> void:
	var monde = etat.monde
	var divergences := 0
	var premiere := ""
	for plante in Vegetation.vivantes(etat.plantes, _config):
		var porte := int(plante.proprietes.get("voisins", -999))
		var reel := Vegetation.voisinage(plante.position, monde, _rayon)
		if porte != reel:
			divergences += 1
			if premiere == "":
				premiere = "'%s' porte %d, controle %d" % [plante.id, porte, reel]
	_v.v(divergences == 0,
		"%s : %d compteur(s) voisins divergent(s) -- premier : %s" % [ou, divergences, premiere])

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
	espece.stade_production_min = 99
	espece.max_produits_par_plante = 0
	espece.ralentissement_dernier_stade = 1.0
	espece.duree_vie_produit = 60.0
	espece.ressource = "graine"
	espece.rayon_collision = 1.5
	return espece

func _conclure() -> void:
	if _v.echecs() > 0:
		print("ECHEC: compteur voisins desynchronise (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: compteur voisins -- exact apres etat_initial, chaque tick (naissance/mort/stade), stade seul, retirer(), sequence longue")
	quit(0)
