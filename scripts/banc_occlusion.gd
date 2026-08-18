extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_occlusion.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « occlusion -- un obstacle entre A et B bloque la
# perception » : PREMIERE DEMONSTRATION REELLE du troisieme filtre de
# scripts/perception.gd:_percevoir_propagation_obstacles (canal ouie) --
# un mur en pierre entre une source et un colon attenue le son au point de
# le faire tomber sous le seuil de perception ; le meme mur retire (ou
# rendu transparent au toggle), le son redevient percu.
#
# AUCUN MECANISME DU COEUR TOUCHE AU-DELA DE perception.gd/data/canaux.json/
# data/proprietes_immuables_composition.json (deja modifies par ce chantier,
# voir leurs propres en-tetes) : objet.gd/monde.gd/banc_commun.gd/
# banc_son.gd/banc_resonance.gd restent inchanges. Ce fichier COMPOSE :
# - Objet.fabriquer (INCHANGE) -- deux sources sonores REELLES (fer,
#   son_emis 0.5) et un mur REEL (pierre, absorption_sonore 0.05,
#   data/materiaux.json), memes patrons que banc_son.gd/banc_fracture_sonore.gd.
# - BancCommun.fabriquer_colon (INCHANGE) -- deux colons (colon_avec_mur/
#   colon_temoin), type partage "colon" (data/types.json). Chaque colon
#   recoit ENSUITE, comme banc_son.gd:fabriquer_colon_son, une surcharge
#   LOCALE de canaux_config.ouie (data/banc_occlusion.json:*.colon.
#   ouie_surcharge) -- jamais un mecanisme du coeur qui la lirait pour ce
#   banc.
# - Monde/Perception.percevoir (INCHANGES) -- un Monde JETABLE, RECONSTRUIT
#   CHAQUE TICK (meme idiome que banc_resonance.gd -- monde.gd n'a AUCUNE
#   fonction de retrait, voir CARTE.md §6 : faire "disparaitre" le mur au
#   toggle exige de ne jamais l'ajouter au Monde de ce tick, jamais une
#   mutation en place d'un objet deja enregistre). Perception.percevoir
#   isole ensuite ce que chaque colon capte par le canal "ouie" precisement
#   (captures_ouie, RECOPIEE de banc_son.gd -- jamais un appel croise entre
#   bancs, meme discipline documentee partout ailleurs dans ce depot).
#
# DEUX PAIRES colon/source, jamais une seule : "avec_mur" (colon_avec_mur/
# source_avec_mur/mur, TOGGLABLE) et "temoin" (colon_temoin/source_temoin,
# AUCUN mur, jamais touche) -- voir data/banc_occlusion.json._note pour la
# geometrie exacte et les valeurs numeriques (memes que
# scripts/test_perception.gd:_mur_obstacle_bloque_le_son, marge fine
# assumee : la pierre reelle n'attenue que de 5%, "quasi bloque" plutot
# qu'un mur artificiellement fort).
#
# Toggle au clic gauche (_unhandled_input) inverse _mur_actif -- meme geste
# que banc_reflectivite.gd/banc_resonance.gd. Mur actif : absent du Monde
# du tick suivant, colon_avec_mur cesse d'entendre source_avec_mur. Mur
# inactif : present, colon_avec_mur l'entend de nouveau. colon_temoin
# n'est JAMAIS affecte par ce toggle (aucun mur dans sa paire).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge donnees/catalogues, fabrique les deux
#   sources, le mur et les deux colons, cree le rendu. _unhandled_input
#   bascule _mur_actif. _process reconstruit le Monde du tick (fonction
#   statique testable, voir monde_du_tick), fait percevoir chaque colon,
#   logue au CHANGEMENT seulement (jamais chaque frame, meme idiome que
#   banc_son.gd), redessine les labels.
# - Fonctions statiques (pures, testables headless, voir
#   scripts/test_banc_occlusion.gd) : fabriquer_colon_occlusion/
#   monde_du_tick/captures_ouie/ids_de/facteur_obstacle_affichage, plus le
#   texte d'affichage et de log.
#
# ESPACEMENT VISUEL (correction, retour Yael -- labels qui se chevauchaient
# entre colon et source de chaque paire, distance REELLE 100 pour une
# largeur de label 190) : `position_affichage` etire une position AUTOUR du
# CENTRE DE SON GROUPE (colon+source), horizontalement SEULEMENT, par
# FACTEUR_ESPACEMENT_VISUEL -- RENDU SEUL, jamais lu par
# Perception.percevoir/monde_du_tick, qui continuent de travailler sur
# `objet.position` brut, EXACTEMENT tel que fabrique depuis data/
# banc_occlusion.json (fichier hors perimetre de cette correction). Le mur,
# a mi-chemin entre colon et source dans le monde reel, reste EXACTEMENT a
# mi-chemin a l'ecran -- son propre ecart au centre du groupe est etire de
# la meme facon, jamais recalcule autrement (ne se retrouve donc jamais
# colle a l'un des deux). `_position_rendu` (Dictionary id -> Vector3,
# calculee UNE FOIS en _ready, aucun objet de ce banc ne bouge apres coup)
# remplace `objet.position` dans TOUT le rendu (carres, labels, camera) --
# jamais dans `_rafraichir_tout`/`monde_du_tick`.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const TAILLE := 64.0
const TAILLE_MUR := 40.0
const TAILLE_POLICE := 15
const LARGEUR_LABEL := 190.0
const FACTEUR_ESPACEMENT_VISUEL := 2.6

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}

