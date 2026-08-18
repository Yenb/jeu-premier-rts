extends Node2D

# Cablage de banc VISUEL, separe (Scene/banc_temperature.tscn, PAS la scene
# principale -- run/main_scene reste banc_p1, coexiste avec les autres
# bancs). Existe pour VOIR scripts/temperature.gd (ferme et prouve hors
# domaine par test_temperature.gd, lint vert) tourner sur une scene
# observable -- PREMIERE DEMONSTRATION REELLE. JETABLE PAR DEFINITION.
# Recopie le patron de scripts/banc_vent.gd (Node impur + fonctions
# statiques pures testables, CanvasLayer pour le HUD, Camera2D fixe).
#
# CE QU'IL DOIT MONTRER : un feu FIXE (source de chaleur immobile) et une
# source MOBILE qui traverse la scene toute seule (mouvement sinusoidal,
# fonction pure du temps -- aucun hasard, meme discipline que vent.gd) --
# les deux sont de simples Dictionary { position, rayon, temperature,
# force } CONSTRUITS PAR CE BANC, jamais par temperature.gd (voir
# temperature.gd, en-tete : "sources... construit et possede ENTIEREMENT
# par l'appelant"). Un troisieme objet, `objet_test`, est DEPLACE AU
# CLAVIER (fleches OU ZQSD) -- c'est CE BANC qui ecrit sa nouvelle
# position chaque tick (Input lu ici, jamais dans temperature.gd), qui
# n'avance jamais lui-meme aucune position. `Temperature.avancer` fait
# ensuite avancer sa temperature vers la temperature locale a sa position
# COURANTE -- la loi de Newton (vite d'abord, puis de plus en plus
# lentement) devient visible a l'oeil en approchant/eloignant l'objet
# d'une source. Un Label (CanvasLayer, patron banc_champ.gd/banc_vent.gd)
# affiche EN PERMANENCE, pour objet_test : sa temperature, la temperature
# locale a sa position, et l'ecart entre les deux. Chaque carre (objet_test,
# feu, source_mobile) est colore du FROID au CHAUD selon sa propre
# temperature (couleur_pour_temperature, lisible sans lire la console).
# Trace console : un rapport periodique (intervalle en donnee), une ligne
# par rapport, meme discipline que banc_vent.gd.
#
# PORTEE VOLONTAIREMENT LIMITEE : ce banc ne route rien par
# attaches.gd/proximite.gd/jugement.gd/dominance.gd/agir.gd -- aucune
# decision, seulement un deplacement direct au clavier et l'appel du
# mecanisme de temperature. Aucun allumage, aucun seuil de fusion, aucun
# abri -- hors perimetre du chantier "temperature", mecanisme de base
# seul (voir temperature.gd).
#
# Deux moities, meme decoupage que banc_vent.gd :
# - Node (impur) : _ready charge data/banc_temperature.json (jetable,
#   propre a ce banc) et data/temperature.json (catalogue PARTAGE, reel,
#   jamais surcharge ni mute ici -- meme discipline que banc_vent.gd avec
#   data/vent.json). _process lit le clavier, deplace objet_test, deplace
#   la source mobile, appelle Temperature.avancer/locale, redessine les
#   trois carres et le Label, imprime le rapport periodique.
# - Fonctions statiques (pures, testables headless, voir
#   test_banc_temperature.gd) : deplacement_clavier, position_source_mobile,
#   sources_du_tick, fabriquer_objet_test, couleur_pour_temperature,
#   texte_objet, ligne_log.

const Temperature = preload("res://scripts/temperature.gd")

const TAILLE_OBJET := 40.0
const TAILLE_FEU := 60.0
const TAILLE_SOURCE_MOBILE := 30.0

var _donnees: Dictionary = {}
var _catalogue_temperature: Dictionary = {}
var _objet_test: Dictionary = {}
var _feu: Dictionary = {}
var _centre_mobile := Vector3.ZERO
var _amplitude_mobile := 0.0
var _periode_mobile := 0.0
var _rayon_mobile := 0.0
var _temperature_mobile := 0.0
var _force_mobile := 1.0
var _vitesse_objet := 0.0
var _couleur_froid := Color.BLUE
var _couleur_chaud := Color.RED
var _echelle_min := 0.0
var _echelle_max := 100.0
var _noeud_objet: ColorRect
var _noeud_feu: ColorRect
var _noeud_source_mobile: ColorRect
var _label: Label
var _temps_ecoule := 0.0
var _prochain_print := 0.0
var _intervalle_print := 2.0

