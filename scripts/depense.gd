extends RefCounted

# Modele generique de depense : une chose porte PLUSIEURS reserves nommees
# (energie, matiere...), chacune ponctionnee chaque pas par un cout de base
# (son etat le fixe) et un surcout (son action en cours le fixe), tous deux
# deja resolus en NOMBRES sur la chose -- ce fichier ne connait aucun nom
# d'action, aucun nom d'etat, aucun nom de reserve.
#
# NEUTRE PAR CONSTRUCTION, a exploiter et jamais a contourner : le calcul est
# reserve - (cout_base + surcout_action) * delta. Un cout NEGATIF fait donc
# REMONTER la reserve -- c'est ainsi qu'une jachere se refait, qu'un besoin
# monte, qu'un blesse recupere, sans une ligne de code neuve.
#
# BORNE BASSE SEULEMENT : "reserve" est bornee a 0.0 A LA SOUSTRACTION
# (max(0.0, ...)), jamais laissee descendre en negatif -- une reserve epuisee
# reste a 0.0 tant qu'aucun flux.gd ne la recharge. RIEN DANS LE COEUR NE
# BORNE LE HAUT : tout plafond est un geste de CABLAGE.
#   ECARTE, a ne pas reproposer tel quel : une reserve NON bornee, dont la
#   valeur negative mesurerait la profondeur du manque pour une remontee
#   proportionnelle. Aucun mecanisme ne lit cette profondeur, et le symptome
#   se voit -- des "reste" negatifs affiches apres extinction. Si le besoin
#   revient, il se reconcoit sur une mesure explicite (un compteur de temps
#   passe a zero), jamais sur une reserve laissee negative.
#
# UN SEUL EMPLACEMENT "surcout_action" PAR CANAL : deux morceaux de cablage
# qui y ecrivent chacun le leur se detruisent EN SILENCE, aucun test ne
# rougit. D'ou la discipline d'un ECRIVAIN UNIQUE, qui somme puis ecrit une
# seule fois.
#
# NE CONSULTE JAMAIS etat_effectif.gd : un etat qui pretendrait moduler une
# depense serait vrai en donnee et sans le moindre effet, EN SILENCE. Un
# cablage qui veut un cout effectif compose la valeur lui-meme avant d'ecrire.
#
# SEUILS EN ESCALIER, meme modele que extinction.gd (reference de catalogue) :
# un canal ne porte pas ses DEFINITIONS de seuils, il porte une reference
# ("seuils_ref", String) vers une entree du catalogue passe en parametre.
# L'instance ne porte que l'ETAT -- quels seuils, par indice dans l'entree
# resolue, ont deja ete franchis ("seuils_franchis"). Le catalogue n'est
# jamais mute : gain de RESUMABILITE (voir docs/design.md, "L'LLM : lecteur
# ancre"), pas seulement de memoire.
#   Un seuil ne s'applique JAMAIS deux fois. PIEGE : un cablage qui RECHARGE
#   une reserve doit vider "seuils_franchis" lui-meme, sinon ce seuil ne se
#   redeclenchera plus jamais.
#   Un seuil pose une CAUSE, jamais un resultat derivable -- la transformation
#   s'applique SUR proprietes, jamais sur le canal : une cause posee doit
#   rester lisible par n'importe quel lecteur qui scanne l'objet, pas enfouie
#   dans un sous-dictionnaire. Consequence : deux canaux peuvent poser chacun
#   la leur sans jamais s'ecraser.
#
# monde : Array de Dictionary { "id", "position", "proprietes" }, mute en
#         place -- chaque reserve decroit independamment des autres.
# delta : temps ecoule ce pas, en secondes.
# catalogue : Dictionary reference -> Array de { "seuil": float, "retirer":
#         Array de cles, "poser": Dictionary cle -> valeur }, en escalier.
#         FACULTATIF (defaut {}) : un appelant sans canal a seuils traverse.
#
# proprietes lues sur la chose :
#   - reserves (Dictionary FACULTATIF) : nom de reserve -> canal. Cle absente
#     ou Dictionary vide -> la chose est ignoree.
#   - un canal est un Dictionary { "reserve": float, "cout_base": float
#     (defaut 0.0), "surcout_action": float (defaut 0.0), "seuils_ref":
#     String FACULTATIVE (defaut "" -- une reserve sans seuils est legitime,
#     elle decroit seulement), "seuils_franchis": Array FACULTATIF d'indices
#     deja appliques (defaut []) }. "seuils_ref" presente mais absente du
#     catalogue est structurellement anormale (meme cas que "transformation"
#     dans extinction.gd) -- push_error, ce canal n'applique rien ce tick.
#
# FRONTIERE avec extinction.gd : ce fichier est INTERNE et sans portee, la
# chose se ponctionne elle-meme et personne d'autre n'intervient ;
# extinction.gd est une consommation par des AGENTS A DISTANCE, et son seuil
# est unique et cloturant la ou celui-ci est multiple et en escalier. Deux
# formes de decroissance, jamais la meme : l'une vient de ce qu'on EST,
# l'autre de ce qu'on SUBIT.
#
# Rend l'Array des id des choses ayant franchi au moins un seuil, sur au
# moins une reserve, ce pas de temps.
static func avancer(monde: Array, delta: float, catalogue: Dictionary = {}) -> Array:
	var franchis: Array = []
	for chose in monde:
		var proprietes: Dictionary = chose.proprietes
		var reserves: Dictionary = proprietes.get("reserves", {})
		if reserves.is_empty():
			continue
		var a_franchi := false
		for nom in reserves:
			if _avancer_canal(reserves[nom], proprietes, delta, catalogue):
				a_franchi = true
		if a_franchi:
			franchis.append(chose.id)
	return franchis

static func _avancer_canal(canal: Dictionary, proprietes: Dictionary, delta: float, catalogue: Dictionary) -> bool:
	var reserve: float = canal.get("reserve", 0.0)
	var cout_base: float = canal.get("cout_base", 0.0)
	var surcout: float = canal.get("surcout_action", 0.0)
	reserve = max(0.0, reserve - (cout_base + surcout) * delta)
	canal["reserve"] = reserve
	var ref: String = canal.get("seuils_ref", "")
	if ref == "":
		return false
	if not catalogue.has(ref):
		push_error("depense.gd : reference de seuils '%s' absente du catalogue" % ref)
		return false
	var definitions: Array = catalogue[ref]
	var franchis: Array = canal.get("seuils_franchis", [])
	var a_appliquer: Array = []
	for i in range(definitions.size()):
		if franchis.has(i):
			continue
		if reserve <= float(definitions[i].get("seuil", 0.0)):
			a_appliquer.append(i)
	if a_appliquer.is_empty():
		return false
	a_appliquer.sort_custom(func(a, b): return definitions[a].get("seuil", 0.0) > definitions[b].get("seuil", 0.0))
	for i in a_appliquer:
		_appliquer_seuil(proprietes, definitions[i])
		franchis.append(i)
	canal["seuils_franchis"] = franchis
	return true

# Ce qu'un seuil pose est COPIE, jamais assigne tel quel (CARTE.md §6,
# doctrine du meme nom).
static func _appliquer_seuil(proprietes: Dictionary, seuil: Dictionary) -> void:
	for cle in seuil.get("retirer", []):
		proprietes.erase(cle)
	var poser: Dictionary = seuil.get("poser", {})
	for cle in poser:
		var valeur = poser[cle]
		if valeur is Dictionary or valeur is Array:
			valeur = valeur.duplicate(true)
		proprietes[cle] = valeur
