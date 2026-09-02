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
# ELLE PUBLIE SES CHANGEMENTS COLONNE PAR COLONNE, pour qui veut suivre. Chaque
# poser_masque qui modifie reellement une colonne l'inscrit dans UN ensemble PAR
# CONSOMMATEUR NOMME que `drainer_modifications(nom)` rend et VIDE. Pas de
# signal Godot : le framework est data pur (aucun `signal` dans `scripts/`), un
# appelant DRAINE quand il veut au lieu qu'on lui pousse. UN dict par
# consommateur, jamais un dict partage : deux appelants qui drainent le meme
# ensemble se le voleraient au premier appel. Le premier drain d'un nom cree
# son entree ; les modifications ANTERIEURES a cet enregistrement sont
# perdues -- c'est acceptable car les appelants du jeu (rendu streame,
# collision streame) font un rafraichissement complet a leur `_ready`.
#
# L'INSCRIPTION EST GATEE PAR `is_editor_hint()`. En editeur, l'outil de
# sculpture appelle poser_masque des milliers de fois sans qu'aucun streamer ne
# draine ; l'inscription y grossirait sans utilite. En jeu, le drain vide au fil
# de l'eau. Cet etat n'est jamais persiste -- il ne vit que pour la duree d'une
# session.
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

# nom_consommateur (String) -> Dictionary[colonne Vector2i -> true]. Chaque
# consommateur a son propre ensemble de colonnes modifiees. Etat runtime, jamais
# persiste. Voir en-tete section "ELLE PUBLIE SES CHANGEMENTS COLONNE PAR
# COLONNE".
var _drains: Dictionary = {}

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
#
# `sommet_max_colonne` rend la COUCHE MAX (int) sans tenir compte des sous-cubes
# entames. Utilite : rendu AABB, tests de sculpture (le bloc EST la, meme s'il
# est cassé). Pour tout ce qui doit interagir physiquement avec le sol (chute,
# snap Y, blocage, tir), utiliser `sommet(x_monde, z_monde)` qui rend la Y monde
# precise au sous-cube pres.
func sommet_max_colonne(colonne: Vector2i) -> Variant:
	var bits := masque(colonne)
	if bits == 0:
		return null
	return couche_base + rang_le_plus_haut(bits)

# LA Y MONDE DU SOMMET REEL au point (x_monde, z_monde). Prend en compte les
# sous-cubes cassés dans la couche du haut : si la cellule sommet a un sous-cube
# du haut cassé pile sous (x, z), la Y descend d'1/3 de cote_cellule (ou plus si
# la rangée sous est aussi cassée). Retourne null si vide/hors emprise.
#
# CE QU'ELLE EST : la vérité au sous-cube près, la source pour tout ce qui
# doit tomber/reposer sur le sol. La doctrine data l'exige : un ennemi tombe
# dans un trou d'un sous-cube parce que la carte le sait.
func sommet(x_monde: float, z_monde: float) -> Variant:
	var cote_f: float = cote
	var cx: int = int(floor(x_monde / cote_f))
	var cz: int = int(floor(z_monde / cote_f))
	var col := Vector2i(cx, cz)
	var couche_max: Variant = sommet_max_colonne(col)
	if couche_max == null:
		return null
	var couche: int = int(couche_max)
	# Position du point DANS la cellule, ramenee a [0, 3) sur chaque axe.
	var x_local: float = x_monde - float(cx) * cote_f
	var z_local: float = z_monde - float(cz) * cote_f
	var ix: int = clampi(int(floor(x_local * 3.0 / cote_f)), 0, 2)
	var iz: int = clampi(int(floor(z_local * 3.0 / cote_f)), 0, 2)
	# Cherche le plus haut iy (dans la couche sommet) dont le sous-cube (ix, iy, iz)
	# est plein. Si aucun, la cellule sommet est trouee sous ce point --
	# descendre a la couche du dessous.
	var cellule := Vector3i(cx, couche, cz)
	var masque_sc: int = sous_cubes(cellule)
	for iy in range(2, -1, -1):
		var idx: int = ix + iy * 3 + iz * 9
		if (masque_sc & (1 << idx)) != 0:
			return float(couche) * cote_f + (float(iy) + 1.0) * (cote_f / 3.0)
	# Aucun sous-cube plein sous ce point dans la couche sommet.
	# Descendre : cherche la premiere couche sous qui a un sous-cube plein a (ix, iz).
	var c := couche - 1
	while c >= couche_base:
		if not est_pleine(col, c):
			c -= 1
			continue
		var m: int = sous_cubes(Vector3i(cx, c, cz))
		for iy in range(2, -1, -1):
			var idx2: int = ix + iy * 3 + iz * 9
			if (m & (1 << idx2)) != 0:
				return float(c) * cote_f + (float(iy) + 1.0) * (cote_f / 3.0)
		c -= 1
	return null

