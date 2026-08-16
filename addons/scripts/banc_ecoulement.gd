extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_ecoulement.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier "ecoulement
# gravitaire -- eau par pente" : premiere demonstration reelle de
# scripts/ecoulement.gd (mecanisme du coeur neuf) sur un TERRAIN modelise en
# objets ordinaires (grille de cases-objets, patron "tout est objet" --
# jamais une structure separee, voir audit_ecoulement_gravitaire_
# prealable.md §1). CASES CONSTRUITES A LA MAIN (pas Objet.fabriquer, meme
# statut que banc_maladie.gd/banc_toxicite.gd -- une case n'a pas de
# composition, aucune densite/masse a calculer).
#
# MODELE DE POSITION (decision Yael, question posee avant d'ecrire) :
# case.position reste un FAIT SPATIAL PUR, en unites de GRILLE (x=colonne,
# y=ligne, z=0.0 TOUJOURS) -- jamais l'altitude. L'altitude vit dans
# proprietes.altitude (nom_altitude passe a Ecoulement.avancer), DECOUPLEE
# de position : rayon_voisinage=1.5 (data/banc_ecoulement.json) couvre les 8
# voisins Moore adjacents (orthogonaux a 1.0, diagonaux a sqrt(2)) SANS
# jamais etre pollue par l'ecart d'altitude entre deux cases -- voir
# scripts/ecoulement.gd, meme rationale. Le rendu (ColorRect) convertit
# separement l'index de grille en pixels via TAILLE_CASE, jamais case.
# position lui-meme.
#
# ABSORPTION + EVAPORATION -- AUCUN CODE NEUF, reutilise depense.gd TEL
# QUEL : le canal reserves.<nom_reserve> de chaque case porte cout_base
# (absorption, DERIVE de permeabilite UNE FOIS a la construction, meme
# formule que scripts/banc_permeabilite.gd:taux_decroissance_permeabilite --
# plancher + facteur*permeabilite) ET surcout_action (evaporation_par_s,
# CONSTANTE globale -- reutilise le meme champ que depense.gd credite deja a
# "ce que l'action en cours coute", ici une perte seche constante plutot
# qu'une action ; depense.gd ne connait de toute facon aucun nom de domaine,
# voir sa propre doctrine). Un seul appel a Depense.avancer(cases, delta)
# par tick decremente les deux a la fois -- AUCUNE distinction cote
# mecanisme, seulement a l'AFFICHAGE (diagnostiquer_absorption_evaporation
# ci-dessous, fonction PURE qui rejoue le MEME calcul borne que depense.gd
# EN LECTURE SEULE avant l'appel reel, pour scinder le total en deux
# nombres a la trace -- jamais une deuxieme source de verite).
#
# CE QU'ON DOIT VOIR : une pente (montagne a gauche, altitude_max ;
# vallee a droite, altitude_min), moitie gauche en terre (permeable,
# absorbe vite), moitie droite en roche (impermeable, retient longtemps.
# De l'eau posee sur la colonne de gauche (colonne 0) coule de case en
# case vers la droite ET vers le bas de la pente (ecoulement.gd, la
# hauteur = altitude + eau, jamais en sens inverse), s'accumule
# temporairement avant de s'infiltrer/evaporer (depense.gd). Chaque case
# change de couleur (brun/vert sec -> bleu sature) et sa barre de niveau
# monte/descend avec sa reserve d'eau. Un compteur en haut affiche l'eau
# totale du systeme, qui descend au cours du temps (absorption +
# evaporation, jamais l'ecoulement lui-meme qui ne fait que deplacer
# l'eau). Un clic gauche ajoute de l'eau (+ajout_clic) sur la case sous
# la souris, pour experimenter. Un label de detail affiche altitude/
# niveau_eau/permeabilite/type_sol de la case survolee.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la grille et le rendu. _unhandled_input
#   ajoute de l'eau au clic. _process appelle UNIQUEMENT Ecoulement.avancer
#   puis Depense.avancer (fonctions du coeur, jamais reimplementees) et lit
#   leurs resultats pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_ecoulement.gd) : construire_grille/type_sol_pour_colonne/
#   altitude_pour_colonne/cout_base_absorption/
#   diagnostiquer_absorption_evaporation/couleur_pour_niveau/
#   case_la_plus_proche/ajouter_eau, plus le texte d'affichage et de log.

