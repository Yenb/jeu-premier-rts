extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_champ_saturation_plat.gd
#
# Verrouille scripts/champ_saturation_plat.gd, variante ALLOCATION-
# REDUITE de champ_saturation.gd (grille PackedFloat32Array plate,
# lookup O(1) sans hash Vector2i). Prouve que les valeurs lues sont
# EQUIVALENTES (tolerance 1e-5 par case sur la difference float entre
# division et multiplication par l'inverse pre-calc) au champ Dictionary
# apres N depots / retraits / transitions.

const ChampPlat = preload("res://scripts/champ_saturation_plat.gd")
const ChampDict = preload("res://scripts/champ_saturation.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

const TOLERANCE: float = 1.0e-5

func _init() -> void:
	_configurer_puis_deposer_puis_retrait_rend_champ_vide()
	_rayon_zero_ne_touche_que_case_centrale()
	_depot_hors_bornes_ignore_silencieusement()
	_cumul_de_deux_depots_matche_dict()
	_redeposer_matche_deposer_ancien_puis_nouveau()
	_deposer_lot_matche_deposer_un_par_un()
	_redeposer_lot_matche_redeposer_un_par_un()
	_lire_lot_matche_lire_un_par_un()
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: champ plat equivalent au champ Dictionary sur depot/retrait, ",
		"rayon zero, hors bornes silencieux, cumul additif, redeposer, ",
		"deposer_lot, redeposer_lot, lire_lot (tolerance %f)" % TOLERANCE)
	quit(0)

func _configure(champ) -> void:
	# Grille assez large pour couvrir les rayons testes.
	champ.configurer(-20, -20, 20, 20)

func _comparer_champs(plat, dict, tag: String) -> void:
	var ecart_max: float = 0.0
	var dx: int = -20
	while dx <= 20:
		var dz: int = -20
		while dz <= 20:
			var vp: float = plat.lire(float(dx) + 0.5, float(dz) + 0.5, 1.0)
			var vd: float = dict.lire(float(dx) + 0.5, float(dz) + 0.5, 1.0)
			ecart_max = maxf(ecart_max, absf(vp - vd))
			dz += 1
		dx += 1
	verif.v(ecart_max <= TOLERANCE, "%s : ecart max %f > tolerance %f" % [tag, ecart_max, TOLERANCE])

func _configurer_puis_deposer_puis_retrait_rend_champ_vide() -> void:
	var c := ChampPlat.new()
	_configure(c)
	c.deposer(0.0, 0.0, 4.0, 1.0, 0.5, 1)
	c.deposer(0.0, 0.0, 4.0, 1.0, 0.5, -1)
	verif.v(c.nombre_cases() == 0, "champ plat doit etre vide apres depot puis retrait symetrique (%d != 0)" % c.nombre_cases())

func _rayon_zero_ne_touche_que_case_centrale() -> void:
	var c := ChampPlat.new()
	_configure(c)
	c.deposer(3.5, -2.5, 0.0, 1.0, 0.4, 1)
	verif.v(c.nombre_cases() == 1, "rayon zero doit toucher UNE case (%d != 1)" % c.nombre_cases())
	verif.v(absf(c.lire(3.5, -2.5, 1.0) - 0.4) < TOLERANCE, "case centrale doit valoir magnitude")

func _depot_hors_bornes_ignore_silencieusement() -> void:
	var c := ChampPlat.new()
	_configure(c)
	# Centre hors bornes (bornes = -20..20 en indices). Depot entier ignore.
	c.deposer(50.0, 50.0, 3.0, 1.0, 1.0, 1)
	verif.v(c.nombre_cases() == 0, "depot hors bornes doit etre inerte (%d != 0)" % c.nombre_cases())
	# Centre en emprise, empreinte deborde : cases en emprise seules recoivent.
	c.deposer(19.5, 19.5, 3.0, 1.0, 1.0, 1)
	verif.v(c.nombre_cases() > 0, "depot bord emprise doit poser sur les cases en emprise")

func _cumul_de_deux_depots_matche_dict() -> void:
	var plat := ChampPlat.new()
	_configure(plat)
	var dict := ChampDict.new()
	plat.deposer(0.0, 0.0, 4.0, 1.0, 0.5, 1)
	plat.deposer(2.5, 1.5, 3.0, 1.0, 0.8, 1)
	dict.deposer(0.0, 0.0, 4.0, 1.0, 0.5, 1)
	dict.deposer(2.5, 1.5, 3.0, 1.0, 0.8, 1)
	_comparer_champs(plat, dict, "cumul de deux depots")

