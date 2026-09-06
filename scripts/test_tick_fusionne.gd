extends SceneTree

# Test headless :
# godot --headless --script scripts/test_tick_fusionne.gd
#
# Verrouille la PARITE bit-a-bit entre :
#   Chemin A -- 3 passes (l'ancien _physics_process) :
#     errance ANCIENNE (recalcule desiree CHAQUE frame)
#     -> Mouvement.pas_simple_lot
#     -> ecriture buffer.
#   Chemin B -- 2 passes (round 11 revise) :
#     errance REVISEE (recalcule desiree UNIQUEMENT a l'expiration de l'horloge)
#     -> Banc.physique_et_buffer (fusion physique + buffer).
#
# Precondition B : desiree_init = direction * vitesse au spawn (sans quoi frame
# 1 partirait de Vector3.ZERO au lieu de la direction tiree au spawn).
# Le banc l'a integree dans _remplir_colonnes_depuis_individus.
#
# 200 agents, 30 frames a dt=1/60. Meme graine RNG.

const Verif = preload("res://scripts/verif.gd")
const Mouvement = preload("res://scripts/mouvement_kinematic.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const Banc = preload("res://jeu/bancs/banc_peuplement.gd")

var _v := Verif.new()


func _init() -> void:
	_executer()
	if _v.echecs() == 0:
		print("OK: 3-passes vs 2-passes (fusion physique+buffer) -- parite bit-a-bit, 30 frames, 200 agents")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)


func _executer() -> void:
	var carte: Resource = CarteTerrain.new()
	var delta: float = 1.0 / 60.0
	var gravite: float = 18.0
	var n: int = 200
	var frames: int = 30
	var seed: int = 20260906

	var rng_init := RandomNumberGenerator.new()
	rng_init.seed = seed
	var positions_init := PackedVector3Array()
	positions_init.resize(n)
	var velocites_init := PackedVector3Array()
	velocites_init.resize(n)
	var directions_init := PackedVector3Array()
	directions_init.resize(n)
	var cap_horloges_init := PackedFloat32Array()
	cap_horloges_init.resize(n)
	var vitesses_init := PackedFloat32Array()
	vitesses_init.resize(n)
	var desirees_init := PackedVector3Array()
	desirees_init.resize(n)
	var au_sols_init := PackedByteArray()
	au_sols_init.resize(n)
	var slots_init := PackedInt32Array()
	slots_init.resize(n)
	for i in range(n):
		var x: float = float(i % 20) - 10.0 + 0.5
		var z: float = float(i / 20) - 10.0 + 0.5
		var y: float = 14.4 if (i % 3) == 0 else 20.0
		positions_init[i] = Vector3(x, y, z)
		velocites_init[i] = Vector3.ZERO
		var angle: float = rng_init.randf() * TAU
		directions_init[i] = Vector3(cos(angle), 0.0, sin(angle))
		cap_horloges_init[i] = rng_init.randf_range(3.0, 8.0)
		vitesses_init[i] = 1.5
		desirees_init[i] = directions_init[i] * vitesses_init[i]
		au_sols_init[i] = 0
		slots_init[i] = i

	var taille_buffer: int = n * 12
	var buffer_init := PackedFloat32Array()
	buffer_init.resize(taille_buffer)
	for k in range(n):
		var base: int = k * 12
		buffer_init[base + 0] = 1.0
		buffer_init[base + 5] = 1.0
		buffer_init[base + 10] = 1.0

	# CHEMIN A -- 3 passes.
	var cols_a := _cloner_cols(positions_init, velocites_init, desirees_init, directions_init, cap_horloges_init, vitesses_init, au_sols_init, slots_init)
	var buffer_a: PackedFloat32Array = buffer_init.duplicate()
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = seed + 1
	for _f in range(frames):
		_errance_ancienne(cols_a, n, rng_a, delta)
		Mouvement.pas_simple_lot(cols_a, n, gravite, delta, carte)
		buffer_a = _ecrire_buffer(cols_a, buffer_a, n)

	# CHEMIN B -- 2 passes (errance revisee + physique_et_buffer).
	var cols_b := _cloner_cols(positions_init, velocites_init, desirees_init, directions_init, cap_horloges_init, vitesses_init, au_sols_init, slots_init)
	var buffer_b: PackedFloat32Array = buffer_init.duplicate()
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = seed + 1
	for _f in range(frames):
		_errance_revisee(cols_b, n, rng_b, delta)
		buffer_b = Banc.physique_et_buffer(cols_b, buffer_b, n, gravite, delta, carte)

	_comparer_col_vec3(cols_a.position, cols_b.position, "position")
	_comparer_col_vec3(cols_a.velocite, cols_b.velocite, "velocite")
	_comparer_col_vec3(cols_a.desiree, cols_b.desiree, "desiree")
	_comparer_col_vec3(cols_a.direction, cols_b.direction, "direction")
	_comparer_col_float(cols_a.cap_horloge, cols_b.cap_horloge, "cap_horloge")
	_comparer_col_byte(cols_a.au_sol, cols_b.au_sol, "au_sol")
	_comparer_buffer(buffer_a, buffer_b)


