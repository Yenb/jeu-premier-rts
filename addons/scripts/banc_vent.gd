extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_vent.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Existe pour VOIR scripts/vent.gd (ferme et prouve hors domaine par
# test_vent.gd) moduler la PORTEE de l'odorat (scripts/perception.gd,
# chantier "vent") -- PREMIERE DEMONSTRATION REELLE. JETABLE PAR DEFINITION.
#
# CE QU'IL DOIT MONTRER : un "nez" (percepteur minimal, canal odorat SEUL --
# aucune decision, aucun pipeline, meme famille que banc_deformation.gd/
# banc_etat_effectif.gd) immobile au centre ; N sources d'odeur disposees en
# CERCLE A DISTANCE EGALE autour de lui (positions_en_cercle, calculees depuis
# data/banc_vent.json:sources.nombre/rayon, jamais ecrites a la main) --
# chacune un carre qui change de couleur selon qu'elle est CAPTEE ce tick ou
# non. Le vent REEL (data/vent.json, catalogue PARTAGE, jamais surcharge ni
# mute ici) tourne au fil du temps (variation lente) et souffle en rafales
# (force) : l'ENSEMBLE des sources capturees pivote avec lui, visible a
# l'ecran sans lire la console. Une fleche (Line2D) pointe la direction du
# vent, sa longueur suit sa force (echelle et plafond en donnee). Trois
# valeurs affichees en PERMANENCE (CanvasLayer, patron banc_champ.gd) :
# direction (angle en degres), force, et portee effective de l'odorat DANS LE
# SENS DU VENT (Vent.facteur_directionnel, jamais reimplementee) -- plus, a
# titre de contraste, la portee CONTRE le vent. Trace console : un rapport
# periodique (intervalle en donnee) plus une ligne A CHAQUE CHANGEMENT de
# capture d'une source (jamais par tick), meme discipline que
# banc_p1.gd/banc_charge.gd.
#
# PORTEE VOLONTAIREMENT LIMITEE (meme discipline que banc_deformation.gd) : ce
# banc ne route RIEN par attaches.gd/proximite.gd/jugement.gd/dominance.gd/
# agir.gd -- decider()/agir_et_deplacer() n'existent pas ici. Le "nez" ne
# bouge jamais ; seul le VENT bouge (tourne, rafale). AUCUNE source locale de
# perturbation n'est demontree ICI (limite stricte du chantier, voir
# CLAUDE.md/cadrage) -- la preuve qu'une source locale module le vent dans
# son rayon et pas au-dela vit dans test_vent.gd et test_perception.gd,
# chemin dedie, pas dans ce banc.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge data/banc_vent.json (jetable, propre a ce
#   banc) et data/vent.json/data/canaux.json (catalogues PARTAGES, reels,
#   jamais mutes). _process avance _temps_ecoule, appelle Perception.percevoir
#   sur le "nez", redessine chaque source (couleur) et la fleche de vent, met
#   a jour le label, imprime le rapport periodique et les changements de
#   capture.
# - Fonctions statiques (pures, testables headless, voir test_banc_vent.gd) :
#   positions_en_cercle, fabriquer_nez, ids_captes, couleur_pour_capture,
#   changements_de_capture, texte_vent.

const Perception = preload("res://scripts/perception.gd")
const Vent = preload("res://scripts/vent.gd")
const Monde = preload("res://scripts/monde.gd")

const TAILLE_NEZ := 26.0
const TAILLE_SOURCE := 20.0
const LARGEUR_FLECHE := 4.0
const ZOOM_CAMERA := 1.0

var _donnees: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _catalogue_vent: Dictionary = {}
var _monde := Monde.new()
var _nez: Dictionary = {}
var _sources: Array = []
var _noeuds_sources: Dictionary = {}
var _fleche_vent: Line2D
var _label: Label
var _captures_precedentes: Dictionary = {}
var _temps_ecoule := 0.0
var _prochain_print := 0.0
var _intervalle_print := 2.0
var _couleur_captee := Color(0.95, 0.6, 0.1)
var _couleur_non_captee := Color(0.4, 0.4, 0.45)

func _ready() -> void:
	_donnees = _charger_json("res://data/banc_vent.json")
	_catalogue_canaux = _charger_json("res://data/canaux.json")
	_catalogue_vent = _charger_json("res://data/vent.json")
	_intervalle_print = _donnees.get("intervalle_print", 2.0)
	_couleur_captee = _couleur_depuis_array(_donnees.get("couleur_captee", [0.95, 0.6, 0.1]))
	_couleur_non_captee = _couleur_depuis_array(_donnees.get("couleur_non_captee", [0.4, 0.4, 0.45]))

	var decl_nez: Dictionary = _donnees.get("nez", {})
	var pos_nez: Array = decl_nez.get("position", [0.0, 0.0, 0.0])
	_nez = fabriquer_nez(Vector3(pos_nez[0], pos_nez[1], pos_nez[2]), decl_nez.get("portee_odorat", 250.0))
	_monde.ajouter(_nez, "nez", _nez.position)

	var decl_sources: Dictionary = _donnees.get("sources", {})
	var positions := positions_en_cercle(_nez.position, decl_sources.get("rayon", 300.0), decl_sources.get("nombre", 8))
	for i in positions.size():
		var id := "odeur_%d" % i
		var source := {"id": id, "position": positions[i], "proprietes": {}}
		_monde.ajouter(source, "odeur", source.position)
		_sources.append(source)
		_captures_precedentes[id] = false

	_dessiner_carre(_nez.position, TAILLE_NEZ, _couleur_depuis_array(_donnees.get("couleur_nez", [0.2, 0.7, 0.9])))
	for source in _sources:
		_noeuds_sources[source.id] = _dessiner_carre(source.position, TAILLE_SOURCE, _couleur_non_captee)

	_fleche_vent = Line2D.new()
	_fleche_vent.width = LARGEUR_FLECHE
	_fleche_vent.default_color = _couleur_depuis_array(_donnees.get("couleur_fleche_vent", [0.9, 0.2, 0.9]))
	_fleche_vent.add_point(Vector2.ZERO)
	_fleche_vent.add_point(Vector2.ZERO)
	add_child(_fleche_vent)

	# CanvasLayer : le Label reste fixe a l'ecran, jamais transforme par la
	# Camera2D -- patron HUD deja etabli par banc_champ.gd.
	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label = Label.new()
	_label.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label)

	var camera := Camera2D.new()
	camera.position = Vector2(_nez.position.x, _nez.position.y)
	camera.zoom = Vector2(ZOOM_CAMERA, ZOOM_CAMERA)
	camera.enabled = true
	add_child(camera)

