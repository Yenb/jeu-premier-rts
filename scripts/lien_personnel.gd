extends RefCounted

# Mecanisme du coeur : LIEN PERSONNEL -- 2e source de saillance individuelle
# (voir docs/design.md, "Le modele : attaches et forme", DEUX SOURCES DE
# SAILLANCE : ATTACHE PAR TRAIT / LIEN PERSONNEL), PHASE 5 etape 1/4 du
# chantier "L'entite comme agent complet" (voir docs/suivi_corps_interne_entite.md).
# Brique pure : aucun evenement reel ne pose de lien a ce stade, aucune
# couche de saillance ne le lit encore -- seul le mecanisme existe ici,
# prouve hors domaine.
#
# Modele : une entite porte une force NOMMEE PAR CHOSE PRECISE
# (proprietes.liens_personnels[chose_id] = force: float) -- Dictionary
# PLAT, jamais imbrique (a la difference de deformation.gd : un lien
# personnel vise UN objet precis, pas une paire source/cible). poser()
# incremente la force d'un montant (un renouvellement s'accumule, ne
# remplace jamais) ; avancer() decroit chaque force selon un taux lu au
# catalogue, et RETIRE l'entree quand elle descend sous un plancher --
# sans ce retrait, le Dictionary grossirait indefiniment de liens
# residuels quasi nuls. force() ne fait que LIRE, jamais n'ecrit.
#
# Structurel vs facultatif (voir docs/design.md, "Propriete structurelle
# vs facultative") : proprietes.liens_personnels est STRUCTURELLE, meme
# convention que proprietes.deformation/engagement -- sa cle absente dit
# "ceci n'est pas une entite equipee pour porter un lien personnel",
# jamais "aucun lien". Meme raison qu'en PHASE 4 (deformation.gd) : les
# trois fonctions recoivent une seule entite, jamais un monde: Array a
# scanner -- la structuralite suit la forme de l'appel, pas le nom du
# composant (voir docs/suivi_corps_interne_entite.md, PHASE 4 piece 1).
# Sa valeur vide ({}) est legitime (aucun lien encore forme). Une chose
# absente de proprietes.liens_personnels est un point neutre legitime
# (poser() la cree, avancer()/force() ne l'inventent jamais).
#
# entite : Dictionary { id, position, proprietes }, mute en place par
#          poser()/avancer(). force() ne mute jamais rien.
# chose_id : String, identifiant opaque -- ce fichier ne connait aucun
#            nom de chose du monde, seulement des cles.
# catalogue : Dictionary "defaut" -> { taux_decroissance,
#             plancher_suppression } -- data/liens_personnels.json,
#             jamais charge par ce fichier (meme convention que
#             deformation.gd/couplage.gd/extinction.gd). Une seule
#             entree "defaut" a ce stade -- qualification par source
#             evenementielle (defense/sommeil/...) laissee a une etape
#             ulterieure, non necessaire ici.
#
# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) :
# proprietes.liens_personnels ne porte jamais que des float en valeur --
# aucun Vector3, aucun Callable.

static func poser(entite: Dictionary, chose_id: String, magnitude: float) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("liens_personnels"):
		push_error("lien_personnel.gd : propriete structurelle 'liens_personnels' absente de proprietes")
		return
	var liens: Dictionary = proprietes.liens_personnels
	liens[chose_id] = liens.get(chose_id, 0.0) + magnitude

static func avancer(entite: Dictionary, delta: float, catalogue: Dictionary) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("liens_personnels"):
		push_error("lien_personnel.gd : propriete structurelle 'liens_personnels' absente de proprietes")
		return
	if not catalogue.has("defaut"):
		push_error("lien_personnel.gd : catalogue sans entree 'defaut'")
		return
	var regle: Dictionary = catalogue.defaut
	var taux: float = regle.get("taux_decroissance", 0.0)
	var plancher: float = regle.get("plancher_suppression", 0.0)
	var liens: Dictionary = proprietes.liens_personnels
	var a_retirer: Array = []
	for chose_id in liens:
		var force_restante: float = max(0.0, liens[chose_id] - taux * delta)
		liens[chose_id] = force_restante
		if force_restante < plancher:
			a_retirer.append(chose_id)
	for chose_id in a_retirer:
		liens.erase(chose_id)

static func force(entite: Dictionary, chose_id: String, _catalogue: Dictionary) -> float:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("liens_personnels"):
		push_error("lien_personnel.gd : propriete structurelle 'liens_personnels' absente de proprietes")
		return 0.0
	return proprietes.liens_personnels.get(chose_id, 0.0)
