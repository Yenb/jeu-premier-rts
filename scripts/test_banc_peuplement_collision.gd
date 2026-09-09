extends SceneTree

# Test headless : jeu/Proto/collision.gd applique a deux Dict-entites en
# recouvrement les ecarte de leur profondeur -- verrouille le contrat cable
# par jeu/bancs/banc_peuplement.gd (Collision.detecter + Collision.resoudre sur
# _entites_collision, sortie mute directement entite.position).
#
# Deux boites de demi_taille 0.4 sur X, positionnees a (0,0,0) et (0.5,0,0).
# Recouvrement geometrique sur X : 0.4 + 0.4 - 0.5 = 0.3. Les deux entites ont
# velocite ZERO -> Collision.resoudre partage 50/50 -> chaque entite bouge de
# 0.15 le long de la normale. Distance finale attendue : 0.8 (sum des
# demi_taille), soit ecart >= profondeur.

const Verif = preload("res://scripts/verif.gd")
const Monde = preload("res://scripts/monde.gd")
const Collision = preload("res://jeu/Proto/collision.gd")

var _v := Verif.new()

func _init() -> void:
	_lancer.call_deferred()

func _lancer() -> void:
	_executer()
	if _v.echecs() == 0:
		print("OK: banc_peuplement collision -- deux agents en recouvrement ecartes par Collision.detecter + resoudre (aucune physique Godot)")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)

func _executer() -> void:
	var monde = Monde.new()
	monde.structure_simple = true
	var demi := Vector3(0.4, 0.4, 0.4)
	var forme_boite := {
		"type": "boite",
		"transform_locale": Transform3D.IDENTITY,
		"parametres": {"demi_taille": demi},
	}
	var a := _fabriquer_entite("a", Vector3.ZERO, forme_boite)
	var b := _fabriquer_entite("b", Vector3(0.5, 0.0, 0.0), forme_boite)
	monde.ajouter(a, "peuplement_coll", a.position)
	monde.ajouter(b, "peuplement_coll", b.position)

	# Pre-condition : distance 0.5, profondeur de recouvrement 0.3.
	var d_avant: float = (a.position as Vector3).distance_to(b.position as Vector3)
	_v.v(is_equal_approx(d_avant, 0.5), "pre : distance != 0.5 (obtenu %.4f)" % d_avant)

	# Une passe de collision : broadphase + narrowphase GJK/EPA + resoudre.
	var contacts: Array = Collision.detecter([a, b], 0.016)
	_v.v(contacts.size() == 1, "detecter : attendu 1 contact, obtenu %d" % contacts.size())
	if contacts.size() >= 1:
		var c: Dictionary = contacts[0]
		_v.v(float(c.get("profondeur", 0.0)) >= 0.29, "detecter : profondeur < 0.29 (obtenu %.4f)" % float(c.get("profondeur", 0.0)))

	Collision.resoudre(contacts, [a, b])

	# Post-condition : les deux entites doivent etre ecartees d'AU MOINS la
	# profondeur (0.3). Attendu ~0.8 = 2 * demi_taille.x (50/50 sur normale +X).
	var d_apres: float = (a.position as Vector3).distance_to(b.position as Vector3)
	_v.v(d_apres >= 0.5 + 0.3 - 1e-4, "post : distance %.4f < 0.5 + profondeur 0.3 (attendu >= 0.8)" % d_apres)
	# Recouvrement effectif = max(0, 0.8 - distance). Doit etre nul (a epsilon pres).
	var recouvrement: float = maxf(0.0, 0.8 - d_apres)
	_v.v(recouvrement < 1e-3, "post : recouvrement residuel %.4f (attendu ~0)" % recouvrement)

func _fabriquer_entite(id: String, pos: Vector3, forme: Dictionary) -> Dictionary:
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
	ent.proprietes["aabb_cache"] = Collision.aabb_forme(forme, Transform3D(Basis.IDENTITY, pos))
	return ent
