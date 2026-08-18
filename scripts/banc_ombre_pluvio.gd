extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_ombre_pluvio.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier "ombre pluviometrique
# -- il pleut moins derriere la montagne" : premiere demonstration reelle de
# scripts/champ_occulte.gd (mecanisme du coeur neuf) et, par lui, de
# scripts/occlusion.gd (geometrie extraite de perception.gd par le meme
# chantier). Terrain modelise en objets ordinaires, CASES CONSTRUITES A LA
# MAIN (pas Objet.fabriquer, meme statut que banc_ecoulement.gd/
# banc_maladie.gd -- une case n'a pas de composition).
#
# CE QU'ON DOIT VOIR : une mer a gauche (source unique, hors grille, forte
# humidite_emission) arrose toute la plaine, de moins en moins fort en
# s'eloignant (loi en 1/d). Une montagne au centre (trois cases, un sommet
# encadre de deux epaules PLUS BASSES) porte une OMBRE vers la droite : les
# cases juste derriere le sommet sont les plus seches, celles derriere les
# epaules le sont moins, celles qui sortent du cone d'ombre (bord haut/bas de
# la grille, loin de l'axe mer-montagne) recoivent presque autant que si la
# montagne n'existait pas. GRADUE, JAMAIS UNE COUPURE NETTE : c'est tout le
# point du mecanisme (perception.gd, lui, ne peut rendre qu'un percu/non
# percu -- voir audit_terrain_et_monde_prealable.md §7).
#
# CLIC GAUCHE : bascule l'occlusion (montagne active / inactive), meme geste
# bistable que banc_radiation.gd/banc_acide.gd. AUCUNE case n'est deplacee ni
# reconstruite -- seule la liste d'obstacles passee a ChampOcculte.
# intensite_locale change (celle du relief, ou une liste vide). C'est la
# comparaison AVANT/APRES qui rend l'ombre lisible d'un coup d'oeil, et c'est
# la seule chose qui bouge dans ce banc : le champ est une fonction PURE des
# positions, rien n'y evolue avec le temps.
#
# LE VENT EST UN DECOR, ET RIEN D'AUTRE -- dit ici plutot que masque : la
# fleche et son libelle sont lus depuis data/banc_ombre_pluvio.json
# (vent_direction/vent_force), ce banc n'appelle JAMAIS scripts/vent.gd et le
# vent n'entre dans AUCUN calcul. champ_occulte.gd n'a pas de parametre de
# vent : une humidite portee par le vent serait un autre chantier (voir
# audit_terrain_et_monde_prealable.md §5, "l'appariement de deux voisins par
# un vecteur n'existe nulle part").
#
# ALTITUDE vs RELIEF_BLOQUANT (decision de donnee, pas de code) :
# proprietes.altitude porte l'altitude reelle (2.0 en plaine, jusqu'a 14.0 au
# sommet), DECOUPLEE de position (position.z reste 0.0, doctrine
# ecoulement.gd). proprietes.relief_bloquant en est la NORMALISATION [0,1] --
# c'est elle que lit occlusion.gd, jamais l'altitude brute : le facteur
# d'occlusion borne sa valeur a [0,1], une altitude brute clamperait a 1.0 et
# bloquerait TOTALEMENT, sans aucune gradation.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la grille, la source, la liste
#   d'obstacles et le rendu. _unhandled_input bascule l'occlusion. _process
#   appelle UNIQUEMENT avancer_humidite (qui n'est qu'une boucle sur
#   ChampOcculte.intensite_locale, jamais un calcul reimplemente) et lit le
#   resultat pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_ombre_pluvio.gd) : construire_grille/altitude_pour_case/
#   relief_bloquant_pour_altitude/construire_sources/obstacles_relief/
#   avancer_humidite/humidite_de/couleur_pour_humidite/couleur_pour_relief/
#   case_a/case_la_plus_proche, plus le texte d'affichage et de log.

const ChampOcculte = preload("res://scripts/champ_occulte.gd")

const TAILLE_CASE := 74.0
const MARGE_CASE := 6.0
const INTERVALLE_PRINT := 2.0

