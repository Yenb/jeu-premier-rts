extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_erosion.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier "erosion par vent et
# eau -- le sol part et se depose", audit prealable
# audit_terrain_et_monde_prealable.md (ligne 5, PARTIELLEMENT COUVERT).
# Compose QUATRE mecanismes deja fermes, TOUS INCHANGES : ecoulement.gd
# (debit d'eau entre cases), consommer.gd (le transfert conserve lui-meme),
# vent.gd (direction et force du vent), etat_effectif.gd (couvert vegetal
# modulable par un etat). AUCUN MECANISME DU COEUR TOUCHE, aucun .gd neuf
# du coeur : tout ce qui suit est du CABLAGE.
#
# CE QU'ON DOIT VOIR : une grille 8x8 en pente (montagne colonne 0 a gauche,
# vallee a droite), chaque case portant une reserve de SOL identique au
# depart. De l'eau posee sur la colonne 0 coule vers le bas de la pente et
# EMPORTE du sol au passage ; un vent constant de gauche a droite emporte du
# sol NU. La moitie GAUCHE porte un couvert vegetal (couvert_gauche) et
# resiste au vent ; la moitie DROITE est nue et s'erode vite. Le sol emporte
# se DEPOSE en aval (colonne de droite) : le compteur de sol total ne bouge
# JAMAIS -- c'est la preuve visible de la conservation. depense.gd
# N'INTERVIENT PAS dans ce banc : le sol ne disparait pas, il se deplace.
#
# DEUX EROSIONS, DEUX CABLAGES DISTINCTS, MEME GESTE FINAL :
#
# 1. PAR L'EAU -- ENTRAINEMENT, jamais une gravite propre au sol.
#    Ecoulement.avancer rend l'Array des transferts d'eau du tick
#    ({ source_id, receveur_id, quantite }) ; eroder_par_eau boucle
#    DESSUS et transfere, sur la MEME paire de cases et dans le MEME sens,
#    quantite * coefficient_erosion_eau de sol. Un second appel a
#    Ecoulement.avancer avec nom_reserve="sol" aurait ete possible mais
#    FAUX : _hauteur() y vaut altitude + reserve, le sol coulerait donc de
#    sa PROPRE gravite, independamment de l'eau (de la boue, pas de
#    l'erosion -- voir audit_terrain_et_monde_prealable.md, ligne 5).
#
# 2. PAR LE VENT -- APPARIEMENT DE DEUX VOISINS PAR UN VECTEUR.
#    Aucun mecanisme du depot ne fait ca (ecoulement.gd apparie par
#    comparaison d'altitude, jamais par une direction externe) : la boucle
#    nue sur les paires est RECOPIEE ici depuis le patron d'ecoulement.gd,
#    localement, comme banc_mana_conduction.gd recopie banc_conduction.gd --
#    deux bancs jetables ne se referencent jamais entre eux. SI CE GESTE
#    DOIT DURER, c'est un mecanisme du coeur neuf (NEUVIEME nature :
#    transfert conserve oriente par un champ vectoriel) -- a trancher par
#    Yael, pas ici.
#
#    GATE "CE VOISIN EST SOUS LE VENT" = Vent.facteur_directionnel > 1.0
#    (SEUIL_SOUS_VENT), JAMAIS "> 0.0" : facteur_directionnel ne rend
#    JAMAIS une valeur negative ni nulle (facteur_min_contre_vent vaut 0.4
#    dans la donnee), un test "> 0.0" serait donc TOUJOURS vrai et le sol
#    partirait aussi CONTRE le vent -- une diffusion isotrope, pas une
#    erosion orientee (decision Yael, question posee avant d'ecrire).
#    "> 1.0" est STRICTEMENT equivalent a "produit scalaire > 0 ET vent non
#    nul" par construction de vent.gd (interpolation en DEUX morceaux
#    autour d'un point milieu perpendiculaire toujours exactement egal a
#    1.0, et intensite nulle a vent nul qui ramene tout a 1.0) -- ce n'est
#    pas un cas particulier code a part, c'est une propriete de la formule.
#    Consequence exacte sur la grille : un vent +x fait partir le sol vers
#    les TROIS voisins de droite (dot 1.0 et 0.707), jamais vers les deux
#    perpendiculaires (dot 0.0, facteur exactement 1.0) ni vers les trois
#    de gauche.
#
# DEMANDE NUE, DANS LES DEUX CAS, MEME CONVENTION QUE ecoulement.gd : la
# trace porte le RETOUR du mecanisme, jamais ce qu'on lui a demande.
#
# SEQUENCE : UNE SEULE PASSE, mutation immediate, comme ecoulement.gd -- la
# reserve de sol d'une case decroit a chaque transfert, ce qui borne
# naturellement la somme qu'elle distribue a ses voisins dans le meme tick.
# MEME EFFET ASSUME : a grand delta, du sol peut "voyager" sur plus d'un
# saut en un seul tick (ordre d'iteration) -- accepte par calibration, voir
# ecoulement.gd, meme rationale.
#
# COUVERT VEGETAL : lu par EtatEffectif.valeur (jamais proprietes[...] en
# direct) -- aujourd'hui aucun etat ne le module, la valeur de base est
# rendue telle quelle ; un etat futur ("brule", "defriche") le modulerait
# sans une ligne de code ici. Borne a [0,1] avant usage : exposition =
# 1.0 - couvert, couvert=1.0 -> AUCUNE erosion par vent (gate exacte, pas
# une asymptote).
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la grille et le rendu. _unhandled_input
#   ajoute de l'eau au clic. _process appelle Ecoulement.avancer puis les
#   deux cablages d'erosion (qui appellent Consommer/Vent/EtatEffectif,
#   jamais reimplementes) et lit leurs resultats pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_erosion.gd) : construire_grille/altitude_pour_colonne/
#   couvert_pour_colonne/sources_depuis_donnee/eroder_par_eau/
#   eroder_par_vent/somme_quantites/couleur_pour_sol/
#   couleur_pour_eau/case_la_plus_proche/ajouter_eau, plus les textes.

