extends SceneTree

# Test headless : le raccourci boite-alignee de aabb_forme
# (jeu/Proto/collision.gd) rend une AABB EGALE (position et size) a la boucle
# generique 6-supports pour une "boite" a basis identite. Une rotation de basis
# (boite tournee) ou tout autre type (capsule) doit continuer a passer par la
# boucle generique -- ce test le prouve indirectement en verifiant que l'AABB
# reste correcte (tailles attendues calculees a la main).

const Verif = preload("res://scripts/verif.gd")
const Collision = preload("res://jeu/Proto/collision.gd")

var _v := Verif.new()

func _init() -> void:
	_lancer.call_deferred()

func _lancer() -> void:
	_cas_boite_alignee()
	_cas_boite_tournee()
	_cas_capsule()
	if _v.echecs() == 0:
		print("OK: aabb_forme -- raccourci boite-alignee = AABB directe, boite tournee et capsule passent par la boucle 6-supports")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

# Boite alignee : raccourci actif. AABB doit etre EXACTEMENT AABB(pos - h, h*2).
func _cas_boite_alignee() -> void:
	var h := Vector3(0.4, 0.3, 0.5)
	var pos := Vector3(2.0, 1.0, -3.0)
	var forme := {"type": "boite", "transform_locale": Transform3D.IDENTITY, "parametres": {"demi_taille": h}}
	var tf := Transform3D(Basis.IDENTITY, pos)
	var aabb := Collision.aabb_forme(forme, tf)
	var attendu := AABB(pos - h, h * 2.0)
	_v.v(aabb.position.distance_to(attendu.position) < 1e-6, "boite alignee position : recu %s attendu %s" % [str(aabb.position), str(attendu.position)])
	_v.v(aabb.size.distance_to(attendu.size) < 1e-6, "boite alignee size : recu %s attendu %s" % [str(aabb.size), str(attendu.size)])

# Boite tournee 45deg sur Y : le raccourci ne s'applique pas (basis != IDENTITY),
# la boucle 6-supports tourne. Demi-taille projetee sur X et Z = 0.4 * sqrt(2).
func _cas_boite_tournee() -> void:
	var h := Vector3(0.4, 0.4, 0.4)
	var forme := {"type": "boite", "transform_locale": Transform3D.IDENTITY, "parametres": {"demi_taille": h}}
	var basis_rot := Basis(Vector3.UP, deg_to_rad(45.0))
	var tf := Transform3D(basis_rot, Vector3.ZERO)
	var aabb := Collision.aabb_forme(forme, tf)
	var attendu_h := 0.4 * sqrt(2.0)
	_v.v(absf(aabb.size.x - 2.0 * attendu_h) < 1e-4, "boite tournee size.x %.4f attendu %.4f" % [aabb.size.x, 2.0 * attendu_h])
	_v.v(absf(aabb.size.y - 0.8) < 1e-4, "boite tournee size.y %.4f attendu 0.8" % aabb.size.y)
	_v.v(absf(aabb.size.z - 2.0 * attendu_h) < 1e-4, "boite tournee size.z %.4f attendu %.4f" % [aabb.size.z, 2.0 * attendu_h])

# Capsule rayon 0.5 hauteur 2.0 axe Y : boucle 6-supports. Size attendue
# (1.0, 2.0, 1.0).
func _cas_capsule() -> void:
	var forme := {"type": "capsule", "transform_locale": Transform3D.IDENTITY, "parametres": {"rayon": 0.5, "hauteur": 2.0}}
	var tf := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var aabb := Collision.aabb_forme(forme, tf)
	_v.v(absf(aabb.size.x - 1.0) < 1e-4, "capsule size.x %.4f attendu 1.0" % aabb.size.x)
	_v.v(absf(aabb.size.y - 2.0) < 1e-4, "capsule size.y %.4f attendu 2.0" % aabb.size.y)
	_v.v(absf(aabb.size.z - 1.0) < 1e-4, "capsule size.z %.4f attendu 1.0" % aabb.size.z)
