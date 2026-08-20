@tool
extends Node3D

# OUTIL D'EDITEUR, jamais du jeu. Accroche a un noeud pose a cote du GridMap,
# il lit UNE couche du terrain, y reconnait les zones que le sculpteur a
# entourees, et les comble -- ou les retire. Rien a tracer, rien a saisir :
# ce qui est deja sur la couche suffit a designer le travail. Il ne tourne
# QUE dans l'editeur : aucun _ready, aucun _process, rien ne se declenche tout
# seul. Lance en jeu, ce noeud ne fait rien.
#
# Entree : la couche et le mode, regles dans l'inspecteur.
# Sortie : les cellules encloses du GridMap frere, posees ou retirees, plus un
# compte rendu en console. Ne touche a aucun fichier -- c'est Ctrl+S dans
# l'editeur qui ecrit la scene, jamais cet outil.
#
# CE QU'EST « L'INTERIEUR », ET POURQUOI LE BORD N'EST JAMAIS UN MUR. Une
# cellule est INTERIEURE quand elle n'est pas atteignable depuis le bord de la
# carte en se deplacant de proche en proche a travers des cellules de meme
# nature. Le bord ne compte donc pour rien : un contour qui s'appuie sur lui
# n'enferme rien, sa poche communique avec l'exterieur par le bord lui-meme.
# C'est la definition la plus simple qui ne demande RIEN au sculpteur -- ni de
# designer un point de depart, ni de tracer un polygone.
#
# UN SEUL ALGORITHME POUR LES DEUX MODES, ce qui change est la NATURE
# cherchee :
# - REMPLIR cherche les poches de VIDE encloses par du plein, et les comble.
# - CREUSER cherche les masses de PLEIN qui n'atteignent pas le bord -- des
#   ilots -- et les retire ENTIEREMENT, contour compris. C'est la symetrie
#   exacte du remplissage, et la seule lecture qui ait un sens : une zone
#   « interieure » au sens du remplissage est vide par construction, il n'y
#   aurait rien a y retirer.
#
# VOISINAGE A QUATRE, jamais a huit, et c'est ce qui rend l'outil utilisable :
# une diagonale de cubes ne laisse alors passer aucune fuite, donc un trait
# trace en biais FERME son contour. Le voisinage a huit ferait fuir toute
# figure qui n'est pas tracee en escalier strict.
#
# CE QU'IL NE SAIT PAS DIRE : « ce contour-la est ouvert ». Il ne reconnait
# aucun contour comme objet -- il ne voit que des cellules et leur connexite.
# Zero zone close sur une couche qui porte des cubes est le SEUL signe qu'il
# peut rendre, et il le rend explicitement plutot que de se taire.
#
# LA LISTE DES CELLULES EST MATERIALISEE, contrairement a la boite d'
# outil_sculpture.gd, et sans danger : elle est bornee par une couche, jamais
# par une hauteur libre -- au pire l'emprise entiere, soit quelques dizaines de
# milliers d'entrees. L'ecriture reste decoupee par frame pour la meme raison
# que la : un editeur ne rend rien tant qu'un appel ne lui a pas rendu la main.
#
# RIEN N'EST ANNULABLE : Ctrl+Z defait la case cochee, jamais les cellules
# ecrites. La parade est le mode inverse.
#
# Regles tenues : positions en Vector3i (grille), jamais des Vector2. Aucun
# hasard -- le parcours est deterministe, l'ordre des cellules ne depend que
# des indices. Les traces sont des sorties de mise au point pour l'editeur,
# jamais du texte joueur.

const Generateur = preload("res://jeu/terrain/generer_carte.gd")
const Commun = preload("res://jeu/terrain/terrain_commun.gd")

const CELLULES_PAR_FRAME := 2048

enum Mode { REMPLIR, CREUSER }

@export var couche := 7
@export var mode: Mode = Mode.REMPLIR

# La case se decoche AVANT d'agir : elle est un declencheur, pas un etat. Ainsi
# rien ne reste coche dans la scene enregistree, et une action qui echoue ne
# laisse pas une case allumee qui ferait croire le contraire.
@export var appliquer := false:
	set(demande):
		appliquer = false
		if demande:
			_appliquer()

var _en_cours := false