const Ecoulement = preload("res://scripts/ecoulement.gd")
const Consommer = preload("res://scripts/consommer.gd")
const Vent = preload("res://scripts/vent.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Somme = preload("res://scripts/somme.gd")

# Un voisin est "sous le vent" quand facteur_directionnel le porte STRICTEMENT
# au-dessus du point milieu perpendiculaire (toujours exactement 1.0) -- voir
# en-tete, GATE.
const SEUIL_SOUS_VENT := 1.0

const TAILLE_CASE := 82.0
const MARGE_CASE := 5.0
const INTERVALLE_PRINT := 1.0

var _config: Dictionary = {}
var _etats: Dictionary = {}
var _catalogue_vent: Dictionary = {}
var _sources_vent: Array = []
var _cases: Array = []
var _noeuds_sol: Dictionary = {}
var _noeuds_eau: Dictionary = {}
var _labels_case: Dictionary = {}
var _label_compteur: Label
var _label_vent: Label
var _fleche_vent: Node2D
var _temps: float = 0.0
var _prochain_print: float = 0.0
var _sol_initial_total: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_erosion.json")
	_etats = _charger_json("res://data/etats.json")
	_catalogue_vent = _config.vent
	_sources_vent = sources_depuis_donnee(_config)

	_cases = construire_grille(_config)
	_sol_initial_total = Somme.reserves(_cases, _config.nom_reserve_sol)
	for case in _cases:
		_creer_rendu_case(case)

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label_compteur = Label.new()
	_label_compteur.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label_compteur)
	_label_vent = Label.new()
	_label_vent.position = Vector2(10.0, 34.0)
	couche_ui.add_child(_label_vent)
	_fleche_vent = _creer_fleche_vent()
	couche_ui.add_child(_fleche_vent)

	_poser_camera()
	_rafraichir_tout()
	print(_ligne_pose_initiale(_cases, _config.nom_reserve_sol, _config.nom_reserve_eau))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var case: Variant = case_la_plus_proche(_cases, get_global_mouse_position(), TAILLE_CASE)
	if case == null:
		return
	ajouter_eau(case, _config.nom_reserve_eau, _config.ajout_eau_clic)
	print("t=%.1f clic : +%.2f d'eau sur %s" % [_temps, _config.ajout_eau_clic, case.id])
	_rafraichir_tout()

