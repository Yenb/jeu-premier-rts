extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_conduction.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « conduction
# electrique -- courant continu » : montre flux.gd (transfert continu,
# deja ferme, deja cable sur banc_animal.gd) et charge.gd -> etat_duree.gd
# -> depense.gd (patron « accumulation -> etat -> degat », deja ferme trois
# fois par banc_pourriture.gd/banc_corrosion.gd/banc_solubilite.gd) composes
# sur un domaine neuf, l'electricite -- AUCUN DES DEUX PATRONS N'EST
# REECRIT, seul ce fichier les appelle.
#
# AUCUN MECANISME DU COEUR TOUCHE : flux.gd/charge.gd/etat_effectif.gd/
# etat_duree.gd/depense.gd/objet.gd restent inchanges. Deux lignes de
# donnee au-dela de ce fichier et de data/banc_conduction.json (jetable,
# propre au banc) : "conductivite_electrique" rejoint data/proprietes_
# immuables_composition.json (dormante avant ce chantier, comme absorption_
# humidite/solubilite avant les leurs) et "electrocute" rejoint data/
# etats.json (catalogue PARTAGE, meme famille reversible que mouille/
# pourri/corrode -- duree, aucun effet module, sert seulement de marqueur
# de gate pour depense.gd).
#
# LA CIRCULATION DU COURANT (flux.gd, jamais modifie) : un objet est
# CONDUCTEUR_ACTIF si sa conductivite_electrique EFFECTIVE (EtatEffectif.
# valeur, applique "mouille" x10.0 si l'etat est present -- fondation
# dormante du chantier humidite, voir data/etats.json:mouille) depasse
# "seuil_conduction" (donnee, 1.0 S/m -- separe nettement fer ~1e7 de
# bois/pierre ~1e-15/1e-9, unites documentees dans materiaux.json:_note).
# Un objet est SOUS_TENSION si un GENERATEUR actif (structurel, jamais
# lu par aucun mecanisme du coeur) l'atteint par une chaine ININTERROMPUE
# d'objets conducteur_actif en contact (portee_contact) -- calcule CHAQUE
# TICK par propager_tension (parcours en largeur, fonction pure de ce
# fichier, PAS flux.gd : flux.gd ne sait pas propager de proche en proche,
# il transfere depuis une SOURCE vers toute chose RECEPTRICE a portee de
# CETTE source, jamais receptrice-devient-source automatiquement). Un
# isolant (bois) n'est jamais conducteur_actif : la chaine s'arrete net
# a lui, rien au-dela ne devient jamais sous_tension -- AUCUNE branche "si
# bois" nulle part, la loi ne connait que le seuil sur une valeur continue.
#
# flux.gd EST ENSUITE APPELE, une fois par objet energise ce tick, avec un
# EMETTEUR SYNTHETIQUE (position de l'objet lui-meme, taux_flux = facteur_
# conductivite_base * conductivite EFFECTIVE de CET objet) -- meme idiome
# que banc_humidite.gd (« un appel a Charge.avancer PAR OBJET CIBLE, pondere
# par absorption_humidite ») transpose a flux.gd, puisque flux.gd ne connait
# qu'UN SEUL taux_flux par source, jamais un coefficient par receveur. C'est
# ce qui rend le TAUX DE TRANSFERT proportionnel a la conductivite du
# RECEPTEUR (demande du chantier) sans toucher flux.gd : chaque objet
# accumule sa propre reserve "courant" a une vitesse qui LUI est propre.
# "facteur_conductivite_base" (1e-6) compense l'ecart d'echelle entre les
# unites reelles de materiaux.json (S/m, 1e-15 a 1e7) et une reserve
# lisible a l'ecran en quelques secondes -- meme geste que la masse
# minuscule de leger_golem dans banc_champ.json, jamais une loi differente.
#
# LES DEGATS (charge.gd -> etat_duree.gd -> depense.gd, patron ferme trois
# fois) : un agent (colon_test, construit A LA MAIN comme banc_contagion.gd
# -- aucun pipeline de decision necessaire ici, seulement l'exposition et la
# reserve) accumule une charge "electrocution" dont chaque cause est un
# objet SOUS_TENSION a portee, pondere par SA conductivite effective (meme
# facteur_conductivite_base que ci-dessus -- meme raison, ramener l'echelle
# S/m a un seuil de charge lisible). Au franchissement, charge.gd pose un
# simple marqueur booleen (expose_electrocution, jamais etats_actifs
# directement -- charge.gd est symetrique, incompatible avec un retrait
# PROGRESSIF) ; CE FICHIER, tant que le marqueur reste vrai, repose lui-meme
# EtatDuree.poser("electrocute") CHAQUE tick (remise a 1.0, jamais un
# cumul, meme idiome que "mouille"/"expose_humidite" dans banc_humidite.gd).
# depense.gd n'a de coefficient par receveur : le cout_base du canal
# "integrite" de l'agent est donc GELE a "degat_par_s" (donnee) SEULEMENT
# tant que "electrocute" est dans etats_actifs, 0.0 sinon -- meme gate
# exact que la reserve "integrite" du fer dans banc_corrosion.gd.
#
# CE QU'ON DOIT VOIR : un clic gauche bascule TOUS les generateurs actifs/
# inactifs a la fois (meme geste que banc_humidite.gd, applique a quatre
# sources). Trois rangees : fer-bois-fer (le second fer ne s'energise
# jamais, le courant est bloque au bois), fer-fer-fer (les trois s'energisent
# en chaine), et une paire fer sec/fer mouille (chacun sa propre source, meme
# distance) dont la reserve "courant" grandit dix fois plus vite pour le
# mouille -- effet direct de la fondation dormante "mouille module
# conductivite_electrique x10.0". Un agent pose pres du fer central de la
# rangee qui traverse prend des degats continus (reserve "integrite" qui
# decroit) tant que la rangee reste sous tension ; couper les generateurs
# arrete les degats, "electrocute" s'estompe progressivement (etat_duree.gd,
# duree 1.5s), jamais un retrait instantane.
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier, ses donnees et
# ses tests sont le SEUL perimetre au-dela des deux lignes de donnee citees
# plus haut -- flux.gd/charge.gd/etat_effectif.gd/etat_duree.gd/depense.gd/
# temperature.gd/perception.gd/propagation.gd/agir.gd/champ.gd/objet.gd
# restent EXACTEMENT ceux deja verrouilles par leurs propres tests, aucun
# n'est touche par ce chantier.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique generateurs/objets/
#   agent (Objet.fabriquer pour les objets composes, construction a la main
#   pour generateurs et agent -- meme patron que banc_contagion.gd, aucun
#   pipeline de decision necessaire). _unhandled_input bascule tous les
#   generateurs au clic gauche. _process appelle UNIQUEMENT avancer()
#   (fonction statique, ci-dessous) puis lit ses resultats pour l'affichage/
#   la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_conduction.gd) : conducteurs_actifs/propager_tension/
#   causes_de_tension/avancer/basculer_generateurs/fabriquer_objets/
#   fabriquer_generateurs/fabriquer_agent/diagnostiquer, plus le texte
#   d'affichage et de log. `position_affichage` (correction visuelle,
#   session ulterieure, voir DISPOSITION_AFFICHAGE plus bas) est PURE mais
#   hors de ce perimetre de test -- purement cosmetique, aucun comportement
#   de jeu n'en depend.

