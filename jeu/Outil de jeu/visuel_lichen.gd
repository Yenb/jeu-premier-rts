extends Node3D

# BANC "test_ennemi2 Mother box" -- LE VISUEL DE LICHEN : meme role que
# visuel_herbe.gd, taille et couleur du lichen. Un seul MultiMeshInstance3D
# rend tous les lichens en un draw call.

const MAX_INSTANCES := 200000
const TAILLE_CUBE := 0.30
const COULEUR := Color(0.15, 0.55, 0.5, 1)

var _multimesh: MultiMesh
var _mmi: MultiMeshInstance3D
var _libres: Array[int] = []

func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(TAILLE_CUBE, TAILLE_CUBE, TAILLE_CUBE)
	var materiau := StandardMaterial3D.new()
	materiau.albedo_color = COULEUR
	mesh.material = materiau

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = mesh
	_multimesh.instance_count = MAX_INSTANCES

	var t_cache := Transform3D(Basis(), Vector3(0.0, -10000.0, 0.0))
	for i in range(MAX_INSTANCES):
		_multimesh.set_instance_transform(i, t_cache)
		_libres.append(i)

	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _multimesh
	# CUSTOM_AABB LARGE (voir visuel_herbe.gd, meme raison).
	_mmi.custom_aabb = AABB(Vector3(-500, -200, -500), Vector3(1000, 400, 1000))
	add_child(_mmi)
	add_to_group("visuel_lichen")

func inscrire(pos: Vector3) -> int:
	if _libres.is_empty():
		push_warning("visuel_lichen.gd : MAX_INSTANCES atteint (%d), nouveau cube invisible" % MAX_INSTANCES)
		return -1
	var i: int = _libres.pop_back()
	_multimesh.set_instance_transform(i, Transform3D(Basis(), pos))
	return i

func retirer(index: int) -> void:
	if index < 0:
		return
	_multimesh.set_instance_transform(index, Transform3D(Basis(), Vector3(0.0, -10000.0, 0.0)))
	_libres.append(index)
