extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_outil_fenetre.gd
#
# Verrouille res://jeu/terrain/outil_fenetre.gd, le passage de la fenetre entre
# la carte et le GridMap :
# - LA FENETRE SE POSE LA OU ELLE EST SUR LA CARTE. La colonne 1000 devient la
#   cellule 1000 du GridMap, jamais une cellule autour de l'origine : deplacer
#   le curseur doit DEPLACER le terrain rendu, pas en changer le contenu sur
#   place. Une fenetre centree loin de l'origine est le seul cas ou cela se
#   voit -- au centre (0,0) tout se confond et le test serait aveugle ;
# - charger rend le relief que la carte decrit, colonne vide comprise ;
# - charger EFFACE ce qui etait pose : un relief plus bas que le precedent ne
#   laisse rien depasser ;
# - l'aller-retour est l'IDENTITE : charger puis enregistrer sans rien toucher
#   ne change aucun sommet de la carte ;
# - sculpter dans le GridMap puis enregistrer ecrit la hauteur sculptee dans la
#   carte, a la bonne colonne ;
# - une colonne CREUSEE jusqu'au vide s'ecrit comme vide. C'est le cas que
#   « n'ecrire que ce qu'on voit » raterait : une colonne sans cellule
#   resterait pleine dans la carte ;
# - une fenetre a cheval sur le bord de l'emprise ne charge ni n'ecrit dehors ;
# - CHARGER POSE SANS COLLISION, ET VIDER REND LA BIBLIOTHEQUE DE JEU. Un
#   GridMap cree un corps physique par cellule, paye a la frame qui suit :
#   mesure a 28 secondes pour 630 000 cellules, contre 267 ms sans les formes.
#   Le jour ou la bibliotheque allegee resterait sur le terrain, le jeu aurait
#   un sol traversable et aucun test de correction ne rougirait ;
# - LA BIBLIOTHEQUE DE JEU N'EST MISE DE COTE QU'UNE FOIS. Deux chargements de
#   suite mettraient sinon de cote la version allegee, qui deviendrait ce que
#   « vider » restaure ;
# - DEPLACER EST UN SEUL GESTE : ce qui etait sous la fenetre part dans la carte
#   ET sur le disque, puis la nouvelle zone se rend. C'est la raison d'etre de
#   la fenetre -- ne jamais tenir plus qu'un endroit en cellules. Un
#   deplacement qui ne ferait que changer un chiffre laisserait le travail dans
#   le GridMap, ou le chargement suivant l'effacerait sans un mot ;
# - SANS FENETRE CHARGEE, DEPLACER N'ECRIT RIEN : viser sur une scene qu'on
#   vient d'ouvrir ne doit declencher aucune ecriture ;
# - VIDER INVALIDE LA FENETRE. Un GridMap vide releve des colonnes vides
#   partout : l'enregistrer effacerait six cents metres de sculpture dans la
#   carte, en une case cochee, sans que rien a l'ecran ne le montre.
#
# Entree : la bibliotheque res://jeu/terrain/bloc.tres et des GridMap construits
# ici, jamais enregistres dans une scene. Sortie : une ligne « OK: » et le code
# 0 si tout tient, « ECHEC: » et le code 1 sinon.
#
# LE NOEUD N'EST PAS INSTANCIE : tout ce qui decide est statique, et les cases
# de l'inspecteur ne font que declencher. Ce test appelle les memes fonctions
# que l'editeur, sans editeur.
#
# Regles tenues : positions en Vector3i (grille), jamais Vector2 -- une colonne
# est un Vector2i. Aucun hasard. Les prints sont des traces de mise au point,
# pas du texte joueur. Rien de scripts/, data/ ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const OutilFenetre = preload("res://jeu/terrain/outil_fenetre.gd")
const Commun = preload("res://jeu/terrain/terrain_commun.gd")

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"

# Une fenetre courte : ce qui est verrouille est le transfert, pas une taille.
const DEMI := 8

# LE CENTRE N'EST PAS L'ORIGINE, ET C'EST TOUT L'INTERET : un decalage applique
# a l'envers passerait inapercu sur une fenetre centree.
const CENTRE := Vector2i(1000, -700)

var _v
var _bibliotheque: MeshLibrary

