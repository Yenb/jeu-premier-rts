extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_photodegradation.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1). Chantier
# « photodegradation -- le soleil degrade la matiere organique morte » :
# compose scripts/lumiere.gd et scripts/depense.gd, AUCUN DES DEUX TOUCHE.
# Physique visee (voir docs/design.md, « Les proprietes materiau comme
# noeuds de connexion transversaux ») : les UV cassent directement les
# macromolecules organiques et accelerent leur decomposition -- ce banc ne
# montre QUE cet effet, isole de tout autre phenomene (pas d'humidite, pas
# de feu, pas de pourriture microbienne par charge.gd -- voir
# banc_pourriture.gd pour cet autre mecanisme, jamais compose ici).
#
# UN SEUL geste mecanique, ecrit CHAQUE TICK sur la reserve 'integrite'
# (depense.gd n'a lui-meme aucun coefficient de lumiere) :
#   cout_base_eff = biodegradabilite * facteur_uv_degradation * lumiere_locale
# Puis un unique appel a Depense.avancer -- depense.gd fait tout le reste
# (bornage a 0.0, inchange).
#
# TROIS OBJETS : bois_soleil/pierre_soleil sont dans le rayon de la source
# 'soleil' (scripts/lumiere.gd), bois_noir en est hors de portee EN
# PERMANENCE, quel que soit l'etat du soleil -- c'est la POSITION qui
# decide qui peut recevoir de la lumiere, jamais un drapeau par objet.
# 'pierre_soleil' porte biodegradabilite=0.0 (data/materiaux.json) :
# recoit la MEME lumiere que bois_soleil, ne perd jamais d'integrite --
# preuve que biodegradabilite 0.0 neutralise l'effet quelle que soit
# l'exposition.
#
# LE SOLEIL EST TOGGLABLE AU CLIC (contrairement a banc_uv_degradation.gd,
# ou la source lumineuse reste fixe) : _soleil_actif est un booleen PORTE
# PAR CE NOEUD, jamais par lumiere.gd -- un clic gauche l'inverse. La
# bascule s'exprime uniquement par QUELLES sources sont passees a
# Lumiere.locale (liste [soleil] si actif, [] sinon) -- avancer() lui-meme
# ne connait aucune notion de "toggle", seulement une liste de sources
# recue en parametre, meme patron que lumiere.gd/vent.gd/temperature.gd.
# Soleil coupe -> lumiere_locale retombe sur l'ambiante (0.0,
# data/lumiere.json:defaut.ambiante.intensite) partout -> cout_base_eff
# retombe a 0.0 -> aucune reserve ne bouge plus, sans aucune branche
# speciale.
#
# LIMITE STRICTE : ce fichier, ses donnees et ses tests sont le SEUL
# perimetre -- lumiere.gd/depense.gd/objet.gd restent exactement ceux deja
# verrouilles par leurs propres tests, aucun n'est touche par ce chantier.
# 'biodegradabilite' (data/proprietes_immuables_composition.json) est
# DEJA fusionnee (chantier concurrent « UV et biodegradation »,
# scripts/banc_uv_degradation.gd) -- rien a ajouter ici.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit les trois objets (Objet.fabriquer) et
#   la source solaire. _unhandled_input bascule _soleil_actif au clic
#   gauche. _process appelle UNIQUEMENT avancer() (fonction statique) puis
#   lit ses resultats pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_photodegradation.gd) : basculer_soleil/avancer/
#   fabriquer_objets/diagnostiquer, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Depense = preload("res://scripts/depense.gd")
const Lumiere = preload("res://scripts/lumiere.gd")

const TAILLE := 60.0
const HAUTEUR_BARRE := 8.0
const TAILLE_SOLEIL := 40.0

