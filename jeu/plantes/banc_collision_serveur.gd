extends SceneTree

# Banc de mesure comparatif :
# godot --headless --script jeu/plantes/banc_collision_serveur.gd
#
# COMPARE deux facons de poser N corps de collision statique, EN REGIME
# DYNAMIQUE : plateau etabli, puis K corps detruits+recrees par frame
# (taux de churn). Le premier banc mesurait un plateau fige, ce que les
# arbres du jeu ne sont pas -- ils naissent, changent de stade, meurent
# en continu.
#
# APPROCHE A : StaticBody3D + CollisionShape3D dans l'arbre de scene.
# APPROCHE B : PhysicsServer3D.body_create + body_add_shape brut, aucun
# noeud dans l'arbre.
#
# LA SHAPE EST PARTAGEE dans les deux approches.
#
# PROTOCOLE :
# - N ∈ {1500, 2827} : deux tailles pour croiser avec le churn, la seconde
#   etant le plafond calcule (2827 = arbres dans un rayon de 60 m a densite
#   maximale). La premiere permet de voir si l'anomalie du banc statique
#   precedent (5000 < 2827) venait de N, du churn, ou du script.
# - taux_churn ∈ {0, 0.1, 1, 5} % par frame. 0 = baseline plateau. 0.1 =
#   regime naturel calcule depuis les stades de verification.tscn (7
#   evenements par vie × N arbres / 1100 s + churn deplacement joueur).
#   1 et 5 = marge et stress test.
# - Pour chaque combinaison : 5 frames de chauffe (broadphase), puis 60
#   frames de mesure avec churn actif chaque frame.

const CHEMIN_BIBLIOTHEQUE := "res://jeu/terrain/bloc.tres"
const COTE := 40
const COUCHE := 0
const HAUTEUR_CYLINDRE := 14.0
const RAYON_CYLINDRE := 1.5
const RAYON_DISPERSION := 20.0
const FRAMES_CHAUFFE := 5
const FRAMES_MESURE := 60
const N_VALEURS := [2827]
const TAUX_CHURN := [0.001]
const REPETITIONS := 5

var _racine: Node3D
var _rng: RandomNumberGenerator

func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_tout.call_deferred()

func _tout() -> void:
	_racine = Node3D.new()
	get_root().add_child(_racine)
	var grille := _terrain_plat()
	_racine.add_child(grille)
	await process_frame

	# ISOLATION : par defaut lance les deux dans le meme processus, mais si
	# on passe --sb ou --ps en ligne de commande, on ne lance que l'un des
	# deux -- pour prouver qu'une interference dans le meme process cause
	# ou non la derive observee.
	var args := OS.get_cmdline_user_args()
	var mode_sb := args.has("--sb") or not (args.has("--sb") or args.has("--ps"))
	var mode_ps := args.has("--ps") or not (args.has("--sb") or args.has("--ps"))
	print("=== BANC COLLISION SERVEUR (regime dynamique, cycle destroy/wait/create) ===")
	print("mode: sb=%s ps=%s" % [mode_sb, mode_ps])
	print("N | churn %% | approche | rep | ms/frame")
	for n in N_VALEURS:
		for churn in TAUX_CHURN:
			if mode_sb:
				for rep in range(REPETITIONS):
					var a_ms := await _mesurer_static_body(n, churn)
					print("%d | %.1f | StaticBody3D | %d | %.3f" % [n, churn * 100.0, rep, a_ms])
			if mode_ps:
				for rep in range(REPETITIONS):
					var b_ms := await _mesurer_server_body(n, churn)
					print("%d | %.1f | PhysicsServer3D | %d | %.3f" % [n, churn * 100.0, rep, b_ms])
	_racine.queue_free()
	quit(0)

func _terrain_plat() -> GridMap:
	var g := GridMap.new()
	g.mesh_library = load(CHEMIN_BIBLIOTHEQUE) as MeshLibrary
	for x in range(COTE):
		for z in range(COTE):
			g.set_cell_item(Vector3i(x, COUCHE, z), 0)
	return g