const Objet = preload("res://scripts/objet.gd")
const Flux = preload("res://scripts/flux.gd")
const Charge = preload("res://scripts/charge.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Depense = preload("res://scripts/depense.gd")
const Portee = preload("res://scripts/portee.gd")

const TAILLE := 60.0
const TAILLE_SOURCE := 24.0
const HAUTEUR_BARRE := 8.0
const PROPRIETE_CONDUCTIVITE := "conductivite_electrique"
const COURANT_BARRE_MAX := 200.0
const INTEGRITE_BARRE_MAX := 10.0
# BUG FERME (correction visuelle, session ulterieure) : flux.gd:_recharger
# ne fait qu'ADDITIONNER (voir son en-tete, "ce fichier ne 'donne' rien, il
# transfere selon un nombre") -- rien dans flux.gd ne decroit jamais un
# canal, contrairement a charge.gd (taux_decroissance NATIF, d'ou la barre
# de banc_humidite.gd qui redescend). Sans un geste EQUIVALENT ici, la
# reserve "courant" ne peut que monter, saturer a COURANT_BARRE_MAX, puis y
# rester pour toujours meme generateurs coupes -- la barre semblait figee
# "pleine" alors que le texte affichait bien la valeur (correcte, elle
# aussi figee). TAUX_DECROISSANCE_COURANT fait decroitre "courant" SEULEMENT
# pour un objet qui n'est PLUS energise ce tick (voir avancer() plus bas) --
# jamais pendant qu'il conduit, jamais via depense.gd (qui n'a pas de
# coefficient "energise ou non", il draine inconditionnellement).
const TAUX_DECROISSANCE_COURANT := 40.0

# DISPOSITION D'AFFICHAGE (correction visuelle, session ulterieure) :
# separee de la position REELLE (Vector3, data/banc_conduction.json, JAMAIS
# TOUCHEE -- lue par propager_tension/Portee.en_portee pour la distance de
# CONTACT reelle, 90 unites, necessaire au jeu). Les labels de ce banc
# portent 4-6 lignes (conductivite en notation scientifique comprise) : a
# 90 unites d'ecart reel, aucun espacement de donnee ne suffirait a les
# separer -- contrairement a banc_humidite.gd/banc_porosite.gd (200-300
# unites entre objets, la distance ne joue aucun role de jeu chez eux). Ce
# tableau place donc chaque id a une position D'ECRAN SEULE -- voir
# position_affichage() plus bas, jamais lue par avancer()/
# propager_tension()/causes_de_tension(), uniquement par les fonctions de
# rendu (_creer_rendu_*/_poser_camera) : le COMPORTEMENT DE SIMULATION reste
# rigoureusement inchange, seul l'ENDROIT OU C'EST DESSINE change. Quatre
# groupes espaces de 280 (colonnes) et 340 (lignes) : bloque/traverse cote
# a cote (memes colonnes, pour comparer visuellement les deux rangees),
# colon_test sur sa PROPRE ligne (jamais superpose a fer_traverse_2), sec/
# mouille dans un second bloc a droite (peu d'objets, pas besoin des memes
# colonnes que bloque/traverse).
const DISPOSITION_AFFICHAGE := {
	"source_bloque": Vector2(0.0, 0.0),
	"fer_bloque_1": Vector2(280.0, 0.0),
	"bois_bloque": Vector2(560.0, 0.0),
	"fer_bloque_2": Vector2(840.0, 0.0),

	"source_traverse": Vector2(0.0, 340.0),
	"fer_traverse_1": Vector2(280.0, 340.0),
	"fer_traverse_2": Vector2(560.0, 340.0),
	"fer_traverse_3": Vector2(840.0, 340.0),

	"colon_test": Vector2(560.0, 680.0),

	"source_sec": Vector2(1220.0, 0.0),
	"fer_sec": Vector2(1500.0, 0.0),

	"source_mouille": Vector2(1220.0, 340.0),
	"fer_mouille": Vector2(1500.0, 340.0),
}
const CENTRE_AFFICHAGE := Vector2(850.0, 325.0)
const ZOOM_AFFICHAGE := 0.63
const TAILLE_POLICE_LABEL := 14

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _materiaux: Dictionary = {}
var _sources: Array = []
var _objets: Array = []
var _agent: Dictionary = {}
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_agent: ColorRect
var _label_agent: Label
var _sous_tension_avant: Dictionary = {}
var _electrocute_avant: bool = false
var _actif_avant: bool = false
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_conduction.json")
	_etats = _charger_json("res://data/etats.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_sources = fabriquer_generateurs(_config.get("sources", []))
	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables)
	_agent = fabriquer_agent(_config.get("agent", {}), _config)

	for source in _sources:
		_creer_rendu_source(source)
	for objet in _objets:
		_sous_tension_avant[objet.id] = false
		_creer_rendu_objet(objet)
	_creer_rendu_agent()
	_poser_camera()

	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		basculer_generateurs(_sources, _config.propriete_cause)
		var actif: bool = _generateurs_actifs(_sources, _config.propriete_cause)
		print(_ligne_generateurs(_temps, actif))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(_sources, _objets, _agent, delta, _config, _etats)

	for objet in _objets:
		var id: String = objet.id
		var sous_tension: bool = objet.proprietes.get(_config.propriete_sous_tension, false)
		if sous_tension != _sous_tension_avant.get(id, false):
			var effective: float = EtatEffectif.valeur(objet, PROPRIETE_CONDUCTIVITE, _etats)
			print(_ligne_sous_tension(_temps, id, sous_tension, effective))
			_sous_tension_avant[id] = sous_tension

	var electrocute: bool = _agent.proprietes.get("etats_actifs", []).has(_config.nom_etat_electrocute)
	if electrocute != _electrocute_avant:
		var reserve: float = _agent.proprietes.get("reserves", {}).get(_config.nom_reserve_integrite, {}).get("reserve", 0.0)
		print(_ligne_electrocute(_temps, electrocute, reserve))
		_electrocute_avant = electrocute

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for source in _sources:
		var actif: bool = source.proprietes.get(_config.propriete_cause, false)
		_noeuds[source.id].color = Color(0.15, 0.55, 0.95) if actif else Color(0.4, 0.4, 0.4)
		_labels[source.id].text = "%s\n%s" % [source.id, "ACTIF" if actif else "INACTIF"]

	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet, _config, _etats)
		_noeuds[id].color = _teinte_pour_statut(diag.sous_tension, diag.conducteur_actif)
		var ratio: float = clamp(diag.courant / COURANT_BARRE_MAX, 0.0, 1.0)
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio
		_labels[id].text = _texte_label_objet(id, diag)

	var diag_agent := diagnostiquer_agent(_agent, _config)
	_noeud_agent.color = Color(0.85, 0.15, 0.15) if diag_agent.electrocute else Color(0.5, 0.5, 0.55)
	_label_agent.text = _texte_label_agent(diag_agent)