var _config: Dictionary = {}
var _cases: Array = []
var _sources: Array = []
var _obstacles: Array = []
var _relief_actif: bool = true
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _label_titre: Label
var _label_detail: Label
var _temps: float = 0.0
var _prochain_print: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_ombre_pluvio.json")

	_cases = construire_grille(_config)
	_sources = construire_sources(_config)
	_obstacles = obstacles_relief(_cases, _config.propriete_obstacle)

	for case in _cases:
		_creer_rendu_case(case)
	_creer_fleche_vent()
	_creer_source_visuelle()

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label_titre = Label.new()
	_label_titre.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label_titre)
	_label_detail = Label.new()
	_label_detail.position = Vector2(10.0, 34.0)
	couche_ui.add_child(_label_detail)

	_poser_camera()
	avancer_humidite(_cases, _sources, _obstacles, _config)
	_rafraichir_tout()
	print(_ligne_pose_initiale(_cases, _obstacles, _config))
	print(grille_texte(_cases, _config))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_relief_actif = not _relief_actif
	avancer_humidite(_cases, _sources, _obstacles_actifs(), _config)
	_rafraichir_tout()
	print("t=%.1f clic : relief %s" % [_temps, "ACTIF" if _relief_actif else "INACTIF"])
	print(grille_texte(_cases, _config))

func _process(delta: float) -> void:
	_temps += delta
	avancer_humidite(_cases, _sources, _obstacles_actifs(), _config)
	_rafraichir_tout()

	if _temps >= _prochain_print:
		_prochain_print = _temps + INTERVALLE_PRINT
		print(_ligne_trace(_temps, _cases, _config, _relief_actif))

func _obstacles_actifs() -> Array:
	return _obstacles if _relief_actif else []

func _rafraichir_tout() -> void:
	var reference: float = float(_config.humidite_reference)
	var taille_visible: float = TAILLE_CASE - MARGE_CASE
	for case in _cases:
		var id: String = case.id
		var humidite: float = humidite_de(case, _config)
		var bloquant: float = float(case.proprietes.get(_config.propriete_obstacle, 0.0))
		var noeud: ColorRect = _noeuds[id]
		if bloquant > 0.0:
			noeud.color = couleur_pour_relief(bloquant, _relief_actif)
			var hauteur: float = taille_visible * (1.0 + bloquant) if _relief_actif else taille_visible
			var bas: float = noeud.position.y + noeud.size.y
			noeud.size.y = hauteur
			noeud.position.y = bas - hauteur
		else:
			noeud.color = couleur_pour_humidite(humidite, reference)
		_labels[id].text = "%.1f\nr%.2f" % [humidite, bloquant]

	_label_titre.text = _texte_titre(_cases, _config, _relief_actif)
	var case_survolee: Variant = case_la_plus_proche(_cases, get_global_mouse_position(), TAILLE_CASE)
	_label_detail.text = _texte_detail(case_survolee, _config)

# ---- Fonctions PURES, testables headless (voir test_banc_ombre_pluvio.gd) ----

# Grille grille_colonnes x grille_lignes, ordre ligne-majeur. position en
# unites de GRILLE (x=colonne, y=ligne, z=0.0 TOUJOURS -- l'altitude vit dans
# proprietes, voir en-tete). Chaque case porte son altitude, sa normalisation
# relief_bloquant [0,1] et une humidite initialisee a 0.0 (ecrite au premier
# avancer_humidite, jamais lue avant).
static func construire_grille(config: Dictionary) -> Array:
	var colonnes: int = int(config.grille_colonnes)
	var lignes: int = int(config.grille_lignes)
	var cases: Array = []
	for ligne in range(lignes):
		for colonne in range(colonnes):
			var altitude: float = altitude_pour_case(colonne, ligne, config)
			cases.append({
				"id": "case_%d_%d" % [colonne, ligne],
				"position": Vector3(float(colonne), float(ligne), 0.0),
				"proprietes": {
					config.nom_altitude: altitude,
					config.propriete_obstacle: relief_bloquant_pour_altitude(altitude, config),
					config.nom_propriete_humidite: 0.0,
				},
			})
	return cases

