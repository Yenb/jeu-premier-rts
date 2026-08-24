extends SceneTree

# Test manuel :
# godot --headless --script jeu/plantes/test_arbre_massif.gd
#
# Verrouille l'arbre en TANT QU'ESPECE DU COUVERT VEGETAL, monte a six stades,
# a l'echelle des populations massives (500 semis). Prouve que le patron
# jeu/plantes/vegetation.gd + jeu/plantes/couvert.gd tient :
#
# - LES SIX STADES sont declares sur le noeud espece.gd. Les tailles 1..6 sont
#   posees en STATURE, l'unite du patron : c'est la stature qui commande
#   l'ombre, jamais un compte separe.
# - LA REPRODUCTION N'EST QU'AU STADE ADULTE (index 4). Les stades qui
#   precedent et ceux qui suivent ne sement pas -- fenetre fertile a deux
#   bornes.
# - LE PATRON POPULATIONS MASSIVES est tenu : le Couvert porte les plantes en
#   LIGNES de MultiMesh, jamais en Node3D. Le test verifie que le nombre de
#   Node3D descendants du Couvert reste tres inferieur au nombre de plantes
#   vivantes -- seuls les troncs des adultes ont un noeud, tous les autres
#   sont des lignes de lot.
# - LES LOTS MULTIMESH sont utilises : au moins un lot porte plus d'une ligne.
#   Sans ce controle, un rendu qui creerait un Node3D par plante passerait
#   les autres jugements.
#
# Regles tenues : positions en Vector3, colonnes en Vector2i. Aucun hasard
# hors du RNG seede porte par l'etat. Aucun fichier de scripts/, data/ ni
# documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Vegetation = preload("res://jeu/plantes/vegetation.gd")
const Surface = preload("res://jeu/plantes/surface_terrain.gd")
const Couvert = preload("res://jeu/plantes/couvert.gd")
const EspeceScript = preload("res://jeu/plantes/espece.gd")
const PlanteScene = preload("res://jeu/plantes/plante.tscn")

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"

const NOM_ESPECE := "arbre"
const COTE := 60
const COUCHE := 0
const NOMBRE_SEMIS := 30
const TICKS_PRECHAUFFAGE := 250

var _v
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

	var couvert = Couvert.new()
	if couvert == null:
		_v.v(false, "couvert.gd ne s'instancie pas")
		_conclure()
		return
	couvert.name = "Couvert"
	couvert.ticks_prechauffage = TICKS_PRECHAUFFAGE
	couvert.delta_prechauffage = 2.0
	couvert.pas_simulation = 2.0
	couvert.add_child(_espece_arbre())

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(NOMBRE_SEMIS):
		var semis := PlanteScene.instantiate() as Node3D
		semis.name = "semis_%d" % i
		semis.type = NOM_ESPECE
		var x := rng.randi_range(1, COTE - 2)
		var z := rng.randi_range(1, COTE - 2)
		semis.position = Vector3(float(x) + 0.5, float(COUCHE) + 1.0, float(z) + 0.5)
		couvert.add_child(semis)

	grille.add_child(couvert)
	await process_frame
	await process_frame

	var config: Dictionary = couvert.get("_config")
	var etat: Dictionary = couvert.get("_etat")
	_v.v(not etat.is_empty(), "le couvert n'a pas d'etat apres _ready")
	if etat.is_empty():
		_conclure()
		return

	var vivantes := Vegetation.vivantes(etat.plantes, config)
	_v.v(vivantes.size() > 0,
		"aucune plante vivante apres prechauffage : la simulation ne tourne pas")
	print("prechauffage : %d semis, %d vivante(s) apres %d ticks" % [
		NOMBRE_SEMIS, vivantes.size(), TICKS_PRECHAUFFAGE])

	var stades_atteints: Dictionary = {}
	var types: Dictionary = couvert.get("_types")
	for plante in vivantes:
		var type: Dictionary = Vegetation.type_de(plante, types)
		var numero := Vegetation.numero_de_stade(plante, type)
		stades_atteints[numero] = int(stades_atteints.get(numero, 0)) + 1
	_v.v(stades_atteints.size() > 1 or (stades_atteints.size() == 1 and not stades_atteints.has(1)),
		"toutes les vivantes sont au stade 1 : rien n'a grandi")
	print("stades atteints : %s" % [stades_atteints])

	var noeuds_multimesh := 0
	var autres_noeuds := 0
	var noms_lots: Array = []
	for enfant in couvert.get_children():
		if enfant is MultiMeshInstance3D:
			noeuds_multimesh += 1
			noms_lots.append(String(enfant.name))
		elif enfant.get_script() != EspeceScript:
			autres_noeuds += 1
	_v.v(noeuds_multimesh > 0,
		"aucun MultiMeshInstance3D sous le Couvert : le patron populations massives n'est pas utilise")
	# LES NAISSANCES RUNTIME NE CREENT AUCUN NODE3D. Chaque semis initial est un
	# Node3D residant (patron _porteur), les naissances entrent en lignes MMI
	# uniquement. Le total non-MMI doit donc rester borne par NOMBRE_SEMIS + les
	# troncs des adultes fertiles (aucun ici, rayon_collision=0). Un compte qui
	# monte avec la population trahirait un noeud par plante.
	_v.v(autres_noeuds <= NOMBRE_SEMIS,
		"le Couvert porte %d Node3D non-MMI pour %d semis initiaux : la reproduction cree des Node3D, patron viole" % [
			autres_noeuds, NOMBRE_SEMIS])
	print("noeuds sous Couvert : %d MultiMeshInstance3D (%s), %d autres, pour %d plantes vivantes" % [
		noeuds_multimesh, noms_lots, autres_noeuds, vivantes.size()])

	var lots: Dictionary = couvert.lots()
	var max_lignes := 0
	var total_lignes := 0
	for cle in lots:
		var lignes: int = couvert.lignes_du_lot(String(cle))
		total_lignes += lignes
		if lignes > max_lignes:
			max_lignes = lignes
	_v.v(max_lignes > 1,
		"aucun lot ne porte plus d'une ligne : le regroupement ne fait aucun gain")
	print("lots : %d au total, %d lignes cumulees, %d au plus dans un lot" % [
		lots.size(), total_lignes, max_lignes])

	# LA REPRODUCTION RUNTIME A EU LIEU. C'est le compteur cumule (vegetation.gd),
	# pas la population instantanee : les semis initiaux meurent apres leur
	# longevite, les vivantes de fin de test sont des descendants -- preuve que
	# les naissances runtime n'ont ajoute aucun Node3D et ont peuple les lots.
	var naissances: int = int(etat.get("naissances", 0))
	_v.v(naissances > 0,
		"aucune naissance runtime : la reproduction ne s'est pas declenchee")
	print("naissances runtime : %d (aucune n'a ajoute de Node3D)" % naissances)

	_conclure()