# ---- Fonctions PURES, testables headless (voir test_banc_conduction.gd) ----

# Rend id -> bool : vrai si la conductivite EFFECTIVE de l'objet (mouille
# comprise, EtatEffectif.valeur -- jamais reimplementee) depasse
# "seuil_conduction". Un objet sans "conductivite_electrique" (absente de
# sa fiche materiau, ou fabrication sans composition) retombe sur le
# defaut 0.0 de proprietes.get -- jamais conducteur.
static func conducteurs_actifs(objets: Array, etats: Dictionary, seuil_conduction: float) -> Dictionary:
	var actifs: Dictionary = {}
	for objet in objets:
		var effective: float = EtatEffectif.valeur(objet, PROPRIETE_CONDUCTIVITE, etats)
		actifs[objet.id] = effective > seuil_conduction
	return actifs

# Parcours en largeur depuis chaque generateur ACTIF (proprietes[propriete_
# cause] vrai), a travers les objets dont conducteurs[id] est vrai, en
# contact (Portee.en_portee, meme fonction partagee que charge.gd/flux.gd/
# propagation.gd/attaches.gd/extinction.gd -- voir docs/design.md,
# "Direction majeure"). Rend id -> true pour chaque objet ATTEINT -- un
# objet non conducteur n'est jamais ajoute a la frontiere, rien au-dela
# de lui ne peut donc jamais s'energiser (blocage NET, pas une attenuation).
# Aucun generateur actif, ou monde vide : rend {} (chemin mort).
static func propager_tension(sources: Array, objets: Array, conducteurs: Dictionary, portee_contact: float, propriete_cause: String) -> Dictionary:
	var energises: Dictionary = {}
	var frontiere: Array = []
	for source in sources:
		if source.proprietes.get(propriete_cause, false):
			frontiere.append(source)
	while not frontiere.is_empty():
		var courant: Dictionary = frontiere.pop_back()
		for objet in objets:
			if energises.has(objet.id):
				continue
			if not conducteurs.get(objet.id, false):
				continue
			if Portee.en_portee(courant.position, objet.position, portee_contact):
				energises[objet.id] = true
				frontiere.append(objet)
	return energises

