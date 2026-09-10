# JOUEUR JETABLE DU BANC ARBRE.
#
# CharacterBody3D pose au-dessus du sol du banc, pour se promener a
# hauteur d'oeil dans la foret et la juger depuis l'interieur. Exception
# joueur du CLAUDE.md (§ Doctrine de base) : seul pont autorise entre le
# monde data et le rendu Godot, parce que c'est lui qui recoit les inputs
# et donne le point de vue. Ne simule RIEN du monde : ne touche ni les
# arbres, ni le champ de couvert, ni la banque de graines. Les arbres
# n'ont aucun corps physique (MultiMesh) -- le joueur les traverse,
# assume dans ce jet.
#
# INPUT. project.godot n'a pas de section [input] : on utilise les
# actions ui_* de Godot (toujours presentes) plus la souris, sans creer
# d'actions nouvelles. Avant/arriere = ui_up/ui_down, gauche/droite
# (STRAFE, pas rotation) = ui_left/ui_right. La rotation vient uniquement
# de la souris (lacet du corps, tangage des yeux borne). ECHAP libere le
# curseur, un clic le reprend. Le joueur du JEU (jeu/unites/personnage.gd)
# fait autrement (ui_left/right rotate) -- ce banc est jetable, la
# difference est assumee.
#
# ORDRE D'EXECUTION. Mouvement dans _physics_process (interpolation
# physique active dans project.godot), evenements souris dans _input.
# Camera enfant reglee current=true au _ready pour prendre le point de
# vue a la place de la camera plongeante du banc.

extends CharacterBody3D

const VITESSE_MARCHE := 6.0
const GRAVITE := 20.0
const SENSIBILITE_SOURIS := 0.003
const INCLINAISON_MAX := 1.5
const HAUTEUR_CAPSULE := 1.8
const RAYON_CAPSULE := 0.35
const HAUTEUR_YEUX := 1.7

var _lacet: float = 0.0
var _tangage: float = 0.0
var _yeux: Camera3D = null

func _ready() -> void:
	var forme := CapsuleShape3D.new()
	forme.radius = RAYON_CAPSULE
	forme.height = HAUTEUR_CAPSULE
	var collision := CollisionShape3D.new()
	collision.shape = forme
	collision.position = Vector3(0.0, HAUTEUR_CAPSULE * 0.5, 0.0)
	add_child(collision)
	var corps := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = RAYON_CAPSULE
	mesh.height = HAUTEUR_CAPSULE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.75, 0.4)
	mesh.material = mat
	corps.mesh = mesh
	corps.position = Vector3(0.0, HAUTEUR_CAPSULE * 0.5, 0.0)
	add_child(corps)
	_yeux = Camera3D.new()
	_yeux.position = Vector3(0.0, HAUTEUR_YEUX, 0.0)
	_yeux.near = 0.05
	_yeux.current = true
	add_child(_yeux)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(evenement: InputEvent) -> void:
	if evenement.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if evenement is InputEventMouseButton and evenement.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not (evenement is InputEventMouseMotion):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_lacet -= evenement.relative.x * SENSIBILITE_SOURIS
	_tangage = clampf(_tangage - evenement.relative.y * SENSIBILITE_SOURIS,
		-INCLINAISON_MAX, INCLINAISON_MAX)

func _physics_process(delta: float) -> void:
	rotation = Vector3(0.0, _lacet, 0.0)
	if _yeux != null:
		_yeux.rotation.x = _tangage
	var avance: float = Input.get_axis("ui_down", "ui_up")
	var strafe: float = Input.get_axis("ui_left", "ui_right")
	var base := Basis(Vector3.UP, _lacet)
	var direction := (-base.z) * avance + base.x * strafe
	direction.y = 0.0
	if direction.length_squared() > 0.0:
		direction = direction.normalized()
	velocity.x = direction.x * VITESSE_MARCHE
	velocity.z = direction.z * VITESSE_MARCHE
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITE * delta
	move_and_slide()
