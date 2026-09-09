extends SceneTree

# Test headless de reference bit-a-bit pour Collision.detecter + Collision.resoudre.
# Le split tick -> detecter/resoudre ne touche aucun calcul (broadphase, narrowphase,
# swept, resolution identiques) : les positions finales d'un scenario connu sont
# strictement egales aux valeurs figees ici. Scenario : cluster de 6 boites reparties
# sur plusieurs cellules de la broadphase locale. Toute divergence future signale
# qu'un calcul a bouge, quelle qu'en soit la cause.

const Verif = preload("res://scripts/verif.gd")
const Monde = preload("res://scripts/monde.gd")
const Collision = preload("res://jeu/Proto/collision.gd")

var _v := Verif.new()

# Positions finales attendues apres UN Collision.detecter + Collision.resoudre
# sur le cluster (delta 0.016). Capturees avec l'ancien tick+resoudre. Ordre
# stricte des indices : p0..p5.
const POS_FINALES := [
	Vector3(-0.125000000, 0.000000000, -0.125000000),
	Vector3(0.499999940, 0.000000000, -0.100000009),
	Vector3(1.050000072, 0.000000000, -0.074999996),
	Vector3(1.699999928, 0.000000000, -0.100000009),
	Vector3(0.200000003, 0.000000000, 0.825000048),
	Vector3(1.325000048, 0.000000000, 0.875000000),
]
const CONTACTS_ATTENDUS := 8

func _init() -> void:
	_lancer.call_deferred()

func _lancer() -> void:
	_executer()
	if _v.echecs() == 0:
		print("OK: parite detecter+resoudre -- 8 contacts, 6 positions finales bit-a-bit (scenario cluster 6 boites)")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _executer() -> void:
	var monde = Monde.new()
	monde.structure_simple = true
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
	var i := 0
	while i < positions_init.size():
		var e := _fab("p%d" % i, positions_init[i], f)
		monde.ajouter(e, "peuplement_coll", e.position)
		entites.append(e)
		i += 1
	var contacts: Array = Collision.detecter(entites, 0.016)
	_v.v(contacts.size() == CONTACTS_ATTENDUS,
		"detecter : attendu %d contacts, obtenu %d" % [CONTACTS_ATTENDUS, contacts.size()])
	Collision.resoudre(contacts, entites)
	# Egalite EXACTE des flottants : le split ne bouge aucun calcul, donc les
	# positions finales sont bit-a-bit celles de la capture.
	for j in range(entites.size()):
		var obtenu: Vector3 = entites[j].position
		var attendu: Vector3 = POS_FINALES[j]
		_v.v(obtenu == attendu,
			"p%d : obtenu %s attendu %s" % [j, str(obtenu), str(attendu)])

func _fab(id: String, pos: Vector3, forme: Dictionary) -> Dictionary:
	var e := {
		"id": id,
		"position": pos,
		"proprietes": {
			"formes": [forme],
			"velocite": Vector3.ZERO,
			"orientation": Basis.IDENTITY,
			"masque_collision": 1,
			"masque_reponse": 1,
			"reponse": "bloque",
		},
	}
	e.proprietes["aabb_cache"] = Collision.aabb_forme(forme, Transform3D(Basis.IDENTITY, pos))
	return e
