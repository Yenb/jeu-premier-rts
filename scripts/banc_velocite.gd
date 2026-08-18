extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_velocite.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1). Existe pour VOIR
# scripts/velocite.gd jouer en jeu pour la premiere fois : QUATRE objets --
# un colon deplace au clic (mouvement VOLONTAIRE seul), le golem/aimant de
# banc_champ.gd REUTILISES TELS QUELS (mouvement SUBI par un champ, PLUS un
# ordre volontaire partage avec le colon), et un repere qui ne bouge jamais
# -- affichent tous les quatre leur velocite courante, derivee PASSIVEMENT
# par Velocite.avancer, dernier appel de _process (voir velocite.gd,
# "COUT D'ADOPTION"). JETABLE PAR DEFINITION : aucune regle de jeu ne doit
# vivre ici, seulement du cablage.
#
# REUTILISATION, PAS RECREATION (meme discipline que banc_champ.gd,
# decision Yael) : le CONTROLE (BancControle.donner_ordre/avancer_controle)
# et le golem/aimant magnetiques (BancChamp.fabriquer_golem_magnetique/
# _fabriquer_aimant, Champ.avancer, data/banc_champ.json/data/champs.json)
# sont repris TEL QUEL, precharges ici, JAMAIS dupliques. Ce fichier
# n'ajoute que : un colon local (controllable, sans composition -- jamais
# dans le champ magnetique), un repere immobile, et l'appel a
# Velocite.avancer -- une seule etape neuve apres celles des deux bancs
# reutilises.
#
# UN SEUL CLIC, DEUX ORDRES : le clic gauche pose le MEME point-cible sur
# le colon ET sur le golem (BancControle.donner_ordre, appele deux fois) --
# aucune ambiguite d'entree, et ca reproduit EXACTEMENT l'interaction deja
# prouvee par banc_champ.gd pour le golem (loin le clic gagne, pres le champ
# domine) tout en donnant au colon un mouvement volontaire pur, sans aucun
# champ, pour contraste. Cliquer PRES de l'aimant fait monter la velocite du
# golem (le champ domine, 1/d^2) ; cliquer LOIN de l'aimant, dans la
# direction opposee, la fait redescendre (le pas volontaire l'emporte, le
# champ est faible) -- AUCUNE branche "si pres"/"si loin" nulle part ici,
# la difference emerge de la meme composition que banc_champ.gd (voir
# champ.gd, "Frontiere avec fuite.gd").
#
# CE QU'ON DOIT VOIR : le colon (rouge) part immobile (velocite affichee
# (0,0,0)), un clic gauche le fait avancer -- sa velocite (magnitude
# affichee) monte vers sa vitesse plafond puis retombe exactement a zero des
# qu'il atteint la cible (BancCommun.bouger_vers, deja borne). Le golem
# (violet) et l'aimant (gris fonce) reproduisent banc_champ.gd -- le golem
# accelere en s'approchant de l'aimant (velocite qui monte), ralentit ou
# s'eloigne si le prochain clic l'envoie loin de l'aimant (velocite qui
# redescend, portee par le pas volontaire seul, le champ faiblissant en
# 1/d^2). Le repere (gris clair), jamais touche par aucun mecanisme, affiche
# EXACTEMENT velocite=(0,0,0) sur toute l'observation. Un Label recapitule
# les quatre lignes (id, velocite, magnitude) a chaque tick ; la console
# imprime la meme chose toutes les 0.5s.

const Objet = preload("res://scripts/objet.gd")
const Velocite = preload("res://scripts/velocite.gd")
const Champ = preload("res://scripts/champ.gd")
const BancChamp = preload("res://scripts/banc_champ.gd")
const BancControle = preload("res://scripts/banc_controle.gd")

const TAILLE_COLON := 20.0
const TAILLE_GOLEM := 20.0
const TAILLE_AIMANT := 40.0
const TAILLE_REPERE := 14.0
const ZOOM_CAMERA := 0.8
const INTERVALLE_PRINT := 0.5

var _donnees: Dictionary = {}
var _donnees_champ: Dictionary = {}
var _catalogue_types: Dictionary = {}
var _materiaux: Dictionary = {}
var _catalogue_champs: Dictionary = {}
var _colon: Dictionary = {}
var _golem: Dictionary = {}
var _aimant: Dictionary = {}
var _repere: Dictionary = {}
var _noeuds: Dictionary = {}
var _label: Label
var _temps_ecoule := 0.0
var _prochain_print := 0.0

