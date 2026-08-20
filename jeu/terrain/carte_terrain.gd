@tool
extends Resource

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

# LES SEULES COLONNES QUI S'ECARTENT DU DEFAUT. Clef : la colonne. Valeur : la
# couche de sa cellule pleine la plus haute. Une valeur sous `couche_base`
# designe une colonne VIDE -- creusee jusqu'au fond.
@export var reliefs: Dictionary[Vector2i, int] = {}

# Le sommet du terrain plein par defaut, celui que rend toute colonne non
# sculptee.
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

# La couche de la cellule pleine la plus haute d'une colonne, ou null.
#
# NULL A DEUX CAUSES ET AUCUN APPELANT N'A BESOIN DE LES DISTINGUER pour poser
# quoi que ce soit : hors emprise, ou colonne creusee jusqu'au vide. Meme choix
# que surface_terrain.gd:couche_de -- un entier sentinelle serait pris pour une
# couche reelle.
func sommet(colonne: Vector2i) -> Variant:
	if not dans_emprise(colonne):
		return null
	var couche: int = reliefs.get(colonne, sommet_de_base())
	if couche < couche_base:
		return null
	return couche

# Ecrit le sommet d'une colonne. Rend false quand la colonne est hors emprise --
# ecrire hors emprise poserait de la matiere qu'aucun outil ne retrouverait.
#
# UNE COLONNE REMISE AU DEFAUT SORT DU STOCKAGE. Sans ca, sculpter puis defaire
# laisserait derriere lui une entree par geste, et le poids de la carte suivrait
# le nombre de gestes au lieu de ce qui est reellement sculpte.
func sculpter(colonne: Vector2i, couche: int) -> bool:
	if not dans_emprise(colonne):
		return false
	if couche == sommet_de_base():
		reliefs.erase(colonne)
	else:
		reliefs[colonne] = couche
	return true

# Le nombre de colonnes qui s'ecartent du defaut : ce que la carte pese
# reellement, par opposition a ce qu'elle couvre.
func colonnes_sculptees() -> int:
	return reliefs.size()

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

# Les cellules pleines d'une colonne, de la base a son sommet. Liste VIDE pour
# une colonne vide ou hors emprise -- ce qui dessine n'a alors rien a poser.
func cellules_de(colonne: Vector2i) -> Array[Vector3i]:
	var cellules: Array[Vector3i] = []
	var haut: Variant = sommet(colonne)
	if haut == null:
		return cellules
	for y in range(couche_base, int(haut) + 1):
		cellules.append(Vector3i(colonne.x, y, colonne.y))
	return cellules
