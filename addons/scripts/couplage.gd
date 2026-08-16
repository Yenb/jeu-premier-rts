extends RefCounted

# Mecanisme du coeur : COUPLAGE, le VERBE -- l'acte physique de rester lie a
# une cible tant qu'on reste a portee. PHASE 1 du chantier "L'entite comme
# agent complet" (voir docs/cadrage_corps_interne_colon.md,
# docs/cadrage_phase1_engagement.md §C, docs/suivi_corps_interne_entite.md).
# Extrait de _engagement/
# _verrouiller_engagement, jusqu'ici local a banc_animal.gd.
#
# Nommage tranche en conversation (a ne pas confondre) : ce fichier est un
# VERBE (couplage = le mecanisme, le fait physique nu). L'ETAT qu'il pose et
# lit sur l'entite reste un NOM : entite.proprietes.ENGAGEMENT -- c'est cet
# etat, pas le mecanisme, que agir.gd/data/engagements.json designent. Le
# fichier suit le mecanisme (couplage.gd), la propriete suit son propre nom
# (engagement) : ne pas renommer l'un en fonction de l'autre.
#
# Rappel doctrine, a ne jamais confondre :
# - N'EST PAS une intention BDI (pas un plan defendu contre les
#   distractions) -- les 4 couches tournent toujours, aucun court-circuit.
# - N'EST PAS gain_inertie (preference de PERSONNALITE, qui reste distincte
#   et s'ajoute -- voir agir.gd). Le couplage est un FAIT PHYSIQUE : tant
#   que l'entite reste couplee a sa cible, elle pese plus lourd. Se pose
#   par presence, se retire par absence ou satisfaction, jamais par choix.
#
# entite.proprietes.engagement est STRUCTURELLE (voir docs/design.md,
# "Propriete structurelle vs facultative") : sa cle absente dit "ceci n'est
# pas une entite equipee pour se coupler" -- alarme (push_error). Sa valeur
# est soit null (aucun engagement en cours, legitime), soit un Dictionary
# { cible_id, regle_id, poids, seuil_satisfait, duree, ...contexte }.
#
# Trois fonctions, l'appelant decide quand les invoquer (aucun etat retenu
# ici -- RefCounted statique, comme le reste du coeur) :
# - poser(entite, cible, regle_id, catalogue, contexte) : ecrit l'engagement
#   depuis la regle resolue dans le catalogue (data/engagements.json).
#   contexte (Dictionary, facultatif) fusionne des cles supplementaires
#   dans l'engagement pose -- sert a parametrer satisfait_par quand un
#   meme regle_id s'applique a plusieurs canaux (voir JETONS ci-dessous).
# - avancer(entite, cible, delta, catalogue) : evalue l'engagement en
#   cours. cible = l'objet vise (Variant, deja retrouve par l'appelant --
#   ce fichier ne fait aucune requete spatiale ni de lookup par id, voir
#   monde.gd/Monde.par_id pour ca), ou null si la cible n'existe plus.
#   Rend "vide" (aucun engagement), "garde" (reste valide), "satisfait"
#   (but atteint) ou "arrache" (cible disparue -- impossibilite). Retire
#   l'engagement (remis a null) sur satisfait ou arrache.
#   L'ARRACHEMENT PAR SAILLANCE (une alternative devient trop forte malgre
#   le poids d'engagement) N'EST PAS evalue ici -- ce fichier ne recoit ni
#   saillance ni visibles, il ne va pas les chercher lui-meme. Ca vit dans
#   agir.gd/le cablage de banc, qui appelle retirer() quand la decision
#   change de cible malgre l'engagement actif.
# - retirer(entite, raison) : remet l'engagement a null. raison sert au
#   log eventuel de l'appelant, jamais lue par ce fichier.
#
# satisfait_par, CONTEXTE ET JETONS "{cle}" -- MECANIQUE COMPLETE, avec
# exemple concret file (pas besoin de lire les tests pour comprendre) :
#
# 1) LE PROBLEME QUE LES JETONS RESOLVENT. satisfait_par (dans la regle du
#    catalogue) est un chemin en points ("a.b.c") vers une valeur
#    numerique. Une regle de catalogue est UNIQUE et PARTAGEE par toutes
#    les entites qui l'utilisent -- mais banc_animal a DEJA N reserves
#    interchangeables (energie, matiere, demain sommeil/soif/chaleur) qui
#    partagent la MEME forme de regle (memes poids/seuils). Sans jeton, il
#    faudrait UNE entree de catalogue PAR reserve ("animal_reserve_energie",
#    "animal_reserve_matiere", ...) : une duplication qui grandirait a
#    chaque reserve ajoutee et regresserait la genericite a N reserves deja
#    acquise par banc_animal (cible_besoin ne nomme aucune reserve en dur).
#    Le jeton "{cle}" dans satisfait_par laisse UNE SEULE regle
#    ("animal_reserve") s'appliquer a n'importe quelle reserve, choisie au
#    cas par cas par l'appelant.
#
# 2) COMMENT contexte LES REMPLIT -- exemple concret. Le catalogue porte :
#      "animal_reserve": { "poids": 5.0, "seuil_satisfait": 19.5,
#        "satisfait_par": "reserves.{canal}.reserve", ... }
#    L'appelant (banc_animal.gd), au moment de poser(), sait DEJA quelle
#    reserve il engage (par ex. "energie", la plus basse ce tick) -- il la
#    passe via le parametre contexte :
#      Couplage.poser(animal, source_lumiere, "animal_reserve", catalogue,
#        {"canal": "energie"})
#    poser() fusionne contexte TEL QUEL dans l'engagement pose : la cle
#    "canal" devient une cle de plus a cote de cible_id/regle_id/poids/...
#    (engagement.canal == "energie"). Plus tard, avancer() lit
#    satisfait_par ("reserves.{canal}.reserve") et appelle _substituer()
#    AVANT d'evaluer le chemin : chaque "{canal}" est remplace par
#    engagement.get("canal") -- ici "energie" -- ce qui donne le chemin
#    concret "reserves.energie.reserve". Ce fichier ne sait pas ce que
#    "canal" signifie ni combien de jetons une regle peut porter : il ne
#    fait QUE remplacer une sous-chaine par cle de contexte. C'est
#    l'appelant qui choisit le nom du jeton et sa valeur -- une regle sans
#    aucun jeton (ex. "travail_restant" pour colon_chantier) traverse
#    _substituer() sans effet, contexte peut alors rester {} (defaut).
#
# 3) RESOLUTION DU CHEMIN UNE FOIS SUBSTITUE -- cible D'ABORD, entite
#    SINON. Le chemin concret ("reserves.energie.reserve" dans l'exemple
#    ci-dessus, ou "travail_restant" pour un chantier) est cherche
#    D'ABORD dans cible.proprietes, SINON dans entite.proprietes. Generique
#    par construction, ce fichier ne sait pas laquelle des deux s'applique :
#    - un CHANTIER pose sa valeur ("travail_restant") sur la CIBLE (le
#      bloc/feu que l'entite travaille) -- trouve du premier coup, la
#      recherche cote entite n'est jamais tentee.
#    - une RESERVE (l'exemple "reserves.energie.reserve" ci-dessus) est une
#      jauge de L'ENTITE elle-meme (l'animal), pas de la cible (une source
#      de lumiere ne porte pas de reserve) -- absente de cible.proprietes,
#      la recherche retombe sur entite.proprietes, ou elle est trouvee.
#    Chemin absent des DEUX (ou cible null) -> valeur 0.0, un point neutre
#    legitime (couvre aussi bien "chantier fini, cle erasee" que "reserve
#    jamais posee").
#
# 4) SENS DE LA SATISFACTION -- pourquoi un simple "<=" ne suffit pas. Un
#    CHANTIER se satisfait quand sa valeur DESCEND (travail_restant vers
#    0) ; une RESERVE se satisfait quand la sienne MONTE (une jauge qui se
#    recharge vers son maximum, ex. 19.5 sur 20.0) -- deux sens opposes
#    pour le meme mecanisme generique. sens_satisfaction (dans la regle du
#    catalogue, cache sur l'engagement au moment du poser comme
#    seuil_satisfait/seuil_bascule -- meme raison de resumabilite) tranche :
#    "sous_seuil" (DEFAUT, comportement historique) -- satisfait quand
#    valeur <= seuil_satisfait (colon_chantier : travail_restant tombe a
#    0.0 ou moins). "sur_seuil" -- satisfait quand valeur >= seuil_satisfait
#    (animal_reserve : la reserve remonte a 19.5 ou plus). Sans ce champ,
#    une regle "sur_seuil" appliquee avec la comparaison par defaut
#    declarerait satisfaction des le premier tick (une reserve qui vient de
#    commencer a descendre passe sous n'importe quel seuil positif) --
#    l'engagement se relacherait avant meme d'avoir commence.
#
# FORMAT DE contexte (parametre optionnel de poser(), defaut {}) : un
# Dictionary PLAT cle -> valeur, aucune forme imposee au-dela de "toute cle
# devient une cle de l'engagement pose". Les valeurs sont typiquement des
# String (noms de canal/reserve a substituer dans un jeton "{cle}"), mais
# rien n'empeche d'y glisser un nombre ou un bool si un futur regle_id en a
# besoin comme donnee d'instance -- ce fichier ne valide ni ne restreint son
# contenu, il fusionne, un point c'est tout.
#
# Recoit : entite/cible ({ id, position, proprietes }), catalogue
# (data/engagements.json, cle regle_id -> { poids, seuil_satisfait,
# seuil_bascule, satisfait_par, arrache_par }). Catalogue en parametre,
# jamais charge par ce fichier (meme convention que extinction.gd/
# depense.gd/charge.gd -- testable hors domaine sans toucher au
# disque).