# Une cause par objet SOUS_TENSION, poids = sa conductivite EFFECTIVE
# multipliee par "facteur_conductivite_base" (compense l'echelle S/m,
# voir en-tete) -- demande du chantier : "le poids est proportionnel a
# conductivite_electrique de l'objet sous tension". Un objet sous tension
# a conductivite effective nulle ou negative (ne devrait jamais arriver,
# garde defensive) ne produit aucune cause.
static func causes_de_tension(objets: Array, propriete_sous_tension: String, etats: Dictionary, facteur_conductivite_base: float) -> Array:
	var causes: Array = []
	for chose in objets:
		if not chose.proprietes.get(propriete_sous_tension, false):
			continue
		var effective: float = EtatEffectif.valeur(chose, PROPRIETE_CONDUCTIVITE, etats)
		if effective <= 0.0:
			continue
		causes.append({"position": chose.position, "poids": effective * facteur_conductivite_base})
	return causes

# UN PAS de simulation complet : (1) determine qui conduit et qui est sous
# tension ce tick (proprietes.sous_tension/conducteur_actif POSES sur
# chaque objet -- lisibles par l'affichage sans recalcul) ; (2) flux.gd,
# une fois PAR OBJET energise, avec un emetteur synthetique dont le
# taux_flux est proportionnel a la conductivite EFFECTIVE de CET OBJET
# (voir en-tete, POURQUOI PAR OBJET) ; (2b) DECROISSANCE (voir
# TAUX_DECROISSANCE_COURANT en-tete, BUG FERME) : chaque objet qui N'EST
# PLUS energise ce tick voit sa reserve "courant" decroitre vers 0 --
# flux.gd n'a lui-meme AUCUN geste de decroissance, seul ce pas le fournit,
# jamais applique a un objet encore energise (sinon il rentrerait en
# concurrence avec l'accumulation de l'etape 2) ; (3) charge.gd ->
# etat_duree.gd -> depense.gd sur l'agent, meme patron ferme trois fois
# (pourriture/corrosion/solubilite), applique ici a une exposition
# electrique plutot qu'a l'humidite. Rend { energises, receveurs, bascules,
# expirees, franchis_integrite } -- memes formes que celles deja rendues
# par Charge.avancer/EtatDuree.avancer/Depense.avancer, jamais recalculees
# ici.
static func avancer(sources: Array, objets: Array, agent: Dictionary, delta: float, config: Dictionary, etats: Dictionary) -> Dictionary:
	var conducteurs := conducteurs_actifs(objets, etats, config.seuil_conduction)
	var energises := propager_tension(sources, objets, conducteurs, config.portee_contact, config.propriete_cause)
	for objet in objets:
		objet.proprietes[config.propriete_sous_tension] = energises.has(objet.id)
		objet.proprietes[config.propriete_conducteur] = conducteurs.get(objet.id, false)

	var receveurs: Array = []
	var table_flux := [{"source": config.propriete_sous_tension, "receptrice": config.propriete_conducteur, "cible": config.nom_reserve_courant}]
	for objet in objets:
		if not energises.has(objet.id):
			continue
		var effective: float = EtatEffectif.valeur(objet, PROPRIETE_CONDUCTIVITE, etats)
		var emetteur := {
			"id": "%s_emetteur" % objet.id,
			"position": objet.position,
			"proprietes": {
				config.propriete_sous_tension: true,
				"taux_flux": config.facteur_conductivite_base * effective,
				"portee_flux": config.portee_contact,
			},
		}
		Flux.avancer([emetteur, objet], table_flux, delta)
		receveurs.append(objet.id)

	for objet in objets:
		if energises.has(objet.id):
			continue
		var reserves_objet: Dictionary = objet.proprietes.get("reserves", {})
		var canal_courant: Dictionary = reserves_objet.get(config.nom_reserve_courant, {})
		if canal_courant.is_empty():
			continue
		canal_courant["reserve"] = max(0.0, canal_courant.get("reserve", 0.0) - TAUX_DECROISSANCE_COURANT * delta)

	var causes := causes_de_tension(objets, config.propriete_sous_tension, etats, config.facteur_conductivite_base)
	var bascules := Charge.avancer([agent], causes, delta)
	if agent.proprietes.get(config.declencheur_expose_electrocution, false):
		EtatDuree.poser(agent, config.nom_etat_electrocute, etats)
	var expirees := EtatDuree.avancer([agent], delta, etats)

	var reserves: Dictionary = agent.proprietes.get("reserves", {})
	if reserves.has(config.nom_reserve_integrite):
		var actif_electrocute: bool = agent.proprietes.get("etats_actifs", []).has(config.nom_etat_electrocute)
		reserves[config.nom_reserve_integrite]["cout_base"] = config.degat_par_s if actif_electrocute else 0.0
	var franchis_integrite := Depense.avancer([agent], delta)

	return {
		"energises": energises.keys(),
		"receveurs": receveurs,
		"bascules": bascules,
		"expirees": expirees,
		"franchis_integrite": franchis_integrite,
	}

