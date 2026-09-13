extends SceneTree

# Test manuel :
# godot --headless --script jeu/plantes/test_zone_exclusion_arbre.gd
#
# Verrouille jeu/plantes/zone_exclusion_arbre.gd, HORS DOMAINE : le
# test ne mentionne ni arbre, ni graine, ni foret. Prouve que
# `contient_avec_centre(cx, cz, x, z)` (predicat pur, sans dependance
# a la scene) rend true dans l'emprise (cercle et carre) et false hors
# emprise, que le centre translate l'emprise, que le carre supporte
# des demi-etendues asymetriques (rectangle).

const ZoneExclusion = preload("res://jeu/plantes/zone_exclusion_arbre.gd")
const Verif = preload("res://scripts/verif.gd")

var verif := Verif.new()

func _init() -> void:
	_cercle_contient_dans_rayon_et_rejette_hors_rayon()
	_carre_contient_dans_demi_etendues_et_rejette_hors()
	_carre_supporte_rectangle_asymetrique()
	_centre_translate_l_emprise()
	if verif.echecs() > 0:
		print("ECHEC: %d assertion(s) ratee(s)" % verif.echecs())
		quit(1)
		return
	print("OK: cercle et carre acceptent dans l'emprise et rejettent hors, ",
		"rectangle asymetrique tient, centre translate l'emprise")
	quit(0)

func _cercle_contient_dans_rayon_et_rejette_hors_rayon() -> void:
	var z := ZoneExclusion.new()
	z.forme = 0
	z.rayon = 5.0
	verif.v(z.contient_avec_centre(0.0, 0.0, 0.0, 0.0), "centre doit etre dans le cercle")
	verif.v(z.contient_avec_centre(0.0, 0.0, 4.0, 0.0), "point a distance 4 doit etre dans le cercle de rayon 5")
	verif.v(z.contient_avec_centre(0.0, 0.0, 3.0, 4.0), "point a distance 5 exactement doit etre dans le cercle (bord inclus)")
	verif.v(not z.contient_avec_centre(0.0, 0.0, 5.001, 0.0), "point a distance > 5 doit etre hors du cercle")
	verif.v(not z.contient_avec_centre(0.0, 0.0, 4.0, 4.0), "point a distance ~5.66 doit etre hors du cercle")
	z.free()

func _carre_contient_dans_demi_etendues_et_rejette_hors() -> void:
	var z := ZoneExclusion.new()
	z.forme = 1
	z.demi_x = 3.0
	z.demi_z = 3.0
	verif.v(z.contient_avec_centre(0.0, 0.0, 0.0, 0.0), "centre doit etre dans le carre")
	verif.v(z.contient_avec_centre(0.0, 0.0, 3.0, 3.0), "coin du carre doit etre dedans (bord inclus)")
	verif.v(z.contient_avec_centre(0.0, 0.0, -3.0, 2.0), "point aux limites en X doit etre dedans")
	verif.v(not z.contient_avec_centre(0.0, 0.0, 3.001, 0.0), "point hors demi_x doit etre rejete")
	verif.v(not z.contient_avec_centre(0.0, 0.0, 0.0, -3.001), "point hors demi_z doit etre rejete")
	z.free()

func _carre_supporte_rectangle_asymetrique() -> void:
	var z := ZoneExclusion.new()
	z.forme = 1
	z.demi_x = 10.0
	z.demi_z = 2.0
	verif.v(z.contient_avec_centre(0.0, 0.0, 9.0, 1.0), "rectangle 20x4 doit contenir (9, 1)")
	verif.v(not z.contient_avec_centre(0.0, 0.0, 0.0, 3.0), "rectangle 20x4 doit rejeter (0, 3) hors du demi_z")
	verif.v(z.contient_avec_centre(0.0, 0.0, -10.0, -2.0), "coin (-10, -2) inclus")
	z.free()

func _centre_translate_l_emprise() -> void:
	var z := ZoneExclusion.new()
	z.forme = 0
	z.rayon = 5.0
	verif.v(z.contient_avec_centre(100.0, 50.0, 100.0, 50.0), "centre translate doit etre dans le cercle")
	verif.v(z.contient_avec_centre(100.0, 50.0, 103.0, 54.0), "point a distance 5 du centre translate doit etre dans le cercle")
	verif.v(not z.contient_avec_centre(100.0, 50.0, 0.0, 0.0), "origine monde doit etre hors du cercle translate loin")
	z.free()
