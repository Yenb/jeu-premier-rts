extends RefCounted

# Mecanisme du coeur : DEFORMATION -- biais accumule par exposition,
# PHASE 4 piece 1/3 du chantier "L'entite comme agent complet" (voir
# docs/cadrage_corps_interne_colon.md, docs/cadrage_phase4_deformation.md,
# docs/suivi_corps_interne_entite.md). Brique pure : aucune source reelle
# ne pose de deformation a ce stade (piece 2, habituation), aucune couche
# de saillance ne la lit encore (piece 3, proximite.gd) -- seul le
# mecanisme existe ici, prouve hors domaine.
#
# Modele : une entite porte un biais NOMME PAR SOURCE puis PAR CIBLE
# (proprietes.deformation_etat[source][cible] = { rapide, lent }) -- deux
# REGISTRES DE DURABILITE, jamais un seul nombre. poser() incremente les
# deux d'un coup (une exposition marque les deux horloges) ;
# avancer() les decroit chacun a son propre taux (rapide s'efface vite,
# lent persiste) -- c'est cette DIFFERENCE de taux qui donne le
# "souvenir court terme vs long terme", pas une propriete du registre
# lui-meme. biais() ne fait que LIRE, jamais n'ecrit : une combinaison
# ponderee (w_rapide/w_lent) des deux registres, destinee a moduler la
# saillance une fois cablee en piece 3 -- ce fichier ne sait pas ce
# qu'un colon en fera.
#
# FORME A (chantier "un seul patron de reference de catalogue", session
# ulterieure) : l'ancien champ unique proprietes.deformation (forme B, la
# CLE de premier niveau ETAIT la reference vers data/deformations.json)
# est remplace par DEUX champs separes -- proprietes.deformation_sources
# (Array de String, les sources ACTIVES pour cette entite, chacune
# verifiee contre data/deformations.json par scripts/test_lint_donnees.gd)
# et proprietes.deformation_etat (Dictionary [source][cible] = { rapide,
# lent }, l'ETAT interne mutable, jamais verifie par le linter -- ce sont
# des donnees, pas des references). "cible" reste une simple cle de
# Dictionary sous deformation_etat : ce n'est PAS une reference de
# catalogue (jamais verifiee contre quoi que ce soit, meme avant ce
# chantier) -- un nom de propriete du monde, comme attache.propriete.
#
# Structurel vs facultatif (voir docs/design.md, "Propriete structurelle
# vs facultative") : proprietes.deformation_sources ET
# proprietes.deformation_etat sont TOUTES DEUX STRUCTURELLES, meme
# convention que proprietes.engagement (couplage.gd) -- la cle absente de
# L'UNE OU L'AUTRE dit "ceci n'est pas une entite equipee pour porter un
# biais", jamais "biais neutre" (les deux remplacent a deux le seul champ
# structurel d'avant ce chantier, meme garantie, jamais un defaut
# silencieux sur aucune des deux). Leurs valeurs vides ([] / {}) sont
# legitimes (aucune deformation encore active/formee). Une SOURCE ou une
# PAIRE source/cible absente de proprietes.deformation_etat est un point
# neutre legitime (aucune exposition encore posee) : poser() la cree,
# avancer()/biais() ne l'inventent jamais. Une source absente du CATALOGUE
# recu en parametre alarme (push_error), meme contrat que "transformation"
# (extinction.gd) ou "regle_id" (couplage.gd) -- catalogue toujours recu
# en parametre, jamais charge par ce fichier.
#
# CONTRAT STRUCTUREL NEUF (poser() uniquement) : une source qui n'est pas
# listee dans proprietes.deformation_sources n'a pas a recevoir d'ecriture
# -- push_error nommant la source ET l'entite, aucune ecriture. Ce
# controle n'existait pas avant ce chantier (la forme B ne distinguait pas
# "source declaree" de "source posee", les deux etaient le meme
# Dictionary) ; il ne change le comportement d'aucun appelant reel du
# depot, chaque source aujourd'hui posee (ex. "habituation" par
# banc_deformation.gd) est deja listee la ou l'entite est fabriquee (voir
# data/types.json:colon.deformation_sources). avancer()/biais() ne lisent
# QUE proprietes.deformation_etat -- jamais deformation_sources, elles ne
# s'occupent que de ce qui EST pose, jamais de ce qui POURRAIT l'etre.
#
# Le champ "sens" du catalogue (data/deformations.json) est porte ici
# mais NON LU par ce fichier -- il n'est applique au calcul de saillance
# qu'en piece 3 (le lecteur), voir cadrage.
#
# entite : Dictionary { id, position, proprietes }, mute en place par
#          poser()/avancer(). biais() ne mute jamais rien.
# source/cible : String, noms opaques -- ce fichier ne connait ni
#                "habituation", ni "trauma", ni "gravitique" : tout le
#                vocabulaire vit en donnee (data/deformations.json).
# catalogue : Dictionary source -> { taux_decroissance_rapide,
#             taux_decroissance_lent, w_rapide, w_lent, sens } --
#             data/deformations.json, jamais charge par ce fichier (meme
#             convention que extinction.gd/depense.gd/charge.gd/couplage.gd).
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# proprietes.deformation_etat ne porte jamais que des float dans ses
# feuilles -- aucun Vector3, aucun Callable. proprietes.deformation_sources
# ne porte jamais que des String.

