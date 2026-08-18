extends RefCounted

# Mecanisme du coeur : INTENSITE D'ETAT -- un etat pose sur un objet
# (proprietes.etats_actifs, voir etat_effectif.gd) porte une INTENSITE
# (proprietes.etats_intensite, float 0.0-1.0 -- PAS une simple presence).
# Ce fichier fait decroitre cette intensite avec le temps et RETIRE
# l'etat DE LUI-MEME quand elle atteint zero -- sans intervention
# manuelle, SANS TOUCHER etat_effectif.gd : voir COMMENT ETAT_EFFECTIF.GD
# CONSOMME L'INTENSITE plus bas, qui explique comment un fichier jamais
# modifie produit quand meme un effet proportionnel.
#
# EVOLUTION (chantier "un etat a une intensite qui decroit" -- remplace EN
# PLACE le premier chantier "un etat peut cesser", meme fichier, memes
# deux fonctions poser()/avancer(), stockage evolue, decision explicite de
# Yael) : l'ancien proprietes.etats_duree (temps restant en secondes,
# effet PLEIN jusqu'a l'instant du retrait, puis rien) est REMPLACE par
# proprietes.etats_intensite (0.0 a 1.0, effet PROPORTIONNEL en continu).
# "duree" (catalogue, data/etats.json) garde LE MEME NOM ET LE MEME SENS
# ("combien de secondes pour aller de 1.0 a 0.0") -- seul ce qui est
# STOCKE sur l'instance change, la donnee elle-meme ne bouge pas.
#
# COMMENT ETAT_EFFECTIF.GD CONSOMME L'INTENSITE, SANS Y ETRE MODIFIE :
# etat_effectif.gd:resoudre() lit un Dictionary "etats" RECU EN PARAMETRE,
# opaque -- il ignore d'ou il vient, aucune ligne n'y a change.
# etats_ponderes(chose, catalogue), plus bas, CONSTRUIT un Dictionary de
# la MEME FORME que le catalogue reel, mais dont chaque effet d'un etat
# actif ET suivi en intensite a deja ete PRE-MELANGE a la base (ecraser)
# ou a l'identite (moduler) selon l'intensite courante -- voir LES DEUX
# GESTES A INTENSITE ci-dessous. L'APPELANT (banc, test) passe CE
# Dictionary a EtatEffectif.valeur/resoudre() A LA PLACE du catalogue
# brut : la loi de resolution (ecraser gagne sur moduler, tri
# alphabetique en cas de conflit...) tourne alors EXACTEMENT comme avant,
# sans une ligne changee, sur des nombres deja ajustes. Un etat SANS
# intensite suivie (jamais dans etats_intensite -- pas de "duree"
# declaree) traverse etats_ponderes INCHANGE : ses effets restent ceux du
# catalogue tels quels, intensite implicite 1.0 permanente -- exactement
# le comportement d'avant ce chantier, aucune exception codee.
#
# LES DEUX GESTES A INTENSITE (decision assumee -- JAMAIS une seule
# formule generique pour les deux, ECRASER et MODULER n'ont pas la meme
# IDENTITE, c'est-a-dire pas le meme effet quand l'intensite tombe a
# zero) :
# - ECRASER a intensite i : valeur_effective = lerp(base_de_la_propriete_
#   visee, valeur_du_catalogue, i). A i=1.0, ecrasement plein (identique
#   a avant) ; a i=0.0, resultat = LA BASE, EXACTEMENT -- l'ecrasement
#   n'a plus aucun effet, comme si l'etat n'etait pas la. L'IDENTITE d'un
#   ecraseur epuise est donc LA BASE (une grandeur qui depend de la
#   chose), jamais un nombre fixe.
# - MODULER a intensite i : facteur_effectif = lerp(1.0, facteur_du_
#   catalogue, i). A i=1.0, facteur plein (identique a avant) ; a i=0.0,
#   facteur = 1.0 -- multiplier par 1.0 ne change rien. L'IDENTITE d'un
#   modulateur epuise est donc TOUJOURS 1.0 (une constante universelle),
#   jamais la base.
# Les deux sont bien PROPORTIONNELS a l'intensite, mais selon des formes
# DIFFERENTES, chacune vers SA PROPRE identite -- imposer la meme formule
# aux deux casserait l'ecraseur (rien ne garantirait un retour exact a la
# base quand l'etat s'eteint).
#
# Trois fonctions :
#
# poser(objet, nom_etat, catalogue) -> void : ajoute nom_etat a
# proprietes.etats_actifs (forme A, s'il n'y est pas deja). Si
# catalogue[nom_etat] porte "duree" (float, secondes POUR ALLER DE 1.0 A
# 0.0) : (RE)INITIALISE proprietes.etats_intensite[nom_etat] A 1.0 --
# REMISE A NEUF, JAMAIS UN CUMUL (decision assumee, voir REPOSE
# ci-dessous). Si catalogue[nom_etat] NE PORTE PAS "duree" : etats_actifs
# recoit quand meme le nom (l'etat est actif, intensite implicite 1.0
# permanente), mais etats_intensite n'est jamais touche pour ce nom --
# absence LEGITIME, jamais une alarme ("la rouille ne s'en va pas").
# CONSEQUENCE A NE PAS DECOUVRIR APRES COUP : un etat sans "duree" declaree
# n'entre JAMAIS dans le suivi d'intensite, donc avancer() ne le retirera
# JAMAIS -- son seul retrait possible est celui du cablage, a la main.
# nom_etat absent du catalogue ENTIER (reference cassee, pas juste "sans
# duree") : push_error nommant l'etat, rien n'est pose.
#
# avancer(monde, delta, catalogue) -> Array : POUR CHAQUE decroissance,
# CE FICHIER A DESORMAIS BESOIN DU CATALOGUE (difference avec la version
# precedente, qui ne stockait que des secondes brutes et n'en avait pas
# besoin) -- l'intensite etant une FRACTION de la duree totale, convertir
# un delta en secondes vers un delta d'intensite exige de connaitre cette
# duree totale, qui vient TOUJOURS du catalogue, jamais devinee ni
# stockee une seconde fois sur l'instance. Pour chaque chose de monde qui
# porte proprietes.etats_intensite (FACULTATIVE, meme statut que
# etats_actifs dans etat_effectif.gd -- chemin mort, aucune allocation si
# absente), decremente CHAQUE intensite de (delta / duree_de_cet_etat) ;
# une intensite qui atteint zero ou moins retire son nom d'etat
# d'etats_intensite ET d'etats_actifs -- c'est CE retrait, et lui seul,
# qui rend la propriete a sa valeur de base pour etat_effectif.gd. Un nom
# present dans etats_intensite mais dont le catalogue n'a plus de "duree"
# positive : push_error, cette entree seule est ignoree ce pas (jamais
# une division par zero, jamais une intensite figee en silence). Rend un
# Array de { id, nom_etat } pour chaque expiration survenue ce pas.
#
# etats_ponderes(chose, catalogue) -> Dictionary : voir COMMENT
# ETAT_EFFECTIF.GD CONSOMME L'INTENSITE ci-dessus. PURE, ne mute rien --
# construit et REND un Dictionary, jamais ecrit sur "chose".
#
# REPOSE (deux applications successives du meme etat sur le meme objet) :
# TRANCHE -- REMISE A 1.0, JAMAIS UN CUMUL. Rearroser un bois deja
# mouille le laisse a PLEINE humidite, pas "plus mouille que mouille" --
# un cumul (au-dela de 1.0, ou une prolongation de duree) ouvrirait un
# etat non borne si l'appelant pose en boucle (ex. exposition continue a
# la pluie). La regle NE DEPEND D'AUCUN ORDRE D'ITERATION DE DICTIONARY :
# poser() ecrit une seule cle, une seule fois, un ECRASEMENT DIRECT
# (proprietes.etats_intensite[nom_etat] = 1.0), jamais une somme ni une
# comparaison entre plusieurs entrees existantes.
#
# STRUCTUREL vs FACULTATIF : proprietes.etats_intensite est FACULTATIVE
# (comme etats_actifs dans etat_effectif.gd) -- sa cle absente dit juste
# "aucun etat de cet objet ne s'epuise", jamais une alarme. Chaque entree
# DE etats_intensite, elle, est traitee avec CONFIANCE une fois la cle
# presente (meme contrat qu'un element de proprietes.attaches dans
# attaches.gd).
#
# DECOUPAGE (pourquoi un futur "etat qui cesse par condition du monde" ne
# casse rien ici) : inchange depuis la version precedente -- ce fichier
# ne sait QUE decompter un delta, il ignore tout de la RAISON pour
# laquelle un etat a ete pose. Un futur mecanisme "condition du monde"
# (ex. un futur temperature.gd) retirerait un etat par le MEME geste
# qu'utilise deja etat_effectif.gd pour le LIRE : retirer le nom
# d'etats_actifs (et, s'il y figure, d'etats_intensite) -- il n'aurait
# besoin de rien connaitre de ce fichier, ni l'inverse. Les deux
# mecanismes resteraient completement independants, cote a cote.
#
# Recoit : objet/chose ({ id, position, proprietes }), nom_etat (String),
# catalogue (data/etats.json, ou tout catalogue au meme format -- jamais
# charge par ce fichier). Aucune des trois fonctions ne connait "mouille",
# "huile", ni aucune propriete de jeu.

