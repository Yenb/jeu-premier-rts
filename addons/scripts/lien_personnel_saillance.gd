extends RefCounted

# Couche 2 (saillance) : LIEN PERSONNEL -- PREMIERE LECTURE d'un lien
# personnel (scripts/lien_personnel.gd) par une couche de saillance, PHASE 5
# etape 3/4 du chantier "L'entite comme agent complet" (voir
# docs/suivi_corps_interne_entite.md). Fonction pure lecteur, aucune
# mutation -- meme convention que Deformation.biais.
#
# Role (voir docs/design.md, "Le modele : attaches et forme", L'ELARGISSEMENT
# et "Le lien personnel rend saillant CE QUI S'EN APPROCHE") : un lien
# personnel vise UNE chose precise (proprietes.liens_personnels[chose_id] =
# force). Ce mecanisme ne rend PAS saillante la chose liee elle-meme -- il
# rend saillant CE QUI S'EN APPROCHE, dans l'espace, exactement comme
# attaches.gd relie deux choses par une distance ENTRE ELLES (jamais au
# colon). Un colon perd d'attention pour tout ce qui se rapproche d'une
# chose a laquelle il tient personnellement, meme une chose qu'il n'a
# jamais vue avant.
#
# Modele : pour une chose PERCUE quelconque, pour chaque chose_liee_id que
# porte colon.proprietes.liens_personnels, on retrouve la POSITION de la
# chose liee (jamais son id seul) via monde.par_id, et on mesure la distance
# ENTRE la chose percue et la chose liee -- jamais au colon (meme option B
# que attaches.gd, voir docs/design.md). Plus cette distance est courte au
# regard de portee_menace, plus la contribution est haute ; au-dela de
# portee_menace, contribution nulle. Les contributions de plusieurs liens
# s'ADDITIONNENT (compose EN SEQUENCE avec les autres sources plutot
# qu'ecraser -- meme famille additive que "ATTACHE + PROXIMITE", voir
# docs/design.md, DEUX SOURCES DE SAILLANCE).
#
# entite (colon) : Dictionary { proprietes: { liens_personnels } }. Meme
# convention que lien_personnel.gd : liens_personnels est STRUCTURELLE (sa
# cle absente dit "ceci n'est pas une entite equipee pour porter un lien
# personnel", jamais "aucun lien") -- ce fichier ne fait que LIRE, jamais
# poser ni avancer, mais lit la meme cle, meme contrat.
# chose : Dictionary { position: Vector3, ... } -- la chose PERCUE dont on
# evalue le bonus de saillance, jamais la chose liee elle-meme (meme si
# rien n'empeche geometriquement qu'elles coincident, ex. la chose liee
# elle-meme est "percue" et se retrouve donc a distance 0 d'elle-meme).
# monde : Variant expose par_id(id) -> { chose, type } ou null -- jamais un
# import de monde.gd (duck-type, meme convention que agir.gd:
# _avec_cible_engagee). par_id alarme deja lui-meme si l'id est absent
# (chose liee detruite depuis) : ce fichier ne double pas l'alarme, il
# traite juste une reponse null comme une contribution nulle, silencieusement.
# catalogue : Dictionary "defaut" -> { portee_menace } -- data/
# liens_personnels.json, jamais charge par ce fichier (meme convention que
# lien_personnel.gd/deformation.gd/couplage.gd). portee_menace absente de
# l'entree "defaut" (ou l'entree "defaut" elle-meme absente) alarme
# (push_error) et rend 0.0, meme contrat que les autres alarmes de
# catalogue de ce depot.

static func bonus(colon: Dictionary, chose: Dictionary, monde, catalogue: Dictionary) -> float:
	var proprietes: Dictionary = colon.get("proprietes", {})
	if not proprietes.has("liens_personnels"):
		push_error("lien_personnel_saillance.gd : propriete structurelle 'liens_personnels' absente de proprietes")
		return 0.0
	if not catalogue.has("defaut") or not catalogue.defaut.has("portee_menace"):
		push_error("lien_personnel_saillance.gd : catalogue sans 'defaut.portee_menace'")
		return 0.0
	var portee_menace: float = catalogue.defaut.portee_menace
	var liens: Dictionary = proprietes.liens_personnels
	var total := 0.0
	for chose_liee_id in liens:
		var wrapper = monde.par_id(chose_liee_id)
		if wrapper == null:
			continue
		var distance: float = chose.position.distance_to(wrapper.chose.position)
		if distance >= portee_menace:
			continue
		var force_du_lien: float = liens[chose_liee_id]
		total += force_du_lien * (1.0 - distance / portee_menace)
	return total