# Position D'ECRAN d'un id (voir DISPOSITION_AFFICHAGE ci-dessus) -- JAMAIS
# la position reelle (Vector3) que lit le jeu. Un id absent de la table
# (ne devrait jamais arriver, les treize ids de data/banc_conduction.json y
# figurent tous) retombe sur l'origine -- chemin mort silencieux, purement
# cosmetique, aucune alarme necessaire (contrairement a une reference de
# catalogue de jeu).
static func position_affichage(id: String) -> Vector2:
	return DISPOSITION_AFFICHAGE.get(id, Vector2.ZERO)

static func _generateurs_actifs(sources: Array, propriete_cause: String) -> bool:
	for source in sources:
		if source.proprietes.get(propriete_cause, false):
			return true
	return false

static func basculer_generateurs(sources: Array, propriete_cause: String) -> void:
	var actif := not _generateurs_actifs(sources, propriete_cause)
	for source in sources:
		source.proprietes[propriete_cause] = actif

# Construit les generateurs A LA MAIN (Dictionary { id, position,
# proprietes: { <propriete_cause>: false } }, meme patron que
# banc_contagion.gd -- pas Objet.fabriquer, aucune composition physique,
# ce sont des sources abstraites, jamais des conducteurs).
static func fabriquer_generateurs(declarations: Array) -> Array:
	var sources: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		sources.append({
			"id": decl.id,
			"position": Vector3(pos[0], pos[1], pos[2]),
			"proprietes": {},
		})
	return sources