const Ecoulement = preload("res://scripts/ecoulement.gd")
const Depense = preload("res://scripts/depense.gd")
const Somme = preload("res://scripts/somme.gd")

const TAILLE_CASE := 60.0
const MARGE_CASE := 4.0
const HAUTEUR_BARRE := 8.0
const INTERVALLE_PRINT := 1.0

var _config: Dictionary = {}
var _materiaux: Dictionary = {}
var _cases: Array = []
var _noeuds: Dictionary = {}
var _barres_fond: Dictionary = {}
var _barres_remplies: Dictionary = {}
var _labels_niveau: Dictionary = {}
var _label_compteur: Label
var _label_detail: Label
var _temps: float = 0.0
var _prochain_print: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_ecoulement.json")
	_materiaux = _charger_json("res://data/materiaux.json")

	_cases = construire_grille(_config, _materiaux)
	for case in _cases:
		_creer_rendu_case(case)

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label_compteur = Label.new()
	_label_compteur.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label_compteur)
	_label_detail = Label.new()
	_label_detail.position = Vector2(10.0, 34.0)
	couche_ui.add_child(_label_detail)

	_poser_camera()
	_rafraichir_tout()
	print(_ligne_pose_initiale(_cases, _config.nom_reserve))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos := get_global_mouse_position()
	var case: Variant = case_la_plus_proche(_cases, pos, TAILLE_CASE)
	if case == null:
		return
	ajouter_eau(case, _config.nom_reserve, _config.ajout_clic)
	print("t=%.1f clic : +%.2f sur %s" % [_temps, _config.ajout_clic, case.id])
	_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta

	var transferts: Array = Ecoulement.avancer(_cases, _config.rayon_voisinage, _config.nom_reserve, _config.nom_altitude, _config.taux_ecoulement, delta)
	var diag_depense: Dictionary = diagnostiquer_absorption_evaporation(_cases, _config.nom_reserve, delta)
	Depense.avancer(_cases, delta, {})

	_rafraichir_tout()

	if _temps >= _prochain_print:
		_prochain_print = _temps + INTERVALLE_PRINT
		var total: float = Somme.reserves(_cases, _config.nom_reserve)
		print(_ligne_trace(_temps, transferts.size(), total, diag_depense.absorbe, diag_depense.evapore))

func _rafraichir_tout() -> void:
	var total: float = Somme.reserves(_cases, _config.nom_reserve)
	_label_compteur.text = "eau totale : %.2f" % total

	var reference: float = float(_config.eau_initiale)
	for case in _cases:
		var id: String = case.id
		var niveau: float = case.proprietes.reserves[_config.nom_reserve].reserve
		var type_sol: String = case.proprietes.type_sol
		_noeuds[id].color = couleur_pour_niveau(niveau, type_sol, reference)
		var ratio: float = clamp(niveau / reference, 0.0, 1.0) if reference > 0.0 else 0.0
		_barres_remplies[id].size.y = _barres_fond[id].size.y * ratio
		_barres_remplies[id].position.y = _barres_fond[id].position.y + _barres_fond[id].size.y * (1.0 - ratio)
		_labels_niveau[id].text = "%.1f" % niveau

	var pos_souris := get_global_mouse_position()
	var case_survolee: Variant = case_la_plus_proche(_cases, pos_souris, TAILLE_CASE)
	_label_detail.text = _texte_detail(case_survolee, _config.nom_reserve, _config.nom_altitude)

# ---- Fonctions PURES, testables headless (voir test_banc_ecoulement.gd) ----

# Construit la grille grille_lignes x grille_colonnes, index colonne d'abord
# (position.x=colonne, position.y=ligne, position.z=0.0 TOUJOURS -- voir
# en-tete, "MODELE DE POSITION"). Rend un Array plat, ordre ligne-majeur
# (index = ligne*grille_colonnes + colonne).
static func construire_grille(config: Dictionary, materiaux: Dictionary) -> Array:
	var lignes: int = config.grille_lignes
	var colonnes: int = config.grille_colonnes
	var cases: Array = []
	for ligne in range(lignes):
		for colonne in range(colonnes):
			var type_sol := type_sol_pour_colonne(colonne, colonnes, config)
			var permeabilite: float = float(materiaux.get(type_sol, {}).get("permeabilite", 0.0))
			var altitude := altitude_pour_colonne(colonne, colonnes, config.altitude_max, config.altitude_min)
			var eau_initiale: float = float(config.eau_initiale) if colonne == 0 else 0.0
			cases.append({
				"id": "case_%d_%d" % [colonne, ligne],
				"position": Vector3(float(colonne), float(ligne), 0.0),
				"proprietes": {
					config.nom_altitude: altitude,
					"permeabilite": permeabilite,
					"type_sol": type_sol,
					"reserves": {
						config.nom_reserve: {
							"reserve": eau_initiale,
							"cout_base": cout_base_absorption(permeabilite, config),
							"surcout_action": float(config.evaporation_par_s),
							"seuils_ref": "",
						},
					},
				},
			})
	return cases

