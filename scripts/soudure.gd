extends RefCounted

const Objet = preload("res://scripts/objet.gd")

# Mecanisme du coeur : SOUDURE -- fusion IRREVERSIBLE de deux objets
# physiques en un seul objet composite (chantier "soudabilite", voir
# audit_soudabilite.md). Calcul PUR (fabriquer_composite) plus UNE fonction
# qui mute (souder) -- meme repartition que deformation.gd/expression.gd
# (une fonction pure de lecture/construction, une qui ecrit).
#
# DOCTRINE (meme famille que produit.gd -- docs/design.md, "Modele objet" +
# objet.gd, DENSITE EFFECTIVE) : si la composition change, c'est un objet
# DIFFERENT, jamais une mutation de type. La masse du composite n'est donc
# JAMAIS posee a la main -- elle sort de la MEME moyenne ponderee des
# volumes qu'Objet.fabriquer applique deja a tout objet compose (jamais
# reimplementee ici). DIFFERENCE avec produit.gd : celui-ci part d'UN SEUL
# objet et d'un GABARIT de catalogue (rendement de masse, proportions d'un
# type nomme) ; celui-la part de DEUX objets REELS et concatene leurs
# compositions REELLES telles quelles (masse totale conservee, aucun
# rendement, aucun gabarit) -- un parallele a produit.gd, pas une extension
# de son code (produit.gd n'est pas touche, sa signature ne porte qu'un
# seul "proprietes_ancien").
#
# fabriquer_composite (PURE, aucune mutation, aucune connaissance de
# "monde") :
#   proprietes_a / proprietes_b : Dictionary "proprietes" des deux objets
#     qui se soudent -- ce fichier ne lit que "composition" dessus, jamais
#     id/position (memes conventions que produit.gd).
#   materiaux : data/materiaux.json, transmis tel quel a Objet.fabriquer.
#   proprietes_immuables : Array de String (FACULTATIF, defaut []) --
#     data/proprietes_immuables_composition.json:proprietes, transmis tel
#     quel a Objet.fabriquer pour que le composite recalcule TOUTES les
#     proprietes immuables (masse/densite/volume, plus inflammabilite/
#     point_fusion/soudabilite/etc. si demandees) depuis sa composition
#     COMBINEE -- jamais une moyenne des deux valeurs d'origine prise a la
#     main, jamais un recalcul partiel.
#   patron_composite : Dictionary FACULTATIF (defaut {}) -- fusionne TEL
#     QUEL sur le resultat apres fabrication, meme role que
#     produit.gd:config.patron_produit (ce que le composite doit porter en
#     plus de ce que la composition seule determine -- ex. un chantier a
#     reprendre). Dictionary opaque, aucun nom en dur ici.
# Rend : le Dictionary "proprietes" du composite (JAMAIS { id, position,
#   proprietes } -- position/id restent la responsabilite de l'appelant,
#   voir souder() ci-dessous), ou {} si la fusion est REFUSEE :
#   - "composition" absente de l'un des deux -- CE MECANISME EST
#     STRUCTURELLEMENT LIMITE AUX OBJETS PHYSIQUES (voir docs/design.md,
#     "Propriete structurelle vs facultative") : un appelant qui presente
#     ici une chose sans composition (colon, feu, batisse) se trompe de
#     mecanisme, ce n'est pas une absence legitime -- push_error nommant
#     lequel des deux, rien n'est produit.
#   - la fabrication du composite echoue (materiau absent, fiche sans
#     "densite", composition vide) -- ECHEC deja signale par
#     Objet.fabriquer lui-meme (push_error), simplement propage ici.
static func fabriquer_composite(
	proprietes_a: Dictionary,
	proprietes_b: Dictionary,
	materiaux: Dictionary,
	proprietes_immuables: Array = [],
	patron_composite: Dictionary = {},
) -> Dictionary:
	if not proprietes_a.has("composition"):
		push_error("soudure.gd : proprietes_a sans 'composition' -- ne peut pas se souder, mecanisme reserve aux objets physiques")
		return {}
	if not proprietes_b.has("composition"):
		push_error("soudure.gd : proprietes_b sans 'composition' -- ne peut pas se souder, mecanisme reserve aux objets physiques")
		return {}

	var composition_combinee: Array = proprietes_a.composition.duplicate(true) + proprietes_b.composition.duplicate(true)
	var table_synthetique: Dictionary = {"__soudure": {"composition": composition_combinee}}
	var fabrique: Dictionary = Objet.fabriquer("__soudure", "__soudure", Vector3.ZERO, table_synthetique, materiaux, proprietes_immuables)
	if fabrique.is_empty():
		return {}

	var proprietes: Dictionary = fabrique.proprietes
	proprietes.merge(patron_composite, true)
	return proprietes

