extends SceneTree

# Test headless : parite BIT-A-BIT entre :
#   ORACLE -- jeu/Proto/collision.gd::detecter + resoudre (GDScript, verite).
#   CIBLE  -- extension_terrain/CollisionLot::detecter + resoudre (C++).
#
# DEUX scenarios :
# (1) PEUPLEMENT : cluster de 6 boites en recouvrement, orient IDENTITY.
#     Egalite exacte des flottants sur positions finales ET sur chaque contact.
# (2) MULTI-FORMES : sphere + boite + capsule + hull, orient != IDENTITY pour
#     une entite. Prouve que le narrowphase complet est porte, pas seulement
#     la boite. Egalite exacte aussi.

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
	if _v.echecs() == 0:
		print("OK: CollisionLot (C++) detecter+resoudre == collision.gd, egalite exacte des flottants sur peuplement (6 boites) ET multi-formes (sphere+boite+capsule+hull, orient tournee)")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _scenario_peuplement() -> void:
	var demi := Vector3(0.4, 0.4, 0.4)
	var f := {"type": "boite", "transform_locale": Transform3D.IDENTITY, "parametres": {"demi_taille": demi}}
	var positions_init := [
		Vector3(0.00, 0.00, 0.00),
		Vector3(0.55, 0.00, 0.05),
		Vector3(1.05, 0.00, 0.10),
		Vector3(1.55, 0.00, 0.05),
		Vector3(0.20, 0.00, 0.55),
		Vector3(1.30, 0.00, 0.55),
	]
	var entites: Array = []
	for i in range(positions_init.size()):
		entites.append(_fab_generique("p%d" % i, positions_init[i], f, Basis.IDENTITY))
	_executer_et_comparer(entites, "peuplement")

func _scenario_multi_formes() -> void:
	var forme_sphere := {"type": "sphere", "transform_locale": Transform3D.IDENTITY,
			"parametres": {"rayon": 0.4}}
	var forme_boite := {"type": "boite", "transform_locale": Transform3D.IDENTITY,
			"parametres": {"demi_taille": Vector3(0.35, 0.5, 0.35)}}
	var forme_capsule := {"type": "capsule", "transform_locale": Transform3D.IDENTITY,
			"parametres": {"rayon": 0.3, "hauteur": 1.2}}
	var pts_hull: Array[Vector3] = [
		Vector3(0.4, 0.3, 0.4), Vector3(-0.4, 0.3, 0.4),
		Vector3(-0.4, 0.3, -0.4), Vector3(0.4, 0.3, -0.4),
		Vector3(0.0, -0.3, 0.0),
	]
	var forme_hull := {"type": "hull", "transform_locale": Transform3D.IDENTITY,
			"parametres": {"points": pts_hull}}
	var basis_rot := Basis(Vector3.UP, deg_to_rad(30.0))
	var entites: Array = [
		_fab_generique("s0", Vector3(0.0, 0.0, 0.0), forme_sphere, Basis.IDENTITY),
		_fab_generique("b0", Vector3(0.65, 0.0, 0.0), forme_boite, Basis.IDENTITY),
		_fab_generique("c0", Vector3(0.0, 0.0, 0.8), forme_capsule, Basis.IDENTITY),
		_fab_generique("h0", Vector3(0.4, 0.0, 0.9), forme_hull, basis_rot),
	]
	_executer_et_comparer(entites, "multi_formes")

