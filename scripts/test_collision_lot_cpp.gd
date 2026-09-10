extends SceneTree

# Parite bit-a-bit CollisionLot (C++) vs jeu/Proto/collision.gd (oracle).
# Trois scenarios : peuplement (6 boites en cluster), multi-formes
# (sphere+boite+capsule+hull, orient tournee), rayons frontiere (r_i != r_j
# a distance dans ]min, max[).

const Verif = preload("res://scripts/verif.gd")
const Collision = preload("res://jeu/Proto/collision.gd")

var _v := Verif.new()

func _init() -> void:
	if not ClassDB.class_exists("CollisionLot"):
		printerr("ECHEC: classe C++ 'CollisionLot' absente -- extension_terrain non chargee ?")
		quit(1)
		return
	_lancer.call_deferred()

func _lancer() -> void:
	_scenario_peuplement()
	_scenario_multi_formes()
	_scenario_rayons_frontiere()
	if _v.echecs() == 0:
		print("OK: CollisionLot == collision.gd, egalite exacte des flottants (peuplement + multi-formes + rayons frontiere)")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _scenario_peuplement() -> void:
	var demi := Vector3(0.4, 0.4, 0.4)
	var f := _forme_boite(demi)
	var pos := [
		Vector3(0.00, 0.00, 0.00),
		Vector3(0.55, 0.00, 0.05),
		Vector3(1.05, 0.00, 0.10),
		Vector3(1.55, 0.00, 0.05),
		Vector3(0.20, 0.00, 0.55),
		Vector3(1.30, 0.00, 0.55),
	]
	var entites: Array = []
	for i in range(pos.size()):
		entites.append(_fab("p%d" % i, pos[i], f, Basis.IDENTITY))
	_executer_et_comparer(entites, "peuplement")

func _scenario_multi_formes() -> void:
	var f_sphere := {"type": "sphere", "transform_locale": Transform3D.IDENTITY, "parametres": {"rayon": 0.4}}
	var f_boite := _forme_boite(Vector3(0.35, 0.5, 0.35))
	var f_capsule := {"type": "capsule", "transform_locale": Transform3D.IDENTITY, "parametres": {"rayon": 0.3, "hauteur": 1.2}}
	var pts: Array[Vector3] = [
		Vector3(0.4, 0.3, 0.4), Vector3(-0.4, 0.3, 0.4),
		Vector3(-0.4, 0.3, -0.4), Vector3(0.4, 0.3, -0.4),
		Vector3(0.0, -0.3, 0.0),
	]
	var f_hull := {"type": "hull", "transform_locale": Transform3D.IDENTITY, "parametres": {"points": pts}}
	var basis_rot := Basis(Vector3.UP, deg_to_rad(30.0))
	var entites: Array = [
		_fab("s0", Vector3(0.0, 0.0, 0.0), f_sphere, Basis.IDENTITY),
		_fab("b0", Vector3(0.65, 0.0, 0.0), f_boite, Basis.IDENTITY),
		_fab("c0", Vector3(0.0, 0.0, 0.8), f_capsule, Basis.IDENTITY),
		_fab("h0", Vector3(0.4, 0.0, 0.9), f_hull, basis_rot),
	]
	_executer_et_comparer(entites, "multi_formes")

func _scenario_rayons_frontiere() -> void:
	# r_i != r_j, distance dans ]min(r_i,r_j), max(r_i,r_j)[.
	# Verrouille que max(r_i, r_j)^2 capte bien la paire cote broadphase.
	var entites: Array = [
		_fab("pt", Vector3.ZERO, _forme_boite(Vector3(0.4, 0.4, 0.4)), Basis.IDENTITY),
		_fab("gd", Vector3(2.5, 0.0, 0.0), _forme_boite(Vector3(1.2, 1.2, 1.2)), Basis.IDENTITY),
	]
	_executer_et_comparer(entites, "rayons_frontiere")

