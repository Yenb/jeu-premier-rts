extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_absorption_sonore.tscn, PAS la
# scene principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « absorption_sonore -- un materiau absorbe le son » :
# PROUVE, avec des materiaux DIFFERENTS, ce que banc_occlusion.gd a deja
# demontre avec la pierre seule -- le troisieme filtre de
# scripts/perception.gd:_percevoir_propagation_obstacles (canal ouie) reduit
# le son selon la valeur REELLE d'absorption_sonore de l'obstacle, jamais
# une simple coupure binaire.
#
# AUCUN MECANISME DU COEUR TOUCHE : perception.gd/objet.gd/monde.gd/
# banc_commun.gd/banc_son.gd/banc_occlusion.gd/banc_resonance.gd restent
# inchanges. Ce fichier COMPOSE :
# - Objet.fabriquer (INCHANGE) -- une source REELLE (fer, son_emis 0.5) et
#   TROIS variantes reelles du mur (bois/pierre/fer, absorption_sonore
#   0.3/0.05/0.02, data/materiaux.json), memes patrons que
#   banc_son.gd/banc_occlusion.gd.
# - BancCommun.fabriquer_colon (INCHANGE) -- un colon, type partage "colon"
#   (data/types.json). Recoit ENSUITE, comme banc_son.gd:fabriquer_colon_son/
#   banc_occlusion.gd:fabriquer_colon_occlusion, une surcharge LOCALE de
#   canaux_config.ouie (data/banc_absorption_sonore.json:colon.ouie_surcharge)
#   -- SEUIL VOLONTAIREMENT NUL (contrairement a banc_occlusion.gd) : ce
#   banc montre un POURCENTAGE de reduction, jamais une coupure -- le colon
#   entend TOUJOURS la source, quel que soit l'etat du mur.
# - Monde/Perception.percevoir (INCHANGES) -- un Monde JETABLE, RECONSTRUIT
#   CHAQUE TICK (meme idiome que banc_occlusion.gd/banc_resonance.gd --
#   monde.gd n'a AUCUNE fonction de retrait, voir CARTE.md §6). Le mur
#   n'entre dans le Monde du tick QUE si l'etat courant n'est pas "aucun",
#   et alors SEULE la variante du materiau courant y entre -- jamais deux
#   murs simultanement dans ce banc (voir data/banc_absorption_sonore.json,
#   _note).
#
# QUATRE ETATS, cycliques au clic gauche (ETATS_MUR, etat_suivant) : "aucun"
# (pas de mur), "bois" (absorption_sonore 0.3, reduction ~30%), "pierre"
# (0.05, ~5%), "fer" (0.02, ~2%) -- le bois absorbe le plus (panneau
# acoustique), le fer le moins (le metal resonne, il n'absorbe pas). Chaque
# clic avance d'un cran, boucle apres "fer".
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready charge donnees/catalogues, fabrique la source, les
#   trois variantes du mur et le colon, cree le rendu. _unhandled_input fait
#   avancer _etat_mur. _process reconstruit le Monde du tick (fonction
#   statique testable, voir monde_du_tick), fait percevoir le colon, logue
#   au CHANGEMENT seulement (jamais chaque frame, meme idiome que
#   banc_son.gd/banc_occlusion.gd), redessine les labels.
# - Fonctions statiques (pures, testables headless, voir
#   scripts/test_banc_absorption_sonore.gd) : etat_suivant/
#   fabriquer_colon_absorption/fabriquer_source/fabriquer_murs/
#   monde_du_tick/captures_ouie/ids_de/facteur_attenuation_affichage/
#   intensite_recue_affichage, plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const TAILLE := 64.0
const TAILLE_MUR := 40.0
const TAILLE_POLICE := 15
const LARGEUR_LABEL := 190.0
const FACTEUR_ESPACEMENT_VISUEL := 2.6

const ETATS_MUR := ["aucun", "bois", "pierre", "fer"]

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}

var _colon: Dictionary = {}
var _source: Dictionary = {}
var _murs: Dictionary = {}
var _etat_mur: String = "aucun"

var _position_rendu: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _noeud_mur: ColorRect
var _label_mur: Label
var _entendus_avant: Array = []
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_absorption_sonore.json")
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

	_source = fabriquer_source(_config.source, catalogue_types, materiaux, proprietes_immuables)
	_murs = fabriquer_murs(_config.mur, catalogue_types, materiaux, proprietes_immuables)
	_colon = fabriquer_colon_absorption(_config.colon, catalogue_types)

	var centre: Vector3 = (_colon.position + _source.position) / 2.0
	_position_rendu[_colon.id] = position_affichage(_colon.position, centre, FACTEUR_ESPACEMENT_VISUEL)
	_position_rendu[_source.id] = position_affichage(_source.position, centre, FACTEUR_ESPACEMENT_VISUEL)
	_position_rendu[_config.mur.id] = position_affichage(Vector3(_config.mur.position[0], _config.mur.position[1], _config.mur.position[2]), centre, FACTEUR_ESPACEMENT_VISUEL)

	_creer_rendu_objet(_source)
	_creer_rendu_objet(_colon)
	_creer_rendu_mur()
	_poser_camera()

	print(_ligne_toggle(0.0, _etat_mur, _murs))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_etat_mur = etat_suivant(_etat_mur)
		print(_ligne_toggle(_temps, _etat_mur, _murs))
		_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	_rafraichir_tout()

