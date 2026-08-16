extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_succession.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier "succession
# ecologique -- nu -> prairie -> taillis -> foret" : premiere demonstration
# reelle de scripts/stade.gd (stades EXCLUSIFS, un seul a la fois) attele a
# scripts/senescence.gd (l'horloge) sur un TERRAIN modelise en objets
# ordinaires -- meme patron de grille que scripts/banc_ecoulement.gd. CASES
# CONSTRUITES A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_ecoulement.gd/banc_maladie.gd -- une case n'a pas de composition).
#
# AUCUN MECANISME DU COEUR TOUCHE : stade.gd, senescence.gd et propagation.gd
# sont INCHANGES. Ce fichier ne fait que les appeler dans l'ordre et lire
# leurs effets.
#
# CHAINE, DEUX APPELS PAR CASE ET PAR TICK, JAMAIS PLUS :
#   1. Senescence.avancer(case, delta, annees_par_seconde_pour_case(...))
#      fait avancer proprietes.age (en ANNEES ; annees_par_seconde est le
#      facteur d'echelle, RECU du cablage par doctrine -- voir l'en-tete de
#      senescence.gd).
#   2. Stade.avancer(case) relit proprietes.age contre
#      proprietes.stades_config et ecrit proprietes.stade -- une String
#      unique, donc des stades EXCLUSIFS par construction (jamais deux noms
#      actifs en meme temps, contrairement au patron cumulatif de
#      seuil_etat.gd).
#
# VIEILLISSEMENT CONDITIONNEL, SANS UNE LIGNE DE MECANISME :
# annees_par_seconde_pour_case (fonction PURE ci-dessous) rend 0.0 quand la
# case ne remplit pas la condition de croissance, sinon le taux nominal du
# catalogue. senescence.gd multiplie deja delta par ce facteur : a 0.0,
# proprietes.age ne bouge plus du tout, donc stade.gd ne fait plus jamais
# rien -- l'horloge est arretee, aucun cas particulier a coder. La condition
# elle-meme est NOMMEE EN DONNEE (data/banc_succession.json,
# "propriete_croissance") et posee sur la case a la construction : la
# derniere colonne (colonne_sterile) la porte a false et reste au premier
# stade pour toujours, preuve visible a l'ecran a cote de cinq colonnes qui
# progressent normalement.
#
# LE FEU EST UN CLIC, PAS UNE PROPAGATION (choix de la consigne, dit plutot
# que masque) : scripts/propagation.gd:avancer rend bien l'Array des ids
# nouvellement enflammes et ferait un declencheur legitime, mais il n'est
# PAS cable ici -- ce banc montre la succession et sa remise a zero, pas la
# transmission du feu de case en case. declencher_feu (fonction PURE)
# ecrit DIRECTEMENT proprietes.age = 0.0 ET proprietes.stade = <premier
# stade> sur la case cliquee et ses voisines immediates (rayon_feu, via
# Portee.en_portee). LES DEUX ECRITURES SONT OBLIGATOIRES : stade.gd refuse
# tout retour en arriere (il compare des INDEX dans stades_config), donc
# remettre l'age seul laisserait proprietes.stade fige sur l'ancien stade et
# bloquerait la remontee. Ce n'est pas un contournement du mecanisme : c'est
# le patron d'ecriture directe par le cablage, deja partout dans le depot
# (banc_maladie.gd pose porteur, banc_activation_neutronique.gd pose
# force_radiation).
#
# MODELE DE POSITION (identique a banc_ecoulement.gd) : case.position est un
# FAIT SPATIAL PUR en unites de GRILLE (x=colonne, y=ligne, z=0.0 TOUJOURS).
# rayon_feu=1.5 couvre les 8 voisines Moore adjacentes (orthogonales a 1.0,
# diagonales a sqrt(2)). Le rendu (ColorRect) convertit separement l'index de
# grille en pixels via TAILLE_CASE, jamais case.position lui-meme.
#
# CE QU'ON DOIT VOIR : une grille 6x6 brune (tout le monde "nu") qui verdit
# par vagues -- vert clair (prairie) vers 0.5 s, vert moyen (taillis) vers
# 2 s, vert fonce (foret) vers 7.5 s -- sauf la derniere colonne, sterile,
# qui reste brune indefiniment. Chaque case affiche son stade et son age. Un
# compteur en haut donne le nombre de cases par stade. Un clic gauche brule
# la case sous la souris et ses 8 voisines : elles repassent brunes et
# recommencent toute la succession depuis zero, pendant que le reste de la
# grille continue de vieillir.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la grille et le rendu. _unhandled_input
#   declenche le feu au clic. _process appelle UNIQUEMENT avancer_cases (qui
#   n'appelle que des fonctions du coeur, jamais reimplementees) et lit son
#   resultat pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_succession.gd) : construire_grille/nom_stade_initial/
#   annees_par_seconde_pour_case/avancer_cases/declencher_feu/
#   compter_par_stade/couleur_pour_stade/case_la_plus_proche, plus le texte
#   d'affichage et de log.

