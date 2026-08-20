extends Node3D

# BANC "test_ennemi" -- le geste le plus simple possible : viser un objet du
# groupe "destructible" a moins de `portee` metres et cliquer le detruit.
# Rien d'autre : pas de degats, pas d'animation, pas de retour visuel. Sert a
# valider le geste avant d'y accrocher quoi que ce soit -- pas destine a
# survivre tel quel dans le jeu.
#
# Entree : la camera ACTIVE de la scene (get_viewport().get_camera_3d(),
# jamais un chemin en dur -- la meme scene peut changer de camera). Sortie :
# libere le noeud vise.

@export var portee: float = 3.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_viser_et_detruire()

func _viser_et_detruire() -> void:
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
	if cible is Node and cible.is_in_group("destructible"):
		print("[test_ennemi] detruit : %s" % cible.name)
		cible.queue_free()