func _process(delta: float) -> void:
	_temps += delta

	var transferts_eau: Array = Ecoulement.avancer(_cases, _config.rayon_voisinage, _config.nom_reserve_eau, _config.nom_altitude, _config.taux_ecoulement, delta)
	var erosion_eau: Array = eroder_par_eau(_cases, transferts_eau, _config.nom_reserve_sol, _config.coefficient_erosion_eau)
	var erosion_vent: Array = eroder_par_vent(_cases, _config, _catalogue_vent, _sources_vent, _etats, _temps, delta)

	_rafraichir_tout()

	if _temps >= _prochain_print:
		_prochain_print = _temps + INTERVALLE_PRINT
		print(_ligne_trace(
			_temps,
			transferts_eau.size(),
			somme_quantites(erosion_eau),
			somme_quantites(erosion_vent),
			Somme.reserves(_cases, _config.nom_reserve_sol),
			_sol_initial_total,
			Somme.reserves(_cases, _config.nom_reserve_eau),
		))

func _rafraichir_tout() -> void:
	var sol_total: float = Somme.reserves(_cases, _config.nom_reserve_sol)
	var eau_totale: float = Somme.reserves(_cases, _config.nom_reserve_eau)
	_label_compteur.text = _texte_compteur(sol_total, _sol_initial_total, eau_totale)

	var capacite: float = float(_config.sol_capacite)
	var reference_eau: float = float(_config.eau_initiale)
	for case in _cases:
		var id: String = case.id
		var sol: float = _reserve(case, _config.nom_reserve_sol)
		var eau: float = _reserve(case, _config.nom_reserve_eau)
		var couvert: float = EtatEffectif.valeur(case, _config.nom_couvert, _etats)
		_noeuds_sol[id].color = couleur_pour_sol(sol, capacite)
		_noeuds_eau[id].color = couleur_pour_eau(eau, reference_eau)
		_labels_case[id].text = _texte_case(sol, couvert, eau)

	var centre := Vector3(float(_config.grille_colonnes - 1) / 2.0, float(_config.grille_lignes - 1) / 2.0, 0.0)
	var vecteur_vent: Vector3 = Vent.vecteur(centre, _temps, _catalogue_vent, _sources_vent)
	_label_vent.text = _texte_vent(vecteur_vent)
	if vecteur_vent.length() > 0.0:
		_fleche_vent.rotation = Vector2(vecteur_vent.x, vecteur_vent.y).angle()

# ---- Fonctions PURES, testables headless (voir test_banc_erosion.gd) ----

# Construit la grille grille_lignes x grille_colonnes, index colonne d'abord
# (position.x=colonne, position.y=ligne, position.z=0.0 TOUJOURS -- meme
# modele de position que banc_ecoulement.gd : l'altitude vit dans
# proprietes.<nom_altitude>, jamais dans position.z). Rend un Array plat,
# ordre ligne-majeur (index = ligne*grille_colonnes + colonne).
# Chaque case porte DEUX reserves : le SOL (identique partout au depart,
# avec sa capacite de reference d'affichage) et l'EAU (eau_initiale sur la
# colonne 0 seule, 0.0 ailleurs).
static func construire_grille(config: Dictionary) -> Array:
	var lignes: int = config.grille_lignes
	var colonnes: int = config.grille_colonnes
	var cases: Array = []
	for ligne in range(lignes):
		for colonne in range(colonnes):
			var eau: float = float(config.eau_initiale) if colonne == 0 else 0.0
			cases.append({
				"id": "case_%d_%d" % [colonne, ligne],
				"position": Vector3(float(colonne), float(ligne), 0.0),
				"proprietes": {
					config.nom_altitude: altitude_pour_colonne(colonne, colonnes, config.altitude_max, config.altitude_min),
					config.nom_couvert: couvert_pour_colonne(colonne, colonnes, config),
					"reserves": {
						config.nom_reserve_sol: {
							"reserve": float(config.sol_initial),
							"capacite": float(config.sol_capacite),
						},
						config.nom_reserve_eau: {
							"reserve": eau,
						},
					},
				},
			})
	return cases