func _executer_et_comparer(entites_original: Array, nom_scenario: String) -> void:
	var delta: float = 0.016
	# ORACLE.
	var entites_oracle: Array = _cloner_entites(entites_original)
	var contacts_oracle: Array = Collision.detecter(entites_oracle, delta)
	Collision.resoudre(contacts_oracle, entites_oracle)
	# CIBLE.
	var entites_cible: Array = _cloner_entites(entites_original)
	var cpp = ClassDB.instantiate("CollisionLot")
	var soa: Dictionary = _decomposer(entites_cible, delta)
	var sortie: Dictionary = cpp.detecter(soa)
	var entree_resoudre := {
		"positions": soa.positions,
		"velocites": soa.velocites,
		"reponses": soa.reponses,
		"masques_r": soa.masques_r,
		"contacts_a": sortie.contacts_a,
		"contacts_b": sortie.contacts_b,
		"contacts_normale": sortie.contacts_normale,
		"contacts_profondeur": sortie.contacts_profondeur,
	}
	var sortie_res: Dictionary = cpp.resoudre(entree_resoudre)
	var positions_cible: PackedVector3Array = sortie_res.positions
	for i in range(entites_cible.size()):
		entites_cible[i].position = positions_cible[i]
	# --- Comparaisons ---
	_v.v(contacts_oracle.size() == (sortie.contacts_a as PackedInt32Array).size(),
		"%s : nb contacts oracle=%d cpp=%d" % [nom_scenario, contacts_oracle.size(), (sortie.contacts_a as PackedInt32Array).size()])
	if contacts_oracle.size() == (sortie.contacts_a as PackedInt32Array).size():
		var oracle_par_paire: Dictionary = {}
		for c in contacts_oracle:
			var ia: int = _index_de(c.a, entites_oracle)
			var ib: int = _index_de(c.b, entites_oracle)
			var lo: int = mini(ia, ib)
			var hi: int = maxi(ia, ib)
			var normale_lohi: Vector3 = c.normale if ia < ib else -c.normale
			oracle_par_paire[Vector2i(lo, hi)] = {
				"normale": normale_lohi,
				"profondeur": float(c.profondeur),
			}
		var ca_arr: PackedInt32Array = sortie.contacts_a
		var cb_arr: PackedInt32Array = sortie.contacts_b
		var cn_arr: PackedVector3Array = sortie.contacts_normale
		var cp_arr: PackedFloat32Array = sortie.contacts_profondeur
		for k in range(ca_arr.size()):
			var ia_c: int = ca_arr[k]
			var ib_c: int = cb_arr[k]
			var lo: int = mini(ia_c, ib_c)
			var hi: int = maxi(ia_c, ib_c)
			var cle := Vector2i(lo, hi)
			if not oracle_par_paire.has(cle):
				_v.v(false, "%s : paire cpp (%d,%d) absente cote oracle" % [nom_scenario, ia_c, ib_c])
				continue
			var ref: Dictionary = oracle_par_paire[cle]
			var n_cpp: Vector3 = cn_arr[k] if ia_c < ib_c else -cn_arr[k]
			_v.v(n_cpp == ref.normale,
				"%s : paire (%d,%d) normale cpp=%s oracle=%s" % [nom_scenario, lo, hi, str(n_cpp), str(ref.normale)])
			_v.v(cp_arr[k] == ref.profondeur,
				"%s : paire (%d,%d) profondeur cpp=%f oracle=%f" % [nom_scenario, lo, hi, cp_arr[k], ref.profondeur])
	for i in range(entites_oracle.size()):
		var pos_o: Vector3 = entites_oracle[i].position
		var pos_c: Vector3 = entites_cible[i].position
		_v.v(pos_o == pos_c,
			"%s : position finale entite %d oracle=%s cpp=%s" % [nom_scenario, i, str(pos_o), str(pos_c)])

func _index_de(entite: Dictionary, entites: Array) -> int:
	for k in range(entites.size()):
		if entites[k] == entite:
			return k
	return -1

func _fab_generique(id: String, pos: Vector3, forme: Dictionary, orient: Basis) -> Dictionary:
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

func _cloner_entites(entites: Array) -> Array:
	var out: Array = []
	for e in entites:
		var pr_src: Dictionary = e.proprietes
		var pr: Dictionary = {
			"formes": pr_src.formes,
			"velocite": pr_src.velocite,
			"orientation": pr_src.orientation,
			"masque_collision": pr_src.masque_collision,
			"masque_reponse": pr_src.masque_reponse,
			"reponse": pr_src.reponse,
		}
		if pr_src.has("aabb_cache"):
			pr["aabb_cache"] = pr_src.aabb_cache
		out.append({"id": e.id, "position": e.position, "proprietes": pr})
	return out

