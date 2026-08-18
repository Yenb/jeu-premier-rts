extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_cratere.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Chantier "cratere + erosion --
# trace d'impact qui s'efface", audit prealable
# audit_terrain_et_monde_prealable.md §3 ("CABLABLE avec l'existant, aucun
# .gd neuf"). Compose Frappe.frapper / Depense.avancer / Ecoulement.avancer
# -- AUCUN MECANISME DU COEUR TOUCHE.
#
# CASES CONSTRUITES A LA MAIN (pas Objet.fabriquer, meme statut que
# banc_ecoulement.gd/banc_maladie.gd -- une case n'a pas de composition).
# position reste un FAIT SPATIAL PUR en unites de GRILLE (x=colonne,
# y=ligne, z=0.0 TOUJOURS) -- jamais l'altitude, meme decision que
# banc_ecoulement.gd (voir scripts/ecoulement.gd, "MODELE DE POSITION").
#
# TROIS PROPRIETES DE CASE, TROIS CONTRATS DISTINCTS -- c'est le coeur de
# ce banc :
# - proprietes.<nom_altitude_base> ("altitude") : le sol de reference.
#   PLAT ici, et JAMAIS REECRITE par personne. Un cratere ne l'ecrase pas.
# - proprietes.creusement (float, defaut 0.0) : la trace d'impact, ECRITE
#   par ce cablage a l'impact, REMISE A 0.0 par depense.gd au bout de la
#   reserve trace_age (data/seuils_combustible.json:effacement_trace).
# - proprietes.<nom_altitude_effective> ("altitude_effective") : DERIVEE
#   chaque tick, altitude - creusement. C'est ELLE SEULE qui est passee a
#   Ecoulement.avancer comme nom_altitude. ecoulement.gd ne connait pas
#   "creusement" et n'a pas a le connaitre : il lit un nom de propriete
#   d'altitude que l'appelant lui donne (voir son en-tete). Voie (b) de
#   l'audit prealable §3 -- l'altitude de base n'etant jamais ecrasee, elle
#   n'est jamais a restaurer.
#
# L'IMPACT (impacter, fonction PURE) : Frappe.frapper decremente
# reserves.<nom_reserve_integrite> de degats_impact -- frappe.gd ne fait que
# ca, il ne creuse rien (verifie ligne a ligne, audit §3 : "frappe.gd ne
# peut PAS creuser, et c'est sans importance"). C'est CE CABLAGE qui traduit
# le franchissement (reserve retombee a seuil_creusement) en ecriture de
# creusement = profondeur_impact * (degats_reels / degats_reference).
# Le meme geste REARME l'integrite a integrite_sol_max : l'integrite mesure
# la resistance a UN impact, jamais une usure cumulee -- sans ce rearmement
# une case ne serait creusable qu'une seule fois de toute la vie du banc, et
# le cycle creuse -> s'efface -> se recreuse ne serait pas observable
# (DECISION DE CABLAGE ASSUMEE, absente de la consigne).
#
# L'EFFACEMENT, AUCUN CODE NEUF : le meme impact recharge
# reserves.<nom_reserve_trace> a duree_effacement et VIDE ses
# "seuils_franchis" (obligatoire -- depense.gd n'applique jamais deux fois
# le meme seuil, un cratere suivant ne s'effacerait plus). depense.gd
# consomme ensuite cette reserve a cout_base_trace par seconde puis, au
# zero, applique lui-meme "effacement_trace" qui repose creusement a 0.0.
# CE CABLAGE NE REMET DONC JAMAIS creusement A ZERO LUI-MEME : il ne fait
# que LIRE les ids rendus par Depense.avancer pour la trace console
# (effacements_de ci-dessous, croisement avec les cases creusees releves
# AVANT l'appel -- une fois creusement repose a 0.0 par depense.gd, plus
# rien ne dit qu'il etait positif).
#
# AUCUNE ABSORPTION NI EVAPORATION (contrairement a banc_ecoulement.gd) :
# le canal d'eau porte cout_base=0.0 et surcout_action=0.0, l'eau totale du
# systeme reste donc constante. La variable observee ici est le CRATERE, pas
# la perte d'eau -- une eau qui s'infiltre rendrait l'accumulation dans le
# creux illisible en quelques secondes.
#
# CE QU'ON DOIT VOIR : une grille 6x6 plate et brune, de l'eau posee sur la
# ligne du haut qui se repand jusqu'a un niveau a peu pres uniforme (teinte
# bleue). Un clic (bouton, ou clic gauche n'importe ou) frappe la case au
# CENTRE : elle vire au noir (creusement) et l'eau s'y accumule -- son
# niveau monte au-dessus de celui de ses voisines, exactement de la
# profondeur du creux. trace_age decompte a l'ecran ; a zero le cratere
# disparait d'un coup, la case redevient brune et l'eau accumulee repart
# vers les voisines. Compteur en haut : eau totale (constante) et nombre de
# crateres actifs. Console : une ligne a chaque impact, une a chaque
# effacement, une par seconde pour l'etat general.
#
# Deux moities, meme decoupage que les autres bancs :
# - Node (impur) : _ready construit la grille, le rendu et le bouton.
#   _unhandled_input frappe au clic gauche. _process appelle UNIQUEMENT
#   Depense.avancer puis Ecoulement.avancer (fonctions du coeur, jamais
#   reimplementees) et lit leurs resultats pour l'affichage/la console.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_cratere.gd) : construire_grille/case_centre/impacter/
#   rafraichir_altitudes_effectives/ids_creuses/effacements_de/
#   compter_crateres/couleur_case, plus les textes.