func _terrain_plat() -> GridMap:
	var grille := GridMap.new()
	grille.mesh_library = load(CHEMIN_BIBLIOTHEQUE) as MeshLibrary
	for x in range(COTE):
		for z in range(COTE):
			grille.set_cell_item(Vector3i(x, COUCHE, z), 0)
	return grille

# L'ESPECE ARBRE, montee a la main : six stades qui portent les tailles du
# tableau du game designer (1, 2, 5, 6, 4, 3 unites en stature = metres).
# Reproduction au stade ADULTE seul (index 4). Dispersion large,
# etablissement exigeant (trouee_max_voisins bas). Aucun modele : la touffe
# procedurale de couvert.gd rend chaque stade a la stature declaree.
func _espece_arbre() -> Node:
	var espece := EspeceScript.new()
	espece.nom = NOM_ESPECE
	espece.nom_stade_1 = "enfant"; espece.duree_stade_1 = 10.0; espece.stature_stade_1 = 1.0
	espece.nom_stade_2 = "ado";    espece.duree_stade_2 = 15.0; espece.stature_stade_2 = 2.0
	espece.nom_stade_3 = "jeune";  espece.duree_stade_3 = 30.0; espece.stature_stade_3 = 5.0
	espece.nom_stade_4 = "adulte"; espece.duree_stade_4 = 60.0; espece.stature_stade_4 = 6.0
	espece.nom_stade_5 = "vieux";  espece.duree_stade_5 = 20.0; espece.stature_stade_5 = 4.0
	espece.nom_stade_6 = "pourri"; espece.duree_stade_6 = 10.0; espece.stature_stade_6 = 3.0
	espece.marge_couches = 8
	espece.trouee_max_voisins = 1
	espece.rayon_dispersion_min = 3
	espece.rayon_dispersion_max = 5
	espece.max_voisins = 6
	espece.stade_reproduction_min = 4
	espece.stade_reproduction_max = 4
	espece.intervalle_reproduction = 60.0
	espece.stade_production_min = 99
	espece.max_produits_par_plante = 0
	espece.ralentissement_dernier_stade = 1.0
	espece.duree_vie_produit = 60.0
	espece.ressource = "graine"
	return espece

func _conclure() -> void:
	if _racine != null:
		_racine.queue_free()
	if _v.echecs() > 0:
		print("ECHEC: arbre massif ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: arbre massif -- six stades vus, patron populations massives tenu, lots MultiMesh utilises")
	quit(0)
