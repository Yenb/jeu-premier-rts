extends RefCounted

# Mecanisme du coeur NEUF (chantier « composition en profondeur -- chainage
# automatique de reactions »). Detecte, PARMI TOUS les objets d'un monde a
# plat, les paires a portee de contact qui correspondent a une entree d'un
# catalogue de reactions, accumule un canal charge.gd dedie ("reaction") sur
# CHACUNE de ces paires, et transforme la CIBLE (via produit.gd:transformer)
# des que son canal franchit son seuil. Compose charge.gd/produit.gd/
# portee.gd deja fermes -- n'en reimplemente aucun.
#
# MODELE ASYMETRIQUE, DECISION YAEL (question posee avant d'ecrire, la
# consigne d'origine du chantier disait « transformer sur les deux
# reactifs », contredit par son propre exemple narratif -- « l'eau reste de
# l'eau ») : dans une entree { materiau_a, materiau_b, ... }, materiau_a est
# la SOURCE/le CATALYSEUR -- jamais transforme par ce fichier, il reste
# exactement lui-meme. materiau_b est la CIBLE -- seule transformee, via
# Produit.transformer, en type_produit. Meme convention de role que
# scripts/banc_reactivite.gd (acide = materiau_a jamais transforme par ce
# canal, cible = materiau_b transformee), generalisee ici a un catalogue
# entier plutot qu'a trois cibles fixes cablees a la main.
#
# CHAINAGE PAR LE TEMPS, PAS PAR UNE BOUCLE INTERNE : ce fichier ne se
# rappelle jamais lui-meme dans le meme appel. Toutes les paires sont
# DETECTEES d'abord (sur l'etat du monde AU DEBUT de cet appel), PUIS toutes
# les transformations retenues sont APPLIQUEES -- en deux passes disjointes,
# jamais entremelees -- pour qu'un objet transforme PENDANT cet appel ne soit
# JAMAIS relu comme reactif frais par un autre couple examine dans LE MEME
# appel (sinon une cascade a profondeur 2 se produirait en un seul tick,
# contrairement a la consigne : « la cascade emerge du passage du temps, pas
# d'une boucle interne »). Un produit ne redevient un reactif potentiel qu'au
# PROCHAIN appel (prochain tick du cablage appelant), une fois que le monde
# porte deja sa nouvelle composition.
#
# PROFONDEUR DE CHAINE, seule protection contre les boucles infinies
# (A+B->C, C+D->A, A+B->C...) : chaque objet porte _profondeur_chaine (int,
# defaut 0 -- absente = objet de base, jamais issu d'une reaction). Un objet
# dont _profondeur_chaine >= profondeur_max est EXCLU de la detection, qu'il
# joue le role de source OU de cible. Le produit d'une reaction recoit
# max(profondeur des sources ayant contribue, profondeur de la cible
# d'origine) + 1 -- jamais une valeur posee a la main.
#
# "reactivite" est traitee ici comme scripts/produit.gd traite "masse" :
# une grandeur physique STRUCTURELLE au mecanisme lui-meme (le sujet de ce
# fichier est litteralement la reactivite chimique), jamais un nom de
# contenu comme "fer"/"acide" -- aucun nom de materiau, de type ni de
# reaction n'apparait en dur, uniquement lu depuis catalogue_reactions et
# proprietes.composition (meme lecture mono-materiau que
# scripts/banc_reactivite.gd:materiau_de).
#
# Recoit :
# - monde (Array de Dictionary { id, position, proprietes }) : MUTE EN
#   PLACE, meme convention que charge.gd/depense.gd -- jamais un Monde
#   (scripts/monde.gd), qui indexe par id pour une requete spatiale
#   ponctuelle : ce mecanisme compare TOUTES les paires entre elles, un
#   Array plat suffit et reste le patron partage par les cinq/six
#   mecanismes deja fermes (aucune "boucle principale" n'existe sur
#   monde.gd : c'est le cablage du banc/jeu qui appelle ce fichier chaque
#   tick, meme responsabilite que pour charge.gd/depense.gd/consommer.gd).
# - catalogue_reactions (Array de Dictionary { materiau_a, materiau_b,
#   seuil_reactivite, type_produit, rendement, portee_reaction }) --
#   data/reactions.json:reactions. portee_reaction (float, facultative,
#   defaut 0.0) est la portee de CONTACT de cette paire -- initialise le
#   canal "reaction" a sa creation, jamais relue ensuite (le canal, une
#   fois cree, vit de sa propre portee_charge comme tout canal charge.gd).
# - delta (float) : temps ecoule ce pas, en secondes -- transmis tel quel a
#   Charge.avancer.
# - profondeur_max (int) : voir PROFONDEUR DE CHAINE ci-dessus.
#   profondeur_max <= 0 empeche toute reaction (tout objet de base est deja
#   a profondeur 0 >= 0).
# - table (Dictionary, data/types.json fusionne) / materiaux (Dictionary,
#   data/materiaux.json) : transmis tels quels a Produit.transformer,
#   jamais relus autrement ici.
#
# Rend un Array de Dictionary { id, type_produit, profondeur_chaine } -- une
# entree par transformation APPLIQUEE ce pas (jamais par paire simplement
# accumulee sous le seuil).
const Charge = preload("res://scripts/charge.gd")
const Produit = preload("res://scripts/produit.gd")

