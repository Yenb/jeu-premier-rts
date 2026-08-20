extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_maquette.gd
#
# Verrouille res://jeu/terrain/maquette.gd, la vue d'ensemble de la carte :
# - l'echantillon d'une colonne NEGATIVE tombe du bon cote. La division entiere
#   de GDScript tronque vers zero : -1 / 20 rend 0, ce qui replierait une bande
#   entiere de la carte sur l'echantillon voisin, et rien a l'ecran ne le
#   montrerait ;
# - l'echantillon garde la colonne la PLUS HAUTE : une crete d'une colonne de
#   large survit a la reduction ;
# - une colonne creusee jusqu'au vide ne remonte jamais un echantillon ;
# - LE COUT NE SUIT PAS L'EMPRISE : echantillonner une carte VIERGE de 100 km²
#   tient sous un plafond que balayer ses vingt-cinq millions de colonnes
#   creverait de deux ordres. C'est le jugement qui attrape le jour ou quelqu'un
#   remplacerait la lecture des sculptures par un parcours de l'emprise ;
# - CHAQUE COLONNE SCULPTEE COUTE UNE LECTURE, PAS PLUS : le surcout par colonne
#   travaillee reste borne. Comparer simplement « vierge » et « travaillee »
#   serait le mauvais test -- lire plus de sculptures DOIT couter plus cher, et
#   un rapport plafonne punirait le travail au lieu du balayage ;
# - le compte de cellules vaut le nombre d'echantillons de l'emprise, pas le
#   nombre de colonnes ;
# - les teintes s'etalent sur l'etendue REELLE, et une carte plate ne divise
#   jamais par zero ;
# - SA CONSTRUCTION NE TIENT PAS A _ready. Cet evenement ne part qu'une fois, et
#   jamais quand l'editeur recharge un script @tool sur un noeud deja
#   instancie : une maquette qui l'aurait manque resterait vide pour toujours,
#   sans une erreur. doit_construire() est la question que le rattrapage pose a
#   chaque image, et c'est elle qui est verrouillee ici ;
# - ELLE SAIT A QUELLE HAUTEUR EST SA SURFACE. Un curseur pose a zero passe
#   quatorze metres SOUS elle et disparait derriere -- mesure sur la scene ;
# - EN JEU, LA MAQUETTE NE POSE RIEN. C'est un outil d'editeur, et la meme scene
#   sert a jouer : soixante-deux mille cellules colorees flotteraient au-dessus
#   du joueur, en pure perte. Un lancement reel l'a montre ;
# - construire() la peuple quand meme, ce qui prouve que le silence en jeu vient
#   du contexte et non d'une maquette cassee ;
# - sa camera PORTE ASSEZ LOIN pour voir la carte entiere. Le plan de coupe
#   d'une Camera3D vaut 4000 m par defaut, moins que la moitie d'une carte de
#   dix kilometres : la maquette serait construite, et l'ecran vide.
#
# Entree : des cartes construites ici, et un GridMap jamais enregistre dans une
# scene. Sortie : une ligne « OK: » et le code 0 si tout tient, « ECHEC: » et le
# code 1 sinon.
#
# Regles tenues : positions en Vector3i (grille), jamais Vector2 -- un
# echantillon est un Vector2i. Aucun hasard non seede. Les prints sont des
# traces de mise au point, pas du texte joueur. Rien de scripts/, data/ ni
# documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const Maquette = preload("res://jeu/terrain/maquette.gd")

const EMPRISE := 2500
const PAS := 20
const TEINTES := 8

# Combien de colonnes sculptees pour la mesure de cout, et la graine du tirage.
const GRAINE := 20260820
const COLONNES_SCULPTEES := 50000

# Ce qu'echantillonner une carte VIERGE de 100 km² a le droit de couter. Large :
# ce qu'on refuse est un parcours de l'emprise, qui a vingt-cinq millions de
# lectures se compte en secondes, jamais quelques millisecondes de bruit.
const PLAFOND_VIERGE_MS := 200.0

# Ce que chaque colonne sculptee a le droit d'ajouter. Une lecture de Dictionary
# se mesure sous la microseconde ; au-dela, une colonne coute plus qu'un acces.
const PLAFOND_PAR_COLONNE_US := 5.0

var _v

# LES JUGEMENTS SONT DIFFERES, jamais joues dans _init : la racine du SceneTree
# n'est pas encore prete a cet instant, un noeud qu'on y ajoute n'entre pas dans
# l'arbre, et son _ready ne part donc jamais. Une scene se verifierait alors
# vide alors qu'elle se peuple parfaitement au lancement.
func _init() -> void:
	_v = Verif.new()
	_tout.call_deferred()