# Moitie gauche des colonnes (colonne < colonnes/2) : materiau_gauche
# (permeable) ; moitie droite : materiau_droite (impermeable) -- voir
# data/banc_ecoulement.json.
static func type_sol_pour_colonne(colonne: int, colonnes: int, config: Dictionary) -> String:
	return config.materiau_gauche if colonne < colonnes / 2 else config.materiau_droite

# Interpolation lineaire, colonne 0 = altitude_max (montagne, gauche),
# derniere colonne = altitude_min (vallee, droite). colonnes<=1 : rend
# altitude_max, chemin degenere jamais atteint par la config reelle (8
# colonnes) mais garde defensive contre une division par zero.
static func altitude_pour_colonne(colonne: int, colonnes: int, altitude_max: float, altitude_min: float) -> float:
	if colonnes <= 1:
		return altitude_max
	var ratio: float = float(colonne) / float(colonnes - 1)
	return lerp(altitude_max, altitude_min, ratio)

# taux_decroissance = taux_decroissance_plancher + facteur_permeabilite *
# permeabilite -- MEME FORMULE que scripts/banc_permeabilite.gd:
# taux_decroissance_permeabilite, ECRITE ici comme cout_base du canal de
# reserve (scripts/depense.gd), jamais comme un taux_decroissance de
# charge.gd (ce banc n'utilise pas charge.gd).
static func cout_base_absorption(permeabilite: float, config: Dictionary) -> float:
	var plancher: float = config.get("taux_decroissance_plancher", 0.0)
	var facteur: float = config.get("facteur_permeabilite", 0.0)
	return plancher + facteur * permeabilite

# Rejoue EN LECTURE SEULE, AVANT l'appel reel a Depense.avancer, le MEME
# calcul borne que depense.gd:_avancer_canal (reserve - (cout_base+
# surcout_action)*delta, borne a zero) -- scinde ensuite le decrement total
# de CHAQUE case, proportionnellement a cout_base/(cout_base+surcout_action),
# entre "absorbe" (cout_base) et "evapore" (surcout_action). JAMAIS une
# deuxieme source de verite : la MUTATION reelle vient toujours de
# Depense.avancer, cette fonction ne fait QUE lire pour produire deux
# nombres de trace la ou depense.gd n'en rend qu'un (implicite, dans la
# reserve decrue). cout_base+surcout_action == 0.0 : rend un decrement nul
# des deux cotes, chemin mort legitime (rien a decomposer).
static func diagnostiquer_absorption_evaporation(cases: Array, nom_reserve: String, delta: float) -> Dictionary:
	var absorbe := 0.0
	var evapore := 0.0
	for case in cases:
		var canal: Dictionary = case.proprietes.reserves.get(nom_reserve, {})
		var reserve: float = float(canal.get("reserve", 0.0))
		var cout_base: float = float(canal.get("cout_base", 0.0))
		var surcout: float = float(canal.get("surcout_action", 0.0))
		var somme_couts: float = cout_base + surcout
		if somme_couts <= 0.0:
			continue
		var decrement: float = min(reserve, somme_couts * delta)
		absorbe += decrement * (cout_base / somme_couts)
		evapore += decrement * (surcout / somme_couts)
	return {"absorbe": absorbe, "evapore": evapore}

