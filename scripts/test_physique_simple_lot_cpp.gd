extends SceneTree

# Test headless :
# godot --headless --script scripts/test_physique_simple_lot_cpp.gd
#
# Verrouille la PARITE entre :
#   ORACLE -- jeu/bancs/banc_peuplement.gd::physique_et_buffer (GDScript entiere,
#             chemin verrouille par test_tick_fusionne, verite de reference).
#   CIBLE  -- extension_terrain/PhysiqueSimpleLot::pas_simple_lot (C++) + rejeu
#             GDScript sur `indices_a_repasser` (chemin utilise_cpp=true du
#             banc).
#
# Meme etat initial (positions, velocites, desiree, au_sol, slot, buffer), meme
# carte, meme delta/gravite. N frames, on compare positions/velocites/au_sol/
# buffer sur les DEUX cotes a l'epsilon flottant pres.
#
# La CIBLE n'appelle PAS l'errance : ce test verrouille la boucle physique
# seule, pas le tirage RNG (deja verrouille par test_tick_fusionne). Les
# colonnes "desiree" sont figees a une valeur non-nulle pour que le deplacement
# horizontal soit non-trivial et exerce les trois tests de sol.

const Verif = preload("res://scripts/verif.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")
const Banc = preload("res://jeu/bancs/banc_peuplement.gd")

const EPSILON := 0.0005

var _v := Verif.new()

func _init() -> void:
	if not ClassDB.class_exists("PhysiqueSimpleLot"):
		printerr("ECHEC: classe C++ 'PhysiqueSimpleLot' absente -- extension_terrain non chargee ?")
		quit(1)
		return
	_executer()
	if _v.echecs() == 0:
		print("OK: PhysiqueSimpleLot (C++) + rejeu GDScript sur les miss == physique_et_buffer GDScript, parite a %s pres, 30 frames, 200 agents" % str(EPSILON))
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

	# Etat initial deterministe -- meme geometrie que test_tick_fusionne, sans
	# l'errance : desiree gele a une valeur non-triviale pour exercer les tests
	# sol.
	var positions_init := PackedVector3Array()
	positions_init.resize(n)
	var velocites_init := PackedVector3Array()
	velocites_init.resize(n)
	var desirees_init := PackedVector3Array()
	desirees_init.resize(n)
	var au_sols_init := PackedByteArray()
	au_sols_init.resize(n)
	var slots_init := PackedInt32Array()
	slots_init.resize(n)
	for i in range(n):
		var x: float = float(i % 20) - 10.0 + 0.5
		@warning_ignore("integer_division")
		var z: float = float(i / 20) - 10.0 + 0.5
		var y: float = 14.4 if (i % 3) == 0 else 20.0
		positions_init[i] = Vector3(x, y, z)
		velocites_init[i] = Vector3.ZERO
		var angle: float = float(i) * 0.31415
		desirees_init[i] = Vector3(cos(angle) * 1.5, 0.0, sin(angle) * 1.5)
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

	# --- ORACLE (GDScript) ---
	var cols_gd := _cloner_cols(positions_init, velocites_init, desirees_init, au_sols_init, slots_init)
	var buffer_gd: PackedFloat32Array = buffer_init.duplicate()
	for _f in range(frames):
		buffer_gd = Banc.physique_et_buffer(cols_gd, buffer_gd, n, gravite, delta, carte)

	# --- CIBLE (C++ + rejeu GDScript sur indices_a_repasser) ---
	var cpp = ClassDB.instantiate("PhysiqueSimpleLot")
	var cols_cpp := _cloner_cols(positions_init, velocites_init, desirees_init, au_sols_init, slots_init)
	var buffer_cpp: PackedFloat32Array = buffer_init.duplicate()
	var cote: float = 2.0
	if "cote" in carte:
		cote = float(carte.cote)
	var demi_cote: int = int(carte.demi_cote)
	var total_hits: int = 0
	for _f in range(frames):
		var entree := {
			"position": cols_cpp.position,
			"velocite": cols_cpp.velocite,
			"desiree": cols_cpp.desiree,
			"au_sol": cols_cpp.au_sol,
			"slot": cols_cpp.slot,
			"buffer": buffer_cpp,
			"count": n,
			"gravite": gravite,
			"delta": delta,
			"vitesse_terminale": 55.0,
			"table": carte.table_sommet(),
			"demi_cote": demi_cote,
			"cote": cote,
		}
		var sortie: Dictionary = cpp.pas_simple_lot(entree)
		cols_cpp.position = sortie.position
		cols_cpp.velocite = sortie.velocite
		cols_cpp.au_sol = sortie.au_sol
		buffer_cpp = sortie.buffer
		var indices: PackedInt32Array = sortie.indices_a_repasser
		total_hits += n - indices.size()
		if not indices.is_empty():
			buffer_cpp = Banc.physique_et_buffer_indices(cols_cpp, buffer_cpp, indices, gravite, delta, carte)

	_v.v(total_hits > 0,
		"le C++ doit avoir traite au moins UN indice en happy path (table chaude) sur 30 frames -- sinon la boucle native n'est pas exercee (hits=%d)" % total_hits)
	_comparer_vec3(cols_gd.position, cols_cpp.position, "position")
	_comparer_vec3(cols_gd.velocite, cols_cpp.velocite, "velocite")
	_comparer_byte(cols_gd.au_sol, cols_cpp.au_sol, "au_sol")
	_comparer_buffer(buffer_gd, buffer_cpp)

func _cloner_cols(pos: PackedVector3Array, vel: PackedVector3Array, des: PackedVector3Array, aus: PackedByteArray, slot: PackedInt32Array) -> Dictionary:
	return {
		"position": pos.duplicate(),
		"velocite": vel.duplicate(),
		"desiree": des.duplicate(),
		"au_sol": aus.duplicate(),
		"slot": slot.duplicate(),
	}

func _comparer_vec3(a: PackedVector3Array, b: PackedVector3Array, nom: String) -> void:
	_v.v(a.size() == b.size(), "%s : tailles differentes (%d vs %d)" % [nom, a.size(), b.size()])
	var i: int = 0
	while i < a.size():
		var d: Vector3 = a[i] - b[i]
		var pire: float = maxf(maxf(absf(d.x), absf(d.y)), absf(d.z))
		if pire > EPSILON:
			_v.v(false, "%s[%d] : GD=%s CPP=%s, ecart=%f > epsilon %f" % [nom, i, str(a[i]), str(b[i]), pire, EPSILON])
			return
		i += 1

func _comparer_byte(a: PackedByteArray, b: PackedByteArray, nom: String) -> void:
	_v.v(a.size() == b.size(), "%s : tailles differentes (%d vs %d)" % [nom, a.size(), b.size()])
	var i: int = 0
	while i < a.size():
		if a[i] != b[i]:
			_v.v(false, "%s[%d] : GD=%d CPP=%d" % [nom, i, a[i], b[i]])
			return
		i += 1

func _comparer_buffer(a: PackedFloat32Array, b: PackedFloat32Array) -> void:
	_v.v(a.size() == b.size(), "buffer : tailles differentes (%d vs %d)" % [a.size(), b.size()])
	var i: int = 0
	while i < a.size():
		if absf(a[i] - b[i]) > EPSILON:
			_v.v(false, "buffer[%d] : GD=%f CPP=%f, ecart=%f > epsilon %f" % [i, a[i], b[i], absf(a[i] - b[i]), EPSILON])
			return
		i += 1