func _tout() -> void:
	var temoin: Node = Maquette.new()
	# UN SCRIPT QUI NE COMPILE PAS ROUGIT, IL NE SE SAUTE PAS.
	if temoin == null:
		_v.v(false, "maquette.gd ne s'instancie pas : le script ne compile pas")
		_conclure()
		return
	temoin.free()
	_echantillonnage()
	_teintes()
	_pose()
	_declenchement()
	_sans_relief()
	_cout()
	_scene()
	_conclure()

func _echantillonnage() -> void:
	# LE CAS QUI CASSE : les colonnes negatives.
	_v.v(Maquette.echantillon_de(Vector2i(-1, -1), PAS) == Vector2i(-1, -1),
		"la colonne (-1,-1) tombe dans l'echantillon %v au lieu de (-1,-1)" % [
			Maquette.echantillon_de(Vector2i(-1, -1), PAS)])
	_v.v(Maquette.echantillon_de(Vector2i(-PAS, 0), PAS) == Vector2i(-1, 0),
		"la derniere colonne de l'echantillon -1 n'y tombe pas")
	_v.v(Maquette.echantillon_de(Vector2i(0, 0), PAS) == Vector2i.ZERO,
		"la colonne d'origine ne tombe pas dans l'echantillon d'origine")
	_v.v(Maquette.echantillon_de(Vector2i(PAS, PAS), PAS) == Vector2i(1, 1),
		"la premiere colonne de l'echantillon 1 n'y tombe pas")

	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = EMPRISE
	var base: int = carte.sommet_de_base()

	# Une crete d'UNE colonne de large, et un trou d'une colonne, dans le meme
	# echantillon.
	var crete := Vector2i(-1000, 500)
	var trou := Vector2i(-999, 500)
	carte.sculpter(crete, base + 9)
	carte.sculpter(trou, carte.couche_base - 1)
	var echantillon := Maquette.echantillon_de(crete, PAS)
	_v.v(Maquette.echantillon_de(trou, PAS) == echantillon,
		"la crete et le trou ne sont pas dans le meme echantillon : le test ne prouve rien")

	var sommets := Maquette.echantillonner(carte, PAS)
	_v.v(int(sommets.get(echantillon, -99)) == base + 9,
		"l'echantillon retient %s, la crete est a %d" % [
			sommets.get(echantillon, null), base + 9])

	# Un echantillon intact rend le defaut, sans qu'aucune colonne n'ait ete lue.
	_v.v(int(sommets.get(Vector2i(10, 10), -99)) == base,
		"un echantillon non sculpte ne rend pas le sommet par defaut")

	# Une colonne creusee SEULE ne remonte pas son echantillon.
	var creusee := Vector2i(1200, -1200)
	carte.sculpter(creusee, carte.couche_base - 1)
	sommets = Maquette.echantillonner(carte, PAS)
	_v.v(int(sommets.get(Maquette.echantillon_de(creusee, PAS), -99)) == base,
		"une colonne creusee a fait remonter son echantillon")