func _ready() -> void:
	_donnees = _charger_json("res://data/banc_temperature.json")
	_catalogue_temperature = _charger_json("res://data/temperature.json")

	_intervalle_print = _donnees.get("intervalle_print", 2.0)
	_couleur_froid = _couleur_depuis_array(_donnees.get("couleur_froid", [0.15, 0.35, 0.85]))
	_couleur_chaud = _couleur_depuis_array(_donnees.get("couleur_chaud", [0.85, 0.15, 0.1]))
	var echelle: Dictionary = _donnees.get("echelle_couleur", {})
	_echelle_min = echelle.get("min", 0.0)
	_echelle_max = echelle.get("max", 100.0)

	var decl_feu: Dictionary = _donnees.get("feu", {})
	var pos_feu: Array = decl_feu.get("position", [0.0, 0.0, 0.0])
	_feu = {
		"position": Vector3(pos_feu[0], pos_feu[1], pos_feu[2]),
		"rayon": decl_feu.get("rayon", 300.0),
		"temperature": decl_feu.get("temperature", 300.0),
		"force": decl_feu.get("force", 1.0),
	}

	var decl_mobile: Dictionary = _donnees.get("source_mobile", {})
	var pos_centre: Array = decl_mobile.get("centre", [0.0, 0.0, 0.0])
	_centre_mobile = Vector3(pos_centre[0], pos_centre[1], pos_centre[2])
	_amplitude_mobile = decl_mobile.get("amplitude", 250.0)
	_periode_mobile = decl_mobile.get("periode", 12.0)
	_rayon_mobile = decl_mobile.get("rayon", 200.0)
	_temperature_mobile = decl_mobile.get("temperature", 150.0)
	_force_mobile = decl_mobile.get("force", 1.0)

	var decl_objet: Dictionary = _donnees.get("objet_test", {})
	var pos_objet: Array = decl_objet.get("position", [-300.0, 200.0, 0.0])
	_vitesse_objet = decl_objet.get("vitesse", 200.0)
	_objet_test = fabriquer_objet_test(
		Vector3(pos_objet[0], pos_objet[1], pos_objet[2]),
		decl_objet.get("temperature_initiale", 20.0),
		decl_objet.get("conductivite_thermique", 0.4),
	)

	_noeud_feu = _dessiner_carre(_feu.position, TAILLE_FEU, _couleur_pour(_feu.temperature))
	_noeud_source_mobile = _dessiner_carre(_centre_mobile, TAILLE_SOURCE_MOBILE, _couleur_pour(_temperature_mobile))
	_noeud_objet = _dessiner_carre(_objet_test.position, TAILLE_OBJET, _couleur_pour(_objet_test.proprietes.temperature))

	var couche_ui := CanvasLayer.new()
	add_child(couche_ui)
	_label = Label.new()
	_label.position = Vector2(10.0, 10.0)
	couche_ui.add_child(_label)

	var decl_camera: Dictionary = _donnees.get("camera", {})
	var pos_camera: Array = decl_camera.get("position", [0.0, 0.0, 0.0])
	var camera := Camera2D.new()
	camera.position = Vector2(pos_camera[0], pos_camera[1])
	camera.zoom = Vector2(decl_camera.get("zoom", 0.7), decl_camera.get("zoom", 0.7))
	camera.enabled = true
	add_child(camera)

func _process(delta: float) -> void:
	_temps_ecoule += delta

	var gauche := Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_Q)
	var droite := Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D)
	var haut := Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_Z)
	var bas := Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)
	_objet_test.position += deplacement_clavier(gauche, droite, haut, bas, _vitesse_objet, delta)

	var position_mobile := position_source_mobile(_centre_mobile, _amplitude_mobile, _periode_mobile, _temps_ecoule)
	var sources := sources_du_tick(_feu, position_mobile, _rayon_mobile, _temperature_mobile, _force_mobile)

	var monde := [_objet_test]
	Temperature.avancer(monde, sources, delta, _catalogue_temperature)
	var locale: float = Temperature.locale(_objet_test.position, sources, _catalogue_temperature)

	_noeud_objet.position = Vector2(_objet_test.position.x, _objet_test.position.y) - _noeud_objet.size / 2.0
	_noeud_objet.color = _couleur_pour(_objet_test.proprietes.temperature)
	_noeud_source_mobile.position = Vector2(position_mobile.x, position_mobile.y) - _noeud_source_mobile.size / 2.0

	_label.text = texte_objet(_objet_test.proprietes.temperature, locale)

	if _temps_ecoule >= _prochain_print:
		_prochain_print = _temps_ecoule + _intervalle_print
		print(ligne_log(_temps_ecoule, _objet_test.position, _objet_test.proprietes.temperature, locale))

