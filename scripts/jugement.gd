extends RefCounted

# Couche 2bis (saillance) : jugement -- valeur emergente d'une chose par sa
# rencontre avec une autre. Ne connait ni le feu ni l'abri : la valeur
# n'est jamais dans la chose seule, elle nait du RAPPORT entre une chose
# porteuse d'une propriete JUGEE et la pression exercee ailleurs dans la
# scene par une propriete DECLENCHEUR. Voir docs/design.md, "Jugement :
# troisieme source de saillance".
#
# Entree :
# - perceptions (Array de { chose, type, position, distance }, couche 1,
#   brute) -- sert a trouver les choses PERCUES portant la propriete
#   jugee, meme si elles n'ont aucune saillance propre (donc absentes de
#   resultats).
# - colon ({ proprietes: { forme } }).
# - resultats (Array issu de la couche 2 deja concatenee, attaches +
#   proximite -- { type, saillance, ... }, certaines entrees portant
#   "chose" -- origine proximite -- d'autres non -- origine attache, qui
#   n'a rien a tester et est ignoree, pas une alarme) -- sert a mesurer la
#   PRESSION exercee par le declencheur.
# - jugements (Dictionary issu de data/jugements.json, { propriete_jugee:
#   propriete_declencheur }, forme identique a menaces.json).
#
# forme est STRUCTURELLE (meme convention qu'attaches.gd) : absente de
# proprietes -- push_error puis retour []. gain_jugement (dans forme) est
# FACULTATIF, defaut 0.0 -- un colon qui ne le porte pas ne juge
# simplement rien (point neutre legitime du continu, meme statut qu'une
# saillance_intrinseque absente cote proximite.gd) : gain <= 0.0 -> [].
# plafond_jugement, lui, bascule STRUCTUREL des que gain_jugement est
# present et strictement positif -- CAS DU COUPLE (docs/design.md,
# "Propriete structurelle vs facultative") : un gain sans plafond ne
# retombe pas sur un etat neutre, il retombe sur une saillance NON
# BORNEE, plus forte que ce que le gain seul aurait du produire --
# push_error puis []. gain_jugement absent ou <= 0 rend la question du
# plafond sans objet, aucune alarme.
#
# PRESSION : pour chaque couple { jugee: declencheur } de la table, la
# somme des saillances de "resultats" portees par des choses PERCUES
# (entrees avec "chose") dont chose.proprietes porte le declencheur.
# Pression nulle -> la propriete jugee ne produit RIEN, jamais une entree
# a zero -- meme contrat que proximite.gd. Pression positive -> chaque
# chose PERCUE (perceptions, pas resultats : une chose jugee peut n'avoir
# aucune saillance propre) portant la propriete jugee rend une entree
# { chose, type, position, saillance }, saillance = pression *
# gain_jugement, plafonnee par plafond_jugement.
#
# AUCUNE DISTANCE n'entre dans ce calcul -- ni entre la chose jugee et le
# declencheur, ni au colon (decision de design, voir docs/design.md) : ce
# qui compte est la pression deja portee par resultats, jamais une
# position.
#
# LECTURE DE LA DEFORMATION DU COLON (PHASE 4bis chantier B, chantier
# "L'entite comme agent complet", voir docs/cadrage_phase4_deformation.md) --
# PATRON COPIE depuis proximite.gd piece 3 ("Lecture de la deformation du
# colon"). Apres le calcul de la PRESSION SOMMEE pour un declencheur donne,
# pour chaque (source, cible) que porte colon.proprietes.deformation_etat ET dont
# la cible EST CE DECLENCHEUR (cible == declencheur -- il n'y a pas de
# "chose" unique ici, seulement le nom de propriete qui a produit la
# pression) : Deformation.biais(colon, source, declencheur,
# catalogue_deformations) rend un facteur, applique MULTIPLICATIVEMENT --
# "baisse" (habituation) => pression *= (1.0 - biais) ; "monte" =>
# pression *= (1.0 + biais). Plusieurs sources se composent EN SEQUENCE,
# jamais additivement -- meme principe que "Lecture des calques :
# composition multiplicative" (docs/design.md).
#
# DECISION DOCTRINALE -- le biais s'applique a la PRESSION DEJA SOMMEE,
# JAMAIS a chaque saillance individuelle avant sommation : un colon habitue
# a "brule" voit sa pression TOTALE de refuge/abrite attenuee d'un coup,
# pas chaque feu individuellement (qui serait la lecture individuelle deja
# faite par proximite.gd, PHASE 4 piece 3) -- sinon le biais serait compte
# deux fois sur la meme exposition.
#
# colon.proprietes.deformation_etat est FACULTATIVE ICI (contrairement a
# deformation.gd, ou la meme cle est STRUCTURELLE) -- meme precedent que
# proximite.gd/agir.gd:_score (voir CARTE.md §2, agir.gd et proximite.gd) :
# son absence dit juste "aucune donnee de deformation disponible", pression
# rendue inchangee, jamais une alarme. catalogue_deformations
# (data/deformations.json) est FACULTATIF ici, defaut {} (meme convention
# que "catalogue" dans proximite.gd) -- ne casse pas un appelant qui ne
# fournit encore aucune deformation.
#
# Rend : Array de { chose, type, position, saillance }, meme forme que
# proximite.gd -- pour que la concatenation vers dominance.gd (att + prox
# + jugement) reste aveugle a l'origine d'un nombre.

