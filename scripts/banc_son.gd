extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_son.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Chantier « son -- grandeur ambiante par sources » :
# PREMIERE DEMONSTRATION REELLE du filtre d'intensite atténuée par la
# distance active dans scripts/perception.gd:_percevoir_propagation_obstacles
# (canal ouie, champ "seuil" jusqu'ici dormant), COMPOSEE avec un filtre de
# frequence propre a ce banc (frequence_min/frequence_max, jamais lu par le
# coeur -- voir plus bas).
#
# AUCUN MECANISME DU COEUR TOUCHE AU-DELA DE LA GARDE DE FILTRE POSEE DANS
# perception.gd (seule modification du coeur pour ce chantier) : objet.gd/
# monde.gd/banc_commun.gd restent inchanges. Ce fichier COMPOSE :
# - Objet.fabriquer (INCHANGE) -- quatre sources sonores REELLES (fer/bois/
#   pierre, data/materiaux.json), composant "objet_physique" et fusionnant
#   "son_emis" comme n'importe quelle autre propriete immuable (meme patron
#   que banc_chaleur_emise.gd:fabriquer_objets pour "chaleur_emise").
#   "frequence" (Hz) est posee EN DUR sur chaque declaration de type dans
#   data/banc_son.json:types -- PAS une propriete materiau (une meme
#   matiere peut sonner a des frequences tres differentes selon sa forme),
#   simplement fusionnee par le merge superficiel de objet.gd:fabriquer.
# - BancCommun.fabriquer_colon (INCHANGE) -- deux colons (humain/chien),
#   type partage "colon" (data/types.json). fabriquer_colon_son (CI-DESSOUS,
#   propre a ce banc) fusionne PAR-DESSUS canaux_config.ouie une surcharge
#   LOCALE (seuil/frequence_min/frequence_max, data/banc_son.json:
#   colons.*.ouie_surcharge) -- meme geste que le retrait local de
#   profil_saillance dans banc_feu.gd:_ajouter_colon : une donnee de banc
#   qui mute proprietes APRES fabrication, jamais un mecanisme du coeur qui
#   la lirait pour elle.
# - Perception.percevoir (INCHANGE COTE SIGNATURE, seul son comportement
#   interne change -- voir perception.gd) -- appele CHAQUE TICK par colon ;
#   ce fichier isole ensuite les entrees captees par le canal OUIE
#   precisement (captures_ouie), puisque vue/odorat perçoivent aussi les
#   memes sources sans filtre d'intensite ni de frequence (aucune propriete
#   "irremplacable"/"notre_ouvrage"/etc. sur nos sources, mais la geometrie
#   seule suffirait a les capter par un autre canal -- isoler "ouie" est
#   necessaire pour observer PRECISEMENT le nouveau filtre).
#
# FILTRE DE FREQUENCE (filtrer_par_frequence, PROPRE A CE BANC, jamais dans
# perception.gd -- limite stricte du chantier, voir CLAUDE.md) : une chose
# dont "frequence" (proprietes, FACULTATIVE, defaut 0.0) tombe hors de
# [frequence_min, frequence_max] est retiree -- APRES le filtre de seuil
# (deja applique par perception.gd), jamais avant : les deux filtres sont
# INDEPENDANTS (source_forte et source_ultrason partagent le MEME son_emis,
# seule la frequence les distingue -- voir data/banc_son.json._note).
#
# Deux moities, meme decoupage que les autres bancs :
# SOURCE MOBILE (retour Yael -- les quatre autres sources varient
# l'intensite de BASE a distance FIXE identique, aucune ne montre
# l'attenuation par la DISTANCE a l'ecran, seuls les tests le prouvaient) :
# "source_mobile_humain" (data/banc_son.json:mouvement_source_mobile) est
# la SEULE source dont la position change au fil du temps, position_
# source_mobile (PURE, testable) -- oscille sur l'axe X autour de
# colon_humain SEUL, traversant deux fois par periode la distance ou son
# intensite attenuee franchit le seuil : observable EN DIRECT dans le
# label de colon_humain et dans la trace console (au changement seulement).
#
# - Node (impur) : _ready charge donnees/catalogues, fabrique sources et
#   colons, cree le rendu. _process deplace source_mobile_humain (position_
#   source_mobile), recalcule sons_entendus(...) par colon chaque tick,
#   logue au CHANGEMENT seulement (jamais chaque frame, meme idiome que
#   banc_lien_personnel.gd:_logger_decision), redessine les labels.
# - Fonctions statiques (pures, testables headless, voir
#   scripts/test_banc_son.gd) : fabriquer_sources/fabriquer_colon_son/
#   captures_ouie/filtrer_par_frequence/sons_entendus/intensite_attenuee,
#   plus le texte d'affichage et de log.