static func poser(objet: Dictionary, nom_etat: String, catalogue: Dictionary) -> void:
	if not catalogue.has(nom_etat):
		push_error("etat_duree.gd : etat '%s' absent du catalogue" % nom_etat)
		return
	var proprietes: Dictionary = objet.get("proprietes", {})
	var actifs: Array = proprietes.get("etats_actifs", [])
	if not actifs.has(nom_etat):
		actifs.append(nom_etat)
	proprietes["etats_actifs"] = actifs

	var entree: Dictionary = catalogue[nom_etat]
	if entree.has("duree"):
		var intensites: Dictionary = proprietes.get("etats_intensite", {})
		intensites[nom_etat] = 1.0
		proprietes["etats_intensite"] = intensites

static func avancer(monde: Array, delta: float, catalogue: Dictionary) -> Array:
	var expirees: Array = []
	for chose in monde:
		var proprietes: Dictionary = chose.get("proprietes", {})
		if not proprietes.has("etats_intensite"):
			continue
		var intensites: Dictionary = proprietes.etats_intensite
		if intensites.is_empty():
			continue
		var a_retirer: Array = []
		for nom_etat in intensites:
			var duree_totale: float = float(catalogue.get(nom_etat, {}).get("duree", 0.0))
			if duree_totale <= 0.0:
				push_error("etat_duree.gd : etat '%s' present dans etats_intensite sans 'duree' positive au catalogue" % nom_etat)
				continue
			intensites[nom_etat] = intensites[nom_etat] - (delta / duree_totale)
			if intensites[nom_etat] <= 0.0:
				a_retirer.append(nom_etat)
		if a_retirer.is_empty():
			continue
		var actifs: Array = proprietes.get("etats_actifs", [])
		for nom_etat in a_retirer:
			intensites.erase(nom_etat)
			actifs.erase(nom_etat)
			expirees.append({"id": chose.get("id", ""), "nom_etat": nom_etat})
	return expirees