func _init() -> void:
	_v = Verif.new()
	# UN SCRIPT QUI NE COMPILE PAS ROUGIT, IL NE SE SAUTE PAS. Sans ce jugement,
	# chaque appel plante isolement, aucun _v.v ne s'execute, et le test conclut
	# OK sur zero echec -- le faux vert exact que ce projet a deja paye.
	var temoin: Node = OutilFenetre.new()
	if temoin == null:
		_v.v(false, "outil_fenetre.gd ne s'instancie pas : le script ne compile pas")
		_conclure()
		return
	temoin.free()
	_bibliotheque = load(CHEMIN_BIBLIOTHEQUE) as MeshLibrary
	if _bibliotheque == null:
		_v.v(false, "%s ne se charge pas" % CHEMIN_BIBLIOTHEQUE)
		_conclure()
		return
	_decalage()
	_chargement()
	_aller_retour()
	_sculpture_enregistree()
	_bord_emprise()
	_garde_fou()
	_vidage()
	await _deplacement()
	_conclure()

func _grille_neuve() -> GridMap:
	var grille := GridMap.new()
	grille.cell_size = Vector3(2.0, 2.0, 2.0)
	grille.mesh_library = _bibliotheque
	get_root().add_child(grille)
	return grille

func _carte_neuve() -> Resource:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 2500
	return carte

func _decalage() -> void:
	var colonnes := OutilFenetre.colonnes_de(CENTRE, DEMI)
	_v.v(colonnes.size() == DEMI * DEMI * 4,
		"la fenetre compte %d colonnes, %d attendues" % [colonnes.size(), DEMI * DEMI * 4])

	# ELLE COUVRE LES COLONNES DE LA CARTE AUTOUR DE SON CENTRE, jamais des
	# colonnes autour de l'origine.
	_v.v(colonnes.has(CENTRE), "la fenetre ne couvre pas son propre centre")
	_v.v(colonnes.has(CENTRE + Vector2i(-DEMI, DEMI - 1)), "un coin de la fenetre manque")
	_v.v(not colonnes.has(CENTRE + Vector2i(DEMI, 0)),
		"la fenetre deborde de sa demi-largeur")
	_v.v(not colonnes.has(Vector2i.ZERO),
		"la fenetre couvre l'origine alors qu'elle est centree en %v" % CENTRE)

	# Une fenetre ailleurs couvre d'autres colonnes : elle SE DEPLACE.
	var ailleurs := OutilFenetre.colonnes_de(Vector2i.ZERO, DEMI)
	_v.v(not ailleurs.has(CENTRE),
		"deux fenetres de centres differents couvrent les memes colonnes")

func _chargement() -> void:
	var carte := _carte_neuve()
	var base: int = carte.sommet_de_base()
	var monte := Vector2i(1002, -698)
	var creuse := Vector2i(998, -702)
	carte.sculpter(monte, base + 5)
	carte.sculpter(creuse, carte.couche_base - 1)

	var grille := _grille_neuve()
	var bloc := Commun.premier_bloc(grille)
	var colonnes := OutilFenetre.colonnes_de(CENTRE, DEMI)
	OutilFenetre.charger_tranche(grille, carte, colonnes, CENTRE, bloc, 0, colonnes.size())

	var sommets := OutilFenetre.sommets_du_gridmap(grille)
	# LA CELLULE POSEE PORTE LA COLONNE DE LA CARTE, sans conversion.
	_v.v(int(sommets.get(monte, -99)) == base + 5,
		"la colonne montee arrive a %s dans le GridMap, %d attendu" % [
			sommets.get(monte, null), base + 5])
	_v.v(not sommets.has(creuse),
		"la colonne creusee jusqu'au vide a quand meme ete posee")
	_v.v(int(sommets.get(CENTRE, -99)) == base,
		"une colonne non sculptee n'arrive pas au sommet par defaut")
	_v.v(not sommets.has(Vector2i.ZERO),
		"une cellule a ete posee a l'origine alors que la fenetre est en %v" % CENTRE)

	# CHARGER EFFACE : on recharge une carte VIERGE par-dessus, la colonne montee
	# doit redescendre au defaut.
	var vierge := _carte_neuve()
	grille.clear()
	OutilFenetre.charger_tranche(grille, vierge, colonnes, CENTRE, bloc, 0, colonnes.size())
	sommets = OutilFenetre.sommets_du_gridmap(grille)
	_v.v(int(sommets.get(monte, -99)) == base,
		"le relief precedent depasse encore apres un rechargement")
	grille.queue_free()