func _teintes() -> void:
	_v.v(Maquette.teinte_de(0, 0, 10, TEINTES) == 0, "le plus bas ne prend pas la teinte du bas")
	_v.v(Maquette.teinte_de(10, 0, 10, TEINTES) == TEINTES - 1,
		"le plus haut ne prend pas la teinte du haut")
	_v.v(Maquette.teinte_de(5, 0, 10, TEINTES) > 0
			and Maquette.teinte_de(5, 0, 10, TEINTES) < TEINTES - 1,
		"le milieu ne prend pas une teinte intermediaire")
	# CARTE PLATE : aucune division par zero, une seule teinte.
	_v.v(Maquette.teinte_de(6, 6, 6, TEINTES) == 0,
		"une carte plate ne rend pas une teinte unique")

	# UN DENIVELE MINUSCULE NE PREND PLUS TOUTE LA GAMME. Sans plancher, un
	# ecart de 3 (bas=6, haut=9) ferait deja tomber le haut en pleine teinte
	# blanche -- exactement le cas d'un monticule de sculpteur sur une carte
	# presque plate.
	var elargie := Maquette.etendue_elargie([6, 9], 20)
	_v.v(elargie[0] == 6, "le plancher deplace le bas : %d au lieu de 6" % elargie[0])
	_v.v(elargie[1] == 26, "le plancher ne va pas assez haut : %d au lieu de 26" % elargie[1])
	_v.v(Maquette.teinte_de(9, elargie[0], elargie[1], TEINTES) < TEINTES - 1,
		"un denivele de 3 couches atteint quand meme la teinte du haut avec le plancher")
	# LE PLANCHER NE RETRECIT JAMAIS UN VRAI RELIEF.
	var large := Maquette.etendue_elargie([0, 40], 20)
	_v.v(large[0] == 0 and large[1] == 40,
		"le plancher retrecit une etendue deja plus large que lui : %s" % [large])

	var bas := Color(0.2, 0.35, 0.18)
	var milieu := Color(0.52, 0.42, 0.26)
	var haut := Color(0.92, 0.92, 0.88)
	_v.v(Maquette.couleur_de(0, TEINTES, bas, milieu, haut).is_equal_approx(bas),
		"la premiere teinte n'est pas la couleur du bas")
	_v.v(Maquette.couleur_de(TEINTES - 1, TEINTES, bas, milieu, haut).is_equal_approx(haut),
		"la derniere teinte n'est pas la couleur du haut")

	var bibliotheque := Maquette.bibliotheque_de(PAS, 2.0, TEINTES, bas, milieu, haut)
	_v.v(bibliotheque.get_item_list().size() == TEINTES,
		"la bibliotheque porte %d items, %d teintes demandees" % [
			bibliotheque.get_item_list().size(), TEINTES])
	var cube := bibliotheque.get_item_mesh(0) as BoxMesh
	_v.v(cube != null and cube.size.is_equal_approx(Vector3(float(PAS) * 2.0, 2.0, float(PAS) * 2.0)),
		"le cube de maquette ne fait pas %d colonnes de large et une couche de haut" % PAS)
	# RIEN NE MARCHE SUR UNE MAQUETTE.
	_v.v(bibliotheque.get_item_shapes(0).is_empty(),
		"un item de maquette porte une forme de collision")

func _pose() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = EMPRISE
	var base: int = carte.sommet_de_base()
	carte.sculpter(Vector2i(0, 0), base + 6)

	var grille := GridMap.new()
	grille.cell_size = Vector3(float(PAS) * carte.cote, carte.cote, float(PAS) * carte.cote)
	get_root().add_child(grille)

	var sommets := Maquette.echantillonner(carte, PAS)
	var bornes: Array[int] = Maquette.etendue(sommets)
	_v.v(bornes[0] == base, "le point le plus bas releve est %d, %d attendu" % [bornes[0], base])
	_v.v(bornes[1] == base + 6, "le point le plus haut releve est %d, %d attendu" % [
		bornes[1], base + 6])

	var posees := Maquette.poser(grille, sommets, bornes[0], bornes[1], TEINTES)
	var cote_echantillons := (EMPRISE * 2) / PAS
	_v.v(posees == cote_echantillons * cote_echantillons,
		"%d cellules posees, %d attendues (%d x %d echantillons)" % [
			posees, cote_echantillons * cote_echantillons, cote_echantillons,
			cote_echantillons])
	_v.v(grille.get_used_cells().size() == posees,
		"le GridMap porte %d cellules pour %d posees" % [
			grille.get_used_cells().size(), posees])
	# UNE PEAU, PAS UN VOLUME : une seule cellule par echantillon.
	_v.v(posees < carte.colonnes(),
		"la maquette pose autant de cellules que la carte a de colonnes")

	# La cellule sculptee est posee a SA couche, et prend la teinte du haut.
	var sommet_pose := Vector3i(0, base + 6, 0)
	_v.v(grille.get_cell_item(sommet_pose) == TEINTES - 1,
		"la cellule la plus haute ne porte pas la teinte du haut")

	print("maquette : %d cellules pour %d colonnes (1 pour %d x %d)" % [
		posees, carte.colonnes(), PAS, PAS])
	grille.queue_free()

