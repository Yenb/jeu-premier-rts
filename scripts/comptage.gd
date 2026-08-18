extends RefCounted

# Mecanisme du coeur : COMPTAGE -- premiere brique de la couche LECTEUR
# (voir docs/design.md, "Les collectifs n'existent pas -- un resume lu,
# pas un objet pose"). Aucun objet-groupe : ce fichier compte, sur une
# liste DEJA CONSTRUITE par l'appelant, combien d'entites satisfont une
# regle exprimee en donnee. Ne connait aucun mot du monde (ni colon, ni
# faction, ni region, ni position) -- l'appelant filtre par espace ou par
# tout autre critere AVANT d'appeler ce mecanisme, en construisant
# lui-meme la liste `entites`.
#
# TROISIEME PATRON DE PORTEE : ni le monde entier scanne (propagation.gd/
# charge.gd), ni un rayon autour d'un point (perception.gd), mais une
# liste DEJA SELECTIONNEE, recue en parametre. Ce fichier ne sait pas d'ou
# elle vient ni comment elle a ete filtree dans l'espace -- c'est ce qui
# permet a UNE regle de servir deux questions differentes.
#
# entites : Array de Dictionary. Chaque element attendu porte au moins la
#           cle "proprietes" (Dictionary) -- un element qui ne la porte
#           pas est ignore silencieusement (Array sale legitime,
#           l'appelant filtre s'il veut ; ce n'est pas un contrat sur la
#           forme globale de "entites", juste une garde contre un element
#           mal forme).
# regle_id : String, reference vers une entree de `catalogue` --
#            STRUCTURELLE (voir docs/design.md, "Propriete du monde vs
#            champ de configuration technique") : absente du catalogue,
#            push_error nommant regle_id, retour 0 -- repli sur, jamais
#            un defaut silencieux qui ferait passer une regle inconnue
#            pour un compte a zero legitime.
# catalogue : Dictionary regle_id -> { propriete, mode, valeur_reference,
#             champ_element } -- data/comptages.json, jamais charge par ce
#             fichier (meme convention que deformation.gd/
#             lien_personnel.gd/extinction.gd). "propriete" nomme la cle
#             testee sur entite.proprietes ; "mode" est un parmi
#             "presente"/"egale"/"superieur_a"/"contient_element_avec_champ"
#             (voir plus bas) ; "valeur_reference" est requise pour
#             "egale"/"superieur_a"/"contient_element_avec_champ", ignoree
#             pour "presente" ; "champ_element" n'est requis que pour
#             "contient_element_avec_champ".
#
# Quatre modes, pas plus (V1) :
# - presente : compte si entite.proprietes.has(propriete), quelle que
#   soit la valeur (meme false, meme null, meme 0) -- test de PRESENCE de
#   cle, jamais une comparaison de valeur (voir docs/design.md,
#   "Propriete structurelle vs facultative" -- .has() avant .get()).
# - egale : compte si entite.proprietes[propriete] == valeur_reference.
#   Absence de la cle = ne compte pas, jamais une alarme (une propriete
#   facultative absente est un fait legitime).
# - superieur_a : compte si entite.proprietes[propriete] > valeur_reference.
#   Absence de la cle = ne compte pas. Valeur presente mais non numerique
#   (String, bool...) : push_error nommant l'entite et la propriete,
#   cette entite seule est ignoree, le comptage continue sur les autres.
# - contient_element_avec_champ : entite.proprietes[propriete] doit etre
#   un Array ; compte si CET Array contient au moins un Dictionary dont
#   [champ_element] == valeur_reference. Generalisation de "egale" a un
#   champ niche dans un element d'Array (ex. proprietes.attaches, Array de
#   { propriete, force } -- compter les entites dont au moins une attache
#   vise un trait donne). Absence de la cle propriete = ne compte pas,
#   meme contrat que egale/superieur_a. Valeur presente mais non Array :
#   push_error nommant l'entite et la propriete, entite ignoree. Un
#   element de l'Array qui ne porte pas champ_element est simplement
#   ignore (ne matche pas), aucune alarme -- meme statut qu'une propriete
#   facultative absente sur un Dictionary ordinaire.
#
# LIMITE : "valeur_reference" vit dans le CATALOGUE, elle est donc
# STATIQUE. Compter par rapport a une grandeur qui varie PAR CIBLE
# exigerait une entree de catalogue par cible -- ce mecanisme ne sait pas
# le faire, et un appelant qui en a besoin construit lui-meme sa liste.
#
# Ne fait pas : aucune notion d'espace (region, portee, position) ; ne
# mute jamais `entites` ni `catalogue` ; ne rend jamais la LISTE des
# entites qui satisfont la regle, seulement leur NOMBRE. Ne cable aucun
# banc -- ce mecanisme reste une brique, le cablage vit dans les bancs
# qui l'appellent.

static func compter(entites: Array, regle_id: String, catalogue: Dictionary) -> int:
	if not catalogue.has(regle_id):
		push_error("comptage.gd : regle_id '%s' absente du catalogue" % regle_id)
		return 0
	var regle: Dictionary = catalogue[regle_id]
	var propriete: String = regle.get("propriete", "")
	var mode: String = regle.get("mode", "")

	var compte := 0
	for entite in entites:
		if not (entite is Dictionary) or not entite.has("proprietes"):
			continue
		if _satisfait(entite, entite.proprietes, propriete, mode, regle):
			compte += 1
	return compte

# Juge une seule entite contre une regle deja resolue. "entite" n'est lue
# ici que pour nommer la source d'une alarme (valeur non numerique/non
# Array selon le mode) -- aucune autre lecture que "proprietes", deja
# extraite par l'appelant. "regle" est passee entiere (pas seulement
# valeur_reference) : contient_element_avec_champ a besoin en plus de
# champ_element, superieur_a/egale ne lisent que valeur_reference.
static func _satisfait(entite: Dictionary, proprietes: Dictionary, propriete: String, mode: String, regle: Dictionary) -> bool:
	var valeur_reference = regle.get("valeur_reference")
	match mode:
		"presente":
			return proprietes.has(propriete)
		"egale":
			return proprietes.has(propriete) and proprietes[propriete] == valeur_reference
		"superieur_a":
			if not proprietes.has(propriete):
				return false
			var valeur = proprietes[propriete]
			if not (valeur is float or valeur is int):
				push_error("comptage.gd : entite '%s' porte '%s' = %s (non numerique), mode superieur_a ignore cette entite" %
					[entite.get("id", "?"), propriete, str(valeur)])
				return false
			return valeur > valeur_reference
		"contient_element_avec_champ":
			if not proprietes.has(propriete):
				return false
			var valeur = proprietes[propriete]
			if not (valeur is Array):
				push_error("comptage.gd : entite '%s' porte '%s' = %s (non Array), mode contient_element_avec_champ ignore cette entite" %
					[entite.get("id", "?"), propriete, str(valeur)])
				return false
			var champ_element: String = regle.get("champ_element", "")
			for element in valeur:
				if element is Dictionary and element.get(champ_element, null) == valeur_reference:
					return true
			return false
		_:
			push_error("comptage.gd : mode '%s' inconnu" % mode)
			return false
