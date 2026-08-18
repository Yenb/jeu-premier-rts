extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_mana_conduction.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Chantier « conductivite_
# electrique pour la magie -- canalisation de mana » : rejoue EXACTEMENT le
# patron de scripts/banc_conduction.gd (conducteurs_actifs/propager_tension,
# parcours en largeur depuis une source active, puis flux.gd appele une fois
# par objet energise) sur un domaine DIFFERENT -- un objet conducteur relie a
# une source de mana canalise le mana a ses voisins conducteurs tant que le
# contact dure, exactement comme il canalise le courant.
#
# AUCUN MECANISME DU COEUR TOUCHE, AUCUNE LIGNE EMPRUNTEE PAR APPEL CROISE A
# banc_conduction.gd : flux.gd/etat_effectif.gd/objet.gd restent inchanges,
# ce fichier RECOPIE localement les deux fonctions propres au banc
# (conducteurs_actifs/propager_mana), meme discipline que banc_solubilite.gd
# recopiant banc_humidite.gd/banc_pourriture.gd -- deux bancs jetables ne se
# referencent jamais entre eux. Aucune donnee partagee neuve au-dela de ce
# fichier et de data/banc_mana_conduction.json (jetable, propre au banc) :
# "conductivite_electrique" est DEJA fusionnee dans data/proprietes_immuables_
# composition.json depuis le chantier « conduction electrique -- courant
# continu », reutilisee ici telle quelle -- c'est la SEULE propriete du depot
# qui approche une notion de canalisation, aucune propriete magique n'existe
# encore (voir audit_colonnes_chimique_nucleaire_magie_prealable.md).
#
# LA CANALISATION DU MANA (memes lois que le courant, seuil propre) : un
# objet est CONDUCTEUR_MANA_ACTIF si sa conductivite_electrique EFFECTIVE
# (EtatEffectif.valeur, jamais reimplementee) depasse "seuil_conduction_mana"
# (donnee, VOLONTAIREMENT DIFFERENTE du seuil electrique de banc_conduction.gd
# -- 10.0 S/m ici contre 1.0 S/m la-bas, toujours entre bois/pierre ~1e-15/
# 1e-9 et fer ~1e7, la demonstration ne depend pas de la valeur exacte tant
# qu'elle separe les deux). Un objet est SOUS_MANA si une SOURCE active
# (structurelle, jamais lue par aucun mecanisme du coeur) l'atteint par une
# chaine ININTERROMPUE d'objets conducteur_mana_actif en contact
# (portee_contact) -- calcule CHAQUE TICK par propager_mana (parcours en
# largeur, fonction pure de ce fichier, PAS flux.gd : flux.gd ne sait pas
# propager de proche en proche, il transfere depuis une SOURCE vers toute
# chose RECEPTRICE a portee de CETTE source, jamais receptrice-devient-source
# automatiquement). Un isolant (bois) n'est jamais conducteur_mana_actif : la
# chaine s'arrete net a lui, rien au-dela ne devient jamais sous_mana --
# AUCUNE branche "si bois" nulle part, la loi ne connait que le seuil sur une
# valeur continue.
#
# flux.gd EST ENSUITE APPELE, une fois par objet canalise ce tick, avec un
# EMETTEUR SYNTHETIQUE (position de l'objet lui-meme, taux_flux = facteur_
# conductivite_base * conductivite EFFECTIVE de CET objet) -- meme idiome que
# banc_conduction.gd, transpose au mana : le taux de transfert reste
# proportionnel a la conductivite du RECEPTEUR sans toucher flux.gd, chaque
# objet accumule sa propre reserve "mana" a une vitesse qui LUI est propre.
#
# CE QU'ON DOIT VOIR : un clic gauche bascule TOUTES les sources actives/
# inactives a la fois (meme geste que banc_conduction.gd). Deux rangees :
# fer-bois-fer (le second fer ne recoit jamais de mana, canalise bloquee au
# bois) et fer-fer-fer (les trois se canalisent en chaine -- remplacer le
# bois par du fer fait traverser la rangee entiere). Couper la source arrete
# la canalisation ; la reserve "mana" de chaque objet decroit alors vers zero
# (voir TAUX_DECROISSANCE_MANA plus bas, meme correction que banc_conduction.gd
# -- flux.gd n'a lui-meme aucun geste de decroissance, seul ce pas le fournit).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique sources/objets
#   (Objet.fabriquer pour les objets composes). _unhandled_input bascule
#   toutes les sources au clic gauche. _process appelle UNIQUEMENT avancer()
#   (fonction statique, ci-dessous) puis lit ses resultats pour l'affichage/
#   la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_mana_conduction.gd) : conducteurs_actifs/propager_mana/
#   avancer/basculer_sources/fabriquer_sources/fabriquer_objets/
#   diagnostiquer, plus le texte d'affichage et de log.
#   `position_affichage` est PURE mais hors de ce perimetre de test --
#   purement cosmetique, aucun comportement de jeu n'en depend.

