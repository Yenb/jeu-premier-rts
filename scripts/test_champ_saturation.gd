extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_champ_saturation.gd
#
# Verrouille scripts/champ_saturation.gd, mecanisme HORS DOMAINE : le test
# ne mentionne ni arbre, ni ombre, ni graine. Prouve que deposer(...) puis
# retirer(...) au meme endroit rend un champ vide, que la decroissance est
# lineaire en norme Chebyshev, que deux depots se cumulent, et que la
# portee physique est independante de taille_case.

const ChampSaturation = preload("res://scripts/champ_saturation.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_depot_puis_retrait_symetrique_rend_champ_vide()
	_rayon_zero_ne_touche_que_la_case_centrale()
	_decroissance_chebyshev_lineaire()
	_bord_strict_skippe()
	_cumul_de_deux_depots()
	_portee_independante_de_taille_case()
	_case_sous_epsilon_retiree()
	_magnitude_nulle_no_op()
	_redeposer_equivaut_retrait_puis_depot()
	_redeposer_lot_equivaut_a_redeposer_un_par_un()
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: depot signe symetrique (champ vide apres retrait), decroissance " +
		"Chebyshev lineaire, bord strict skippe, cumul additif, portee physique " +
		"independante de taille_case, case sous epsilon retiree, magnitude nulle no-op")
	quit(0)

# Depot puis retrait aux memes parametres : champ vide.
func _depot_puis_retrait_symetrique_rend_champ_vide() -> void:
	var c := ChampSaturation.new()
	c.deposer(10.0, 20.0, 5.0, 1.0, 1.5, 1)
	verif.v(c.nombre_cases() > 0, "depot devrait remplir des cases")
	c.deposer(10.0, 20.0, 5.0, 1.0, 1.5, -1)
	verif.v(c.nombre_cases() == 0, "retrait symetrique devrait vider le champ, reste %d cases" % c.nombre_cases())

# Rayon nul : une seule case pleine (centre), aucune voisine.
func _rayon_zero_ne_touche_que_la_case_centrale() -> void:
	var c := ChampSaturation.new()
	c.deposer(0.5, 0.5, 0.0, 1.0, 2.0, 1)
	verif.v(c.nombre_cases() == 1, "rayon=0 doit poser exactement 1 case, recu %d" % c.nombre_cases())
	verif.v(is_equal_approx(c.lire(0.5, 0.5, 1.0), 2.0), "case centrale doit recevoir magnitude exacte")
	verif.v(c.lire(1.5, 0.5, 1.0) == 0.0, "voisine ne doit rien recevoir")

# rayon=4 en cases (rayon_m=4, taille_case=1) : centre=mag, cases a d=1
# recoivent mag*(1-1/4)=0.75mag, d=2 -> 0.5mag, d=3 -> 0.25mag, d=4 -> 0
# (bord strict, skippe).
func _decroissance_chebyshev_lineaire() -> void:
	var c := ChampSaturation.new()
	c.deposer(0.5, 0.5, 4.0, 1.0, 1.0, 1)
	verif.v(is_equal_approx(c.lire(0.5, 0.5, 1.0), 1.0), "centre = magnitude")
	verif.v(is_equal_approx(c.lire(1.5, 0.5, 1.0), 0.75), "d=1 axial doit valoir 0.75, recu %f" % c.lire(1.5, 0.5, 1.0))
	verif.v(is_equal_approx(c.lire(1.5, 1.5, 1.0), 0.75), "d=1 diagonal (Chebyshev) doit valoir 0.75")
	verif.v(is_equal_approx(c.lire(2.5, 0.5, 1.0), 0.5), "d=2 doit valoir 0.5")
	verif.v(is_equal_approx(c.lire(3.5, 0.5, 1.0), 0.25), "d=3 doit valoir 0.25")