var _config: Dictionary = {}
var _catalogue_lumiere: Dictionary = {}
var _materiaux: Dictionary = {}
var _soleil: Dictionary = {}
var _soleil_actif: bool = true
var _objets: Array = []
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_soleil: ColorRect
var _temps: float = 0.0
var _prochain_print: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_photodegradation.json")
	_catalogue_lumiere = _charger_json("res://data/lumiere.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])

	_soleil = _source_lumiere(_config.soleil)
	_objets = fabriquer_objets(_config.get("objets", []), _materiaux, proprietes_immuables, _config)
	for objet in _objets:
		_creer_rendu_objet(objet)
	_creer_rendu_soleil()
	_poser_camera()

	print(_ligne_soleil(0.0, _soleil_actif))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_soleil_actif = basculer_soleil(_soleil_actif)
		print(_ligne_soleil(_temps, _soleil_actif))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	var sources: Array = [_soleil] if _soleil_actif else []
	var resultat := avancer(_objets, sources, delta, _config, _catalogue_lumiere)

	if _temps >= _prochain_print:
		_prochain_print += float(_config.intervalle_print)
		for objet in _objets:
			print(_ligne_rapport(_temps, objet, diagnostiquer(objet, _config, resultat.lumieres.get(objet.id, 0.0))))

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	var sources: Array = [_soleil] if _soleil_actif else []
	for objet in _objets:
		var id: String = objet.id
		var lumiere_locale: float = Lumiere.locale(objet.position, sources, _catalogue_lumiere).intensite
		var diag := diagnostiquer(objet, _config, lumiere_locale)
		_labels[id].text = _texte_label(id, diag)
		var ratio: float = clamp(diag.reserve / diag.reserve_capacite, 0.0, 1.0) if diag.reserve_capacite > 0.0 else 0.0
		_barres_remplies[id].size.x = _barres_fond[id].size.x * ratio
	_noeud_soleil.color = Color(0.95, 0.75, 0.15) if _soleil_actif else Color(0.35, 0.35, 0.35)

# ---- Fonctions PURES, testables headless (voir test_banc_photodegradation.gd) ----

static func basculer_soleil(actif: bool) -> bool:
	return not actif

# UN PAS de simulation complet. Pour chaque objet : lumiere_locale au point
# de l'objet (Lumiere.locale, source recue en parametre -- vide si le
# soleil est coupe, NON TOUCHE), puis ecrit cout_base EFFECTIF sur la
# reserve 'integrite' (biodegradabilite DE CET OBJET x facteur_uv_
# degradation x lumiere_locale). Puis Depense.avancer(objets, delta, {})
# UNE FOIS pour tous (aucun seuils_ref configure sur ce banc -- catalogue
# vide, comportement legitime de depense.gd, voir sa doctrine "seuils_ref"
# facultative -- ce banc montre une decroissance OBSERVEE, jamais une
# transformation terminale). Rend { lumieres: Dictionary id -> lumiere_
# locale, franchis: Array d'id ayant franchi un seuil ce pas -- toujours
# vide sur ce banc, rendu par symetrie avec depense.gd:avancer }.
static func avancer(objets: Array, sources_lumiere: Array, delta: float, config: Dictionary, catalogue_lumiere: Dictionary) -> Dictionary:
	var lumieres: Dictionary = {}
	for objet in objets:
		var lumiere_locale: float = Lumiere.locale(objet.position, sources_lumiere, catalogue_lumiere).intensite
		lumieres[objet.id] = lumiere_locale

		var reserves: Dictionary = objet.proprietes.get("reserves", {})
		if reserves.has(config.nom_reserve_integrite):
			var canal: Dictionary = reserves[config.nom_reserve_integrite]
			var biodegradabilite: float = objet.proprietes.get(config.propriete_biodegradabilite, 0.0)
			canal["cout_base"] = biodegradabilite * float(config.facteur_uv_degradation) * lumiere_locale

	var franchis := Depense.avancer(objets, delta, {})
	return {"lumieres": lumieres, "franchis": franchis}

# Construit les objets via Objet.fabriquer (composition fusionnee -- meme
# patron que banc_pourriture.gd/banc_uv_degradation.gd). Chaque objet
# recoit ENSUITE sa propre reserve 'integrite' (dupliquee, jamais partagee
# entre objets -- tous les objets de ce banc en portent une, contrairement
# a banc_uv_degradation.gd ou seule une partie des objets la recevait).
static func fabriquer_objets(declarations: Array, materiaux: Dictionary, proprietes_immuables: Array, config: Dictionary) -> Array:
	var catalogue: Dictionary = {}
	for decl in declarations:
		catalogue[decl.id] = {"composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), catalogue, materiaux, proprietes_immuables)
		objet.proprietes["reserves"] = {config.nom_reserve_integrite: config.reserve_integrite_defaut.duplicate(true)}
		objets.append(objet)
	return objets

static func _source_lumiere(decl: Dictionary) -> Dictionary:
	var pos: Array = decl.position
	return {
		"position": Vector3(pos[0], pos[1], pos[2]),
		"rayon": decl.rayon,
		"intensite": decl.intensite,
		"temperature_couleur": decl.get("temperature_couleur", 0.0),
		"force": decl.force,
	}

# Diagnostic d'affichage, PUR : lit uniquement des valeurs deja calculees
# par depense.gd, ne reimplemente jamais sa loi (meme doctrine que
# banc_uv_degradation.gd:diagnostiquer). Rend { biodegradabilite,
# lumiere_locale, reserve, reserve_capacite }.
static func diagnostiquer(objet: Dictionary, config: Dictionary, lumiere_locale: float) -> Dictionary:
	var reserves: Dictionary = objet.proprietes.get("reserves", {})
	var canal: Dictionary = reserves.get(config.nom_reserve_integrite, {})
	return {
		"biodegradabilite": objet.proprietes.get(config.propriete_biodegradabilite, 0.0),
		"lumiere_locale": lumiere_locale,
		"reserve": canal.get("reserve", 0.0),
		"reserve_capacite": float(config.reserve_integrite_defaut.reserve),
	}

static func _texte_label(id: String, diag: Dictionary) -> String:
	return "%s\nbiodeg=%.2f\nlumiere_locale=%.2f\nintegrite=%.2f/%.2f" % [id, diag.biodegradabilite, diag.lumiere_locale, diag.reserve, diag.reserve_capacite]

static func _ligne_rapport(t: float, objet: Dictionary, diag: Dictionary) -> String:
	return "t=%.1fs %s : lumiere_locale=%.2f integrite=%.2f/%.2f" % [t, objet.id, diag.lumiere_locale, diag.reserve, diag.reserve_capacite]

static func _ligne_soleil(t: float, actif: bool) -> String:
	return "t=%.1fs soleil : %s" % [t, "ACTIF" if actif else "COUPE"]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.color = Color(0.55, 0.42, 0.28)
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
	rempli.color = Color(0.9, 0.6, 0.15)
	rempli.size = Vector2(0.0, HAUTEUR_BARRE)
	rempli.position = fond.position
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0 + 15.0, TAILLE / 2.0 + 80.0)
	add_child(label)
	_labels[id] = label

func _creer_rendu_soleil() -> void:
	_noeud_soleil = ColorRect.new()
	_noeud_soleil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_soleil.size = Vector2(TAILLE_SOLEIL, TAILLE_SOLEIL)
	_noeud_soleil.position = Vector2(_soleil.position.x, _soleil.position.y) - _noeud_soleil.size / 2.0
	add_child(_noeud_soleil)

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