const Senescence = preload("res://scripts/senescence.gd")
const Stade = preload("res://scripts/stade.gd")
const Portee = preload("res://scripts/portee.gd")

const TAILLE_CASE := 90.0
const MARGE_CASE := 6.0

var _config: Dictionary = {}
var _cases: Array = []
var _noeuds: Dictionary = {}
var _labels_case: Dictionary = {}
var _label_compteur: Label
var _temps: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_succession.json")

	_cases = construire_grille(_config)
	for case in _cases:
		_creer_rendu_case(case)

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label_compteur = Label.new()
	_label_compteur.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label_compteur)

	_poser_camera()
	_rafraichir_tout()
	print(_ligne_pose_initiale(_cases, _config))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var case: Variant = case_la_plus_proche(_cases, get_global_mouse_position(), TAILLE_CASE)
	if case == null:
		return
	var brulees: Array = declencher_feu(_cases, case, _config)
	print(_ligne_trace_feu(_temps, case.id, brulees))
	_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta
	for changement in avancer_cases(_cases, delta, _config):
		print(_ligne_trace_changement(_temps, changement))
	_rafraichir_tout()

func _rafraichir_tout() -> void:
	_label_compteur.text = texte_compteur(compter_par_stade(_cases, _config))
	for case in _cases:
		var id: String = case.id
		_noeuds[id].color = couleur_pour_stade(case.proprietes.get("stade", ""), _config)
		_labels_case[id].text = texte_case(case)

# ---- Fonctions PURES, testables headless (voir test_banc_succession.gd) ----

# Construit la grille grille_lignes x grille_colonnes, index colonne d'abord
# (position.x=colonne, position.y=ligne, position.z=0.0 TOUJOURS -- voir
# en-tete, "MODELE DE POSITION"). Rend un Array plat, ordre ligne-majeur
# (index = ligne*grille_colonnes + colonne).
#
# Chaque case porte les TROIS proprietes que stade.gd/senescence.gd exigent
# comme STRUCTURELLES (age, stades_config, plus stade que stade.gd lit sans
# jamais l'exiger) : leur absence ferait push_error et aucune ecriture, voir
# les en-tetes des deux mecanismes. stades_config est DUPLIQUEE EN
# PROFONDEUR par case -- jamais la meme instance d'Array partagee par 36
# cases (aucun mecanisme ne l'ecrit aujourd'hui, mais l'aliasing sur une
# valeur imbriquee est deja un bug reel du depot, voir l'en-tete de
# propagation.gd).
static func construire_grille(config: Dictionary) -> Array:
	var lignes: int = config.grille_lignes
	var colonnes: int = config.grille_colonnes
	var initial := nom_stade_initial(config)
	var propriete_croissance: String = config.get("propriete_croissance", "")
	var colonne_sterile: int = int(config.get("colonne_sterile", -1))
	var cases: Array = []
	for ligne in range(lignes):
		for colonne in range(colonnes):
			var proprietes: Dictionary = {
				"age": 0.0,
				"stade": initial,
				"stades_config": config.stades_config.duplicate(true),
			}
			if propriete_croissance != "":
				proprietes[propriete_croissance] = colonne != colonne_sterile
			cases.append({
				"id": "case_%d_%d" % [colonne, ligne],
				"position": Vector3(float(colonne), float(ligne), 0.0),
				"proprietes": proprietes,
			})
	return cases

# Premier stade declare par le catalogue -- l'etat de depart de toute case,
# ET l'etat vers lequel un feu la ramene. JAMAIS un nom en dur ici : "nu"
# n'existe que dans data/banc_succession.json. Catalogue vide : rend "",
# chemin degenere (aucune case ne progresserait de toute facon, stade.gd
# sortant immediatement sur un stades_config vide).
static func nom_stade_initial(config: Dictionary) -> String:
	var stades: Array = config.get("stades_config", [])
	if stades.is_empty():
		return ""
	return stades[0].get("nom", "")

# VIEILLISSEMENT CONDITIONNEL (voir en-tete) : rend 0.0 -- horloge arretee,
# senescence.gd ne bougera plus proprietes.age d'un iota -- quand la case
# porte la propriete nommee par config.propriete_croissance a une valeur
# fausse, sinon le taux nominal du catalogue. Case qui NE PORTE PAS cette
# propriete : taux nominal (defaut true, absence legitime -- une case sans
# condition declaree pousse normalement, jamais une alarme).
# propriete_croissance vide : condition entierement desactivee, toute la
# grille au taux nominal.
static func annees_par_seconde_pour_case(case: Dictionary, config: Dictionary) -> float:
	var propriete: String = config.get("propriete_croissance", "")
	if propriete != "" and not case.proprietes.get(propriete, true):
		return 0.0
	return float(config.get("annees_par_seconde", 0.0))