func _position_aleatoire() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	var rayon := sqrt(_rng.randf()) * RAYON_DISPERSION
	return Vector3(cos(angle) * rayon, HAUTEUR_CYLINDRE * 0.5 + 1.0, sin(angle) * rayon)

func _mesurer_static_body(n: int, taux_churn: float) -> float:
	_rng.seed = 12345
	var forme := CylinderShape3D.new()
	forme.radius = RAYON_CYLINDRE
	forme.height = HAUTEUR_CYLINDRE
	var bodies: Array = []
	for i in range(n):
		bodies.append(_creer_static_body(forme))
	for _c in range(FRAMES_CHAUFFE):
		await physics_frame
	# COMPTEUR STRUCTUREL : StaticBody3D = enfant direct de _racine (moins la
	# GridMap). Un ecart avec N pendant la mesure signale que le nettoyage
	# entre repetitions est incomplet.
	var enfants_debut := _racine.get_child_count() - 1
	var k := int(round(float(n) * taux_churn))
	var total_ms := 0.0
	for _m in range(FRAMES_MESURE):
		var indices: Dictionary = {}
		for _e in range(k):
			var idx := _rng.randi_range(0, bodies.size() - 1)
			if indices.has(idx):
				continue
			(bodies[idx] as StaticBody3D).queue_free()
			indices[idx] = true
		await process_frame
		for idx in indices:
			bodies[idx] = _creer_static_body(forme)
		await physics_frame
		total_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var enfants_fin := _racine.get_child_count() - 1
	for body in bodies:
		if is_instance_valid(body):
			body.queue_free()
	print("  [debug SB] enfants_debut=%d enfants_fin=%d N=%d" % [enfants_debut, enfants_fin, n])
	for _n in range(20):
		await process_frame
	return total_ms / float(FRAMES_MESURE)

func _creer_static_body(forme: Shape3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = forme
	body.add_child(collision)
	body.position = _position_aleatoire()
	_racine.add_child(body)
	return body

func _mesurer_server_body(n: int, taux_churn: float) -> float:
	_rng.seed = 12345
	var forme_rid := PhysicsServer3D.cylinder_shape_create()
	PhysicsServer3D.shape_set_data(forme_rid, {"radius": RAYON_CYLINDRE, "height": HAUTEUR_CYLINDRE})
	var space_rid: RID = get_root().world_3d.space
	var bodies_rid: Array = []
	for i in range(n):
		bodies_rid.append(_creer_server_body(forme_rid, space_rid))
	for _c in range(FRAMES_CHAUFFE):
		await physics_frame
	var enfants_debut := _racine.get_child_count() - 1
	var rid_debut := bodies_rid.size()
	var k := int(round(float(n) * taux_churn))
	var total_ms := 0.0
	for _m in range(FRAMES_MESURE):
		var indices: Dictionary = {}
		for _e in range(k):
			var idx := _rng.randi_range(0, bodies_rid.size() - 1)
			if indices.has(idx):
				continue
			PhysicsServer3D.free_rid(bodies_rid[idx])
			indices[idx] = true
		await process_frame
		for idx in indices:
			bodies_rid[idx] = _creer_server_body(forme_rid, space_rid)
		await physics_frame
		total_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var enfants_fin := _racine.get_child_count() - 1
	var rid_fin := bodies_rid.size()
	for body_rid in bodies_rid:
		PhysicsServer3D.free_rid(body_rid)
	PhysicsServer3D.free_rid(forme_rid)
	print("  [debug PS] enfants_debut=%d enfants_fin=%d rid_debut=%d rid_fin=%d N=%d" % [
		enfants_debut, enfants_fin, rid_debut, rid_fin, n])
	# NETTOYAGE COMPLET entre repetitions.
	for _n in range(20):
		await process_frame
	return total_ms / float(FRAMES_MESURE)

func _creer_server_body(forme_rid: RID, space_rid: RID) -> RID:
	var body_rid := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body_rid, space_rid)
	PhysicsServer3D.body_add_shape(body_rid, forme_rid)
	PhysicsServer3D.body_set_state(body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM,
		Transform3D(Basis(), _position_aleatoire()))
	return body_rid