static func etats_ponderes(chose: Dictionary, catalogue: Dictionary) -> Dictionary:
	var proprietes: Dictionary = chose.get("proprietes", {})
	var intensites: Dictionary = proprietes.get("etats_intensite", {})
	var actifs: Array = proprietes.get("etats_actifs", [])
	var resultat: Dictionary = {}
	for nom_variant in actifs:
		var nom_etat: String = String(nom_variant)
		if not catalogue.has(nom_etat):
			continue
		var entree: Dictionary = catalogue[nom_etat]
		if not intensites.has(nom_etat):
			resultat[nom_etat] = entree
			continue
		var i: float = intensites[nom_etat]
		var effets_ajustes: Array = []
		for effet in entree.get("effets", []):
			var propriete: String = effet.get("propriete", "")
			var mode: String = effet.get("mode", "")
			if mode == "ecraser":
				var base: float = float(proprietes.get(propriete, 0.0))
				var valeur_cible: float = float(effet.get("valeur", 0.0))
				effets_ajustes.append({"propriete": propriete, "mode": "ecraser", "valeur": lerp(base, valeur_cible, i)})
			elif mode == "moduler":
				var facteur_cible: float = float(effet.get("facteur", 1.0))
				effets_ajustes.append({"propriete": propriete, "mode": "moduler", "facteur": lerp(1.0, facteur_cible, i)})
			else:
				effets_ajustes.append(effet)
		resultat[nom_etat] = {"effets": effets_ajustes}
	return resultat