# Interpolation lineaire, colonne 0 = altitude_max (montagne, gauche),
# derniere colonne = altitude_min (vallee, droite). RECOPIEE depuis
# banc_ecoulement.gd (deux bancs jetables ne se referencent jamais entre
# eux). colonnes<=1 : rend altitude_max, garde defensive contre une division
# par zero, jamais atteinte par la config reelle.
static func altitude_pour_colonne(colonne: int, colonnes: int, altitude_max: float, altitude_min: float) -> float:
	if colonnes <= 1:
		return altitude_max
	return lerp(altitude_max, altitude_min, float(colonne) / float(colonnes - 1))

# Moitie gauche des colonnes (colonne < colonnes/2) : couvert_gauche (sol
# protege) ; moitie droite : couvert_droite (sol nu) -- voir
# data/banc_erosion.json.
static func couvert_pour_colonne(colonne: int, colonnes: int, config: Dictionary) -> float:
	return float(config.couvert_gauche) if colonne < colonnes / 2 else float(config.couvert_droite)

# Traduit les sources de vent de la DONNEE (JSON : position/vecteur en
# Dictionary {x,y,z}) vers la forme attendue par vent.gd (Vector3). Une
# source incomplete est laissee telle quelle : vent.gd la signale lui-meme
# (push_error nommant son index) et l'ignore seule -- jamais deux endroits
# qui valident la meme chose.
static func sources_depuis_donnee(config: Dictionary) -> Array:
	var sources: Array = []
	for brute in config.get("sources_vent", []):
		if not (brute.has("position") and brute.has("rayon") and brute.has("vecteur")):
			sources.append(brute)
			continue
		sources.append({
			"position": _vecteur_depuis_dict(brute.position),
			"rayon": float(brute.rayon),
			"vecteur": _vecteur_depuis_dict(brute.vecteur),
		})
	return sources

static func _vecteur_depuis_dict(d: Dictionary) -> Vector3:
	return Vector3(d.get("x", 0.0), d.get("y", 0.0), d.get("z", 0.0))

# EROSION PAR EAU -- entrainement. Boucle sur les transferts d'EAU rendus par
# Ecoulement.avancer et rejoue le MEME sens sur la reserve de SOL, a
# coefficient_erosion_eau pres. PRE-BORNE a la reserve de sol COURANTE de la
# source (voir en-tete, PRE-BORNAGE) : la meme case peut apparaitre plusieurs
# fois dans la liste (elle distribue vers plusieurs voisins), sa reserve est
# donc relue a chaque fois. Rend l'Array des transferts de sol effectues
# ({ source_id, receveur_id, quantite }), pour trace/affichage.
static func eroder_par_eau(cases: Array, transferts_eau: Array, nom_reserve_sol: String, coefficient: float) -> Array:
	var faits: Array = []
	if coefficient <= 0.0 or transferts_eau.is_empty():
		return faits
	var index: Dictionary = index_par_id(cases)
	for transfert in transferts_eau:
		if not (index.has(transfert.source_id) and index.has(transfert.receveur_id)):
			continue
		var source: Dictionary = index[transfert.source_id]
		var receveur: Dictionary = index[transfert.receveur_id]
		# Demande NUE -- la trace porte le RETOUR.
		var demande: float = float(transfert.quantite) * coefficient
		if demande <= 0.0:
			continue
		var resultat: Dictionary = Consommer.transferer(source, receveur, nom_reserve_sol, nom_reserve_sol, demande, 1.0)
		var quantite: float = float(resultat.quantite)
		if quantite <= 0.0:
			continue
		faits.append({"source_id": source.id, "receveur_id": receveur.id, "quantite": quantite})
	return faits

