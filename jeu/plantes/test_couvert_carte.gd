extends SceneTree

# Test manuel :
# godot --headless --script jeu/plantes/test_couvert_carte.gd
#
# Verrouille le relevé pris sur une CARTE de terrain plutot que sur les cellules
# d'un GridMap -- ce qui permet au couvert de pousser sur un terrain rendu par
# morceaux :
# - LES DEUX SOURCES DISENT LA MEME CHOSE. Sur un terrain entierement rendu, le
#   releve pris sur la carte et celui pris sur les cellules repondent la meme
#   couche et la meme position, colonne par colonne, emprise entiere. Sans ce
#   jugement, la carte pourrait decaler tout le couvert d'une demi-cellule ou
#   d'une couche sans que rien ne rougisse ;
# - UNE GRILLE VIDE NE REND PAS UN TERRAIN VIDE. C'est le cas qui compte : au
#   moment ou le couvert s'eveille, le terrain n'a pose aucune cellule, l'ordre
#   des _ready allant des enfants vers le parent ;
# - LE PLANCHER DU RELIEF IGNORE LES COLONNES CREUSEES. Un seul trou ferait
#   sinon plonger le plafond de toutes les especes ;
# - UNE PLANTE VIT LA OU AUCUNE CELLULE N'EST RENDUE. Le terrain ne pose qu'un
#   disque d'une cellule de rayon, le semis est pose loin dehors, et il pousse
#   quand meme -- ce que le releve pris sur les cellules rendait impossible.
#
# Entree : rien -- carte, terrain et especes sont construits ici. Sortie : une
# ligne « OK: » et le code 0 si tout tient, « ECHEC: » et le code 1 sinon.
#
# LES ESPECES SONT MONTEES ICI, jamais lues dans une scene du jeu : ce qui est
# verrouille est le MECANISME, pas la calibration du jour. Meme regle que
# test_plante.gd, dont ce fichier reprend le montage.
#
# Regles tenues : positions en Vector3, jamais Vector2 -- une COLONNE est un
# Vector2i, un index et pas une position. Aucun hasard. Les prints sont des
# traces de mise au point, pas du texte joueur. Rien de scripts/, data/ ni
# documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Surface = preload("res://jeu/plantes/surface_terrain.gd")
const Couvert = preload("res://jeu/plantes/couvert.gd")
const Vegetation = preload("res://jeu/plantes/vegetation.gd")
const EspeceScript = preload("res://jeu/plantes/espece.gd")
const PlanteScene = preload("res://jeu/plantes/plante.tscn")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const TerrainVisible = preload("res://jeu/terrain/terrain_visible.gd")

const EMPRISE := 6
const ESPECE_HAUTE := "haute"
const ESPECE_BASSE := "basse"

# La colonne du semis lointain : dans l'emprise de la carte, hors de tout ce que
# le terrain rend.
const COLONNE_LOIN := Vector2i(5, 5)

var _v
var _racine: Node3D

func _init() -> void:
	_v = Verif.new()
	_tout.call_deferred()

func _tout() -> void:
	_racine = Node3D.new()
	get_root().add_child(_racine)
	await _les_deux_sources_s_accordent()
	_la_grille_vide()
	_le_plancher()
	await _une_plante_hors_du_rendu()
	_conclure()

# Une carte avec du relief : une butte, un creux, et une colonne creusee jusqu'au
# vide.
func _carte() -> Resource:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = EMPRISE
	carte.sculpter(Vector2i(2, 2), carte.sommet_de_base() + 3)
	carte.sculpter(Vector2i(-1, 4), carte.couche_base)
	carte.sculpter(Vector2i(-3, 1), carte.couche_base - 1)
	return carte