const Frappe = preload("res://scripts/frappe.gd")
const Depense = preload("res://scripts/depense.gd")
const Ecoulement = preload("res://scripts/ecoulement.gd")
const Somme = preload("res://scripts/somme.gd")

const TAILLE_CASE := 100.0
const MARGE_CASE := 6.0
const INTERVALLE_PRINT := 1.0

var _config: Dictionary = {}
var _catalogue_seuils: Dictionary = {}
var _cases: Array = []
var _noeuds: Dictionary = {}
var _labels_case: Dictionary = {}
var _label_compteur: Label
var _temps: float = 0.0
var _prochain_print: float = 0.0

func _ready() -> void:
	_config = _charger_json("res://data/banc_cratere.json")
	_catalogue_seuils = _charger_json("res://data/seuils_combustible.json")

	_cases = construire_grille(_config)
	for case in _cases:
		_creer_rendu_case(case)

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label_compteur = Label.new()
	_label_compteur.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label_compteur)
	var bouton := Button.new()
	bouton.text = "FRAPPER LE CENTRE"
	bouton.position = Vector2(10.0, 36.0)
	bouton.pressed.connect(_frapper_centre)
	couche_ui.add_child(bouton)

	_poser_camera()
	_rafraichir_tout()
	print(_ligne_pose_initiale(_cases, _config.nom_reserve_eau))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_frapper_centre()

func _process(delta: float) -> void:
	_temps += delta

	# ORDRE OBLIGATOIRE : relever les cases creusees AVANT Depense.avancer
	# (qui peut reposer creusement a 0.0 sans laisser de trace), puis
	# rederiver l'altitude effective AVANT Ecoulement.avancer (sinon
	# l'ecoulement de ce tick verrait le relief du tick precedent).
	var creusees_avant: Array = ids_creuses(_cases)
	var franchis: Array = Depense.avancer(_cases, delta, _catalogue_seuils)
	for id in effacements_de(franchis, creusees_avant):
		print(_ligne_effacement(_temps, id))

	rafraichir_altitudes_effectives(_cases, _config)
	var transferts: Array = Ecoulement.avancer(_cases, _config.rayon_voisinage, _config.nom_reserve_eau, _config.nom_altitude_effective, _config.taux_ecoulement, delta)

	_rafraichir_tout()

	if _temps >= _prochain_print:
		_prochain_print = _temps + INTERVALLE_PRINT
		print(_ligne_trace(_temps, transferts.size(), Somme.reserves(_cases, _config.nom_reserve_eau), compter_crateres(_cases)))

