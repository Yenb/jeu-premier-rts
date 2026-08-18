extends RefCounted

# Mecanisme du coeur : ATTACHE PAR TRAIT -- L'ELARGISSEMENT, passage du lien
# personnel (vecu, une chose precise) a l'attache par trait (idee, collective
# -- voir docs/design.md, "Le modele : attaches et forme", DEUX SOURCES DE
# SAILLANCE), PHASE 5 etape 4/4 piece 1/3 du chantier "L'entite comme agent
# complet" (voir docs/suivi_corps_interne_entite.md). Brique pure : aucun
# cablage reel, aucun banc -- seul le mecanisme existe ici, prouve hors
# domaine.
#
# Modele : une entite qui a personnellement vecu (proprietes.liens_personnels,
# voir lien_personnel.gd) plusieurs choses DIFFERENTES portant le meme trait,
# avec assez de force sur chacune, finit par porter une attache GENERALE sur
# ce trait (proprietes.attaches, voir attaches.gd) -- elle defendra desormais
# n'importe quelle chose portant ce trait, pas seulement celles qu'elle a
# personnellement vecues. Seuil COMPOSITE, nombre ET force (tranche par Yael,
# option (c) de docs/design.md) : il faut a la fois assez de choses liees
# (seuil_nombre) ET que chacune d'elles porte une force individuelle assez
# haute (seuil_force) -- une seule chose liee tres fortement ne suffit
# jamais, ni beaucoup de choses liees tres faiblement.
#
# avancer() est IDEMPOTENT : une fois l'attache par trait formee, un appel
# ulterieur qui retrouve les memes conditions ne l'ajoute pas une seconde
# fois (verifie contre proprietes.attaches avant d'ecrire). avancer() ne
# retire jamais une attache deja formee (pas de mecanisme d'oubli ici --
# une attache par trait, une fois formee, est immuable comme toute entree de
# proprietes.attaches, voir attaches.gd).
#
# SURCHARGE PAR COLON (PHASE 5 etape 4/4 piece 2/3) : les trois seuils
# (seuil_nombre, seuil_force, force_attache) se lisent COLON D'ABORD,
# CATALOGUE EN REPLI -- entite.proprietes.sensibilite_generalisation[trait_vise]
# porte 0 a 3 des trois cles ; toute cle absente de la surcharge retombe sur
# la regle du catalogue, jamais sur un defaut invente ici. Une surcharge
# PARTIELLE est valide (ex. seuil_nombre seul surcharge, seuil_force/
# force_attache viennent du catalogue). Mélange voies B (surcharge
# individuelle, comme poids_verbes/attaches/forme) et C (valeurs partagees
# de demarrage dans le catalogue) -- tranche par Yael, voir
# docs/suivi_corps_interne_entite.md. sensibilite_generalisation est
# FACULTATIVE sur l'entite (contrairement a liens_personnels/attaches
# ci-dessous) : son absence dit juste "aucune surcharge, tout depuis le
# catalogue" -- point neutre legitime, jamais une alarme.
#
# Structurel vs facultatif (voir docs/design.md, "Propriete structurelle vs
# facultative") : proprietes.liens_personnels ET proprietes.attaches sont
# STRUCTURELLES ici, chacune independamment verifiee -- leur absence dit
# "ceci n'est pas une entite equipee pour ce mecanisme", jamais un defaut
# silencieux. Meme raison qu'en PHASE 4/5 (deformation.gd/lien_personnel.gd) :
# la fonction recoit une seule entite, jamais un monde: Array a scanner.
#
# entite : Dictionary { id, position, proprietes }, mute en place (append sur
#          proprietes.attaches) quand un trait est nouvellement acquis.
# monde : Variant expose par_id(id) -> { chose, type } ou null -- jamais un
#         import de monde.gd (duck-type, meme convention que
#         lien_personnel_saillance.gd/agir.gd:_avec_cible_engagee). par_id
#         alarme deja lui-meme si l'id est absent (chose liee detruite
#         depuis) : ce fichier ne double pas l'alarme, une reponse null est
#         simplement ignoree (skip silencieux).
# catalogue : Dictionary regle_id -> { propriete, seuil_nombre, seuil_force,
#             force_attache } -- data/attaches_par_trait.json, jamais charge
#             par ce fichier (meme convention que lien_personnel.gd/
#             deformation.gd/couplage.gd). regle_id est un identifiant de
#             regle OPAQUE (comme actes_liants.json/engagements.json) --
#             "propriete" nomme explicitement le trait reellement verifie
#             sur les choses liees et pose dans l'attache formee, jamais
#             devine en decodant regle_id.
#
# Rend : Array des traits (String, valeur de "propriete") NOUVELLEMENT
# acquis a cet appel -- permet a l'appelant de logger l'evenement. Vide si
# rien n'a change.
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# l'entree ajoutee a proprietes.attaches ({ propriete, force }) ne porte que
# du JSON pur, meme forme que toute attache posee a la fabrication (voir
# attaches.gd).

static func avancer(entite: Dictionary, monde, catalogue: Dictionary) -> Array:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("liens_personnels"):
		push_error("attache_par_trait.gd : propriete structurelle 'liens_personnels' absente de proprietes")
		return []
	if not proprietes.has("attaches"):
		push_error("attache_par_trait.gd : propriete structurelle 'attaches' absente de proprietes")
		return []
	var sensibilite: Dictionary = proprietes.get("sensibilite_generalisation", {})
	var nouveaux: Array = []
	for regle_id in catalogue:
		var regle: Dictionary = catalogue[regle_id]
		var trait_vise: String = regle.get("propriete", "")
		var surcharge: Dictionary = sensibilite.get(trait_vise, {})
		var seuil_nombre: int = surcharge.get("seuil_nombre", regle.get("seuil_nombre", 0))
		var seuil_force: float = surcharge.get("seuil_force", regle.get("seuil_force", 0.0))
		var force_attache: float = surcharge.get("force_attache", regle.get("force_attache", 1.0))
		var compte := 0
		for chose_id in proprietes.liens_personnels:
			var force: float = proprietes.liens_personnels[chose_id]
			if force < seuil_force:
				continue
			var wrapper = monde.par_id(chose_id)
			if wrapper == null:
				continue
			if wrapper.chose.proprietes.get(trait_vise, false) == true:
				compte += 1
		if compte < seuil_nombre:
			continue
		var deja_present := false
		for attache in proprietes.attaches:
			if attache.get("propriete", "") == trait_vise:
				deja_present = true
				break
		if deja_present:
			continue
		proprietes.attaches.append({"propriete": trait_vise, "force": force_attache})
		nouveaux.append(trait_vise)
	return nouveaux