var _colon_avec_mur: Dictionary = {}
var _source_avec_mur: Dictionary = {}
var _mur: Dictionary = {}
var _colon_temoin: Dictionary = {}
var _source_temoin: Dictionary = {}
var _mur_actif: bool = true

var _position_rendu: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_mur: ColorRect
var _label_mur: Label
var _entendus_avant: Dictionary = {}
var _temps: float = 0.0
var _prochain_print: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_occlusion.json")
	var materiaux: Dictionary = _charger_json("res://data/materiaux.json")
	var proprietes_immuables: Array = _charger_json("res://data/proprietes_immuables_composition.json").get("proprietes", [])
	var types_partages: Dictionary = _charger_json("res://data/types.json")
	var catalogue_types: Dictionary = _config.get("types", {}).duplicate(true)
	catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	catalogue_types["dynamique"] = types_partages.get("dynamique", {})
	catalogue_types["percevant"] = types_partages.get("percevant", {})
	catalogue_types["agent"] = types_partages.get("agent", {})
	catalogue_types["colon"] = types_partages.get("colon", {})
	_catalogue_canaux = _charger_json("res://data/canaux.json")

	var decl_avec_mur: Dictionary = _config.avec_mur
	var decl_temoin: Dictionary = _config.temoin

	_source_avec_mur = fabriquer_source(decl_avec_mur.source, catalogue_types, materiaux, proprietes_immuables)
	_mur = fabriquer_mur(decl_avec_mur.mur, catalogue_types, materiaux, proprietes_immuables)
	_colon_avec_mur = fabriquer_colon_occlusion(decl_avec_mur.colon, catalogue_types)

	_source_temoin = fabriquer_source(decl_temoin.source, catalogue_types, materiaux, proprietes_immuables)
	_colon_temoin = fabriquer_colon_occlusion(decl_temoin.colon, catalogue_types)

	var centre_avec_mur: Vector3 = (_colon_avec_mur.position + _source_avec_mur.position) / 2.0
	var centre_temoin: Vector3 = (_colon_temoin.position + _source_temoin.position) / 2.0
	_position_rendu[_colon_avec_mur.id] = position_affichage(_colon_avec_mur.position, centre_avec_mur, FACTEUR_ESPACEMENT_VISUEL)
	_position_rendu[_source_avec_mur.id] = position_affichage(_source_avec_mur.position, centre_avec_mur, FACTEUR_ESPACEMENT_VISUEL)
	_position_rendu[_mur.id] = position_affichage(_mur.position, centre_avec_mur, FACTEUR_ESPACEMENT_VISUEL)
	_position_rendu[_colon_temoin.id] = position_affichage(_colon_temoin.position, centre_temoin, FACTEUR_ESPACEMENT_VISUEL)
	_position_rendu[_source_temoin.id] = position_affichage(_source_temoin.position, centre_temoin, FACTEUR_ESPACEMENT_VISUEL)

	_creer_rendu_objet(_source_avec_mur)
	_creer_rendu_objet(_colon_avec_mur)
	_creer_rendu_objet(_source_temoin)
	_creer_rendu_objet(_colon_temoin)
	_creer_rendu_mur()
	_poser_camera()

	_prochain_print = _config.get("intervalle_print", 2.0)
	print(_ligne_toggle(0.0, _mur_actif))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_mur_actif = not _mur_actif
		print(_ligne_toggle(_temps, _mur_actif))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	if _temps >= _prochain_print:
		_prochain_print += _config.get("intervalle_print", 2.0)
	_rafraichir_tout()