# LA FENETRE DE TRAVAIL, deduite de ce que la grille PORTE sur cette couche :
# le carre englobant des cellules posees, plus une cellule de marge. Rend
# { bas, cote }, ou un cote nul quand la couche est vide.
#
# ELLE NE SUIT PAS L'EMPRISE DECLAREE, et c'est tout l'objet de ce geste. Sur
# une carte de cent kilometres carres, balayer l'emprise fait vingt-cinq
# millions de cases et autant d'octets, pour un contour qui en occupe quelques
# centaines. Le cout suit ce qui est pose, jamais la taille du monde.
#
# LA MARGE D'UNE CELLULE EST STRUCTURELLE : le bord de la fenetre est la PORTE
# DE SORTIE de l'algorithme. Sans elle, un contour appuye contre la derniere
# cellule posee n'aurait aucun exterieur, et tout ce qu'il enferme passerait
# pour ouvert -- ou l'inverse.
static func fenetre_utile(grille: GridMap, couche_lue: int) -> Dictionary:
	var bas := Vector2i(0, 0)
	var haut := Vector2i(0, 0)
	var premier := true
	for cellule in grille.get_used_cells():
		if cellule.y != couche_lue:
			continue
		var colonne := Vector2i(cellule.x, cellule.z)
		if premier:
			bas = colonne
			haut = colonne
			premier = false
			continue
		bas.x = mini(bas.x, colonne.x)
		bas.y = mini(bas.y, colonne.y)
		haut.x = maxi(haut.x, colonne.x)
		haut.y = maxi(haut.y, colonne.y)
	if premier:
		return { "bas": Vector2i.ZERO, "cote": 0 }
	# Un CARRE : l'algorithme indexe en cote x cote, et une fenetre rectangulaire
	# demanderait deux largeurs partout. Le carre coute quelques cases de plus,
	# jamais un ordre de grandeur.
	var large := maxi(haut.x - bas.x, haut.y - bas.y) + 3
	return { "bas": bas - Vector2i.ONE, "cote": large }

# Etat de la couche, une case par cellule de la fenetre : 1 pleine, 0 vide.
# Indice = (x - bas.x) * cote + (z - bas.y).
static func occupation(grille: GridMap, couche_lue: int, bas: Vector2i,
		cote: int) -> PackedByteArray:
	var carte := PackedByteArray()
	if cote <= 0:
		return carte
	carte.resize(cote * cote)
	for x in range(bas.x, bas.x + cote):
		for z in range(bas.y, bas.y + cote):
			if grille.get_cell_item(Vector3i(x, couche_lue, z)) != GridMap.INVALID_CELL_ITEM:
				carte[(x - bas.x) * cote + (z - bas.y)] = 1
	return carte

# Rend { cellules, zones } : les cellules encloses de la couche, et le nombre
# de zones distinctes qu'elles forment. `cherche_vide` dit la NATURE cherchee --
# vrai pour les poches de vide (remplir), faux pour les ilots pleins (creuser).
static func zones_encloses(carte: PackedByteArray, bas: Vector2i, cote: int,
		couche_lue: int, cherche_vide: bool) -> Dictionary:
	var total := cote * cote
	var vide := { "cellules": [] as Array[Vector3i], "zones": 0 }
	if carte.size() != total:
		push_error("occupation de %d cases pour une couche qui en compte %d" % [
			carte.size(), total])
		return vide

	# 0 pas encore vue, 1 atteinte depuis le bord (exterieure), 2 close.
	var etat := PackedByteArray()
	etat.resize(total)

	# Premiere vague : tout ce qui touche le bord de la FENETRE. Le bord n'est
	# jamais un mur, il est la porte de sortie -- voir fenetre_utile, qui garde
	# une cellule de marge pour qu'il en existe toujours un.
	var pile: Array[int] = []
	for a in range(cote):
		for index in [a * cote, a * cote + cote - 1, a, (cote - 1) * cote + a]:
			if etat[index] == 0 and _est_de_la_nature(carte, index, cherche_vide):
				etat[index] = 1
				pile.append(index)
	while not pile.is_empty():
		for voisin in _voisins(pile.pop_back(), cote):
			if etat[voisin] == 0 and _est_de_la_nature(carte, voisin, cherche_vide):
				etat[voisin] = 1
				pile.append(voisin)

	# Ce qui reste de la bonne nature sans avoir ete atteint est enclos. Chaque
	# groupe connexe compte pour UNE zone -- deux contours separes sur la meme
	# couche ne font pas une seule zone parce qu'ils partagent une couche.
	var cellules: Array[Vector3i] = []
	var zones := 0
	for depart in range(total):
		if etat[depart] != 0 or not _est_de_la_nature(carte, depart, cherche_vide):
			continue
		zones += 1
		etat[depart] = 2
		var groupe: Array[int] = [depart]
		while not groupe.is_empty():
			var index: int = groupe.pop_back()
			@warning_ignore("integer_division")
			cellules.append(Vector3i(
				index / cote + bas.x, couche_lue, index % cote + bas.y))
			for voisin in _voisins(index, cote):
				if etat[voisin] == 0 and _est_de_la_nature(carte, voisin, cherche_vide):
					etat[voisin] = 2
					groupe.append(voisin)
	return { "cellules": cellules, "zones": zones }