func _aller_retour() -> void:
	var carte := _carte_neuve()
	var base: int = carte.sommet_de_base()
	carte.sculpter(Vector2i(1003, -703), base + 2)
	carte.sculpter(Vector2i(996, -696), carte.couche_base)
	var avant: int = carte.colonnes_sculptees()

	var grille := _grille_neuve()
	var bloc := Commun.premier_bloc(grille)
	var colonnes := OutilFenetre.colonnes_de(CENTRE, DEMI)
	OutilFenetre.charger_tranche(grille, carte, colonnes, CENTRE, bloc, 0, colonnes.size())
	var changees := OutilFenetre.enregistrer_fenetre(grille, carte, CENTRE, DEMI)

	_v.v(changees == 0,
		"l'aller-retour a change %d colonnes alors que rien n'a ete sculpte" % changees)
	_v.v(carte.colonnes_sculptees() == avant,
		"l'aller-retour laisse %d colonnes stockees contre %d avant" % [
			carte.colonnes_sculptees(), avant])
	_v.v(carte.sommet(Vector2i(1003, -703)) == base + 2,
		"le sommet monte n'a pas survecu a l'aller-retour")
	_v.v(carte.sommet(Vector2i(996, -696)) == carte.couche_base,
		"le sommet creuse n'a pas survecu a l'aller-retour")
	grille.queue_free()

func _sculpture_enregistree() -> void:
	var carte := _carte_neuve()
	var base: int = carte.sommet_de_base()
	var grille := _grille_neuve()
	var bloc := Commun.premier_bloc(grille)
	var colonnes := OutilFenetre.colonnes_de(CENTRE, DEMI)
	OutilFenetre.charger_tranche(grille, carte, colonnes, CENTRE, bloc, 0, colonnes.size())

	# On sculpte comme le ferait outil_sculpture.gd : dans les cellules du
	# GridMap, qui portent desormais les colonnes de la carte.
	var butte := CENTRE + Vector2i(2, -4)
	for y in range(base + 1, base + 4):
		grille.set_cell_item(Vector3i(butte.x, y, butte.y), bloc)
	var trou := CENTRE + Vector2i(-5, 6)
	for y in range(carte.couche_base, base + 1):
		grille.set_cell_item(Vector3i(trou.x, y, trou.y), GridMap.INVALID_CELL_ITEM)

	var changees := OutilFenetre.enregistrer_fenetre(grille, carte, CENTRE, DEMI)
	_v.v(changees == 2, "%d colonnes changees, 2 sculptees" % changees)
	_v.v(carte.sommet(butte) == base + 3,
		"la butte s'ecrit a %s dans la carte, %d attendu" % [carte.sommet(butte), base + 3])
	# LE CAS QUE « n'ecrire que ce qu'on voit » RATERAIT.
	_v.v(carte.sommet(trou) == null,
		"le trou creuse jusqu'au vide n'est pas ecrit comme vide : %s" % [carte.sommet(trou)])
	# Et rien n'a bouge la ou la fenetre n'est pas.
	_v.v(carte.sommet(Vector2i.ZERO) == base,
		"une colonne hors de la fenetre a ete touchee")
	grille.queue_free()

func _bord_emprise() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 20
	var grille := _grille_neuve()
	var bloc := Commun.premier_bloc(grille)
	# Centre pose au coin : une partie de la fenetre tombe hors emprise.
	var centre := Vector2i(19, 19)
	var colonnes := OutilFenetre.colonnes_de(centre, DEMI)
	OutilFenetre.charger_tranche(grille, carte, colonnes, centre, bloc, 0, colonnes.size())

	var dehors := 0
	for cellule in grille.get_used_cells():
		if not carte.dans_emprise(Vector2i(cellule.x, cellule.z)):
			dehors += 1
	_v.v(dehors == 0, "%d cellules chargees hors emprise" % dehors)
	_v.v(not grille.get_used_cells().is_empty(),
		"une fenetre a cheval sur le bord n'a rien charge du tout")

	# Et l'enregistrement n'ecrit rien dehors.
	OutilFenetre.enregistrer_fenetre(grille, carte, centre, DEMI)
	for colonne in carte.reliefs:
		if not carte.dans_emprise(colonne):
			_v.v(false, "colonne %v ecrite hors emprise" % colonne)
			break
	grille.queue_free()