# LE COEUR DU BANC. Pour chaque case, dans cet ordre et une seule fois par
# tick : Senescence.avancer (horloge) puis Stade.avancer (evaluation). Rend
# l'Array des changements de stade survenus CE tick ({ id, avant, apres,
# age }) -- lu par la trace console, jamais recalcule par l'appelant. Une
# case dont le stade n'a pas bouge n'y figure pas.
static func avancer_cases(cases: Array, delta: float, config: Dictionary) -> Array:
	var changements: Array = []
	for case in cases:
		var avant: String = case.proprietes.get("stade", "")
		Senescence.avancer(case, delta, annees_par_seconde_pour_case(case, config))
		Stade.avancer(case)
		var apres: String = case.proprietes.get("stade", "")
		if apres != avant:
			changements.append({
				"id": case.id,
				"avant": avant,
				"apres": apres,
				"age": float(case.proprietes.get("age", 0.0)),
			})
	return changements

# LA PERTURBATION (voir en-tete, "LE FEU EST UN CLIC") : remet age = 0.0 ET
# stade = premier stade sur la case cible et sur toutes celles a rayon_feu
# d'elle (Portee.en_portee, en unites de GRILLE -- 1.5 couvre les 8
# voisines immediates). LES DEUX ECRITURES SONT OBLIGATOIRES : sans le
# stade, stade.gd retrouverait l'ancien index et refuserait toute remontee.
# Rend l'Array des ids brules (la cible comprise), pour la trace. Ne touche
# a AUCUNE autre propriete -- ni croissance_possible (une colonne sterile
# brulee reste sterile), ni stades_config.
static func declencher_feu(cases: Array, case_cible: Dictionary, config: Dictionary) -> Array:
	var rayon: float = float(config.get("rayon_feu", 0.0))
	var initial := nom_stade_initial(config)
	var brulees: Array = []
	for case in cases:
		if not Portee.en_portee(case.position, case_cible.position, rayon):
			continue
		case.proprietes["age"] = 0.0
		case.proprietes["stade"] = initial
		brulees.append(case.id)
	return brulees

# Compte les cases par stade, dans l'ORDRE du catalogue (chaque nom declare
# apparait, meme a zero -- un stade qui disparait de l'affichage serait plus
# dur a lire qu'un stade a 0). Un stade inattendu (hors catalogue) serait
# compte quand meme plutot qu'ignore silencieusement.
static func compter_par_stade(cases: Array, config: Dictionary) -> Dictionary:
	var comptes: Dictionary = {}
	for entree in config.get("stades_config", []):
		comptes[entree.get("nom", "")] = 0
	for case in cases:
		var nom: String = case.proprietes.get("stade", "")
		comptes[nom] = comptes.get(nom, 0) + 1
	return comptes

# Table de RENDU seule (data/banc_succession.json, "couleurs_stade") : brun
# pour le sol nu, puis trois verts de plus en plus sombres. AUCUN nom de
# stade en dur ici -- contrairement a banc_ecoulement.gd:couleur_pour_niveau
# qui nomme "terre" dans son code, ce banc garde meme sa table de couleurs en
# donnee. Stade inconnu de la table : gris neutre, jamais un plantage.
static func couleur_pour_stade(nom: String, config: Dictionary) -> Color:
	var table: Dictionary = config.get("couleurs_stade", {})
	if not table.has(nom):
		return Color(0.5, 0.5, 0.5)
	var composantes: Array = table[nom]
	return Color(float(composantes[0]), float(composantes[1]), float(composantes[2]))

# Retrouve la case dont la position de GRILLE (convertie en pixels par
# taille_case) est la plus proche de "position_ecran" -- utilisee par le
# clic. Rend null si "cases" est vide (chemin mort, jamais atteint en jeu
# reel). MEME GESTE que banc_ecoulement.gd:case_la_plus_proche, RECOPIE ici :
# deux bancs jetables ne se referencent jamais entre eux (meme discipline que
# banc_mana_conduction.gd recopiant banc_conduction.gd).
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

static func texte_case(case: Dictionary) -> String:
	return "%s\n%.1f a" % [case.proprietes.get("stade", "?"), float(case.proprietes.get("age", 0.0))]

static func texte_compteur(comptes: Dictionary) -> String:
	var morceaux: Array = []
	for nom in comptes:
		morceaux.append("%s=%d" % [nom, comptes[nom]])
	return "cases par stade : " + " | ".join(morceaux)

static func _ligne_pose_initiale(cases: Array, config: Dictionary) -> String:
	return "t=0.0 grille posee : %d cases, %s" % [cases.size(), texte_compteur(compter_par_stade(cases, config))]

static func _ligne_trace_changement(t: float, changement: Dictionary) -> String:
	return "t=%.1f stade : %s %s -> %s (age=%.1f a)" % [t, changement.id, changement.avant, changement.apres, changement.age]

static func _ligne_trace_feu(t: float, id_cible: String, brulees: Array) -> String:
	return "t=%.1f FEU sur %s : %d cases remises a zero (%s)" % [t, id_cible, brulees.size(), ", ".join(brulees)]

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

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 12)
	label.size = Vector2(taille_visible, taille_visible)
	label.position = noeud.position
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
	_labels_case[id] = label

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
