extends Node3D

# BANC "test_ennemi" -- l'arme a distance du joueur. Touche F fait
# apparaitre un projectile jaune depuis la camera, qui file dans la
# direction visee a `vitesse_projectile` m/s. Le projectile lui-meme
# porte les degats et la duree de vie -- voir projectile.gd.
#
# TOUCHE F et pas clic droit : le clic droit passe par un autre chemin
# d'input qui ne remontait pas jusqu'a nous, F est direct et sans
# competition. Cheat de test, pas d'ergonomie a chercher.

const ProjectileScene := preload("res://jeu/Outil de jeu/projectile.tscn")

# LE PROJECTILE APPARAIT `decalage_depart` metres DEVANT la camera :
# sans ca, il pourrait toucher le corps du personnage tireur. 0.3 m
# suffit (rayon capsule 0.25 m), et evite qu'un tir a courte portee
# voit la balle deja apparue DERRIERE la cible.
@export var decalage_depart: float = 0.3

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F:
		_tirer()

func _tirer() -> void:
	var personnage := get_parent()
	var camera := personnage.get_node_or_null("Yeux") as Camera3D
	if camera == null:
		print("[arme] ROUGE : Yeux introuvable sur ", personnage.name)
		return
	var direction := -camera.global_transform.basis.z
	print("[arme] TIR : camera_pos=%v, direction=%v, personnage_pos=%v" % [
		camera.global_position, direction, personnage.global_position])
	var projectile := ProjectileScene.instantiate() as Node3D
	# ATTACHE A LA RACINE DE LA SCENE (get_owner), pas au personnage :
	# sinon le projectile suit le tireur s'il bouge, il devient un
	# satellite. get_owner est plus robuste que get_tree().current_scene
	# qui peut etre null en headless ou en scene instanciee a la main.
	var accueil: Node = get_owner()
	if accueil == null:
		accueil = get_tree().current_scene
	if accueil == null:
		accueil = get_parent()
	accueil.add_child(projectile)
	projectile.global_position = camera.global_position + direction * decalage_depart
	# LE PERSONNAGE (parent de l'arme) est passe au projectile pour etre
	# exclu des raycasts -- sinon le corps du tireur est le premier
	# obstacle et la balle meurt au premier frame.
	var tireur := get_parent() as PhysicsBody3D
	projectile.lancer(direction, tireur)
