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

const BalleScene := preload("res://jeu/Proto/balle_violette.tscn")

# LA FACE AVANT DU CUBE : cube de 0.3 m, moitie = 0.15 m sur -Z local.
@export var decalage_avant: float = 0.15

# LE PREMIER CLIC POSE mouse_mode=CAPTURED (voir personnage.gd) et
# personnage.gd ne consomme PAS l'evenement -- l'ordre d'appel de
# _unhandled_input entre noeuds n'est pas garanti. Sans ce flag, si
# arme_tir tourne apres personnage.gd, le premier clic tire aussi (une
# balle part au geste qui sert a rentrer en jeu). Le flag ne passe a
# vrai qu'a la frame SUIVANT la premiere capture vue par _process --
# le premier clic est donc toujours consomme par la capture.
var _prete: bool = false

func _process(_delta: float) -> void:
	# APRES UN ECHAP (mode=VISIBLE), le prochain clic recapture -- il ne
	# doit pas tirer. Sans ce reset, _prete reste true entre deux captures
	# et un clic de recapture tire par accident. La regle est la meme
	# qu'au demarrage : une frame de latence apres chaque passage a
	# CAPTURED.
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_prete = true
	else:
		_prete = false
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
	if evenement.button_index != MOUSE_BUTTON_LEFT:
		return
	if not evenement.pressed:
		return
	if not _prete:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	_tirer()

func _tirer() -> void:
	var direction := -global_transform.basis.z
	var balle := BalleScene.instantiate() as Node3D
	# ATTACHE A LA RACINE, pas au parent : sinon la balle suit le tireur.
	var accueil: Node = get_owner()
	if accueil == null:
		accueil = get_tree().current_scene
	if accueil == null:
		accueil = get_parent()
	accueil.add_child(balle)
	balle.global_position = to_global(Vector3(0, 0, -decalage_avant))
	# TIREUR = le CharacterBody3D auquel l'arme est attachee, exclu des
	# raycasts (voir en-tete).
	var tireur := get_parent_node_3d() as PhysicsBody3D
	if tireur == null:
		# L'arme peut etre attachee a un enfant intermediaire ; remonter
		# jusqu'au premier PhysicsBody3D.
		var noeud: Node = get_parent()
		while noeud != null and not (noeud is PhysicsBody3D):
			noeud = noeud.get_parent()
		tireur = noeud as PhysicsBody3D
	balle.lancer(direction, tireur)
