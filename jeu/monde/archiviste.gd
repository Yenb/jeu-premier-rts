@tool
extends Node

# CE QUI ECRIT LE MONDE SUR LE DISQUE, et la seule chose qui le fasse. Il tient
# une liste de registres -- terrain, objets, vegetation, creatures, rivieres --
# et ecrit ceux qui se sont marques sales. Rien d'autre du jeu n'appelle
# ResourceSaver.
#
# Entree : des registres (voir registre.gd), un intervalle. Sortie : des
# fichiers sur le disque, et une trace par ecriture.
#
# AJOUTER UNE SORTE DE DONNEE AU MONDE NE DEMANDE AUCUNE LIGNE ICI. Elle herite
# de registre.gd, elle se marque quand elle change, on la glisse dans la liste :
# elle est enregistree. C'est toute la raison d'etre de ce fichier -- sans lui,
# chaque domaine porterait son propre code d'ecriture, son propre oubli, et son
# propre defaut le jour ou personne ne pense a l'appeler.
#
# IL ECRIT DANS L'EDITEUR COMME EN JEU. Sculpter un terrain, miner un bloc en
# partie, une creature qui se deplace hors de vue : ce sont trois modifications
# du meme monde, et aucune n'a de raison d'etre traitee a part.
#
# A INTERVALLE, JAMAIS A CHAQUE IMAGE. Ecrire des qu'un bit change relancerait
# une serialisation complete a chaque cellule posee. On regarde toutes les
# `secondes_entre_ecritures` et on n'ecrit que ce qui est marque -- souvent
# rien, et ca ne coute alors qu'un parcours de la liste.
#
# CE QU'IL NE FAIT PAS, ET QUI SE VERRA A L'ECHELLE : l'ecriture est SYNCHRONE.
# ResourceSaver bloque le temps qu'il ecrit, et un registre de plusieurs
# megaoctets se sentira. Les moteurs a monde ouvert ecrivent sur un fil separe ;
# ce sera a mesurer avant de le faire ici, jamais a supposer.
#
# Regles tenues : aucun hasard. Aucun texte visible par le joueur. Aucun nom de
# contenu. Rien de scripts/, data/ ni documents/ n'est lu ni ecrit.

# Les donnees du monde a garder. Ordre sans importance : chacune est ecrite pour
# elle-meme.
@export var registres: Array[Resource] = []

# Tout ce qui suit est un reglage, jamais une constante : un monde qui change
# vite veut un intervalle court, un monde de contemplation non.
@export var secondes_entre_ecritures: float = 2.0

# A false, plus rien ne s'ecrit -- utile pour eprouver une modification sans la
# garder. Ce qui est marque le reste, et partira a la prochaine ecriture.
@export var actif := true

@export var journal := true

var _depuis := 0.0

func _process(delta: float) -> void:
	if not actif:
		return
	_depuis += delta
	if _depuis < maxf(secondes_entre_ecritures, 0.0):
		return
	_depuis = 0.0
	ecrire_les_sales()

# Ecrit tous les registres marques. Rend le nombre de fichiers ecrits.
#
# UN REGISTRE QUI ECHOUE NE SE DECLARE PAS PROPRE : il repassera a la prochaine
# ecriture. Se croire enregistre apres un echec est la seule facon de perdre du
# travail sans qu'aucune trace ne le dise.
func ecrire_les_sales() -> int:
	var ecrits := 0
	for registre in registres:
		if registre == null or not registre.has_method("est_sale"):
			continue
		if not registre.est_sale():
			continue
		if not registre.peut_etre_ecrit():
			push_warning("%s n'a aucun chemin sur le disque : sa modification ne sera pas gardee" % [
				registre.nom_lisible()])
			continue
		var erreur := ResourceSaver.save(registre, registre.resource_path)
		if erreur != OK:
			push_error("ecriture de %s impossible (erreur %d) : le registre reste marque" % [
				registre.nom_lisible(), erreur])
			continue
		registre.marquer_propre()
		ecrits += 1
		if journal:
			print("monde ecrit : %s" % registre.nom_lisible())
	return ecrits

# Combien de registres attendent d'etre ecrits. Sert aux tests et aux traces,
# jamais a decider quoi que ce soit.
func en_attente() -> int:
	var combien := 0
	for registre in registres:
		if registre != null and registre.has_method("est_sale") and registre.est_sale():
			combien += 1
	return combien
