extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_persistance.gd
#
# CE QUE LES AUTRES TESTS NE VOYAIENT PAS. Six pertes silencieuses ont traverse
# treize tests verts : chacune ci-dessous a ete constatee AVANT d'etre corrigee,
# et aucune ne faisait rougir quoi que ce soit.
#
# - LE JEU REDESSINE-T-IL CE QUE LA CARTE GARDE ? terrain_visible posait toutes
#   les cellules avec le premier item de la bibliotheque, droit : la carte avait
#   tout garde, l'ecran ne montrait que des cubes ;
# - REPORTER LES PARTICULARITES N'EFFACE PAS CE QU'IL N'A PAS VU. Une colonne
#   absente de la grille retombait au bloc par defaut et ecrasait la rampe que la
#   carte gardait -- invisible, puisque le masque restait juste ;
# - UNE FENETRE QUI SE DIT CHARGEE SANS COLONNES CONNUES NE CREUSE RIEN. Le
#   drapeau survivait a la fermeture de l'editeur, l'ensemble des colonnes non :
#   a la reouverture, l'enregistrement automatique creusait toute la fenetre une
#   seconde et demie plus tard, sans qu'aucun bouton n'ait ete coche ;
# - CE QUI SORT DES COUCHES REPRESENTABLES ALARME. Sculpter sous `couche_base`
#   ou au-dela de la 62e etait jete en silence ;
# - UNE COLONNE ENTIEREMENT CREUSEE DANS LA SCENE RESTE CREUSEE au lancement,
#   au lieu de revenir pleine.
#
# Entree : des cartes et des GridMap construits ici. Sortie : une ligne « OK: »
# et le code 0 si tout tient, « ECHEC: » et le code 1 sinon.
#
# Regles tenues : aucun hasard. Les prints sont des traces de mise au point, pas
# du texte joueur. Rien de scripts/, data/ ni documents/ n'est ecrit, et aucune
# carte du depot n'est touchee.