func _frapper_centre() -> void:
	var case: Variant = case_centre(_cases, _config)
	if case == null:
		return
	var resultat: Dictionary = impacter(case, _config)
	print(_ligne_impact(_temps, case.id, resultat))
	rafraichir_altitudes_effectives(_cases, _config)
	_rafraichir_tout()

func _rafraichir_tout() -> void:
	_label_compteur.text = "eau totale : %.2f    crateres actifs : %d" % [
		Somme.reserves(_cases, _config.nom_reserve_eau), compter_crateres(_cases)
	]
	for case in _cases:
		var id: String = case.id
		_noeuds[id].color = couleur_case(
			float(case.proprietes.get("creusement", 0.0)),
			float(case.proprietes.reserves[_config.nom_reserve_eau].reserve),
			float(_config.profondeur_impact),
			float(_config.eau_reference_couleur))
		_labels_case[id].text = texte_case(case, _config)

# ---- Fonctions PURES, testables headless (voir test_banc_cratere.gd) ----

# Construit la grille grille_lignes x grille_colonnes, TERRAIN PLAT
# (altitude_plate partout). Rend un Array plat, ordre ligne-majeur
# (index = ligne*grille_colonnes + colonne).
#
# TROIS CANAUX DE RESERVE par case, tous lus par le MEME Depense.avancer :
# - nom_reserve_eau : cout_base ET surcout_action a 0.0 -- l'eau ne se perd
#   jamais dans ce banc (voir en-tete), depense.gd la laisse donc intacte.
# - nom_reserve_integrite : la cible de Frappe.frapper, jamais decroissante
#   d'elle-meme (cout_base 0.0) -- seul un impact la fait descendre.
# - nom_reserve_trace : la duree de vie du cratere. Posee VIDE (reserve
#   0.0) et deja porteuse de seuils_ref : depense.gd applique donc son
#   seuil des le premier tick, ce qui repose creusement a 0.0 sur une case
#   ou il vaut deja 0.0 -- no-op voulu, jamais visible (effacements_de ne
#   trace que les cases qui etaient reellement creusees).
#
# eau_initiale est posee sur la LIGNE 0 seule (le haut de la grille), 0.0
# partout ailleurs -- meme geste que banc_ecoulement.gd sur sa colonne 0.
static func construire_grille(config: Dictionary) -> Array:
	var lignes: int = config.grille_lignes
	var colonnes: int = config.grille_colonnes
	var altitude: float = float(config.altitude_plate)
	var cases: Array = []
	for ligne in range(lignes):
		for colonne in range(colonnes):
			var eau: float = float(config.eau_initiale) if ligne == 0 else 0.0
			cases.append({
				"id": "case_%d_%d" % [colonne, ligne],
				"position": Vector3(float(colonne), float(ligne), 0.0),
				"proprietes": {
					config.nom_altitude_base: altitude,
					config.nom_altitude_effective: altitude,
					"creusement": 0.0,
					"reserves": {
						config.nom_reserve_eau: {
							"reserve": eau,
							"cout_base": 0.0,
							"surcout_action": 0.0,
							"seuils_ref": "",
						},
						config.nom_reserve_integrite: {
							"reserve": float(config.integrite_sol_max),
							"cout_base": 0.0,
							"surcout_action": 0.0,
							"seuils_ref": "",
						},
						config.nom_reserve_trace: {
							"reserve": 0.0,
							"capacite": float(config.duree_effacement),
							"cout_base": float(config.cout_base_trace),
							"surcout_action": 0.0,
							"seuils_ref": String(config.seuils_ref),
							"seuils_franchis": [],
						},
					},
				},
			})
	return cases