static func poser(entite: Dictionary, source: String, cible: String, magnitude: float) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("deformation_sources"):
		push_error("deformation.gd : propriete structurelle 'deformation_sources' absente de proprietes")
		return
	if not proprietes.has("deformation_etat"):
		push_error("deformation.gd : propriete structurelle 'deformation_etat' absente de proprietes")
		return
	if not proprietes.deformation_sources.has(source):
		push_error("deformation.gd : source '%s' non declaree dans deformation_sources de l'entite '%s'" % [source, entite.get("id", "?")])
		return
	var deformation: Dictionary = proprietes.deformation_etat
	if not deformation.has(source):
		deformation[source] = {}
	if not deformation[source].has(cible):
		deformation[source][cible] = {"rapide": 0.0, "lent": 0.0}
	var canal: Dictionary = deformation[source][cible]
	canal["rapide"] = canal.get("rapide", 0.0) + magnitude
	canal["lent"] = canal.get("lent", 0.0) + magnitude

static func avancer(entite: Dictionary, delta: float, catalogue: Dictionary) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("deformation_etat"):
		push_error("deformation.gd : propriete structurelle 'deformation_etat' absente de proprietes")
		return
	var deformation: Dictionary = proprietes.deformation_etat
	for source in deformation:
		if not catalogue.has(source):
			push_error("deformation.gd : source '%s' absente du catalogue" % source)
			continue
		var regle: Dictionary = catalogue[source]
		var taux_rapide: float = regle.get("taux_decroissance_rapide", 0.0)
		var taux_lent: float = regle.get("taux_decroissance_lent", 0.0)
		for cible in deformation[source]:
			var canal: Dictionary = deformation[source][cible]
			canal["rapide"] = max(0.0, canal.get("rapide", 0.0) - taux_rapide * delta)
			canal["lent"] = max(0.0, canal.get("lent", 0.0) - taux_lent * delta)

static func biais(entite: Dictionary, source: String, cible: String, catalogue: Dictionary) -> float:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("deformation_etat"):
		push_error("deformation.gd : propriete structurelle 'deformation_etat' absente de proprietes")
		return 0.0
	var deformation: Dictionary = proprietes.deformation_etat
	if not deformation.has(source) or not deformation[source].has(cible):
		return 0.0
	if not catalogue.has(source):
		push_error("deformation.gd : source '%s' absente du catalogue" % source)
		return 0.0
	var canal: Dictionary = deformation[source][cible]
	var regle: Dictionary = catalogue[source]
	var w_rapide: float = regle.get("w_rapide", 0.0)
	var w_lent: float = regle.get("w_lent", 0.0)
	return w_rapide * canal.get("rapide", 0.0) + w_lent * canal.get("lent", 0.0)
