extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_facteur_variance.gd
#
# Verrouille scripts/facteur_variance.gd, mecanisme HORS DOMAINE : le test
# ne mentionne ni arbre, ni graine, ni stade. Prouve que `tirer(rng, a)`
# rend un facteur dans [1-a, 1+a] pour tout usage, borne le sortie
# lorsqu'on lui passe une amplitude negative ou >1, et rend deterministe
# les tirages sous meme seed.

const FacteurVariance = preload("res://scripts/facteur_variance.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_amplitude_zero_rend_un_exact()
	_amplitude_borne_intervalle()
	_amplitude_negative_clampe_a_zero()
	_amplitude_superieure_a_un_clampe_a_un()
	_meme_seed_meme_sequence()
	_moyenne_grosse_population_proche_de_un()
	_tirer_entre_reste_dans_les_bornes()
	_tirer_entre_mini_egal_maxi_rend_valeur_exacte()
	_tirer_entre_meme_seed_reproduit_la_sequence()
	_tirer_entre_bornes_asymetriques_moyenne_au_centre()
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: amplitude 0 rend 1.0 exact, amplitude a borne le facteur dans [1-a, 1+a], " +
		"amplitude negative ou >1 clampee sans facteur negatif silencieux, meme seed " +
		"reproduit la meme sequence, moyenne d'un gros echantillon proche de 1.0, " +
		"tirer_entre reste dans [mini, maxi] et deterministe sous seed egal")
	quit(0)

func _amplitude_zero_rend_un_exact() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var i: int = 0
	while i < 100:
		var f: float = FacteurVariance.tirer(rng, 0.0)
		verif.v(f == 1.0, "amplitude 0 doit rendre 1.0 exact, recu %f" % f)
		i += 1

func _amplitude_borne_intervalle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var a: float = 0.5
	var i: int = 0
	while i < 1000:
		var f: float = FacteurVariance.tirer(rng, a)
		verif.v(f >= 1.0 - a - 1e-6, "facteur %f sous la borne 1-a" % f)
		verif.v(f <= 1.0 + a + 1e-6, "facteur %f au-dessus de 1+a" % f)
		i += 1

func _amplitude_negative_clampe_a_zero() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var i: int = 0
	while i < 100:
		var f: float = FacteurVariance.tirer(rng, -0.5)
		verif.v(f == 1.0, "amplitude negative doit clamper a 0 -> 1.0, recu %f" % f)
		i += 1

func _amplitude_superieure_a_un_clampe_a_un() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var i: int = 0
	while i < 1000:
		var f: float = FacteurVariance.tirer(rng, 2.5)
		verif.v(f >= 0.0 - 1e-6, "amplitude clampee a 1 doit garder facteur >= 0, recu %f" % f)
		verif.v(f <= 2.0 + 1e-6, "amplitude clampee a 1 doit garder facteur <= 2, recu %f" % f)
		i += 1

func _meme_seed_meme_sequence() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 20260910
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 20260910
	var i: int = 0
	while i < 200:
		var fa: float = FacteurVariance.tirer(rng_a, 0.7)
		var fb: float = FacteurVariance.tirer(rng_b, 0.7)
		verif.v(fa == fb, "meme seed doit rendre meme facteur (a=%f b=%f)" % [fa, fb])
		i += 1

func _moyenne_grosse_population_proche_de_un() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 314159
	var somme: float = 0.0
	var n: int = 100000
	var i: int = 0
	while i < n:
		somme += FacteurVariance.tirer(rng, 0.5)
		i += 1
	var moyenne: float = somme / float(n)
	# Distribution uniforme sur [1-a, 1+a] : moyenne theorique = 1.0. Tolerance
	# large pour ne pas rougir sur un aleas statistique.
	verif.v(abs(moyenne - 1.0) < 0.01, "moyenne %f trop loin de 1.0 sur %d tirages" % [moyenne, n])

func _tirer_entre_reste_dans_les_bornes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var mini: float = 0.5
	var maxi: float = 2.0
	var i: int = 0
	while i < 1000:
		var f: float = FacteurVariance.tirer_entre(rng, mini, maxi)
		verif.v(f >= mini - 1e-6, "tirer_entre %f sous mini %f" % [f, mini])
		verif.v(f <= maxi + 1e-6, "tirer_entre %f au-dessus de maxi %f" % [f, maxi])
		i += 1

func _tirer_entre_mini_egal_maxi_rend_valeur_exacte() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var i: int = 0
	while i < 100:
		var f: float = FacteurVariance.tirer_entre(rng, 1.7, 1.7)
		verif.v(f == 1.7, "tirer_entre(1.7, 1.7) doit rendre 1.7 exact, recu %f" % f)
		i += 1

func _tirer_entre_meme_seed_reproduit_la_sequence() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 20260911
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 20260911
	var i: int = 0
	while i < 200:
		var fa: float = FacteurVariance.tirer_entre(rng_a, -1.0, 3.0)
		var fb: float = FacteurVariance.tirer_entre(rng_b, -1.0, 3.0)
		verif.v(fa == fb, "meme seed doit rendre meme tirer_entre (a=%f b=%f)" % [fa, fb])
		i += 1

func _tirer_entre_bornes_asymetriques_moyenne_au_centre() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 271828
	var mini: float = 0.5
	var maxi: float = 2.0
	var somme: float = 0.0
	var n: int = 100000
	var i: int = 0
	while i < n:
		somme += FacteurVariance.tirer_entre(rng, mini, maxi)
		i += 1
	var moyenne: float = somme / float(n)
	# Uniforme sur [mini, maxi] -> moyenne theorique = (mini + maxi) / 2.
	var centre: float = (mini + maxi) * 0.5
	verif.v(abs(moyenne - centre) < 0.01, "moyenne %f trop loin du centre %f sur %d tirages" % [moyenne, centre, n])