func _executer_et_comparer(entites_original: Array, nom: String) -> void:
	var delta: float = 0.016
	var oracle: Array = _cloner(entites_original)
	var contacts_oracle: Array = Collision.detecter(oracle, delta)
	Collision.resoudre(contacts_oracle, oracle)
	var cible: Array = _cloner(entites_original)
	var cpp = ClassDB.instantiate("CollisionLot")
	var soa: Dictionary = _decomposer(cible, delta)
	var out_det: Dictionary = cpp.detecter(soa)
	var out_res: Dictionary = cpp.resoudre({
		"positions": soa.positions,
		"velocites": soa.velocites,
		"reponses": soa.reponses,
		"masques_r": soa.masques_r,
		"contacts_a": out_det.contacts_a,
		"contacts_b": out_det.contacts_b,
		"contacts_normale": out_det.contacts_normale,
		"contacts_profondeur": out_det.contacts_profondeur,
	})
	var pos_cible: PackedVector3Array = out_res.positions
	for i in range(cible.size()):
		cible[i].position = pos_cible[i]
	var n_oracle: int = contacts_oracle.size()
	var n_cible: int = (out_det.contacts_a as PackedInt32Array).size()
	_v.v(n_oracle == n_cible, "%s : nb contacts oracle=%d cpp=%d" % [nom, n_oracle, n_cible])
	if n_oracle == n_cible:
		var ref: Dictionary = {}
		for c in contacts_oracle:
			var ia: int = _idx(c.a, oracle)
			var ib: int = _idx(c.b, oracle)
			var lo: int = mini(ia, ib)
			var hi: int = maxi(ia, ib)
			ref[Vector2i(lo, hi)] = {
				"normale": c.normale if ia < ib else -c.normale,
				"profondeur": float(c.profondeur),
			}
		var ca: PackedInt32Array = out_det.contacts_a
		var cb: PackedInt32Array = out_det.contacts_b
		var cn: PackedVector3Array = out_det.contacts_normale
		var cp: PackedFloat32Array = out_det.contacts_profondeur
		for k in range(ca.size()):
			var lo: int = mini(ca[k], cb[k])
			var hi: int = maxi(ca[k], cb[k])
			var cle := Vector2i(lo, hi)
			if not ref.has(cle):
				_v.v(false, "%s : paire cpp (%d,%d) absente oracle" % [nom, ca[k], cb[k]])
				continue
			var r: Dictionary = ref[cle]
			var n_cpp: Vector3 = cn[k] if ca[k] < cb[k] else -cn[k]
			_v.v(n_cpp == r.normale, "%s : normale paire (%d,%d) cpp=%s oracle=%s" % [nom, lo, hi, str(n_cpp), str(r.normale)])
			_v.v(cp[k] == r.profondeur, "%s : profondeur paire (%d,%d) cpp=%f oracle=%f" % [nom, lo, hi, cp[k], r.profondeur])
	for i in range(oracle.size()):
		_v.v(oracle[i].position == cible[i].position,
			"%s : position finale entite %d oracle=%s cpp=%s" % [nom, i, str(oracle[i].position), str(cible[i].position)])

func _idx(entite: Dictionary, entites: Array) -> int:
	for k in range(entites.size()):
		if entites[k] == entite:
			return k
	return -1

func _forme_boite(demi: Vector3) -> Dictionary:
	return {"type": "boite", "transform_locale": Transform3D.IDENTITY, "parametres": {"demi_taille": demi}}

func _fab(id: String, pos: Vector3, forme: Dictionary, orient: Basis) -> Dictionary:
	var e := {
		"id": id,
		"position": pos,
		"proprietes": {
			"formes": [forme],
			"velocite": Vector3.ZERO,
			"orientation": orient,
			"masque_collision": 1,
			"masque_reponse": 1,
			"reponse": "bloque",
		},
	}
	e.proprietes["aabb_cache"] = Collision.aabb_forme(forme, Transform3D(orient, pos))
	return e

func _cloner(entites: Array) -> Array:
	var out: Array = []
	for e in entites:
		var p_src: Dictionary = e.proprietes
		var p: Dictionary = {
			"formes": p_src.formes,
			"velocite": p_src.velocite,
			"orientation": p_src.orientation,
			"masque_collision": p_src.masque_collision,
			"masque_reponse": p_src.masque_reponse,
			"reponse": p_src.reponse,
		}
		if p_src.has("aabb_cache"):
			p["aabb_cache"] = p_src.aabb_cache
		out.append({"id": e.id, "position": e.position, "proprietes": p})
	return out