# Bord strict a poids=0 : case a rayon exact n'est pas posee.
func _bord_strict_skippe() -> void:
	var c := ChampSaturation.new()
	c.deposer(0.5, 0.5, 2.0, 1.0, 1.0, 1)
	# rayon=2 en cases, d=2 -> poids = 1 - 2/2 = 0.0 -> skippe.
	verif.v(c.lire(2.5, 0.5, 1.0) == 0.0, "case a d=rayon doit etre skippee, recu %f" % c.lire(2.5, 0.5, 1.0))
	# Le nombre de cases est le carre 3x3 (d in [0,1]) = 9, pas 5x5 = 25.
	verif.v(c.nombre_cases() == 9, "seules les cases a poids > 0 doivent etre posees, recu %d" % c.nombre_cases())

# Deux depots identiques : chaque case vaut double.
func _cumul_de_deux_depots() -> void:
	var c := ChampSaturation.new()
	c.deposer(0.5, 0.5, 4.0, 1.0, 1.0, 1)
	c.deposer(0.5, 0.5, 4.0, 1.0, 1.0, 1)
	verif.v(is_equal_approx(c.lire(0.5, 0.5, 1.0), 2.0), "cumul centre doit doubler")
	verif.v(is_equal_approx(c.lire(1.5, 0.5, 1.0), 1.5), "cumul d=1 doit doubler")

# Meme rayon physique, deux tailles de case differentes : la LECTURE au meme
# point physique donne la meme valeur au centre (magnitude), et l'empreinte
# physique couvre le meme disque, seule la finesse change.
func _portee_independante_de_taille_case() -> void:
	var c1 := ChampSaturation.new()
	c1.deposer(0.0, 0.0, 5.0, 1.0, 1.0, 1)
	var c2 := ChampSaturation.new()
	c2.deposer(0.0, 0.0, 5.0, 2.5, 1.0, 1)
	# Centre : plein a magnitude dans les deux.
	verif.v(is_equal_approx(c1.lire(0.0, 0.0, 1.0), 1.0), "centre magnitude tc=1")
	verif.v(is_equal_approx(c2.lire(0.0, 0.0, 2.5), 1.0), "centre magnitude tc=2.5")
	# Un point a ~4m du centre est dans la portee physique dans les deux
	# cas : lecture strictement positive.
	verif.v(c1.lire(4.0, 0.0, 1.0) > 0.0, "point a 4m dans portee, tc=1")
	verif.v(c2.lire(4.0, 0.0, 2.5) > 0.0, "point a 4m dans portee, tc=2.5")
	# Un point a ~6m du centre est HORS portee physique : lecture nulle
	# dans les deux.
	verif.v(c1.lire(6.0, 0.0, 1.0) == 0.0, "point a 6m hors portee, tc=1")
	verif.v(c2.lire(6.0, 0.0, 2.5) == 0.0, "point a 6m hors portee, tc=2.5")

# Un depot puis un retrait presque total : les cases retombant sous EPS
# disparaissent du champ.
func _case_sous_epsilon_retiree() -> void:
	var c := ChampSaturation.new()
	c.deposer(0.5, 0.5, 2.0, 1.0, 1.0, 1)
	var n_avant: int = c.nombre_cases()
	c.deposer(0.5, 0.5, 2.0, 1.0, 1.0 - 1.0e-9, -1)
	verif.v(c.nombre_cases() < n_avant, "cases quasi nulles doivent etre retirees")

# Magnitude 0 : no-op.
func _magnitude_nulle_no_op() -> void:
	var c := ChampSaturation.new()
	c.deposer(0.0, 0.0, 5.0, 1.0, 0.0, 1)
	verif.v(c.nombre_cases() == 0, "magnitude nulle ne doit rien poser")

