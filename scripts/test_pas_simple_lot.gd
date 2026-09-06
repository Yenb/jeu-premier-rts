extends SceneTree

# Test headless :
# godot --headless --script scripts/test_pas_simple_lot.gd
#
# Verrouille la PARITE image par image entre Mouvement.pas_simple (chemin par
# agent, Dict) et Mouvement.pas_simple_lot (chemin batch, colonnes typees).
# Meme entrees initiales, meme carte, meme delta, meme gravite -> memes
# positions / velocites / au_sols apres N frames. C'est ce qui garantit que
# l'aplatissement du round 8 ne change pas le comportement observable.
#
# Trois agents avec desirees distinctes (arrete, mouvement +X, mouvement -Z),
# 10 frames a dt=1/60. Comparaison bit a bit sur position et velocite, egalite
# stricte sur au_sol.

const Verif = preload("res://scripts/verif.gd")
const Mouvement = preload("res://scripts/mouvement_kinematic.gd")
const CarteTerrain = preload("res://jeu/terrain/carte_terrain.gd")

var _v := Verif.new()


func _init() -> void:
	_executer()
	if _v.echecs() == 0:
		print("OK: pas_simple vs pas_simple_lot -- parite bit-a-bit sur 10 frames, 3 agents")
		quit(0)
	else:
		printerr("ECHEC: %d assertion(s) fausse(s)" % _v.echecs())
		quit(1)


func _executer() -> void:
	var carte: Resource = CarteTerrain.new()
	var delta: float = 1.0 / 60.0
	var gravite: float = 18.0
	var n: int = 3
	var frames: int = 10

	# Etat initial commun.
	var positions_init: PackedVector3Array = PackedVector3Array([
		Vector3(0.0, 14.0, 0.0),      # au sol pile
		Vector3(2.0, 14.4, 2.0),      # au sol + 0.4 (comme le banc)
		Vector3(-3.0, 20.0, -3.0),    # en l'air, tombera
	])
	var velocites_init: PackedVector3Array = PackedVector3Array([
		Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
	])
	var desirees: PackedVector3Array = PackedVector3Array([
		Vector3.ZERO,                 # arrete
		Vector3(1.0, 0.0, 0.0),       # marche vers +X
		Vector3(0.0, 0.0, -1.0),      # marche vers -Z
	])
	var au_sols_init: PackedByteArray = PackedByteArray([0, 0, 0])

	# ---- CHEMIN 1 : pas_simple par agent (Dict), sur copies independantes.
	var entites: Array = []
	for i in range(n):
		entites.append({
			"id": "test_%d" % i,
			"position": positions_init[i],
			"proprietes": {
				"velocite": velocites_init[i],
				"velocite_desiree_horizontale": desirees[i],
				"au_sol": bool(au_sols_init[i]),
				"gravite": gravite,
			},
		})
	for _f in range(frames):
		for i in range(n):
			Mouvement.pas_simple(entites[i], delta, null, carte)

	# ---- CHEMIN 2 : pas_simple_lot sur colonnes, meme etat initial.
	var cols := {
		"position": positions_init.duplicate(),
		"velocite": velocites_init.duplicate(),
		"desiree": desirees.duplicate(),
		"au_sol": au_sols_init.duplicate(),
	}
	for _f in range(frames):
		Mouvement.pas_simple_lot(cols, n, gravite, delta, carte)

	# ---- COMPARAISON.
	var positions_lot: PackedVector3Array = cols.position
	var velocites_lot: PackedVector3Array = cols.velocite
	var au_sols_lot: PackedByteArray = cols.au_sol
	for i in range(n):
		var pos_ref: Vector3 = entites[i].position
		var pos_lot: Vector3 = positions_lot[i]
		_v.v(pos_ref == pos_lot,
			"agent %d : position divergent (par-agent %s vs lot %s)" % [i, str(pos_ref), str(pos_lot)])
		var ve_ref: Vector3 = entites[i].proprietes.velocite
		var ve_lot: Vector3 = velocites_lot[i]
		_v.v(ve_ref == ve_lot,
			"agent %d : velocite divergent (par-agent %s vs lot %s)" % [i, str(ve_ref), str(ve_lot)])
		var au_ref: bool = bool(entites[i].proprietes.au_sol)
		var au_lot: bool = au_sols_lot[i] != 0
		_v.v(au_ref == au_lot,
			"agent %d : au_sol divergent (par-agent %s vs lot %s)" % [i, str(au_ref), str(au_lot)])
