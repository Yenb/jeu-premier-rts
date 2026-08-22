extends Node3D

# BANC "test_ennemi2 Mother box" -- LE PRECHAUFFEUR D'HERBE. Simule N
# secondes de croissance en DONNEES PURES (positions, ages, voisins dans
# des Arrays), puis instancie les survivants en une seule passe, chacun
# avec son age deja ecoule.
#
# POURQUOI EN DONNEES ? Faire tourner N secondes en INSTANCIANT chaque
# nouveau cube pendant la simu paierait pour rien : rendu, physique, timers,
# arbre de scene, garbage. Personne ne regarde. La logique de croissance
# vit dans quelques floats par brin -- rien de plus -- et c'est ce qui
# la rend rapide meme sur N secondes a l'echelle du tapis.
# Le raycast d'altitude reste physique (l'espace physique existe des le
# premier physics_frame, meme sans nodes visibles) : quelques microsecondes
# par appel, negligeable devant l'economie de scene.
#
# COMPTEUR EVENEMENTIEL : chaque brin porte 'voisins' maintenu aux
# evenements (naissance et mort dans son rayon), jamais recalcule par
# balayage a chaque pas. Reflete le pattern des cubes en jeu, sans passer
# par le champ scalaire (la simu vit dans une Array plate, l'inscription
# dans un champ serait un pont inutile pendant le prechauffage).
#
# LES GRAINES : les enfants Marker3D (ou tout Node3D) DE CE NOEUD, plus
# N positions aleatoires si `nombre_graines_aleatoires > 0`. Chaque
# graine subit son propre raycast d'altitude -- celles hors sol sont
# ecartees.
#
# LES PARAMETRES DE SIMU DOIVENT MATCHER cube_herbe.gd -- ils sont dupliques
# ici par choix : chaque cube porte ses propres @export, le prechauffeur
# aussi. Regle-les dans les DEUX endroits si tu changes le gameplay.
#
# ATTENTION AU CHAINAGE : ce noeud est retire (queue_free) apres avoir pose
# les cubes. Il ne re-prechauffe jamais.

const GROUPE := "herbe"

@export var duree_prechauffage: float = 60.0
@export var pas_simu: float = 1.0

@export var duree_gestation: float = 10.0
@export var duree_vie: float = 60.0
@export var rayon_voisinage: float = 0.40
@export var seuil_voisins: int = 33
@export var rayon_pose: float = 0.10
@export var y_min: float = -1000.0
@export var y_max: float = 1000.0

@export var seed_rng: int = 20261121
@export var nombre_graines_aleatoires: int = 0
@export var rayon_dispersion_graines: float = 0.0

func _ready() -> void:
	for _i in range(5):
		await get_tree().physics_frame
	_simuler_puis_poser()

func _simuler_puis_poser() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_rng

	var graines := _positions_des_enfants()
	graines.append_array(_positions_aleatoires(rng))
	if graines.is_empty():
		push_warning("prechauffeur_herbe.gd : ni Marker3D enfant ni graine aleatoire, rien a prechauffer")
		queue_free()
		return

	# INITIALISATION DES BRINS ET DE LEUR COMPTEUR DE VOISINS. Chaque graine
	# pose au sol devient un brin. Une fois toutes posees, on incremente les
	# compteurs mutuellement pour les graines qui tombent dans le rayon
	# l'une de l'autre -- balayage une seule fois, jamais rejoue.
	var brins: Array = []
	for pos in graines:
		var y_sol: Variant = _hauteur_sol_sous(pos)
		if y_sol == null:
			continue
		var pos_au_sol := Vector3(pos.x, float(y_sol), pos.z)
		brins.append({"pos": pos_au_sol, "age": 0.0, "voisins": 0, "ecoule": 0.0})
	for i in range(brins.size()):
		for j in range(i + 1, brins.size()):
			if (brins[i].pos as Vector3).distance_to(brins[j].pos) <= rayon_voisinage:
				brins[i]["voisins"] = int(brins[i].voisins) + 1
				brins[j]["voisins"] = int(brins[j].voisins) + 1

	if brins.is_empty():
		queue_free()
		return

	var pas_restants: int = int(ceil(duree_prechauffage / pas_simu))
	for _n in range(pas_restants):
		_avancer_un_pas(brins, rng, pas_simu)

	_poser_les_survivants(brins)
	queue_free()