func _process(delta: float) -> void:
	_temps_ecoule += delta

	var perceptions := Perception.percevoir(_nez, _monde, _catalogue_canaux, _catalogue_vent, _temps_ecoule, [])
	var captes := ids_captes(perceptions)
	var captures_courantes: Dictionary = {}
	for source in _sources:
		captures_courantes[source.id] = captes.has(source.id)

	for changement in changements_de_capture(_captures_precedentes, captures_courantes):
		var noeud: ColorRect = _noeuds_sources[changement.id]
		noeud.color = couleur_pour_capture(changement.captee, _couleur_captee, _couleur_non_captee)
		print("t=%.1f %s : %s" % [_temps_ecoule, changement.id, "captee" if changement.captee else "perdue"])
	_captures_precedentes = captures_courantes

	var vecteur_vent: Vector3 = Vent.vecteur(_nez.position, _temps_ecoule, _catalogue_vent, [])
	_redessiner_fleche(vecteur_vent)

	var portee_odorat: float = _nez.proprietes.canaux_config.odorat.portee
	var portee_aval := portee_odorat
	var portee_amont := portee_odorat
	if vecteur_vent.length() > 0.0001:
		var direction := vecteur_vent.normalized()
		portee_aval = portee_odorat * Vent.facteur_directionnel(vecteur_vent, direction, _catalogue_vent)
		portee_amont = portee_odorat * Vent.facteur_directionnel(vecteur_vent, -direction, _catalogue_vent)
	var texte := texte_vent(vecteur_vent, portee_aval, portee_amont)
	_label.text = texte

	if _temps_ecoule >= _prochain_print:
		_prochain_print = _temps_ecoule + _intervalle_print
		print("t=%.1f %s" % [_temps_ecoule, texte])

