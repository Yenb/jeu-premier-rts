extends RefCounted

# Geste generique : TRANSFORMATION D'UN OBJET EN UN AUTRE, PAR RENDEMENT DE
# MASSE -- calcul PUR, aucune mutation, aucune connaissance de "monde" ni
# d'agents. Sert au chantier "transformation produit un objet neuf"
# (scripts/extinction.gd, a_zero.produire) : quand un chantier s'acheve,
# l'objet EXISTANT peut disparaitre et un objet NEUF apparaitre a sa place
# -- bois -> charbon, charbon -> cendre, minerai -> metal, aucun nom en
# dur ici.
#
# DOCTRINE (docs/design.md, "Modele objet" + objet.gd, DENSITE EFFECTIVE) :
# si la composition change, c'est un objet DIFFERENT -- jamais une
# mutation de type. La masse du nouvel objet n'est donc jamais posee a la
# main (masse/densite/volume sont des SORTIES derivees de la composition,
# interdit de les ecrire ailleurs qu'a la fabrication) : ce fichier
# construit une composition dont le VOLUME de chaque element est calcule
# pour que la masse resultante egale exactement rendement * masse_ancien,
# puis delegue TOUT le calcul de densite/volume/masse a Objet.fabriquer --
# jamais une seconde formule de densite ici. Generalise sans branche a N
# materiaux (chaque element du gabarit garde sa PROPORTION de volume) :
# pour un materiau seul, la proportion vaut 1.0 et la formule se reduit
# au cas simple.
#
# rendement_perdu n'existe pas comme champ : c'est le complement de
# rendement (1.0 - rendement), jamais stocke, jamais lu -- la masse
# perdue disparait simplement (elle n'est nulle part).
#
# Recoit :
# - proprietes_ancien (Dictionary) : proprietes de la chose qui disparait
#   -- ce fichier ne lit que "masse" dessus, jamais id/position.
# - config (Dictionary, data/transformations.json:
#   transformations.<cle>.a_zero.produire) : { type_produit: String
#   (reference vers table, verifiee par scripts/test_lint_donnees.gd),
#   rendement: float, patron_produit: Dictionary FACULTATIF (defaut {}) }.
#   patron_produit est fusionne TEL QUEL sur le nouvel objet apres sa
#   fabrication -- memes cles que data/transformations.json:patron
#   (travail_restant, transformation, profil_saillance, brule...) mais
#   AUCUN nom en dur ici : Dictionary opaque. Permet au produit de
#   repartir immediatement dans un nouveau chantier (charbon qui continue
#   de bruler) sans que ce fichier sache ce qu'est "bruler".
# - table (Dictionary) : catalogue de fabrication (data/types.json, DEJA
#   fusionne avec ses paquets "herite" -- meme table que recoit partout
#   ailleurs Objet.fabriquer).
# - materiaux (Dictionary) : data/materiaux.json, meme convention.
#
# Rend le Dictionary "proprietes" du nouvel objet (JAMAIS { id, position,
# proprietes } -- position/id restent la responsabilite de l'appelant, ce
# fichier ne les connait pas), ou {} (Dictionary vide) si rien ne doit
# etre produit :
# - rendement <= 0.0 : TOUT est perdu, rien ne se produit -- CHEMIN MORT
#   VOULU, jamais une alarme (voir "rendement_perdu" ci-dessus).
# - config incomplete (type_produit/rendement absents), type_produit
#   absent de table, type sans composition exploitable (volume total
#   nul), ou un materiau de la composition-gabarit absent de materiaux/
#   sans "densite" : ECHEC, push_error nommant la cause, rend {}.

const Objet = preload("res://scripts/objet.gd")

static func transformer(proprietes_ancien: Dictionary, config: Dictionary, table: Dictionary, materiaux: Dictionary) -> Dictionary:
	if not config.has("type_produit") or not config.has("rendement"):
		push_error("produit.gd : configuration 'produire' incomplete (type_produit/rendement requis)")
		return {}
	var rendement: float = config.rendement
	if rendement <= 0.0:
		return {}
	var type_produit: String = config.type_produit
	if not table.has(type_produit):
		push_error("produit.gd : type produit '%s' absent de la table de fabrication" % type_produit)
		return {}

	var gabarit: Dictionary = table[type_produit]
	var composition_gabarit: Array = gabarit.get("composition", [])
	var volume_gabarit_total := 0.0
	for element in composition_gabarit:
		volume_gabarit_total += float(element.get("volume", 0.0))
	if volume_gabarit_total <= 0.0:
		push_error("produit.gd : type produit '%s' sans composition exploitable (volume total nul)" % type_produit)
		return {}

	var masse_ancien: float = float(proprietes_ancien.get("masse", 0.0))
	var masse_produit: float = masse_ancien * rendement

	var nouvelle_composition: Array = []
	for element in composition_gabarit:
		var nom_materiau: String = element.get("materiau", "")
		var fiche: Dictionary = materiaux.get(nom_materiau, {})
		if not fiche.has("densite"):
			push_error("produit.gd : materiau '%s' (type produit '%s') absent de materiaux.json ou sans 'densite'" % [nom_materiau, type_produit])
			return {}
		var densite_kg_m3: float = float(fiche.densite) * Objet.G_CM3_VERS_KG_M3
		var proportion: float = float(element.get("volume", 0.0)) / volume_gabarit_total
		nouvelle_composition.append({
			"materiau": nom_materiau,
			"volume": (masse_produit * proportion) / densite_kg_m3,
		})

	var table_surchargee: Dictionary = table.duplicate(true)
	table_surchargee[type_produit] = gabarit.duplicate(true)
	table_surchargee[type_produit]["composition"] = nouvelle_composition

	var fabrique: Dictionary = Objet.fabriquer(type_produit, type_produit, Vector3.ZERO, table_surchargee, materiaux)
	if fabrique.is_empty():
		return {}

	var proprietes: Dictionary = fabrique.proprietes
	proprietes.merge(config.get("patron_produit", {}), true)
	return proprietes
