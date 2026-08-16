extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_biomes.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier "biomes -- conditions
# multiples -> type de terrain" : premiere demonstration reelle de
# scripts/conditions.gd REJOUE A CHAQUE TICK, avec retirer_si_faux=true --
# c'est-a-dire de la REVERSIBILITE, la seule chose que
# objet.gd:_evaluer_emergences ne pouvait pas montrer (il n'evalue qu'une
# fois, a la naissance de l'objet, et ne retire jamais).
#
# CASES CONSTRUITES A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_ecoulement.gd/banc_maladie.gd/banc_toxicite.gd -- une case n'a pas de
# composition, aucune densite/masse a calculer). MODELE DE POSITION identique
# a banc_ecoulement.gd : position = fait spatial pur en unites de GRILLE
# (x=colonne, y=ligne, z=0.0 TOUJOURS) ; le rendu convertit separement en
# pixels via TAILLE_CASE, jamais case.position lui-meme.
#
# CE QU'ON DOIT VOIR : une grille 6x6 ou l'humidite croit vers la DROITE
# (colonnes) et la temperature vers le BAS (lignes) -- deux axes croises, donc
# les cinq rendus possibles (desert/foret/toundra/marais/aucun) presents des le
# demarrage. Chaque case affiche son humidite, sa temperature et son biome, et
# prend la couleur de ce biome. Un compteur en haut donne le nombre de cases
# par biome. UN CLIC GAUCHE RECHAUFFE TOUT LE MONDE (+pas_temperature), UN CLIC
# DROIT REFROIDIT (-pas_temperature) : les biomes se reorganisent EN DIRECT --
# la foret perd son biome puis devient toundra quand on refroidit, la retrouve
# quand on rechauffe. Chaque changement de biome d'une case est trace en
# console.
#
# HUMIDITE AUX FLECHES HAUT/BAS (+/-pas_humidite), AJOUT NOMME, hors de la
# consigne d'origine : celle-ci ne demandait qu'un controle de TEMPERATURE au
# clic, mais decrivait aussi "le marais devient desert si l'humidite baisse" --
# inatteignable avec la temperature seule (desert exige humidite<0.2, marais
# humidite>=0.8, et aucun clic ne pouvait franchir cet ecart). Le controle
# d'humidite existe donc pour rendre CETTE transition observable ; le retirer
# ne casserait rien d'autre que cette demonstration.
#
# LE CLIMAT NE DERIVE JAMAIS : chaque case garde ses valeurs de BASE
# (humidite_base/temperature_base, posees une fois a la construction, jamais
# mutees). L'humidite/temperature EFFECTIVE est recalculee CHAQUE TICK comme
# base + decalage global courant (appliquer_climat, PURE et IDEMPOTENTE) --
# jamais un "+= pas" accumule sur la case elle-meme, qui aurait fait diverger
# les cases entre elles au moindre tick manque. L'humidite effective est
# BORNEE a [0,1] (un ratio), la temperature ne l'est pas (des degres Celsius
# n'ont pas de plafond de jeu).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la grille et le rendu ; _unhandled_input
#   ne fait que deplacer deux nombres (_decalage_temperature/_decalage_
#   humidite), jamais calculer ; _process appelle appliquer_climat puis
#   evaluer_biomes (qui appelle Conditions.evaluer, mecanisme du coeur, jamais
#   reimplemente) et lit leurs resultats pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_biomes.gd) : construire_grille/humidite_pour_colonne/
#   temperature_pour_ligne/appliquer_climat/evaluer_biomes/compter_par_biome/
#   couleur_pour_biome/case_la_plus_proche, plus les textes d'affichage et de
#   log.

const Conditions = preload("res://scripts/conditions.gd")

const TAILLE_CASE := 96.0
const MARGE_CASE := 6.0

var _config: Dictionary = {}
var _catalogue: Array = []
var _cases: Array = []
var _noeuds: Dictionary = {}
var _labels: Dictionary = {}
var _label_compteur: Label
var _label_climat: Label
var _decalage_temperature: float = 0.0
var _decalage_humidite: float = 0.0
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_biomes.json")
	_catalogue = _charger_json("res://data/biomes.json").get("biomes", [])

	_cases = construire_grille(_config)
	for case in _cases:
		_creer_rendu_case(case)

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label_compteur = Label.new()
	_label_compteur.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label_compteur)
	_label_climat = Label.new()
	_label_climat.position = Vector2(10.0, 34.0)
	couche_ui.add_child(_label_climat)

	_poser_camera()
	# Premiere evaluation AVANT le premier _process : la grille s'affiche
	# deja peuplee de biomes, jamais une frame entierement brune.
	appliquer_climat(_cases, _decalage_temperature, _decalage_humidite, _config)
	var changements: Array = evaluer_biomes(_cases, _catalogue, _config.nom_biome)
	print(_ligne_pose_initiale(_cases, _config.nom_biome))
	for changement in changements:
		print(ligne_changement(0.0, changement))
	_rafraichir_tout()