func _avancer_un_pas(brins: Array, rng: RandomNumberGenerator, dt: float) -> void:
	# COMPTEUR EVENEMENTIEL : chaque brin porte 'voisins' maintenu aux
	# evenements. La saturation est simplement voisins >= seuil, pas un tag.

	# 1. VIEILLISSEMENT + SELECTION DES MORTS.
	var morts_index: Array = []
	for i in range(brins.size()):
		brins[i]["age"] = float(brins[i].age) + dt
		if float(brins[i].age) >= duree_vie:
			morts_index.append(i)

	# 2. RETRAIT DES MORTS + PROPAGATION AUX VOISINS.
	morts_index.sort()
	morts_index.reverse()
	for i in morts_index:
		var pos_mort: Vector3 = brins[i].pos
		brins.remove_at(i)
		for j in range(brins.size()):
			if pos_mort.distance_to(brins[j].pos) <= rayon_voisinage:
				brins[j]["voisins"] = maxi(0, int(brins[j].voisins) - 1)

	# 3. TENTATIVE DE PONTE POUR LES NON-SATUREES. Snapshot brins.size()
	# avant la boucle : les nouveaux nes de CE pas ne pondent pas eux-memes
	# ce pas.
	var taille_avant := brins.size()
	for i in range(taille_avant):
		if int(brins[i].voisins) >= seuil_voisins:
			continue
		brins[i]["ecoule"] = float(brins[i].ecoule) + dt
		if float(brins[i].ecoule) < duree_gestation:
			continue

		brins[i]["ecoule"] = 0.0

		var angle := rng.randf_range(0.0, TAU)
		var candidate := (brins[i].pos as Vector3) + Vector3(cos(angle) * rayon_pose, 0.0, sin(angle) * rayon_pose)
		var y_sol: Variant = _hauteur_sol_sous(candidate)
		if y_sol == null:
			continue
		if float(y_sol) < y_min or float(y_sol) > y_max:
			continue

		# NAISSANCE : compte les voisins de la nouvelle position par
		# balayage une fois, puis incremente le compteur de chacun.
		var pos_bebe := Vector3(candidate.x, float(y_sol), candidate.z)
		var voisins_bebe := 0
		for j in range(brins.size()):
			if pos_bebe.distance_to(brins[j].pos) <= rayon_voisinage:
				voisins_bebe += 1
				brins[j]["voisins"] = int(brins[j].voisins) + 1
		brins.append({
			"pos": pos_bebe,
			"age": 0.0,
			"voisins": voisins_bebe,
			"ecoule": 0.0,
		})

func _poser_les_survivants(brins: Array) -> void:
	# CANEVAS DE BASE (voir CLAUDE.md § « Populations massives ») : on
	# n'instancie AUCUN Node par brin. Les brins survivants sont pousses
	# dans le ManagerHerbe existant, qui les prend en charge dans son
	# tableau plat -- meme structure que les brins qu'il gere deja lui-
	# meme. La transition est invisible pour le reste du systeme.
	var manager := get_tree().get_first_node_in_group("manager_herbe")
	if manager == null:
		push_error("prechauffeur_herbe.gd : ManagerHerbe absent, brins prechauffes ignores")
		return
	for brin in brins:
		manager.ajouter_avec_age(brin.pos as Vector3, float(brin.age))

func _positions_des_enfants() -> Array:
	var positions: Array = []
	for enfant in get_children():
		if enfant is Node3D:
			positions.append((enfant as Node3D).global_position)
	return positions

# TIRAGE UNIFORME SUR DISQUE : angle uniforme sur [0, TAU), rayon = sqrt
# d'un uniforme sur [0, 1] fois le rayon max -- sinon les tirages se
# concentrent au centre.
func _positions_aleatoires(rng: RandomNumberGenerator) -> Array:
	var positions: Array = []
	if nombre_graines_aleatoires <= 0 or rayon_dispersion_graines <= 0.0:
		return positions
	for _i in range(nombre_graines_aleatoires):
		var angle := rng.randf_range(0.0, TAU)
		var rayon := sqrt(rng.randf()) * rayon_dispersion_graines
		positions.append(global_position + Vector3(cos(angle) * rayon, 0.0, sin(angle) * rayon))
	return positions

func _hauteur_sol_sous(point: Vector3) -> Variant:
	# Raycast restreint au GridMap (voir semeur.gd, meme piege).
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
