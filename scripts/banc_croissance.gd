extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_croissance.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier « croissance
# vegetale -- une plante pousse sous la lumiere et l'eau » : compose
# scripts/lumiere.gd (lumiere_locale, lue directement), scripts/charge.gd
# (un canal 'humidite' qui monte tant qu'une source d'eau est a portee) et
# scripts/flux.gd (fait monter une reserve 'maturite'), AUCUN DES TROIS
# TOUCHE.
#
# LA CROISSANCE (flux.gd, jamais modifie) : croissance_max (data/materiaux.json:
# plante_demo, fusionnee via data/proprietes_immuables_composition.json,
# meme patron que biodegradabilite) est une vitesse MAXIMALE -- le taux
# reellement applique est croissance_max * lumiere_locale *
# charge_humidite_normalisee, OU les deux derniers facteurs sont eux-memes
# bornes [0.0, 1.0] (lumiere_locale par lumiere.gd, charge_humidite par
# charge_humidite_normalisee ci-dessous) pour que le produit ne depasse
# JAMAIS croissance_max -- c'est le contrat que son nom porte. flux.gd ne
# connait qu'UN SEUL taux_flux par source (jamais un coefficient par
# receveur) : ce fichier construit donc, CHAQUE TICK et PAR PLANTE, un
# emetteur SYNTHETIQUE dont le taux_flux est ce produit deja calcule --
# MEME IDIOME que banc_conduction.gd (« un appel a Flux.avancer PAR OBJET,
# avec un emetteur synthetique dont le taux_flux est proportionnel a la
# conductivite EFFECTIVE de CET OBJET »), transpose ici a la lumiere et
# l'humidite plutot qu'a la conductivite. flux.gd n'ecrit jamais de plafond
# lui-meme (voir son en-tete, "ce fichier ne 'donne' rien, il transfere") :
# la reserve 'maturite' est donc bornee a 1.0 CE FICHIER, apres chaque appel,
# jamais par flux.gd -- MEME BUG a eviter que celui deja ferme dans
# banc_conduction.gd (reserve 'courant' qui ne pouvait que monter), sauf
# qu'ici le plafond est le comportement VOULU (une plante adulte ne redevient
# jamais graine, voir docs/prototypes.md), pas un bug a corriger par une
# decroissance.
#
# L'HUMIDITE (charge.gd, jamais modifie) : chaque plante porte un canal
# 'humidite' (proprietes.etats.humidite) qui monte tant que la source d'eau
# est a portee (portee_charge, meme mecanisme que banc_charge.gd/
# banc_humidite.gd) et redescend sinon (taux_decroissance). AUCUN marqueur
# 'mouille'/EtatDuree ici (contrairement a banc_humidite.gd) : ce chantier
# n'a besoin que de la charge elle-meme, jamais d'un etat seche
# progressivement -- 'poser' reste donc {} (vide), charge.gd bascule un
# 'franchissement' en interne mais ce fichier ne le lit jamais, seule la
# VALEUR de la charge (normalisee par son propre seuil) importe.
# charge_humidite_normalisee(canal) = clamp(charge/seuil, 0.0, 1.0) --
# JAMAIS la charge brute (non bornee au-dessus par charge.gd, voir son
# en-tete) : lue brute, une exposition prolongee ferait grimper le taux de
# croissance sans borne, violant le contrat "croissance_max = vitesse
# MAXIMALE".
#
# LA LUMIERE (lumiere.gd, jamais modifie) : lue DIRECTEMENT via
# Lumiere.locale(position, sources, catalogue).intensite -- jamais a
# travers un flux.gd intermediaire (contrairement a l'eau) : docs/design.md,
# « Exemple travaille : la croissance vegetale » decrit deja la lumiere
# comme une composante LUE, la biomasse comme une reserve qui COMPOSE les
# deux, jamais alimentee directement par une source de flux.gd pour la
# lumiere elle-meme.
#
# DEUX SOURCES INDEPENDANTES, TOGGLABLES SEPAREMENT (contrairement a
# banc_photodegradation.gd/banc_humidite.gd, qui n'ont chacun qu'UNE seule
# source a basculer) : clic GAUCHE bascule la lumiere (meme geste que
# banc_photodegradation.gd), clic DROIT bascule l'eau (meme geste que
# banc_humidite.gd, applique a un second bouton -- meme patron deja utilise
# pour deux gestes distincts que banc_controle.gd, "clic gauche deplace...
# clic droit pose un feu").
#
# TROIS PLANTES, MEME croissance_max (data/banc_croissance.json, toutes
# plante_demo) -- seule leur POSITION relative aux deux sources explique la
# divergence observee (meme discipline que bois_soleil/bois_noir dans
# banc_photodegradation.json) : plante_1 recoit les deux (pousse),
# plante_2 recoit la lumiere seule (stagne), plante_3 recoit l'eau seule
# (stagne). La comparaison "croissance_max haute pousse plus vite que basse"
# est verrouillee par un test UNITAIRE de taux_croissance() (voir
# test_banc_croissance.gd), pas par ce banc -- les trois plantes de la scene
# partagent volontairement la meme valeur, seule la lumiere/l'eau varie ici.
#
# LIMITE STRICTE : ce fichier, ses donnees et ses tests sont le SEUL
# perimetre au-dela de deux lignes de donnee (materiau plante_demo,
# proprietes_immuables_composition.json:croissance_max) -- lumiere.gd/
# charge.gd/flux.gd/objet.gd restent EXACTEMENT ceux deja verrouilles par
# leurs propres tests, aucun n'est touche par ce chantier.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees et fabrique les trois plantes.
#   _unhandled_input bascule lumiere (clic gauche) ou eau (clic droit).
#   _process appelle UNIQUEMENT avancer() (fonction statique) puis lit ses
#   resultats pour l'affichage/la console -- jamais un calcul refait ici.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_croissance.gd) : charge_humidite_normalisee/taux_croissance/
#   avancer/basculer/fabriquer_plantes/diagnostiquer, plus le texte
#   d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Charge = preload("res://scripts/charge.gd")
const Flux = preload("res://scripts/flux.gd")
const Lumiere = preload("res://scripts/lumiere.gd")