# Couleur : moyenne ponderee (lerp) entre la couleur "sec" du type de sol
# (brun pour terre, gris pour roche -- JAMAIS un nom de type en dur ailleurs
# que dans CE tableau de rendu, discipline "banc jetable peut nommer une
# categorie pour poser une scene d'observation", CLAUDE.md) et un bleu
# sature, au ratio niveau/reference (borne [0,1]). reference<=0.0 : rend
# systematiquement la couleur seche (ratio 0), jamais une division par
# zero.
static func couleur_pour_niveau(niveau: float, type_sol: String, reference: float) -> Color:
	var ratio: float = clamp(niveau / reference, 0.0, 1.0) if reference > 0.0 else 0.0
	var sec: Color = Color(0.42, 0.30, 0.16) if type_sol == "terre" else Color(0.5, 0.5, 0.52)
	var sature: Color = Color(0.05, 0.15, 0.55)
	return sec.lerp(sature, ratio)

# Retrouve la case dont la position de GRILLE (convertie en pixels par
# taille_case) est la plus proche de "position_ecran" -- utilise pour le
# clic ET pour le survol. Rend null si "cases" est vide (chemin mort,
# jamais atteint en jeu reel).
static func case_la_plus_proche(cases: Array, position_ecran: Vector2, taille_case: float) -> Variant:
	if cases.is_empty():
		return null
	var meilleure: Variant = null
	var meilleure_distance := INF
	for case in cases:
		var pos: Vector3 = case.position
		var pos_ecran_case := Vector2(pos.x, pos.y) * taille_case
		var distance: float = pos_ecran_case.distance_to(position_ecran)
		if distance < meilleure_distance:
			meilleure_distance = distance
			meilleure = case
	return meilleure

# Mute "case" en place : credite "quantite" sur le canal nom_reserve (cree
# le canal minimal s'il n'existe pas encore -- meme geste que
# consommer.gd:_crediter, RECOPIE ici, jamais un appel croise -- ce fichier
# ne cable QUE ce banc).
static func ajouter_eau(case: Dictionary, nom_reserve: String, quantite: float) -> void:
	var reserves: Dictionary = case.proprietes.get("reserves", {})
	if not reserves.has(nom_reserve):
		reserves[nom_reserve] = {"reserve": 0.0}
	var canal: Dictionary = reserves[nom_reserve]
	canal["reserve"] = canal.get("reserve", 0.0) + quantite
	case.proprietes["reserves"] = reserves

static func _texte_detail(case: Variant, nom_reserve: String, nom_altitude: String) -> String:
	if case == null:
		return ""
	var p: Dictionary = case.proprietes
	var niveau: float = float(p.get("reserves", {}).get(nom_reserve, {}).get("reserve", 0.0))
	return "%s : altitude=%.2f niveau_eau=%.2f permeabilite=%.2f type_sol=%s" % [
		case.id, p.get(nom_altitude, 0.0), niveau, p.get("permeabilite", 0.0), p.get("type_sol", "?")
	]

static func _ligne_pose_initiale(cases: Array, nom_reserve: String) -> String:
	return "t=0.0 grille posee : %d cases, eau totale=%.2f" % [cases.size(), Somme.reserves(cases, nom_reserve)]

static func _ligne_trace(t: float, nb_transferts: int, total: float, absorbe: float, evapore: float) -> String:
	return "t=%.1f transferts=%d eau_totale=%.2f absorbee=%.4f evaporee=%.4f" % [t, nb_transferts, total, absorbe, evapore]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction
# des noeuds et la camera.

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

	var fond := ColorRect.new()
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fond.color = Color(0.15, 0.15, 0.15)
	fond.size = Vector2(HAUTEUR_BARRE, taille_visible)
	fond.position = centre + Vector2(taille_visible / 2.0 + 3.0, -taille_visible / 2.0)
	add_child(fond)
	_barres_fond[id] = fond

	var rempli := ColorRect.new()
	rempli.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rempli.color = Color(0.2, 0.55, 0.9)
	rempli.size = Vector2(HAUTEUR_BARRE, 0.0)
	rempli.position = fond.position + Vector2(0.0, fond.size.y)
	add_child(rempli)
	_barres_remplies[id] = rempli

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 10)
	label.position = centre - Vector2(taille_visible / 2.0, taille_visible / 2.0 + 2.0)
	add_child(label)
	_labels_niveau[id] = label

func _poser_camera() -> void:
	var lignes: int = _config.grille_lignes
	var colonnes: int = _config.grille_colonnes
	var centre := Vector2(float(colonnes - 1), float(lignes - 1)) * TAILLE_CASE / 2.0
	var camera := Camera2D.new()
	camera.position = centre
	camera.zoom = Vector2(0.9, 0.9)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