# souder() : MUTATION EN PLACE -- point d'entree destine a un appelant qui
# tient deja les deux objets reels dans "monde" (meme forme que
# extinction.gd:_appliquer_a_zero, "produire") : "chose_a" ABSORBE
# "chose_b", garde son id ET sa position (jamais recalculee -- aucune
# moyenne de positions, decision de design DELIBEREMENT LAISSEE A
# L'APPELANT s'il veut un jour placer le composite ailleurs qu'a la
# position d'un des deux, voir audit_soudabilite.md §3, point 4 -- NON
# TRANCHE ICI). "chose_b" est VIDEE (proprietes.clear()), jamais retiree
# de "monde" -- ce depot n'a aucune fonction de retrait d'objet
# (scripts/monde.gd, voir CARTE.md §6) ; un fantome { id, position,
# proprietes: {} } y reste pour toujours, meme idiome que extinction.gd
# sur un objet entierement consume (voir audit_soudabilite.md §3, point 3).
#
# GARDE "MEME OBJET" (structurelle, pas un pansement) : "chose_a"/
# "chose_b" avec le MEME id sont refuses -- sans cette garde, cloner un
# objet deux fois dans le meme appel viderait le composite qu'on vient
# d'ecrire au lieu de le laisser survivre (l'ordre "ecrit A, puis vide B"
# effacerait A si A et B sont le MEME Dictionary), une chose ne se soude
# jamais a elle-meme par construction, pas seulement par discipline
# d'appelant.
#
# Rend true si la soudure a eu lieu (chose_a mutee, chose_b videe), false
# sinon -- AUCUNE mutation si false (meme discipline que
# fabriquer_composite : echec net, jamais une ecriture partielle).
#
# PIEGE A CONNAITRE AVANT DE CABLER : le composite est fabrique sur une
# TABLE SYNTHETIQUE d'un seul type, qui ne porte AUCUN "herite" (voir
# fabriquer_composite ci-dessus). Il ne recoit donc PAS les proprietes des
# paquets fondateurs (objet_physique, dynamique...) que les deux soudes
# tenaient de data/types.json -- seules survivent celles que la
# COMPOSITION determine, plus `patron_composite`. Un cablage qui a besoin
# des proprietes de paquet sur le composite les repose LUI-MEME juste
# apres l'appel, ou les passe dans `patron_composite`.
static func souder(
	chose_a: Dictionary,
	chose_b: Dictionary,
	materiaux: Dictionary,
	proprietes_immuables: Array = [],
	patron_composite: Dictionary = {},
) -> bool:
	if chose_a.id == chose_b.id:
		push_error("soudure.gd : chose_a et chose_b portent le meme id ('%s') -- une chose ne se soude jamais a elle-meme" % chose_a.id)
		return false

	var nouvelles_proprietes: Dictionary = fabriquer_composite(
		chose_a.proprietes, chose_b.proprietes, materiaux, proprietes_immuables, patron_composite
	)
	if nouvelles_proprietes.is_empty():
		return false

	chose_a.proprietes.clear()
	chose_a.proprietes.merge(nouvelles_proprietes, true)
	chose_b.proprietes.clear()
	return true
