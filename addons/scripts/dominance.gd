extends RefCounted

# Couche 3 : dominance. Ne trie pas, ecrase.
#
# resultats : Array de { ..., saillance: float } -- la CONCATENATION
#         att + prox (Attaches.evaluer() + Proximite.evaluer()), jamais
#         Attaches.evaluer() seul : ce fichier ne sait pas d'ou vient
#         chaque entree, il ne lit que "saillance".
# colon : Dictionary, seul champ lu : proprietes.forme.seuil_ecrasement.
#         forme est STRUCTURELLE (sa cle absente de proprietes -> push_error
#         + retour neutre [], jamais un defaut silencieux) ; seuil_ecrasement
#         en son sein reste FACULTATIF (defaut INF si absent -- rien n'est
#         ecrase).
#
# La saillance la plus haute est la reference. Tout ce qui est en
# dessous d'un ecart trop grand devient INVISIBLE, pas "moins
# prioritaire" : ce n'est meme plus dans la liste rendue.
#
# Le seuil d'ecrasement vient de la forme du colon, comme le rayon
# de liaison. Aucun type en dur : le moteur ne compare que des
# nombres (saillance, ecart, seuil).
#
# Rend l'Array des entrees de resultats dont l'ecart au sommet est <= seuil.

static func visibles(resultats: Array, colon: Dictionary) -> Array:
	if resultats.is_empty():
		return []
	var proprietes: Dictionary = colon.get("proprietes", {})
	if not proprietes.has("forme"):
		push_error("dominance.gd : propriete structurelle 'forme' absente de proprietes")
		return []
	var forme: Dictionary = proprietes.forme
	var seuil: float = forme.get("seuil_ecrasement", INF)
	var sommet := -INF
	for r in resultats:
		sommet = max(sommet, r.saillance)
	var vus: Array = []
	for r in resultats:
		var ecart: float = sommet - r.saillance
		if ecart <= seuil:
			vus.append(r)
	return vus