# Invariant : redeposer(A -> B) == deposer(A, -1) puis deposer(B, +1) sur
# le meme champ initial. Trois scenarios : (1) rayons differents non nuls,
# (2) rayon nul cote ancien (naissance simulee), (3) rayon nul cote nouveau
# (mort simulee). Tolerance = EPS_COUVERT.
func _redeposer_equivaut_retrait_puis_depot() -> void:
	var scenarios: Array = [
		{"ra": 5.0, "rn": 3.0, "ma": 0.8, "mn": 1.2},
		{"ra": 0.0, "rn": 4.0, "ma": 0.5, "mn": 1.0},
		{"ra": 4.0, "rn": 0.0, "ma": 1.0, "mn": 0.3},
		{"ra": 6.0, "rn": 6.0, "ma": 1.0, "mn": 1.0},
	]
	var eps: float = 1.0e-6
	for s in scenarios:
		var oracle := ChampSaturation.new()
		# Champ initial non vide pour couvrir le cas cumul sur existant.
		oracle.deposer(10.0, 0.0, 4.0, 1.0, 0.5, 1)
		oracle.deposer(0.0, 0.0, float(s["ra"]), 1.0, float(s["ma"]), -1)
		oracle.deposer(0.0, 0.0, float(s["rn"]), 1.0, float(s["mn"]), 1)
		var essai := ChampSaturation.new()
		essai.deposer(10.0, 0.0, 4.0, 1.0, 0.5, 1)
		essai.redeposer(0.0, 0.0, float(s["ra"]), float(s["rn"]), 1.0, float(s["ma"]), float(s["mn"]))
		# Meme nombre de cases (a un pres pour cas limite EPS, tolere).
		verif.v(absi(oracle.nombre_cases() - essai.nombre_cases()) <= 1,
			"redeposer scenario %s : ecart nombre_cases oracle=%d essai=%d" % [str(s), oracle.nombre_cases(), essai.nombre_cases()])
		# Comparaison valeur par valeur sur un carre large autour du centre.
		var ecart_max: float = 0.0
		for dx in range(-8, 9):
			for dz in range(-8, 9):
				var vo: float = oracle.lire(float(dx) + 0.5, float(dz) + 0.5, 1.0)
				var ve: float = essai.lire(float(dx) + 0.5, float(dz) + 0.5, 1.0)
				ecart_max = maxf(ecart_max, absf(vo - ve))
		verif.v(ecart_max < eps,
			"redeposer scenario %s : ecart max %f depasse eps %f" % [str(s), ecart_max, eps])

# Invariant : redeposer_lot(N transitions) == redeposer une par une dans
# le meme ordre. Trois transitions a des centres distincts avec rayons
# et magnitudes varies, champ initial non vide pour couvrir le cumul.
func _redeposer_lot_equivaut_a_redeposer_un_par_un() -> void:
	var cx: PackedFloat32Array = PackedFloat32Array([0.0, 5.0, -3.0])
	var cz: PackedFloat32Array = PackedFloat32Array([0.0, 2.0, -4.0])
	var r_a: PackedFloat32Array = PackedFloat32Array([4.0, 3.0, 0.0])
	var r_n: PackedFloat32Array = PackedFloat32Array([3.0, 5.0, 4.0])
	var m_a: PackedFloat32Array = PackedFloat32Array([0.8, 1.0, 0.0])
	var m_n: PackedFloat32Array = PackedFloat32Array([1.2, 0.6, 0.9])
	var taille_case: float = 1.0
	var oracle := ChampSaturation.new()
	oracle.deposer(10.0, 0.0, 4.0, taille_case, 0.5, 1)
	var essai := ChampSaturation.new()
	essai.deposer(10.0, 0.0, 4.0, taille_case, 0.5, 1)
	# Oracle : N appels a redeposer dans l'ordre.
	var i: int = 0
	while i < cx.size():
		oracle.redeposer(cx[i], cz[i], r_a[i], r_n[i], taille_case, m_a[i], m_n[i])
		i += 1
	# Essai : un seul appel a redeposer_lot.
	essai.redeposer_lot(cx, cz, r_a, r_n, taille_case, m_a, m_n)
	verif.v(oracle.nombre_cases() == essai.nombre_cases(),
		"redeposer_lot : nombre_cases oracle=%d essai=%d" % [oracle.nombre_cases(), essai.nombre_cases()])
	var ecart_max: float = 0.0
	for dx in range(-10, 11):
		for dz in range(-10, 11):
			var vo: float = oracle.lire(float(dx) + 0.5, float(dz) + 0.5, taille_case)
			var ve: float = essai.lire(float(dx) + 0.5, float(dz) + 0.5, taille_case)
			ecart_max = maxf(ecart_max, absf(vo - ve))
	verif.v(ecart_max == 0.0,
		"redeposer_lot doit rendre le meme champ que N redeposer sequentiels (ecart max %f)" % ecart_max)
