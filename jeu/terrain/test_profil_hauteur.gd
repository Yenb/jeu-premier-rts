extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_profil_hauteur.gd
#
# Verrouille le PROFIL DE HAUTEUR PAR ITEM de carte_terrain : sur une cellule
# sommet pleine, `sommet` ne rend plus un plafond plat mais la surface interpolee
# du profil de l'item, orientee par l'orthogonal_index.
#
# Ce qui est tenu :
# - GENERIQUE, PROUVE HORS DOMAINE : un item fictif avec un profil arbitraire rend
#   exactement la hauteur bilineaire attendue -- le mecanisme ne connait aucune
#   "rampe", juste des coins ;
# - CALIBRATION RAMPE : l'item 2 (rampe de bloc.tres) monte vers le cote -x de la
#   cellule (mesure sur les 6 sommets du prisme, identiques maillage et collision),
#   du bas (frac 0) au haut (frac 1, plafond) ;
# - ORIENTATION : un demi-tour (index 10) inverse le sens de la pente ;
# - NON-REGRESSION : une cellule par defaut (bloc plein) garde son plafond plat,
#   et une cellule creusee ignore le profil.
#
# carte_terrain n'a pas de class_name (doctrine) : Carte.new() rend un objet non
# type, donc chaque lecture de propriete est castee explicitement (float/int).
#
# Regles tenues : positions en Vector3. Aucun hasard. Les prints sont des traces.
# Rien de scripts/, data/ ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const Carte = preload("res://jeu/terrain/carte_terrain.gd")

const TOL := 0.001

var _v

func _init() -> void:
	_v = Verif.new()
	_juger_hors_domaine()
	_juger_rampe()
	_juger_orientation()
	_juger_non_regression()
	_conclure()

func _couche_sommet(c) -> int:
	return int(c.couche_base) + int(c.couches_pleines) - 1

# GENERIQUE : item fictif, profil arbitraire [0.2,0.2,0.8,0.8] (monte vers u=1,
# independant de v). La hauteur suit 0.2 + 0.6*u en fraction de cellule.
func _juger_hors_domaine() -> void:
	var c = Carte.new()
	var cote := float(c.cote)
	var couche := _couche_sommet(c)
	var base := float(couche) * cote
	c.poser_profil_hauteur(99, PackedFloat32Array([0.2, 0.2, 0.8, 0.8]))
	c.poser_cellule(Vector3i(1, couche, 1), 99, 0)   # colonne 1 : monde x dans [cote, 2*cote)
	for u in [0.25, 0.5, 0.75]:
		var x := cote + (u as float) * cote
		var z := cote + 0.5 * cote
		var attendu := base + (0.2 + 0.6 * (u as float)) * cote
		var mesure = c.sommet(x, z)
		_v.v(mesure != null and absf(float(mesure) - attendu) < TOL,
			"profil generique a u=%.2f : %s au lieu de %.3f" % [u, mesure, attendu])
	print("hors domaine : profil arbitraire interpole bilineairement, sans nommer aucune forme")

# RAMPE (item 2) orientation 0 : monte vers -x. frac = 1 - u.
func _juger_rampe() -> void:
	var c = Carte.new()
	var cote := float(c.cote)
	var couche := _couche_sommet(c)
	var base := float(couche) * cote
	c.poser_cellule(Vector3i(0, couche, 0), 2, 0)   # colonne 0 : monde x dans [0, cote)
	var z := 0.5 * cote
	var y_pres_de_zero = c.sommet(0.1 * cote, z)
	var y_pres_du_bord = c.sommet(0.9 * cote, z)
	_v.v(y_pres_de_zero != null and y_pres_du_bord != null, "la rampe ne rend aucune hauteur")
	if y_pres_de_zero == null or y_pres_du_bord == null:
		return
	var attendu_bas := base + (1.0 - 0.1) * cote
	var attendu_haut := base + (1.0 - 0.9) * cote
	_v.v(absf(float(y_pres_de_zero) - attendu_bas) < TOL,
		"rampe pres de x=0 : %.3f au lieu de %.3f (doit etre haut)" % [y_pres_de_zero, attendu_bas])
	_v.v(absf(float(y_pres_du_bord) - attendu_haut) < TOL,
		"rampe pres du bord : %.3f au lieu de %.3f (doit etre bas)" % [y_pres_du_bord, attendu_haut])
	_v.v(float(y_pres_de_zero) > float(y_pres_du_bord), "la rampe ne monte pas vers -x")
	print("rampe : monte vers -x, du plafond (%.2f) au plancher (%.2f)" % [y_pres_de_zero, y_pres_du_bord])

# DEMI-TOUR (orthogonal_index 10 = 180°) : la pente s'inverse.
func _juger_orientation() -> void:
	var c = Carte.new()
	var cote := float(c.cote)
	var couche := _couche_sommet(c)
	c.poser_cellule(Vector3i(0, couche, 0), 2, 10)
	var z := 0.5 * cote
	var y_pres_de_zero = c.sommet(0.1 * cote, z)
	var y_pres_du_bord = c.sommet(0.9 * cote, z)
	_v.v(y_pres_de_zero != null and y_pres_du_bord != null
		and float(y_pres_de_zero) < float(y_pres_du_bord),
		"le demi-tour n'inverse pas la pente : %s puis %s" % [y_pres_de_zero, y_pres_du_bord])
	print("demi-tour : pente inversee (monte vers +x)")

# NON-REGRESSION : bloc plein -> plafond plat ; cellule creusee -> sous-cubes.
func _juger_non_regression() -> void:
	var c = Carte.new()
	var cote := float(c.cote)
	var couche := _couche_sommet(c)
	var base := float(couche) * cote
	var plat = c.sommet(0.5 * cote, 0.5 * cote)
	_v.v(plat != null and absf(float(plat) - (base + cote)) < TOL,
		"un bloc plein par defaut ne rend plus son plafond plat : %s" % plat)
	c.poser_cellule(Vector3i(3, couche, 3), 2, 0)
	var x := 3.0 * cote + 0.1 * cote
	var z := 3.0 * cote + 0.5 * cote
	var avant = c.sommet(x, z)
	var ix := clampi(int(floor(0.1 * 3.0)), 0, 2)
	var iz := clampi(int(floor(0.5 * 3.0)), 0, 2)
	c.casser_sous_cube(Vector3i(3, couche, 3), ix + 2 * 3 + iz * 9)
	var apres = c.sommet(x, z)
	_v.v(avant != null and apres != null and float(apres) < float(avant),
		"une cellule creusee garde la hauteur du profil au lieu de descendre : %s puis %s" % [avant, apres])
	print("non-regression : bloc plein plat, cellule creusee suit les sous-cubes")

func _conclure() -> void:
	if _v.echecs() > 0:
		print("ECHEC: le profil de hauteur ne tient pas (%d)" % _v.echecs())
		quit(1)
		return
	print("OK: profil de hauteur -- mecanisme bilineaire generique hors domaine, rampe calibree qui " +
		"monte vers -x, demi-tour qui inverse, bloc plein plat et cellule creusee preserves")
	quit(0)