# Construit les objets conducteurs/isolants via Objet.fabriquer (composition
# fusionnee -- meme patron que banc_humidite.gd/banc_corrosion.gd, catalogue
# LOCAL a une entree par id). "etats_actifs" (FACULTATIF sur la declaration,
# ex. ["mouille"] pour le demo mouille) est copie tel quel apres fabrication
# -- Objet.fabriquer ne le connait pas, ce n'est pas une propriete
# immuable de composition. Une reserve "courant" vide est initialisee
# pour que le premier affichage (avant tout tick) montre 0.0 plutot qu'une
# absence -- flux.gd la creerait de toute facon au premier transfert.
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["etats_actifs"] = decl.get("etats_actifs", []).duplicate(true)
		objet.proprietes["reserves"] = {"courant": {"reserve": 0.0}}
		objets.append(objet)
	return objets

# Construit l'agent A LA MAIN (meme patron que banc_contagion.gd) : aucun
# pipeline de decision necessaire pour ce chantier, seulement l'exposition
# (canal "electrocution", charge.gd) et la reserve consommee ("integrite",
# depense.gd).
static func fabriquer_agent(decl: Dictionary, config: Dictionary) -> Dictionary:
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	return {
		"id": decl.get("id", "agent"),
		"position": Vector3(pos[0], pos[1], pos[2]),
		"proprietes": {
			"etats": {config.nom_canal_electrocution: config.canal_electrocution_defaut.duplicate(true)},
			"etats_actifs": [],
			"reserves": {config.nom_reserve_integrite: config.reserve_integrite_defaut.duplicate(true)},
		},
	}

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees
# par etat_effectif.gd/flux.gd, ne reimplemente jamais leur loi (meme
# doctrine que banc_humidite.gd/banc_corrosion.gd:diagnostiquer). Rend
# { sous_tension, conducteur_actif, conductivite_effective, courant }.
static func diagnostiquer(objet: Dictionary, config: Dictionary, etats: Dictionary) -> Dictionary:
	return {
		"sous_tension": objet.proprietes.get(config.propriete_sous_tension, false),
		"conducteur_actif": objet.proprietes.get(config.propriete_conducteur, false),
		"conductivite_effective": EtatEffectif.valeur(objet, PROPRIETE_CONDUCTIVITE, etats),
		"courant": objet.proprietes.get("reserves", {}).get(config.nom_reserve_courant, {}).get("reserve", 0.0),
	}

# Diagnostic d'affichage de l'agent, PUR. Rend { electrocute, charge,
# seuil, reserve_integrite }.
static func diagnostiquer_agent(agent: Dictionary, config: Dictionary) -> Dictionary:
	var canal: Dictionary = agent.proprietes.get("etats", {}).get(config.nom_canal_electrocution, {})
	var reserves: Dictionary = agent.proprietes.get("reserves", {})
	return {
		"electrocute": agent.proprietes.get("etats_actifs", []).has(config.nom_etat_electrocute),
		"charge": canal.get("charge", 0.0),
		"seuil": canal.get("seuil", 0.0),
		"reserve_integrite": reserves.get(config.nom_reserve_integrite, {}).get("reserve", 0.0),
	}

