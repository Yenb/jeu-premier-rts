@tool
extends "res://jeu/monde/registre.gd"

# LA DONNEE DU TERRAIN, et rien d'autre : aucun noeud, aucun GridMap, aucun
# rendu. Elle dit ou s'arrete la carte, et jusqu'a quelle couche la matiere
# monte sous chaque colonne. Ce qui la DESSINE se branche dessus ; elle ne
# connait pas son dessinateur.
#
# Entree : rien -- ses champs sont exportes et se reglent a l'inspecteur ou par
# un outil. Sortie : le sommet d'une colonne, en couches de grille, ou null
# quand la colonne est hors emprise ou vide.
#
# UNE COLONNE EST UN Vector2i (x/z de la grille), un INDEX et pas une position
# -- meme convention que surface_terrain.gd, qui est l'autre bout du pont. Les
# positions restent des Vector3 partout ailleurs.
#
# CHAQUE CARTE PORTE SON EMPRISE. C'est ce qui separe cette donnee d'une
# constante de generateur : deux cartes de tailles differentes coexistent, et
# l'outil qui en lit une n'a plus a deviner de quelle taille elle est.
#
# ON ENREGISTRE CE QUE LA CELLULE EST, JAMAIS UN RESUME DE CE QU'ON A PREVU
# QU'ELLE SOIT. Un resume ne garde que ce qui etait prevu en l'ecrivant : un
# masque « plein / vide » perd l'item et l'orientation, donc les rampes, et
# perdra de la meme facon toute sorte de bloc ajoutee plus tard. Chaque nouvelle
# chose demanderait alors de rouvrir le releve -- et jusqu'a ce qu'on le fasse,
# elle disparaitrait sans un mot.
#
# LE DEFAUT RESTE GRATUIT : le masque dit QUELLES couches sont pleines, et seules
# les cellules qui S'ECARTENT du bloc par defaut coutent une entree. Un terrain
# plat de cent kilometres carres ne pese pas un octet de plus qu'avant ; une
# rampe en coute une, un bloc que personne n'a encore invente aussi.
#
# UNE CARTE EST UN VOLUME, PAS UN RELIEF. Chaque colonne porte QUELLES COUCHES
# sont pleines, pas seulement jusqu'ou la matiere monte. Une hauteur unique par
# colonne ne sait representer ni grotte, ni pont, ni surplomb, ni deux niveaux
# separes par du vide : elle les remplit tous du fond au sommet. Tout le terrain
# destructible de GAME_DESIGN.md en depend -- miner sous la surface, un pont qui
# tient par cohesion, l'etayage.
#
# LES COUCHES TIENNENT DANS UN MASQUE DE BITS, un entier par colonne : le bit i
# dit que la couche `couche_base + i` est pleine. Soixante-trois couches, soit
# cent vingt-six metres de haut a deux metres la cellule. Une LISTE de couches
# par colonne serait exacte aussi et couterait, sur les colonnes profondes,
# autant d'entrees que de couches -- la ou le masque en coute UNE, quelle que
# soit la complexite du volume.
#
# LE PLAT NE COUTE RIEN, ET C'EST CE QUI REND L'ECHELLE TENABLE. Une carte est
# PLEINE par defaut jusqu'a `couche_base + couches_pleines - 1` ; seules les
# colonnes qui S'ECARTENT de ce defaut sont stockees. Une carte vierge de
# vingt-cinq millions de colonnes pese donc ce que pese son en-tete, et son
# poids suit ce qui a ete sculpte, jamais son emprise. Un GridMap fait
# l'inverse : il stocke chaque cellule posee, mesure a 16,5 octets de scene et
# 86 octets de memoire par cellule, ce qui borne l'emprise sculptable bien avant
# que le jeu ne le demande.
#
# UNE COLONNE SE LIT EN TEMPS CONSTANT, sans aucun rayon a parcourir : c'est un
# acces de Dictionary, ou le defaut quand la colonne n'y est pas. Le cout d'une
# lecture ne suit ni l'emprise ni le nombre de colonnes sculptees.
#
# ELLE TOURNE DANS L'EDITEUR (@tool), et ce n'est pas un confort. Un script non
# @tool n'est pas execute par l'editeur : la ressource y devient un PLACEHOLDER,
# qui porte ses champs mais dont aucune methode ne repond. Tout outil d'editeur
# qui l'interroge -- la maquette, la fenetre de sculpture -- tombe alors sur
# « Attempt to call a method on a placeholder instance ». Il n'y a rien a
# executer ici de toute facon : aucun _init, aucun _ready, aucun _process, que
# des champs et des fonctions pures.
#
# C'EST UN REGISTRE DU MONDE (`jeu/monde/registre.gd`) : chaque geste qui la
# modifie se MARQUE, et l'archiviste l'ecrit. Ce fichier n'appelle jamais
# ResourceSaver -- une donnee qui sait s'ecrire elle-meme est une donnee qu'on
# oublie d'ecrire ailleurs.
#
# Regles tenues : aucun hasard. Aucun texte visible par le joueur. Aucun nom de
# contenu -- cette donnee ne sait pas ce qui pousse ni ce qui marche dessus.
# Rien de scripts/, data/ ni documents/ n'est lu ni ecrit.

