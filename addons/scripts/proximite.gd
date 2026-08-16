extends RefCounted

# Couche 2 : saillance de proximite. Plancher commun a tous les colons —
# ne passe par aucune attache, ne connait aucune forme, aucun colon n'y
# est aveugle.
#
# Une chose peut etre saillante EN SOI (le feu), independamment de toute
# menace sur une attache. Meme modele que extinction.gd/depense.gd
# (reference de catalogue, jamais une copie par valeur) : une chose ne
# porte plus saillance_intrinseque/portee_saillance directement -- elle
# porte "profil_saillance" (String), une reference vers une entree du
# catalogue recu en parametre (data/profils_saillance.json). Gain de
# RESUMABILITE (voir docs/design.md, "L'LLM : lecteur ancre") : lire
# proprietes sur une chose saillante affiche un mot, pas deux nombres
# recopies sur chaque instance du meme profil.
#
# LECTURE DE LA DEFORMATION DU COLON (PHASE 4 piece 3, chantier "L'entite
# comme agent complet", voir docs/cadrage_phase4_deformation.md) -- PREMIER
# LECTEUR de scripts/deformation.gd, PATRON A COPIER par attaches.gd/
# jugement.gd dans une phase ulterieure (memes sources de saillance, meme
# lecture, pas fait ici). Apres le calcul de la saillance NUE (poids *
# facteur * avancement), pour chaque (source, cible) que porte
# colon.proprietes.deformation_etat ET que la chose evaluee porte reellement
# (chose.proprietes.has(cible)) : Deformation.biais(colon, source, cible,
# catalogue_deformations) rend un facteur, applique MULTIPLICATIVEMENT --
# "baisse" (habituation) => saillance *= (1.0 - biais) ; "monte" =>
# saillance *= (1.0 + biais). Plusieurs sources se composent EN SEQUENCE
# (chaque facteur multiplie la saillance deja modulee par le precedent),
# jamais additivement -- meme principe que "Lecture des calques :
# composition multiplicative" (docs/design.md).
#
# colon.proprietes.deformation_etat est FACULTATIVE ICI (contrairement a
# deformation.gd, ou la meme cle est STRUCTURELLE) -- deux fichiers, deux
# contrats, meme precedent que colon.proprietes.engagement (STRUCTURELLE
# dans couplage.gd, FACULTATIVE dans agir.gd:_score, voir CARTE.md §2
# agir.gd) : son absence dit juste "aucune donnee de deformation
# disponible pour ce colon", saillance rendue inchangee, jamais une
# alarme. L'alarme sur une SOURCE presente mais absente du catalogue reste
# celle deja posee par Deformation.biais (piece 1) -- rien a dupliquer ici.
#
# "profil_saillance" est FACULTATIVE (son absence dit juste "cette chose
# n'est pas saillante en soi", un point neutre legitime -- l'arbre). Des
# qu'elle est presente, sa resolution devient STRUCTURELLE : une reference
# absente du catalogue alarme (push_error) et exclut l'entree, jamais un
# silence. Une fois l'entree resolue, meme CAS DU COUPLE qu'avant :
# saillance_intrinseque > 0 declare l'entree saillante, portee_saillance
# la borne et devient STRUCTURELLE a son tour -- sa cle absente ne
# retombe pas sur une portee infinie, elle alarme et exclut l'entree.
# Une portee_saillance PRESENTE a 0.0 (ou moins) reste une intention
# explicite, pas un oubli : saillance nulle, sans alarme.
#
# La distance utilisee est celle deja calculee par la perception (couche
# 1, colon -> chose) : la seule distance AU COLON autorisee dans tout le
# moteur de saillance. Jamais une distance entre deux choses ici — ca,
# c'est le travail des attaches (liaison en espace, option B).
#
# catalogue : Dictionary reference -> { saillance_intrinseque, portee_saillance }
#         (data/profils_saillance.json). Facultatif (defaut {}) pour ne
#         pas casser un appelant qui ne fournit encore aucune chose saillante.
#
# PONDERATION PAR AVANCEMENT (travail_restant/travail_initial) : un chantier
# presque fini pese moins qu'un chantier frais -- pas d'exception codee.
# REMPLACE l'ancien mecanisme "facteur_occupation" (comptage d'agents a
# portee/en route, voir CARTE.md §6) : celui-la oscillait -- un colon
# comptait comme son propre occupant des qu'il avait decide une fois,
# gain_inertie (additif) ne pouvant pas compenser une auto-penalisation
# multiplicative. Celui-ci ne peut PAS osciller par construction : rien ici
# ne depend d'une DECISION de colon (aucun agent lu, aucune liste recue),
# seulement d'un TRAVAIL deja accompli. Quand une chose porte
# "travail_restant" ET "travail_initial" > 0 (les deux poses ENSEMBLE par
# le patron a l'allumage, voir data/transformations.json -- travail_initial
# ne bouge JAMAIS, c'est la reference immuable ; travail_restant descend,
# seul extinction.gd le mute, jamais Proximite.evaluer), la saillance est
# multipliee par (travail_restant / travail_initial) -- 1.0 pour un
# chantier frais, proche de 0.0 pour un chantier presque fini. Une chose
# SANS chantier (l'une des deux cles absente, ou travail_initial <= 0.0)
# garde sa saillance INCHANGEE -- point neutre legitime, aucune alarme :
# ce ne sont pas des references de catalogue a resoudre, juste deux
# nombres a comparer sur l'instance, rien a valider structurellement.