# Recalcule TOUT depuis l'etat courant (quel mur, ou aucun) et redessine --
# appelee a chaque tick ET au clic, jamais deux calculs paralleles qui
# pourraient diverger.
func _rafraichir_tout() -> void:
	var monde = monde_du_tick(_colon, _source, _murs, _etat_mur)
	var entendus := captures_ouie(_colon, monde, _catalogue_canaux)
	var ids := ids_de(entendus)
	ids.sort()
	if ids != _entendus_avant:
		_entendus_avant = ids
		print(_ligne_log(_temps, ids))

	var facteur := facteur_attenuation_affichage(_etat_mur, _murs)
	var distance: float = _colon.position.distance_to(_source.position)
	var portee: float = _colon.proprietes.canaux_config.ouie.portee
	var intensite := intensite_recue_affichage(_source.proprietes.get("son_emis", 0.0), distance, portee, facteur)

	_labels[_colon.id].text = _texte_label_colon(_colon.id, ids, intensite, facteur)
	_labels[_source.id].text = _texte_label_source(_source, facteur)

	_noeud_mur.visible = _etat_mur != "aucun"
	_label_mur.visible = _etat_mur != "aucun"
	if _etat_mur != "aucun":
		_noeud_mur.color = _couleur_de("mur_%s" % _etat_mur)
		_label_mur.text = _texte_label_mur(_etat_mur, _murs)

# ---- Fonctions statiques, pures, testables ----

# Cycle ETATS_MUR, boucle apres le dernier. Un etat inconnu (jamais rencontre
# en pratique, garde defensive) repart du premier : ETATS_MUR.find() rend -1,
# (-1 + 1) % size == 0 == index de "aucun", sans branche separee a ecrire.
static func etat_suivant(etat: String) -> String:
	var index: int = ETATS_MUR.find(etat)
	return ETATS_MUR[(index + 1) % ETATS_MUR.size()]

# Fabrique un colon partage (BancCommun.fabriquer_colon, INCHANGE) puis
# fusionne PAR-DESSUS canaux_config.ouie une surcharge LOCALE (decl.
# ouie_surcharge -- portee/seuil, data/banc_absorption_sonore.json) -- meme
# geste que banc_son.gd:fabriquer_colon_son/banc_occlusion.gd:
# fabriquer_colon_occlusion, jamais un mecanisme du coeur qui la lirait pour
# ce banc.
static func fabriquer_colon_absorption(decl: Dictionary, catalogue_types: Dictionary) -> Dictionary:
	var colon := BancCommun.fabriquer_colon(decl.id, "colon", decl, catalogue_types)
	colon.proprietes.canaux_config.ouie.merge(decl.get("ouie_surcharge", {}), true)
	return colon