static func poser(
	entite: Dictionary,
	cible: Dictionary,
	regle_id: String,
	catalogue: Dictionary,
	contexte: Dictionary = {},
) -> void:
	if not catalogue.has(regle_id):
		push_error("couplage.gd : regle '%s' absente du catalogue" % regle_id)
		return
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("engagement"):
		push_error("couplage.gd : propriete structurelle 'engagement' absente de proprietes")
		return
	var regle: Dictionary = catalogue[regle_id]
	var engagement: Dictionary = {
		"cible_id": cible.id,
		"regle_id": regle_id,
		"poids": regle.get("poids", 0.0),
		"seuil_satisfait": regle.get("seuil_satisfait", 0.0),
		"seuil_bascule": regle.get("seuil_bascule", 0.0),
		"sens_satisfaction": regle.get("sens_satisfaction", "sous_seuil"),
		"duree": 0.0,
	}
	for cle in contexte:
		engagement[cle] = contexte[cle]
	proprietes["engagement"] = engagement

static func avancer(
	entite: Dictionary,
	cible: Variant,
	delta: float,
	catalogue: Dictionary,
) -> String:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has("engagement"):
		push_error("couplage.gd : propriete structurelle 'engagement' absente de proprietes")
		return "vide"
	var engagement: Variant = proprietes.engagement
	if engagement == null:
		return "vide"
	if cible == null:
		proprietes["engagement"] = null
		return "arrache"
	var regle_id: String = engagement.regle_id
	if not catalogue.has(regle_id):
		push_error("couplage.gd : regle '%s' absente du catalogue" % regle_id)
		proprietes["engagement"] = null
		return "arrache"
	engagement["duree"] = engagement.get("duree", 0.0) + delta
	var regle: Dictionary = catalogue[regle_id]
	var chemin := _substituer(regle.get("satisfait_par", ""), engagement)
	var valeur := _valeur_satisfaction(cible, entite, chemin)
	var seuil := float(engagement.seuil_satisfait)
	var sens: String = engagement.get("sens_satisfaction", "sous_seuil")
	var satisfait: bool = valeur >= seuil if sens == "sur_seuil" else valeur <= seuil
	if satisfait:
		proprietes["engagement"] = null
		return "satisfait"
	return "garde"

static func retirer(entite: Dictionary, raison: String) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	proprietes["engagement"] = null

static func _substituer(gabarit: String, contexte: Dictionary) -> String:
	var resultat := gabarit
	for cle in contexte:
		resultat = resultat.replace("{%s}" % cle, str(contexte[cle]))
	return resultat

static func _lire_chemin(proprietes: Dictionary, chemin: String) -> Variant:
	if chemin == "":
		return null
	var courant: Variant = proprietes
	for morceau in chemin.split("."):
		if courant is Dictionary and courant.has(morceau):
			courant = courant[morceau]
		else:
			return null
	return courant

static func _valeur_satisfaction(cible: Dictionary, entite: Dictionary, chemin: String) -> float:
	var sur_cible: Variant = _lire_chemin(cible.get("proprietes", {}), chemin)
	if sur_cible != null:
		return float(sur_cible)
	var sur_entite: Variant = _lire_chemin(entite.get("proprietes", {}), chemin)
	if sur_entite != null:
		return float(sur_entite)
	return 0.0
