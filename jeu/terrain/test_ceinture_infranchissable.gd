extends SceneTree

# Test manuel :
# godot --headless --script jeu/terrain/test_ceinture_infranchissable.gd
#
# VERROUILLE QUE LA CEINTURE DE verification.tscn ARRETE LES CORPS, sur les quatre
# cotes, quel que soit son implementation (GridMap de cellules OU StaticBody3D de
# quatre boites). Le meme banc sert de baseline AVANT le refactor et de validation
# APRES : il ne connait pas la forme de la ceinture, seulement sa fonction.
#
# Quatre epreuves, chacune visant un bug Godot connu contre les grandes limites
# loin de l'origine (la ceinture est a ~500 m) :
#   A  barriere : un CharacterBody3D lance vers chaque bord a 20 m/s ne sort pas.
#   B  tunneling : un RigidBody3D a 100 m/s (CCD active) vers chaque bord ne
#      franchit pas (issue #39095).
#   C  jitter : un CharacterBody3D colle au mur, pousse PARALLELEMENT, ne doit pas
#      osciller perpendiculairement (issue #75537).
#   D  glissement : le meme doit avancer le long du mur sans se bloquer
#      (issue #69683).
#
# GEOMETRIE DEDUITE DE L'EMPRISE, jamais de map_to_local (murs_limite_boite.faces)
# -- pour valoir sans GridMap. Sur la ceinture GridMap, une verification compare
# la deduction au centrage reel du noeud : si elle diverge, la baseline rougit.
#
# LE VERDICT ATTEND UN NOMBRE FIXE DE PAS, jamais l'immobilite : un corps qui n'a
# pas encore bouge conclurait a tort.
#
# Entree : res://jeu/Proto/verification.tscn (couvert et terrain lointain liberes,
# inutiles a la collision), plus des corps temoins construits ici. Sortie : une
# ligne OK/ECHEC et le code 0/1.
#
# Regles tenues : positions en Vector3. Aucun hasard. Les prints sont des traces.
# Rien de scripts/, data/ ni documents/ n'est ecrit.

const Verif = preload("res://scripts/verif.gd")
const MursBoite = preload("res://jeu/terrain/murs_limite_boite.gd")

const CHEMIN_DEFAUT := "res://jeu/Proto/verification.tscn"
const COUCHES := 22

# La scene a tester : verification.tscn par defaut, surchargee par
# « -- scene=res://... » pour valider les autres cartes refactorees.
var _chemin := CHEMIN_DEFAUT

var _v
var _racine: Node3D
var _murs: Node
var _carte
var _rate := false
# x = mur oriente selon X (Est/Ouest) ; sinon selon Z (Nord/Sud). dir = sens
# exterieur. face = coordonnee de la face interne, remplie apres la deduction.
var _sides := [
	{"nom": "est", "x": true, "dir": 1, "face": 0.0},
	{"nom": "ouest", "x": true, "dir": -1, "face": 0.0},
	{"nom": "nord", "x": false, "dir": 1, "face": 0.0},
	{"nom": "sud", "x": false, "dir": -1, "face": 0.0},
]

func _init() -> void:
	_v = Verif.new()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("scene="):
			_chemin = a.substr("scene=".length())
	_run()

func _run() -> void:
	await _mettre_en_place()
	if _rate:
		_conclure()
		return
	_verifier_geometrie()
	await _test_a()
	await _test_b()
	await _test_c()
	await _test_d()
	_conclure()

