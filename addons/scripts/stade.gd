extends RefCounted

# Mecanisme du coeur : STADE -- fait avancer le stade de vie d'une entite
# selon son age. Remplace le booleen mature (jamais ecrit dans ce depot) par
# un systeme de stades OUVERT : chaque type declare ses propres stades en
# donnee (data/types.json, cle stades_config), ce fichier ne connait AUCUN
# nom de stade -- ni "nouveau_ne", ni "larve", ni "graine" n'apparaissent
# ici, seulement dans les catalogues recus (portes par l'entite elle-meme,
# voir plus bas) et dans le test hors domaine.
#
# MODELE : proprietes.stades_config (Array ORDONNE par age_seuil CROISSANT,
# chaque element { nom: String, age_seuil: float }) declare la table ;
# proprietes.stade (String) porte le nom du stade COURANT. avancer() trouve
# l'INDEX du dernier element de stades_config dont age_seuil <= proprietes.age
# (le stade le plus avance que l'age atteint autorise), et n'ecrit
# proprietes.stade QUE si cet index est STRICTEMENT plus avance que l'index
# du stade courant dans la meme table -- JAMAIS un retour en arriere, meme
# si stades_config n'etait pas parfaitement ordonnee ou si l'appelant faisait
# reculer l'age (aucun mecanisme du depot ne le fait aujourd'hui --
# senescence.gd n'incremente jamais a la baisse -- mais la garde compare des
# INDEX dans la table, pas des ages, donc ne suppose pas cette invariante).
#
# Structurel vs facultatif (voir docs/design.md, "Propriete structurelle vs
# facultative") : proprietes.age et proprietes.stades_config sont
# STRUCTURELLES ICI -- posees sur data/types.json:dynamique (0.0 / [] par
# defaut), heritees par tout type qui compose ce paquet, meme geste que
# age/genes_actifs/marques_epigenetiques (voir senescence.gd/expression.gd).
# Leur cle absente dit "ceci n'est pas une entite equipee pour porter un
# stade de vie", jamais "stade neutre" -- push_error puis aucune ecriture.
# proprietes.stades_config VIDE ([]) reste un point neutre LEGITIME (aucun
# stade declare pour ce type) : aucune alarme, aucune ecriture, meme contrat
# qu'un genes_actifs vide dans expression.gd. proprietes.stade elle-meme
# n'est jamais verifiee structurellement : ce fichier lit sa valeur courante
# seulement pour comparer des index (voir _index_du_stade, qui rend -1 sur
# une chaine vide ou absente de la table -- meme traitement qu'"aucun stade
# encore atteint", jamais une alarme).
#
# NE POSE AUCUNE AUTRE PROPRIETE : ce fichier ne fait QUE mettre a jour le
# String proprietes.stade -- les mecanismes en aval qui veulent reagir a un
# stade (reproduction, capacites) le LISENT, jamais ce fichier qui ne les
# connait pas. Meme patron que senescence.gd (incremente l'age, expression.gd
# fait le reste) : stade.gd compare des nombres et avance un index, rien de
# plus.
#
# NE RECOIT AUCUN CATALOGUE : contrairement a senescence.gd/epigenetique.gd/
# expression.gd, ce fichier ne recoit ni ne charge aucun data/*.json -- la
# table des stades vit DEJA sur l'entite (proprietes.stades_config), jamais
# dans un catalogue partage. Un gene qui voudrait moduler un age_seuil
# (expression.gd) devrait cibler une cle PLATE sur proprietes, jamais un
# element de l'Array stades_config : expression.gd:_lire_chemin/_ecrire_chemin
# ne descendent que dans des Dictionary imbriques (segment par segment), pas
# dans un Array indexe -- aucune donnee reelle ne cible stades_config
# aujourd'hui, aucun changement requis tant que ca reste vrai.
#
# entite : Dictionary { id, position, proprietes }, mute en place par
#          avancer() -- seule proprietes.stade change.
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# proprietes.stade est une String nue, proprietes.stades_config un Array de
# Dictionary a feuilles String/float -- aucun Vector3, aucun Callable.

static func avancer(entite: Dictionary) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("age"):
		push_error("stade.gd : propriete structurelle 'age' absente de proprietes")
		return
	if not proprietes.has("stades_config"):
		push_error("stade.gd : propriete structurelle 'stades_config' absente de proprietes")
		return
	var stades_config: Array = proprietes.stades_config
	if stades_config.is_empty():
		return
	var age: float = proprietes.age
	var index_trouve: int = -1
	for i in range(stades_config.size()):
		var age_seuil: float = stades_config[i].get("age_seuil", 0.0)
		if age >= age_seuil:
			index_trouve = i
	if index_trouve == -1:
		return
	var index_courant: int = _index_du_stade(stades_config, proprietes.get("stade", ""))
	if index_trouve <= index_courant:
		return
	proprietes["stade"] = stades_config[index_trouve].get("nom", "")

static func _index_du_stade(stades_config: Array, nom: String) -> int:
	if nom == "":
		return -1
	for i in range(stades_config.size()):
		if stades_config[i].get("nom", "") == nom:
			return i
	return -1
