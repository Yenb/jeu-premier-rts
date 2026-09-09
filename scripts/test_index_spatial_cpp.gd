extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_index_spatial_cpp.gd
#
# Verrouille la PARITE entre :
#   ORACLE -- scripts/monde.gd::deplacer_simple (mode structure_simple, chemin
#             GDScript), verite verrouillee par test_monde_structure_simple.gd.
#   CIBLE  -- extension_terrain/IndexSpatial::deplacer_lot (chemin C++,
#             utilise par banc_peuplement.gd quand deplacer_cpp=true).
#
# N=500 unites, 20 frames de mouvement pseudo-aleatoire mais deterministe.
# Apres chaque frame, on compare la CASE de chaque unite dans les deux
# indexes -- doivent etre identiques.
#
# Le test ne compare PAS choses_dans_rayon : le C++ ne l'implemente pas
# (structure cible du portage, pas ce chantier). Ce qui garantit la parite
# de choses_dans_rayon future : les cases sont identiques.

const Monde = preload("res://scripts/monde.gd")
const Objet = preload("res://scripts/objet.gd")
const Verif = preload("res://scripts/verif.gd")

const N := 500
const FRAMES := 20
const EXPOSANT := 4  # arete = 16

var verif := Verif.new()

func _init() -> void:
	if not ClassDB.class_exists("IndexSpatial"):
		printerr("ECHEC: classe C++ 'IndexSpatial' absente -- extension_terrain non chargee ?")
		quit(1)
		return
	_executer()
	if verif.echecs() == 0:
		print("OK: IndexSpatial C++ deplacer_lot rend la meme case par unite " +
			"que monde.gd::deplacer_simple GDScript, sur %d frames a N=%d" % [FRAMES, N])
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % verif.echecs())
		quit(1)

func _executer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	var positions := PackedVector3Array()
	positions.resize(N)
	var deltas := PackedVector3Array()
	deltas.resize(N)
	for i in range(N):
		positions[i] = Vector3(rng.randf_range(-100.0, 100.0), 0.0, rng.randf_range(-100.0, 100.0))
		var angle: float = rng.randf() * TAU
		deltas[i] = Vector3(cos(angle) * 0.8, 0.0, sin(angle) * 0.8)

	# ORACLE
	var monde := Monde.new()
	monde.structure_simple = true
	for i in range(N):
		var o := Objet.fabriquer("p%d" % i, "t", positions[i], {})
		monde.ajouter(o, "t", positions[i])
	var _r := monde.choses_dans_rayon(Vector3.ZERO, pow(2.0, EXPOSANT))

	# CIBLE
	var index_cpp = ClassDB.instantiate("IndexSpatial")
	index_cpp.configurer(N)
	index_cpp.ouvrir_niveau(EXPOSANT)

	index_cpp.deplacer_lot(positions)
	_comparer_cases(monde, index_cpp, 0)

	for f in range(1, FRAMES):
		for i in range(N):
			positions[i] += deltas[i]
			var entree = monde.par_id("p%d" % i)
			entree.chose.position = positions[i]
			monde.deplacer_simple(entree.chose)
		index_cpp.deplacer_lot(positions)
		_comparer_cases(monde, index_cpp, f)

func _comparer_cases(monde, index_cpp, frame: int) -> void:
	var cases_cpp: Dictionary = index_cpp.cases_pour_niveau(EXPOSANT)
	var case_de_cpp: Dictionary = {}
	for cle in cases_cpp:
		var ids_int: PackedInt32Array = cases_cpp[cle]
		for id_int in ids_int:
			case_de_cpp[int(id_int)] = cle
	var niveau_gd = monde._niveaux[EXPOSANT]
	var case_de_gd: Dictionary = niveau_gd.case_de
	for i in range(N):
		var id_str: String = "p%d" % i
		var case_gd = case_de_gd.get(id_str)
		var case_cpp = case_de_cpp.get(i)
		if case_gd != case_cpp:
			verif.v(false, "frame %d, unite %d : case GD=%s vs case CPP=%s" % [frame, i, str(case_gd), str(case_cpp)])
			return