func _mettre_en_place() -> void:
	var paquet := load(_chemin) as PackedScene
	_v.v(paquet != null, "%s introuvable" % _chemin)
	if paquet == null:
		_rate = true
		return
	print(">>> scene testee : %s" % _chemin)
	_racine = paquet.instantiate() as Node3D
	_v.v(_racine != null, "la racine de %s n'est pas un Node3D" % _chemin)
	if _racine == null:
		_rate = true
		return
	# Le couvert (prechauffage lourd) et le terrain lointain (streaming) ne
	# servent pas a la collision de la ceinture.
	var couvert := _racine.get_node_or_null("Terrain/Couvert")
	if couvert:
		couvert.free()
	var streame := _racine.get_node_or_null("TerrainStreame")
	if streame:
		streame.free()
	root.add_child(_racine)
	_murs = _racine.get_node_or_null("Limites/Murs")
	_v.v(_murs != null, "aucun noeud Limites/Murs dans la scene")
	if _murs == null:
		_rate = true
		return
	_carte = _murs.get("carte")
	_v.v(_carte != null, "le noeud Limites/Murs n'a pas de carte")
	if _carte == null:
		_rate = true
		return
	await physics_frame
	await physics_frame

func _verifier_geometrie() -> void:
	var f := MursBoite.faces(_carte, COUCHES)
	_sides[0].face = f["interne_max"]
	_sides[1].face = f["interne_min"]
	_sides[2].face = f["interne_max"]
	_sides[3].face = f["interne_min"]
	print("faces deduites : interne_min=%.2f interne_max=%.2f y=[%.2f, %.2f]" % [
		f["interne_min"], f["interne_max"], f["y_bas"], f["y_haut"]])
	if _murs is GridMap:
		var gm := _murs as GridMap
		var c: float = float(_carte.cote)
		var dc: int = int(_carte.demi_cote)
		var centre_est := (gm.transform * gm.map_to_local(Vector3i(dc, 0, 0))).x
		_v.v(absf(centre_est - (f["interne_max"] + c * 0.5)) < 0.01,
			"geometrie X : centre cellule est reel=%.3f deduit=%.3f" % [centre_est, f["interne_max"] + c * 0.5])
		var centre_nord := (gm.transform * gm.map_to_local(Vector3i(0, 0, dc))).z
		_v.v(absf(centre_nord - (f["interne_max"] + c * 0.5)) < 0.01,
			"geometrie Z : centre cellule nord reel=%.3f deduit=%.3f" % [centre_nord, f["interne_max"] + c * 0.5])
		var sommet := (gm.transform * gm.map_to_local(Vector3i(dc, COUCHES - 1, 0))).y + gm.cell_size.y * 0.5
		_v.v(absf(sommet - f["y_haut"]) < 0.01,
			"geometrie Y : sommet ceinture reel=%.3f deduit=%.3f" % [sommet, f["y_haut"]])

func _test_a() -> void:
	for s in _sides:
		var estx: bool = s.x
		var dir: int = s.dir
		var face: float = s.face
		var nom: String = s.nom
		var depart := _point(estx, face - float(dir) * 5.0)
		var body := _perso(depart)
		root.add_child(body)
		await physics_frame
		for i in 180:
			body.velocity = _vel(estx, dir, 20.0)
			body.move_and_slide()
			await physics_frame
		var fin := _coord(body.position, estx)
		var avance := float(dir) * (fin - _coord(depart, estx))
		_v.v(avance > 1.0, "A/%s : le personnage n'a pas avance vers le mur (avance %.2f m)" % [nom, avance])
		var depassement := float(dir) * (fin - face)
		_v.v(depassement <= 1.0,
			"A/%s : ceinture FRANCHIE, coord=%.2f face=%.2f (depassement %.2f m)" % [nom, fin, face, depassement])
		print("A/%s : coord finale %.2f (face %.2f), avance %.2f m" % [nom, fin, face, avance])
		body.queue_free()
		await physics_frame