# EROSION PAR VENT -- appariement de deux voisins par un vecteur (voir
# en-tete, point 2). Pour CHAQUE case : un seul appel a Vent.vecteur (le vent
# ne depend que de la position et du temps, jamais du voisin interroge), puis
# une boucle nue sur les autres cases a distance <= rayon_voisinage. Un
# voisin recoit du sol SEULEMENT si Vent.facteur_directionnel le porte
# strictement au-dessus de SEUIL_SOUS_VENT.
# quantite = force_vent * taux_erosion_vent * (1 - couvert_vegetal EFFECTIF)
# * delta, PRE-BORNEE a la reserve de sol COURANTE de la case (qui decroit a
# chaque voisin servi -- une case presque vide ne distribue pas trois fois
# ce qu'elle possede). Rend l'Array des transferts effectues.
static func eroder_par_vent(cases: Array, config: Dictionary, catalogue_vent: Dictionary, sources_vent: Array, etats: Dictionary, temps: float, delta: float) -> Array:
	var faits: Array = []
	var taux: float = float(config.taux_erosion_vent)
	if taux <= 0.0 or delta <= 0.0:
		return faits
	var nom_sol: String = config.nom_reserve_sol
	var nom_couvert: String = config.nom_couvert
	var rayon: float = float(config.rayon_voisinage)
	for i in range(cases.size()):
		var case: Dictionary = cases[i]
		if _reserve(case, nom_sol) <= 0.0:
			continue
		var vecteur_vent: Vector3 = Vent.vecteur(case.position, temps, catalogue_vent, sources_vent)
		var force: float = vecteur_vent.length()
		if force <= 0.0:
			continue
		var couvert: float = clamp(EtatEffectif.valeur(case, nom_couvert, etats), 0.0, 1.0)
		var exposition: float = 1.0 - couvert
		if exposition <= 0.0:
			continue
		for j in range(cases.size()):
			if i == j:
				continue
			var voisin: Dictionary = cases[j]
			var direction: Vector3 = voisin.position - case.position
			if direction.length() > rayon:
				continue
			if Vent.facteur_directionnel(vecteur_vent, direction, catalogue_vent) <= SEUIL_SOUS_VENT:
				continue
			# Court-circuit, pas un bornage : evite de balayer pour rien.
			if _reserve(case, nom_sol) <= 0.0:
				break
			var demande: float = force * taux * exposition * delta
			if demande <= 0.0:
				continue
			var resultat: Dictionary = Consommer.transferer(case, voisin, nom_sol, nom_sol, demande, 1.0)
			var quantite: float = float(resultat.quantite)
			if quantite <= 0.0:
				continue
			faits.append({"source_id": case.id, "receveur_id": voisin.id, "quantite": quantite})
	return faits

static func index_par_id(cases: Array) -> Dictionary:
	var index: Dictionary = {}
	for case in cases:
		index[case.id] = case
	return index

static func somme_quantites(transferts: Array) -> float:
	var total := 0.0
	for transfert in transferts:
		total += float(transfert.quantite)
	return total

static func _reserve(case: Dictionary, nom_reserve: String) -> float:
	return float(case.proprietes.get("reserves", {}).get(nom_reserve, {}).get("reserve", 0.0))

# Couleur d'EPAISSEUR DE SOL, en deux segments : de la roche nue (gris) au
# brun clair sur la premiere tranche (ratio < RATIO_SOL_MINCE), puis du brun
# clair au brun fonce jusqu'a la capacite. Un depot au-dela de la capacite
# rend exactement la meme couleur que la capacite (borne, jamais divergente).
# capacite<=0.0 : rend systematiquement la roche nue, jamais une division
# par zero.
const RATIO_SOL_MINCE := 0.15

static func couleur_pour_sol(reserve_sol: float, capacite: float) -> Color:
	var roche := Color(0.48, 0.47, 0.45)
	var brun_clair := Color(0.66, 0.52, 0.33)
	var brun_fonce := Color(0.28, 0.18, 0.09)
	if capacite <= 0.0:
		return roche
	var ratio: float = clamp(reserve_sol / capacite, 0.0, 1.0)
	if ratio <= RATIO_SOL_MINCE:
		return roche.lerp(brun_clair, ratio / RATIO_SOL_MINCE)
	return brun_clair.lerp(brun_fonce, (ratio - RATIO_SOL_MINCE) / (1.0 - RATIO_SOL_MINCE))

# Couleur de la SUPERPOSITION d'eau : un bleu dont seule l'OPACITE varie avec
# le niveau (la couleur du sol reste lisible dessous). reference<=0.0 : rend
# un bleu totalement transparent, jamais une division par zero.
static func couleur_pour_eau(niveau: float, reference: float) -> Color:
	var ratio: float = clamp(niveau / reference, 0.0, 1.0) if reference > 0.0 else 0.0
	return Color(0.15, 0.35, 0.85, ratio * 0.75)

# Retrouve la case dont la position de GRILLE (convertie en pixels par
# taille_case) est la plus proche de "position_ecran". Rend null si "cases"
# est vide (chemin mort, jamais atteint en jeu reel).
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