func _declenchement() -> void:
	var maquette: Node3D = Maquette.new()
	get_root().add_child(maquette)

	# SANS CARTE, RIEN A CONSTRUIRE -- et surtout pas en boucle a chaque image.
	_v.v(not maquette.doit_construire(),
		"une maquette sans carte se croit a construire : elle recommencerait a chaque image")

	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 100
	maquette.carte = carte
	maquette.pas_echantillon = PAS
	# UNE CARTE POSEE ET RIEN D'AFFICHE : c'est exactement le cas qu'un _ready
	# manque laisse derriere lui, et que le rattrapage doit voir.
	_v.v(maquette.doit_construire(),
		"une maquette qui porte une carte et n'a rien pose ne se sait pas a construire")

	maquette.construire()
	_v.v(not maquette.doit_construire(),
		"la maquette se reconstruirait a chaque image apres avoir construit")
	_v.v(maquette.grille().get_used_cells().size() > 0, "construire() n'a rien pose")

	# LA HAUTEUR DE SA SURFACE, celle sur laquelle un curseur se pose.
	var dessus: float = maquette.hauteur_du_dessus()
	var attendue: float = float(carte.sommet_de_base() + 1) * carte.cote
	_v.v(absf(dessus - attendue) < 0.01,
		"la maquette annonce son dessus a %.2f m, %.2f attendus" % [dessus, attendue])
	_v.v(dessus > 0.0,
		"la maquette annonce un dessus a zero : un curseur pose la passerait dessous")

	maquette.queue_free()

# SANS RELIEF (le defaut) : un sommet sculpte ne se voit plus, ni dans la
# hauteur posee ni dans la teinte -- personne ne marche sur la maquette.
func _sans_relief() -> void:
	var carte: Resource = CarteTerrain.new()
	carte.demi_cote = 100
	var base: int = carte.sommet_de_base()
	carte.sculpter(Vector2i(0, 0), base + 6)

	var maquette: Node3D = Maquette.new()
	get_root().add_child(maquette)
	maquette.carte = carte
	maquette.pas_echantillon = PAS
	_v.v(not maquette.relief, "relief est active par defaut : une maquette neuve montrerait la sculpture")

	maquette.construire()
	var echantillon := Maquette.echantillon_de(Vector2i(0, 0), PAS)
	var pose := Vector3i(echantillon.x, base, echantillon.y)
	_v.v(maquette.grille().get_cell_item(pose) == 0,
		"sans relief, l'echantillon sculpte ne prend pas la teinte du bas")
	_v.v(maquette.grille().get_cell_item(Vector3i(echantillon.x, base + 6, echantillon.y))
			== GridMap.INVALID_CELL_ITEM,
		"sans relief, une cellule existe quand meme a la hauteur sculptee")

	maquette.relief = true
	maquette.construire()
	_v.v(maquette.grille().get_cell_item(Vector3i(echantillon.x, base + 6, echantillon.y)) != GridMap.INVALID_CELL_ITEM,
		"avec relief active, la sculpture a disparu : le drapeau ne fait plus rien")

	maquette.queue_free()

func _cout() -> void:
	var vierge: Resource = CarteTerrain.new()
	vierge.demi_cote = EMPRISE

	var travaillee: Resource = CarteTerrain.new()
	travaillee.demi_cote = EMPRISE
	var base: int = travaillee.sommet_de_base()
	var tirage := RandomNumberGenerator.new()
	tirage.seed = GRAINE
	for i in range(COLONNES_SCULPTEES):
		travaillee.sculpter(Vector2i(
			tirage.randi_range(-EMPRISE, EMPRISE - 1),
			tirage.randi_range(-EMPRISE, EMPRISE - 1)), base + tirage.randi_range(1, 6))

	var debut := Time.get_ticks_usec()
	var sommets_vierge := Maquette.echantillonner(vierge, PAS)
	var temps_vierge := (Time.get_ticks_usec() - debut) / 1000.0

	debut = Time.get_ticks_usec()
	var sommets_travaillee := Maquette.echantillonner(travaillee, PAS)
	var temps_travaillee := (Time.get_ticks_usec() - debut) / 1000.0

	_v.v(sommets_vierge.size() == sommets_travaillee.size(),
		"les deux cartes ne rendent pas le meme nombre d'echantillons")

	var par_colonne := (temps_travaillee - temps_vierge) * 1000.0 / float(COLONNES_SCULPTEES)
	print("cout : %d echantillons en %.0f ms sur carte vierge de %d colonnes, %.0f ms avec %d sculptees (%.2f us par colonne sculptee)" % [
		sommets_vierge.size(), temps_vierge, vierge.colonnes(), temps_travaillee,
		COLONNES_SCULPTEES, par_colonne])

	# LE JUGEMENT QUI ATTRAPE UN BALAYAGE D'EMPRISE.
	_v.v(temps_vierge <= PLAFOND_VIERGE_MS,
		"echantillonner une carte vierge de %d colonnes coute %.0f ms, plafond %.0f : l'emprise est parcourue" % [
			vierge.colonnes(), temps_vierge, PLAFOND_VIERGE_MS])
	_v.v(par_colonne <= PLAFOND_PAR_COLONNE_US,
		"chaque colonne sculptee coute %.2f us, plafond %.2f" % [
			par_colonne, PLAFOND_PAR_COLONNE_US])

