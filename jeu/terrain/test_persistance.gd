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
# - PEINDRE UNE CELLULE NE VIDE PAS LA COLONNE. Le releve prenait le masque de
#   la grille TEL QUEL : poser une cellule a l'etage zero -- le reglage par
#   defaut du panneau GridMap -- sur une colonne jamais chargee effacait les six
#   couches sous elle et laissait un puits. Une couche absente de la grille a
#   deux causes qu'on ne distingue pas sans savoir ce qui a ete charge ;
# - LE CURSEUR CHARGE ENCORE APRES REOUVERTURE. `deplacer_vers` refuse de bouger
#   une fenetre qui ne se sait pas chargee : si `fenetre_chargee` ne survit pas a
#   la sauvegarde de la scene, tirer le repere ne charge plus rien. Le drapeau a
#   ete desexporte pour empecher un creusement automatique -- et a emporte le
#   curseur avec lui, sans qu'aucun test ne bouge ;
# - RIEN NE S'EFFACE TOUT SEUL. Sculpter ici, deplacer le repere la-bas,
#   relancer : TOUT doit rester. Trois mecanismes automatiques ont efface du
#   travail dans cette session, chacun pour une raison differente. Il n'y a plus
#   qu'un seul chemin d'enregistrement, et il n'efface jamais.
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
const SECTIONS := 7

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
	await _deplacer_n_efface_rien()
	_peindre_ne_vide_pas()
	await _le_curseur_charge_encore_apres_reouverture()
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

# LE GESTE QUI A FAIT PERDRE LE PLUS DE TRAVAIL : sculpter ici, deplacer le
# repere ailleurs, relancer. Ce qu'on a sculpte AVANT le deplacement doit
# survivre -- il n'a aucun lien avec l'endroit ou pointe le marqueur.
func _deplacer_n_efface_rien() -> void:
	# SA PROPRE RACINE : terrain_commun.gd refuse de choisir entre plusieurs
	# GridMap freres, et les sections precedentes ont laisse les leurs.
	var coin := Node3D.new()
	_racine.add_child(coin)
	var grille := GridMap.new()
	grille.mesh_library = _biblio
	coin.add_child(grille)
	var outil: Node3D = Outil.new()
	coin.add_child(outil)

	var carte := _carte(200)
	var base: int = carte.sommet_de_base()
	outil.carte = carte
	outil.demi_fenetre = 20
	outil.centre = Vector2i.ZERO
	outil.journal = false

	outil.charger = true
	var f := 0
	while not outil.fenetre_chargee and f < 400:
		await process_frame
		f += 1
	_v.v(outil.fenetre_chargee, "le chargement n'a jamais fini : le test ne prouve rien")

	var bloc := _biblio.get_item_list()[0]
	var ici := Vector2i(2, 2)
	for y in range(base + 1, base + 5):
		grille.set_cell_item(Vector3i(ici.x, y, ici.y), int(bloc))
	Outil.enregistrer_ce_qui_est_pose(grille, carte)
	_v.v(carte.sommet(ici) == base + 4, "la sculpture de depart n'est pas enregistree")

	# LE DEPLACEMENT, tres loin.
	var ailleurs := Vector2i(120, 120)
	var fait: bool = await outil.deplacer_vers(ailleurs)
	_v.v(fait, "le deplacement n'a rien fait : le test ne prouve rien")
	_v.v(carte.sommet(ici) == base + 4,
		"deplacer le repere a efface ce qui etait sculpte ailleurs : sommet %s" % [
			carte.sommet(ici)])

	# On sculpte la-bas aussi, et les DEUX doivent tenir.
	var la_bas := Vector2i(122, 122)
	for y in range(base + 1, base + 3):
		grille.set_cell_item(Vector3i(la_bas.x, y, la_bas.y), int(bloc))
	Outil.enregistrer_ce_qui_est_pose(grille, carte)
	_v.v(carte.sommet(la_bas) == base + 2, "la sculpture d'apres n'est pas enregistree")
	_v.v(carte.sommet(ici) == base + 4, "sculpter ailleurs a efface la premiere")

	# ET LE LANCEMENT ne doit rien perdre non plus.
	var terrain: GridMap = TerrainVisible.new()
	terrain.mesh_library = _biblio
	terrain.carte = carte
	terrain.rayon_cellules = 10
	terrain.groupe_observateur = &"aucun_pour_ce_test"
	for cellule in grille.get_used_cells():
		terrain.set_cell_item(cellule, grille.get_cell_item(cellule),
			grille.get_cell_item_orientation(cellule))
	_racine.add_child(terrain)
	await process_frame

	_v.v(carte.sommet(ici) == base + 4,
		"le lancement a efface ce qui etait loin du repere : sommet %s" % [carte.sommet(ici)])
	_v.v(carte.sommet(la_bas) == base + 2, "le lancement a efface la seconde sculpture")

	terrain.queue_free()
	coin.queue_free()
	_faites += 1