static func _teinte_pour_statut(sous_tension: bool, conducteur_actif: bool) -> Color:
	if sous_tension:
		return Color(1.0, 0.85, 0.1)
	if conducteur_actif:
		return Color(0.55, 0.55, 0.6)
	return Color(0.5, 0.35, 0.2)

# GDScript (l'operateur % sur String) ne supporte PAS %e/%g (notation
# scientifique) -- seuls %s/%c/%d/%o/%x/%X/%f sont reconnus, "unsupported
# format character" sinon (constate a l'ecran, chaque tick de _process,
# jamais leve pendant les tests headless : aucun test n'appelle ces
# fonctions de texte). conductivite_electrique s'etend sur ~22 ordres de
# grandeur (1e-15 a 1e8, mouille compris) -- %f seul rendrait soit 0.00
# soit un nombre illisible. Reconstruit la notation scientifique a la main
# avec les seuls specificateurs supportes (%f/%d).
static func _formatter_scientifique(valeur: float) -> String:
	if valeur == 0.0:
		return "0.00e+00"
	var signe := "-" if valeur < 0.0 else ""
	var v: float = absf(valeur)
	var exposant := int(floor(log(v) / log(10.0)))
	var mantisse: float = v / pow(10.0, exposant)
	if mantisse >= 10.0:
		mantisse /= 10.0
		exposant += 1
	return "%s%.2fe%s%d" % [signe, mantisse, "+" if exposant >= 0 else "-", absi(exposant)]

static func _texte_label_objet(id: String, diag: Dictionary) -> String:
	return "%s\nconductivite=%s\nconducteur=%s\nsous_tension=%s\ncourant=%.2f" % [
		id, _formatter_scientifique(diag.conductivite_effective), diag.conducteur_actif, diag.sous_tension, diag.courant
	]

static func _texte_label_agent(diag: Dictionary) -> String:
	return "colon_test\nelectrocute=%s\ncharge=%.2f/%.2f\nintegrite=%.2f" % [
		diag.electrocute, diag.charge, diag.seuil, diag.reserve_integrite
	]

static func _ligne_generateurs(t: float, actif: bool) -> String:
	return "t=%.1fs generateurs : %s" % [t, "ACTIFS" if actif else "INACTIFS"]

static func _ligne_sous_tension(t: float, id: String, sous_tension: bool, effective: float) -> String:
	return "t=%.1fs %s : sous_tension %s (conductivite=%s)" % [
		t, id, "POSE" if sous_tension else "RETIRE", _formatter_scientifique(effective)
	]

static func _ligne_electrocute(t: float, electrocute: bool, reserve: float) -> String:
	if electrocute:
		return "t=%.1fs colon_test : electrocute (integrite=%.2f)" % [t, reserve]
	return "t=%.1fs colon_test : electrocution terminee, guerison progressive (integrite=%.2f)" % [t, reserve]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_source(source: Dictionary) -> void:
	var id: String = source.id
	var centre := position_affichage(id)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
	label.position = noeud.position - Vector2(10.0, 40.0)
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[id] = label

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := position_affichage(id)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.color = Color(0.2, 0.2, 0.2)
	fond.size = Vector2(TAILLE, HAUTEUR_BARRE)
	fond.position = centre + Vector2(-TAILLE / 2.0, TAILLE / 2.0 + 6.0)
	add_child(fond)
	_barres_fond[id] = fond

	var rempli := ColorRect.new()
	rempli.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rempli.color = Color(1.0, 0.85, 0.1)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 120.0)
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[id] = label

func _creer_rendu_agent() -> void:
	var centre := position_affichage(_agent.id)
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE * 0.6, TAILLE * 0.6)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeud_agent = noeud

	var label := Label.new()
	label.position = noeud.position - Vector2(10.0, 100.0)
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_label_agent = label

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = CENTRE_AFFICHAGE
	camera.zoom = Vector2(ZOOM_AFFICHAGE, ZOOM_AFFICHAGE)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