static func fabriquer_source(decl: Dictionary, catalogue_types: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Dictionary:
	var pos: Array = decl.position
	return Objet.fabriquer(decl.id, "source_son", Vector3(pos[0], pos[1], pos[2]), catalogue_types, materiaux, proprietes_immuables)

# Fabrique les TROIS variantes reelles du mur (bois/pierre/fer), MEME id
# pour les trois (decl.id) -- jamais de collision, monde_du_tick n'en ajoute
# jamais plus d'une a la fois au Monde d'un meme tick.
static func fabriquer_murs(decl: Dictionary, catalogue_types: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Dictionary:
	var pos: Array = decl.position
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var murs: Dictionary = {}
	for materiau in ["bois", "pierre", "fer"]:
		murs[materiau] = Objet.fabriquer(decl.id, "mur_%s" % materiau, position3, catalogue_types, materiaux, proprietes_immuables)
	return murs

# Coeur du chantier cote cablage : le Monde du tick, RECONSTRUIT DU NEANT a
# chaque appel (meme idiome que banc_occlusion.gd/banc_resonance.gd -- monde.gd
# n'a AUCUNE fonction de retrait, voir CARTE.md §6) -- la variante de mur
# correspondant a "etat" n'y entre QUE si "etat" n'est pas "aucun".
static func monde_du_tick(colon: Dictionary, source: Dictionary, murs: Dictionary, etat: String):
	var mur_actif: Array = [] if etat == "aucun" else [murs[etat]]
	return BancCommun.monde_depuis([
		{"choses": [colon], "type": "colon"},
		{"choses": [source], "type": "source_son"},
		{"choses": mur_actif, "type": "mur"},
	])

# RECOPIEE de banc_son.gd/banc_occlusion.gd:captures_ouie -- parmi tout ce
# que Perception.percevoir rend, ne retient que les entrees captees par le
# canal "ouie" precisement.
static func captures_ouie(colon: Dictionary, monde, catalogue_canaux: Dictionary) -> Array:
	var perceptions: Array = Perception.percevoir(colon, monde, catalogue_canaux)
	var resultat: Array = []
	for entree in perceptions:
		if "ouie" in entree.canaux:
			resultat.append(entree)
	return resultat

# RECOPIEE de banc_son.gd/banc_occlusion.gd:ids_de.
static func ids_de(perceptions: Array) -> Array:
	var ids: Array = []
	for entree in perceptions:
		ids.append(entree.chose.id)
	return ids

# POUR L'AFFICHAGE SEUL (jamais consultee par captures_ouie ci-dessus, qui
# passe toujours par Perception.percevoir, le vrai chemin) : le facteur
# d'attenuation par l'unique obstacle courant, MEME FORMULE que
# perception.gd:_facteur_obstacles applique a un candidat retenu ((1.0 -
# valeur)) -- "aucun" : facteur neutre 1.0, aucun obstacle.
static func facteur_attenuation_affichage(etat: String, murs: Dictionary) -> float:
	if etat == "aucun":
		return 1.0
	return 1.0 - murs[etat].proprietes.get("absorption_sonore", 0.0)

# POUR L'AFFICHAGE SEUL, MEME FORMULE que
# perception.gd:_percevoir_propagation_obstacles (attenuation par la
# distance PUIS par le facteur d'obstacles) -- portee <= 0.0 : 0.0, jamais
# une division par zero.
static func intensite_recue_affichage(son_emis: float, distance: float, portee: float, facteur: float) -> float:
	if portee <= 0.0:
		return 0.0
	return son_emis * (1.0 - distance / portee) * facteur

# Etire une position AUTOUR du centre du groupe, horizontalement SEULEMENT
# (Y/Z inchanges) -- RENDU SEUL, jamais lu par Perception.percevoir/
# monde_du_tick, qui continuent de travailler sur la position REELLE. Meme
# fonction que banc_occlusion.gd:position_affichage -- un mur a mi-chemin
# entre colon et source reste EXACTEMENT a mi-chemin apres etirement (offset
# nul -> reste nul, quel que soit le facteur).
static func position_affichage(position_reelle: Vector3, centre_groupe: Vector3, facteur: float) -> Vector3:
	return Vector3(
		centre_groupe.x + (position_reelle.x - centre_groupe.x) * facteur,
		position_reelle.y,
		position_reelle.z,
	)

static func _texte_label_source(source: Dictionary, facteur_obstacle: float) -> String:
	return "%s\nson_emis=%.2f\natenuation_obstacle=%.0f%%" % [source.id, source.proprietes.get("son_emis", 0.0), (1.0 - facteur_obstacle) * 100.0]

static func _texte_label_colon(id: String, ids_captes: Array, intensite: float, facteur: float) -> String:
	var entendu: String = ", ".join(ids_captes) if not ids_captes.is_empty() else "(rien)"
	return "%s\nsources percues : %s\nintensite recue=%.4f\natenuation par obstacle=%.0f%%" % [id, entendu, intensite, (1.0 - facteur) * 100.0]

static func _texte_label_mur(etat: String, murs: Dictionary) -> String:
	var absorption: float = murs[etat].proprietes.get("absorption_sonore", 0.0)
	return "mur (%s)\nabsorption_sonore=%.2f" % [etat, absorption]

static func _ligne_toggle(t: float, etat: String, murs: Dictionary) -> String:
	if etat == "aucun":
		return "t=%.1fs MUR : aucun" % t
	return "t=%.1fs MUR : %s (absorption_sonore=%.2f)" % [t, etat, murs[etat].proprietes.get("absorption_sonore", 0.0)]

static func _ligne_log(t: float, ids: Array) -> String:
	var entendu: String = ", ".join(ids) if not ids.is_empty() else "(rien)"
	return "t=%.1f colon_0 entend : %s" % [t, entendu]

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
	noeud.color = _couleur_de("colon" if objet.id == _colon.id else "source")
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
	var position_ecran: Vector3 = _position_rendu[_config.mur.id]
	_noeud_mur = ColorRect.new()
	_noeud_mur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noeud_mur.size = Vector2(TAILLE_MUR, TAILLE_MUR)
	_noeud_mur.color = _couleur_de("mur_bois")
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
