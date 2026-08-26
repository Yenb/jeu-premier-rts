@tool
extends Node3D

# UN PEUPLEMENT : un noeud pose sous le Couvert qui declare une population
# initiale d'une espece, deja repartie sur ses stades. Le Couvert le
# reconnait au ready et fabrique N plantes deja au stade demande, chacune
# avec son age cumule -- comme si elles avaient vecu jusque-la.
#
# POURQUOI PAS LE PRECHAUFFAGE : le prechauffage joue la simulation entiere
# avant la premiere image, ce qui coute a la population fabriquee. Un
# peuplement pose des plantes DIRECTEMENT au bon stade, sans jouer un tick.
# Le joueur arrive sur une foret deja debout, la machinerie (reproduction,
# mort, croissance) prend le relais aussitot.
#
# LES POSITIONS SONT TIREES DANS UN DISQUE de rayon `rayon_dispersion` autour
# de la position de ce noeud. Le tirage est SEEDE : deux parties de meme
# graine donnent le meme peuplement.
#
# COPIE-COLLE : chaque Peuplement declare une foret independante. Poser
# deux Peuplement a des endroits differents fait deux forets differentes,
# possiblement de compositions differentes.
#
# CE FICHIER NE SIMULE RIEN : couvert.gd le lit au ready, tire les positions,
# et pose autant de semis dans l'etat de simulation qu'il a d'individus a
# declarer. Aucune classe de contenu ici : `espece` est une CLE (le meme mot
# qu'un semis met dans son champ `type`).

@export var espece: String = ""
@export var rayon_dispersion: float = 30.0
@export var seed_rng: int = 20260824
# COMBIEN D'INDIVIDUS PAR STADE, un champ nomme par stade au lieu d'un tableau
# opaque indexe. Le stade 1 est le PLUS JEUNE de l'espece, le stade 6 le PLUS
# VIEUX. Les NOMS des stades (enfant, adulte, vieux...) vivent sur le noeud de
# l'espece, pas ici : ce noeud est generique et ne connait aucune espece. Un
# stade au-dela du dernier de l'espece est ignore (signale en console).
@export_group("Nombre d'individus par stade")
## Le plus jeune stade de l'espece.
@export var nombre_stade_1: int = 0
@export var nombre_stade_2: int = 0
@export var nombre_stade_3: int = 0
@export var nombre_stade_4: int = 0
@export var nombre_stade_5: int = 0
## Le plus vieux stade de l'espece.
@export var nombre_stade_6: int = 0

@export_group("Etalement")

# COMBIEN DE PLANTES FABRIQUEES PAR TICK (etalement du spawn). Sans ce
# budget, N plantes fabriquees d'un coup donnent un pic ~650 ms a N=1000
# (fabriquer_plante + rebuild monde + rafraichir_toutes). A 30 plantes/tick,
# le pic disparait : ~20-25 ms par frame etalees sur ceil(N/30) ticks.
@export var budget_par_frame: int = 30

# FENETRE D'ETALEMENT VISUEL, en secondes. Chaque plante recoit un
# age_initial = age_seuil_cible + aleatoire dans [-duree/2, +duree/2]. Les
# plantes atteignent leur stade cible a des instants disperses -> apparence
# progressive au lieu d'un pop-in bloc. Independant du budget frame.
@export var duree_dispersion_apparition: float = 3.0

# LES NOMBRES, rassembles en tableau indexe par stade (index 0 = stade 1) --
# c'est la SEULE chose que couvert.gd lit, il ne connait jamais les champs.
func nombres() -> Array[int]:
	return [nombre_stade_1, nombre_stade_2, nombre_stade_3,
		nombre_stade_4, nombre_stade_5, nombre_stade_6]

func _get_configuration_warnings() -> PackedStringArray:
	var alertes := PackedStringArray()
	if espece == "":
		alertes.append("Ce peuplement ne nomme aucune espece : le Couvert l'ignorera.")
	var total := 0
	for n in nombres():
		total += int(n)
	if total <= 0:
		alertes.append("Ce peuplement ne declare aucun individu : il ne pose rien.")
	if rayon_dispersion <= 0.0:
		alertes.append("Rayon de dispersion nul ou negatif : tous les individus tomberaient au meme endroit.")
	return alertes