func _scene() -> void:
	var chemin := "res://jeu/terrain/maquette.tscn"
	var paquet := load(chemin) as PackedScene
	if paquet == null:
		_v.v(false, "%s introuvable ou illisible" % chemin)
		return
	var racine := paquet.instantiate() as Node3D
	if racine == null:
		_v.v(false, "la racine de %s n'est pas un Node3D" % chemin)
		return
	get_root().add_child(racine)

	var terrain := racine.get_node_or_null("Terrain") as Node3D
	if terrain == null:
		_v.v(false, "aucun noeud nomme Terrain sous la racine")
		racine.queue_free()
		return
	if terrain.carte == null:
		_v.v(false, "la maquette de la scene ne porte aucune carte")
		racine.queue_free()
		return

	# LA CARTE TOURNE-T-ELLE DANS L'EDITEUR ? Un script non @tool n'y est pas
	# execute : la ressource devient un PLACEHOLDER, qui porte ses champs mais
	# dont aucune methode ne repond, et la maquette tombe sur « Attempt to call a
	# method on a placeholder instance ». RIEN EN HEADLESS NE PEUT LE VOIR -- il
	# n'y a pas d'editeur, donc pas de placeholder. D'ou ce jugement, qui lit le
	# mode du script au lieu d'attendre l'erreur.
	var script_carte: Script = terrain.carte.get_script()
	_v.v(script_carte != null and script_carte.is_tool(),
		"le script de la carte n'est pas @tool : dans l'editeur la maquette ne pourra appeler aucune de ses methodes")

	# HORS EDITEUR, RIEN. Voir l'en-tete : le lancement du jeu ne doit pas payer
	# une vue d'ensemble que personne ne regarde.
	_v.v(terrain.grille().get_used_cells().is_empty(),
		"la maquette a pose %d cellules en jeu, alors qu'elle est un outil d'editeur" % [
			terrain.grille().get_used_cells().size()])

	# ... mais elle sait le faire quand on le lui demande.
	terrain.construire()
	var posees: int = terrain.grille().get_used_cells().size()

	# SES CELLULES NE PARTENT PAS DANS LE FICHIER DE SCENE : le GridMap qui les
	# porte n'a pas d'owner, donc le pack ne le voit pas. Sans ca, un megaoctet
	# s'ajoutait a la scene a chaque sauvegarde.
	_v.v(terrain.grille().owner == null,
		"le GridMap de la maquette a un owner : ses cellules seront enregistrees dans la scene")
	_v.v(posees > 0, "construire() n'a pose aucune cellule")
	var cote_echantillons: int = (terrain.carte.demi_cote * 2) / terrain.pas_echantillon
	_v.v(posees == cote_echantillons * cote_echantillons,
		"construire() pose %d cellules, %d attendues" % [
			posees, cote_echantillons * cote_echantillons])

	var vue := racine.get_node_or_null("Vue") as Camera3D
	if vue == null:
		_v.v(false, "aucune Camera3D nommee Vue sous la racine")
	else:
		# LE PLAN DE COUPE, mesure contre l'emprise REELLE de la carte, jamais
		# contre un nombre recopie ici.
		var portee_utile: float = terrain.carte.metres() + vue.global_position.y
		_v.v(vue.far >= portee_utile,
			"la camera porte a %.0f m, il en faut %.0f pour voir une carte de %.0f m depuis %.0f m de haut" % [
				vue.far, portee_utile, terrain.carte.metres(), vue.global_position.y])
		_v.v(vue.current, "la camera de la maquette n'est pas active")

	print("scene : vide en jeu, %d cellules apres construire(), camera a %.0f m portant a %.0f m" % [
		posees, (vue.global_position.y if vue != null else 0.0),
		(vue.far if vue != null else 0.0)])
	racine.queue_free()

func _conclure() -> void:
	if _v.echecs() > 0:
		print("ECHEC: la maquette ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: maquette -- construction qui ne tient pas a _ready, hauteur de surface connue, echantillon plancher sur les negatifs, crete conservee, creux ignore, peau et non volume, teintes etalees sur l'etendue reelle, cout qui suit le travail et non l'emprise, scene peuplee et camera qui porte")
	quit(0)
