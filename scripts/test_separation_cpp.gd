extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_separation_cpp.gd
#
# Verrouille la PARITE entre :
#   ORACLE -- calcul de reference GDScript naif O(N^2) : pour chaque unite,
#             parcourt TOUTES les autres, cumule diff * (rayon - d) / d pour
#             chaque voisin dans rayon, puis normalise en direction unitaire
#             horizontale (Y=0). Meme formule que le C++, appliquee sans
#             indexation spatiale -- ROLLBACK theorique si le C++ regressait.
#   CIBLE  -- extension_terrain/IndexSpatial::separation_lot (chemin C++,
#             lit les cases voisines touchees par rayon dans l'index deja
#             tenu par deplacer_lot).
#
# N=200 unites reparties aleatoirement dans une zone de 40x40 (densite proche
# du regime de peuplement). rayon=2.0 (defaut du banc, inferieur a l'arete
# 2^EXPOSANT=16 comme exige par le contrat de separation_lot). Une frame.
#
# Egalite de vecteur a vecteur avec tolerance : l'arithmetique flottante
# somme les contributions dans un ordre different selon la case dans laquelle
# tombe chaque voisin, puis prend une racine, ce qui empeche la parite bit a
# bit -- consequence acceptee : oracle theorique, pas miroir bit a bit.

const Verif = preload("res://scripts/verif.gd")

const N := 200
const EXPOSANT := 4  # arete = 16
const RAYON := 2.0
const DEMI_ZONE := 20.0  # zone 40x40, densite comparable au peuplement du banc
const EPS := 1.0e-4

var _v := Verif.new()

func _init() -> void:
	if not ClassDB.class_exists("IndexSpatial"):
		printerr("ECHEC: classe C++ 'IndexSpatial' absente -- extension_terrain non chargee ?")
		quit(1)
		return
	_executer()
	if _v.echecs() == 0:
		print("OK: IndexSpatial C++ separation_lot rend la meme direction par unite " +
			"que l'oracle GDScript O(N^2), sur N=%d, rayon=%.2f, epsilon=%f" % [N, RAYON, EPS])
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _executer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	var positions := PackedVector3Array()
	positions.resize(N)
	for i in range(N):
		positions[i] = Vector3(
			rng.randf_range(-DEMI_ZONE, DEMI_ZONE),
			12.0,
			rng.randf_range(-DEMI_ZONE, DEMI_ZONE))

	# CIBLE (C++) : index rempli via deplacer_lot puis separation_lot.
	# On ouvre DEUX niveaux : celui du deplacer (EXPOSANT=4, arete 16) et
	# celui de la separation (EXPOSANT_SEP=1, arete 2, adapte au rayon).
	# separation_lot doit auto-selectionner EXPOSANT_SEP (plus petite arete
	# >= rayon) -- verrouille le vrai chemin de prod du banc.
	var index_cpp = ClassDB.instantiate("IndexSpatial")
	index_cpp.configurer(N)
	index_cpp.ouvrir_niveau(EXPOSANT)
	# Niveau PLANAIRE dedie a la separation : deplacer_lot y insere avec y=0
	# dans la clef, separation_lot le lit sans balayer l'axe Y. Exigence du
	# contrat depuis le chantier "degraissage separation_lot" (2026-09-08).
	index_cpp.ouvrir_niveau_planaire(1)
	index_cpp.deplacer_lot(positions)
	var dirs_cpp: PackedVector3Array = index_cpp.separation_lot(positions, RAYON)
	_v.v(dirs_cpp.size() == N, "separation_lot rend %d directions, attendu %d" % [dirs_cpp.size(), N])

	# ORACLE (GDScript naif) : meme formule, aucune indexation.
	var dirs_ref := _separation_reference(positions, RAYON)

	# Comparaison vecteur par vecteur.
	var voisins_total: int = 0
	for i in range(N):
		var d_cpp: Vector3 = dirs_cpp[i]
		var d_ref: Vector3 = dirs_ref[i]
		if not is_equal_approx(d_cpp.y, 0.0):
			_v.v(false, "unite %d : Y de la direction C++ != 0 (%.6f)" % [i, d_cpp.y])
			return
		var ecart_x: float = absf(d_cpp.x - d_ref.x)
		var ecart_z: float = absf(d_cpp.z - d_ref.z)
		if ecart_x > EPS or ecart_z > EPS:
			_v.v(false, "unite %d : CPP=(%.6f, %.6f) vs REF=(%.6f, %.6f), ecart=(%f, %f)" % [
				i, d_cpp.x, d_cpp.z, d_ref.x, d_ref.z, ecart_x, ecart_z])
			return
		if d_ref.length_squared() > 0.0:
			voisins_total += 1
	# Sanite : un rayon de 2 sur N=200 dans 40x40 doit produire des voisinages
	# non triviaux, sinon la parite serait un match trivial de zeros.
	_v.v(voisins_total > 0, "aucune unite n'a de voisin dans rayon %.2f -- test trivial, revoir DEMI_ZONE" % RAYON)

func _separation_reference(positions: PackedVector3Array, rayon: float) -> PackedVector3Array:
	var count: int = positions.size()
	var out := PackedVector3Array()
	out.resize(count)
	var rayon2: float = rayon * rayon
	for i in range(count):
		var p: Vector3 = positions[i]
		var ax: float = 0.0
		var az: float = 0.0
		for j in range(count):
			if j == i:
				continue
			var q: Vector3 = positions[j]
			var dx: float = p.x - q.x
			var dz: float = p.z - q.z
			var d2: float = dx * dx + dz * dz
			if d2 > rayon2 or d2 <= 1.0e-8:
				continue
			var d: float = sqrt(d2)
			var w: float = (rayon - d) / d
			ax += dx * w
			az += dz * w
		var len2: float = ax * ax + az * az
		if len2 > 1.0e-8:
			var inv_len: float = 1.0 / sqrt(len2)
			out[i] = Vector3(ax * inv_len, 0.0, az * inv_len)
		else:
			out[i] = Vector3.ZERO
	return out