# Moitie du cote de la carte, EN CELLULES. La carte est centree sur l'origine :
# les colonnes valides vont de -demi_cote a demi_cote - 1 sur les deux axes.
@export var demi_cote: int = 150

# Couche de la premiere cellule pleine, et nombre de couches pleines du defaut.
# Le sommet par defaut est donc `couche_base + couches_pleines - 1`.
@export var couche_base: int = 0
@export var couches_pleines: int = 7

# Arete de la cellule, en metres. Portee par la carte pour la meme raison que
# l'emprise : c'est elle qui convertit une emprise en superficie.
@export var cote: float = 2.0

# LES SEULES CELLULES QUI S'ECARTENT DU BLOC PAR DEFAUT. Clef : la cellule.
# Valeur : son item et son orientation, codes ensemble. Voir l'en-tete -- c'est
# ce registre qui fait survivre une rampe, et tout ce qui viendra apres.
@export var particularites: Dictionary[Vector3i, int] = {}

# LES SEULES COLONNES QUI S'ECARTENT DU DEFAUT. Clef : la colonne. Valeur : le
# MASQUE de ses couches pleines -- bit i pour la couche `couche_base + i`. Un
# masque nul designe une colonne entierement vide.
@export var volumes: Dictionary[Vector2i, int] = {}

# CE QUI N'A PAS BESOIN D'ETRE DIT. Une cellule posee sans rien de particulier
# est le premier bloc de la bibliotheque, droit : c'est le cas de l'immense
# majorite du terrain, et il ne coute aucune entree.
const ITEM_DEFAUT := 0
const ORIENTATION_DEFAUT := 0

# Une orientation de GridMap tient sur vingt-quatre valeurs ; trente-deux laisse
# la place sans jamais melanger les deux nombres.
const ORIENTATIONS := 32

# Combien de couches un masque peut porter. Le bit de signe reste libre : un
# masque negatif se compare mal et se lit encore plus mal.
const COUCHES_MAXIMALES := 63

# Le masque du terrain plein par defaut, celui que rend toute colonne non
# sculptee : les `couches_pleines` premieres couches, depuis la base.
func masque_de_base() -> int:
	return masque_plein(couches_pleines)

# Un masque dont les `combien` premieres couches sont pleines.
static func masque_plein(combien: int) -> int:
	var borne := clampi(combien, 0, COUCHES_MAXIMALES)
	if borne <= 0:
		return 0
	return (1 << borne) - 1

# Le sommet du terrain plein par defaut. Garde parce que tout ce qui SCULPTE
# raisonne encore en hauteur -- la ou tout ce qui LIT raisonne en volume.
func sommet_de_base() -> int:
	return couche_base + couches_pleines - 1

func colonnes() -> int:
	return demi_cote * demi_cote * 4

func metres() -> float:
	return float(demi_cote) * 2.0 * cote

func superficie_km2() -> float:
	var m := metres()
	return (m * m) / 1000000.0

func dans_emprise(colonne: Vector2i) -> bool:
	return colonne.x >= -demi_cote and colonne.x < demi_cote \
		and colonne.y >= -demi_cote and colonne.y < demi_cote

# LE MASQUE des couches pleines d'une colonne. Zero hors emprise comme pour une
# colonne entierement creusee : dans les deux cas il n'y a rien a poser, et
# aucun appelant n'a besoin de les distinguer.
func masque(colonne: Vector2i) -> int:
	if not dans_emprise(colonne):
		return 0
	return volumes.get(colonne, masque_de_base())

