extends RefCounted

const QuantiteMatiere = preload("res://scripts/quantite_matiere.gd")

# Modele generique de FORCE A PORTEE : une chose porte une PROPRIETE SOURCE
# (magnetisme, ou tout autre nom donne en donnee), lue A LA DEMANDE dans sa
# fiche materiau (patron proximite.gd : reference resolue a chaque appel,
# jamais fusionnee a la fabrication -- voir data/materiaux.json, "RESERVE",
# et objet.gd, seule la densite est fusionnee). Deux choses qui portent
# chacune une quantite de matiere non nulle pour la MEME entree de catalogue
# s'attirent ou se repoussent selon une loi UNIQUE, MUTUELLE, appliquee par
# PAIRES (i<j, chaque paire traitee une seule fois, zero double comptage) :
# la force decroit avec la distance (1/d^exposant, exposant en donnee), et
# CHAQUE objet de la paire se deplace inversement a sa propre MASSE (deja
# calculee a la fabrication, objet.gd) -- l'immobilite d'un aimant tres
# lourd EMERGE du rapport de masse, aucune propriete "fixe" n'existe.
#
# Ce fichier ne connait AUCUN phenomene nomme : ni "magnetisme", ni
# "explosion", ni "gravite", ni "vent" n'apparaissent dans ce code. Le
# magnetisme est une ENTREE de data/champs.json parmi d'autres possibles,
# jamais une branche. Meme discipline que charge.gd (aucun nom de canal en
# dur) et propagation.gd (aucun nom de menace en dur).
#
# MUTATION DE POSITION EN PLACE (patron charge.gd sur Dictionary partage) :
# le deplacement est SUBI par l'objet, jamais decide -- contrairement a
# bouger_vers/bouger_selon (scripts/banc_commun.gd), qui RENDENT une
# position et laissent l'appelant assigner (mouvement d'AGENT, decide).
# monde.gd relit toujours position en direct (choses_dans_rayon), donc une
# mutation en place ici est visible immediatement par le reste du pipeline,
# sans cablage supplementaire.
#
# monde : Array de Dictionary { "id", "position" (Vector3), "proprietes" },
#         MUTE EN PLACE : "position" seule est modifiee, jamais "proprietes"
#         -- ce fichier ne pose ni ne retire aucune cle.
# delta : temps ecoule ce pas, en secondes.
# catalogue : Dictionary nom_champ -> entree { "propriete_source": String,
#         "signe": float, "exposant": float, "portee": float,
#         "plancher_distance": float, "plafond_deplacement": float,
#         "duree": float (FACULTATIF, JAMAIS LU ICI -- voir DUREE plus bas) }.
#         FACULTATIF (defaut {}) pour ne pas casser un appelant qui ne
#         fournit encore aucun champ.
# materiaux : Dictionary reference -> fiche (data/materiaux.json).
#         FACULTATIF (defaut {}).
#
# Toute cle de "catalogue" commencant par "_" (ex. "_note") est ignoree --
# meme convention que test_lint_donnees.gd:_parcourir, un champ descriptif
# n'est jamais une entree de champ.
#
# ENTREE STRUCTURELLE : une entree de catalogue sans "propriete_source",
# "signe", "exposant", "portee", "plancher_distance" ou "plafond_deplacement"
# est une donnee cassee -- push_error (nommant l'entree ET le champ absent),
# entree entierement ignoree ce tick, jamais un defaut invente qui simulerait
# une loi physique inventee.
#
# PROPRIETE SOURCE, resolution : le calcul de la quantite de matiere pour
# "propriete_source" (somme ponderee par volume sur "composition", PAS une
# moyenne -- une chose sans "composition" a quantite 0.0, silencieuse, ni
# source ni cible) est DELEGUE a scripts/quantite_matiere.gd:quantite --
# geste partage avec objet.gd (chantier "feu -- la reserve de combustible
# suit la matiere"), qui porte seul la doctrine complete du calcul (patron
# composition/materiaux, reference structurelle, propriete facultative sur
# la fiche). Voir son en-tete pour le detail -- non reduplique ici.
#
# LOI (par paire, par entree de catalogue, MUTUELLE) :
#   quantite = quantite_matiere(a) * quantite_matiere(b) -- produit des
#     DEUX cotes : si l'un des deux est 0.0 (objet sans la propriete),
#     la quantite de la paire est 0.0, l'objet n'est ni source ni cible
#     (decision explicite, voir en-tete du chantier). C'est la forme
#     mutuelle standard (gravite/Coulomb) : chaque objet EST source ET
#     cible pour l'autre, jamais un role fige.
#   d = max(distance_reelle, plancher_distance) -- le plancher borne le
#     1/d^exposant pres de zero (pas d'infini), en donnee, jamais en dur.
#   au-dela de "portee" : force nulle (chose hors du champ, pas de calcul).
#   force = quantite * (1.0 / d^exposant) * signe -- signe positif attire
#     VERS la source (magnetisme), signe negatif repousse (explosion,
#     jamais ecrite ici, seul le parametre existe deja pour elle).
#   deplacement_i = |force| / masse_i * delta, borne par "plafond_deplacement"
#     (jamais de traversee au contact, en donnee, jamais en dur) --
#     "masse" est STRUCTURELLE des qu'un objet participe a une paire (une
#     chose avec "composition" a deja recu "masse" par objet.gd:fabriquer ;
#     son absence est une donnee cassee, push_error, paire ignoree). DEUX
#     ROLES DISTINCTS, jamais a confondre : la QUANTITE DE MATIERE
#     MAGNETIQUE (ci-dessus) ATTIRE -- combien la source tire ; la MASSE
#     (ici) RESISTE -- combien l'objet accelere pour une meme force. Un
#     gros bloc de fer et un petit clou du meme materiau peuvent avoir la
#     MEME masse (materiaux differents, ou meme materiau mais densite
#     compensee par forme) sans avoir la meme quantite de matiere
#     magnetique -- les deux se composent dans le calcul ci-dessous
#     (force / masse), jamais fusionnes en un seul nombre.
#   direction : le long de l'axe (chose_b.position - chose_a.position),
#     signe(force) pour chaque cote -- attraction rapproche les deux le
#     long de cet axe, repulsion les eloigne, jamais de cas particulier.
#
# DUREE (parametre "duree" de l'entree de catalogue) : PORTE PAR LE SCHEMA,
# LU PAR AUCUN CODE ICI -- meme statut que data/types.json:objet_physique.
# temperature (fondation dormante). Une source PERMANENTE (magnetisme :
# "duree" absente) tire tant qu'elle reste dans "monde" a chaque tick, sans
# aucun code de cycle de vie -- champ.gd retrouve une chose permanente par
# balayage, comme propagation.gd retrouve un feu permanent via _en_feu.
# Une source EPHEMERE (explosion, "duree" finie -- NON ECRITE ici) exigerait
# qu'un objet transitoire naisse dans le monde (Objet.fabriquer, deja
# generique) puis en soit RETIRE apres sa duree de vie -- capacite absente
# de monde.gd aujourd'hui (aucune fonction de retrait), donc hors de portee
# de ce chantier. Le champ pourra porter une source ephemere sans refonte
# de LA LOI le jour ou cette capacite existe ailleurs.
#
# Frontiere avec fuite.gd : fuite.gd ne decide rien, ne connait ni masse ni
# distance-decroissance, rend une DIRECTION consommee par un mouvement
# d'AGENT (bouger_selon). champ.gd ne rend aucune direction a un appelant --
# il DEPLACE lui-meme, en place, un mouvement SUBI, jamais choisi.
# Frontiere avec charge.gd/extinction.gd : meme geste de detection a portee
# (somme/portee), mais aucun des deux ne deplace jamais position -- ils ne
# mutent que des proprietes. champ.gd est le premier mecanisme du coeur a
# ecrire position hors d'une decision d'agent.
#
# Rend l'Array des id des choses deplacees ce pas de temps (au moins une
# paire non nulle les impliquant), comme les ids retournes par charge.gd/
# extinction.gd/propagation.gd -- jamais une garantie de deplacement non
# nul pour toutes les choses de "monde".
static func avancer(monde: Array, delta: float, catalogue: Dictionary = {}, materiaux: Dictionary = {}) -> Array:
	var deplaces: Dictionary = {}
	for nom_champ in catalogue:
		if String(nom_champ).begins_with("_"):
			continue
		var entree: Dictionary = catalogue[nom_champ]
		if not _entree_valide(nom_champ, entree):
			continue
		for i in range(monde.size()):
			for j in range(i + 1, monde.size()):
				_appliquer_paire(monde[i], monde[j], entree, materiaux, delta, deplaces)
	return deplaces.keys()