# La case au centre de la grille (division entiere -- 6x6 rend case_3_3).
# Rend null si "cases" est vide ou si aucune case ne porte cette position
# (chemin mort, jamais atteint par la config reelle).
static func case_centre(cases: Array, config: Dictionary) -> Variant:
	var colonne: int = int(config.grille_colonnes) / 2
	var ligne: int = int(config.grille_lignes) / 2
	for case in cases:
		if int(case.position.x) == colonne and int(case.position.y) == ligne:
			return case
	return null

# Frappe la case et, SI la frappe a fait retomber son integrite au seuil,
# ecrit le cratere. Mute "case" en place. Rend { creuse: bool,
# degats_reels: float, creusement: float, trace_age: float } -- pour la
# trace console, jamais recalcule par l'appelant.
#
# degats_reels est la quantite REELLEMENT retiree (frappe.gd borne la
# reserve a zero) : frapper une case deja a zero rend degats_reels 0.0 et
# ne creuse rien. Le ratio degats_reels/degats_reference est donc
# naturellement dans [0,1] des lors que degats_reference vaut
# integrite_sol_max ; le clamp reste une garde contre une donnee mal
# calibree, jamais un cas de jeu.
static func impacter(case: Dictionary, config: Dictionary) -> Dictionary:
	var nom_integrite: String = config.nom_reserve_integrite
	var canal: Dictionary = case.proprietes.get("reserves", {}).get(nom_integrite, {})
	var avant: float = float(canal.get("reserve", 0.0))
	Frappe.frapper(case, float(config.degats_impact), nom_integrite)
	var apres: float = float(canal.get("reserve", 0.0))
	var degats_reels: float = avant - apres

	if degats_reels <= 0.0 or apres > float(config.seuil_creusement):
		return {
			"creuse": false,
			"degats_reels": degats_reels,
			"creusement": float(case.proprietes.get("creusement", 0.0)),
			"trace_age": _reserve(case, config.nom_reserve_trace),
		}

	var reference: float = float(config.degats_reference)
	var ratio: float = clamp(degats_reels / reference, 0.0, 1.0) if reference > 0.0 else 0.0
	case.proprietes["creusement"] = float(config.profondeur_impact) * ratio

	var trace: Dictionary = case.proprietes.reserves[config.nom_reserve_trace]
	trace["reserve"] = float(config.duree_effacement)
	trace["capacite"] = float(config.duree_effacement)
	trace["seuils_franchis"] = []
	canal["reserve"] = float(config.integrite_sol_max)

	return {
		"creuse": true,
		"degats_reels": degats_reels,
		"creusement": float(case.proprietes.creusement),
		"trace_age": float(trace.reserve),
	}

# Redérive nom_altitude_effective = nom_altitude_base - creusement sur
# CHAQUE case. Mute en place. L'altitude de base n'est jamais touchee.
static func rafraichir_altitudes_effectives(cases: Array, config: Dictionary) -> void:
	for case in cases:
		var p: Dictionary = case.proprietes
		p[config.nom_altitude_effective] = float(p.get(config.nom_altitude_base, 0.0)) - float(p.get("creusement", 0.0))

static func ids_creuses(cases: Array) -> Array:
	var ids: Array = []
	for case in cases:
		if float(case.proprietes.get("creusement", 0.0)) > 0.0:
			ids.append(case.id)
	return ids

# Croise les ids rendus par Depense.avancer (toute case ayant franchi un
# seuil, sur n'importe quelle reserve) avec les cases qui etaient CREUSEES
# juste avant l'appel -- seule cette intersection est un effacement de
# cratere reel. Sans ce croisement, le seuil applique a vide au premier
# tick (voir construire_grille) tracerait 36 faux effacements.
static func effacements_de(franchis: Array, creusees_avant: Array) -> Array:
	var effaces: Array = []
	for id in franchis:
		if creusees_avant.has(id):
			effaces.append(id)
	return effaces