const TAILLE := 50.0
const HAUTEUR_BARRE := 8.0
const TAILLE_SOURCE := 30.0

var _config: Dictionary = {}
var _catalogue_lumiere: Dictionary = {}
var _materiaux: Dictionary = {}
var _source_lumiere: Dictionary = {}
var _source_eau: Dictionary = {}
var _lumiere_active: bool = true
var _eau_active: bool = true
var _plantes: Array = []
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_lumiere: ColorRect
var _noeud_eau: ColorRect
var _croissance_active_avant: Dictionary = {}
var _adulte_avant: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_croissance.json")
	_catalogue_lumiere = _charger_json("res://data/lumiere.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_source_lumiere = _lire_source_lumiere(_config.source_lumiere)
	_source_eau = _lire_source_eau(_config.source_eau)
	_plantes = fabriquer_plantes(_config.get("plantes", []), _materiaux, proprietes_immuables, _config)

	for plante in _plantes:
		_croissance_active_avant[plante.id] = false
		_adulte_avant[plante.id] = false
		_creer_rendu_plante(plante)
	_creer_rendu_source_lumiere()
	_creer_rendu_source_eau()
	_poser_camera()

	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_lumiere_active = basculer(_lumiere_active)
		print(_ligne_source(_temps, "lumiere", _lumiere_active))
		_rafraichir_tout()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_eau_active = basculer(_eau_active)
		print(_ligne_source(_temps, "eau", _eau_active))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var diag := avancer(_plantes, _source_lumiere, _lumiere_active, _source_eau, _eau_active, delta, _config, _catalogue_lumiere)

	for plante in _plantes:
		var id: String = plante.id
		var d: Dictionary = diag[id]
		var actif: bool = d.taux > 0.0001
		if actif != _croissance_active_avant.get(id, false):
			print(_ligne_croissance(_temps, id, actif, d))
			_croissance_active_avant[id] = actif
		var adulte: bool = d.maturite >= 1.0
		if adulte and not _adulte_avant.get(id, false):
			print(_ligne_adulte(_temps, id))
			_adulte_avant[id] = true

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	var sources_lumiere: Array = [_source_lumiere] if _lumiere_active else []
	for plante in _plantes:
		var id: String = plante.id
		var lumiere_locale: float = Lumiere.locale(plante.position, sources_lumiere, _catalogue_lumiere).intensite
		var diag := diagnostiquer(plante, _config, lumiere_locale)
		_labels[id].text = _texte_label(id, diag)
		var ratio: float = clamp(diag.maturite, 0.0, 1.0)
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio
		_noeuds[id].color = _teinte_pour_maturite(diag.maturite)
	_noeud_lumiere.color = Color(0.95, 0.75, 0.15) if _lumiere_active else Color(0.35, 0.35, 0.35)
	_noeud_eau.color = Color(0.2, 0.55, 0.95) if _eau_active else Color(0.35, 0.35, 0.35)

# ---- Fonctions PURES, testables headless (voir test_banc_croissance.gd) ----

# clamp(charge/seuil, 0.0, 1.0) -- JAMAIS la charge brute (charge.gd ne la
# borne qu'a 0.0 en bas, jamais au-dessus, voir son en-tete) : un facteur
# non borne violerait le contrat "croissance_max = vitesse MAXIMALE" (voir
# en-tete du fichier). seuil <= 0.0 : repli binaire (1.0 si une charge
# positive existe deja, 0.0 sinon), jamais une division par zero.
static func charge_humidite_normalisee(canal: Dictionary) -> float:
	var charge: float = canal.get("charge", 0.0)
	var seuil: float = canal.get("seuil", 0.0)
	if seuil <= 0.0:
		return 1.0 if charge > 0.0 else 0.0
	return clamp(charge / seuil, 0.0, 1.0)

# Simple multiplication -- aucun clamp ici (les trois facteurs recus sont
# deja bornes par leurs propres lecteurs, voir en-tete), fonction separee
# uniquement pour rester testable seule (voir "croissance_max haute pousse
# plus vite que basse" dans test_banc_croissance.gd).
static func taux_croissance(croissance_max: float, lumiere_locale: float, charge_humidite: float) -> float:
	return croissance_max * lumiere_locale * charge_humidite

static func basculer(actif: bool) -> bool:
	return not actif

# UN PAS de simulation complet. (1) Charge.avancer (NON TOUCHE) une seule
# fois pour toutes les plantes -- l'eau ne module aucun coefficient par
# receveur ici (contrairement a banc_humidite.gd), toutes les plantes
# recoivent le meme poids de cause, seule leur PORTEE au canal (identique,
# data/banc_croissance.json) et leur DISTANCE a la source les separent.
# (2) pour chaque plante : lumiere_locale lue directement (Lumiere.locale,
# NON TOUCHE), charge d'humidite normalisee, taux = produit des trois,
# emetteur flux.gd synthetique CE TICK avec ce taux, Flux.avancer (NON
# TOUCHE) sur [emetteur, plante] seuls -- puis la reserve 'maturite' est
# bornee a 1.0 (flux.gd ne borne jamais rien lui-meme, voir en-tete).
# Rend id -> { lumiere_locale, charge_humidite, taux, maturite }.
static func avancer(
	plantes: Array,
	source_lumiere: Dictionary,
	lumiere_active: bool,
	source_eau: Dictionary,
	eau_active: bool,
	delta: float,
	config: Dictionary,
	catalogue_lumiere: Dictionary,
) -> Dictionary:
	var sources_lumiere: Array = [source_lumiere] if lumiere_active else []
	var causes_eau: Array = [{"position": source_eau.position}] if eau_active else []
	Charge.avancer(plantes, causes_eau, delta)

	var table_flux := [{
		"source": config.propriete_source_croissance,
		"receptrice": config.propriete_receptrice_croissance,
		"cible": config.nom_reserve_maturite,
	}]

	var diag: Dictionary = {}
	for plante in plantes:
		var lumiere_locale: float = Lumiere.locale(plante.position, sources_lumiere, catalogue_lumiere).intensite
		var canal: Dictionary = plante.proprietes.get("etats", {}).get(config.nom_canal_humidite, {})
		var charge_h := charge_humidite_normalisee(canal)
		var croissance_max: float = plante.proprietes.get(config.propriete_croissance_max, 0.0)
		var taux := taux_croissance(croissance_max, lumiere_locale, charge_h)

		var emetteur := {
			"id": "%s_emetteur_croissance" % plante.id,
			"position": plante.position,
			"proprietes": {
				config.propriete_source_croissance: true,
				"taux_flux": taux,
				"portee_flux": config.portee_flux_croissance,
			},
		}
		Flux.avancer([emetteur, plante], table_flux, delta)

		var reserves: Dictionary = plante.proprietes.get("reserves", {})
		var canal_maturite: Dictionary = reserves.get(config.nom_reserve_maturite, {})
		if not canal_maturite.is_empty():
			canal_maturite["reserve"] = min(1.0, canal_maturite.get("reserve", 0.0))

		diag[plante.id] = {
			"lumiere_locale": lumiere_locale,
			"charge_humidite": charge_h,
			"taux": taux,
			"maturite": canal_maturite.get("reserve", 0.0),
		}
	return diag

# Construit les plantes via Objet.fabriquer (composition fusionnee -- meme
# patron que banc_photodegradation.gd/banc_humidite.gd, catalogue LOCAL,
# une entree par id, la cle "composition" seule). Chaque plante recoit
# ENSUITE son propre canal d'humidite (duplique, jamais partage), sa propre
# reserve 'maturite' (demarre a 0.0) et le marqueur receptrice de
# croissance.
static func fabriquer_plantes(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, config: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var plantes: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var plante := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		if plante.is_empty():
			continue
		plante.proprietes[config.propriete_receptrice_croissance] = true
		plante.proprietes["etats"] = {config.nom_canal_humidite: config.canal_humidite_defaut.duplicate(true)}
		plante.proprietes["reserves"] = {config.nom_reserve_maturite: {"reserve": 0.0}}
		plantes.append(plante)
	return plantes

static func _lire_source_lumiere(decl: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	return {
		"position": Vector3(pos[0], pos[1], pos[2]),
		"rayon": decl.rayon,
		"intensite": decl.intensite,
		"temperature_couleur": decl.get("temperature_couleur", 0.0),
		"force": decl.force,
	}

static func _lire_source_eau(decl: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	return {"id": decl.get("id", "source_eau"), "position": Vector3(pos[0], pos[1], pos[2])}

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees
# par charge.gd/flux.gd/lumiere.gd, ne reimplemente jamais leur loi (meme
# doctrine que les autres bancs). Rend { croissance_max, lumiere_locale,
# charge_humidite, maturite }.
static func diagnostiquer(plante: Dictionary, config: Dictionary, lumiere_locale: float) -> Dictionary:
	var canal: Dictionary = plante.proprietes.get("etats", {}).get(config.nom_canal_humidite, {})
	var reserves: Dictionary = plante.proprietes.get("reserves", {})
	var canal_maturite: Dictionary = reserves.get(config.nom_reserve_maturite, {})
	return {
		"croissance_max": plante.proprietes.get(config.propriete_croissance_max, 0.0),
		"lumiere_locale": lumiere_locale,
		"charge_humidite": charge_humidite_normalisee(canal),
		"maturite": canal_maturite.get("reserve", 0.0),
	}

static func _teinte_pour_maturite(maturite: float) -> Color:
	return Color(0.35, 0.25, 0.1).lerp(Color(0.15, 0.75, 0.2), clamp(maturite, 0.0, 1.0))

static func _texte_label(id: String, diag: Dictionary) -> String:
	return "%s\ncroissance_max=%.2f\nlumiere_locale=%.2f\ncharge_humidite=%.2f\nmaturite=%.2f" % [
		id, diag.croissance_max, diag.lumiere_locale, diag.charge_humidite, diag.maturite
	]

static func _ligne_source(t: float, nom: String, actif: bool) -> String:
	return "t=%.1fs %s : %s" % [t, nom, "ACTIVE" if actif else "COUPEE"]

static func _ligne_croissance(t: float, id: String, actif: bool, d: Dictionary) -> String:
	if actif:
		return "t=%.1fs %s : croissance ACTIVE (taux=%.3f, lumiere=%.2f, humidite=%.2f)" % [t, id, d.taux, d.lumiere_locale, d.charge_humidite]
	return "t=%.1fs %s : croissance ARRETEE (lumiere=%.2f, humidite=%.2f)" % [t, id, d.lumiere_locale, d.charge_humidite]

static func _ligne_adulte(t: float, id: String) -> String:
	return "t=%.1fs %s : maturite atteinte (adulte)" % [t, id]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_plante(plante: Dictionary) -> void:
	var id: String = plante.id
	var centre := Vector2(plante.position.x, plante.position.y)

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
	rempli.color = Color(0.15, 0.75, 0.2)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0 + 20.0, TAILLE / 2.0 + 100.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_source_lumiere() -> void:
	_noeud_lumiere = ColorRect.new()
	_noeud_lumiere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_lumiere.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	_noeud_lumiere.position = Vector2(_source_lumiere.position.x, _source_lumiere.position.y) - _noeud_lumiere.size / 2.0
	add_child(_noeud_lumiere)

func _creer_rendu_source_eau() -> void:
	_noeud_eau = ColorRect.new()
	_noeud_eau.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_eau.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	_noeud_eau.position = Vector2(_source_eau.position.x, _source_eau.position.y) - _noeud_eau.size / 2.0
	add_child(_noeud_eau)

func _poser_camera() -> void:
	var config_camera: Dictionary = _config.camera
	var pos: Array = config_camera.position
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(config_camera.zoom, config_camera.zoom)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
