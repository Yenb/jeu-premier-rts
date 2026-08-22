extends Node3D

# BANC "test_ennemi2 Mother box" -- LE VISUEL D'HERBE : un seul
# MultiMeshInstance3D qui rend TOUS les cubes d'herbe en UN draw call, au
# lieu d'un MeshInstance3D par cube. Chaque cube_herbe.gd n'a plus son
# mesh -- il s'inscrit ici a sa naissance, se retire a sa mort.
#
# POURQUOI : a 1000 cubes, la version un-mesh-par-cube fait 1000 draw calls
# et pese 5 Ko par nœud (mesh + node overhead). Le MultiMesh fait 1 draw
# call et un transform par instance dans un buffer GPU -- gain typique
# ~100x sur le GPU (voir doc Godot "Optimization using MultiMeshes").
#
# FREE-LIST : le MultiMesh de Godot exige un `instance_count` fixe. On
# alloue MAX_INSTANCES slots a l'init et on maintient une liste des index
# libres. Naissance = pop de la liste et pose transform. Mort = push sur
# la liste et cache le transform (scale zero). Un cube qui meurt libere
# son slot, un cube qui nait le reprend. La memoire est constante, jamais
# de re-allocation.
#
# SI MAX_INSTANCES EST DEPASSE : nouveau cube ne recoit pas de slot, reste
# invisible. La simulation continue normalement (le cube existe, il pond
# et meurt), seul le rendu manque. Non bloquant. A monter si le cas se
# produit -- alarme dans push_warning.

const MAX_INSTANCES := 200000
const TAILLE_CUBE := 0.06
const COULEUR := Color(0.15, 0.75, 0.2, 1)

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

	# INITIALISATION DE LA FREE-LIST : tous les indices libres au demarrage,
	# et toutes les instances CACHEES par scale zero. Sans ca, les 10000
	# instances apparaissent a l'origine (superposees en un pate).
	var t_cache := Transform3D(Basis(), Vector3(0.0, -10000.0, 0.0))
	for i in range(MAX_INSTANCES):
		_multimesh.set_instance_transform(i, t_cache)
		_libres.append(i)

	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _multimesh
	# CUSTOM_AABB LARGE : sans ça, Godot calcule l'AABB depuis les transforms
	# du buffer. Toutes les instances non-inscrites sont a scale(0) a
	# l'origine, donc l'AABB automatique se concentre pres de (0,0,0). Un
	# joueur ailleurs sur la carte ne voit rien -- le MultiMesh est culle
	# hors du champ. On force une boite englobante qui couvre toute la zone
	# de jeu possible (± 500 m en xz, ± 200 m en y).
	_mmi.custom_aabb = AABB(Vector3(-500, -200, -500), Vector3(1000, 400, 1000))
	add_child(_mmi)
	add_to_group("visuel_herbe")

# Un cube nait a `pos` : recoit un index libre. Rend -1 si plus de slots
# (saturation du visuel, la simulation continue mais le cube reste
# invisible).
func inscrire(pos: Vector3) -> int:
	if _libres.is_empty():
		push_warning("visuel_herbe.gd : MAX_INSTANCES atteint (%d), nouveau cube invisible" % MAX_INSTANCES)
		return -1
	var i: int = _libres.pop_back()
	_multimesh.set_instance_transform(i, Transform3D(Basis(), pos))
	return i

# Un cube meurt : rend son slot a la liste libre, cache son transform.
# Passe -1 si le cube n'avait pas de slot (visuel sature a sa naissance).
func retirer(index: int) -> void:
	if index < 0:
		return
	_multimesh.set_instance_transform(index, Transform3D(Basis(), Vector3(0.0, -10000.0, 0.0)))
	_libres.append(index)
