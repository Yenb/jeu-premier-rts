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

# MANGER EN CONTINU : tant que le clic gauche est maintenu, une bouchee
# toutes les CADENCE_MANGER secondes -- pas besoin de cliquer 30 fois.
const CADENCE_MANGER := 1.0
var _cooldown_manger: float = 0.0

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
	if _cooldown_manger > 0.0:
		_cooldown_manger = max(0.0, _cooldown_manger - delta)
	# Clic gauche maintenu + pas d'action de portage/creuser en cours -> tick
	# manger. Le premier clic passe par _frapper (event pressed) qui pose le
	# cooldown ; ici on relaie tant que le bouton reste enfonce.
	if _prete and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and _cooldown_manger <= 0.0:
		var manager := get_tree().get_first_node_in_group(&"manager_proto")
		if manager != null:
			var porte_pelle: bool = manager.has_method("porte_pelle") and manager.call("porte_pelle")
			var porte_cube: bool = manager.has_method("porteur_a_cube") and manager.call("porteur_a_cube")
			if not porte_pelle and not porte_cube and manager.has_method("manger_si_bloc_bleu_proche"):
				var dir := -global_transform.basis.z
				var org := to_global(Vector3(0, 0, -decalage_avant))
				if manager.call("manger_si_bloc_bleu_proche", org, dir):
					_cooldown_manger = CADENCE_MANGER
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
	# Touche E : toggle prendre/poser un outil portable (pelle, beche, futurs),
	# geste generique pilote par la visee (independant du clic gauche).
	if evenement is InputEventKey and evenement.pressed and not evenement.echo \
			and (evenement as InputEventKey).keycode == KEY_E:
		if _prete and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var manager := get_tree().get_first_node_in_group(&"manager_proto")
			if manager != null and manager.has_method("toggle_prendre_poser_e"):
				var direction := -global_transform.basis.z
				var origine := to_global(Vector3(0, 0, -decalage_avant))
				manager.call("toggle_prendre_poser_e", origine, direction)
		return
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
	# PRIORITE PORTAGE :
	# 1. porte pelle -> creuser (10 PV, 5 coups pour un sous-cube). Rater le
	#    raycast (viseur pas sur sol) ne doit RIEN faire d'autre -- surtout
	#    pas poser la pelle (elle occupe le meme slot _cube_porte qu'un
	#    sous-cube libre). Retour immediat quel que soit le resultat.
	# 1 bis. porte beche -> becher (10 coups -> transformation). Meme regle
	#    que la pelle : outil unique dans _cube_porte, retour immediat.
	# 2. porte cube libre -> pose (jamais la pelle, gardee au dessus).
	# 3. cube libre proche -> prend
	# 4. bloc bleu proche -> mange
	# 5. melee (comportement de base)
	if manager.has_method("porte_pelle") and manager.call("porte_pelle"):
		manager.call("creuser_avec_pelle", origine, direction)
		_cooldown_melee = cadence_melee
		return
	if manager.has_method("porte_beche") and manager.call("porte_beche"):
		manager.call("becher_avec_beche", origine, direction)
		_cooldown_melee = cadence_melee
		return
	if manager.has_method("porteur_a_cube") and manager.call("porteur_a_cube"):
		manager.call("porteur_poser")
		_cooldown_melee = cadence_melee
		return
	if manager.has_method("porteur_prendre_si_proche") \
			and manager.call("porteur_prendre_si_proche", origine, direction):
		_cooldown_melee = cadence_melee
		return
	# Bloc bleu pointe -> manger direct (independant de l'inspecteur).
	if manager.has_method("manger_si_bloc_bleu_proche") \
			and manager.call("manger_si_bloc_bleu_proche", origine, direction):
		_cooldown_melee = cadence_melee
		_cooldown_manger = CADENCE_MANGER
		return
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
