extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_fracture_sonore.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1, coexiste avec les
# autres bancs). Existe pour VOIR resistance_impact/fragilite se fracturer
# par le SON plutot que par le choc mecanique (scripts/banc_fracture.gd),
# meme etat 'fracture' (data/etats.json), arrive par un AUTRE chemin.
# Chantier « fracture par son -- un son intense casse un objet fragile »,
# audit prealable audit_sonore_prealable.md §3 (fragilite : « zero fichier
# du coeur a toucher -- une entree de catalogue + un cablage de banc,
# patron deja ferme par banc_fracture.gd »).
#
# AUCUN MECANISME DU COEUR TOUCHE : frappe.gd/seuil_etat.gd/etat_effectif.gd/
# etat_duree.gd/depense.gd/produit.gd/perception.gd restent inchanges.
# frappe.gd N'EST MEME PAS UTILISE ICI (contrairement a banc_fracture.gd) --
# il n'y a pas d'evenement ponctuel choisi par un clic, seulement une
# ACCUMULATION CONTINUE tant qu'une source sonore reste active, patron
# temperature.gd/charge.gd (continu, delta-dependant) mais ECRITE PAR CE
# FICHIER DIRECTEMENT sur 'intensite_sonore_cumulee' -- aucun mecanisme du
# coeur ne connait cette propriete, elle n'existe QUE parce que ce cablage
# l'ecrit lui-meme, meme statut que 'degats_impact_cumules' dans
# banc_fracture.gd (voir frappe.gd, qui ne monte jamais aucune propriete).
#
# Ce fichier COMPOSE trois patrons deja fermes, jamais reecrits :
# - Portee.en_portee (INCHANGE) -- une chose hors du rayon de la source ne
#   recoit jamais d'exposition, meme fonction partagee que les cinq
#   mecanismes de « Direction majeure ».
# - SeuilEtat.avancer (INCHANGE) -- compare intensite_sonore_cumulee a
#   resistance_impact (seuil_propriete, fusionnee a la fabrication) via une
#   DEUXIEME entree de data/seuils_etat.json ('fracture_sonore'), qui pose
#   le MEME etat 'fracture' que l'entree mecanique de banc_fracture.gd --
#   coexistence documentee dans seuil_etat.gd (memoire PAR ENTREE). Catalogue
#   PARTAGE data/seuils_etat.json passe TEL QUEL (point_fusion/
#   point_ebullition/sublimation/chaud/fracture y cohabitent, jamais
#   declenchees ici -- aucune source de temperature ni de choc dans ce banc).
# - Produit.transformer (INCHANGE, meme patron que banc_fracture.gd) --
#   appele PAR CE FICHIER, jamais par seuil_etat.gd, UNIQUEMENT si l'objet
#   fraichement fracture porte une fragilite superieure a
#   config.seuil_fragilite_eclats : le verre (0.9) se transforme toujours en
#   eclats, le fer (0.2) reste seul pose (deformation sans debris, jamais
#   transforme) -- fragilite tranche, jamais un nom de materiau en dur ici.
#
# ACCUMULATION AVEC DELTA, DECISION ASSUMEE : intensite_sonore_cumulee monte
# de (son_emis_source * (1.0 - distance/rayon_source)) * delta a CHAQUE tick
# ou la source est active -- jamais un montant fixe par tick (contrairement
# a deformation.gd/lien_personnel_croissance.gd, qui posent un montant FIXE
# par evenement de perception discret). Choix SUR car cette grandeur ne
# redescend JAMAIS (meme famille que degats_impact_cumules) : le bug connu
# de lien_personnel_croissance.gd (un montant multiplie par delta, trop
# petit, efface par une DECROISSANCE avant de survivre d'un tick a l'autre)
# ne peut pas se reproduire ici, il n'existe aucune decroissance sur
# intensite_sonore_cumulee. Le delta-scaling rend seulement l'accumulation
# INDEPENDANTE du framerate, ce qu'un montant fixe par tick ne serait pas.
#
# Deux moities, meme decoupage que banc_fracture.gd :
# - Node (impur) : _ready charge les donnees/catalogues partages et
#   fabrique les deux objets (Objet.fabriquer, INCHANGE). _unhandled_input
#   BASCULE la source au clic gauche (jamais un choc positionne -- toute la
#   scene est exposee ou non, pas une cible visee). _process fait avancer
#   l'exposition ET la fracture a chaque tick (continu, contrairement au
#   geste instantane de banc_fracture.gd) et redessine.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_fracture_sonore.gd) : fabriquer_objets/intensite_recue/
#   avancer_exposition/avancer_fracture, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Portee = preload("res://scripts/portee.gd")
const SeuilEtat = preload("res://scripts/seuil_etat.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Produit = preload("res://scripts/produit.gd")

const TAILLE := 70.0
const TAILLE_POLICE_LABEL := 13
const COULEUR_ECLATS := Color(0.75, 0.85, 0.9)
const COULEUR_SOURCE_ACTIVE := Color(0.95, 0.85, 0.2)
const COULEUR_SOURCE_INACTIVE := Color(0.35, 0.35, 0.35)
const TAILLE_SOURCE := 30.0

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _proprietes_immuables: Array = []
var _objet_physique: Dictionary = {}
var _catalogue_seuils_etat: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _transformations: Dictionary = {}
var _position_source: Vector3 = Vector3.ZERO
var _son_emis_source: float = 0.0
var _rayon_source: float = 0.0
var _source_active: bool = false
var _objets: Array = []
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _fracture_avant: Dictionary = {}
var _transforme_avant: Dictionary = {}
var _noeud_source: ColorRect
var _label_source: Label
var _camera: Camera2D
var _temps: float = 0.0
var _dernier_rapport: float = -INF

func _ready() -> void:
	_config = _charger_json("res://data/banc_fracture_sonore.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_proprietes_immuables = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	_objet_physique = _charger_json("res://data/types.json").get("objet_physique", {})
	_catalogue_seuils_etat = _charger_json("res://data/seuils_etat.json")
	_etats = _charger_json("res://data/etats.json")
	_catalogue_types = _charger_json("res://data/types.json")
	_transformations = _charger_json("res://data/transformations.json").get("transformations", {})

	var pos_source: Array = _config.position_source
	_position_source = Vector3(pos_source[0], pos_source[1], pos_source[2])
	_son_emis_source = _config.son_emis_source
	_rayon_source = _config.rayon_source

	_objets = fabriquer_objets(_config.get("objets", []), _objet_physique, _materiaux, _proprietes_immuables)

	for objet in _objets:
		_fracture_avant[objet.id] = false
		_transforme_avant[objet.id] = false
		_creer_rendu_objet(objet)
	_creer_rendu_source()
	_poser_camera()
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_source_active = not _source_active
		print(_ligne_toggle(_temps, _source_active))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta

	if _source_active:
		avancer_exposition(_objets, true, _position_source, _son_emis_source, _rayon_source, delta)

	var resultat := avancer_fracture(_objets, _catalogue_seuils_etat, _transformations, _catalogue_types, _materiaux, _config.seuil_fragilite_eclats)
	for id in resultat.bascules:
		if _fracture_avant.get(id, false):
			continue
		_fracture_avant[id] = true
		print(_ligne_fracture(_temps, id, _objet_par_id(id), _etats))
	for id in resultat.transformes:
		_transforme_avant[id] = true
		print(_ligne_transforme(_temps, id, _objet_par_id(id)))

	if _temps - _dernier_rapport >= _config.get("intervalle_print", 2.0):
		_dernier_rapport = _temps
		for objet in _objets:
			if not _transforme_avant.get(objet.id, false):
				print(_ligne_rapport(_temps, objet))

	_rafraichir_tout()

func _objet_par_id(id: String) -> Dictionary:
	for objet in _objets:
		if objet.id == id:
			return objet
	return {}

func _rafraichir_tout() -> void:
	for objet in _objets:
		var id: String = objet.id
		_noeuds[id].color = _teinte(objet, _transforme_avant.get(id, false), _fracture_avant.get(id, false))
		_labels[id].text = _texte_label(objet)
	_noeud_source.color = COULEUR_SOURCE_ACTIVE if _source_active else COULEUR_SOURCE_INACTIVE
	_label_source.text = "source : %s" % ("active" if _source_active else "coupee")

# ---- Fonctions PURES, testables headless (voir test_banc_fracture_sonore.gd) ----

# Construit les objets via Objet.fabriquer (composition fusionnee -- meme
# patron que banc_fracture.gd, "objet_physique" fusionne). Ajoute A LA MAIN
# (Objet.fabriquer ne les connait pas) : "intensite_sonore_cumulee" (0.0,
# la grandeur que scripts/seuil_etat.gd va comparer -- SANS elle,
# proprietes.has() rendrait faux et l'entree "fracture_sonore" ne se
# declencherait jamais, meme raison que "degats_impact_cumules" dans
# banc_fracture.gd), "etats_actifs" (Array vide, structurelle pour
# seuil_etat.gd/etat_effectif.gd) et "transformation_fracture" (pointeur
# DATA vers data/transformations.json, vide ou nomme selon la declaration --
# jamais un nom de materiau en dur ici).
static func fabriquer_objets(declarations: Array, objet_physique: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var table: Dictionary = {"objet_physique": objet_physique}
	for decl in declarations:
		table[decl.id] = {"herite": ["objet_physique"], "composition": decl.composition}
	var objets: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var objet := Objet.fabriquer(decl.id, decl.id, Vector3(pos[0], pos[1], pos[2]), table, materiaux, proprietes_immuables)
		if objet.is_empty():
			continue
		objet.proprietes["intensite_sonore_cumulee"] = 0.0
		objet.proprietes["etats_actifs"] = []
		objet.proprietes["transformation_fracture"] = decl.get("transformation_fracture", "")
		objets.append(objet)
	return objets

# Intensite recue PAR UN OBJET d'UNE source, a l'instant present -- PAS
# encore multipliee par delta (avancer_exposition le fait). Hors du rayon
# de la source (Portee.en_portee) : 0.0, chemin mort -- une chose hors de
# portee ne recoit jamais rien, meme avec un son_emis_source enorme. Dans
# le rayon : son_emis_source attenue lineairement par la distance, meme
# formule que perception.gd:_percevoir_propagation_obstacles
# (son_emis * (1.0 - distance/portee)), jamais dupliquee ici via un import
# croise -- perception.gd n'est jamais appele par ce banc, seule la FORMULE
# est reprise (ce banc n'a pas de canal perceptif, seulement une exposition
# physique directe).
static func intensite_recue(position_objet: Vector3, position_source: Vector3, son_emis_source: float, rayon_source: float) -> float:
	if not Portee.en_portee(position_source, position_objet, rayon_source):
		return 0.0
	if rayon_source <= 0.0:
		return 0.0
	var distance: float = position_source.distance_to(position_objet)
	return son_emis_source * (1.0 - distance / rayon_source)

# Fait avancer l'exposition sonore d'UN PAS DE TEMPS sur TOUS les objets --
# MUTE EN PLACE, meme convention que seuil_etat.gd/charge.gd. "source_active"
# GATE explicite (jamais devine depuis son_emis_source) : source coupee,
# CHEMIN MORT STRICT, aucun objet ne voit intensite_sonore_cumulee bouger,
# quel que soit le reste des parametres -- c'est ce qui garantit "sans
# source rien ne casse" (voir test_banc_fracture_sonore.gd).
static func avancer_exposition(objets: Array, source_active: bool, position_source: Vector3, son_emis_source: float, rayon_source: float, delta: float) -> void:
	if not source_active:
		return
	for objet in objets:
		var intensite := intensite_recue(objet.position, position_source, son_emis_source, rayon_source)
		if intensite <= 0.0:
			continue
		var cumul: float = objet.proprietes.get("intensite_sonore_cumulee", 0.0)
		objet.proprietes["intensite_sonore_cumulee"] = cumul + intensite * delta

# Verifie le franchissement de "fracture" (SeuilEtat.avancer, INCHANGE,
# via data/seuils_etat.json:fracture_sonore -- compare intensite_sonore_
# cumulee a resistance_impact) sur TOUT le monde, puis, pour chaque id
# fraichement fracture, decide via "fragilite" (lue SEULE par ce fichier,
# aucun mecanisme du coeur ne la connait) si l'objet produit des eclats
# (Produit.transformer, INCHANGE) ou se contente de rester fracture, deforme
# sans transformation. Rend { bascules, transformes } -- memes formes que
# celles deja rendues par SeuilEtat.avancer, jamais recalculees ici. MEME
# FONCTION, RECOPIEE DEPUIS banc_fracture.gd (chaque banc porte sa propre
# copie, jamais un import croise entre bancs) -- seule difference reelle :
# aucune reserve "integrite" a filtrer en amont, ce banc n'utilise jamais
# frappe.gd.
static func avancer_fracture(objets: Array, catalogue_seuils_etat: Dictionary, transformations: Dictionary, table_types: Dictionary, materiaux: Dictionary, seuil_fragilite_eclats: float) -> Dictionary:
	var bascules := SeuilEtat.avancer(objets, catalogue_seuils_etat)
	var transformes: Array = []
	for objet in objets:
		if not bascules.has(objet.id):
			continue
		if not objet.proprietes.get("etats_actifs", []).has("fracture"):
			continue
		var fragilite: float = objet.proprietes.get("fragilite", 0.0)
		if fragilite < seuil_fragilite_eclats:
			continue
		var nom_transformation: String = objet.proprietes.get("transformation_fracture", "")
		if nom_transformation.is_empty():
			continue
		var config_produire: Dictionary = transformations.get(nom_transformation, {}).get("a_zero", {}).get("produire", {})
		var nouvelles_proprietes: Dictionary = Produit.transformer(objet.proprietes, config_produire, table_types, materiaux)
		if nouvelles_proprietes.is_empty():
			continue
		objet.proprietes.clear()
		objet.proprietes.merge(nouvelles_proprietes, true)
		transformes.append(objet.id)
	return {"bascules": bascules, "transformes": transformes}

static func _teinte(objet: Dictionary, transforme: bool, fracture: bool) -> Color:
	if transforme:
		return COULEUR_ECLATS
	if fracture:
		return Color(0.7, 0.2, 0.15)
	var intensite: float = objet.proprietes.get("intensite_sonore_cumulee", 0.0)
	var resistance: float = max(objet.proprietes.get("resistance_impact", 0.0), 0.0001)
	var ratio: float = clamp(intensite / resistance, 0.0, 1.0)
	return Color(0.55, 0.55, 0.6).lerp(Color(0.85, 0.5, 0.15), ratio)

static func _texte_label(objet: Dictionary) -> String:
	var proprietes: Dictionary = objet.proprietes
	if not proprietes.has("resistance_impact"):
		return "%s\n(transforme)\nmasse=%.2f" % [objet.id, proprietes.get("masse", 0.0)]
	var fracture: bool = proprietes.get("etats_actifs", []).has("fracture")
	return "%s\nresistance_impact=%.2f\nfragilite=%.2f\nintensite_cumulee=%.2f\netat=%s" % [
		objet.id,
		proprietes.get("resistance_impact", 0.0),
		proprietes.get("fragilite", 0.0),
		proprietes.get("intensite_sonore_cumulee", 0.0),
		"fracture" if fracture else "intact",
	]

static func _ligne_toggle(t: float, actif: bool) -> String:
	return "t=%.1fs SOURCE : %s" % [t, "activee" if actif else "coupee"]

static func _ligne_rapport(t: float, objet: Dictionary) -> String:
	return "t=%.1fs %s : intensite_sonore_cumulee=%.2f / resistance_impact=%.2f" % [
		t, objet.id, objet.proprietes.get("intensite_sonore_cumulee", 0.0), objet.proprietes.get("resistance_impact", 0.0),
	]

static func _ligne_fracture(t: float, id: String, objet: Dictionary, etats: Dictionary) -> String:
	var durete_eff := EtatEffectif.valeur(objet, "durete", etats)
	var compression_eff := EtatEffectif.valeur(objet, "resistance_compression", etats)
	return "t=%.1fs %s : FRACTURE PAR LE SON (durete effective -> %.2f, resistance_compression effective -> %.2f)" % [t, id, durete_eff, compression_eff]

static func _ligne_transforme(t: float, id: String, objet: Dictionary) -> String:
	return "t=%.1fs %s : reduit en eclats (masse=%.2f)" % [t, id, objet.proprietes.get("masse", 0.0)]

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

	var label := Label.new()
	label.position = centre - Vector2(TAILLE / 2.0, TAILLE / 2.0 + 90.0)
	label.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(label)
	_labels[id] = label

func _creer_rendu_source() -> void:
	var centre := Vector2(_position_source.x, _position_source.y)

	_noeud_source = ColorRect.new()
	_noeud_source.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_source.size = Vector2(TAILLE_SOURCE, TAILLE_SOURCE)
	_noeud_source.position = centre - _noeud_source.size / 2.0
	add_child(_noeud_source)

	_label_source = Label.new()
	_label_source.position = centre - Vector2(TAILLE_SOURCE / 2.0, TAILLE_SOURCE / 2.0 + 24.0)
	_label_source.add_theme_font_size_override("font_size", TAILLE_POLICE_LABEL)
	add_child(_label_source)

func _poser_camera() -> void:
	var decl_camera: Dictionary = _config.get("camera", {})
	var pos: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	_camera = Camera2D.new()
	_camera.position = Vector2(pos[0], pos[1])
	_camera.zoom = Vector2(decl_camera.get("zoom", 0.5), decl_camera.get("zoom", 0.5))
	_camera.enabled = true
	add_child(_camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