# ---- Fonctions statiques, pures, testables ----

# N positions egalement espacees sur un cercle de rayon donne autour de
# `centre`, dans le plan XY (z inchangee) -- meme convention que les
# positions de banc en Vector3(x,y,0). `nombre` <= 0 rend un Array vide,
# jamais une erreur (point neutre legitime : aucune source a placer).
static func positions_en_cercle(centre: Vector3, rayon: float, nombre: int) -> Array:
	var resultat: Array = []
	if nombre <= 0:
		return resultat
	for i in nombre:
		var angle: float = TAU * i / nombre
		resultat.append(centre + Vector3(rayon * cos(angle), rayon * sin(angle), 0.0))
	return resultat

# Le "nez" : un percepteur minimal, canal odorat SEUL -- aucun forme/attaches/
# poids_verbes, ce banc ne route rien par agir.gd.
static func fabriquer_nez(position: Vector3, portee_odorat: float) -> Dictionary:
	return {
		"id": "nez",
		"position": position,
		"proprietes": {
			"canaux": ["odorat"],
			"canaux_config": {"odorat": {"portee": portee_odorat, "sensibilite": 1.0, "seuil": 0.0}},
		},
	}

static func ids_captes(perceptions: Array) -> Array:
	var resultat: Array = []
	for entree in perceptions:
		resultat.append(entree.chose.id)
	return resultat

static func couleur_pour_capture(captee: bool, couleur_captee: Color, couleur_non_captee: Color) -> Color:
	return couleur_captee if captee else couleur_non_captee

# Rend UNIQUEMENT les ids dont l'etat de capture a change entre deux tours --
# jamais un print par tick, meme discipline que banc_p1.gd/banc_charge.gd.
static func changements_de_capture(precedent: Dictionary, courant: Dictionary) -> Array:
	var resultat: Array = []
	for id in courant:
		if precedent.get(id, false) != courant[id]:
			resultat.append({"id": id, "captee": courant[id]})
	return resultat

static func texte_vent(vecteur_vent: Vector3, portee_aval: float, portee_amont: float) -> String:
	var force: float = vecteur_vent.length()
	var angle_deg: float = 0.0
	if force > 0.0001:
		angle_deg = rad_to_deg(atan2(vecteur_vent.y, vecteur_vent.x))
	return "vent : direction=%.1f deg force=%.2f | portee odorat aval=%.1f amont=%.1f" % [angle_deg, force, portee_aval, portee_amont]

# ---- Rendu, jetable ----

func _redessiner_fleche(vecteur_vent: Vector3) -> void:
	var echelle: float = _donnees.get("echelle_affichage_vent", 8.0)
	var longueur_max: float = _donnees.get("longueur_fleche_max", 200.0)
	var longueur: float = clamp(vecteur_vent.length() * echelle, 0.0, longueur_max)
	var direction2d := Vector2.RIGHT
	if vecteur_vent.length() > 0.0001:
		direction2d = Vector2(vecteur_vent.x, vecteur_vent.y).normalized()
	var origine := Vector2(_nez.position.x, _nez.position.y)
	_fleche_vent.set_point_position(0, origine)
	_fleche_vent.set_point_position(1, origine + direction2d * longueur)

func _dessiner_carre(position3: Vector3, taille: float, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	carre.position = Vector2(position3.x, position3.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _couleur_depuis_array(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