# UNE COLONNE ENTIEREMENT CREUSEE : ce qui est POSE est pris, rien n'est efface.
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

	# UNE COLONNE ABSENTE DE LA GRILLE N'EST JAMAIS TOUCHEE, et c'est la regle
	# qui protege tout le reste : absente peut vouloir dire creusee, ou jamais
	# chargee, et rien ne les distingue. On garde.
	Outil.enregistrer_ce_qui_est_pose(grille, carte)
	_v.v(carte.sommet(trou) != null,
		"une colonne absente de la grille a ete creusee : le travail d'ailleurs peut partir")
	_v.v(carte.sommet(Vector2i(0, 0)) != null, "le terrain autour a ete creuse")
	_v.v(carte.sommet(Vector2i(40, 40)) != null, "une colonne lointaine a ete creusee")

	grille.queue_free()
	_faites += 1

# LE PUITS : une cellule peinte a l'etage zero sur une colonne jamais chargee.
func _peindre_ne_vide_pas() -> void:
	var carte := _carte()
	var base: int = carte.sommet_de_base()
	var grille := _grille()
	var colonne := Vector2i(9, 9)

	_v.v(carte.sommet(colonne) == base,
		"la colonne de depart ne porte pas le terrain par defaut")

	# LE GESTE : UNE cellule, tout en bas, sur une colonne que rien n'a chargee.
	grille.set_cell_item(Vector3i(colonne.x, carte.couche_base, colonne.y), 0)
	Outil.enregistrer_ce_qui_est_pose(grille, carte)

	_v.v(carte.sommet(colonne) == base,
		"peindre une cellule en bas a vide la colonne : sommet %s au lieu de %d" % [
			carte.sommet(colonne), base])
	for couche in range(carte.couche_base, base + 1):
		if not carte.est_pleine(colonne, couche):
			_v.v(false, "la couche %d a disparu sous la cellule peinte" % couche)
			break

	# ET UNE COLONNE CHARGEE, elle, peut etre creusee : on sait ce qu'elle porte.
	var chargee := Vector2i(-9, -9)
	var connues: Dictionary = { chargee: true }
	for y in range(carte.couche_base, base + 1):
		grille.set_cell_item(Vector3i(chargee.x, y, chargee.y), 0)
	grille.set_cell_item(Vector3i(chargee.x, base, chargee.y), GridMap.INVALID_CELL_ITEM)
	Outil.enregistrer_ce_qui_est_pose(grille, carte, connues)
	_v.v(not carte.est_pleine(chargee, base),
		"une colonne chargee ne peut plus etre creusee : la sculpture ne s'enregistre plus")

	grille.queue_free()
	_faites += 1

# CE QUI PROTEGE DU CREUSEMENT N'EST PAS CE DRAPEAU, c'est le filtre de
# `enregistrer_ce_qui_est_pose` -- prouve par _peindre_ne_vide_pas. Le drapeau,
# lui, doit SURVIVRE, sinon le curseur devient inerte.
func _le_curseur_charge_encore_apres_reouverture() -> void:
	var outil := Node3D.new()
	outil.set_script(Outil)
	_racine.add_child(outil)

	# 1. IL SURVIT A LA SAUVEGARDE DE LA SCENE. Une propriete non exportee est
	# effacee du .tscn par Godot a la premiere sauvegarde, en silence.
	var range_dans_la_scene := false
	for propriete in outil.get_property_list():
		if propriete.name != "fenetre_chargee":
			continue
		range_dans_la_scene = (int(propriete.usage) & PROPERTY_USAGE_STORAGE) != 0
	_v.v(range_dans_la_scene,
		"fenetre_chargee n'est pas rangee dans la scene : a la reouverture elle "
		+ "revient fausse, et tirer le repere ne charge plus rien")

	# 2. ET C'EST BIEN LUI QUI COMMANDE LE CURSEUR : faux, rien ne se charge.
	outil.carte = _carte()
	outil.suivre_le_curseur = true
	outil.journal = false
	outil.fenetre_chargee = false
	var refus: bool = await outil.deplacer_vers(Vector2i(20, 20))
	_v.v(not refus, "une fenetre qui ne se sait pas chargee a quand meme bouge")

	outil.queue_free()
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
		+ "rien, les couches hors portee alarment, et RIEN ne s'efface tout seul -- "
		+ "ni en deplacant le repere, ni au lancement, ni en peignant une cellule ; "
		+ "et le curseur charge encore apres reouverture de la scene")
	quit(0)