func _garde_fou() -> void:
	# Le garde-fou vit dans la methode d'instance, qui a besoin d'un frere
	# GridMap : on monte la scene minimale qu'attend terrain_commun.gd.
	var racine := Node3D.new()
	get_root().add_child(racine)
	var grille := GridMap.new()
	grille.cell_size = Vector3(2.0, 2.0, 2.0)
	grille.mesh_library = _bibliotheque
	racine.add_child(grille)
	var outil: Node3D = OutilFenetre.new()
	racine.add_child(outil)

	var carte := _carte_neuve()
	outil.carte = carte
	outil.demi_fenetre = DEMI
	outil.centre = CENTRE
	_v.v(not outil.fenetre_chargee, "l'outil se croit charge avant tout chargement")

	# Enregistrer sans avoir charge ne doit RIEN ecrire.
	var avant: int = carte.colonnes_sculptees()
	outil.enregistrer = true
	_v.v(carte.colonnes_sculptees() == avant,
		"enregistrer sans fenetre chargee a ecrit dans la carte")

	# Charge, puis centre deplace : refus egalement.
	outil.centre_charge = CENTRE
	outil.fenetre_chargee = true
	outil.centre = Vector2i(0, 0)
	grille.set_cell_item(Vector3i(0, 0, 0), Commun.premier_bloc(grille))
	avant = carte.colonnes_sculptees()
	outil.enregistrer = true
	_v.v(carte.colonnes_sculptees() == avant,
		"enregistrer a un centre different du centre charge a ecrit dans la carte")

	racine.queue_free()

func _vidage() -> void:
	var racine := Node3D.new()
	get_root().add_child(racine)
	var grille := GridMap.new()
	grille.cell_size = Vector3(2.0, 2.0, 2.0)
	grille.mesh_library = _bibliotheque
	racine.add_child(grille)
	var outil: Node3D = OutilFenetre.new()
	racine.add_child(outil)

	var carte := _carte_neuve()
	var base: int = carte.sommet_de_base()
	carte.sculpter(Vector2i(1001, -701), base + 4)
	outil.carte = carte
	outil.demi_fenetre = DEMI
	outil.centre = CENTRE

	var de_jeu := grille.mesh_library
	var formes_avant := de_jeu.get_item_shapes(Commun.premier_bloc(grille)).size()
	_v.v(formes_avant > 0,
		"la bibliotheque de depart n'a aucune forme : le test ne prouverait rien")

	outil.charger = true
	_v.v(outil.fenetre_chargee, "charger n'a pas marque la fenetre comme chargee")
	_v.v(not grille.get_used_cells().is_empty(), "charger n'a rien pose")

	# SCULPTER SE FAIT SANS COLLISION : c'est ce qui fait passer le chargement
	# de vingt-huit secondes a moins d'une.
	var pendant := grille.mesh_library
	_v.v(pendant != de_jeu, "la bibliotheque de jeu est restee pendant l'edition")
	_v.v(pendant.get_item_shapes(Commun.premier_bloc(grille)).is_empty(),
		"la bibliotheque d'edition porte encore des formes de collision")
	_v.v(pendant.get_item_list() == de_jeu.get_item_list(),
		"les identifiants d'items ont change : ce qui est pose designerait un autre bloc")
	_v.v(pendant.get_item_mesh(Commun.premier_bloc(grille)) != null,
		"la bibliotheque d'edition a perdu ses maillages : plus rien a voir en sculptant")
	_v.v(outil.bibliotheque_de_jeu == de_jeu,
		"la bibliotheque de jeu n'a pas ete mise de cote")

	# DEUX CHARGEMENTS DE SUITE ne doivent pas mettre de cote l'allegee.
	outil.charger = true
	_v.v(outil.bibliotheque_de_jeu == de_jeu,
		"un second chargement a pris la bibliotheque allegee pour celle du jeu")

	var sculptees_avant: int = carte.colonnes_sculptees()

	outil.vider = true
	_v.v(grille.get_used_cells().is_empty(), "vider a laisse des cellules")
	_v.v(not outil.fenetre_chargee,
		"vider n'a pas invalide la fenetre : enregistrer effacerait la carte")
	# LE TERRAIN RETROUVE SA COLLISION, sans quoi le sol du jeu serait
	# traversable et aucun test de correction ne le verrait.
	_v.v(grille.mesh_library == de_jeu,
		"vider n'a pas rendu la bibliotheque de jeu : le terrain resterait traversable")

	# LE GESTE QUI DETRUIRAIT TOUT, REFUSE.
	outil.enregistrer = true
	_v.v(carte.colonnes_sculptees() == sculptees_avant,
		"enregistrer apres un vidage a ecrit dans la carte (%d colonnes contre %d)" % [
			carte.colonnes_sculptees(), sculptees_avant])
	_v.v(carte.sommet(Vector2i(1001, -701)) == base + 4,
		"le relief sculpte a ete efface par un enregistrement apres vidage")

	racine.queue_free()

