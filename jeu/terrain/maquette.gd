@tool
extends Node3D

# LA VUE D'ENSEMBLE de la carte : toute l'emprise d'un coup, a resolution
# reduite, teintee par la hauteur. C'est l'outil de REPERAGE du sculpteur --
# voir ou il a travaille, ou il n'a rien fait, et a quoi ressemble le relief en
# grand. Il ne decide rien du terrain et n'ecrit jamais dans la carte.
#
# Entree : une carte, un pas d'echantillonnage, un nombre de teintes. Sortie :
# les cellules d'un GridMap qu'elle fabrique, une par echantillon, et une
# bibliotheque fabriquee elle aussi a l'execution.
#
# SES CELLULES NE SONT JAMAIS ENREGISTREES DANS LA SCENE. Elles vivent dans un
# GridMap cree a l'execution et SANS OWNER : un noeud sans owner n'est pas ecrit
# au pack. Mesure de ce que coutait l'inverse -- la maquette d'une carte de
# 100 km² ajoutait 1,04 Mo au fichier de scene, a chaque sauvegarde, pour un
# contenu entierement reconstructible depuis la carte. Meme raison que pour la
# fenetre de sculpture : la carte est la seule verite, la scene n'en garde
# jamais une copie.
#
# UNE PEAU, PAS UN VOLUME : une seule cellule par echantillon, posee a la couche
# de son sommet. Poser toutes les couches multiplierait le compte par la
# profondeur du terrain pour une maquette dont on ne voit que le dessus.
#
# LA VERTICALE GARDE SON ECHELLE. La cellule est large de `pas` colonnes mais
# haute d'UNE couche : x et z sont reduits, y ne l'est pas. Une cellule cubique
# etirerait le relief du meme facteur que la reduction -- un talus de deux
# couches se lirait comme une falaise.
#
# ELLE NE RELIT JAMAIS L'EMPRISE ENTIERE, et c'est ce qui la rend possible sur
# cent kilometres carres : le fond est POSE PLAT d'un coup, puis seules les
# colonnes SCULPTEES sont relues -- la carte ne stocke que celles-la. Le cout
# suit le travail fait, jamais la taille de la carte. Balayer l'emprise
# demanderait vingt-cinq millions de lectures pour retrouver, presque partout,
# le sommet par defaut.
#
# L'ECHANTILLON GARDE LE PLUS HAUT de ses colonnes. Une crete d'une colonne de
# large survit donc a la reduction, la ou une moyenne l'effacerait. Le revers
# est ecrit : un trou etroit borde de terrain plein disparait, la maquette
# montre les reliefs et pas les creux fins.
#
# SA CONSTRUCTION NE TIENT PAS A UN SEUL EVENEMENT. _ready ne part qu'une fois,
# a l'entree dans l'arbre, et JAMAIS quand l'editeur recharge un script @tool
# sur des noeuds deja instancies. Si quoi que ce soit manque a cet instant --
# script recharge apres coup, carte pas encore resolue -- la maquette reste vide
# DEFINITIVEMENT, sans une erreur, et rien ne retente jamais : un noeud d'allure
# normale qui ne dessine rien. Le rattrapage est donc dans _process, qui
# reconstruit des qu'il trouve la grille vide alors qu'une carte est posee.
#
# ELLE N'EXISTE QUE DANS L'EDITEUR. C'est un outil de REPERAGE du sculpteur, et
# la meme scene sert a jouer : en jeu, ses soixante-deux mille cellules
# flotteraient au-dessus de la tete du joueur, en pure perte de memoire et de
# vue. Elle s'efface donc au lancement au lieu de se construire -- et le fichier
# de scene n'en porte aucune, puisqu'elle se construit toujours a l'ouverture.
#
# LA BIBLIOTHEQUE EST FABRIQUEE ICI, jamais bloc.tres : ses cubes font deux
# metres, ceux d'une maquette au vingtieme en font quarante, et un GridMap ne
# met pas ses maillages a l'echelle de ses cellules -- les blocs se verraient
# comme des grains isoles au milieu du vide. Aucune forme de collision : rien ne
# marche sur une maquette.
#
# Regles tenues : positions en Vector3i (grille), jamais Vector2 -- un
# ECHANTILLON est un Vector2i, un index et pas une position. Aucun hasard. Aucun
# texte visible par le joueur. Rien de scripts/, data/ ni documents/ n'est lu ni
# ecrit.

# Le GridMap fabrique a l'execution. Nomme pour se retrouver, jamais pour se
# reconnaitre : c'est le seul enfant que ce noeud se donne.
const NOM_GRILLE := "Cellules"