# Recalcule TOUT depuis l'etat courant (mur actif ou non) et redessine --
# appelee a chaque tick ET au toggle, jamais deux calculs paralleles qui
# pourraient diverger.
func _rafraichir_tout() -> void:
	var monde = monde_du_tick(_colon_avec_mur, _source_avec_mur, _mur, _mur_actif, _colon_temoin, _source_temoin)

	for colon in [_colon_avec_mur, _colon_temoin]:
		var entendus := captures_ouie(colon, monde, _catalogue_canaux)
		var ids := ids_de(entendus)
		ids.sort()
		if ids != _entendus_avant.get(colon.id, []):
			_entendus_avant[colon.id] = ids
			print(_ligne_log(_temps, colon.id, ids))
		_labels[colon.id].text = _texte_label_colon(colon.id, ids)

	var facteur := facteur_obstacle_affichage(_mur_actif, _mur.proprietes.get("absorption_sonore", 0.0))
	_labels[_source_avec_mur.id].text = _texte_label_source(_source_avec_mur, facteur)
	_labels[_source_temoin.id].text = _texte_label_source(_source_temoin, 1.0)

	_noeud_mur.visible = _mur_actif
	_label_mur.visible = _mur_actif
	_label_mur.text = "mur (pierre)\nabsorption_sonore=%.2f" % _mur.proprietes.get("absorption_sonore", 0.0)

# ---- Fonctions statiques, pures, testables ----