func _redeposer_matche_deposer_ancien_puis_nouveau() -> void:
	var plat := ChampPlat.new()
	_configure(plat)
	var dict := ChampDict.new()
	plat.deposer(1.0, 2.0, 3.0, 1.0, 0.6, 1)
	dict.deposer(1.0, 2.0, 3.0, 1.0, 0.6, 1)
	plat.redeposer(1.0, 2.0, 3.0, 5.0, 1.0, 0.6, 0.9)
	dict.redeposer(1.0, 2.0, 3.0, 5.0, 1.0, 0.6, 0.9)
	_comparer_champs(plat, dict, "redeposer")

func _deposer_lot_matche_deposer_un_par_un() -> void:
	var plat := ChampPlat.new()
	_configure(plat)
	var dict := ChampDict.new()
	var cx: PackedFloat32Array = PackedFloat32Array([0.5, 5.0, -3.5, 2.0])
	var cz: PackedFloat32Array = PackedFloat32Array([0.5, 2.5, -4.0, 1.5])
	var r: PackedFloat32Array = PackedFloat32Array([4.0, 3.0, 5.0, 0.0])
	var m: PackedFloat32Array = PackedFloat32Array([0.8, 1.0, 0.6, 2.0])
	var s: PackedByteArray = PackedByteArray([1, 0, 1, 0])
	plat.deposer_lot(cx, cz, r, 1.0, m, s)
	var i: int = 0
	while i < cx.size():
		var signe: int = 1 if s[i] == 1 else -1
		dict.deposer(cx[i], cz[i], r[i], 1.0, m[i], signe)
		i += 1
	_comparer_champs(plat, dict, "deposer_lot")

func _redeposer_lot_matche_redeposer_un_par_un() -> void:
	var plat := ChampPlat.new()
	_configure(plat)
	var dict := ChampDict.new()
	plat.deposer(0.5, 0.5, 4.0, 1.0, 0.5, 1)
	dict.deposer(0.5, 0.5, 4.0, 1.0, 0.5, 1)
	var cx: PackedFloat32Array = PackedFloat32Array([0.5, 5.5, -3.5])
	var cz: PackedFloat32Array = PackedFloat32Array([0.5, 2.5, -4.5])
	var ra: PackedFloat32Array = PackedFloat32Array([2.0, 0.0, 4.0])
	var rn: PackedFloat32Array = PackedFloat32Array([4.0, 3.0, 2.0])
	var ma: PackedFloat32Array = PackedFloat32Array([0.3, 0.0, 0.6])
	var mn: PackedFloat32Array = PackedFloat32Array([0.7, 0.5, 0.4])
	plat.redeposer_lot(cx, cz, ra, rn, 1.0, ma, mn)
	var i: int = 0
	while i < cx.size():
		dict.redeposer(cx[i], cz[i], ra[i], rn[i], 1.0, ma[i], mn[i])
		i += 1
	_comparer_champs(plat, dict, "redeposer_lot")

func _lire_lot_matche_lire_un_par_un() -> void:
	var plat := ChampPlat.new()
	_configure(plat)
	plat.deposer(0.0, 0.0, 5.0, 1.0, 1.0, 1)
	plat.deposer(6.0, 3.0, 3.0, 1.0, 0.8, 1)
	var px: PackedFloat32Array = PackedFloat32Array([0.5, 3.5, 6.5, 20.5, -30.0])
	var pz: PackedFloat32Array = PackedFloat32Array([0.5, -1.5, 3.5, 20.5, -30.0])
	var attendu := PackedFloat32Array()
	attendu.resize(px.size())
	var i: int = 0
	while i < px.size():
		attendu[i] = plat.lire(px[i], pz[i], 1.0)
		i += 1
	var obtenu: PackedFloat32Array = plat.lire_lot(px, pz, 1.0)
	verif.v(obtenu.size() == attendu.size(), "lire_lot doit rendre la meme longueur")
	var ecart_max: float = 0.0
	var k: int = 0
	while k < obtenu.size():
		ecart_max = maxf(ecart_max, absf(obtenu[k] - attendu[k]))
		k += 1
	verif.v(ecart_max == 0.0, "lire_lot doit rendre EXACTEMENT les memes valeurs que lire un a un (ecart max %f)" % ecart_max)