func _unhandled_input(event: InputEvent) -> void:
	# NE CALCULE RIEN : deplace deux nombres, c'est tout. Toute la
	# consequence est recalculee par _process au tick suivant.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_decalage_temperature += float(_config.pas_temperature)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_decalage_temperature -= float(_config.pas_temperature)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_UP:
			_decalage_humidite += float(_config.pas_humidite)
		elif event.keycode == KEY_DOWN:
			_decalage_humidite -= float(_config.pas_humidite)

func _process(delta: float) -> void:
	_temps += delta

	appliquer_climat(_cases, _decalage_temperature, _decalage_humidite, _config)
	var changements: Array = evaluer_biomes(_cases, _catalogue, _config.nom_biome)

	for changement in changements:
		print(ligne_changement(_temps, changement))

	_rafraichir_tout()

func _rafraichir_tout() -> void:
	var nom_biome: String = _config.nom_biome
	for case in _cases:
		var id: String = case.id
		_noeuds[id].color = couleur_pour_biome(case.proprietes.get(nom_biome, ""), _config)
		_labels[id].text = texte_label_case(case, _config)
	_label_compteur.text = texte_compteur(compter_par_biome(_cases, nom_biome))
	_label_climat.text = texte_climat(_decalage_temperature, _decalage_humidite)

# ---- Fonctions PURES, testables headless (voir test_banc_biomes.gd) ----

# Construit la grille grille_lignes x grille_colonnes. Chaque case porte SES
# VALEURS DE BASE (humidite_base/temperature_base) -- posees ici UNE FOIS,
# jamais mutees ensuite (voir en-tete, "LE CLIMAT NE DERIVE JAMAIS"). Les
# proprietes effectives lues par conditions.gd (nom_humidite/nom_temperature)
# ne sont PAS ecrites ici : c'est appliquer_climat qui les pose, y compris au
# tout premier passage. Rend un Array plat, ordre ligne-majeur.
static func construire_grille(config: Dictionary) -> Array:
	var lignes: int = config.grille_lignes
	var colonnes: int = config.grille_colonnes
	var cases: Array = []
	for ligne in range(lignes):
		for colonne in range(colonnes):
			cases.append({
				"id": "case_%d_%d" % [colonne, ligne],
				"position": Vector3(float(colonne), float(ligne), 0.0),
				"proprietes": {
					"humidite_base": humidite_pour_colonne(colonne, colonnes, config),
					"temperature_base": temperature_pour_ligne(ligne, lignes, config),
				},
			})
	return cases

# Interpolation lineaire : colonne 0 = humidite_min (sec, gauche), derniere
# colonne = humidite_max (sature, droite). colonnes<=1 : rend humidite_min,
# chemin degenere jamais atteint par la config reelle (6 colonnes) mais garde
# defensive contre une division par zero -- meme geste que
# banc_ecoulement.gd:altitude_pour_colonne.
static func humidite_pour_colonne(colonne: int, colonnes: int, config: Dictionary) -> float:
	var mini: float = float(config.humidite_min)
	var maxi: float = float(config.humidite_max)
	if colonnes <= 1:
		return mini
	return lerp(mini, maxi, float(colonne) / float(colonnes - 1))

# Interpolation lineaire : ligne 0 = temperature_min (froid, haut), derniere
# ligne = temperature_max (chaud, bas). lignes<=1 : meme garde defensive.
static func temperature_pour_ligne(ligne: int, lignes: int, config: Dictionary) -> float:
	var mini: float = float(config.temperature_min)
	var maxi: float = float(config.temperature_max)
	if lignes <= 1:
		return mini
	return lerp(mini, maxi, float(ligne) / float(lignes - 1))

# MUTE les cases en place : repose humidite/temperature EFFECTIVES a partir
# des valeurs de BASE et des deux decalages globaux. IDEMPOTENTE -- deux
# appels d'affilee avec les memes decalages donnent exactement le meme etat
# (jamais un "+=" cumulatif sur la case). L'humidite est BORNEE a [0,1] (un
# ratio ne peut pas sortir de la), la temperature ne l'est pas.
static func appliquer_climat(cases: Array, decalage_temperature: float, decalage_humidite: float, config: Dictionary) -> void:
	var nom_humidite: String = config.nom_humidite
	var nom_temperature: String = config.nom_temperature
	for case in cases:
		var p: Dictionary = case.proprietes
		p[nom_humidite] = clamp(float(p.get("humidite_base", 0.0)) + decalage_humidite, 0.0, 1.0)
		p[nom_temperature] = float(p.get("temperature_base", 0.0)) + decalage_temperature

