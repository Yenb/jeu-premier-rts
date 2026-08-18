extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_point_ignition.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). PREMIERE DEMONSTRATION
# REELLE du chantier "point_ignition" : propagation.gd:delai_ignition gagne
# un TROISIEME gate (temperature vs point_ignition du materiau), en plus du
# proxy d'intensite deja existant (chantier "feu -- inflammabilite
# effective", demontre par banc_inflammabilite.gd) -- LES DEUX FILTRES
# COEXISTENT, ce banc-ci isole VOLONTAIREMENT le nouveau seul ("intensite"
# ne declare que "propriete_point_ignition" -- const INTENSITE plus bas --
# jamais "propriete_intensite"/"seuil_ignition" ; "etats" reste {}). Noms de domaine reels
# (bois/brule/inflammable) -- exception documentee (CLAUDE.md : "un banc
# jetable peut nommer une categorie pour poser une scene d'observation").
#
# JETABLE PAR DEFINITION : aucune regle de jeu ne doit vivre ici, seulement
# du cablage et de la lecture. Tout diagnostic est en fonctions STATIQUES
# testables (diagnostiquer/_teinte_pour_diagnostic/_texte_label/_ligne_pose/
# _ligne_log) -- _process ne fait qu'appeler Temperature.locale (deja le
# mecanisme reel) puis Propagation.avancer (deja le mecanisme reel, gagne
# son 9e parametre facultatif "temperature_locale" par ce chantier),
# jamais recalculer une loi ecrite ailleurs.
#
# CE QU'ON DOIT VOIR : deux objets de MEME matiere (bois, point_ignition
# 300.0), chacun expose en permanence par son propre foyer voisin (meme
# distance, meme delai_propagation -- seule variable : la temperature
# locale). `cible_chaude` se tient dans le rayon d'une source de
# temperature fixe (800 degres, bien au-dessus de 300) et finit par
# s'enflammer normalement, au delai_propagation de base. `cible_froide`,
# hors de ce rayon (temperature ambiante seule, 20 degres, tres en dessous
# de 300), N'ACCUMULE JAMAIS D'EXPOSITION -- bloquee indefiniment par le
# nouveau gate, malgre une inflammabilite et une exposition IDENTIQUES a
# celles de cible_chaude. Chaque objet affiche en permanence son nom, la
# temperature locale a sa position, son point_ignition, son statut, et une
# barre d'exposition/delai_requis. La TEINTE encode le statut : orange qui
# vire au rouge a mesure que l'exposition approche le delai (cible_chaude),
# rouge sature une fois EN FEU, BLEU fixe si bloque par le froid
# (cible_froide) -- jamais la meme couleur que "en feu". La console imprime
# une ligne de POSE par objet au demarrage, puis une ligne A CHAQUE
# CHANGEMENT DE STATUT (jamais par frame), meme discipline que
# banc_inflammabilite.gd.
#
# LIMITE STRICTE (rappel explicite du chantier) : ce fichier cable
# UNIQUEMENT ce banc -- aucun mecanisme neuf, aucune extension du coeur au
# -dela du 9e parametre facultatif deja ajoute a propagation.gd. objet.gd/
# temperature.gd/depense.gd/combustible.gd non touches, non appeles ici
# au-dela de Temperature.locale (deja publique, deja testee).

const Objet = preload("res://scripts/objet.gd")
const Propagation = preload("res://scripts/propagation.gd")
const Temperature = preload("res://scripts/temperature.gd")

const VULNERABILITE := "inflammable"
# Chantier "correction nom en dur point_ignition" : propagation.gd ne fige
# plus "point_ignition", il lit "propriete_point_ignition" dans le
# Dictionary intensite recu. Ce banc isole VOLONTAIREMENT le gate
# thermique du proxy d'intensite (voir en-tete) -- il declare donc ce SEUL
# champ, jamais propriete_intensite/seuil_ignition.
const INTENSITE := {"propriete_point_ignition": "point_ignition"}
const TAILLE := 70.0
const HAUTEUR_BARRE := 10.0

var _monde: Array = []
var _objets: Array = []
var _feux: Array = []
var _menaces: Dictionary = {}
var _catalogue_temperature: Dictionary = {}
var _source_temperature: Dictionary = {}
var _exposition: Dictionary = {}
var _dernier_statut: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _temps: float = 0.0

