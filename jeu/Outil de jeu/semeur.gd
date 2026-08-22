extends Node3D

# BANC "test_ennemi2 Mother box" -- SEMEUR GENERIQUE. Au _ready, tire N
# positions aleatoires dans un disque autour de sa propre position, fait un
# raycast vertical sur chacune pour poser le nouveau nœud sur le sol, et
# instancie `scene_a_semer` a cet endroit. Ne connait AUCUN nom d'espece,
# reutilisable pour herbe, lichen, ou tout futur objet auto-reproducteur.
#
# S'AUTO-FREE apres avoir seme -- il ne recree jamais, ne surveille rien.
# Un semis initial, point. La population evolue ensuite par ses propres
# mecanismes de reproduction (cube_herbe.gd, cube_lichen.gd).
#
# ATTEND LA PHYSIQUE avant de semer : 5 physics_frame pour que le GridMap
# ait enregistre ses shapes, sinon le raycast rend vide et rien ne se pose.
# Piège deja paye pour prechauffeur_herbe.gd, meme fix.
#
# TIRAGE UNIFORME SUR DISQUE : angle uniforme sur [0, TAU), rayon = sqrt
# d'un uniforme sur [0, 1] fois le rayon max, sinon les tirages se
# concentrent au centre.

@export var scene_a_semer: PackedScene = null
@export var nombre: int = 500
@export var rayon_dispersion: float = 100.0
# BANDE D'ALTITUDE CONSERVATIVE PAR DEFAUT : les cartes typiques du jeu ont
# un sol autour de y=0 a y=20. Un plafond a 30 rejette les sommets de murs
# et limites du GridMap, qui montent souvent bien plus haut. A remonter
# explicitement dans la scene si le vrai relief depasse.
@export var y_min: float = 0.0
@export var y_max: float = 30.0
@export var seed_rng: int = 20261123

func _ready() -> void:
	for _i in range(5):
		await get_tree().physics_frame
	_semer()
	queue_free()

func _semer() -> void:
	if scene_a_semer == null:
		push_warning("semeur.gd : scene_a_semer non renseignee, rien seme")
		return
	var accueil := get_parent()
	if accueil == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_rng
	for _i in range(nombre):
		var angle := rng.randf_range(0.0, TAU)
		var rayon := sqrt(rng.randf()) * rayon_dispersion
		var candidate := global_position + Vector3(cos(angle) * rayon, 0.0, sin(angle) * rayon)
		var y_sol: Variant = _hauteur_sol_sous(candidate)
		if y_sol == null:
			continue
		if float(y_sol) < y_min or float(y_sol) > y_max:
			continue
		var noeud := scene_a_semer.instantiate() as Node3D
		# TRANSMET LA BANDE D'ALTITUDE aux cubes semes : sans ca, chaque cube
		# retomberait sur ses propres defauts (largement ouverts, 1000 m) et
		# pondrait ailleurs que dans la bande voulue -- les pontes hors bande
		# reapparaitraient au sommet des murs du GridMap.
		if "y_min" in noeud:
			noeud.set("y_min", y_min)
		if "y_max" in noeud:
			noeud.set("y_max", y_max)
		# POSITION POSEE AVANT add_child : sinon _ready du cube s'execute
		# avec global_position=(0,0,0), inscrit au champ scalaire a cette
		# case, tous les cubes s'accumulent sur (0,0) tandis que leur vraie
		# position est ailleurs -- aucun cube ne trouve de voisin la ou il
		# est, aucun ne sature, explosion.
		noeud.position = Vector3(candidate.x, float(y_sol), candidate.z)
		accueil.add_child(noeud)

func _hauteur_sol_sous(point: Vector3) -> Variant:
	# RAYCAST RESTREINT AU SOL : le raycast peut aussi toucher n'importe
	# quel corps physique dans la scene -- notamment la Hitbox du
	# personnage, qui pose le nouveau cube A SA HAUTEUR au lieu du sol,
	# creant les cubes flottants "dans le ciel". On rejette tout collider
	# qui n'est pas un GridMap : seul le sol doit compter pour poser un
	# semis. Si la position tombe pile sous le personnage, on renonce
	# silencieusement (perte marginale sur 500 tirages).
	var espace := get_world_3d().direct_space_state
	if espace == null:
		return null
	var depart := point + Vector3(0.0, 1000.0, 0.0)
	var arrivee := point + Vector3(0.0, -1000.0, 0.0)
	var requete := PhysicsRayQueryParameters3D.create(depart, arrivee)
	var frappe := espace.intersect_ray(requete)
	if frappe.is_empty():
		return null
	if not (frappe.collider is GridMap):
		return null
	return (frappe.position as Vector3).y
