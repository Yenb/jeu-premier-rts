# Proto : arme au clic gauche. Recopie du patron `jeu/Outil de jeu/arme_distance.gd`
# avec trois differences :
#   - CLIC GAUCHE au lieu de touche F.
#   - Spawn depuis le CUBE de l'arme (face avant, local Z=-0.15) au lieu de
#     la camera.
#   - Direction = -Z monde du cube, pas de la camera.
#
# Le tireur (parent = Personnage = CharacterBody3D) est exclu des raycasts
# du projectile, comme dans le patron original -- sinon la balle tape la
# capsule du perso au premier frame et meurt.
#
# Intention / consequence si echec / plan B documentes dans le tour ou le
# script a ete cree.
extends Node3D

# LA FACE AVANT DU CUBE : cube de 0.3 m, moitie = 0.15 m sur -Z local.
@export var decalage_avant: float = 0.15

# CORPS-A-CORPS AU CLIC DROIT : portee courte, cadence rapide, ennemis
# uniquement. Le manager fait le test cone.
@export var portee_melee: float = 2.0
@export var degat_melee: int = 2
@export var cadence_melee: float = 0.4  # secondes entre deux coups
var _cooldown_melee: float = 0.0

# LE PREMIER CLIC POSE mouse_mode=CAPTURED (voir personnage.gd) et
# personnage.gd ne consomme PAS l'evenement -- l'ordre d'appel de
# _unhandled_input entre noeuds n'est pas garanti. Sans ce flag, si
# arme_tir tourne apres personnage.gd, le premier clic tire aussi (une
# balle part au geste qui sert a rentrer en jeu). Le flag ne passe a
# vrai qu'a la frame SUIVANT la premiere capture vue par _process --
# le premier clic est donc toujours consomme par la capture.
var _prete: bool = false

func _process(delta: float) -> void:
	# APRES UN ECHAP (mode=VISIBLE), le prochain clic recapture -- il ne
	# doit pas tirer. Sans ce reset, _prete reste true entre deux captures
	# et un clic de recapture tire par accident. La regle est la meme
	# qu'au demarrage : une frame de latence apres chaque passage a
	# CAPTURED.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_prete = true
	else:
		_prete = false
	# Horloge de cadence corps-a-corps : decroit meme quand curseur
	# relache, sinon un ECHAP prolongerait le cooldown au retour.
	if _cooldown_melee > 0.0:
		_cooldown_melee = max(0.0, _cooldown_melee - delta)
	# RECOPIE TANGAGE YEUX : l'arme est enfant direct de Personnage (pas de
	# Personnage/Yeux) pour eviter la purge silencieuse de Godot 4 sur les
	# enfants ajoutes a des noeuds internes d'instances sans editable_children
	# (issues #87809, #99452, #91542). L'arme herite deja de la rotation Y
	# (lacet) via Personnage ; il ne lui manque que le tangage (rotation X)
	# de la camera Yeux, qu'on recopie ici. Sans cette recopie, la balle
	# partirait toujours horizontalement.
	var parent := get_parent()
	if parent != null:
		var yeux := parent.get_node_or_null("Yeux") as Node3D
		if yeux != null:
			rotation.x = yeux.rotation.x

func _unhandled_input(evenement: InputEvent) -> void:
	if not (evenement is InputEventMouseButton):
		return
	if not evenement.pressed:
		return
	if not _prete:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if evenement.button_index == MOUSE_BUTTON_RIGHT:
		_tirer()
	elif evenement.button_index == MOUSE_BUTTON_LEFT:
		_frapper()

func _frapper() -> void:
	if _cooldown_melee > 0.0:
		return
	var manager := get_tree().get_first_node_in_group(&"manager_proto")
	if manager == null:
		push_warning("arme_tir : manager_proto introuvable, coup ignore")
		return
	var direction := -global_transform.basis.z
	var origine := to_global(Vector3(0, 0, -decalage_avant))
	manager.call("frapper_melee", origine, direction, portee_melee, degat_melee)
	_cooldown_melee = cadence_melee

func _tirer() -> void:
	# BALLES SIMULEES EN DONNEES : on ne cree PAS de projectile physique
	# ici. On demande au manager_proto d'ajouter une balle a son tableau
	# _balles (position + direction). Le manager tick chaque balle
	# (avancement, collision segment vs carres) et instancie une peau
	# visuelle si l'observateur est dans le rayon. Consequence : la balle
	# tue les carres meme si le tireur bouge / regarde ailleurs. Si le
	# manager est absent (scene sans proto), le tir ne fait rien -- pas
	# de fallback silencieux, l'absence est visible.
	var manager := get_tree().get_first_node_in_group(&"manager_proto")
	if manager == null:
		push_warning("arme_tir : manager_proto introuvable, tir ignore")
		return
	var direction := -global_transform.basis.z
	var depart := to_global(Vector3(0, 0, -decalage_avant))
	manager.call("spawn_balle", depart, direction)
