@tool
extends Node3D

# OUTIL D'EDITEUR, jamais du jeu. Accroche a un noeud pose a cote du GridMap,
# il pose ou retire des cellules PAR BOITE au lieu d'un cube a la fois. Il ne
# tourne QUE dans l'editeur : aucun _ready, aucun _process, rien ne se
# declenche tout seul -- le seul evenement qui l'active est une case cochee
# dans l'inspecteur. Lance en jeu, ce noeud ne fait rien.
#
# Entree : les quatre proprietes exportees ci-dessous, reglees a la main.
# Sortie : les cellules du GridMap frere, posees ou retirees, plus une trace
# console. Ne touche a aucun fichier -- c'est Ctrl+S dans l'editeur qui ecrit
# la scene, jamais cet outil.
#
# DEUX MOITIES, comme les bancs. Fonctions STATIQUES pures (bornes, volume,
# volume_demande, ecrire_tranche), testables sans editeur, ou vit tout le
# calcul ; methodes d'instance, qui ne font que retrouver le terrain et le
# bloc puis enchainer les tranches. La case cochee declenche, elle ne calcule
# jamais.
#
# LA BOITE N'EST JAMAIS MATERIALISEE EN MEMOIRE. Chaque cellule se calcule
# depuis son INDEX LINEAIRE dans la boite, au moment de l'ecrire. Construire
# d'abord la liste complete est ECARTE : le cout ne vient pas des poses (cent
# mille cellules s'ecrivent en quelques dizaines de millisecondes) mais du
# tableau alloue avant la premiere d'entre elles -- une boite de mille couches
# fait seize millions d'entrees, et rien n'est encore pose.
#
# L'ECRITURE EST DECOUPEE PAR FRAME. Un editeur ne rend rien tant qu'un appel
# ne lui a pas rendu la main : tout ce qui s'ecrit d'un seul tenant le fige,
# quelle que soit la duree. L'outil pose CELLULES_PAR_FRAME cellules, rend la
# main, reprend a la frame suivante. L'editeur reste vivant, la sculpture
# s'affiche au fur et a mesure, et une boite demesuree se voit avancer au lieu
# de figer en silence. Sans arbre de scene -- hors editeur -- il n'y a aucune
# frame a attendre : tout passe d'un coup, meme code d'ecriture.
#
# L'EMPRISE EST LUE SUR LA CARTE que porte un noeud frere, et seulement a defaut
# chez le generateur. Une carte declare son emprise : ecreter a la constante du
# generateur refuserait toute sculpture hors des cent cinquante premieres
# cellules, c'est-a-dire partout sauf au centre d'une carte de cent kilometres
# carres. Jamais recopiee : deux nombres qui doivent s'accorder finissent
# toujours par diverger. La hauteur, elle, n'est
# bornee NULLE PART -- ni vers le haut ni vers le bas, c'est le sculpteur qui
# decide, et ce qu'il demande s'annonce en console avant de commencer.
#
# RIEN N'EST ANNULABLE : Ctrl+Z defait la case cochee, jamais les cellules
# ecrites. Une annulation reelle demanderait un EditorPlugin et son UndoRedo,
# qui n'existent pas ici. La parade est la meme dans l'autre sens -- creuser
# la boite qu'on vient de remplir.
#
# Regles tenues : toutes les positions sont des Vector3i (grille) ou des
# Vector3, jamais des Vector2. Aucun hasard. Les traces sont des sorties de
# mise au point pour l'editeur, jamais du texte joueur.

const Generateur = preload("res://jeu/terrain/generer_carte.gd")
const Commun = preload("res://jeu/terrain/terrain_commun.gd")

# Mesure, pas au juge : a cette taille, la pose et la reconstruction d'octant
# qui la suit tiennent sous trente millisecondes par frame.
const CELLULES_PAR_FRAME := 2048

enum Mode { REMPLIR, CREUSER }

@export var mode: Mode = Mode.REMPLIR
@export var coin_debut := Vector3i.ZERO
@export var coin_fin := Vector3i.ZERO

# La case se decoche AVANT d'agir : elle est un declencheur, pas un etat. Ainsi
# rien ne reste coche dans la scene enregistree, et une action qui echoue ne
# laisse pas une case allumee qui ferait croire le contraire.
@export var appliquer := false:
	set(demande):
		appliquer = false
		if demande:
			_appliquer()

var _en_cours := false

# Bornes de la boite fermee entre deux coins, ECRETEES en x et en z a l'emprise
# du terrain, jamais en hauteur. L'ordre des deux coins n'a aucune importance.
# Rend [bas, haut] ; une borne haute inferieure a la borne basse sur un axe
# designe une boite VIDE, ce que volume() lit comme zero.
static func bornes(coin_a: Vector3i, coin_b: Vector3i, demi_cote: int) -> Array[Vector3i]:
	return [
		Vector3i(
			maxi(mini(coin_a.x, coin_b.x), -demi_cote),
			mini(coin_a.y, coin_b.y),
			maxi(mini(coin_a.z, coin_b.z), -demi_cote)),
		Vector3i(
			mini(maxi(coin_a.x, coin_b.x), demi_cote - 1),
			maxi(coin_a.y, coin_b.y),
			mini(maxi(coin_a.z, coin_b.z), demi_cote - 1)),
	]

