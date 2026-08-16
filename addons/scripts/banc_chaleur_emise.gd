extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_chaleur_emise.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « chaleur_emise -- un feu emet de la chaleur »
# (audit_resistance_impact_produit_prealable.md, Partie B §2/§5/§6) :
# PREMIERE DEMONSTRATION REELLE qu'un objet qui brule emet de la chaleur en
# continu, force proportionnelle a `proprietes.chaleur_emise` (materiau,
# data/materiaux.json, fusionnee a la fabrication via data/
# proprietes_immuables_composition.json).
#
# AUCUN MECANISME DU COEUR TOUCHE : temperature.gd/depense.gd/combustible.gd/
# objet.gd restent inchanges. Ce fichier COMPOSE trois patrons deja fermes :
# - Objet.fabriquer (INCHANGE) -- vrais bois/fer/pierre du catalogue PARTAGE
#   data/materiaux.json, composant "objet_physique" (pour "temperature") et
#   fusionnant "chaleur_emise" comme les autres proprietes immuables (meme
#   patron que banc_foudre.gd:fabriquer_objets). Les deux objets qui brulent
#   recoivent EN PLUS une reserve "combustible" reelle (data/
#   reserve_combustible_composition.json, meme patron que banc_combustible.gd)
#   -- les deux objets froids n'en recoivent jamais.
# - Temperature.avancer (INCHANGE) -- appele CHAQUE TICK avec la liste des
#   sources CONSTRUITES ICI (voir sources_chaleur ci-dessous) : une source
#   par objet qui porte "brule" CE TICK, jamais reconstruite pour un objet
#   qui ne brule plus.
# - Depense.avancer (INCHANGE) -- decremente la reserve "combustible" des
#   deux objets qui brulent ; au seuil "epuisement" (data/
#   seuils_combustible.json, catalogue PARTAGE, INCHANGE), retire "brule"
#   entre autres cles -- l'extinction est donc detectee par depense.gd,
#   jamais par ce fichier, meme patron que banc_combustible.gd.
#
# SOURCES_CHALEUR (fonction PURE, testable, cœur de ce chantier) : pour
# chaque objet qui porte `proprietes.brule == true` CE TICK, construit
# `{ position, rayon: rayon_emission, temperature: temperature_source,
# force: proprietes.get("chaleur_emise", 0.0) }` -- force PROPORTIONNELLE a
# chaleur_emise, jamais un multiplicateur invente. Un objet qui ne brule pas
# n'apparait JAMAIS dans la liste rendue : la source disparait au tick ou
# "brule" est retire (Depense.avancer, ci-dessus), jamais reconstruite au
# tick suivant -- comportement demande par le chantier, obtenu SANS aucune
# memoire d'etat propre a ce fichier (la liste est reconstruite du neant a
# chaque appel, a partir du seul etat courant de `_objets`).
#
# CALIBRATION DU LAYOUT (voir data/banc_chaleur_emise.json._note) : les deux
# objets froids sont a la MEME distance de leur propre foyer, pour que la
# comparaison bois/fer soit propre (seule chaleur_emise diverge, tout le
# reste -- distance, rayon, temperature_source -- est identique) ; les deux
# foyers sont assez eloignes l'un de l'autre pour qu'aucune contamination
# croisee ne brouille la lecture.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge les donnees/catalogues partages et
#   fabrique les quatre objets. _process construit les sources du tick,
#   avance la temperature puis la combustion, detecte l'extinction, imprime
#   un rapport periodique, redessine.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_chaleur_emise.gd) : fabriquer_objets/sources_chaleur, plus le
#   texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Temperature = preload("res://scripts/temperature.gd")
const Depense = preload("res://scripts/depense.gd")

const TAILLE := 60.0
const HAUTEUR_BARRE := 8.0

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _proprietes_immuables: Array = []
var _catalogue_temperature: Dictionary = {}
var _seuils_combustible: Dictionary = {}
var _objets: Array = []
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _eteints: Dictionary = {}
var _temps: float = 0.0
var _prochain_print := 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_chaleur_emise.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_proprietes_immuables = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var objet_physique: Dictionary = _charger_json("res://data/types.json").get("objet_physique", {})
	_catalogue_temperature = _charger_json("res://data/temperature.json")
	_seuils_combustible = _charger_json("res://data/seuils_combustible.json")
	var reserve_combustible: Dictionary = _charger_json("res://data/reserve_combustible_composition.json")

	_objets = fabriquer_objets(_config.get("objets", []), objet_physique, _materiaux, _proprietes_immuables, reserve_combustible)

	for objet in _objets:
		_creer_rendu_objet(objet)
	_poser_camera()

	_prochain_print = _config.get("intervalle_print", 2.0)
	for objet in _objets:
		print(_ligne_pose(0.0, objet))
	_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta

	var sources := sources_chaleur(_objets, _config.get("rayon_emission", 300.0), _config.get("temperature_source", 800.0))
	Temperature.avancer(_objets, sources, delta, _catalogue_temperature)

	var franchis: Array = Depense.avancer(_objets, delta, _seuils_combustible)
	for id in franchis:
		var objet := _par_id(id)
		if objet.is_empty() or _eteints.has(id):
			continue
		if not objet.proprietes.get("brule", false):
			print(_ligne_extinction(_temps, id))
			_eteints[id] = true

	if _temps >= _prochain_print:
		_prochain_print += _config.get("intervalle_print", 2.0)
		for objet in _objets:
			print(_ligne_rapport(_temps, objet))

	_rafraichir_tout()