# PROFIL DE MONTAGNE, pas un mur (voir data/banc_ombre_pluvio.json) : sur la
# colonne de relief, la ligne du sommet porte altitude_sommet, les autres
# lignes de relief altitude_epaule (plus basse) -- c'est cette difference qui
# GRADUE l'ombre portee ligne par ligne. Partout ailleurs : altitude_plaine.
static func altitude_pour_case(colonne: int, ligne: int, config: Dictionary) -> float:
	if colonne != int(config.colonne_relief):
		return float(config.altitude_plaine)
	if not _liste_contient(config.lignes_relief, ligne):
		return float(config.altitude_plaine)
	if ligne == int(config.ligne_sommet):
		return float(config.altitude_sommet)
	return float(config.altitude_epaule)

# JSON.parse_string rend TOUT nombre en float, y compris "1" ecrit sans
# decimale (verifie a l'execution : [1,2,3] devient [1.0, 2.0, 3.0]) -- et
# Array.has() est STRICT sur le type, donc [1.0,2.0,3.0].has(1) rend FALSE.
# Ce piege a coute un banc entier construit sans relief au premier lancement.
# D'ou cette comparaison numerique explicite, jamais Array.has().
static func _liste_contient(liste: Array, valeur: int) -> bool:
	for element in liste:
		if int(element) == valeur:
			return true
	return false

# Normalisation [0,1] de l'altitude entre altitude_plancher et
# altitude_plafond -- c'est CETTE valeur que lit occlusion.gd, jamais
# l'altitude brute (voir en-tete). Plafond <= plancher (donnee incoherente) :
# rend 0.0, jamais une division par zero.
static func relief_bloquant_pour_altitude(altitude: float, config: Dictionary) -> float:
	var plancher: float = float(config.altitude_plancher)
	var plafond: float = float(config.altitude_plafond)
	if plafond <= plancher:
		return 0.0
	return clamp((altitude - plancher) / (plafond - plancher), 0.0, 1.0)

# La mer : UNE source, posee HORS de la grille (source_position.x negatif),
# centree verticalement. Ce n'est PAS une case : elle n'est ni dans _cases,
# ni obstacle, ni jamais arrosee elle-meme.
static func construire_sources(config: Dictionary) -> Array:
	return [{
		"id": "mer",
		"position": _vecteur_depuis_dict(config.source_position),
		"proprietes": {config.propriete_emission: float(config.humidite_emission)},
	}]

# Les obstacles sont les SEULES cases dont la propriete d'obstruction est
# strictement positive (le relief). Les cases de plaine, a 0.0, seraient de
# toute facon transparentes -- les exclure evite d'en tester 57 pour rien a
# chaque source (voir champ_occulte.gd, COUT).
static func obstacles_relief(cases: Array, propriete_obstacle: String) -> Array:
	var obstacles: Array = []
	for case in cases:
		if float(case.proprietes.get(propriete_obstacle, 0.0)) > 0.0:
			obstacles.append(case)
	return obstacles

# Ecrit, sur CHAQUE case, l'intensite rendue par le mecanisme -- le cablage
# ecrit, le mecanisme ne mute jamais rien (champ_occulte.gd, en-tete). Aucune
# accumulation, aucun etat : la valeur est ECRASEE a chaque appel, le champ
# etant une fonction pure des positions.
static func avancer_humidite(cases: Array, sources: Array, obstacles: Array, config: Dictionary) -> void:
	var propriete_obstacle: String = config.propriete_obstacle
	var largeur: float = float(config.largeur_obstacle)
	var propriete_emission: String = config.propriete_emission
	var exposant: float = float(config.exposant_distance)
	var nom_humidite: String = config.nom_propriete_humidite
	for case in cases:
		case.proprietes[nom_humidite] = ChampOcculte.intensite_locale(
			case.position, sources, obstacles, propriete_obstacle, largeur, propriete_emission, exposant)

static func humidite_de(case: Dictionary, config: Dictionary) -> float:
	return float(case.proprietes.get(config.nom_propriete_humidite, 0.0))

static func case_a(cases: Array, colonne: int, ligne: int) -> Variant:
	for case in cases:
		if int(case.position.x) == colonne and int(case.position.y) == ligne:
			return case
	return null