# Une couche donnee est-elle pleine ? Le seul geste qui interroge le VOLUME.
func est_pleine(colonne: Vector2i, couche: int) -> bool:
	var rang := couche - couche_base
	if rang < 0 or rang >= COUCHES_MAXIMALES:
		return false
	return (masque(colonne) & (1 << rang)) != 0

# La couche de la cellule pleine la plus haute, ou null.
#
# NULL A DEUX CAUSES ET AUCUN APPELANT N'A BESOIN DE LES DISTINGUER pour poser
# quoi que ce soit : hors emprise, ou colonne sans aucune couche pleine. Meme
# choix que surface_terrain.gd:couche_de -- un entier sentinelle serait pris
# pour une couche reelle.
#
# LE SOMMET N'EST PLUS LE VOLUME, et c'est tout l'objet du changement : deux
# colonnes de meme sommet peuvent etre creusees differemment. Ce qui DESSINE lit
# le masque ; ce qui POSE quelque chose DESSUS lit le sommet.
func sommet(colonne: Vector2i) -> Variant:
	var bits := masque(colonne)
	if bits == 0:
		return null
	var rang := COUCHES_MAXIMALES - 1
	while rang >= 0:
		if (bits & (1 << rang)) != 0:
			return couche_base + rang
		rang -= 1
	return null

# Ecrit le masque d'une colonne. Rend false hors emprise -- y ecrire poserait de
# la matiere qu'aucun outil ne retrouverait.
#
# UNE COLONNE REMISE AU DEFAUT SORT DU STOCKAGE. Sans ca, sculpter puis defaire
# laisserait une entree par geste, et le poids de la carte suivrait le nombre de
# gestes au lieu de ce qui est reellement sculpte.
func poser_masque(colonne: Vector2i, bits: int) -> bool:
	if not dans_emprise(colonne):
		return false
	var avant := masque(colonne)
	if bits == avant:
		return true
	# LES CELLULES QUI DISPARAISSENT EMPORTENT LEUR PARTICULARITE. Un masque qui
	# eteint une couche sans nettoyer ce registre y laisserait une entree pour
	# une cellule qui n'existe plus -- invisible, et ressuscitee au premier
	# rallumage de la couche.
	var eteintes := avant & ~bits
	if eteintes != 0 and not particularites.is_empty():
		for rang in range(COUCHES_MAXIMALES):
			if (eteintes & (1 << rang)) != 0:
				particularites.erase(Vector3i(colonne.x, couche_base + rang, colonne.y))

	if bits == masque_de_base():
		volumes.erase(colonne)
	else:
		volumes[colonne] = bits
	# VOIR L'EN-TETE : c'est ici, et nulle part ailleurs, que la carte dit
	# qu'elle a change. L'archiviste fait le reste.
	marquer_sale()
	return true

# Ecrit une colonne PLEINE de la base jusqu'a `couche`. Le geste du sculpteur
# qui raisonne en hauteur : il reste juste tant qu'on ne creuse pas dessous.
# Une couche sous la base vide la colonne.
func sculpter(colonne: Vector2i, couche: int) -> bool:
	return poser_masque(colonne, masque_plein(couche - couche_base + 1))

# Le nombre de colonnes qui s'ecartent du defaut : ce que la carte pese
# reellement, par opposition a ce qu'elle couvre.
func colonnes_sculptees() -> int:
	return volumes.size()

# LA COTE DU SOL d'une colonne, en metres : la face sur laquelle une chose
# repose. Rend null quand la colonne est vide ou hors emprise -- rien ne s'y
# pose, et un zero serait pris pour une altitude reelle.
#
# C'EST LA SEULE SOURCE DE LA HAUTEUR DU SOL, pour ce qui est rendu comme pour
# ce qui ne l'est pas. Un objet loin du joueur n'a aucun corps physique sous
# lui : sa hauteur se LIT ici. Pres du joueur, le terrain rendu pose ses
# cellules depuis la meme carte, aux memes couches. Deux sources donneraient un
# objet enfonce ou flottant au moment ou il bascule de l'une a l'autre.
func hauteur_du_sol(colonne: Vector2i) -> Variant:
	var haut: Variant = sommet(colonne)
	if haut == null:
		return null
	return float(int(haut) + 1) * cote