# Calcule le resultat d'interaction pour une paire et une entree de champ --
# calcul UNIQUE partage par avancer() (qui l'applique) et force_paire()
# (qui l'expose en lecture seule, pour l'observabilite d'un banc, sans
# jamais dupliquer la formule).
static func _calculer_paire(chose_a: Dictionary, chose_b: Dictionary, entree: Dictionary, materiaux: Dictionary) -> Dictionary:
	var distance: float = chose_a.position.distance_to(chose_b.position)
	var resultat := {"force": 0.0, "distance": distance, "axe": Vector3.ZERO}
	var cle: String = entree.propriete_source
	var quantite_a := QuantiteMatiere.quantite(chose_a.proprietes, cle, materiaux)
	var quantite_b := QuantiteMatiere.quantite(chose_b.proprietes, cle, materiaux)
	if quantite_a <= 0.0 or quantite_b <= 0.0:
		return resultat
	if distance > entree.portee:
		return resultat
	var d: float = max(distance, entree.plancher_distance)
	var magnitude: float = (quantite_a * quantite_b) / pow(d, entree.exposant)
	resultat.force = magnitude * entree.signe
	if distance > 0.0:
		resultat.axe = (chose_b.position - chose_a.position) / distance
	return resultat

static func _appliquer_paire(chose_a: Dictionary, chose_b: Dictionary, entree: Dictionary, materiaux: Dictionary, delta: float, deplaces: Dictionary) -> void:
	var r := _calculer_paire(chose_a, chose_b, entree, materiaux)
	if r.force == 0.0 or r.axe == Vector3.ZERO:
		return
	if not chose_a.proprietes.has("masse") or not chose_b.proprietes.has("masse"):
		push_error("champ.gd : paire '%s'/'%s' sans 'masse' resolue -- deplacement ignore" % [chose_a.id, chose_b.id])
		return
	var plafond: float = entree.plafond_deplacement
	var direction: float = sign(r.force)
	var pas_a: float = clamp(abs(r.force) / chose_a.proprietes.masse * delta, 0.0, plafond)
	var pas_b: float = clamp(abs(r.force) / chose_b.proprietes.masse * delta, 0.0, plafond)
	chose_a.position += r.axe * direction * pas_a
	chose_b.position += r.axe * -direction * pas_b
	if pas_a > 0.0:
		deplaces[chose_a.id] = true
	if pas_b > 0.0:
		deplaces[chose_b.id] = true

# Lecture seule, publique : la force SIGNEE entre deux choses precises pour
# une entree de champ donnee -- destinee a un banc qui veut AFFICHER la
# traction courante sans reimplementer la loi (voir en-tete). Rend 0.0 dans
# tous les cas ou avancer() n'aurait rien applique (hors portee, l'une des
# deux sans la propriete, positions confondues).
static func force_paire(chose_a: Dictionary, chose_b: Dictionary, entree: Dictionary, materiaux: Dictionary = {}) -> float:
	return _calculer_paire(chose_a, chose_b, entree, materiaux).force

static func _entree_valide(nom_champ, entree: Dictionary) -> bool:
	for champ_requis in ["propriete_source", "signe", "exposant", "portee", "plancher_distance", "plafond_deplacement"]:
		if not entree.has(champ_requis):
			push_error("champ.gd : entree '%s' sans '%s' -- entree ignoree" % [nom_champ, champ_requis])
			return false
	return true
