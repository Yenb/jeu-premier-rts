extends RefCounted

# Ciblage : traduit une decision deja prise (Agir.choisir) en la CHOSE que
# le colon doit VISER. Ce n'est pas une decision -- la decision est deja
# prise, la saillance deja choisie -- ceci ne fait que retrouver OU elle
# pointe, puisque attaches.gd/jugement.gd ne rendent qu'un nombre, jamais
# une position ni une identite (voir docs/design.md, "la saillance est une
# valeur, pas une appartenance").
#
# Entree :
# - decision (Dictionary rendue par Agir.choisir -- { ...visible, action:
#   cle }). Le champ "action" porte le VERBE retenu (cle resolue par
#   agir.gd:_verbe_par_poids, ou "" si aucun verbe strictement positif --
#   voir agir.gd), jamais un nom de type.
# - perceptions (Array de { chose, type, position, distance }, couche 1,
#   brute).
# - menaces (Dictionary issu de data/menaces.json, { propriete_
#   vulnerabilite: propriete_menace }) -- pour retrouver la chose qui
#   menace un trait, quand la decision vient de l'attache (attaches.gd ne
#   rend ni "chose" ni "position").
# - jugements (Dictionary issu de data/jugements.json, { propriete_jugee:
#   propriete_declencheur }) -- pour confirmer qu'une chose deja portee
#   par la decision (origine jugement.gd) est bien une chose JUGEE, jamais
#   pour la relocaliser : jugement.gd rend deja { chose, ... }, la chose
#   visee y est directement.
# - orientations (Dictionary issu de data/orientations.json, { verbe:
#   "jugee" }) -- dit, PAR VERBE, si ce verbe vise la chose JUGEE plutot
#   que le declencheur-menace. Un verbe absent de cette table (y compris
#   "", verbe non resolu) vise le declencheur PAR DEFAUT -- c'est le seul
#   comportement qui ait jamais existe, avant que le jugement n'existe :
#   defaut FACULTATIF, jamais une alarme, cette table ne fait que
#   documenter les exceptions.
#
# COMMENT LE FICHIER SAIT DANS QUEL CAS IL EST : jamais en lisant le nom
# d'un verbe en dur (categorie interdite par l'ADN) -- uniquement via
# orientations, une table de donnees. Ajouter un verbe qui vise la chose
# jugee est une ligne de donnee, zero ligne de code ici.
#
# Rend : la chose visee (Dictionary { id, position, proprietes }), ou null
# si aucune chose ne peut etre identifiee.

static func viser(
	decision: Dictionary,
	perceptions: Array,
	menaces: Dictionary,
	jugements: Dictionary,
	orientations: Dictionary,
) -> Variant:
	var verbe: String = decision.get("action", "")
	if orientations.get(verbe, "declencheur") == "jugee":
		return _chose_jugee(decision, jugements)
	return _chose_declencheur(decision, perceptions, menaces)

# Meme detection propriete-rencontre-propriete-menace en portee que
# attaches.gd:menace_attache -- reprise ici pour retrouver une CHOSE,
# jamais un nombre. Quand la decision porte deja "chose" (origine
# proximite : le declencheur EST la chose saillante percue), elle est
# directement visee -- pas de recherche. Quand la decision porte une
# "menace" positive (origine attache : la saillance ne porte ni chose ni
# position), on retrouve la chose qui menace le trait auquel le colon
# tient.
static func _chose_declencheur(
	decision: Dictionary,
	perceptions: Array,
	menaces: Dictionary,
) -> Variant:
	if decision.has("chose"):
		return decision.chose
	elif decision.get("menace", 0.0) > 0.0:
		return _plus_proche_par_menace(perceptions, decision.type, menaces)
	return null

static func _plus_proche_par_menace(
	perceptions: Array,
	propriete_attache: String,
	menaces: Dictionary,
) -> Variant:
	var meilleure_chose = null
	var meilleure_d := INF
	for instance in perceptions:
		if not instance.chose.proprietes.get(propriete_attache, false):
			continue
		for vuln in menaces:
			if not instance.chose.proprietes.get(vuln, false):
				continue
			var prop_menace = menaces[vuln]
			for autre in perceptions:
				if not autre.chose.proprietes.get(prop_menace, false):
					continue
				var d: float = instance.position.distance_to(autre.position)
				if d < meilleure_d:
					meilleure_d = d
					meilleure_chose = autre.chose
	return meilleure_chose

# jugement.gd rend deja { chose, type, position, saillance } -- la chose
# visee y est directement, jamais a relocaliser. "jugements" sert a
# CONFIRMER que la chose portee par la decision est bien une chose jugee
# (porte au moins une des proprietes-cles de la table), pas a la
# retrouver : une decision au verbe oriente "jugee" sans "chose", ou dont
# la chose ne porte aucune propriete jugee connue, est une incoherence de
# donnees (verbe et catalogue mal accordes) -- rend null plutot que de
# deviner.
static func _chose_jugee(decision: Dictionary, jugements: Dictionary) -> Variant:
	if not decision.has("chose"):
		return null
	var chose: Dictionary = decision.chose
	for propriete_jugee in jugements:
		if chose.proprietes.get(propriete_jugee, false):
			return chose
	return null