const Objet = preload("res://scripts/objet.gd")
const Monde = preload("res://scripts/monde.gd")
const Perception = preload("res://scripts/perception.gd")
const BancCommun = preload("res://scripts/banc_commun.gd")

const TAILLE := 64.0
const TAILLE_POLICE := 22
const LARGEUR_LABEL := 190.0
const MARGE_CADRAGE := 260.0
const ZOOM_MIN := 0.05
const ZOOM_MAX := 2.0
const _TAILLE_ECRAN_DEFAUT := Vector2(1152.0, 648.0)

var _config: Dictionary = {}
var _catalogue_canaux: Dictionary = {}
var _monde := Monde.new()
var _sources: Array = []
var _colons: Array = []
var _sources_par_id: Dictionary = {}
var _types_sources: Dictionary = {}
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _captures_precedentes: Dictionary = {}
var _temps: float = 0.0
var _prochain_print: float = 0.0

var _couche_ui: CanvasLayer
var _camera: Camera2D
var _zoom: float = 1.0
var _taille_ecran: Vector2 = _TAILLE_ECRAN_DEFAUT

func _ready() -> void:
	_config = _charger_json("res://data/banc_son.json")
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

	var declarations_sources: Array = _config.get("sources", [])
	_sources = fabriquer_sources(declarations_sources, catalogue_types, materiaux, proprietes_immuables)
	for decl in declarations_sources:
		_types_sources[decl.id] = decl.type

	_colons = fabriquer_colons(_config.get("colons", {}), catalogue_types)

	_couche_ui = CanvasLayer.new()
	add_child(_couche_ui)
	_taille_ecran = _taille_ecran_reelle()
	_poser_camera(points_de_cadrage(_sources, _colons, _config.get("mouvement_source_mobile", {})))

	for source in _sources:
		_sources_par_id[source.id] = source
		_monde.ajouter(source, _types_sources[source.id], source.position)
		_noeuds[source.id] = _creer_rendu(source.position, _couleur_de(_types_sources[source.id]))
		_labels[source.id] = _creer_label(source.position)
		_labels[source.id].text = texte_label_source(source.id, source.proprietes)

	for colon in _colons:
		_monde.ajouter(colon, "colon", colon.position)
		_noeuds[colon.id] = _creer_rendu(colon.position, _couleur_de(colon.id))
		_labels[colon.id] = _creer_label(colon.position)

	_prochain_print = _config.get("intervalle_print", 2.0)
	for source in _sources:
		print(ligne_source(0.0, source))

# ---- Boucle ----

func _process(delta: float) -> void:
	_temps += delta

	var mouvement: Dictionary = _config.get("mouvement_source_mobile", {})
	if not mouvement.is_empty() and _sources_par_id.has(mouvement.id):
		var mobile: Dictionary = _sources_par_id[mouvement.id]
		mobile.position = position_source_mobile(_temps, mouvement.amplitude_x, mouvement.y_fixe, mouvement.periode)
		_noeuds[mobile.id].position = Vector2(mobile.position.x, mobile.position.y) - _noeuds[mobile.id].size / 2.0
		_labels[mobile.id].position = _position_label_ecran(mobile.position)

	for colon in _colons:
		var ouie_config: Dictionary = colon.proprietes.canaux_config.ouie
		var ids: Array = sons_entendus(colon, _monde, _catalogue_canaux, ouie_config.get("frequence_min", 0.0), ouie_config.get("frequence_max", 0.0))
		ids.sort()
		if ids != _captures_precedentes.get(colon.id, []):
			_captures_precedentes[colon.id] = ids
			print(ligne_log(_temps, colon.id, ids))
		_labels[colon.id].text = texte_label_colon(colon.id, ouie_config, ids)

	if _temps >= _prochain_print:
		_prochain_print += _config.get("intervalle_print", 2.0)
		for source in _sources:
			print(ligne_source(_temps, source))

# ---- Fonctions statiques, pures, testables ----

