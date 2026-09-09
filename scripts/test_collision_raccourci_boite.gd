extends SceneTree

# Test headless de PARITE du raccourci boite-boite alignee de
# jeu/Proto/collision.gd::_contact_forme_paire : sur deux boites a orientation
# identite et transform_locale sans rotation, le raccourci (recouvrement d'AABB
# direct) doit rendre EXACTEMENT la meme normale (A->B) et la meme profondeur
# que gjk/epa sur les memes boites. Verrouille la promesse du raccourci -- si
# une divergence apparait, ce test rougit avant tout usage en jeu.
#
# Trois cas geometriques :
#   1. Recouvrement asymetrique sur X -- axe X gagne (plus petit recouvrement).
#   2. Delta 2D : X plus proche que Y -- axe X gagne encore.
#   3. Delta 3D avec demi-tailles differentes -- l'axe de plus petit
#      recouvrement doit correspondre a celui que epa selectionne.

const Verif = preload("res://scripts/verif.gd")
const Collision = preload("res://jeu/Proto/collision.gd")

var _v := Verif.new()

func _init() -> void:
	_lancer.call_deferred()

func _lancer() -> void:
	_cas(Vector3.ZERO, Vector3(0.5, 0.0, 0.0), Vector3(0.4, 0.4, 0.4), Vector3(0.4, 0.4, 0.4), "cas 1 : X asymetrique")
	_cas(Vector3.ZERO, Vector3(0.3, 0.6, 0.0), Vector3(0.4, 0.4, 0.4), Vector3(0.4, 0.4, 0.4), "cas 2 : X gagne face a Y")
	# Cas 3 : delta 3D avec un axe NET (X, recouvrement 0.1) plus petit que les
	# deux autres (0.7 et 0.9). Ecart franc pour eviter la degenerescence numerique
	# de EPA quand deux axes ont exactement le meme recouvrement.
	_cas(Vector3.ZERO, Vector3(0.7, 0.2, 0.1), Vector3(0.5, 0.5, 0.5), Vector3(0.3, 0.4, 0.5), "cas 3 : X net devant Y et Z")
	if _v.echecs() == 0:
		print("OK: raccourci boite-boite -- parite normale/profondeur avec gjk/epa sur 3 cas")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _cas(pa: Vector3, pb: Vector3, ha: Vector3, hb: Vector3, nom: String) -> void:
	var fa := {"type": "boite", "transform_locale": Transform3D.IDENTITY, "parametres": {"demi_taille": ha}}
	var fb := {"type": "boite", "transform_locale": Transform3D.IDENTITY, "parametres": {"demi_taille": hb}}
	var ta := Transform3D(Basis.IDENTITY, pa)
	var tb := Transform3D(Basis.IDENTITY, pb)
	var r_raccourci: Dictionary = Collision.contact_forme_paire(fa, ta, fb, tb)
	var g: Dictionary = Collision.gjk(fa, ta, fb, tb)
	_v.v(g.intersecte, "%s : gjk doit intersecter (pre-condition)" % nom)
	if not g.intersecte:
		return
	var ep: Dictionary = Collision.epa(g.simplexe, fa, ta, fb, tb)
	_v.v(not r_raccourci.is_empty(), "%s : raccourci doit rendre un contact" % nom)
	if r_raccourci.is_empty():
		return
	var n_r: Vector3 = r_raccourci.normale
	var n_e: Vector3 = ep.normale
	var p_r: float = float(r_raccourci.profondeur)
	var p_e: float = float(ep.profondeur)
	# Tolerance : epa converge a 1e-4 (voir _TOL_EPA dans collision.gd), le
	# raccourci est exact. 1e-3 couvre les deux marges.
	_v.v(absf(p_r - p_e) < 1e-3, "%s : profondeur raccourci %.4f vs epa %.4f" % [nom, p_r, p_e])
	_v.v(n_r.distance_to(n_e) < 1e-3, "%s : normale raccourci %s vs epa %s" % [nom, str(n_r), str(n_e)])
