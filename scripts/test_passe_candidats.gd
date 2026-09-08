extends SceneTree

# Test headless de la passe candidats (chantier "perception de masse en flux,
# fondation GDScript", 2026-09-08). Verrouille la PARITE entre :
#
#   ORACLE  -- GDScript naif O(N^2) : pour chaque paire (i, j != i), test
#              d(i, j) < rayon, retention symetrique.
#   CIBLE   -- BancPeuplement.passe_candidats(cases, positions, inv_arete,
#              rayon) : parcourt les cases planaires 3x3 autour de chaque
#              unite, filtre paires demi-pair, sortie CSR (offsets, voisins,
#              distances).
#
# CE QU'ON PROUVE :
# - Un vrai voisin (dans le rayon) figure dans la liste de i ET dans celle
#   de j (retention symetrique).
# - Un corps hors du rayon mais dans la case (piege "orange") N'EST PAS
#   retenu -- le filtre porte sur la VRAIE distance, pas sur l'appartenance
#   a la case.
# - Auto-paire (i == j) exclue.
# - Distances remontees == vraie distance euclidienne planaire.
# - Structure CSR bien formee : offsets.size() == count+1, offsets[count] ==
#   total, voisins.size() == distances.size() == total.
#
# Utilise scripts/verif.gd -- assert() natif INTERDIT.
# Lancement : godot --headless --script scripts/test_passe_candidats.gd
#
# Cases construites A LA MAIN (pas de dependance a IndexSpatial ni deplacer_lot) :
# on bucketise nous-memes pour rester independant de l'index C++ dans ce test
# unitaire -- l'arete du niveau planaire est passee en parametre.

const Verif = preload("res://scripts/verif.gd")
const BancPeuplement = preload("res://jeu/bancs/banc_peuplement.gd")

var _v := Verif.new()

func _init() -> void:
	_executer()
	if _v.echecs() == 0:
		print("OK: passe_candidats -- 6 cas passes (CSR bien forme, vrai voisin retenu deux fois, hors-rayon rejete, distance juste, parite complete vs oracle, cas vide)")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _executer() -> void:
	# ---- CAS 1 : structure CSR bien formee sur un petit lot ----
	var positions_1 := PackedVector3Array([
		Vector3(0.0, 12.0, 0.0),   # 0 -- au centre
		Vector3(1.0, 12.0, 0.0),   # 1 -- a 1.0 de 0
		Vector3(5.0, 12.0, 0.0),   # 2 -- a 5.0 de 0, isole
		Vector3(0.0, 12.0, 1.5),   # 3 -- a 1.5 de 0, a ~1.8 de 1
		Vector3(20.0, 12.0, 20.0), # 4 -- tres isole
	])
	var rayon: float = 2.0
	var arete: float = 2.0
	var inv_arete: float = 1.0 / arete
	var cases_1: Dictionary = _bucketiser_planaire(positions_1, inv_arete)
	var sortie_1: Dictionary = BancPeuplement.passe_candidats(cases_1, positions_1, inv_arete, rayon)
	var offsets_1: PackedInt32Array = sortie_1.offsets
	var voisins_1: PackedInt32Array = sortie_1.voisins
	var distances_1: PackedFloat32Array = sortie_1.distances
	_v.v(offsets_1.size() == positions_1.size() + 1, "cas 1 : offsets.size() != count+1")
	_v.v(voisins_1.size() == distances_1.size(), "cas 1 : voisins.size() != distances.size()")
	_v.v(offsets_1[positions_1.size()] == voisins_1.size(), "cas 1 : offsets[count] != voisins.size()")

	# ---- CAS 2 : vrai voisin retenu deux fois (i chez j, j chez i) ----
	var voisins_0: Array = _voisins_de(sortie_1, 0)
	var voisins_1_lst: Array = _voisins_de(sortie_1, 1)
	_v.v(voisins_0.has(1), "cas 2 : 1 absent des voisins de 0 (d=1.0 < rayon=2.0)")
	_v.v(voisins_1_lst.has(0), "cas 2 : 0 absent des voisins de 1 (retention symetrique brisee)")

	# ---- CAS 3 : hors-rayon rejete (piege 'orange') ----
	_v.v(voisins_0.has(3), "cas 3 : 3 absent des voisins de 0 (d=1.5 < rayon=2.0)")
	_v.v(not voisins_0.has(2), "cas 3 : 2 present chez 0 alors que d=5.0 > rayon=2.0 -- piege orange")
	_v.v(not voisins_0.has(4), "cas 3 : 4 present chez 0 alors que d>>rayon")

	# ---- CAS 4 : distance juste (parallele voisins/distances) ----
	var idx_1_dans_0: int = _index_de(voisins_0, 1)
	_v.v(idx_1_dans_0 >= 0, "cas 4 : 1 introuvable dans voisins_0 (redondant avec cas 2, garde de coherence)")
	if idx_1_dans_0 >= 0:
		var d_lue: float = distances_1[offsets_1[0] + idx_1_dans_0]
		_v.v(is_equal_approx(d_lue, 1.0), "cas 4 : distance(0,1) lue = %f, attendue 1.0" % d_lue)
	var idx_3_dans_0: int = _index_de(voisins_0, 3)
	if idx_3_dans_0 >= 0:
		var d_lue3: float = distances_1[offsets_1[0] + idx_3_dans_0]
		_v.v(is_equal_approx(d_lue3, 1.5), "cas 4 : distance(0,3) lue = %f, attendue 1.5" % d_lue3)

	# ---- CAS 5 : parite complete vs oracle O(N^2) sur un lot plus large ----
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	var N: int = 80
	var positions_5 := PackedVector3Array()
	positions_5.resize(N)
	for i in range(N):
		positions_5[i] = Vector3(rng.randf_range(-10.0, 10.0), 12.0, rng.randf_range(-10.0, 10.0))
	var cases_5: Dictionary = _bucketiser_planaire(positions_5, inv_arete)
	var sortie_5: Dictionary = BancPeuplement.passe_candidats(cases_5, positions_5, inv_arete, rayon)
	var oracle_5: Dictionary = _oracle_naif(positions_5, rayon)
	for i in range(N):
		var listee_cible: Array = _voisins_de(sortie_5, i)
		listee_cible.sort()
		var listee_ref: Array = oracle_5.get(i, [])
		listee_ref.sort()
		if listee_cible != listee_ref:
			_v.v(false, "cas 5 : unite %d -- voisins CIBLE=%s vs ORACLE=%s" % [i, str(listee_cible), str(listee_ref)])
			return

	# ---- CAS 6 : cas limite rayon=0 ----
	var sortie_vide: Dictionary = BancPeuplement.passe_candidats(cases_1, positions_1, inv_arete, 0.0)
	_v.v((sortie_vide.voisins as PackedInt32Array).size() == 0, "cas 6 : rayon=0 retourne des voisins")
	_v.v((sortie_vide.offsets as PackedInt32Array).size() == positions_1.size() + 1, "cas 6 : offsets mal dimensionne pour lot vide de voisins")