# La carte a survoler. Sans elle, la maquette ne pose rien et le dit.
@export var carte: Resource

# Combien de colonnes par cellule de maquette, sur chaque axe. A 20, cent
# kilometres carres tiennent en 250 x 250 cellules.
@export var pas_echantillon: int = 20

# Combien de teintes etagees entre le point le plus bas et le plus haut. En
# dessous de deux, tout est de la meme couleur et le relief ne se lit plus.
@export var teintes: int = 8

@export var couleur_bas := Color(0.20, 0.35, 0.18)
@export var couleur_milieu := Color(0.52, 0.42, 0.26)
@export var couleur_haut := Color(0.92, 0.92, 0.88)

@export var reconstruire := false:
	set(demande):
		reconstruire = false
		if demande:
			construire()

func _ready() -> void:
	# Voir l'en-tete : outil d'editeur, invisible et gratuit en jeu.
	if not Engine.is_editor_hint():
		set_process(false)
		return
	if doit_construire():
		construire()

# Le rattrapage. Voir l'en-tete : _ready ne suffit pas, et une maquette vide ne
# se signale d'aucune facon.
func _process(_delta: float) -> void:
	if doit_construire():
		construire()

# Y a-t-il une carte a montrer, et rien de pose pour la montrer ? Les deux
# ensemble, jamais l'une puis l'autre : sans carte il n'y a rien a construire,
# et avec des cellules deja posees il n'y a rien a refaire.
func doit_construire() -> bool:
	if carte == null:
		return false
	return grille().get_used_cells().is_empty()

# Le GridMap ou la maquette pose ses cellules, cree au premier besoin.
#
# SANS OWNER, DELIBEREMENT : c'est ce qui l'exclut du fichier de scene. Lui en
# donner un remettrait le megaoctet mesure a chaque sauvegarde.
func grille() -> GridMap:
	var trouvee := get_node_or_null(NOM_GRILLE) as GridMap
	if trouvee != null:
		return trouvee
	trouvee = GridMap.new()
	trouvee.name = NOM_GRILLE
	add_child(trouvee)
	return trouvee

# LA COTE DU DESSUS de la maquette, dans son propre repere : la face sur
# laquelle un curseur se pose. Rend zero tant que rien n'est construit.
#
# ELLE SE DEMANDE, ELLE NE SE RECALCULE PAS AILLEURS. Entre la couche d'une
# cellule et la cote de sa face superieure il y a la taille de cellule ET le
# centrage, qui sont des reglages du noeud : les refaire de l'exterieur, c'est
# les supposer.
func hauteur_du_dessus() -> float:
	var cellules := grille()
	var occupees := cellules.get_used_cells()
	if occupees.is_empty():
		return 0.0
	var plus_haute := occupees[0].y
	for c in occupees:
		plus_haute = maxi(plus_haute, c.y)
	return cellules.map_to_local(Vector3i(0, plus_haute, 0)).y 		+ cellules.cell_size.y * 0.5

# L'echantillon qui contient une colonne. LA DIVISION EST PLANCHER, jamais la
# troncature vers zero : sur les colonnes negatives, -1 / 20 rend 0 en GDScript,
# ce qui replierait toute une bande de la carte sur l'echantillon d'a cote.
static func echantillon_de(colonne: Vector2i, pas: int) -> Vector2i:
	return Vector2i(
		floori(float(colonne.x) / float(pas)),
		floori(float(colonne.y) / float(pas)))

# Le sommet de chaque echantillon de la carte : le PLUS HAUT de ses colonnes.
#
# LE FOND D'ABORD, LES SCULPTURES ENSUITE. Le defaut se pose sans lire une seule
# colonne -- il est le meme partout ; puis les colonnes que la carte stocke
# viennent le corriger. Une colonne creusee jusqu'au vide compte comme la couche
# sous la base, ce qui la laisse perdre face a n'importe quelle voisine pleine.
static func echantillonner(source: Resource, pas: int) -> Dictionary:
	var sommets: Dictionary = {}
	var demi: int = source.demi_cote
	var base: int = source.sommet_de_base()
	var bord: int = echantillon_de(Vector2i(demi - 1, demi - 1), pas).x
	var premier: int = echantillon_de(Vector2i(-demi, -demi), pas).x
	for ex in range(premier, bord + 1):
		for ez in range(premier, bord + 1):
			sommets[Vector2i(ex, ez)] = base

	var vide: int = source.couche_base - 1
	for colonne in source.reliefs:
		var echantillon := echantillon_de(colonne, pas)
		if not sommets.has(echantillon):
			continue
		var couche: int = source.reliefs[colonne]
		var retenu: int = int(sommets[echantillon])
		# Une colonne vide ne remonte jamais un echantillon, elle ne peut que le
		# laisser tel quel.
		sommets[echantillon] = maxi(retenu, maxi(couche, vide))
	return sommets