const _CANAL := "reaction"
const _MARQUEUR_PRET := "_reaction_prete"
const _PROFONDEUR := "_profondeur_chaine"

static func detecter_et_reagir(monde: Array, catalogue_reactions: Array, delta: float, profondeur_max: int, table: Dictionary, materiaux: Dictionary) -> Array:
	# PASSE 1 -- detection : lit l'etat du monde tel qu'il etait au debut de
	# cet appel, ne mute jamais monde.
	var candidats: Array = []
	for objet_b in monde:
		var profondeur_b: int = int(objet_b.proprietes.get(_PROFONDEUR, 0))
		if profondeur_b >= profondeur_max:
			continue
		var materiau_b: String = _materiau_de(objet_b)
		if materiau_b == "":
			continue

		var causes: Array = []
		var profondeur_source_max := 0
		var entree_retenue: Dictionary = {}
		for objet_a in monde:
			if objet_a.id == objet_b.id:
				continue
			var profondeur_a: int = int(objet_a.proprietes.get(_PROFONDEUR, 0))
			if profondeur_a >= profondeur_max:
				continue
			var materiau_a: String = _materiau_de(objet_a)
			if materiau_a == "":
				continue
			var entree := _trouver_reaction(catalogue_reactions, materiau_a, materiau_b)
			if entree.is_empty():
				continue
			entree_retenue = entree
			profondeur_source_max = max(profondeur_source_max, profondeur_a)
			causes.append({"position": objet_a.position, "poids": _score_reaction(objet_a.proprietes, objet_b.proprietes)})

		if causes.is_empty():
			continue
		candidats.append({
			"objet": objet_b,
			"causes": causes,
			"entree": entree_retenue,
			"profondeur_source_max": profondeur_source_max,
			"profondeur_b": profondeur_b,
		})

	# PASSE 2 -- application : accumule puis transforme, jamais relu par la
	# passe 1 (deja terminee).
	var transformations: Array = []
	for candidat in candidats:
		var objet_b: Dictionary = candidat.objet
		_assurer_canal(objet_b.proprietes, candidat.entree)
		Charge.avancer([objet_b], candidat.causes, delta)

		if not objet_b.proprietes.get(_MARQUEUR_PRET, false):
			continue

		var entree: Dictionary = candidat.entree
		var nouvelles: Dictionary = Produit.transformer(objet_b.proprietes, {"type_produit": entree.type_produit, "rendement": entree.rendement}, table, materiaux)
		if nouvelles.is_empty():
			continue
		var nouvelle_profondeur: int = max(candidat.profondeur_source_max, candidat.profondeur_b) + 1
		nouvelles[_PROFONDEUR] = nouvelle_profondeur
		# CONSTAT SYSTEMIQUE DEJA DOCUMENTE (audit_produit_nucleaire_prealable.md,
		# repris par scripts/banc_produit_nucleaire.gd pour force_radiation) :
		# produit.gd:transformer ne refusionne JAMAIS les proprietes immuables
		# de composition sur l'objet neuf -- sans cette ligne, un produit perd
		# sa reactivite et ne pourrait plus jamais reagir, rendant tout
		# chainage a plus d'un etage structurellement impossible. Repose ICI,
		# depuis la fiche materiau du produit LUI-MEME (jamais celle de
		# l'ancien objet) -- meme lecture que materiaux.json partout ailleurs.
		nouvelles["reactivite"] = float(materiaux.get(entree.type_produit, {}).get("reactivite", 0.0))
		objet_b.proprietes.clear()
		objet_b.proprietes.merge(nouvelles, true)
		transformations.append({"id": objet_b.id, "type_produit": entree.type_produit, "profondeur_chaine": nouvelle_profondeur})

	return transformations

# Lecture mono-materiau, meme convention que banc_reactivite.gd:materiau_de
# -- "" si l'objet n'a pas de composition exploitable.
static func _materiau_de(objet: Dictionary) -> String:
	var composition: Array = objet.get("proprietes", {}).get("composition", [])
	if composition.is_empty():
		return ""
	return String(composition[0].get("materiau", ""))

static func _trouver_reaction(catalogue: Array, materiau_a: String, materiau_b: String) -> Dictionary:
	for entree in catalogue:
		if entree.get("materiau_a", "") == materiau_a and entree.get("materiau_b", "") == materiau_b:
			return entree
	return {}

static func _score_reaction(proprietes_a: Dictionary, proprietes_b: Dictionary) -> float:
	return float(proprietes_a.get("reactivite", 0.0)) * float(proprietes_b.get("reactivite", 0.0))

# Cree le canal "reaction" UNE SEULE FOIS (ne touche jamais un canal deja
# present -- la charge accumulee doit survivre d'un appel a l'autre, meme
# discipline que tout canal charge.gd cree a la fabrication).
static func _assurer_canal(proprietes: Dictionary, entree: Dictionary) -> void:
	if not proprietes.has("etats"):
		proprietes["etats"] = {}
	var etats: Dictionary = proprietes["etats"]
	if not etats.has(_CANAL):
		etats[_CANAL] = {
			"charge": 0.0,
			"seuil": float(entree.get("seuil_reactivite", 0.0)),
			"portee_charge": float(entree.get("portee_reaction", 0.0)),
			"taux_decroissance": 0.0,
			"poser": {_MARQUEUR_PRET: true},
		}