# Meme patron que banc_chaleur_emise.gd:fabriquer_objets -- une source
# REELLE par declaration (composition fusionnee via Objet.fabriquer),
# "type" resolu contre catalogue_types (data/banc_son.json:types, fusionne
# par l'appelant avec les paquets partages).
static func fabriquer_sources(declarations: Array, catalogue_types: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> Array:
	var sources: Array = []
	for decl in declarations:
		var pos: Array = decl.position
		var source := Objet.fabriquer(decl.id, decl.type, Vector3(pos[0], pos[1], pos[2]), catalogue_types, materiaux, proprietes_immuables)
		if source.is_empty():
			continue
		sources.append(source)
	return sources

static func fabriquer_colons(declarations: Dictionary, catalogue_types: Dictionary) -> Array:
	var colons: Array = []
	for nom in declarations:
		colons.append(fabriquer_colon_son(nom, declarations[nom], catalogue_types))
	return colons

# Fabrique un colon partage (BancCommun.fabriquer_colon, INCHANGE) puis
# fusionne PAR-DESSUS canaux_config.ouie la surcharge locale de ce banc
# (decl.ouie_surcharge -- seuil/frequence_min/frequence_max) -- jamais un
# mecanisme du coeur qui la lirait pour ce banc, meme geste que le retrait
# local de profil_saillance dans banc_feu.gd:_ajouter_colon.
static func fabriquer_colon_son(nom: String, decl: Dictionary, catalogue_types: Dictionary) -> Dictionary:
	var colon := BancCommun.fabriquer_colon(nom, "colon", decl, catalogue_types)
	colon.proprietes.canaux_config.ouie.merge(decl.get("ouie_surcharge", {}), true)
	return colon

# Parmi tout ce que Perception.percevoir rend (tous canaux confondus --
# vue/odorat captent aussi geometriquement nos sources, sans filtre
# d'intensite ni de frequence), ne retient que les entrees captees par le
# canal "ouie" precisement -- necessaire pour observer le nouveau filtre de
# perception.gd isole des autres canaux.
static func captures_ouie(colon: Dictionary, monde, catalogue_canaux: Dictionary) -> Array:
	var perceptions: Array = Perception.percevoir(colon, monde, catalogue_canaux)
	var resultat: Array = []
	for entree in perceptions:
		if "ouie" in entree.canaux:
			resultat.append(entree)
	return resultat

# Retire toute entree dont "frequence" (proprietes, FACULTATIVE, defaut
# 0.0) tombe hors de [frequence_min, frequence_max] -- filtre PROPRE A CE
# BANC, jamais dans perception.gd (limite stricte du chantier).
static func filtrer_par_frequence(perceptions: Array, frequence_min: float, frequence_max: float) -> Array:
	var resultat: Array = []
	for entree in perceptions:
		var frequence: float = entree.chose.proprietes.get("frequence", 0.0)
		if frequence < frequence_min or frequence > frequence_max:
			continue
		resultat.append(entree)
	return resultat

static func ids_de(perceptions: Array) -> Array:
	var ids: Array = []
	for entree in perceptions:
		ids.append(entree.chose.id)
	return ids

# Point d'entree unique combinant les deux filtres (seuil, deja applique
# par perception.gd, PUIS frequence, applique ici) -- rend les ids des
# sources reellement entendues par ce colon, ce tick.
static func sons_entendus(colon: Dictionary, monde, catalogue_canaux: Dictionary, frequence_min: float, frequence_max: float) -> Array:
	var ouie: Array = captures_ouie(colon, monde, catalogue_canaux)
	var dans_la_plage: Array = filtrer_par_frequence(ouie, frequence_min, frequence_max)
	return ids_de(dans_la_plage)

# Oscillation PURE sur l'axe X, Y fixe -- distance a l'origine variant donc
# entre y_fixe (x=0) et sqrt(amplitude_x^2 + y_fixe^2) (x=+-amplitude_x),
# deux fois par periode. periode <= 0.0 : repli immobile en x=0 (donnee
# degeneree, jamais rencontree avec la config reelle de ce banc).
static func position_source_mobile(temps: float, amplitude_x: float, y_fixe: float, periode: float) -> Vector3:
	if periode <= 0.0:
		return Vector3(0.0, y_fixe, 0.0)
	var x: float = amplitude_x * sin(TAU * temps / periode)
	return Vector3(x, y_fixe, 0.0)

# Tous les points a CADRER dans la camera -- sources (position REELLE),
# colons, PLUS les deux extremes de l'oscillation de source_mobile_humain
# (jamais sa seule position de depart, sans quoi la camera la perdrait de
# vue une fois lancee -- voir mouvement_source_mobile, data/banc_son.json).
# "mouvement" vide (cle absente) : aucun point supplementaire, chemin mort.
static func points_de_cadrage(sources: Array, colons: Array, mouvement: Dictionary) -> Array:
	var points: Array = []
	for source in sources:
		points.append(source.position)
	for colon in colons:
		points.append(colon.position)
	if not mouvement.is_empty():
		var y_fixe: float = mouvement.get("y_fixe", 0.0)
		var amplitude_x: float = mouvement.get("amplitude_x", 0.0)
		points.append(Vector3(-amplitude_x, y_fixe, 0.0))
		points.append(Vector3(amplitude_x, y_fixe, 0.0))
	return points

# Zoom Camera2D qui fait tenir TOUS les points dans une fenetre
# `taille_ecran`, chacun entoure d'une `marge` (carre + bloc de label) --
# jamais un zoom fixe devine, toujours derive des positions REELLES de ce
# lancement. `points` vide ou reduit a un seul point : etendue nulle, repli
# sur ZOOM_MAX (rien a cadrer au-dela d'un point, jamais une division par
# zero). Zoom toujours borne a [ZOOM_MIN, ZOOM_MAX] -- une scene degeneree
# (points confondus ou aberrants) ne doit jamais produire un zoom nul, ni
# a l'inverse un zoom demesure qui ferait disparaitre les carres.
static func zoom_pour_cadrage(points: Array, marge: float, taille_ecran: Vector2) -> float:
	if points.size() < 2:
		return ZOOM_MAX
	var mini: Vector2 = Vector2(points[0].x, points[0].y)
	var maxi: Vector2 = mini
	for p in points:
		mini.x = min(mini.x, p.x)
		mini.y = min(mini.y, p.y)
		maxi.x = max(maxi.x, p.x)
		maxi.y = max(maxi.y, p.y)
	var largeur_monde: float = max(maxi.x - mini.x + marge * 2.0, 1.0)
	var hauteur_monde: float = max(maxi.y - mini.y + marge * 2.0, 1.0)
	var zoom: float = min(taille_ecran.x / largeur_monde, taille_ecran.y / hauteur_monde)
	return clamp(zoom, ZOOM_MIN, ZOOM_MAX)

# Centre (Vector2) du meme ensemble de points -- position de la camera,
# jamais recalculee autrement que par la moyenne des extremes (centre de
# la boite englobante, pas un barycentre pondere).
static func centre_de_cadrage(points: Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var mini: Vector2 = Vector2(points[0].x, points[0].y)
	var maxi: Vector2 = mini
	for p in points:
		mini.x = min(mini.x, p.x)
		mini.y = min(mini.y, p.y)
		maxi.x = max(maxi.x, p.x)
		maxi.y = max(maxi.y, p.y)
	return (mini + maxi) / 2.0

# Meme formule EXACTEMENT que scripts/perception.gd:_percevoir_propagation_obstacles
# -- recopiee ici pour l'affichage seul (labels), jamais consultee par
# sons_entendus ci-dessus (qui passe toujours par Perception.percevoir, le
# vrai chemin).
static func intensite_attenuee(son_emis: float, distance: float, portee: float) -> float:
	if portee <= 0.0:
		return 0.0
	return son_emis * (1.0 - distance / portee)

static func texte_label_source(id: String, proprietes: Dictionary) -> String:
	return "%s\nson_emis=%.2f\nfrequence=%.0f Hz" % [id, proprietes.get("son_emis", 0.0), proprietes.get("frequence", 0.0)]

static func texte_label_colon(id: String, ouie_config: Dictionary, ids_captes: Array) -> String:
	var entendu: String = ", ".join(ids_captes) if not ids_captes.is_empty() else "(rien)"
	return "%s\nseuil=%.2f frequence=%.0f-%.0f Hz\nentend: %s" % [
		id, ouie_config.get("seuil", 0.0), ouie_config.get("frequence_min", 0.0), ouie_config.get("frequence_max", 0.0), entendu,
	]

static func ligne_log(t: float, colon_id: String, ids: Array) -> String:
	var entendu: String = ", ".join(ids) if not ids.is_empty() else "(rien)"
	return "t=%.1f %s entend : %s" % [t, colon_id, entendu]

static func ligne_source(t: float, source: Dictionary) -> String:
	return "t=%.1fs %s : son_emis=%.2f frequence=%.0f Hz" % [t, source.id, source.proprietes.get("son_emis", 0.0), source.proprietes.get("frequence", 0.0)]

# ---- Rendu (impur, Node) -- aucune decision, seulement construction des
# noeuds et de la camera.

func _couleur_de(nom: String) -> Color:
	var rgb: Array = _config.get("couleurs_types", {}).get(nom, [1.0, 1.0, 1.0])
	return Color(rgb[0], rgb[1], rgb[2])

func _creer_rendu(position: Vector3, couleur: Color) -> ColorRect:
	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(TAILLE, TAILLE)
	noeud.color = couleur
	noeud.position = Vector2(position.x, position.y) - noeud.size / 2.0
	add_child(noeud)
	return noeud

# Label en CanvasLayer (bug visuel corrige, retour Yael) : un Label enfant
# du Node2D suit le ZOOM de la camera -- au zoom tres reduit qu'impose la
# grande etendue de ce banc (deux grappes tres eloignees, voir data/
# banc_son.json), sa police par defaut devenait illisible, quelle que soit
# sa taille en points. Un Label en CanvasLayer reste en ESPACE ECRAN, sa
# police (TAILLE_POLICE, forcee ci-dessous) ne retrecit donc plus jamais
# avec le zoom -- seule sa POSITION suit encore le monde, calculee UNE FOIS
# ici via _position_label_ecran (camera statique, sauf pour source_mobile_
# humain qui la recalcule chaque tick dans _process, voir plus haut).
func _creer_label(position: Vector3) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(LARGEUR_LABEL, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TAILLE_POLICE)
	label.position = _position_label_ecran(position)
	_couche_ui.add_child(label)
	return label

# Position ECRAN (CanvasLayer) d'un label ancre sous le carre qui
# represente `position_monde` -- centre horizontalement (LARGEUR_LABEL),
# juste sous le bord inferieur du carre a l'ecran (TAILLE * _zoom, jamais
# TAILLE seule : la taille APPARENTE du carre suit le zoom, le label doit
# rester colle a elle).
func _position_label_ecran(position_monde: Vector3) -> Vector2:
	var ecran: Vector2 = _monde_vers_ecran(position_monde)
	return ecran + Vector2(-LARGEUR_LABEL / 2.0, TAILLE / 2.0 * _zoom + 10.0)

# Conversion monde -> ecran pour la camera STATIQUE de ce banc (position et
# zoom fixes apres _ready -- seule la position MONDE d'un objet change,
# jamais la camera elle-meme) : meme formule que Camera2D applique en
# interne (centre de l'ecran + (monde - camera.position) * zoom).
func _monde_vers_ecran(position_monde: Vector3) -> Vector2:
	return (Vector2(position_monde.x, position_monde.y) - _camera.position) * _zoom + _taille_ecran / 2.0

# Camera qui CADRE TOUJOURS tout le banc (bug visuel corrige, retour Yael :
# "les deux groupes doivent utiliser toute la surface de la fenetre, pas un
# bandeau au centre") -- zoom/position derives des positions REELLES
# (points_de_cadrage/zoom_pour_cadrage/centre_de_cadrage, PURES, testables),
# jamais lus depuis data/banc_son.json:camera (ignore desormais : ce champ
# ne decrit plus un cadrage fiable une fois source_mobile_humain ajoutee,
# et un cadrage calcule depuis les positions reelles reste correct meme si
# une position venait a changer plus tard cote donnee).
func _poser_camera(points: Array) -> void:
	_zoom = zoom_pour_cadrage(points, MARGE_CADRAGE, _taille_ecran)
	var centre := centre_de_cadrage(points)
	_camera = Camera2D.new()
	_camera.position = centre
	_camera.zoom = Vector2(_zoom, _zoom)
	_camera.enabled = true
	add_child(_camera)

func _taille_ecran_reelle() -> Vector2:
	var taille: Vector2 = get_viewport().get_visible_rect().size
	if taille.x <= 0.0 or taille.y <= 0.0:
		return _TAILLE_ECRAN_DEFAUT
	return taille

func _charger_json(chemin: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