# Les couches extremes d'un relevé d'echantillons, en [bas, haut]. Servent a
# etaler les teintes sur ce qui existe REELLEMENT : une echelle fixe rendrait
# une carte presque plate uniformement grise.
static func etendue(sommets: Dictionary) -> Array[int]:
	var bas := 0
	var haut := 0
	var premier := true
	for echantillon in sommets:
		var couche: int = int(sommets[echantillon])
		if premier:
			bas = couche
			haut = couche
			premier = false
			continue
		bas = mini(bas, couche)
		haut = maxi(haut, couche)
	return [bas, haut]

# L'item de teinte d'une couche. Une etendue nulle -- carte parfaitement plate
# -- rend toujours la teinte du bas, jamais une division par zero.
static func teinte_de(couche: int, bas: int, haut: int, combien: int) -> int:
	if combien <= 1 or haut <= bas:
		return 0
	var fraction := float(couche - bas) / float(haut - bas)
	return clampi(int(fraction * float(combien - 1) + 0.5), 0, combien - 1)

# La couleur d'une teinte : du bas au milieu, puis du milieu au haut. Deux
# segments, parce qu'une seule interpolation entre deux couleurs traverse des
# teintes intermediaires qu'on ne choisit pas.
static func couleur_de(rang: int, combien: int, bas: Color, milieu: Color,
		haut: Color) -> Color:
	if combien <= 1:
		return bas
	var fraction := float(rang) / float(combien - 1)
	if fraction <= 0.5:
		return bas.lerp(milieu, fraction * 2.0)
	return milieu.lerp(haut, (fraction - 0.5) * 2.0)

# La bibliotheque de la maquette : un cube par teinte, large de `pas` colonnes
# et haut d'UNE couche.
static func bibliotheque_de(pas: int, cote: float, combien: int, bas: Color,
		milieu: Color, haut: Color) -> MeshLibrary:
	var bibliotheque := MeshLibrary.new()
	for rang in range(maxi(combien, 1)):
		var matiere := StandardMaterial3D.new()
		matiere.albedo_color = couleur_de(rang, maxi(combien, 1), bas, milieu, haut)
		var cube := BoxMesh.new()
		cube.size = Vector3(float(pas) * cote, cote, float(pas) * cote)
		cube.material = matiere
		bibliotheque.create_item(rang)
		bibliotheque.set_item_name(rang, "teinte_%d" % rang)
		bibliotheque.set_item_mesh(rang, cube)
	return bibliotheque

# Pose un relevé d'echantillons dans une grille. Rend le nombre de cellules
# posees.
static func poser(grille: GridMap, sommets: Dictionary, bas: int, haut: int,
		combien: int) -> int:
	var posees := 0
	for echantillon in sommets:
		var couche: int = int(sommets[echantillon])
		var item := teinte_de(couche, bas, haut, combien)
		grille.set_cell_item(Vector3i(echantillon.x, couche, echantillon.y), item)
		posees += 1
	return posees

func construire() -> void:
	if carte == null:
		push_error("maquette sans carte : rien a montrer")
		return
	if pas_echantillon < 1:
		push_error("le pas d'echantillonnage vaut %d : il lui faut au moins 1" % pas_echantillon)
		return

	var cellules := grille()
	var cote: float = carte.cote
	# LA CELLULE EST LARGE ET PLATE : reduite en x et z, a l'echelle en y.
	cellules.cell_size = Vector3(
		float(pas_echantillon) * cote, cote, float(pas_echantillon) * cote)
	cellules.mesh_library = bibliotheque_de(pas_echantillon, cote, teintes,
		couleur_bas, couleur_milieu, couleur_haut)

	var sommets := echantillonner(carte, pas_echantillon)
	var bornes := etendue(sommets)
	cellules.clear()
	var posees := poser(cellules, sommets, bornes[0], bornes[1], teintes)
	print("maquette : %d cellules pour %d colonnes (1 pour %d x %d), couches %d a %d, %d colonnes sculptees relues" % [
		posees, carte.colonnes(), pas_echantillon, pas_echantillon,
		bornes[0], bornes[1], carte.colonnes_sculptees()])