func _ready() -> void:
	var donnees := _charger_json("res://data/banc_point_ignition.json")
	_menaces = _charger_json("res://data/menaces.json")
	_catalogue_temperature = _charger_json("res://data/temperature.json")
	var materiaux := _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	var delai_base: float = donnees.get("delai_propagation_base", 1.0)
	var portee: float = donnees.get("portee_propagation", 900.0)

	var decl_source: Dictionary = donnees.get("source_temperature", {})
	var pos_source: Array = decl_source.get("position", [0.0, 0.0, 0.0])
	_source_temperature = {
		"position": Vector3(pos_source[0], pos_source[1], pos_source[2]),
		"rayon": decl_source.get("rayon", 150.0),
		"temperature": decl_source.get("temperature", 800.0),
		"force": decl_source.get("force", 1.0),
	}

	for decl_feu in donnees.get("feux", []):
		var pos_feu: Array = decl_feu.position
		var feu := {
			"id": decl_feu.id,
			"position": Vector3(pos_feu[0], pos_feu[1], pos_feu[2]),
			"proprietes": {"brule": true},
		}
		_monde.append(feu)
		_feux.append(feu)

	var declarations: Array = donnees.get("objets", [])
	var catalogue_types: Dictionary = {}
	for decl in declarations:
		catalogue_types[decl.id] = {
			VULNERABILITE: true,
			"portee_propagation": portee,
			"delai_propagation": delai_base,
			"composition": decl.composition,
		}

	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue_types, materiaux, proprietes_immuables)
		if objet.is_empty():
			push_error("banc_point_ignition.gd : fabrication refusee pour '%s'" % decl.id)
			continue
		_monde.append(objet)
		_objets.append(objet)
		_exposition[decl.id] = 0.0
		_creer_rendu_objet(objet)

	for feu in _feux:
		_creer_rendu_feu(feu)
	_creer_rendu_source_temperature()
	_poser_camera()

	for objet in _objets:
		var t_locale: float = Temperature.locale(objet.position, [_source_temperature], _catalogue_temperature)
		print(_ligne_pose(objet.id, t_locale, objet.proprietes.get("point_ignition", 0.0)))
	_rafraichir_tout(0.0, true)

func _process(delta: float) -> void:
	_temps += delta
	var temperature_locale: Dictionary = {}
	for objet in _objets:
		temperature_locale[objet.id] = Temperature.locale(objet.position, [_source_temperature], _catalogue_temperature)
	Propagation.avancer(_monde, _menaces, _exposition, delta, {}, INTENSITE, {}, {}, temperature_locale)
	_rafraichir_tout(_temps, false, temperature_locale)

func _rafraichir_tout(t: float, forcer_log: bool, temperature_locale: Dictionary = {}) -> void:
	for objet in _objets:
		var id: String = objet.id
		var t_locale: float = temperature_locale.get(id, Temperature.locale(objet.position, [_source_temperature], _catalogue_temperature))
		var exposition_actuelle: float = _exposition.get(id, 0.0)
		var diag: Dictionary = diagnostiquer(objet, exposition_actuelle, t_locale, VULNERABILITE, _menaces)
		if forcer_log or diag.statut != _dernier_statut.get(id, ""):
			print(_ligne_log(t, id, t_locale, diag, exposition_actuelle))
			_dernier_statut[id] = diag.statut
		_noeuds[id].color = _teinte_pour_diagnostic(diag, exposition_actuelle)
		var ratio := _ratio_exposition(exposition_actuelle, diag.delai_requis)
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio
		_labels[id].text = _texte_label(id, t_locale, diag, exposition_actuelle)

# ---- Diagnostic, PUR : compose Propagation.delai_ignition (deja publique,
# deja testee) -- ne reimplemente jamais sa loi, seulement sa lecture. Rend
# { statut: "intact" | "expose" | "en_feu" | "bloque_froid", point_ignition:
# float, delai_requis: float }. "intensite" (const INTENSITE ci-dessus) ne
# declare que "propriete_point_ignition", jamais "propriete_intensite"/
# "seuil_ignition" : le proxy d'intensite reste inerte, seul le gate
# temperature agit sur ce banc -- delai_requis < 0.0 ne peut donc venir
# QUE de ce gate.
static func diagnostiquer(chose: Dictionary, exposition_actuelle: float, temperature_locale: float, vulnerabilite: String, menaces: Dictionary) -> Dictionary:
	var menace: String = menaces.get(vulnerabilite, "")
	var point_ignition: float = chose.proprietes.get("point_ignition", 0.0)
	var delai_requis: float = Propagation.delai_ignition(chose, INTENSITE, {}, temperature_locale)
	if chose.proprietes.get(menace, false):
		return {"statut": "en_feu", "point_ignition": point_ignition, "delai_requis": delai_requis}
	if delai_requis < 0.0:
		return {"statut": "bloque_froid", "point_ignition": point_ignition, "delai_requis": delai_requis}
	if exposition_actuelle <= 0.0:
		return {"statut": "intact", "point_ignition": point_ignition, "delai_requis": delai_requis}
	return {"statut": "expose", "point_ignition": point_ignition, "delai_requis": delai_requis}