# Decompose un Array de Dict-entites en colonnes SoA pour CollisionLot.
# Pool de formes plat, une entree par (entite, i_forme) -- pas de dedup.
func _decomposer(entites: Array, delta: float) -> Dictionary:
	var N: int = entites.size()
	var positions := PackedVector3Array()
	positions.resize(N)
	var velocites := PackedVector3Array()
	velocites.resize(N)
	var orientations := PackedFloat32Array()
	orientations.resize(N * 9)
	var masques_c := PackedInt32Array()
	masques_c.resize(N)
	var masques_r := PackedInt32Array()
	masques_r.resize(N)
	var reponses := PackedByteArray()
	reponses.resize(N)
	var formes_debut := PackedInt32Array()
	formes_debut.resize(N + 1)
	var formes_type := PackedInt32Array()
	var formes_tf_locale := PackedFloat32Array()
	var formes_params := PackedFloat32Array()
	var hull_points := PackedVector3Array()
	var offset: int = 0
	for i in range(N):
		var e: Dictionary = entites[i]
		positions[i] = e.position
		var p: Dictionary = e.proprietes
		velocites[i] = p.get("velocite", Vector3.ZERO)
		var b: Basis = p.get("orientation", Basis.IDENTITY)
		# Basis row-major (b.rows[i] cote C++) :
		#   row 0 = (b.x.x, b.y.x, b.z.x)  (colonne .x contient les valeurs de x en chaque ligne)
		orientations[i * 9 + 0] = b.x.x
		orientations[i * 9 + 1] = b.y.x
		orientations[i * 9 + 2] = b.z.x
		orientations[i * 9 + 3] = b.x.y
		orientations[i * 9 + 4] = b.y.y
		orientations[i * 9 + 5] = b.z.y
		orientations[i * 9 + 6] = b.x.z
		orientations[i * 9 + 7] = b.y.z
		orientations[i * 9 + 8] = b.z.z
		masques_c[i] = int(p.get("masque_collision", 0))
		masques_r[i] = int(p.get("masque_reponse", 0))
		reponses[i] = 1 if String(p.get("reponse", "")) == "bloque" else 0
		formes_debut[i] = offset
		var formes: Array = p.get("formes", [])
		for f in formes:
			var f_dict: Dictionary = f
			var t: String = String(f_dict.get("type", ""))
			var type_int: int = 0
			match t:
				"sphere": type_int = 0
				"boite": type_int = 1
				"capsule": type_int = 2
				"hull": type_int = 3
			formes_type.push_back(type_int)
			var tf_l: Transform3D = f_dict.get("transform_locale", Transform3D.IDENTITY)
			var bl: Basis = tf_l.basis
			formes_tf_locale.push_back(bl.x.x)
			formes_tf_locale.push_back(bl.y.x)
			formes_tf_locale.push_back(bl.z.x)
			formes_tf_locale.push_back(bl.x.y)
			formes_tf_locale.push_back(bl.y.y)
			formes_tf_locale.push_back(bl.z.y)
			formes_tf_locale.push_back(bl.x.z)
			formes_tf_locale.push_back(bl.y.z)
			formes_tf_locale.push_back(bl.z.z)
			formes_tf_locale.push_back(tf_l.origin.x)
			formes_tf_locale.push_back(tf_l.origin.y)
			formes_tf_locale.push_back(tf_l.origin.z)
			var params: Dictionary = f_dict.get("parametres", {})
			match t:
				"sphere":
					formes_params.push_back(float(params.get("rayon", 0.0)))
					formes_params.push_back(0.0)
					formes_params.push_back(0.0)
					formes_params.push_back(0.0)
				"boite":
					var d: Vector3 = params.get("demi_taille", Vector3.ZERO)
					formes_params.push_back(d.x)
					formes_params.push_back(d.y)
					formes_params.push_back(d.z)
					formes_params.push_back(0.0)
				"capsule":
					formes_params.push_back(float(params.get("rayon", 0.0)))
					formes_params.push_back(float(params.get("hauteur", 0.0)))
					formes_params.push_back(0.0)
					formes_params.push_back(0.0)
				"hull":
					var pts: Array = params.get("points", [])
					formes_params.push_back(float(hull_points.size()))
					formes_params.push_back(float(pts.size()))
					formes_params.push_back(0.0)
					formes_params.push_back(0.0)
					for q in pts:
						hull_points.push_back(q as Vector3)
				_:
					formes_params.push_back(0.0)
					formes_params.push_back(0.0)
					formes_params.push_back(0.0)
					formes_params.push_back(0.0)
			offset += 1
	formes_debut[N] = offset
	return {
		"positions": positions,
		"velocites": velocites,
		"orientations": orientations,
		"masques_c": masques_c,
		"masques_r": masques_r,
		"reponses": reponses,
		"formes_debut": formes_debut,
		"formes_type": formes_type,
		"formes_tf_locale": formes_tf_locale,
		"formes_params": formes_params,
		"hull_points": hull_points,
		"delta": delta,
	}
