extends RefCounted

const Portee = preload("res://scripts/portee.gd")
const Produit = preload("res://scripts/produit.gd")

# Modele de transformation generique : une chose qui porte un chantier
# (travail_restant, sur l'instance, et "transformation" -- String, une
# reference vers une entree du catalogue transformations) est mangee par
# les agents a portee jusqu'a zero, puis change de proprietes selon
# l'entree resolue (a_zero, en donnee). Sert aussi bien a eteindre un feu
# qu'a miner un rocher ou couper du bois -- ce fichier ne connait aucun
# nom de chose, aucune menace, aucun decl_feu.
#
# monde : Array de Dictionary { "id", "position", "proprietes" }, mute en
#         place : travail_restant decroit ; "travail_restant" et
#         "transformation" sont retires quand le chantier s'accomplit.
# agents : Array de Dictionary avec au moins "position" ; "rythme" facultatif
#          (defaut 1.0), la vitesse a laquelle cet agent mange le chantier.
# delta : temps ecoule ce pas, en secondes.
# transformations : catalogue (data/transformations.json, entree
#          "transformations") -- cle -> { portee_travail, a_zero
#          facultatif }. Une chose ne porte plus portee_travail/a_zero
#          directement : elle porte SEULEMENT "transformation", une
#          reference vers une entree de ce catalogue. Ce partage n'est PAS
#          un gain memoire (a_zero etait deja partage par reference entre
#          toutes les choses issues du meme patron avant ce changement,
#          voir docs/prototypes.md) : c'est un gain de RESUMABILITE (voir
#          docs/design.md, "L'LLM : lecteur ancre") -- lire proprietes sur
#          une chose en chantier affiche un mot, pas un Dictionary
#          imbrique.
#
# "transformation" est STRUCTURELLE des qu'une chose a travail_restant >
# 0.0 : une chose en chantier sans cette cle, ou dont la reference ne
# resout dans aucune entree de transformations, ou dont l'entree resolue
# ne porte pas "portee_travail", alerte (push_error) et n'accomplit rien
# ce tick -- jamais un defaut silencieux sur portee_travail (0.0 se
# confondrait avec "personne a portee").
#
# PERTE DE GRANULARITE, ASSUMEE : avant ce changement, un type pouvait
# surcharger portee_travail SEUL en gardant le a_zero du patron (surcharge
# cle par cle, voir propagation.gd). Une reference de catalogue ne permet
# plus qu'une surcharge PAR ENTREE ENTIERE -- un type qui veut son propre
# portee_travail doit referencer (ou definir) toute une entree
# "transformation". Verifie sur data/types.json au moment de ce
# changement : aucun type n'exerce cette granularite (seul "feu"
# surcharge saillance_intrinseque/portee_saillance, hors de ce
# mecanisme). Contrainte future, pas une regression actuelle.
#
# a_zero : Dictionary facultative DANS l'entree resolue de transformations,
#          appliquee une seule fois quand travail_restant atteint zero :
#          "retirer" (Array de cles a effacer de proprietes) et/ou "poser"
#          (Dictionary cle -> valeur a ajouter a proprietes). Les deux
#          facultatifs. "portee_travail", lui, est OBLIGATOIRE dans
#          l'entree resolue -- son absence alerte (push_error), jamais un
#          defaut 0.0 substitue en silence.
#
# a_zero.produire (chantier "transformation produit un objet neuf",
#          FACULTATIF) : { type_produit, rendement, patron_produit
#          facultatif } -- voir scripts/produit.gd pour le calcul complet
#          (rendement de masse, jamais de volume). Quand present ET que
#          l'appelant fournit table/materiaux (voir avancer() ci-dessous),
#          REMPLACE entierement retirer/poser pour cette entree -- les
#          deux n'ont plus de sens sur un objet qui va disparaitre. table
#          vide (comportement par defaut, tout appelant ecrit avant ce
#          chantier) : produire est IGNORE, push_error signalant l'oubli,
#          repli sur retirer/poser (aucun effet si absents -- meme fin
#          qu'une transformation normale, travail_restant/transformation
#          simplement retires).
#
# Frontiere avec depense.gd : ce fichier ne ponctionne jamais une chose
# toute seule -- il faut des agents A PORTEE (consommation par distance).
# Une chose qui se consomme elle-meme, sans agent, c'est depense.gd
# (decroissance interne, sans portee).
#
# Le test "a portee" delegue a scripts/portee.gd:en_portee -- seule part
# partagee avec attaches.gd/propagation.gd/flux.gd/charge.gd (voir
# docs/design.md "Direction majeure" : la fusion des cinq mecanismes est
# ABANDONNEE, ce fichier garde sa propre boucle et sa propre reference de
# catalogue pour la portee).
#
# Rend l'Array des id des choses dont le chantier s'est accompli ce pas de
# temps.
static func avancer(
	monde: Array,
	agents: Array,
	delta: float,
	transformations: Dictionary = {},
	table: Dictionary = {},
	materiaux: Dictionary = {},
) -> Array:
	var accomplis: Array = []
	for chose in monde:
		var proprietes: Dictionary = chose.proprietes
		var restant: float = proprietes.get("travail_restant", 0.0)
		if restant <= 0.0:
			continue
		if not proprietes.has("transformation"):
			push_error("extinction.gd : chose '%s' porte travail_restant sans 'transformation'" % chose.id)
			continue
		var cle: String = proprietes.transformation
		if not transformations.has(cle):
			push_error("extinction.gd : transformation '%s' absente du catalogue (chose '%s')" % [cle, chose.id])
			continue
		var transfo: Dictionary = transformations[cle]
		if not transfo.has("portee_travail"):
			push_error("extinction.gd : transformation '%s' sans 'portee_travail' (chose '%s')" % [cle, chose.id])
			continue
		var portee: float = transfo.portee_travail
		var somme := 0.0
		for agent in agents:
			if Portee.en_portee(chose.position, agent.position, portee):
				somme += agent.get("rythme", 1.0)
		if somme <= 0.0:
			continue
		restant -= somme * delta
		proprietes["travail_restant"] = restant
		if restant <= 0.0:
			_appliquer_a_zero(proprietes, transfo, table, materiaux)
			accomplis.append(chose.id)
	return accomplis

static func _appliquer_a_zero(proprietes: Dictionary, transfo: Dictionary, table: Dictionary = {}, materiaux: Dictionary = {}) -> void:
	var a_zero: Dictionary = transfo.get("a_zero", {})
	var produire: Dictionary = a_zero.get("produire", {})
	if not produire.is_empty():
		if table.is_empty():
			push_error("extinction.gd : transformation avec 'produire' mais aucune table de fabrication fournie a avancer() -- rien ne sera produit")
		else:
			var nouvelles_proprietes: Dictionary = Produit.transformer(proprietes, produire, table, materiaux)
			proprietes.clear()
			proprietes.merge(nouvelles_proprietes, true)
			return
	for cle in a_zero.get("retirer", []):
		proprietes.erase(cle)
	# Ce qu'a_zero pose est COPIE, jamais assigne tel quel (CARTE.md §6,
	# doctrine du meme nom).
	var poser: Dictionary = a_zero.get("poser", {})
	for cle in poser:
		var valeur = poser[cle]
		if valeur is Dictionary or valeur is Array:
			valeur = valeur.duplicate(true)
		proprietes[cle] = valeur
	proprietes.erase("travail_restant")
	proprietes.erase("transformation")