func _ready() -> void:
	_donnees = _charger_json("res://data/banc_velocite.json")
	_donnees_champ = _charger_json("res://data/banc_champ.json")
	_materiaux = _charger_json("res://data/materiaux.json")
	_catalogue_champs = _charger_json("res://data/champs.json")

	_catalogue_types = _donnees.get("types", {}).duplicate(true)
	_catalogue_types.merge(_donnees_champ.get("types", {}).duplicate(true))
	var types_partages := _charger_json("res://data/types.json")
	_catalogue_types["objet_physique"] = types_partages.get("objet_physique", {})
	_catalogue_types["dynamique"] = types_partages.get("dynamique", {})

	_colon = Objet.fabriquer("colon_1", "colon_velocite", _position_decl(_donnees.get("colon", {})), _catalogue_types)
	_golem = BancChamp.fabriquer_golem_magnetique("golem_1", "golem_magnetique", _donnees_champ.get("golem", {}), _catalogue_types, _materiaux)
	_aimant = BancChamp._fabriquer_aimant("aimant_1", "aimant", _donnees_champ.get("aimant", {}), _catalogue_types, _materiaux)
	_repere = Objet.fabriquer("repere_1", "repere", _position_decl(_donnees.get("repere", {})), _catalogue_types)

	_noeuds[_colon.id] = _dessiner_carre(_colon.position, TAILLE_COLON, Color(0.8, 0.2, 0.2))
	_noeuds[_golem.id] = _dessiner_carre(_golem.position, TAILLE_GOLEM, Color(0.55, 0.25, 0.85))
	_noeuds[_aimant.id] = _dessiner_carre(_aimant.position, TAILLE_AIMANT, Color(0.3, 0.3, 0.32))
	_noeuds[_repere.id] = _dessiner_carre(_repere.position, TAILLE_REPERE, Color(0.6, 0.6, 0.6))

	# CanvasLayer : le Label doit rester fixe a l'ecran, jamais transforme
	# par la Camera2D -- meme patron HUD que banc_champ.gd.
	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label = Label.new()
	_label.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label)

	_poser_camera([
		Vector2(_colon.position.x, _colon.position.y),
		Vector2(_golem.position.x, _golem.position.y),
		Vector2(_aimant.position.x, _aimant.position.y),
		Vector2(_repere.position.x, _repere.position.y),
	])

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos := get_global_mouse_position()
	var cible := Vector3(pos.x, pos.y, 0.0)
	BancControle.donner_ordre(_colon, cible)
	BancControle.donner_ordre(_golem, cible)

func _process(delta: float) -> void:
	_temps_ecoule += delta
	BancControle.avancer_controle(_colon, delta)
	BancControle.avancer_controle(_golem, delta)
	Champ.avancer([_golem, _aimant], delta, _catalogue_champs, _materiaux)
	# DERNIER appel du tick, apres TOUS les mecanismes qui mutent position
	# ce pas -- voir velocite.gd, "COUT D'ADOPTION".
	Velocite.avancer([_colon, _golem, _aimant, _repere], delta)

	_redessiner(_noeuds[_colon.id], _colon.position)
	_redessiner(_noeuds[_golem.id], _golem.position)
	_redessiner(_noeuds[_aimant.id], _aimant.position)
	_redessiner(_noeuds[_repere.id], _repere.position)

	_mettre_a_jour_observabilite()

static func _position_decl(decl: Dictionary) -> Vector3:
	var pos: Array = decl.get("position", [0.0, 0.0, 0.0])
	return Vector3(pos[0], pos[1], pos[2])

# Fonction PURE, testable headless : construit le texte affiche a partir de
# quatre objets DEJA avances (proprietes.velocite deja calculee par
# Velocite.avancer) -- jamais une reimplementation du calcul de velocite,
# seulement sa mise en forme.
static func texte_label(colon: Dictionary, golem: Dictionary, aimant: Dictionary, repere: Dictionary) -> String:
	var lignes: Array = []
	for entree in [["colon", colon], ["golem", golem], ["aimant", aimant], ["repere", repere]]:
		var nom: String = entree[0]
		var chose: Dictionary = entree[1]
		var velocite: Vector3 = chose.proprietes.get("velocite", Vector3.ZERO)
		lignes.append("%s : velocite=(%.2f, %.2f, %.2f) |v|=%.2f" % [nom, velocite.x, velocite.y, velocite.z, velocite.length()])
	return "\n".join(lignes)

func _mettre_a_jour_observabilite() -> void:
	var texte := texte_label(_colon, _golem, _aimant, _repere)
	_label.text = texte
	if _temps_ecoule >= _prochain_print:
		_prochain_print = _temps_ecoule + INTERVALLE_PRINT
		print("t=%.1f\n%s" % [_temps_ecoule, texte])

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