# Jaune (sec) -> bleu (humide), au ratio humidite/reference borne [0,1].
# reference <= 0.0 : rend systematiquement le jaune sec, jamais une division
# par zero.
static func couleur_pour_humidite(humidite: float, reference: float) -> Color:
	var ratio: float = clamp(humidite / reference, 0.0, 1.0) if reference > 0.0 else 0.0
	var sec := Color(0.86, 0.78, 0.30)
	var humide := Color(0.08, 0.32, 0.78)
	return sec.lerp(humide, ratio)

# Brun clair -> brun sombre selon la force d'obstruction. Relief INACTIF
# (occlusion basculee au clic) : gris terne, pour qu'on voie d'un coup d'oeil
# que la montagne ne bloque plus rien.
static func couleur_pour_relief(bloquant: float, actif: bool) -> Color:
	if not actif:
		return Color(0.42, 0.42, 0.44)
	return Color(0.55, 0.44, 0.30).lerp(Color(0.28, 0.20, 0.13), clamp(bloquant, 0.0, 1.0))

# Retrouve la case dont la position de GRILLE (convertie en pixels par
# taille_case) est la plus proche de "position_ecran" -- pour le survol.
# Rend null si "cases" est vide (chemin mort, jamais atteint en jeu reel).
static func case_la_plus_proche(cases: Array, position_ecran: Vector2, taille_case: float) -> Variant:
	if cases.is_empty():
		return null
	var meilleure: Variant = null
	var meilleure_distance := INF
	for case in cases:
		var pos: Vector3 = case.position
		var distance: float = (Vector2(pos.x, pos.y) * taille_case).distance_to(position_ecran)
		if distance < meilleure_distance:
			meilleure_distance = distance
			meilleure = case
	return meilleure

# Grille d'humidites en texte, une ligne par ligne de grille -- la seule
# facon d'observer ce banc en headless (voir docs/prototypes.md). Les cases
# de relief sont marquees d'un '#'.
static func grille_texte(cases: Array, config: Dictionary) -> String:
	var colonnes: int = int(config.grille_colonnes)
	var lignes: int = int(config.grille_lignes)
	var texte := ""
	for ligne in range(lignes):
		var morceaux: Array = []
		for colonne in range(colonnes):
			var case: Variant = case_a(cases, colonne, ligne)
			if case == null:
				continue
			var marque: String = "#" if float(case.proprietes.get(config.propriete_obstacle, 0.0)) > 0.0 else " "
			morceaux.append("%5.2f%s" % [humidite_de(case, config), marque])
		texte += "  ligne %d : %s\n" % [ligne, " ".join(morceaux)]
	return texte

static func _texte_titre(cases: Array, config: Dictionary, relief_actif: bool) -> String:
	var vent: Vector3 = _vecteur_depuis_dict(config.vent_direction)
	return "ombre pluviometrique -- relief %s (clic gauche pour basculer) | vent %s force %.1f (DECOR : n'entre dans aucun calcul) | %s" % [
		"ACTIF" if relief_actif else "INACTIF",
		"->" if vent.x >= 0.0 else "<-",
		float(config.vent_force),
		_texte_temoins(cases, config),
	]

static func _texte_temoins(cases: Array, config: Dictionary) -> String:
	var devant: Variant = _case_temoin(cases, config.case_temoin_devant)
	var ombre: Variant = _case_temoin(cases, config.case_temoin_ombre)
	var bord: Variant = _case_temoin(cases, config.case_temoin_bord)
	if devant == null or ombre == null or bord == null:
		return ""
	return "devant=%.2f derriere_axe=%.2f derriere_bord=%.2f" % [
		humidite_de(devant, config), humidite_de(ombre, config), humidite_de(bord, config)
	]

static func _case_temoin(cases: Array, reference: Dictionary) -> Variant:
	return case_a(cases, int(reference.colonne), int(reference.ligne))

static func _texte_detail(case: Variant, config: Dictionary) -> String:
	if case == null:
		return ""
	var p: Dictionary = case.proprietes
	return "%s : %s=%.3f %s=%.3f %s=%.2f" % [
		case.id,
		config.nom_propriete_humidite, humidite_de(case, config),
		config.propriete_obstacle, float(p.get(config.propriete_obstacle, 0.0)),
		config.nom_altitude, float(p.get(config.nom_altitude, 0.0)),
	]