# LE RANG DU BIT LE PLUS HAUT, par dichotomie : six comparaisons au lieu de
# soixante-trois. Ce n'est pas de l'elegance -- `sommet` est appele une fois par
# colonne sculptee par la maquette, et la version naive coutait 5 us par colonne
# la ou celle-ci en coute une fraction. Mesure : le plafond du test etait
# franchi.
static func rang_le_plus_haut(bits: int) -> int:
	var rang := 0
	var reste := bits
	if reste >= (1 << 32):
		rang += 32
		reste >>= 32
	if reste >= (1 << 16):
		rang += 16
		reste >>= 16
	if reste >= (1 << 8):
		rang += 8
		reste >>= 8
	if reste >= (1 << 4):
		rang += 4
		reste >>= 4
	if reste >= (1 << 2):
		rang += 2
		reste >>= 2
	if reste >= 2:
		rang += 1
	return rang

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
	# ET C'EST ICI QU'ELLE PUBLIE. Gate sur `is_editor_hint()` : en editeur,
	# personne ne draine, les dicts grossiraient pour rien. Inscription dans
	# TOUS les drains connus -- un consommateur enregistre est un consommateur
	# qui verra.
	if not Engine.is_editor_hint():
		for nom in _drains:
			_drains[nom][colonne] = true
	return true

# Ecrit une colonne PLEINE de la base jusqu'a `couche`. Le geste du sculpteur
# qui raisonne en hauteur : il reste juste tant qu'on ne creuse pas dessous.
# Une couche sous la base vide la colonne.
func sculpter(colonne: Vector2i, couche: int) -> bool:
	return poser_masque(colonne, masque_plein(couche - couche_base + 1))

# REND LES COLONNES MODIFIEES DEPUIS LE DERNIER APPEL DU CONSOMMATEUR `nom`, ET
# VIDE SON ENSEMBLE. Chaque consommateur a son propre dict, jamais partage. Un
# consommateur qui ne draine pas voit son dict grossir sans limite -- charge a
# lui de drainer regulierement. Le premier appel d'un nom cree son entree.
func drainer_modifications(nom: String) -> Array:
	if not _drains.has(nom):
		_drains[nom] = {}
		return []
	var dict: Dictionary = _drains[nom]
	var liste: Array = dict.keys()
	dict.clear()
	return liste

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
	var haut: Variant = sommet_max_colonne(colonne)
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

# ---- SUBDIVISION EN SOUS-CUBES (3x3x3 = 27) ----
#
# Chaque cellule peut etre entamée : le tir n'abat pas un bloc de 2 m³, il
# retire un petit morceau. La resolution est 3x3x3 sous-cubes (chacun ~2/3 m
# de cote). Un masque 32 bits code l'etat (27 bits utiles + 5 reserve),
# bit `i = ix + iy*3 + iz*9`. Bit a 1 = plein, bit a 0 = detruit.
#
# UNE CELLULE PLEINE N'A PAS D'ENTREE : le dict `_masques_sous_cube` ne
# stocke QUE les cellules entamees. Le defaut est gratuit. Meme principe que
# `particularites` et `volumes`.
#
# UNE CELLULE ENTIEREMENT VIDEE (masque = 0) sort du dict ET declenche
# `retirer_cellule` pour la coherence avec `sommet`, `particularites` et la
# gestion streamer. Sans ca, la couche resterait "pleine" au masque colonne
# alors qu'aucun sous-cube ne reste.
const MASQUE_SOUS_CUBE_PLEIN := (1 << 27) - 1

# Nombre de PV a atteindre sur un sous-cube pour qu'il casse. Meme cap partout,
# quelle que soit la source (tir, pioche, autre) -- la difference se fait sur
# la QUANTITE ajoutee par coup, pas sur le cap.
const MAX_PV_SOUS_CUBE := 50

var _masques_sous_cube: Dictionary = {}  # Vector3i cellule -> int masque
# PV par sous-cube : cellule -> {idx -> pv}. Etat data, jamais persiste (idem
# `_drains`). Publie dans les drains a chaque changement pour que le rendu
# puisse foncer la couleur du mini-cube au fil des coups.
var _pv_sous_cubes: Dictionary = {}

# Le masque des sous-cubes d'une cellule. Une cellule dont la couche n'est
# PAS pleine dans le masque colonne rend 0 : elle n'existe plus, aucun
# sous-cube dedans. Sinon absent du dict = plein par defaut (gratuit),
# present = son masque.
func sous_cubes(cellule: Vector3i) -> int:
	if not est_pleine(Vector2i(cellule.x, cellule.z), cellule.y):
		return 0
	return int(_masques_sous_cube.get(cellule, MASQUE_SOUS_CUBE_PLEIN))

func est_sous_cube_plein(cellule: Vector3i, sous_index: int) -> bool:
	if sous_index < 0 or sous_index >= 27:
		return false
	return (sous_cubes(cellule) & (1 << sous_index)) != 0