# Les cellules pleines d'une colonne, EXACTEMENT celles que son masque declare.
# Liste vide pour une colonne vide ou hors emprise.
#
# ELLE SAUTE LES TROUS, et c'est la difference avec un relief : deux niveaux
# separes par du vide restent deux niveaux, une grotte reste une grotte.
func cellules_de(colonne: Vector2i) -> Array[Vector3i]:
	var cellules: Array[Vector3i] = []
	var bits := masque(colonne)
	if bits == 0:
		return cellules
	for rang in range(COUCHES_MAXIMALES):
		if (bits & (1 << rang)) != 0:
			cellules.append(Vector3i(colonne.x, couche_base + rang, colonne.y))
	return cellules

# CE QU'UNE CELLULE PORTE, code en un entier. Les deux sens, ecrits une fois :
# un codage applique a l'envers est l'erreur que ce fichier peut faire sans que
# rien ne le montre a l'ecran.
static func code_de(item: int, orientation: int) -> int:
	return item * ORIENTATIONS + clampi(orientation, 0, ORIENTATIONS - 1)

static func item_du_code(code: int) -> int:
	@warning_ignore("integer_division")
	return code / ORIENTATIONS

static func orientation_du_code(code: int) -> int:
	return code % ORIENTATIONS

# L'item d'une cellule. Le bloc par defaut quand rien n'est dit -- c'est le cas
# de presque tout le terrain.
func item_de(cellule: Vector3i) -> int:
	if not particularites.has(cellule):
		return ITEM_DEFAUT
	return item_du_code(int(particularites[cellule]))

func orientation_de(cellule: Vector3i) -> int:
	if not particularites.has(cellule):
		return ORIENTATION_DEFAUT
	return orientation_du_code(int(particularites[cellule]))

# POSE UNE CELLULE TELLE QU'ELLE EST : sa couche devient pleine, et son item
# comme son orientation sont gardes s'ils s'ecartent du defaut.
#
# UNE CELLULE ORDINAIRE NE COUTE RIEN : reposer le bloc par defaut droit efface
# la particularite au lieu d'en stocker une. Sans ca, peindre du terrain plat
# ferait grossir la carte d'une entree par cellule.
func poser_cellule(cellule: Vector3i, item: int, orientation: int) -> bool:
	var colonne := Vector2i(cellule.x, cellule.z)
	if not dans_emprise(colonne):
		return false
	var rang := cellule.y - couche_base
	if rang < 0 or rang >= COUCHES_MAXIMALES:
		return false

	var avant := masque(colonne)
	poser_masque(colonne, avant | (1 << rang))

	var code := code_de(item, orientation)
	if code == code_de(ITEM_DEFAUT, ORIENTATION_DEFAUT):
		if particularites.has(cellule):
			particularites.erase(cellule)
			marquer_sale()
	elif int(particularites.get(cellule, -1)) != code:
		particularites[cellule] = code
		marquer_sale()
	return true

# Retire une cellule : sa couche se vide, et ce qu'elle portait de particulier
# part avec elle -- sans quoi le registre garderait des entrees pour des
# cellules qui n'existent plus.
func retirer_cellule(cellule: Vector3i) -> bool:
	var colonne := Vector2i(cellule.x, cellule.z)
	if not dans_emprise(colonne):
		return false
	var rang := cellule.y - couche_base
	if rang < 0 or rang >= COUCHES_MAXIMALES:
		return false
	poser_masque(colonne, masque(colonne) & ~(1 << rang))
	if particularites.has(cellule):
		particularites.erase(cellule)
		marquer_sale()
	return true

# CE QUE LE REGISTRE PESE REELLEMENT : les cellules qui s'ecartent du bloc par
# defaut. Le terrain ordinaire n'y figure pas.
func cellules_particulieres() -> int:
	return particularites.size()

# Le masque que decrivent des couches donnees. Sert a ceux qui relevent un
# GridMap : ils voient des cellules, la carte veut un masque.
static func masque_depuis(couches: Array, base: int) -> int:
	var bits := 0
	for couche in couches:
		var rang: int = int(couche) - base
		if rang >= 0 and rang < COUCHES_MAXIMALES:
			bits |= 1 << rang
	return bits
