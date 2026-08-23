extends Node

# BANC "test_ennemi2 Mother box" -- ACCELERATEUR DE JEU pour observation.
# Touche + / = -> vitesse * 2 (plafond 4x pour ne pas casser la physique
# RigidBody, dont les tick de collision saturent au-dela).
# Touche - / _ -> vitesse / 2 (plancher 0.25x).
# Touche 0 (numpad ou principal) -> reset a 1x.
# Affichage : un print console + un OSD Label ephemere en haut a droite.
#
# NE COMPOSE RIEN DU JEU : purement outil de dev. `Engine.time_scale`
# multiplie delta et le rythme des Timer -- tous les systemes existants
# suivent sans modification (extraction 3s * time_scale, gestation 20s *
# time_scale, etc.).

const PLAFOND := 10.0
const PLANCHER := 0.25

var _label: Label = null

func _ready() -> void:
	# OSD dans un CanvasLayer pour survivre au rendu 3D.
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color(1, 1, 0.3))
	layer.add_child(_label)
	_rafraichir_osd()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var ek: InputEventKey = event as InputEventKey
	var k: int = ek.keycode
	# + (KEY_PLUS = 43, KEY_EQUAL = 61 pour AZERTY = shift), KP_ADD (KEY_KP_ADD = 4118)
	if k == KEY_PLUS or k == KEY_EQUAL or k == KEY_KP_ADD:
		Engine.time_scale = minf(Engine.time_scale * 2.0, PLAFOND)
		_rafraichir_osd()
	elif k == KEY_MINUS or k == KEY_KP_SUBTRACT:
		Engine.time_scale = maxf(Engine.time_scale * 0.5, PLANCHER)
		_rafraichir_osd()
	elif k == KEY_0 or k == KEY_KP_0:
		Engine.time_scale = 1.0
		_rafraichir_osd()

func _rafraichir_osd() -> void:
	var txt := "Vitesse x%.2f  (+ / -  ou  0 = reset)" % Engine.time_scale
	print("[controle_vitesse] ", txt)
	if _label != null:
		_label.text = txt