# ---- Fonctions statiques, pures, testables ----

# Deplacement de l'objet de test pour ce pas, depuis l'etat des touches
# (fleches OU ZQSD -- lu dans _process, jamais ici) : diagonales
# NORMALISEES (une diagonale ne va pas plus vite qu'un axe seul), aucun
# mouvement si aucune touche n'est enfoncee. Convention Godot 2D : Y
# croit vers le bas, "haut" diminue Y.
static func deplacement_clavier(gauche: bool, droite: bool, haut: bool, bas: bool, vitesse: float, delta: float) -> Vector3:
	var direction := Vector3.ZERO
	if droite:
		direction.x += 1.0
	if gauche:
		direction.x -= 1.0
	if bas:
		direction.y += 1.0
	if haut:
		direction.y -= 1.0
	if direction.length() > 0.0001:
		direction = direction.normalized()
	return direction * vitesse * delta

# Position de la source mobile a l'instant `temps` : un aller-retour
# sinusoidal autour de `centre`, fonction PURE du temps, aucun etat, aucun
# hasard -- meme discipline que vent.gd (rejouer le meme temps rend
# toujours la meme position). `periode` <= 0.0 : la source reste immobile
# au centre, jamais une division par zero.
static func position_source_mobile(centre: Vector3, amplitude: float, periode: float, temps: float) -> Vector3:
	if periode <= 0.0:
		return centre
	var decalage: float = amplitude * sin(TAU * temps / periode)
	return centre + Vector3(decalage, 0.0, 0.0)

# Les deux sources de ce tick, dans la forme attendue par
# temperature.gd:locale/avancer -- construites ICI, jamais par le
# mecanisme (voir temperature.gd, en-tete).
static func sources_du_tick(feu: Dictionary, position_mobile: Vector3, rayon_mobile: float, temperature_mobile: float, force_mobile: float) -> Array:
	return [
		feu,
		{"position": position_mobile, "rayon": rayon_mobile, "temperature": temperature_mobile, "force": force_mobile},
	]

# L'objet deplace au clavier : porte sa propre temperature (paquet
# objet_physique) et sa conductivite -- les deux seules cles que
# temperature.gd lit sur une chose.
static func fabriquer_objet_test(position: Vector3, temperature_initiale: float, conductivite: float) -> Dictionary:
	return {
		"id": "objet_test",
		"position": position,
		"proprietes": {"temperature": temperature_initiale, "conductivite_thermique": conductivite},
	}

# Couleur FROID -> CHAUD, interpolation lineaire bornee sur [mini, maxi] --
# lisible a l'oeil sans lire aucun nombre. maxi <= mini : repli neutre sur
# couleur_froid, jamais une division par zero ni une couleur devinee.
static func couleur_pour_temperature(temperature: float, mini: float, maxi: float, couleur_froid: Color, couleur_chaud: Color) -> Color:
	if maxi <= mini:
		return couleur_froid
	var ratio: float = clamp((temperature - mini) / (maxi - mini), 0.0, 1.0)
	return couleur_froid.lerp(couleur_chaud, ratio)

# Texte HUD permanent : les trois nombres demandes -- temperature de
# l'objet, temperature locale a sa position, ecart entre les deux (signe
# = sens dans lequel la loi de Newton pousse encore l'objet).
static func texte_objet(temperature: float, locale: float) -> String:
	return "objet_test\ntemperature = %.1f\ntemperature locale = %.1f\necart = %.1f\n\nfleches ou ZQSD pour deplacer" % [temperature, locale, locale - temperature]

static func ligne_log(t: float, position: Vector3, temperature: float, locale: float) -> String:
	return "t=%.1f objet_test(%.0f,%.0f) : temperature=%.1f locale=%.1f ecart=%.1f" % [t, position.x, position.y, temperature, locale, locale - temperature]

# ---- Rendu, jetable ----

func _couleur_pour(temperature: float) -> Color:
	return couleur_pour_temperature(temperature, _echelle_min, _echelle_max, _couleur_froid, _couleur_chaud)

func _dessiner_carre(position3: Vector3, taille: float, couleur: Color) -> ColorRect:
	var carre := ColorRect.new()
	carre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carre.size = Vector2(taille, taille)
	carre.color = couleur
	carre.position = Vector2(position3.x, position3.y) - carre.size / 2.0
	add_child(carre)
	return carre

func _couleur_depuis_array(rgb: Array) -> Color:
	return Color(rgb[0], rgb[1], rgb[2])

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))
