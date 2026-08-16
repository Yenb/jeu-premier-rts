extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_champ.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Existe pour VOIR
# scripts/champ.gd jouer en jeu pour la premiere fois : un golem
# CONTROLABLE (clic joueur) approche d'un aimant FIXE, et au fil de
# l'approche, une force qui n'a jamais ete decidee finit par dominer une
# force qui l'a ete. JETABLE PAR DEFINITION : aucune regle de jeu ne doit
# vivre ici, seulement du cablage.
#
# REUTILISATION, PAS RECREATION (consigne explicite) : le CONTROLE du golem
# (donner_ordre, avancer_controle -- lecture de "controlable"/"ordre_joueur",
# court-circuit du pipeline de decision) est repris TEL QUEL depuis
# scripts/banc_controle.gd, precharge ici (const BancControle), jamais
# reecrit. Ce fichier n'ajoute qu'UNE etape apres le pas volontaire :
# Champ.avancer (voir _process ci-dessous, decision Yael point 7).
#
# CE QUE `BancControle.fabriquer_golem` NE COUVRE PAS (et pourquoi ce
# fichier ecrit sa propre fabrication, sans toucher au CONTROLE) :
# `fabriquer_golem` appelle `Objet.fabriquer(nom, type, position, table)`
# SANS le parametre `materiaux` -- le golem original (data/banc_controle.json)
# ne porte jamais "composition", donc n'en a jamais eu besoin. Le golem de
# CE banc porte "composition" (pour que champ.gd lise son magnetisme a la
# demande, decision Yael point 5) : `Objet.fabriquer` EXIGE alors un
# catalogue `materiaux` (echec fort sinon, voir objet.gd). `fabriquer_golem_
# magnetique` ci-dessous est donc une fabrication PROPRE A CE BANC -- PAS
# le controle (donner_ordre/avancer_controle, entierement reutilises,
# jamais dupliques ici) -- exactement la meme discipline que
# `BancCommun.fabriquer_colon` (fabrication partagee) reste distincte de
# `agir.gd`/`dominance.gd` (decision partagee) : fabriquer et decider/obeir
# sont deux gestes separes, seul le second est "le controle golem".
#
# ECHELLE ET CALIBRATION : voir data/banc_champ.json._note (1 metre = 40
# unites, memes ordres de grandeur que les autres bancs). leger_golem/
# aimant_metal (data/materiaux.json, magnetisme dans l'echelle 0.0-1.0
# documentee la-bas) portent une MASSE minuscule -- champ.gd n'a aucune
# constante d'echelle globale, donc a portee/echelle de scene realistes,
# seule une masse tres petite rend la traction detectable face au pas
# volontaire. Calibre pour que le POINT DE BASCULE (ou la traction depasse
# le pas volontaire du golem) tombe vers 2-3 metres (80-120 unites) :
# VALEUR DE DEPART, a regler au ressenti -- aucune loi ne change si ces
# nombres bougent, voir data/champs.json et data/banc_champ.json.
#
# CE QU'ON DOIT VOIR : le joueur clique pour approcher le golem (violet) de
# l'aimant (gris fonce, immobile -- masse enorme, AUCUNE propriete "fixe").
# Loin (6-4m), la traction est faible, le clic gagne facilement. Vers 3m,
# la traction contre le pas volontaire, l'approche ralentit. Vers 1-2m, la
# traction depasse le pas volontaire : le golem est aspire, le joueur ne
# controle plus -- AUCUNE branche "if domine" nulle part dans ce fichier
# ni dans champ.gd, la domination EMERGE de la somme (pas volontaire PUIS
# deviation de champ.gd, chacun independant). Un Label affiche a chaque
# tick la distance et la force courantes (Champ.force_paire, lecture
# seule, jamais une reimplementation de la loi).
#
# bouger_vers et le contrat de mouvement partage (BancCommun) restent
# INCHANGES : ce banc ne les touche jamais, la composition champ + decision
# est une simple SUCCESSION de deux etapes dans _process, pas une fusion de
# contrat (voir champ.gd, "Frontiere avec fuite.gd").

const Objet = preload("res://scripts/objet.gd")
const Champ = preload("res://scripts/champ.gd")
const BancControle = preload("res://scripts/banc_controle.gd")

const TAILLE_GOLEM := 20.0
const TAILLE_AIMANT := 40.0
const ZOOM_CAMERA := 1.0
const INTERVALLE_PRINT := 0.5

var _donnees: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _materiaux: Dictionary = {}
var _catalogue_champs: Dictionary = {}
var _golem: Dictionary = {}
var _aimant: Dictionary = {}
var _noeud_golem: ColorRect
var _noeud_aimant: ColorRect
var _label: Label
var _temps_ecoule := 0.0
var _prochain_print := 0.0