func _test_b() -> void:
	for s in _sides:
		var estx: bool = s.x
		var dir: int = s.dir
		var face: float = s.face
		var nom: String = s.nom
		var depart := _point(estx, face - float(dir) * 5.0)
		var proj := RigidBody3D.new()
		var forme := CollisionShape3D.new()
		var bille := SphereShape3D.new()
		bille.radius = 0.3
		forme.shape = bille
		proj.add_child(forme)
		proj.gravity_scale = 0.0
		proj.continuous_cd = true
		proj.position = depart
		root.add_child(proj)
		proj.linear_velocity = _vel(estx, dir, 100.0)
		for i in 60:
			await physics_frame
		var fin := _coord(proj.position, estx)
		var avance := float(dir) * (fin - _coord(depart, estx))
		_v.v(avance > 1.0, "B/%s : le projectile n'a pas avance (avance %.2f m)" % [nom, avance])
		var depassement := float(dir) * (fin - face)
		_v.v(depassement <= 1.0,
			"B/%s : projectile a FRANCHI (tunneling), coord=%.2f face=%.2f (depassement %.2f m)" % [nom, fin, face, depassement])
		print("B/%s : coord finale %.2f (face %.2f)" % [nom, fin, face])
		proj.queue_free()
		await physics_frame

func _test_c() -> void:
	var s = _sides[0]  # est
	var estx: bool = s.x
	var dir: int = s.dir
	var face: float = s.face
	var contact: float = face - float(dir) * 0.5
	var body := _perso(_point(estx, contact))
	root.add_child(body)
	await physics_frame
	var perp := []
	for i in 120:
		body.velocity = _vel_para(estx, 10.0)
		body.move_and_slide()
		await physics_frame
		if i >= 40:
			perp.append(_coord(body.position, estx))
	var variance := _variance(perp)
	_v.v(variance < 0.01, "C : jitter perpendiculaire contre le mur, variance %.6f (attendu ~0)" % variance)
	print("C/est : variance perpendiculaire %.6f sur %d frames" % [variance, perp.size()])
	body.queue_free()
	await physics_frame

func _test_d() -> void:
	var s = _sides[0]  # est
	var estx: bool = s.x
	var dir: int = s.dir
	var face: float = s.face
	var contact: float = face - float(dir) * 0.5
	var body := _perso(_point(estx, contact))
	root.add_child(body)
	await physics_frame
	var depart_para := _coord_para(body.position, estx)
	for i in 60:
		body.velocity = _vel_para(estx, 10.0)
		body.move_and_slide()
		await physics_frame
	var avance := absf(_coord_para(body.position, estx) - depart_para)
	_v.v(avance > 8.0, "D : glissement le long du mur bloque, avance %.2f m (attendu ~10)" % avance)
	print("D/est : glissement %.2f m le long du mur" % avance)
	body.queue_free()
	await physics_frame

func _perso(pos: Vector3) -> CharacterBody3D:
	var c := CharacterBody3D.new()
	c.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var forme := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	forme.shape = capsule
	c.add_child(forme)
	c.position = pos
	return c

func _point(x: bool, coord: float) -> Vector3:
	return Vector3(coord, 22.0, 0.0) if x else Vector3(0.0, 22.0, coord)

func _coord(p: Vector3, x: bool) -> float:
	return p.x if x else p.z

func _coord_para(p: Vector3, x: bool) -> float:
	return p.z if x else p.x

func _vel(x: bool, dir: int, v: float) -> Vector3:
	return Vector3(v * dir, 0.0, 0.0) if x else Vector3(0.0, 0.0, v * dir)

func _vel_para(x: bool, v: float) -> Vector3:
	return Vector3(0.0, 0.0, v) if x else Vector3(v, 0.0, 0.0)

func _variance(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := 0.0
	for x in a:
		m += x
	m /= a.size()
	var s := 0.0
	for x in a:
		s += (x - m) * (x - m)
	return s / a.size()

func _conclure() -> void:
	if _racine != null:
		_racine.queue_free()
	if _v.echecs() > 0:
		print("ECHEC: ceinture infranchissable -- %d echec(s)" % _v.echecs())
		quit(1)
		return
	print("OK: ceinture infranchissable -- barriere 4 cotes, pas de tunneling, pas de jitter, glissement libre")
	quit(0)