func _decomposer(entites: Array, delta: float) -> Dictionary:
	var N: int = entites.size()
	var positions := PackedVector3Array(); positions.resize(N)
	var velocites := PackedVector3Array(); velocites.resize(N)
	var orientations := PackedFloat32Array(); orientations.resize(N * 9)
	var masques_c := PackedInt32Array(); masques_c.resize(N)
	var masques_r := PackedInt32Array(); masques_r.resize(N)
	var reponses := PackedByteArray(); reponses.resize(N)
	var formes_debut := PackedInt32Array(); formes_debut.resize(N + 1)
	var formes_type := PackedInt32Array()
	var formes_tf_locale := PackedFloat32Array()
	var formes_params := PackedFloat32Array()
	var hull_points := PackedVector3Array()
	var off: int = 0
	for i in range(N):
		var e: Dictionary = entites[i]
		positions[i] = e.position
		var p: Dictionary = e.proprietes
		velocites[i] = p.get("velocite", Vector3.ZERO)
		var b: Basis = p.get("orientation", Basis.IDENTITY)
		orientations[i*9+0] = b.x.x; orientations[i*9+1] = b.y.x; orientations[i*9+2] = b.z.x
		orientations[i*9+3] = b.x.y; orientations[i*9+4] = b.y.y; orientations[i*9+5] = b.z.y
		orientations[i*9+6] = b.x.z; orientations[i*9+7] = b.y.z; orientations[i*9+8] = b.z.z
		masques_c[i] = int(p.get("masque_collision", 0))
		masques_r[i] = int(p.get("masque_reponse", 0))
		reponses[i] = 1 if String(p.get("reponse", "")) == "bloque" else 0
		formes_debut[i] = off
		for f in p.get("formes", []):
			var f_d: Dictionary = f
			var t: String = String(f_d.get("type", ""))
			var ti: int = 0
			match t:
				"sphere": ti = 0
				"boite": ti = 1
				"capsule": ti = 2
				"hull": ti = 3
			formes_type.push_back(ti)
			var tf: Transform3D = f_d.get("transform_locale", Transform3D.IDENTITY)
			var bl: Basis = tf.basis
			formes_tf_locale.push_back(bl.x.x); formes_tf_locale.push_back(bl.y.x); formes_tf_locale.push_back(bl.z.x)
			formes_tf_locale.push_back(bl.x.y); formes_tf_locale.push_back(bl.y.y); formes_tf_locale.push_back(bl.z.y)
			formes_tf_locale.push_back(bl.x.z); formes_tf_locale.push_back(bl.y.z); formes_tf_locale.push_back(bl.z.z)
			formes_tf_locale.push_back(tf.origin.x); formes_tf_locale.push_back(tf.origin.y); formes_tf_locale.push_back(tf.origin.z)
			var par: Dictionary = f_d.get("parametres", {})
			match t:
				"sphere":
					formes_params.push_back(float(par.get("rayon", 0.0)))
					formes_params.push_back(0.0); formes_params.push_back(0.0); formes_params.push_back(0.0)
				"boite":
					var d: Vector3 = par.get("demi_taille", Vector3.ZERO)
					formes_params.push_back(d.x); formes_params.push_back(d.y); formes_params.push_back(d.z)
					formes_params.push_back(0.0)
				"capsule":
					formes_params.push_back(float(par.get("rayon", 0.0)))
					formes_params.push_back(float(par.get("hauteur", 0.0)))
					formes_params.push_back(0.0); formes_params.push_back(0.0)
				"hull":
					var pts: Array = par.get("points", [])
					formes_params.push_back(float(hull_points.size()))
					formes_params.push_back(float(pts.size()))
					formes_params.push_back(0.0); formes_params.push_back(0.0)
					for q in pts:
						hull_points.push_back(q as Vector3)
				_:
					formes_params.push_back(0.0); formes_params.push_back(0.0)
					formes_params.push_back(0.0); formes_params.push_back(0.0)
			off += 1
	formes_debut[N] = off
	return {
		"positions": positions, "velocites": velocites, "orientations": orientations,
		"masques_c": masques_c, "masques_r": masques_r, "reponses": reponses,
		"formes_debut": formes_debut, "formes_type": formes_type,
		"formes_tf_locale": formes_tf_locale, "formes_params": formes_params,
		"hull_points": hull_points, "delta": delta,
	}