# ---- Affichage et console, PURS -- lisent un diagnostic deja calcule,
# ne recalculent jamais une valeur de Propagation/Temperature.

static func _teinte_pour_diagnostic(diag: Dictionary, exposition_actuelle: float) -> Color:
	match diag.statut:
		"en_feu":
			return Color(0.75, 0.1, 0.05)
		"bloque_froid":
			return Color(0.15, 0.35, 0.8)
		"expose":
			var ratio: float = _ratio_exposition(exposition_actuelle, diag.delai_requis)
			return Color(0.6 + 0.3 * ratio, 0.35 * (1.0 - ratio), 0.05)
		_:
			return Color(0.5, 0.5, 0.5)

static func _ratio_exposition(exposition: float, delai_requis: float) -> float:
	if delai_requis <= 0.0:
		return 0.0
	return clamp(exposition / delai_requis, 0.0, 1.0)

static func _texte_statut(statut: String) -> String:
	match statut:
		"intact":
			return "INTACT"
		"expose":
			return "EXPOSE"
		"en_feu":
			return "EN FEU"
		"bloque_froid":
			return "BLOQUE (trop froid)"
		_:
			return "?"

static func _texte_label(id: String, temperature_locale: float, diag: Dictionary, exposition_actuelle: float) -> String:
	var delai_texte: String = ("%.2fs" % diag.delai_requis) if diag.delai_requis >= 0.0 else "jamais"
	return "%s\ntemperature_locale=%.1f\npoint_ignition=%.1f\ndelai_requis=%s\n%s\nexposition=%.2fs" % [
		id, temperature_locale, diag.point_ignition, delai_texte, _texte_statut(diag.statut), exposition_actuelle
	]

static func _ligne_pose(id: String, temperature_locale: float, point_ignition: float) -> String:
	return "t=0.0s %s : temperature_locale=%.1f point_ignition=%.1f" % [id, temperature_locale, point_ignition]

static func _ligne_log(t: float, id: String, temperature_locale: float, diag: Dictionary, exposition_actuelle: float) -> String:
	return "t=%.1fs %s : temperature_locale=%.1f point_ignition=%.1f exposition=%.2fs -> %s" % [
		t, id, temperature_locale, diag.point_ignition, exposition_actuelle, _texte_statut(diag.statut)
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y)

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
	rempli.color = Color(0.9, 0.7, 0.1)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 110.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_feu(feu: Dictionary) -> void:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.color = Color(0.95, 0.45, 0.05)
	noeud.size = Vector2(TAILLE * 0.6, TAILLE * 0.6)
	noeud.position = Vector2(feu.position.x, feu.position.y) - noeud.size / 2.0
	add_child(noeud)

	var label := Label.new()
	label.position = noeud.position - Vector2(0.0, 20.0)
	label.text = feu.id
	add_child(label)

func _creer_rendu_source_temperature() -> void:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.color = Color(0.9, 0.2, 0.2, 0.25)
	var rayon: float = _source_temperature.rayon
	noeud.size = Vector2(rayon, rayon) * 2.0
	noeud.position = Vector2(_source_temperature.position.x, _source_temperature.position.y) - noeud.size / 2.0
	add_child(noeud)
	move_child(noeud, 0)

	var label := Label.new()
	label.position = noeud.position + Vector2(4.0, 4.0)
	label.text = "source_temperature (%.0f)" % _source_temperature.temperature
	add_child(label)

func _poser_camera() -> void:
	var centre_x := 0.0
	for objet in _objets:
		centre_x += objet.position.x
	if not _objets.is_empty():
		centre_x /= _objets.size()
	var camera := Camera2D.new()
	camera.position = Vector2(centre_x, 400.0)
	camera.zoom = Vector2(0.6, 0.6)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
