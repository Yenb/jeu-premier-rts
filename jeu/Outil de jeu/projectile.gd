extends Area3D

# BANC "test_ennemi" -- projectile : petite sphere jaune qui file dans une
# direction, inflige des degats au premier destructible touche, se
# detruit apres X secondes si elle ne touche rien.
#
# Area3D et pas RigidBody3D : on n'a pas besoin de gravite ni de physique
# realiste, juste d'un objet qui bouge et detecte les collisions. Plus
# simple, moins cher.

@export var vitesse: float = 30.0
@export var degats: float = 60.0
# APRES CE TEMPS, se detruit meme s'il n'a rien touche. A 30 m/s sur
# 5 s = 150 m parcourus, largement plus que l'emprise du banc (264 m
# c'est la carte, mais un projectile qui traverse tout, on le veut pas).
@export var duree_max: float = 5.0

var _direction: Vector3 = Vector3.ZERO
var _vecu: float = 0.0
# LE TIREUR, exclu des raycasts : sans ca, le raycast de _process
# touche IMMEDIATEMENT le corps du personnage (CharacterBody3D avec
# capsule) au premier frame et la balle s'auto-detruit avant meme
# de voler.
var _tireur: PhysicsBody3D = null

func _ready() -> void:
	body_entered.connect(_sur_impact)

func lancer(direction: Vector3, tireur: PhysicsBody3D = null) -> void:
	_direction = direction.normalized()
	_tireur = tireur

func _process(delta: float) -> void:
	# RAYCAST ENTRE L'ANCIENNE ET LA NOUVELLE POSITION -- evite le
	# tunneling. A 30 m/s * 16 ms = 0.5 m par frame, pile la largeur
	# d'un transporteur. Sans ce raycast, la balle peut SAUTER par
	# dessus une cible entre deux frames et rater completement.
	var depart := global_position
	var arrivee := depart + _direction * vitesse * delta
	var espace := get_world_3d().direct_space_state
	var requete := PhysicsRayQueryParameters3D.create(depart, arrivee)
	if _tireur != null:
		requete.exclude = [_tireur.get_rid()]
	var resultat := espace.intersect_ray(requete)
	if not resultat.is_empty():
		print("[proj] impact frame %.2fs : collider=%s (groupes=%s) a %v" % [
			_vecu, resultat.collider,
			resultat.collider.get_groups() if resultat.collider is Node else "-",
			resultat.position])
		global_position = resultat.position
		_sur_impact(resultat.collider)
		return
	global_position = arrivee
	_vecu += delta
	if _vecu >= duree_max:
		queue_free()

func _sur_impact(body: Node) -> void:
	# IGNORE LE TIREUR : sans ca, la balle spawn a 0.3 m devant la
	# camera entre en collision avec le CharacterBody3D du personnage
	# (Jolt fait detecter les CharacterBody3D par les Area3D), body_entered
	# fire, la balle meurt avant meme de voler.
	if body == _tireur:
		return
	if body.is_in_group("destructible") and body.has_method("subir_frappe"):
		body.subir_frappe(degats)
	# LE PROJECTILE MEURT AU PREMIER IMPACT, meme sur du terrain non
	# destructible -- une balle ne traverse pas.
	queue_free()