const Objet = preload("res://scripts/objet.gd")
const Flux = preload("res://scripts/flux.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Portee = preload("res://scripts/portee.gd")

const TAILLE := 60.0
const TAILLE_SOURCE := 24.0
const HAUTEUR_BARRE := 8.0
const PROPRIETE_CONDUCTIVITE := "conductivite_electrique"
const MANA_BARRE_MAX := 20.0
# Meme correction que banc_conduction.gd (TAUX_DECROISSANCE_COURANT) : flux.gd
# ne fait qu'ADDITIONNER (voir son en-tete, "ce fichier ne 'donne' rien, il
# transfere selon un nombre"), rien n'y decroit jamais un canal. Sans un geste
# EQUIVALENT ici, la reserve "mana" ne pourrait que monter et saturer pour
# toujours, meme sources coupees. TAUX_DECROISSANCE_MANA fait decroitre
# "mana" SEULEMENT pour un objet qui n'est PLUS canalise ce tick -- jamais
# pendant qu'il conduit.
const TAUX_DECROISSANCE_MANA := 40.0

# DISPOSITION D'AFFICHAGE, purement cosmetique -- separee de la position
# REELLE (Vector3, data/banc_mana_conduction.json, JAMAIS TOUCHEE -- lue par
# propager_mana/Portee.en_portee pour la distance de CONTACT reelle, 90
# unites). Deux rangees espacees de 340 (lignes), quatre colonnes espacees de
# 280 -- memes colonnes pour les deux rangees, afin de comparer visuellement
# bloque et traverse.
const DISPOSITION_AFFICHAGE := {
	"source_bloque": Vector2(0.0, 0.0),
	"fer_bloque_1": Vector2(280.0, 0.0),
	"bois_bloque": Vector2(560.0, 0.0),
	"fer_bloque_2": Vector2(840.0, 0.0),

	"source_traverse": Vector2(0.0, 340.0),
	"fer_traverse_1": Vector2(280.0, 340.0),
	"fer_traverse_2": Vector2(560.0, 340.0),
	"fer_traverse_3": Vector2(840.0, 340.0),
}
const CENTRE_AFFICHAGE := Vector2(420.0, 170.0)
const ZOOM_AFFICHAGE := 0.75
const TAILLE_POLICE_LABEL := 14

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _materiaux: Dictionary = {}
var _sources: Array = []
var _objets: Array = []
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _sous_mana_avant: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_mana_conduction.json")
	_etats = _charger_json("res://data/etats.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_sources = fabriquer_sources(_config.get("sources", []))
	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables)

	for source in _sources:
		_creer_rendu_source(source)
	for objet in _objets:
		_sous_mana_avant[objet.id] = false
		_creer_rendu_objet(objet)
	_poser_camera()

	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		basculer_sources(_sources, _config.propriete_cause)
		var actif: bool = _sources_actives(_sources, _config.propriete_cause)
		print(_ligne_sources(_temps, actif))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var resultat := avancer(_sources, _objets, delta, _config, _etats)

	for objet in _objets:
		var id: String = objet.id
		var sous_mana: bool = objet.proprietes.get(_config.propriete_sous_mana, false)
		if sous_mana != _sous_mana_avant.get(id, false):
			var effective: float = EtatEffectif.valeur(objet, PROPRIETE_CONDUCTIVITE, _etats)
			print(_ligne_sous_mana(_temps, id, sous_mana, effective))
			_sous_mana_avant[id] = sous_mana

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	for source in _sources:
		var actif: bool = source.proprietes.get(_config.propriete_cause, false)
		_noeuds[source.id].color = Color(0.6, 0.2, 0.85) if actif else Color(0.4, 0.4, 0.4)
		_labels[source.id].text = "%s\n%s" % [source.id, "ACTIVE" if actif else "INACTIVE"]

	for objet in _objets:
		var id: String = objet.id
		var diag := diagnostiquer(objet, _config, _etats)
		_noeuds[id].color = _teinte_pour_statut(diag.sous_mana, diag.conducteur_actif)
		var ratio: float = clamp(diag.mana / MANA_BARRE_MAX, 0.0, 1.0)
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio
		_labels[id].text = _texte_label_objet(id, diag)

# ---- Fonctions PURES, testables headless (voir test_banc_mana_conduction.gd) ----

# Rend id -> bool : vrai si la conductivite EFFECTIVE de l'objet depasse
# "seuil_conduction_mana". Un objet sans "conductivite_electrique" (absente
# de sa fiche materiau, ou fabrication sans composition) retombe sur le
# defaut 0.0 de proprietes.get -- jamais conducteur.
static func conducteurs_actifs(objets: Array, etats: Dictionary, seuil_conduction_mana: float) -> Dictionary:
	var actifs: Dictionary = {}
	for objet in objets:
		var effective: float = EtatEffectif.valeur(objet, PROPRIETE_CONDUCTIVITE, etats)
		actifs[objet.id] = effective > seuil_conduction_mana
	return actifs

# Parcours en largeur depuis chaque source ACTIVE (proprietes[propriete_cause]
# vrai), a travers les objets dont conducteurs[id] est vrai, en contact
# (Portee.en_portee). Rend id -> true pour chaque objet ATTEINT -- un objet
# non conducteur n'est jamais ajoute a la frontiere, rien au-dela de lui ne
# peut donc jamais se canaliser (blocage NET, pas une attenuation). Aucune
# source active, ou monde vide : rend {} (chemin mort).
static func propager_mana(sources: Array, objets: Array, conducteurs: Dictionary, portee_contact: float, propriete_cause: String) -> Dictionary:
	var canalises: Dictionary = {}
	var frontiere: Array = []
	for source in sources:
		if source.proprietes.get(propriete_cause, false):
			frontiere.append(source)
	while not frontiere.is_empty():
		var courant: Dictionary = frontiere.pop_back()
		for objet in objets:
			if canalises.has(objet.id):
				continue
			if not conducteurs.get(objet.id, false):
				continue
			if Portee.en_portee(courant.position, objet.position, portee_contact):
				canalises[objet.id] = true
				frontiere.append(objet)
	return canalises

# UN PAS de simulation complet : (1) determine qui conduit et qui est
# canalise ce tick (proprietes.sous_mana/conducteur_mana_actif POSES sur
# chaque objet -- lisibles par l'affichage sans recalcul) ; (2) flux.gd, une
# fois PAR OBJET canalise, avec un emetteur synthetique dont le taux_flux est
# proportionnel a la conductivite EFFECTIVE de CET OBJET ; (3) DECROISSANCE
# (voir TAUX_DECROISSANCE_MANA en-tete) : chaque objet qui N'EST PLUS
# canalise ce tick voit sa reserve "mana" decroitre vers 0, jamais applique a
# un objet encore canalise. Rend { canalises, receveurs } -- memes formes que
# celles deja rendues par Flux.avancer, jamais recalculees ici.
static func avancer(sources: Array, objets: Array, delta: float, config: Dictionary, etats: Dictionary) -> Dictionary:
	var conducteurs := conducteurs_actifs(objets, etats, config.seuil_conduction_mana)
	var canalises := propager_mana(sources, objets, conducteurs, config.portee_contact, config.propriete_cause)
	for objet in objets:
		objet.proprietes[config.propriete_sous_mana] = canalises.has(objet.id)
		objet.proprietes[config.propriete_conducteur] = conducteurs.get(objet.id, false)

	var receveurs: Array = []
	var table_flux := [{"source": config.propriete_sous_mana, "receptrice": config.propriete_conducteur, "cible": config.nom_reserve_mana}]
	for objet in objets:
		if not canalises.has(objet.id):
			continue
		var effective: float = EtatEffectif.valeur(objet, PROPRIETE_CONDUCTIVITE, etats)
		var emetteur := {
			"id": "%s_emetteur" % objet.id,
			"position": objet.position,
			"proprietes": {
				config.propriete_sous_mana: true,
				"taux_flux": config.facteur_conductivite_base * effective,
				"portee_flux": config.portee_contact,
			},
		}
		Flux.avancer([emetteur, objet], table_flux, delta)
		receveurs.append(objet.id)

	for objet in objets:
		if canalises.has(objet.id):
			continue
		var reserves_objet: Dictionary = objet.proprietes.get("reserves", {})
		var canal_mana: Dictionary = reserves_objet.get(config.nom_reserve_mana, {})
		if canal_mana.is_empty():
			continue
		canal_mana["reserve"] = max(0.0, canal_mana.get("reserve", 0.0) - TAUX_DECROISSANCE_MANA * delta)

	return {
		"canalises": canalises.keys(),
		"receveurs": receveurs,
	}

# Position D'ECRAN d'un id (voir DISPOSITION_AFFICHAGE ci-dessus) -- JAMAIS
# la position reelle (Vector3) que lit le jeu. Un id absent de la table (ne
# devrait jamais arriver, les huit ids de data/banc_mana_conduction.json y
# figurent tous) retombe sur l'origine -- chemin mort silencieux, purement
# cosmetique.
static func position_affichage(id: String) -> Vector2:
	return DISPOSITION_AFFICHAGE.get(id, Vector2.ZERO)

static func _sources_actives(sources: Array, propriete_cause: String) -> bool:
	for source in sources:
		if source.proprietes.get(propriete_cause, false):
			return true
	return false

static func basculer_sources(sources: Array, propriete_cause: String) -> void:
	var actif := not _sources_actives(sources, propriete_cause)
	for source in sources:
		source.proprietes[propriete_cause] = actif

# Construit les sources A LA MAIN (Dictionary { id, position, proprietes: {
# <propriete_cause>: false } }, meme patron que banc_conduction.gd -- pas
# Objet.fabriquer, aucune composition physique, ce sont des sources
# abstraites, jamais des conducteurs).
static func fabriquer_sources(declarations: Array) -> Array:
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
# fusionnee -- meme patron que banc_conduction.gd, catalogue LOCAL a une
# entree par id). Une reserve "mana" vide est initialisee pour que le premier
# affichage (avant tout tick) montre 0.0 plutot qu'une absence -- flux.gd la
# creerait de toute facon au premier transfert.
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
		objet.proprietes["reserves"] = {"mana": {"reserve": 0.0}}
		objets.append(objet)
	return objets

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees par
# etat_effectif.gd/flux.gd, ne reimplemente jamais leur loi. Rend { sous_mana,
# conducteur_actif, conductivite_effective, mana }.
static func diagnostiquer(objet: Dictionary, config: Dictionary, etats: Dictionary) -> Dictionary:
	return {
		"sous_mana": objet.proprietes.get(config.propriete_sous_mana, false),
		"conducteur_actif": objet.proprietes.get(config.propriete_conducteur, false),
		"conductivite_effective": EtatEffectif.valeur(objet, PROPRIETE_CONDUCTIVITE, etats),
		"mana": objet.proprietes.get("reserves", {}).get(config.nom_reserve_mana, {}).get("reserve", 0.0),
	}

static func _teinte_pour_statut(sous_mana: bool, conducteur_actif: bool) -> Color:
	if sous_mana:
		return Color(0.7, 0.3, 1.0)
	if conducteur_actif:
		return Color(0.55, 0.55, 0.6)
	return Color(0.5, 0.35, 0.2)

# GDScript (l'operateur % sur String) ne supporte PAS %e/%g (notation
# scientifique) -- voir banc_conduction.gd:_formatter_scientifique, meme
# raison (conductivite_electrique s'etend sur ~22 ordres de grandeur),
# RECOPIEE ici (deux bancs jetables ne se referencent jamais entre eux).
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
	return "%s\nconductivite=%s\nconducteur=%s\nsous_mana=%s\nmana=%.2f" % [
		id, _formatter_scientifique(diag.conductivite_effective), diag.conducteur_actif, diag.sous_mana, diag.mana
	]

static func _ligne_sources(t: float, actif: bool) -> String:
	return "t=%.1fs sources : %s" % [t, "ACTIVES" if actif else "INACTIVES"]

static func _ligne_sous_mana(t: float, id: String, sous_mana: bool, effective: float) -> String:
	return "t=%.1fs %s : sous_mana %s (conductivite=%s)" % [
		t, id, "POSE" if sous_mana else "RETIRE", _formatter_scientifique(effective)
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds et la camera.

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
	rempli.color = Color(0.7, 0.3, 1.0)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 100.0)
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[id] = label

func _poser_camera() -> void:
	var camera := Camera2D.new()
	camera.position = CENTRE_AFFICHAGE
	camera.zoom = Vector2(ZOOM_AFFICHAGE, ZOOM_AFFICHAGE)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