func _par_id(id: String) -> Dictionary:
	for objet in _objets:
		if objet.id == id:
			return objet
	return {}

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		_noeuds[id].color = _couleur_pour(objet.proprietes.temperature)
		_labels[id].text = _texte_label(objet)

# ---- Fonctions statiques, pures, testables ----

# Construit, pour chaque declaration, un objet physique reel (composition
# fusionnee -- meme patron que banc_foudre.gd:fabriquer_objets) ; les objets
# dont "brule_initial" est vrai recoivent EN PLUS une reserve "combustible"
# (via reserve_combustible, config REELLE de data/
# reserve_combustible_composition.json -- passer {} pour les autres,
# Objet.fabriquer ne touche alors jamais "reserves") puis "brule" est pose a
# true APRES la fabrication (Objet.fabriquer ne connait aucune notion de
# "brule", meme patron que banc_combustible.gd:_ready).
static func fabriquer_objets(declarations: Array, objet_physique: Dictionary, materiaux: Dictionary, proprietes_immuables: Array, reserve_combustible: Dictionary) -> Array:
	var table: Dictionary = {"objet_physique": objet_physique}
	for decl in declarations:
		table[decl.id] = {"herite": ["objet_physique"], "composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var brule_initial: bool = decl.get("brule_initial", false)
		var config_reserve: Dictionary = reserve_combustible if brule_initial else {}
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), table, materiaux, proprietes_immuables, config_reserve)
		if objet.is_empty():
			continue
		if brule_initial:
			objet.proprietes["brule"] = true
		objets.append(objet)
	return objets

# Coeur du chantier : une source de chaleur PAR OBJET qui porte "brule" CE
# TICK, force PROPORTIONNELLE a "chaleur_emise" (defaut 0.0, materiau sans
# cette propriete ou objet non fabrique par composition -- point neutre
# legitime, jamais une alarme, meme discipline que temperature.gd sur
# conductivite_thermique absente). Un objet qui ne porte pas "brule" (jamais
# allume, ou eteint depuis un tick precedent) n'apparait PAS dans le
# resultat -- aucune memoire propre a cette fonction, reconstruite du neant
# a chaque appel depuis le seul etat courant des objets recus.
static func sources_chaleur(objets: Array, rayon_emission: float, temperature_source: float) -> Array:
	var sources: Array = []
	for objet in objets:
		if not objet.proprietes.get("brule", false):
			continue
		sources.append({
			"position": objet.position,
			"rayon": rayon_emission,
			"temperature": temperature_source,
			"force": objet.proprietes.get("chaleur_emise", 0.0),
		})
	return sources

static func _texte_label(objet: Dictionary) -> String:
	var chaleur_emise: float = objet.proprietes.get("chaleur_emise", 0.0)
	var etat: String = "brule" if objet.proprietes.get("brule", false) else "eteint"
	return "%s\nchaleur_emise=%.2f\ntemperature=%.1f\n%s" % [objet.id, chaleur_emise, objet.proprietes.temperature, etat]

static func _ligne_pose(t: float, objet: Dictionary) -> String:
	var chaleur_emise: float = objet.proprietes.get("chaleur_emise", 0.0)
	var etat: String = "brule" if objet.proprietes.get("brule", false) else "eteint"
	return "t=%.1fs %s : chaleur_emise=%.2f temperature=%.1f (%s)" % [t, objet.id, chaleur_emise, objet.proprietes.temperature, etat]

static func _ligne_rapport(t: float, objet: Dictionary) -> String:
	var etat: String = "brule" if objet.proprietes.get("brule", false) else "eteint"
	return "t=%.1fs %s : temperature=%.1f (%s)" % [t, objet.id, objet.proprietes.temperature, etat]

static func _ligne_extinction(t: float, id: String) -> String:
	return "t=%.1fs %s : eteint (combustible epuise), la source de chaleur disparait" % [t, id]

static func _couleur_pour_temperature(temperature: float, mini: float, maxi: float, couleur_froid: Color, couleur_chaud: Color) -> Color:
	if maxi <= mini:
		return couleur_froid
	var ratio: float = clamp((temperature - mini) / (maxi - mini), 0.0, 1.0)
	return couleur_froid.lerp(couleur_chaud, ratio)

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

func _couleur_pour(temperature: float) -> Color:
	var echelle: Dictionary = _config.get("echelle_couleur", {})
	var couleur_froid := _couleur_depuis_array(_config.get("couleur_froid", [0.15, 0.35, 0.85]))
	var couleur_chaud := _couleur_depuis_array(_config.get("couleur_chaud", [0.85, 0.15, 0.1]))
	return _couleur_pour_temperature(temperature, echelle.get("min", 0.0), echelle.get("max", 800.0), couleur_froid, couleur_chaud)

func _creer_rendu_objet(objet: Dictionary) -> void:
	var id: String = objet.id
	var centre := Vector2(objet.position.x, objet.position.y)

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 70.0)
	add_child(label)
	_labels[id] = label

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos[0], pos[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 0.5), decl_camera.get("zoom", 0.5))
	camera.enabled = true
	add_child(camera)

func _couleur_depuis_array(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