# Rejoue le catalogue sur CHAQUE case via Conditions.evaluer (mecanisme du
# coeur, JAMAIS reimplemente ici) avec retirer_si_faux=true -- c'est ce
# drapeau, et lui seul, qui rend le biome REVERSIBLE.
# Rend l'Array des CHANGEMENTS de ce passage : { id, avant, apres }, ou
# "avant"/"apres" valent "" quand la case ne porte aucun biome. Une case dont
# le biome ne bouge pas n'y figure jamais -- c'est ce qui rend la trace
# console lisible (sans quoi 36 lignes par frame).
# LE CHANGEMENT EST LU AVANT/APRES SUR LA CASE, jamais deduit de la trace
# rendue par Conditions.evaluer : celle-ci dit ce qui a ete pose/retire ce
# passage, pas si la VALEUR a change (poser "foret" sur une case deja foret
# figure dans "poses" et n'est pourtant pas un changement).
static func evaluer_biomes(cases: Array, catalogue: Array, nom_biome: String) -> Array:
	var changements: Array = []
	for case in cases:
		var avant: String = String(case.proprietes.get(nom_biome, ""))
		Conditions.evaluer(case.proprietes, catalogue, true)
		var apres: String = String(case.proprietes.get(nom_biome, ""))
		if avant != apres:
			changements.append({"id": case.id, "avant": avant, "apres": apres})
	return changements

# Compte les cases par biome. Les cases SANS biome sont comptees sous la cle
# "" (chaine vide) -- jamais oubliees, jamais rangees sous un nom invente.
static func compter_par_biome(cases: Array, nom_biome: String) -> Dictionary:
	var comptes: Dictionary = {}
	for case in cases:
		var biome: String = String(case.proprietes.get(nom_biome, ""))
		comptes[biome] = int(comptes.get(biome, 0)) + 1
	return comptes

# Palette lue en DONNEE (data/banc_biomes.json:couleurs_biome) -- ce fichier
# ne nomme aucun biome en dur. Un biome absent de la palette (contenu ajoute
# au catalogue sans couleur) retombe sur la couleur "aucun biome" plutot que
# de planter : un banc d'observation ne doit jamais empecher d'observer.
static func couleur_pour_biome(biome: String, config: Dictionary) -> Color:
	var palette: Dictionary = config.get("couleurs_biome", {})
	var brut: Array = palette.get(biome, config.get("couleur_aucun_biome", [0.4, 0.3, 0.2]))
	return Color(float(brut[0]), float(brut[1]), float(brut[2]))

# Retrouve la case dont la position de GRILLE (convertie en pixels par
# taille_case) est la plus proche de "position_ecran". Rend null si "cases"
# est vide -- meme geste que banc_ecoulement.gd:case_la_plus_proche, RECOPIE
# ici (deux bancs jetables ne se referencent jamais entre eux).
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

static func texte_label_case(case: Dictionary, config: Dictionary) -> String:
	var p: Dictionary = case.proprietes
	var biome: String = String(p.get(config.nom_biome, ""))
	return "h %.2f\nt %.0f\n%s" % [
		float(p.get(config.nom_humidite, 0.0)),
		float(p.get(config.nom_temperature, 0.0)),
		biome if biome != "" else "-",
	]

# Cles triees alphabetiquement : l'ordre d'iteration d'un Dictionary ne doit
# jamais decider de ce que le joueur lit. La cle "" (aucun biome) est rendue
# en dernier, sous un libelle explicite.
static func texte_compteur(comptes: Dictionary) -> String:
	var noms: Array = []
	for cle in comptes:
		if String(cle) != "":
			noms.append(String(cle))
	noms.sort()
	var morceaux: Array = []
	for nom in noms:
		morceaux.append("%s %d" % [nom, int(comptes[nom])])
	if comptes.has(""):
		morceaux.append("aucun %d" % int(comptes[""]))
	return "cases par biome : " + (" | ".join(morceaux) if not morceaux.is_empty() else "-")

static func texte_climat(decalage_temperature: float, decalage_humidite: float) -> String:
	return "decalage global : temperature %+.0f (clic gauche/droit) humidite %+.2f (fleches haut/bas)" % [
		decalage_temperature, decalage_humidite
	]

static func ligne_changement(t: float, changement: Dictionary) -> String:
	var avant: String = String(changement.avant)
	var apres: String = String(changement.apres)
	return "t=%.1f %s : %s -> %s" % [
		t, changement.id,
		avant if avant != "" else "aucun",
		apres if apres != "" else "aucun",
	]

static func _ligne_pose_initiale(cases: Array, nom_biome: String) -> String:
	return "t=0.0 grille posee : %d cases -- %s" % [cases.size(), texte_compteur(compter_par_biome(cases, nom_biome))]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds et la camera.

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
	label.add_theme_font_size_override("font_size", 13)
	# Contour sombre : le meme label doit rester lisible sur le blanc de la
	# toundra comme sur le vert fonce de la foret.
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	label.position = centre - Vector2(taille_visible / 2.0 - 4.0, taille_visible / 2.0 - 4.0)
	add_child(label)
	_labels[id] = label

func _poser_camera() -> void:
	var lignes: int = _config.grille_lignes
	var colonnes: int = _config.grille_colonnes
	var camera := Camera2D.new()
	camera.position = Vector2(float(colonnes - 1), float(lignes - 1)) * TAILLE_CASE / 2.0
	camera.zoom = Vector2(0.9, 0.9)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