static func fabriquer_source(decl: Dictionary, catalogue_types: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Dictionary:
	var pos: Array = decl.position
	return Objet.fabriquer(decl.id, "source_son", Vector3(pos[0], pos[1], pos[2]), catalogue_types, materiaux, proprietes_immuables)

static func fabriquer_mur(decl: Dictionary, catalogue_types: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Dictionary:
	var pos: Array = decl.position
	return Objet.fabriquer(decl.id, "mur", Vector3(pos[0], pos[1], pos[2]), catalogue_types, materiaux, proprietes_immuables)

# Fabrique un colon partage (BancCommun.fabriquer_colon, INCHANGE) puis
# fusionne PAR-DESSUS canaux_config.ouie une surcharge LOCALE (decl.
# ouie_surcharge -- portee/seuil, data/banc_occlusion.json) -- meme geste
# que banc_son.gd:fabriquer_colon_son, jamais un mecanisme du coeur qui la
# lirait pour ce banc.
static func fabriquer_colon_occlusion(decl: Dictionary, catalogue_types: Dictionary) -> Dictionary:
	var colon := BancCommun.fabriquer_colon(decl.id, "colon", decl, catalogue_types)
	colon.proprietes.canaux_config.ouie.merge(decl.get("ouie_surcharge", {}), true)
	return colon

# Coeur du chantier cote cablage : le Monde du tick, RECONSTRUIT DU NEANT a
# chaque appel (meme idiome que banc_resonance.gd:sources_actives -- monde.gd
# n'a AUCUNE fonction de retrait, voir CARTE.md §6) -- le mur n'y entre QUE
# si mur_actif est vrai. Les deux colons entrent aussi (necessaire pour
# l'auto-exclusion de perception.gd -- un colon ne doit jamais se percevoir
# lui-meme, voir perception.gd:_sphere_brute).
static func monde_du_tick(colon_avec_mur: Dictionary, source_avec_mur: Dictionary, mur: Dictionary, mur_actif: bool, colon_temoin: Dictionary, source_temoin: Dictionary):
	var murs: Array = [mur] if mur_actif else []
	return BancCommun.monde_depuis([
		{"choses": [colon_avec_mur, colon_temoin], "type": "colon"},
		{"choses": [source_avec_mur, source_temoin], "type": "source_son"},
		{"choses": murs, "type": "mur"},
	])

# RECOPIEE de banc_son.gd:captures_ouie -- parmi tout ce que
# Perception.percevoir rend, ne retient que les entrees captees par le
# canal "ouie" precisement.
static func captures_ouie(colon: Dictionary, monde, catalogue_canaux: Dictionary) -> Array:
	var perceptions: Array = Perception.percevoir(colon, monde, catalogue_canaux)
	var resultat: Array = []
	for entree in perceptions:
		if "ouie" in entree.canaux:
			resultat.append(entree)
	return resultat

# RECOPIEE de banc_son.gd:ids_de.
static func ids_de(perceptions: Array) -> Array:
	var ids: Array = []
	for entree in perceptions:
		ids.append(entree.chose.id)
	return ids

# POUR L'AFFICHAGE SEUL (jamais consultee par captures_ouie ci-dessus, qui
# passe toujours par Perception.percevoir, le vrai chemin) : le facteur
# d'attenuation par UN SEUL obstacle (ce banc n'en pose jamais deux),
# MEME FORMULE que perception.gd:_facteur_obstacles applique a un candidat
# retenu ((1.0 - valeur), borne implicitement par la fiche materiau reelle
# deja dans [0.0,1.0]) -- mur_actif faux : facteur neutre 1.0, aucun
# obstacle, meme raison que la sphere sans mur.
static func facteur_obstacle_affichage(mur_actif: bool, absorption_sonore: float) -> float:
	if not mur_actif:
		return 1.0
	return 1.0 - absorption_sonore

# Etire une position AUTOUR du centre de son groupe, horizontalement
# SEULEMENT (Y/Z inchanges) -- RENDU SEUL, voir en-tete du fichier. Un
# facteur > 1.0 espace deux points sans jamais changer leur ORDRE ni la
# position d'un point qui coincide deja avec le centre (offset nul ->
# reste nul, quel que soit le facteur) -- un mur a mi-chemin entre colon
# et source reste donc EXACTEMENT a mi-chemin apres etirement.
static func position_affichage(position_reelle: Vector3, centre_groupe: Vector3, facteur: float) -> Vector3:
	return Vector3(
		centre_groupe.x + (position_reelle.x - centre_groupe.x) * facteur,
		position_reelle.y,
		position_reelle.z,
	)

static func _texte_label_source(source: Dictionary, facteur_obstacle: float) -> String:
	return "%s\nson_emis=%.2f\natenuation_obstacle=%.0f%%" % [source.id, source.proprietes.get("son_emis", 0.0), (1.0 - facteur_obstacle) * 100.0]

static func _texte_label_colon(id: String, ids_captes: Array) -> String:
	var entendu: String = ", ".join(ids_captes) if not ids_captes.is_empty() else "(rien)"
	return "%s\nentend : %s" % [id, entendu]

static func _ligne_toggle(t: float, mur_actif: bool) -> String:
	return "t=%.1fs MUR : %s" % [t, "present" if mur_actif else "absent"]

static func _ligne_log(t: float, colon_id: String, ids: Array) -> String:
	var entendu: String = ", ".join(ids) if not ids.is_empty() else "(rien)"
	return "t=%.1f %s entend : %s" % [t, colon_id, entendu]

# ---- Rendu (impur, Node) -- aucune decision, seulement construction des
# noeuds et de la camera.

func _couleur_de(id: String) -> Color:
	var rgb: Array = _config.get("couleurs_types", {}).get(id, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _creer_rendu_objet(objet: Dictionary) -> void:
	var position_ecran: Vector3 = _position_rendu[objet.id]
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.color = _couleur_de(objet.id)
	noeud.position = Vector2(position_ecran.x, position_ecran.y) - noeud.size / 2.0
	add_child(noeud)
	_noeuds[objet.id] = noeud

	var label := Label.new()
	label.custom_minimum_size = Vector2(LARGEUR_LABEL, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TAILLE_POLICE)
	label.position = noeud.position + Vector2(-LARGEUR_LABEL / 2.0 + TAILLE / 2.0, TAILLE + 6.0)
	add_child(label)
	_labels[objet.id] = label

func _creer_rendu_mur() -> void:
	var position_ecran: Vector3 = _position_rendu[_mur.id]
	_noeud_mur = ColorRect.new()
	_noeud_mur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_mur.size = Vector2(TAILLE_MUR, TAILLE_MUR)
	_noeud_mur.color = _couleur_de("mur")
	_noeud_mur.position = Vector2(position_ecran.x, position_ecran.y) - _noeud_mur.size / 2.0
	add_child(_noeud_mur)

	_label_mur = Label.new()
	_label_mur.custom_minimum_size = Vector2(LARGEUR_LABEL, 0.0)
	_label_mur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_mur.add_theme_font_size_override("font_size", TAILLE_POLICE)
	_label_mur.position = _noeud_mur.position + Vector2(-LARGEUR_LABEL / 2.0 + TAILLE_MUR / 2.0, -50.0)
	add_child(_label_mur)

func _poser_camera() -> void:
	var points: Array = _position_rendu.values()
	var mini := Vector2(points[0].x, points[0].y)
	var maxi := mini
	for p in points:
		mini.x = min(mini.x, p.x)
		mini.y = min(mini.y, p.y)
		maxi.x = max(maxi.x, p.x)
		maxi.y = max(maxi.y, p.y)
	var marge := 220.0
	var centre := (mini + maxi) / 2.0
	var taille_ecran: Vector2 = get_viewport().get_visible_rect().size
	if taille_ecran.x <= 0.0 or taille_ecran.y <= 0.0:
		taille_ecran = Vector2(1152.0, 648.0)
	var largeur_monde: float = max(maxi.x - mini.x + marge * 2.0, 1.0)
	var hauteur_monde: float = max(maxi.y - mini.y + marge * 2.0, 1.0)
	var zoom: float = clamp(min(taille_ecran.x / largeur_monde, taille_ecran.y / hauteur_monde), 0.05, 2.0)

	var camera := Camera2D.new()
	camera.position = centre
	camera.zoom = Vector2(zoom, zoom)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