func _deplacement() -> void:
	var racine := Node3D.new()
	get_root().add_child(racine)
	var grille := GridMap.new()
	grille.mesh_library = _bibliotheque
	racine.add_child(grille)
	var outil: Node3D = OutilFenetre.new()
	racine.add_child(outil)

	var chemin := "user://test_deplacement.tres"
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 2500
	ResourceSaver.save(carte, chemin)
	carte = load(chemin)
	var base: int = carte.sommet_de_base()

	outil.carte = carte
	outil.demi_fenetre = DEMI
	outil.centre = CENTRE

	# SANS FENETRE CHARGEE, DEPLACER N'ECRIT RIEN.
	var fait: bool = await outil.deplacer_vers(Vector2i(50, 50))
	_v.v(not fait, "un deplacement a eu lieu alors qu'aucune fenetre n'etait chargee")
	_v.v(carte.colonnes_sculptees() == 0,
		"deplacer sans fenetre chargee a ecrit %d colonnes" % carte.colonnes_sculptees())
	outil.centre = CENTRE

	# On charge, on sculpte une butte, puis on DEPLACE.
	outil.charger = true
	var frames := 0
	while not outil.fenetre_chargee and frames < 300:
		await process_frame
		frames += 1
	var bloc := Commun.premier_bloc(grille)
	var butte := CENTRE + Vector2i(2, -3)
	for y in range(base + 1, base + 4):
		grille.set_cell_item(Vector3i(butte.x, y, butte.y), bloc)

	var ailleurs := Vector2i(-800, 1500)
	fait = await outil.deplacer_vers(ailleurs)
	_v.v(fait, "le deplacement n'a rien fait alors qu'une fenetre etait chargee")

	# 1. CE QUI ETAIT LA EST DANS LA CARTE, et sur le disque.
	var colonne := butte
	_v.v(carte.sommet(colonne) == base + 3,
		"la butte n'a pas ete enregistree avant le deplacement : sommet %s" % [
			carte.sommet(colonne)])
	var relue: Resource = ResourceLoader.load(chemin, "", ResourceLoader.CACHE_MODE_IGNORE)
	_v.v(relue != null and relue.sommet(colonne) == base + 3,
		"la butte n'est pas sur le disque apres le deplacement")

	# 2. LA NOUVELLE ZONE EST RENDUE, et l'ancienne DECHARGEE.
	_v.v(outil.centre == ailleurs and outil.centre_charge == ailleurs,
		"le centre charge est %v, %v attendu" % [outil.centre_charge, ailleurs])
	var sommets := OutilFenetre.sommets_du_gridmap(grille)
	_v.v(sommets.size() == DEMI * DEMI * 4,
		"%d colonnes rendues apres le deplacement, %d attendues" % [
			sommets.size(), DEMI * DEMI * 4])
	# LA BUTTE N'EST PLUS RENDUE : on a change d'endroit, et le terrain se pose
	# desormais LA OU IL EST sur la carte.
	_v.v(not sommets.has(butte),
		"la butte est encore rendue apres le deplacement : %s" % [sommets.get(butte, null)])
	_v.v(sommets.has(ailleurs),
		"la nouvelle zone n'est pas rendue autour de %v" % ailleurs)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))
	racine.queue_free()

func _conclure() -> void:
	if _v.echecs() > 0:
		print("ECHEC: le passage de fenetre ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: fenetre de sculpture -- decalage dans le bon sens, chargement qui efface et pose sans collision, aller-retour identique, creuse ecrit comme vide, bord d'emprise tenu, garde-fou opposable, vidage qui rend la bibliotheque, deplacement qui enregistre puis recharge")
	quit(0)