func _ready() -> void:
	_donnees = _charger_json("res://data/banc_champ.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_catalogue_champs = _charger_json("res://data/champs.json")

	_catalogue_types = _donnees.get("types", {}).duplicate(true)
	var types_partages := _charger_json("res://data/types.json")
	_catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	_catalogue_types["dynamique"] = types_partages.get("dynamique", {})

	_golem = fabriquer_golem_magnetique("golem_1", "golem_magnetique", _donnees.get("golem", {}), _catalogue_types, _materiaux)
	_aimant = _fabriquer_aimant("aimant_1", "aimant", _donnees.get("aimant", {}), _catalogue_types, _materiaux)

	_noeud_golem = _dessiner_carre(_golem.position, TAILLE_GOLEM, Color(0.55, 0.25, 0.85))
	_noeud_aimant = _dessiner_carre(_aimant.position, TAILLE_AIMANT, Color(0.3, 0.3, 0.32))

	# CanvasLayer : le Label doit rester fixe a l'ecran, jamais transforme par
	# la Camera2D (position/zoom) comme le sont golem/aimant -- patron HUD
	# standard Godot. PREMIER banc du depot a combiner camera et texte a
	# l'ecran (voir en-tete) : aucun autre banc n'avait ce besoin.
	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label = Label.new()
	_label.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label)

	_poser_camera([Vector2(_golem.position.x, _golem.position.y), Vector2(_aimant.position.x, _aimant.position.y)])

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos := get_global_mouse_position()
	BancControle.donner_ordre(_golem, Vector3(pos.x, pos.y, 0.0))

func _process(delta: float) -> void:
	_temps_ecoule += delta
	# Ordre 1 : le pas VOLONTAIRE (decision du joueur), entierement repris de
	# banc_controle.gd, inchange.
	BancControle.avancer_controle(_golem, delta)
	# Ordre 2 : la deviation SUBIE, ajoutee PAR-DESSUS -- aucune branche "if
	# domine" : Champ.avancer mute position en place independamment de ce
	# que le pas volontaire vient de faire (voir champ.gd, decision Yael
	# point 7).
	Champ.avancer([_golem, _aimant], delta, _catalogue_champs, _materiaux)

	_redessiner(_noeud_golem, _golem.position)
	_redessiner(_noeud_aimant, _aimant.position)
	_mettre_a_jour_observabilite()

# Fabrication PROPRE A CE BANC (voir en-tete) -- PAS le controle, qui reste
# BancControle.donner_ordre/avancer_controle, jamais duplique ici.
static func fabriquer_golem_magnetique(nom: String, type: String, decl: Dictionary, catalogue_types: Dictionary, materiaux: Dictionary) -> Dictionary:
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	var position3 := Vector3(pos[0], pos[1], pos[2])
	var golem := Objet.fabriquer(nom, type, position3, catalogue_types, materiaux)
	if not golem.is_empty() and decl.has("lie_au_joueur"):
		golem.proprietes["lie_au_joueur"] = decl.lie_au_joueur
	return golem

static func _fabriquer_aimant(nom: String, type: String, decl: Dictionary, catalogue_types: Dictionary, materiaux: Dictionary) -> Dictionary:
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	var position3 := Vector3(pos[0], pos[1], pos[2])
	return Objet.fabriquer(nom, type, position3, catalogue_types, materiaux)

func _mettre_a_jour_observabilite() -> void:
	var distance: float = _golem.position.distance_to(_aimant.position)
	var force: float = Champ.force_paire(_golem, _aimant, _catalogue_champs.get("magnetisme", {}), _materiaux)
	_label.text = "distance golem-aimant : %.1f u (~%.2f m) | force de traction : %.4f" % [distance, distance / 40.0, force]
	if _temps_ecoule >= _prochain_print:
		_prochain_print = _temps_ecoule + INTERVALLE_PRINT
		print("t=%.1f distance=%.1f (~%.2fm) force=%.4f" % [_temps_ecoule, distance, distance / 40.0, force])

func _dessiner_carre(position3: Vector3, taille: float, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	carre.position = Vector2(position3.x, position3.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _redessiner(noeud: ColorRect, position3: Vector3) -> void:
	noeud.position = Vector2(position3.x, position3.y) - noeud.size / 2.0

func _poser_camera(positions: Array) -> void:
	var centre := Vector2.ZERO
	for p in positions:
		centre += p
	if positions.size() > 0:
		centre /= positions.size()
	var camera := Camera2D.new()
	camera.position = centre
	camera.zoom = Vector2(ZOOM_CAMERA, ZOOM_CAMERA)
	camera.enabled = true
	add_child(camera)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