const Deformation = preload("res://scripts/deformation.gd")

static func evaluer(
	perceptions: Array,
	colon: Dictionary,
	resultats: Array,
	jugements: Dictionary,
	catalogue_deformations: Dictionary = {},
) -> Array:
	var proprietes: Dictionary = colon.get("proprietes", {})
	if not proprietes.has("forme"):
		push_error("jugement.gd : propriete structurelle 'forme' absente de proprietes")
		return []
	var forme: Dictionary = proprietes.forme
	var gain: float = forme.get("gain_jugement", 0.0)
	if gain <= 0.0:
		return []
	if not forme.has("plafond_jugement"):
		push_error("jugement.gd : 'gain_jugement' present sans 'plafond_jugement' -- forme incoherente")
		return []
	var plafond: float = max(forme.plafond_jugement, 0.0)

	var sortie: Array = []
	for jugee in jugements:
		var declencheur = jugements[jugee]
		var pression := _pression(declencheur, resultats)
		if pression <= 0.0:
			continue
		pression = _appliquer_deformation(colon, declencheur, pression, catalogue_deformations)
		var saillance: float = clamp(pression * gain, 0.0, plafond)
		for instance in perceptions:
			if not instance.chose.proprietes.get(jugee, false):
				continue
			sortie.append({
				"chose": instance.chose,
				"type": instance.type,
				"position": instance.position,
				"saillance": saillance,
			})
	return sortie

static func _pression(declencheur: String, resultats: Array) -> float:
	var pression := 0.0
	for entree in resultats:
		if not entree.has("chose"):
			continue
		if entree.chose.proprietes.get(declencheur, false):
			pression += entree.saillance
	return pression

# Applique le biais de deformation du COLON (jamais de la chose) a la
# PRESSION DEJA SOMMEE pour ce declencheur -- voir en-tete du fichier,
# "DECISION DOCTRINALE". Meme patron que
# proximite.gd:_appliquer_deformation, adapte : la CIBLE comparee est le
# DECLENCHEUR de cette entree de jugements.json (un String), pas
# chose.proprietes.has(cible) -- il n'y a pas de "chose" unique ici,
# seulement le nom de la propriete qui a produit la pression. Ne mute rien
# (Deformation.biais est pure), rend juste le nombre module.
static func _appliquer_deformation(
	colon: Dictionary,
	declencheur: String,
	pression: float,
	catalogue_deformations: Dictionary,
) -> float:
	var deformation: Dictionary = colon.get("proprietes", {}).get("deformation_etat", {})
	for source in deformation:
		if not deformation[source].has(declencheur):
			continue
		var biais: float = Deformation.biais(colon, source, declencheur, catalogue_deformations)
		var sens: String = catalogue_deformations.get(source, {}).get("sens", "")
		if sens == "baisse":
			pression *= (1.0 - biais)
		elif sens == "monte":
			pression *= (1.0 + biais)
	return pression