static func _est_de_la_nature(carte: PackedByteArray, index: int, cherche_vide: bool) -> bool:
	return (carte[index] == 0) == cherche_vide

# Les quatre voisins orthogonaux, sans ceux qui sortent de l'emprise.
static func _voisins(index: int, cote: int) -> Array[int]:
	var x := index / cote
	var z := index % cote
	var trouves: Array[int] = []
	if x > 0:
		trouves.append(index - cote)
	if x < cote - 1:
		trouves.append(index + cote)
	if z > 0:
		trouves.append(index - 1)
	if z < cote - 1:
		trouves.append(index + 1)
	return trouves

func remplissage_en_cours() -> bool:
	return _en_cours

func _appliquer() -> void:
	if _en_cours:
		push_warning("un remplissage est deja en cours : celui-ci est ignore")
		return

	var grille := Commun.terrain_frere(self)
	if grille == null:
		return

	var bloc := GridMap.INVALID_CELL_ITEM
	if mode == Mode.REMPLIR:
		bloc = Commun.premier_bloc(grille)
		if bloc == GridMap.INVALID_CELL_ITEM:
			return

	# VOIR fenetre_utile : on travaille sur ce qui est POSE, jamais sur l'emprise
	# declaree -- vingt-cinq millions de cases sur une carte de cent kilometres
	# carres, pour un contour qui en occupe quelques centaines.
	var fenetre := fenetre_utile(grille, couche)
	var bas: Vector2i = fenetre.bas
	var cote: int = fenetre.cote
	var carte := occupation(grille, couche, bas, cote)
	var trouve := zones_encloses(carte, bas, cote, couche, mode == Mode.REMPLIR)
	var cellules: Array[Vector3i] = trouve["cellules"]
	print("%s couche %d : %d zone(s) close(s), %d cellules concernees" % [
		Mode.keys()[mode], couche, trouve["zones"], cellules.size()])
	if trouve["zones"] == 0:
		print("  %s" % _pourquoi_rien(carte))
		return

	_en_cours = true
	var index := 0
	var changees := 0
	while index < cellules.size():
		var tranche := Commun.ecrire_cellules(
			grille, cellules, bloc, index, CELLULES_PAR_FRAME)
		index = tranche["index"]
		changees += tranche["changees"]
		if index >= cellules.size():
			break
		# Hors arbre, aucune frame ne viendra jamais : attendre la pendrait.
		if get_tree() == null:
			continue
		await get_tree().process_frame
		# Le terrain peut disparaitre pendant l'attente -- scene fermee, noeud
		# supprime a la main. On s'arrete la ou on en est, sans planter.
		if not is_instance_valid(grille):
			push_warning("le terrain a disparu : remplissage interrompu a %d cellules" % index)
			break
	_en_cours = false

	print("  %d cellules modifiees sur %d parcourues" % [changees, index])

# Zero zone close a deux causes, et les confondre ferait chercher au mauvais
# endroit : une couche sans aucun cube n'a rien a entourer, une couche qui en
# porte a des contours qui fuient.
func _pourquoi_rien(carte: PackedByteArray) -> String:
	var pleines := 0
	for case in carte:
		pleines += case
	if pleines == 0:
		return "la couche %d ne porte aucun cube : rien ne peut entourer quoi que ce soit" % couche
	if mode == Mode.REMPLIR:
		return ("%d cubes sur la couche, mais tout le vide communique avec le bord de la " +
			"carte : aucun contour ne se referme, ou il s'appuie sur le bord") % pleines
	return ("%d cubes sur la couche, tous relies au bord de la carte : aucune masse " +
		"isolee a retirer") % pleines