# Mute "case" en place : credite "quantite" sur le canal nom_reserve (cree le
# canal minimal s'il n'existe pas encore -- meme geste que
# consommer.gd:_crediter, RECOPIE ici, jamais un appel croise).
static func ajouter_eau(case: Dictionary, nom_reserve: String, quantite: float) -> void:
	var reserves: Dictionary = case.proprietes.get("reserves", {})
	if not reserves.has(nom_reserve):
		reserves[nom_reserve] = {"reserve": 0.0}
	var canal: Dictionary = reserves[nom_reserve]
	canal["reserve"] = canal.get("reserve", 0.0) + quantite
	case.proprietes["reserves"] = reserves

static func _texte_case(sol: float, couvert: float, eau: float) -> String:
	return "sol %.1f\ncv %.2f\neau %.1f" % [sol, couvert, eau]

static func _texte_compteur(sol_total: float, sol_initial: float, eau_totale: float) -> String:
	return "sol total : %.2f (depart %.2f, ecart %+.4f)   eau totale : %.2f" % [sol_total, sol_initial, sol_total - sol_initial, eau_totale]

static func _texte_vent(vecteur_vent: Vector3) -> String:
	return "vent : force=%.2f direction=(%.2f, %.2f)" % [vecteur_vent.length(), vecteur_vent.x, vecteur_vent.y]

static func _ligne_pose_initiale(cases: Array, nom_reserve_sol: String, nom_reserve_eau: String) -> String:
	return "t=0.0 grille posee : %d cases, sol total=%.2f, eau totale=%.2f" % [
		cases.size(), Somme.reserves(cases, nom_reserve_sol), Somme.reserves(cases, nom_reserve_eau)
	]

static func _ligne_trace(t: float, nb_transferts_eau: int, sol_par_eau: float, sol_par_vent: float, sol_total: float, sol_initial: float, eau_totale: float) -> String:
	return "t=%.1f transferts_eau=%d sol_emporte_par_eau=%.4f sol_emporte_par_vent=%.4f sol_total=%.2f (ecart %+.4f) eau_totale=%.2f" % [
		t, nb_transferts_eau, sol_par_eau, sol_par_vent, sol_total, sol_total - sol_initial, eau_totale
	]

# ---- Rendu (impur, Node) -- aucune decision, seulement la construction des
# noeuds, la fleche de vent et la camera.

func _creer_rendu_case(case: Dictionary) -> void:
	var id: String = case.id
	var pos: Vector3 = case.position
	var centre := Vector2(pos.x, pos.y) * TAILLE_CASE
	var taille_visible := TAILLE_CASE - MARGE_CASE

	var sol := ColorRect.new()
	sol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sol.size = Vector2(taille_visible, taille_visible)
	sol.position = centre - sol.size / 2.0
	add_child(sol)
	_noeuds_sol[id] = sol

	var eau := ColorRect.new()
	eau.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eau.size = sol.size
	eau.position = sol.position
	add_child(eau)
	_noeuds_eau[id] = eau

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 11)
	label.position = centre - Vector2(taille_visible / 2.0 - 3.0, taille_visible / 2.0 - 2.0)
	add_child(label)
	_labels_case[id] = label

# Fleche pointant vers +x au repos ; _rafraichir_tout la fait tourner selon
# l'angle du vent courant.
func _creer_fleche_vent() -> Node2D:
	var pivot := Node2D.new()
	pivot.position = Vector2(320.0, 42.0)
	var corps := Polygon2D.new()
	corps.polygon = PackedVector2Array([
		Vector2(-60.0, -4.0), Vector2(24.0, -4.0), Vector2(24.0, -14.0),
		Vector2(60.0, 0.0), Vector2(24.0, 14.0), Vector2(24.0, 4.0), Vector2(-60.0, 4.0),
	])
	corps.color = Color(0.85, 0.85, 0.35)
	pivot.add_child(corps)
	return pivot

func _poser_camera() -> void:
	var centre := Vector2(float(int(_config.grille_colonnes) - 1), float(int(_config.grille_lignes) - 1)) * TAILLE_CASE / 2.0
	var camera := Camera2D.new()
	camera.position = centre
	camera.zoom = Vector2(0.75, 0.75)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