# LES DEUX SOURCES, COLONNE PAR COLONNE, SUR UN TERRAIN ENTIEREMENT RENDU.
func _les_deux_sources_s_accordent() -> void:
	var carte := _carte()
	var grille: GridMap = TerrainVisible.new()
	grille.mesh_library = load("res://jeu/terrain/bloc.tres")
	grille.carte = carte
	# Le rayon couvre les coins de l'emprise : sqrt(6² + 6²) vaut 8,5.
	grille.rayon_cellules = 10
	_racine.add_child(grille)
	await process_frame

	var par_cellules := Surface.relever(grille)
	var par_carte := Surface.relever_depuis_carte(grille, carte)
	_v.v(not (par_cellules.sommets as Dictionary).is_empty(),
		"le terrain temoin n'a rien rendu : la comparaison ne prouverait rien")
	_v.v(int(par_cellules.couche_reference) == int(par_carte.couche_reference),
		"plancher du relief : %d par les cellules, %d par la carte" % [
			int(par_cellules.couche_reference), int(par_carte.couche_reference)])

	var couches := 0
	var positions := 0
	var colonnes := 0
	for x in range(-EMPRISE, EMPRISE):
		for z in range(-EMPRISE, EMPRISE):
			var colonne := Vector2i(x, z)
			colonnes += 1
			var a: Variant = Surface.couche_de(colonne, par_cellules)
			var b: Variant = Surface.couche_de(colonne, par_carte)
			if a != b:
				couches += 1
			var pa: Variant = Surface.position_posee(colonne, par_cellules)
			var pb: Variant = Surface.position_posee(colonne, par_carte)
			if pa == null or pb == null:
				if pa != pb:
					positions += 1
			elif not (pa as Vector3).is_equal_approx(pb as Vector3):
				positions += 1
	_v.v(couches == 0, "%d colonnes sur %d n'ont pas la meme couche selon la source" % [
		couches, colonnes])
	_v.v(positions == 0, "%d colonnes sur %d ne posent pas au meme endroit selon la source" % [
		positions, colonnes])

	# HORS EMPRISE, LES DEUX REFUSENT.
	_v.v(Surface.couche_de(Vector2i(EMPRISE + 4, 0), par_carte) == null,
		"la carte rend une couche hors de son emprise")
	print("sources : %d colonnes comparees, plancher a la couche %d" % [
		colonnes, int(par_carte.couche_reference)])
	grille.queue_free()

# LE CAS QUI COMPTE : la grille est vide, la carte ne l'est pas.
func _la_grille_vide() -> void:
	var carte := _carte()
	var grille: GridMap = GridMap.new()
	grille.cell_size = Vector3(carte.cote, carte.cote, carte.cote)

	var par_cellules := Surface.relever(grille)
	var par_carte := Surface.relever_depuis_carte(grille, carte)
	_v.v(not Surface.porte_du_terrain(par_cellules),
		"un GridMap sans cellule passe pour un terrain plantable")
	_v.v(Surface.porte_du_terrain(par_carte),
		"une carte pleine passe pour un terrain sans colonne")
	_v.v(Surface.couche_de(COLONNE_LOIN, par_cellules) == null,
		"une grille vide rend une couche")
	_v.v(Surface.couche_de(COLONNE_LOIN, par_carte) != null,
		"la carte ne rend aucune couche sur une colonne pleine, grille vide")
	grille.free()

# LE PLANCHER IGNORE LE VIDE, ET SUIT LE CREUX.
func _le_plancher() -> void:
	var plate: Resource = CarteTerrain.new()
	plate.demi_cote = EMPRISE
	_v.v(Surface.plancher_de_carte(plate) == plate.sommet_de_base(),
		"une carte plate n'a pas son sommet par defaut pour plancher")

	var creusee: Resource = CarteTerrain.new()
	creusee.demi_cote = EMPRISE
	creusee.sculpter(Vector2i(0, 0), creusee.couche_base - 1)
	_v.v(Surface.plancher_de_carte(creusee) == creusee.sommet_de_base(),
		"une colonne creusee jusqu'au vide fait plonger le plancher : le plafond de toutes les especes suivrait")

	var en_creux: Resource = CarteTerrain.new()
	en_creux.demi_cote = EMPRISE
	en_creux.sculpter(Vector2i(0, 0), en_creux.couche_base + 1)
	_v.v(Surface.plancher_de_carte(en_creux) == en_creux.couche_base + 1,
		"un creux qui porte encore du terrain ne descend pas le plancher")