static func compter_crateres(cases: Array) -> int:
	return ids_creuses(cases).size()

# Deux interpolations enchainees : d'abord brun -> noir au ratio
# creusement/profondeur_ref (le creux), puis le resultat -> bleu au ratio
# niveau_eau/eau_ref (l'eau par-dessus). Une case creusee ET pleine d'eau
# tire donc vers un bleu sombre, jamais vers l'une des deux couleurs pures.
# profondeur_ref/eau_ref <= 0.0 : ratio 0, jamais une division par zero.
static func couleur_case(creusement: float, niveau_eau: float, profondeur_ref: float, eau_ref: float) -> Color:
	var ratio_creux: float = clamp(creusement / profondeur_ref, 0.0, 1.0) if profondeur_ref > 0.0 else 0.0
	var ratio_eau: float = clamp(niveau_eau / eau_ref, 0.0, 1.0) if eau_ref > 0.0 else 0.0
	var brun := Color(0.42, 0.30, 0.16)
	var noir := Color(0.04, 0.04, 0.05)
	var bleu := Color(0.10, 0.35, 0.85)
	return brun.lerp(noir, ratio_creux).lerp(bleu, ratio_eau)

static func texte_case(case: Dictionary, config: Dictionary) -> String:
	var p: Dictionary = case.proprietes
	var trace: Dictionary = p.get("reserves", {}).get(config.nom_reserve_trace, {})
	return "alt %.1f\ncreus %.2f\ntrace %.1f/%.1f\neau %.2f" % [
		float(p.get(config.nom_altitude_base, 0.0)),
		float(p.get("creusement", 0.0)),
		float(trace.get("reserve", 0.0)),
		float(trace.get("capacite", 0.0)),
		_reserve(case, config.nom_reserve_eau),
	]

static func _reserve(case: Dictionary, nom_reserve: String) -> float:
	return float(case.proprietes.get("reserves", {}).get(nom_reserve, {}).get("reserve", 0.0))

static func _ligne_pose_initiale(cases: Array, nom_reserve: String) -> String:
	return "t=0.0 grille posee : %d cases, terrain plat, eau totale=%.2f, aucun cratere" % [cases.size(), Somme.reserves(cases, nom_reserve)]

static func _ligne_impact(t: float, id: String, resultat: Dictionary) -> String:
	if not resultat.creuse:
		return "t=%.1f IMPACT sur %s : degats_reels=%.2f -- integrite non franchie, aucun cratere" % [t, id, resultat.degats_reels]
	return "t=%.1f IMPACT sur %s : degats_reels=%.2f creusement=%.2f trace_age=%.1f" % [t, id, resultat.degats_reels, resultat.creusement, resultat.trace_age]

static func _ligne_effacement(t: float, id: String) -> String:
	return "t=%.1f EFFACEMENT sur %s : trace_age epuise, creusement remis a 0.00 par depense.gd" % [t, id]

static func _ligne_trace(t: float, nb_transferts: int, eau_totale: float, crateres: int) -> String:
	return "t=%.1f transferts=%d eau_totale=%.2f crateres=%d" % [t, nb_transferts, eau_totale, crateres]

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
	label.position = centre - Vector2(taille_visible / 2.0 - 4.0, taille_visible / 2.0 - 2.0)
	add_child(label)
	_labels_case[id] = label

func _poser_camera() -> void:
	var lignes: int = _config.grille_lignes
	var colonnes: int = _config.grille_colonnes
	var centre := Vector2(float(colonnes - 1), float(lignes - 1)) * TAILLE_CASE / 2.0
	var camera := Camera2D.new()
	camera.position = centre
	camera.zoom = Vector2(0.85, 0.85)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
