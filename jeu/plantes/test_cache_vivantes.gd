extends SceneTree

# Test manuel :
# godot --headless --script jeu/plantes/test_cache_vivantes.gd
#
# VERROU DE SYNCHRONISATION DU CACHE DES VIVANTES. A chaque operation qui
# peut affecter la population, il verifie que la liste vivante consommee par
# le pipeline correspond EXACTEMENT aux plantes non-mortes.
#
# CE TEST EXISTE ET PASSE AVANT le refactor du cache. Il sert de garde a
# chaque etape : un cache qui diverge silencieusement dans un cas de bord
# fait rougir ce test, quel que soit le cas.
#
# DEUX INVARIANTS a chaque point observable :
#   (A) etat.plantes ne contient AUCUNE morte -- vrai aux FRONTIERES de tick
#       sur le code actuel (§8 purge en fin de avancer), et vrai en
#       permanence apres le refactor (etat.plantes devient le cache propre).
#   (B) vivantes() rend exactement le compte des non-mortes, memes ids.
#
# Points observables (les §2/§7/§8 internes ne sont pas observables de
# l'exterieur d'un avancer -- ils sont couverts par la frontiere de tick
# qui suit, ou tout ecart de cache aurait survecu) :
#   1. apres etat_initial
#   2. apres chaque avancer() complet (morts + naissances + purge)
#   3. apres retirer() externe
#   4. apres _consommer_file_peuplement (batch Peuplement, via un Couvert)
#
# Regles tenues : positions en Vector3, colonnes en Vector2i. Aucun hasard
# hors du RNG seede. Rien de scripts/, data/ ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Vegetation = preload("res://jeu/plantes/vegetation.gd")
const Surface = preload("res://jeu/plantes/surface_terrain.gd")
const Couvert = preload("res://jeu/plantes/couvert.gd")
const EspeceScript = preload("res://jeu/plantes/espece.gd")
const PeuplementScript = preload("res://jeu/plantes/peuplement.gd")

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"
const NOM_ESPECE := "arbre"
const COTE := 60
const COUCHE := 0

var _v
var _config: Dictionary = {}
var _types: Dictionary = {}
var _releve: Dictionary = {}
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

	# --- 1. apres etat_initial ---
	var semis: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var longevite := float((_types[NOM_ESPECE] as Dictionary).longevite)
	var cote_sem := 14
	for i in range(150):
		var cx := (i % cote_sem) * 3 + 2
		var cz := (i / cote_sem) * 3 + 2
		semis.append({
			"id": "a_%d" % i,
			"colonne": Vector2i(cx, cz),
			"type": NOM_ESPECE,
			# Fenetre choisie pour couvrir a la fois le stade ADULTE fertile
			# (reproduction, ~360-600 pour cette espece) et le passage en
			# vieux/pourri qui mene a la mort dans les ~500 s simulees.
			"age_initial": rng.randf_range(350.0, 720.0),
		})
	var etat := Vegetation.etat_initial(semis, _releve, _config, _types)
	_verifier(etat, "1 apres etat_initial")

	# --- 2. apres chaque avancer() (morts, naissances, purge §8) ---
	var pas := Vegetation.pas_maximal(_types, _config)
	if pas <= 0.0:
		pas = 2.0
	var vu_mort := false
	var vu_naissance := false
	for t in range(50):
		var rapport := Vegetation.avancer(etat, _config, _types, _releve, pas)
		if not (rapport.morts as Array).is_empty():
			vu_mort = true
		if not (rapport.naissances as Array).is_empty():
			vu_naissance = true
		_verifier(etat, "2 apres avancer #%d" % t)
	_v.v(vu_mort, "2 aucun tick n'a produit de mort : le scenario ne verrouille pas la purge")
	_v.v(vu_naissance, "2 aucun tick n'a produit de naissance : le scenario ne verrouille pas l'ajout")

	# --- 3. apres retirer() externe ---
	var vivantes_avant := Vegetation.vivantes(etat.plantes, _config)
	_v.v(vivantes_avant.size() > 0, "3 aucune vivante avant retirer() : rien a couper")
	if vivantes_avant.size() > 0:
		var id_a_retirer := String((vivantes_avant[0] as Dictionary).id)
		var ok := Vegetation.retirer(etat, id_a_retirer, _config, _releve)
		_v.v(ok, "3 retirer() a echoue sur un id vivant")
		_verifier(etat, "3 apres retirer()")

	# --- 4. apres _consommer_file_peuplement ---
	await _verifier_peuplement()

	_racine.queue_free()
	_conclure()

# LE COEUR DU VERROU : compare la liste vivante du pipeline au filtrage
# manuel des non-mortes.
func _verifier(etat: Dictionary, ou: String) -> void:
	var attendu_ids: Dictionary = {}
	for plante in (etat.plantes as Array):
		if not Vegetation.est_disparue(plante, _config):
			attendu_ids[String(plante.id)] = true

	# (A) aucune morte non purgee dans etat.plantes.
	var mortes := 0
	for plante in (etat.plantes as Array):
		if Vegetation.est_disparue(plante, _config):
			mortes += 1
	_v.v(mortes == 0,
		"%s : etat.plantes contient %d morte(s) non purgee(s)" % [ou, mortes])

	# (B) vivantes() rend exactement le compte attendu, memes ids.
	var rendu := Vegetation.vivantes(etat.plantes, _config)
	_v.v(rendu.size() == attendu_ids.size(),
		"%s : vivantes() rend %d, attendu %d" % [ou, rendu.size(), attendu_ids.size()])
	for plante in rendu:
		_v.v(attendu_ids.has(String(plante.id)),
			"%s : vivantes() rend un id inattendu %s" % [ou, plante.id])

func _verifier_peuplement() -> void:
	var grille := _terrain_plat()
	var couvert = Couvert.new()
	couvert.name = "CouvertTest"
	couvert.ticks_prechauffage = 0
	couvert.pas_simulation = 2.0
	couvert.rayon_collision_metres = 100.0
	couvert.add_child(_espece_arbre())
	var obs := Node3D.new()
	obs.name = "obs"
	obs.add_to_group("observateur")
	_racine.add_child(obs)

	var peuplement := Node3D.new()
	peuplement.set_script(PeuplementScript)
	peuplement.name = "PeuplTest"
	peuplement.position = Vector3(30.0, 1.0, 30.0)
	peuplement.set("espece", NOM_ESPECE)
	peuplement.set("rayon_dispersion", 15.0)
	peuplement.set("seed_rng", 99)
	peuplement.set("budget_par_frame", 30)
	var nombres: Array[int] = [0, 0, 0, 80, 0, 0]
	peuplement.set("nombres_par_stade", nombres)
	couvert.add_child(peuplement)

	_racine.add_child(grille)
	grille.add_child(couvert)
	for _i in range(10):
		await process_frame

	var etat: Dictionary = couvert.get("_etat")
	if etat.is_empty():
		_v.v(false, "4 le couvert n'a pas d'etat apres consommation peuplement")
		return
	_v.v((etat.plantes as Array).size() > 0, "4 aucune plante apres consommation peuplement")
	_verifier(etat, "4 apres _consommer_file_peuplement")

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
		print("ECHEC: cache vivantes desynchronise (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: cache vivantes -- synchronise apres etat_initial, chaque tick (morts+naissances+purge), retirer(), et consommation peuplement")
	quit(0)