# Retire un sous-cube. Rend true si l'etat a change (bit etait a 1).
# Publie la colonne dans tous les drains connus -- meme mecanique que
# `poser_masque`. Cellule entierement videe : erase du dict + retire la
# couche via `retirer_cellule` (qui republie aussi la colonne, mais le
# dict de drain a des cles uniques, pas de doublon effectif).
func casser_sous_cube(cellule: Vector3i, sous_index: int) -> bool:
	if sous_index < 0 or sous_index >= 27:
		return false
	if not est_pleine(Vector2i(cellule.x, cellule.z), cellule.y):
		return false
	var bit := 1 << sous_index
	var actuel: int = int(_masques_sous_cube.get(cellule, MASQUE_SOUS_CUBE_PLEIN))
	if (actuel & bit) == 0:
		return false
	var nouveau: int = actuel & ~bit
	if nouveau == 0:
		_masques_sous_cube.erase(cellule)
		retirer_cellule(cellule)
		return true
	_masques_sous_cube[cellule] = nouveau
	marquer_sale()
	if not Engine.is_editor_hint():
		var col := Vector2i(cellule.x, cellule.z)
		for nom in _drains:
			_drains[nom][col] = true
	return true

# PV D'UN SOUS-CUBE : accumule des degats sans casser tant que < MAX_PV.
# Chaque appel ajoute `quantite` PV. Retourne true si le sous-cube A ETE
# CASSE par cet appel (les PV atteignent MAX_PV et le sous-cube est retire
# du dict). Publie dans les drains -- que les degats ou la cassure survienne.
func ajouter_pv_sous_cube(cellule: Vector3i, sous_index: int, quantite: int) -> bool:
	if sous_index < 0 or sous_index >= 27:
		return false
	if not est_pleine(Vector2i(cellule.x, cellule.z), cellule.y):
		return false
	if not est_sous_cube_plein(cellule, sous_index):
		return false
	var par_idx: Dictionary = _pv_sous_cubes.get(cellule, {})
	var pv_actuel: int = int(par_idx.get(sous_index, 0))
	var pv_neuf: int = pv_actuel + quantite
	if pv_neuf >= MAX_PV_SOUS_CUBE:
		par_idx.erase(sous_index)
		if par_idx.is_empty():
			_pv_sous_cubes.erase(cellule)
		else:
			_pv_sous_cubes[cellule] = par_idx
		# casser_sous_cube publie deja dans les drains.
		casser_sous_cube(cellule, sous_index)
		return true
	par_idx[sous_index] = pv_neuf
	_pv_sous_cubes[cellule] = par_idx
	if not Engine.is_editor_hint():
		var col := Vector2i(cellule.x, cellule.z)
		for nom in _drains:
			_drains[nom][col] = true
	return false

# Rend les PV accumules sur ce sous-cube (0 si aucun degat, 0 si absent).
func pv_sous_cube(cellule: Vector3i, sous_index: int) -> int:
	if sous_index < 0 or sous_index >= 27:
		return 0
	var par_idx: Dictionary = _pv_sous_cubes.get(cellule, {})
	return int(par_idx.get(sous_index, 0))

# Le dict des PV pour cette cellule (idx -> pv). Vide si aucun degat.
func pv_sous_cubes_cellule(cellule: Vector3i) -> Dictionary:
	return _pv_sous_cubes.get(cellule, {})

# COUPS DE BECHE : accumule les coups d'outil sur une cellule de terre plein
# sans la transformer tant que < COUPS_BECHE_SEUIL. Meme structure que
# `ajouter_pv_sous_cube` : dict transitoire cellule -> compte, publie dans les
# drains, retourne true UNIQUEMENT au coup qui atteint le seuil. Le caller
# (manager) agit alors -- transformation par `poser_cellule`. Gate item_de ==
# ITEM_DEFAUT : seul le bloc de terre par defaut se beche.
const COUPS_BECHE_SEUIL := 10

var _coups_beche_par_cellule: Dictionary = {}

func ajouter_coups_beche(cellule: Vector3i, quantite: int) -> bool:
	if not est_pleine(Vector2i(cellule.x, cellule.z), cellule.y):
		return false
	if item_de(cellule) != ITEM_DEFAUT:
		return false
	var actuel: int = int(_coups_beche_par_cellule.get(cellule, 0))
	var neuf: int = actuel + quantite
	if neuf >= COUPS_BECHE_SEUIL:
		_coups_beche_par_cellule.erase(cellule)
		if not Engine.is_editor_hint():
			var col := Vector2i(cellule.x, cellule.z)
			for nom in _drains:
				_drains[nom][col] = true
		return true
	_coups_beche_par_cellule[cellule] = neuf
	if not Engine.is_editor_hint():
		var col := Vector2i(cellule.x, cellule.z)
		for nom in _drains:
			_drains[nom][col] = true
	return false

# Le masque que decrivent des couches donnees. Sert a ceux qui relevent un
# GridMap : ils voient des cellules, la carte veut un masque.
static func masque_depuis(couches: Array, base: int) -> int:
	var bits := 0
	for couche in couches:
		var rang: int = int(couche) - base
		if rang >= 0 and rang < COUCHES_MAXIMALES:
			bits |= 1 << rang
	return bits
