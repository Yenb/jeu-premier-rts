extends SceneTree

# Test headless : la lecture de proprietes.aabb_cache dans
# jeu/Proto/collision.gd::_aabb_balayee donne EXACTEMENT la meme broadphase
# qu'un recalcul via _aabb_entite. Verrouille geste 1 -- si le cache diverge du
# recalcul (par exemple cache pris obsolete au pas precedent), ce test rougit.
#
# Protocole : deux entites-boites recouvrantes, une passe de reference (cache
# rafraichi par detecter lui-meme), une passe apres purge explicite du cache
# (fallback _aabb_entite). Les deux passes doivent rendre le meme nombre de
# contacts, la meme profondeur et la meme normale.

const Verif = preload("res://scripts/verif.gd")
const Monde = preload("res://scripts/monde.gd")
const Collision = preload("res://jeu/Proto/collision.gd")

var _v := Verif.new()

func _init() -> void:
	_lancer.call_deferred()

func _lancer() -> void:
	_executer()
	if _v.echecs() == 0:
		print("OK: cache aabb -- broadphase identique avec cache a jour vs recalcul")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _executer() -> void:
	# Deux passes separees (monde + entites neufs a chaque fois), delta identique.
	# Passe 1 : le cache est ecrit par la pre-passe de detecter. Passe 2 : le cache
	# est explicitement absent, detecter doit le calculer via _aabb_entite. Les
	# contacts rendus doivent etre identiques bit pour bit sur nombre, normale et
	# profondeur.
	var c1: Array = _une_passe(true)
	var c2: Array = _une_passe(false)
	_v.v(c1.size() == c2.size(), "contacts : cache=%d recalcul=%d" % [c1.size(), c2.size()])
	if c1.size() != c2.size() or c1.size() == 0:
		return
	var n1: Vector3 = c1[0].normale
	var n2: Vector3 = c2[0].normale
	var p1: float = float(c1[0].profondeur)
	var p2: float = float(c2[0].profondeur)
	_v.v(absf(p1 - p2) < 1e-6, "profondeur : cache %.6f vs recalcul %.6f" % [p1, p2])
	_v.v(n1.distance_to(n2) < 1e-6, "normale : cache %s vs recalcul %s" % [str(n1), str(n2)])

func _une_passe(avec_cache_seed: bool) -> Array:
	var monde = Monde.new()
	monde.structure_simple = true
	var forme := {"type": "boite", "transform_locale": Transform3D.IDENTITY, "parametres": {"demi_taille": Vector3(0.4, 0.4, 0.4)}}
	var a := _fabriquer("a", Vector3.ZERO, forme, avec_cache_seed)
	var b := _fabriquer("b", Vector3(0.5, 0.0, 0.0), forme, avec_cache_seed)
	monde.ajouter(a, "test_cache", a.position)
	monde.ajouter(b, "test_cache", b.position)
	return Collision.detecter([a, b], 0.016)

func _fabriquer(id: String, pos: Vector3, forme: Dictionary, avec_cache_seed: bool) -> Dictionary:
	var ent := {
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
	if avec_cache_seed:
		ent.proprietes["aabb_cache"] = Collision.aabb_forme(forme, Transform3D(Basis.IDENTITY, pos))
	return ent
