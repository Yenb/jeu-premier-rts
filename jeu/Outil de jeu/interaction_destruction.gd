extends Node3D

# BANC "test_ennemi" -- viser un objet du groupe "destructible" a moins de
# `portee` metres et cliquer le frappe. Si la cible sait encaisser un coup
# (methode subir_frappe, voir vie_ennemi.gd), le geste ne fait QUE ça --
# c'est la cible qui decide de sa propre destruction. Sinon, repli sur la
# destruction directe, pour tout ce qui n'a pas encore de vie.
#
# Entree : la camera ACTIVE de la scene (get_viewport().get_camera_3d(),
# jamais un chemin en dur -- la meme scene peut changer de camera).

@export var portee: float = 3.0
@export var degats_par_coup: float = 1.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_viser_et_frapper()

func _viser_et_frapper() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var origine := camera.global_position
	var direction := -camera.global_transform.basis.z
	var espace := get_world_3d().direct_space_state
	var requete := PhysicsRayQueryParameters3D.create(
		origine, origine + direction * portee)
	var resultat := espace.intersect_ray(requete)
	if resultat.is_empty():
		return
	var cible: Object = resultat.get("collider")
	if not (cible is Node and cible.is_in_group("destructible")):
		return
	if cible.has_method("subir_frappe"):
		cible.subir_frappe(degats_par_coup)
	else:
		print("[test_ennemi] detruit : %s" % cible.name)
		cible.queue_free()