static func _ligne_pose_initiale(cases: Array, obstacles: Array, config: Dictionary) -> String:
	return "t=0.0 grille posee : %d cases (%dx%d), %d cases de relief, source '%s' a %s (%s=%.1f)" % [
		cases.size(), int(config.grille_colonnes), int(config.grille_lignes), obstacles.size(),
		"mer", _vecteur_depuis_dict(config.source_position), config.propriete_emission,
		float(config.humidite_emission),
	]

static func _ligne_trace(t: float, cases: Array, config: Dictionary, relief_actif: bool) -> String:
	return "t=%.1f relief=%s %s" % [t, "ACTIF" if relief_actif else "INACTIF", _texte_temoins(cases, config)]

static func _vecteur_depuis_dict(d: Dictionary) -> Vector3:
	return Vector3(d.get("x", 0.0), d.get("y", 0.0), d.get("z", 0.0))

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds, la fleche de decor et la camera.

func _creer_rendu_case(case: Dictionary) -> void:
	var id: String = case.id
	var pos: Vector3 = case.position
	var centre := Vector2(pos.x, pos.y) * TAILLE_CASE
	var taille_visible := TAILLE_CASE - MARGE_CASE

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.size = Vector2(taille_visible, taille_visible)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)
	_noeuds[id] = noeud

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 11)
	label.position = centre - Vector2(taille_visible / 2.0 - 4.0, taille_visible / 2.0 - 2.0)
	add_child(label)
	_labels[id] = label

func _creer_fleche_vent() -> void:
	var vent: Vector3 = _vecteur_depuis_dict(_config.vent_direction)
	var y: float = -1.4 * TAILLE_CASE
	var depart := Vector2(-1.0 * TAILLE_CASE, y)
	var arrivee := Vector2(float(int(_config.grille_colonnes) - 1) * TAILLE_CASE, y)
	if vent.x < 0.0:
		var echange := depart
		depart = arrivee
		arrivee = echange

	# "trait" est un mot reserve de GDScript (verifie a l'execution : Parse
	# Error) -- d'ou "ligne_vent".
	var ligne_vent := Line2D.new()
	ligne_vent.width = 4.0
	ligne_vent.default_color = Color(0.75, 0.75, 0.80)
	ligne_vent.add_point(depart)
	ligne_vent.add_point(arrivee)
	add_child(ligne_vent)

	var sens: float = 1.0 if arrivee.x >= depart.x else -1.0
	var pointe := Polygon2D.new()
	pointe.color = Color(0.75, 0.75, 0.80)
	pointe.polygon = PackedVector2Array([
		arrivee,
		arrivee - Vector2(sens * 22.0, 11.0),
		arrivee - Vector2(sens * 22.0, -11.0),
	])
	add_child(pointe)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.position = depart + Vector2(0.0, -30.0)
	label.text = "vent (decor : n'entre dans aucun calcul)"
	add_child(label)

func _creer_source_visuelle() -> void:
	var pos: Vector3 = _vecteur_depuis_dict(_config.source_position)
	var centre := Vector2(pos.x, pos.y) * TAILLE_CASE

	var noeud := ColorRect.new()
	noeud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noeud.color = Color(0.05, 0.25, 0.65)
	noeud.size = Vector2(TAILLE_CASE * 0.9, TAILLE_CASE * 2.4)
	noeud.position = centre - noeud.size / 2.0
	add_child(noeud)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.position = noeud.position + Vector2(0.0, -22.0)
	label.text = "mer (%s=%.0f)" % [_config.propriete_emission, float(_config.humidite_emission)]
	add_child(label)

func _poser_camera() -> void:
	var colonnes: int = int(_config.grille_colonnes)
	var lignes: int = int(_config.grille_lignes)
	var centre := Vector2(float(colonnes - 1) / 2.0 - 1.0, float(lignes - 1) / 2.0) * TAILLE_CASE
	var camera := Camera2D.new()
	camera.position = centre
	camera.zoom = Vector2(0.82, 0.82)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
