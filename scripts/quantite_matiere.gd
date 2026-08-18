extends RefCounted

# Geste generique : QUANTITE D'UNE PROPRIETE MATERIAU, SOMMEE SUR UNE
# COMPOSITION, PONDEREE PAR VOLUME -- calcul PUR, aucune mutation.
#
# EXTRACTION (chantier "feu -- la reserve de combustible suit la
# matiere"), PAS UNE REECRITURE : scripts/champ.gd:_quantite_matiere
# implemente deja EXACTEMENT ce geste (quantite de matiere magnetique),
# en prive, depuis le chantier champ.gd/banc_champ. champ.gd N'EST PAS
# TOUCHE par ce chantier (liste d'exclusion explicite) -- sa propre copie
# PRIVEE reste en place, INCHANGEE, DUPLIQUEE avec ce fichier. C'est une
# DETTE CONNUE, signalee ici et dans CARTE.md §6, PAS corrigee : migrer
# champ.gd vers cette fonction partagee toucherait champ.gd, hors
# perimetre de ce chantier. Ce fichier existe pour que le DEUXIEME
# consommateur (scripts/objet.gd, chantier combustible) n'ecrive pas une
# TROISIEME copie independante de la meme formule -- "ne reecris pas ce
# geste, reutilise-le ou extrais-le" (consigne du chantier).
#
# INTENSIVE vs EXTENSIVE (meme distinction que champ.gd et objet.gd) :
# une propriete comme la densite est INTENSIVE (la meme partout dans
# l'objet, une MOYENNE ponderee par volume la resout -- voir
# objet.gd:_calculer_densite_effective/_fusionner_proprietes_immuables).
# Une quantite de matiere (magnetisme total, combustible total...) est
# EXTENSIVE : un objet deux fois plus gros du meme materiau en contient
# deux fois plus. Ce fichier calcule TOUJOURS une SOMME, jamais une
# moyenne -- l'inverse du patron d'objet.gd pour les proprietes
# immuables.
#
# quantite(proprietes, propriete_materiau, materiaux) -> float :
# - proprietes SANS "composition" : 0.0, CHEMIN MORT (une chose hors du
#   domaine de la matiere n'est ni source ni contributrice -- meme
#   convention que charge.gd sur "etats" absent).
# - pour CHAQUE element { materiau, volume } de "composition" : "materiau"
#   est une REFERENCE STRUCTURELLE (meme doctrine que
#   proximite.gd:profil_saillance) -- absente de "materiaux", push_error
#   nommant le materiau, cet element contribue 0.0 et le calcul continue
#   pour les autres. La fiche resolue peut NE PAS porter
#   "propriete_materiau" -- FACULTATIF, 0.0, une des ~45 proprietes "a la
#   demande" de materiaux.json peut legitimement manquer (voir
#   docs/design.md, materiaux.json:_note, "RESERVE").
# - QUANTITE = somme, sur chaque element, de (valeur_resolue * volume_i) --
#   jamais divisee par le volume total. Aucune branche mono/multi-
#   materiaux, un seul element est le cas a un terme.
#
# Recoit : proprietes (Dictionary d'une chose -- jamais la chose entiere,
# ce fichier ne connait ni id ni position), propriete_materiau (String,
# nom du champ a lire sur chaque fiche materiau -- jamais en dur ici),
# materiaux (Dictionary reference -> fiche, data/materiaux.json, jamais
# charge par ce fichier). Rend un float >= 0.0 si les valeurs sources le
# sont (ce fichier ne borne rien lui-meme, il ne fait que sommer).

static func quantite(proprietes: Dictionary, propriete_materiau: String, materiaux: Dictionary) -> float:
	if not proprietes.has("composition"):
		return 0.0
	var total := 0.0
	for element in proprietes.composition:
		var nom_materiau: String = element.get("materiau", "")
		var volume: float = element.get("volume", 0.0)
		if not materiaux.has(nom_materiau):
			push_error("quantite_matiere.gd : materiau '%s' absent de materiaux.json" % nom_materiau)
			continue
		var fiche: Dictionary = materiaux[nom_materiau]
		var valeur: float = fiche.get(propriete_materiau, 0.0)
		total += valeur * volume
	return total