# Bucketise `positions` en cases planaires (Vector3i(cx, 0, cz) -> PackedInt32Array
# d'ids). Reproduit exactement ce que fait IndexSpatial::deplacer_lot avec un
# niveau planaire, sans dependre du C++.
func _bucketiser_planaire(positions: PackedVector3Array, inv_arete: float) -> Dictionary:
	var cases: Dictionary = {}
	for i in range(positions.size()):
		var p: Vector3 = positions[i]
		var cx: int = floori(p.x * inv_arete)
		var cz: int = floori(p.z * inv_arete)
		var cle := Vector3i(cx, 0, cz)
		var contenu: PackedInt32Array = cases.get(cle, PackedInt32Array())
		contenu.push_back(i)
		cases[cle] = contenu
	return cases

# Oracle O(N^2) : par unite, liste des voisins dans le rayon (distance
# horizontale STRICTEMENT positive ET STRICTEMENT inferieure au rayon).
func _oracle_naif(positions: PackedVector3Array, rayon: float) -> Dictionary:
	var out: Dictionary = {}
	var rayon2: float = rayon * rayon
	var count: int = positions.size()
	for i in range(count):
		var liste: Array = []
		var p: Vector3 = positions[i]
		for j in range(count):
			if j == i:
				continue
			var q: Vector3 = positions[j]
			var dx: float = p.x - q.x
			var dz: float = p.z - q.z
			var d2: float = dx * dx + dz * dz
			if d2 < rayon2 and d2 > 1.0e-8:
				liste.append(j)
		out[i] = liste
	return out

func _voisins_de(sortie: Dictionary, i: int) -> Array:
	var offsets: PackedInt32Array = sortie.offsets
	var voisins: PackedInt32Array = sortie.voisins
	var debut: int = offsets[i]
	var fin: int = offsets[i + 1]
	var out: Array = []
	for k in range(debut, fin):
		out.append(int(voisins[k]))
	return out

func _index_de(liste: Array, valeur: int) -> int:
	for i in range(liste.size()):
		if int(liste[i]) == valeur:
			return i
	return -1
