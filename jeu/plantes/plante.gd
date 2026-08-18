@tool
extends Node3D

const EspeceScript = preload("res://jeu/plantes/espece.gd")

# UNE GRAINE POSEE A LA MAIN : un marqueur de placement, et rien de plus.
#
# CE FICHIER NE SIMULE RIEN. Ni age, ni stade, ni reproduction, ni mort : tout
# cela vit dans jeu/plantes/vegetation.gd, qui tourne sur des donnees et sans un
# seul noeud. La regle qui l'impose est non negociable (CLAUDE.md) -- « La
# simulation ne depend JAMAIS de l'affichage : le moteur doit pouvoir tourner
# sans rendu ». Une plante qui porterait sa propre horloge rendrait la population
# impossible a simuler sans arbre de scene, donc impossible a tester headless, et
# le premier resume d'etat pour l'LLM devrait relire des noeuds.
#
# CE QUE CE NOEUD EST, ALORS : une position et une espece. Au lancement,
# jeu/plantes/couvert.gd releve sa colonne, en fait une plante de simulation, et
# prend la main sur tout le reste.
#
# ON NE POSE PAS CE NOEUD-CI, on pose une de ses SCENES DERIVEES --
# jeu/plantes/arbre.tscn, jeu/plantes/herbe.tscn -- une par espece. Chacune arrive
# avec son espece deja renseignee et son propre carre coloree : le game designer
# choisit ce qu'il plante en choisissant la scene, jamais en tapant un nom. Une
# faute de frappe retombait en silence sur l'espece par defaut ; ce n'est plus
# possible.
#
# LES REGLAGES NE SONT PAS ICI. Ils vivent sur le noeud d'espece (Arbre, Herbe)
# sous le Couvert : UN SEUL ENDROIT PAR ESPECE. Poser cent semis ne fait pas cent
# copies d'une duree a tenir d'accord -- changer une valeur les change tous.
#
# SES ENFANTS D'EDITEUR SONT LIBERES AU LANCEMENT. Le rendu d'une plante vivante
# est le modele 3D de son stade, que le Couvert instancie sous ce noeud -- pas ce
# cube-ci, qui n'existe que pour se voir et se deplacer dans l'editeur. Le
# laisser en place poserait deux objets au meme endroit, dont un qui ne grandit
# jamais.
#
# Entree : sa transform, posee a la main. Sortie : rien -- il est LU, jamais
# appele.
#
# Regles tenues : positions en Vector3. Aucun texte joueur ici -- l'avertissement
# de configuration est un outil d'editeur, au meme titre qu'un print de mise au
# point, et ne franchit jamais l'ecran du joueur. Rien de scripts/, data/ ni
# addons/ n'est ecrit.

# L'ESPECE que ce semis reclame : `res://jeu/plantes/<type>.json`. Vide = l'espece
# par defaut declaree dans vegetation.json -- jamais un nom ecrit ici, ce qui
# laisserait un nom de contenu dans un .gd (CLAUDE.md, ADN).
@export var type: String = "":
	set(valeur):
		type = valeur
		update_configuration_warnings()

# Le GridMap sous lequel ce semis pousse, cherche PAR TYPE en remontant les
# ancetres -- jamais par nom : renommer un noeud dans l'editeur ne doit rien
# casser. Meme doctrine que jeu/terrain/terrain_commun.gd:terrain_frere, qui
# cherche parmi les freres pour la meme raison.
#
# Rend null quand aucun ancetre n'est un GridMap : la graine est alors hors
# terrain, ce que l'avertissement ci-dessous signale.
func terrain() -> GridMap:
	var noeud := get_parent()
	while noeud != null:
		if noeud is GridMap:
			return noeud
		noeud = noeud.get_parent()
	return null

# AVERTISSEMENT D'EDITEUR SEULEMENT, et deliberement PAUVRE : il ne dit que ce
# qui se verifie sans rien relever. La contrainte de couche exige le sol le plus
# bas de TOUTE la carte, donc un balayage complet du GridMap qu'on ne rejoue pas a
# chaque changement de selection ; c'est jeu/plantes/couvert.gd qui la verifie,
# une fois, et qui nomme en console chaque graine hors couche.
func _get_configuration_warnings() -> PackedStringArray:
	var alertes := PackedStringArray()
	if terrain() == null:
		alertes.append("Aucun GridMap parmi les ancetres : ce semis n'est sur aucun terrain.")
	if type != "" and not _espece_declaree(type):
		alertes.append("Aucune espece nommee '%s' parmi les freres de ce semis." % type)
	return alertes

# L'ESPECE SE CHERCHE PARMI LES FRERES, la ou le Couvert la cherche lui-meme : un
# semis et les especes qu'il peut reclamer sont enfants du meme noeud. Chercher un
# FICHIER serait faux depuis que les especes sont des noeuds -- et c'est ce que ce
# controle faisait, en signalant un JSON qui n'existe plus.
func _espece_declaree(nom: String) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	for frere in parent.get_children():
		if frere.get_script() == EspeceScript and String(frere.nom) == nom:
			return true
	return false