func _cloner_cols(pos, vel, des, dir, cap, vit, aus, slot) -> Dictionary:
	return {
		"position": pos.duplicate(),
		"velocite": vel.duplicate(),
		"desiree": des.duplicate(),
		"direction": dir.duplicate(),
		"cap_horloge": cap.duplicate(),
		"vitesse": vit.duplicate(),
		"au_sol": aus.duplicate(),
		"slot": slot.duplicate(),
	}


# Errance ANCIENNE : recalcule desiree CHAQUE frame (comportement pre-round 11).
func _errance_ancienne(cols: Dictionary, count: int, rng: RandomNumberGenerator, delta: float) -> void:
	var directions: PackedVector3Array = cols.direction
	var cap_horloges: PackedFloat32Array = cols.cap_horloge
	var vitesses: PackedFloat32Array = cols.vitesse
	var desirees: PackedVector3Array = cols.desiree
	var i: int = 0
	while i < count:
		var horloge: float = cap_horloges[i] - delta
		var direction: Vector3 = directions[i]
		if horloge <= 0.0:
			var angle: float = rng.randf() * TAU
			direction = Vector3(cos(angle), 0.0, sin(angle))
			directions[i] = direction
			horloge = rng.randf_range(3.0, 8.0)
		cap_horloges[i] = horloge
		desirees[i] = direction * vitesses[i]
		i += 1
	cols.direction = directions
	cols.cap_horloge = cap_horloges
	cols.desiree = desirees


# Errance REVISEE round 11 : desiree recalcule UNIQUEMENT a l'expiration.
# Doit rester ALIGNE avec la passe errance dans banc_peuplement._physics_process.
func _errance_revisee(cols: Dictionary, count: int, rng: RandomNumberGenerator, delta: float) -> void:
	var directions: PackedVector3Array = cols.direction
	var cap_horloges: PackedFloat32Array = cols.cap_horloge
	var vitesses: PackedFloat32Array = cols.vitesse
	var desirees: PackedVector3Array = cols.desiree
	var repack_desiree: bool = false
	var repack_direction: bool = false
	var i: int = 0
	while i < count:
		var horloge: float = cap_horloges[i] - delta
		if horloge <= 0.0:
			var angle: float = rng.randf() * TAU
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			directions[i] = direction
			repack_direction = true
			horloge = rng.randf_range(3.0, 8.0)
			desirees[i] = direction * vitesses[i]
			repack_desiree = true
		cap_horloges[i] = horloge
		i += 1
	cols.cap_horloge = cap_horloges
	if repack_direction:
		cols.direction = directions
	if repack_desiree:
		cols.desiree = desirees


func _ecrire_buffer(cols: Dictionary, buffer: PackedFloat32Array, count: int) -> PackedFloat32Array:
	var positions: PackedVector3Array = cols.position
	var slots: PackedInt32Array = cols.slot
	var i: int = 0
	while i < count:
		var slot: int = slots[i]
		if slot >= 0:
			var base: int = slot * 12
			var pos: Vector3 = positions[i]
			buffer[base + 3] = pos.x
			buffer[base + 7] = pos.y
			buffer[base + 11] = pos.z
		i += 1
	return buffer


func _comparer_col_vec3(a: PackedVector3Array, b: PackedVector3Array, nom: String) -> void:
	var divergents: int = 0
	for i in range(a.size()):
		if a[i] != b[i]:
			divergents += 1
	_v.v(divergents == 0, "colonne '%s' : %d/%d divergent" % [nom, divergents, a.size()])


func _comparer_col_float(a: PackedFloat32Array, b: PackedFloat32Array, nom: String) -> void:
	var divergents: int = 0
	for i in range(a.size()):
		if a[i] != b[i]:
			divergents += 1
	_v.v(divergents == 0, "colonne '%s' : %d/%d divergent" % [nom, divergents, a.size()])


func _comparer_col_byte(a: PackedByteArray, b: PackedByteArray, nom: String) -> void:
	var divergents: int = 0
	for i in range(a.size()):
		if a[i] != b[i]:
			divergents += 1
	_v.v(divergents == 0, "colonne '%s' : %d/%d divergent" % [nom, divergents, a.size()])


func _comparer_buffer(a: PackedFloat32Array, b: PackedFloat32Array) -> void:
	var divergents: int = 0
	for i in range(a.size()):
		if a[i] != b[i]:
			divergents += 1
	_v.v(divergents == 0, "buffer : %d/%d floats divergent" % [divergents, a.size()])