static func volume(bas: Vector3i, haut: Vector3i) -> int:
	if haut.x < bas.x or haut.y < bas.y or haut.z < bas.z:
		return 0
	return (haut.x - bas.x + 1) * (haut.y - bas.y + 1) * (haut.z - bas.z + 1)

# Ce que la boite demanderait sans ecretage. Sert a DIRE combien de cellules
# sont tombees hors emprise, jamais a decider quoi que ce soit.
static func volume_demande(coin_a: Vector3i, coin_b: Vector3i) -> int:
	return (absi(coin_a.x - coin_b.x) + 1) \
		* (absi(coin_a.y - coin_b.y) + 1) \
		* (absi(coin_a.z - coin_b.z) + 1)

# Ecrit les cellules d'index lineaire [depuis, depuis + combien) et rend
# { index, changees } : l'index atteint, et le nombre de cellules dont l'etat a
# REELLEMENT change. Un seul geste pour les deux modes : poser un bloc et
# retirer un bloc sont le meme appel, l'identifiant change
# (GridMap.INVALID_CELL_ITEM vide la cellule).
#
# UNE CELLULE DEJA DANS L'ETAT DEMANDE N'EST PAS REECRITE. Deux raisons, la
# premiere etant la vraie : le nombre de cellules PARCOURUES ne dit rien de ce
# qui a bouge a l'ecran -- remplir une boite deja pleine parcourt tout et ne
# change rien, et un rapport qui ne compte que le parcours fait chercher une
# panne la ou il n'y en a pas. La seconde est un gain : une cellule non
# reecrite ne salit pas son octant, donc ne le fait pas reconstruire.
static func ecrire_tranche(grille: GridMap, bas: Vector3i, haut: Vector3i,
		bloc: int, depuis: int, combien: int) -> Dictionary:
	var total := volume(bas, haut)
	if total == 0:
		return { "index": 0, "changees": 0 }
	var largeur_z := haut.z - bas.z + 1
	var par_couche := (haut.x - bas.x + 1) * largeur_z
	# Une tranche AVANCE toujours d'au moins une cellule : rendre l'index recu
	# tel quel ferait tourner sans fin la boucle qui appelle.
	var index := clampi(depuis, 0, total)
	var fin := mini(index + maxi(combien, 1), total)
	var changees := 0
	while index < fin:
		var reste := index % par_couche
		var cellule := Vector3i(
			bas.x + reste / largeur_z,
			bas.y + index / par_couche,
			bas.z + reste % largeur_z)
		if grille.get_cell_item(cellule) != bloc:
			grille.set_cell_item(cellule, bloc)
			changees += 1
		index += 1
	return { "index": fin, "changees": changees }

func sculpture_en_cours() -> bool:
	return _en_cours

func _appliquer() -> void:
	if _en_cours:
		push_warning("une sculpture est deja en cours : celle-ci est ignoree")
		return

	var grille := Commun.terrain_frere(self)
	if grille == null:
		return

	var bloc := GridMap.INVALID_CELL_ITEM
	if mode == Mode.REMPLIR:
		bloc = Commun.premier_bloc(grille)
		if bloc == GridMap.INVALID_CELL_ITEM:
			return

	var boite := bornes(coin_debut, coin_fin, Commun.emprise_fraternelle(self, Generateur.DEMI_COTE))
	var total := volume(boite[0], boite[1])
	var ecartees := volume_demande(coin_debut, coin_fin) - total
	print("%s : %d cellules de %s a %s (%d hors emprise, ignorees), %d frames" % [
		Mode.keys()[mode], total, coin_debut, coin_fin, ecartees,
		ceili(float(total) / CELLULES_PAR_FRAME)])

	_en_cours = true
	var index := 0
	var changees := 0
	while index < total:
		var tranche := ecrire_tranche(
			grille, boite[0], boite[1], bloc, index, CELLULES_PAR_FRAME)
		index = tranche["index"]
		changees += tranche["changees"]
		if index >= total:
			break
		# Hors arbre, aucune frame ne viendra jamais : attendre la pendrait.
		if get_tree() == null:
			continue
		await get_tree().process_frame
		# Le terrain peut disparaitre pendant l'attente -- scene fermee, noeud
		# supprime a la main. On s'arrete la ou on en est, sans planter.
		if not is_instance_valid(grille):
			push_warning("le terrain a disparu : sculpture interrompue a %d cellules" % index)
			break
	_en_cours = false

	print("  %d cellules modifiees sur %d parcourues" % [changees, index])
	if changees == 0 and index > 0:
		print("  rien n'a bouge a l'ecran : la boite etait deja dans cet etat")

# Retrouver le terrain et choisir le bloc sont les MEMES gestes pour tous les
# outils : ils vivent dans terrain_commun.gd, jamais recopies ici.