# LA PREUVE PAR LA PLANTE : elle vit la ou rien n'est rendu.
#
# LE TERRAIN NE POSE QU'UNE CELLULE DE RAYON, et le semis est a onze cellules de
# la : aucune cellule ne sera jamais posee sous lui. S'il pousse, c'est que sa
# hauteur vient de la carte.
#
# RIEN N'EST APPELE A LA MAIN : ce qui est verrouille est l'ORDRE des _ready, et
# appeler _ready soi-meme le remplacerait par le sien.
func _une_plante_hors_du_rendu() -> void:
	var carte := _carte()
	var grille: GridMap = TerrainVisible.new()
	grille.mesh_library = load("res://jeu/terrain/bloc.tres")
	grille.carte = carte
	grille.rayon_cellules = 1

	var couvert = Couvert.new()
	if couvert == null:
		_v.v(false, "couvert.gd ne s'instancie pas : le script ne compile pas")
		grille.free()
		return
	couvert.name = "Couvert"
	couvert.ticks_prechauffage = 0
	couvert.pas_simulation = 2.0
	couvert.add_child(_espece_haute())
	couvert.add_child(_espece_basse())
	grille.add_child(couvert)

	var releve := Surface.relever_depuis_carte(grille, carte)
	var pose: Variant = Surface.position_posee(COLONNE_LOIN, releve)
	_v.v(pose != null, "la colonne du semis n'a aucun sol sur la carte : le test ne prouverait rien")
	if pose == null:
		grille.free()
		return
	var semis := PlanteScene.instantiate() as Node3D
	semis.name = "semis_loin"
	semis.type = ESPECE_HAUTE
	semis.position = pose
	couvert.add_child(semis)

	_racine.add_child(grille)
	await process_frame

	var pose_par_le_terrain := grille.get_used_cells().size()
	var etat: Dictionary = couvert.get("_etat")
	var releve_pris: Dictionary = couvert.get("_releve")
	_v.v(releve_pris.get("carte") != null,
		"le couvert a releve les cellules alors que le terrain porte une carte")
	_v.v(not etat.is_empty(), "le couvert n'a aucun etat : rien n'a ete seme")
	if etat.is_empty():
		grille.queue_free()
		return
	var config: Dictionary = couvert.get("_config")
	var vivantes: Array = Vegetation.vivantes(etat.plantes, config)
	_v.v(vivantes.size() > 0,
		"aucune plante vivante alors que la carte porte du sol sous le semis")
	_v.v((etat.refus as Array).is_empty(),
		"le semis a ete refuse : %s" % [etat.refus])

	# ET ELLE EST BIEN HORS DU RENDU.
	var rendues := {}
	for cellule in grille.get_used_cells():
		rendues[Vector2i(cellule.x, cellule.z)] = true
	_v.v(not rendues.has(COLONNE_LOIN),
		"la colonne du semis est rendue : le jugement ne prouve plus rien")

	print("plante : %d vivante(s) en colonne %v, alors que le terrain ne rend que %d cellules autour de l'origine" % [
		vivantes.size(), COLONNE_LOIN, pose_par_le_terrain])
	grille.queue_free()

# LES DEUX ESPECES D'ESSAI, montees a la main -- voir l'en-tete.
func _espece_haute() -> Node:
	var espece := EspeceScript.new()
	espece.nom = ESPECE_HAUTE
	espece.nom_stade_1 = "pousse"; espece.duree_stade_1 = 180.0; espece.stature_stade_1 = 2.0
	espece.nom_stade_2 = "mature"; espece.duree_stade_2 = 240.0; espece.stature_stade_2 = 7.5
	espece.nom_stade_3 = "epuise"; espece.duree_stade_3 = 180.0; espece.stature_stade_3 = 5.0
	espece.marge_couches = 8
	espece.trouee_max_voisins = 1
	espece.rayon_dispersion_min = 3; espece.rayon_dispersion_max = 5
	espece.max_voisins = 6
	espece.stade_reproduction_min = 2; espece.stade_reproduction_max = 2
	espece.intervalle_reproduction = 240.0
	espece.stade_production_min = 2; espece.intervalle_production = 120.0
	espece.max_produits_par_plante = 3; espece.ralentissement_dernier_stade = 2.0
	espece.duree_vie_produit = 300.0; espece.ressource = "graine"
	return espece

func _espece_basse() -> Node:
	var espece := EspeceScript.new()
	espece.nom = ESPECE_BASSE
	espece.nom_stade_1 = "brin"; espece.duree_stade_1 = 25.0; espece.stature_stade_1 = 0.4
	espece.nom_stade_2 = "touffe"; espece.duree_stade_2 = 35.0; espece.stature_stade_2 = 0.8
	espece.nom_stade_3 = "montee"; espece.duree_stade_3 = 40.0; espece.stature_stade_3 = 1.0
	espece.marge_couches = 6
	espece.trouee_max_voisins = 8
	espece.rayon_dispersion_min = 1; espece.rayon_dispersion_max = 2
	espece.max_voisins = 14
	espece.stade_reproduction_min = 2; espece.stade_reproduction_max = 3
	espece.intervalle_reproduction = 30.0
	espece.stade_production_min = 99
	espece.max_produits_par_plante = 0; espece.ralentissement_dernier_stade = 1.0
	espece.duree_vie_produit = 60.0; espece.ressource = "herbe"
	return espece

func _conclure() -> void:
	if _racine != null:
		_racine.queue_free()
	if _v.echecs() > 0:
		print("ECHEC: le releve sur carte ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: releve sur carte -- meme reponse que les cellules la ou elles existent, et une plante qui vit la ou il n'y en a aucune")
	quit(0)