const Deformation = preload("res://scripts/deformation.gd")

static func evaluer(
	perceptions: Array,
	colon: Dictionary,
	catalogue: Dictionary = {},
	catalogue_deformations: Dictionary = {},
) -> Array:
	var resultats: Array = []
	for instance in perceptions:
		var proprietes: Dictionary = instance.chose.proprietes
		var ref: String = proprietes.get("profil_saillance", "")
		if ref == "":
			continue
		if not catalogue.has(ref):
			push_error("proximite.gd: chose '%s' reference un profil_saillance '%s' absent du catalogue" % [instance.chose.get("id", "?"), ref])
			continue
		var profil: Dictionary = catalogue[ref]
		var poids: float = profil.get("saillance_intrinseque", 0.0)
		if poids <= 0.0:
			continue
		if not profil.has("portee_saillance"):
			push_error("proximite.gd: profil_saillance '%s' porte saillance_intrinseque sans portee_saillance" % ref)
			continue
		var portee: float = profil.portee_saillance
		var facteur: float = clamp(1.0 - instance.distance / portee, 0.0, 1.0) if portee > 0.0 else 0.0
		if facteur <= 0.0:
			continue
		var avancement: float = _poids_avancement(proprietes)
		if avancement <= 0.0:
			continue
		var saillance: float = poids * facteur * avancement
		saillance = _appliquer_deformation(colon, proprietes, saillance, catalogue_deformations)
		resultats.append({
			"chose": instance.chose,
			"type": instance.type,
			"position": instance.position,
			"saillance": saillance,
		})
	return resultats

# Applique le biais de deformation du COLON (jamais de la chose) a une
# saillance NUE deja calculee -- voir en-tete du fichier. Ne mute rien
# (Deformation.biais est pure), rend juste le nombre module.
static func _appliquer_deformation(
	colon: Dictionary,
	proprietes_chose: Dictionary,
	saillance: float,
	catalogue_deformations: Dictionary,
) -> float:
	var deformation: Dictionary = colon.get("proprietes", {}).get("deformation_etat", {})
	for source in deformation:
		for cible in deformation[source]:
			if not proprietes_chose.has(cible):
				continue
			var biais: float = Deformation.biais(colon, source, cible, catalogue_deformations)
			var sens: String = catalogue_deformations.get(source, {}).get("sens", "")
			if sens == "baisse":
				saillance *= (1.0 - biais)
			elif sens == "monte":
				saillance *= (1.0 + biais)
	return saillance

# FACULTATIF au sens du couple (voir docs/design.md, "Propriete structurelle
# vs facultative") : les deux cles absentes, ou travail_initial <= 0.0, sont
# un etat neutre legitime -- une chose qui n'est pas un chantier n'a pas a
# etre penalisee ni privilegiee, donc 1.0 (identite multiplicative), jamais
# une alarme.
static func _poids_avancement(proprietes: Dictionary) -> float:
	if not proprietes.has("travail_restant") or proprietes.get("travail_initial", 0.0) <= 0.0:
		return 1.0
	return proprietes.travail_restant / proprietes.travail_initial