const Verif = preload("res://scripts/verif.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const Outil = preload("res://jeu/terrain/outil_fenetre.gd")
const TerrainVisible = preload("res://jeu/terrain/terrain_visible.gd")

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"

# UNE SECTION QUI S'INTERROMPT NE COMPTE AUCUN ECHEC : chacune signe.
const SECTIONS := 5

var _v
var _biblio: MeshLibrary
var _racine: Node3D
var _faites := 0

func _init() -> void:
	_v = Verif.new()
	_tout.call_deferred()

func _tout() -> void:
	_biblio = load(CHEMIN_BIBLIOTHEQUE) as MeshLibrary
	if _biblio == null or _biblio.get_item_list().size() < 2:
		_v.v(false, "bloc.tres manque ou n'a qu'un item : rien ne pourrait etre prouve")
		_conclure()
		return
	_racine = Node3D.new()
	get_root().add_child(_racine)

	await _redessin()
	_report_n_efface_pas()
	_fenetre_sans_colonnes()
	_hors_couches()
	_colonne_creusee()
	_conclure()

func _carte(demi: int = 50) -> Resource:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = demi
	return carte

func _grille() -> GridMap:
	var grille := GridMap.new()
	grille.mesh_library = _biblio
	_racine.add_child(grille)
	return grille

func _particulier() -> int:
	var items: Array = _biblio.get_item_list()
	return int(items[items.size() - 1])

# LE DEFAUT LE PLUS GRAVE : la carte gardait tout, le jeu redessinait des cubes.
func _redessin() -> void:
	var carte := _carte()
	var base: int = carte.sommet_de_base()
	var colonne := Vector2i(2, -1)
	var speciale := Vector3i(colonne.x, base + 1, colonne.y)
	var item := _particulier()
	var oriente := 22

	for y in range(carte.couche_base, base + 1):
		carte.poser_cellule(Vector3i(colonne.x, y, colonne.y), 0, 0)
	carte.poser_cellule(speciale, item, oriente)

	# UNE ORIENTATION SEULE, sans changement d'item : posee AVANT le premier
	# rendu, car rafraichir ne repose que ce qui ENTRE dans le disque -- une
	# colonne deja posee n'est pas redessinee si la carte change dessous.
	var tournee := Vector3i(colonne.x + 1, base, colonne.y)
	carte.poser_cellule(tournee, 0, 16)

	var terrain: GridMap = TerrainVisible.new()
	terrain.mesh_library = _biblio
	terrain.carte = carte
	terrain.rayon_cellules = 6
	terrain.groupe_observateur = &"aucun_pour_ce_test"
	_racine.add_child(terrain)
	await process_frame

	_v.v(terrain.get_cell_item(speciale) == item,
		"le jeu redessine l'item %d au lieu de %d : la carte garde, l'ecran perd" % [
			terrain.get_cell_item(speciale), item])
	_v.v(terrain.get_cell_item_orientation(speciale) == oriente,
		"le jeu redessine l'orientation %d au lieu de %d" % [
			terrain.get_cell_item_orientation(speciale), oriente])

	_v.v(terrain.get_cell_item_orientation(tournee) == 16,
		"une orientation seule est perdue au redessin : %d au lieu de 16" % [
			terrain.get_cell_item_orientation(tournee)])

	terrain.queue_free()
	_faites += 1

# REPORTER NE DOIT PAS EFFACER CE QU'IL N'A PAS VU.
func _report_n_efface_pas() -> void:
	var carte := _carte()
	var base: int = carte.sommet_de_base()
	var item := _particulier()

	# Une rampe deja dans la carte, LOIN de ce que la grille portera.
	var lointaine := Vector3i(6, base, 6)
	carte.poser_cellule(lointaine, item, 22)

	# La grille porte assez de colonnes pour passer le garde-fou de
	# recouvrement, mais PAS celle qui tient la rampe.
	var grille := _grille()
	for x in range(-8, 4):
		for z in range(-8, 4):
			for y in range(carte.couche_base, base + 1):
				grille.set_cell_item(Vector3i(x, y, z), 0)

	Outil.enregistrer_fenetre(grille, carte, Vector2i.ZERO, 8)
	_v.v(carte.item_de(lointaine) == item,
		"une rampe hors de ce que la grille porte a ete ecrasee : item %d au lieu de %d" % [
			carte.item_de(lointaine), item])
	_v.v(carte.orientation_de(lointaine) == 22,
		"son orientation a ete ecrasee : %d au lieu de 22" % carte.orientation_de(lointaine))

	grille.queue_free()
	_faites += 1

# UNE FENETRE QUI SE DIT CHARGEE SANS COLONNES CONNUES NE CREUSE RIEN.
func _fenetre_sans_colonnes() -> void:
	var carte := _carte()
	var base: int = carte.sommet_de_base()

	# Du relief partout dans la fenetre, comme apres un vrai travail.
	for x in range(-8, 8):
		for z in range(-8, 8):
			carte.sculpter(Vector2i(x, z), base + 1)
	var avant: int = carte.colonnes_sculptees()
	_v.v(avant > 0, "la carte d'essai est vide : rien ne pourrait etre creuse")

	# La grille ne porte qu'un coin -- assez pour passer RECOUVREMENT_MINIMAL.
	var grille := _grille()
	for x in range(-8, -3):
		for z in range(-8, -3):
			for y in range(carte.couche_base, base + 1):
				grille.set_cell_item(Vector3i(x, y, z), 0)

	# `permises` VIDE : c'est l'etat d'une scene rouverte. Rien ne doit partir.
	Outil.enregistrer_fenetre(grille, carte, Vector2i.ZERO, 8, {})

	var vides := 0
	for x in range(-8, 8):
		for z in range(-8, 8):
			if carte.sommet(Vector2i(x, z)) == null:
				vides += 1
	_v.v(vides == 0,
		"%d colonnes creusees par un enregistrement sans colonnes connues" % vides)

	grille.queue_free()
	_faites += 1

# CE QUI NE PEUT PAS ETRE GARDE SE DIT.
func _hors_couches() -> void:
	var carte := _carte()
	var grille := _grille()

	# Sous couche_base et au-dela de la derniere couche representable.
	grille.set_cell_item(Vector3i(1, carte.couche_base - 1, 1), 0)
	grille.set_cell_item(Vector3i(1, carte.couche_base + CarteTerrain.COUCHES_MAXIMALES, 1), 0)
	grille.set_cell_item(Vector3i(1, carte.couche_base, 1), 0)

	var masques := Outil.volumes_du_gridmap(grille, carte.couche_base)
	# Ce qui tient est garde...
	_v.v(masques.has(Vector2i(1, 1)), "la cellule representable a ete perdue aussi")
	# ... et la DERNIERE couche representable, elle, doit passer.
	var haute := Vector3i(2, carte.couche_base + CarteTerrain.COUCHES_MAXIMALES - 1, 2)
	grille.set_cell_item(haute, 0)
	masques = Outil.volumes_du_gridmap(grille, carte.couche_base)
	_v.v(masques.has(Vector2i(2, 2)),
		"la derniere couche representable (%d) est refusee" % haute.y)

	grille.queue_free()
	_faites += 1

# UNE COLONNE ENTIEREMENT CREUSEE DANS LA SCENE RESTE CREUSEE.
func _colonne_creusee() -> void:
	var carte := _carte()
	var base: int = carte.sommet_de_base()
	var grille := _grille()

	# Un carre de terrain, avec UN trou complet au milieu.
	var trou := Vector2i(3, 3)
	for x in range(0, 7):
		for z in range(0, 7):
			if Vector2i(x, z) == trou:
				continue
			for y in range(carte.couche_base, base + 1):
				grille.set_cell_item(Vector3i(x, y, z), 0)

	# Sans le drapeau, la colonne absente n'est pas touchee : elle revient pleine.
	var temoin := _carte()
	Outil.enregistrer_ce_qui_est_pose(grille, temoin, false)
	_v.v(temoin.sommet(trou) != null,
		"sans le drapeau, une colonne absente est creusee : le comportement par defaut a change")

	# AVEC le drapeau -- ce que fait terrain_visible en reprenant une scene --
	# la colonne comprise dans la boite travaillee est bien creusee.
	Outil.enregistrer_ce_qui_est_pose(grille, carte, true)
	_v.v(carte.sommet(trou) == null,
		"la colonne entierement creusee revient pleine : sommet %s" % [carte.sommet(trou)])
	_v.v(carte.sommet(Vector2i(0, 0)) != null,
		"le terrain autour du trou a ete creuse aussi")
	# HORS de la boite travaillee, rien n'est touche.
	_v.v(carte.sommet(Vector2i(40, 40)) != null,
		"une colonne hors de la boite travaillee a ete creusee")

	grille.queue_free()
	_faites += 1

func _conclure() -> void:
	_v.v(_faites == SECTIONS,
		"%d sections sur %d sont allees jusqu'au bout" % [_faites, SECTIONS])
	if _racine != null:
		_racine.queue_free()
	if _v.echecs() > 0:
		print("ECHEC: la persistance ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: persistance -- le jeu redessine ce que la carte garde (item et orientation), "
		+ "reporter n'efface pas ce qu'il n'a pas vu, une fenetre sans colonnes connues ne creuse "
		+ "rien, les couches hors portee alarment, une colonne creusee reste creusee")
	quit(0)
