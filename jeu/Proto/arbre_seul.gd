@tool
extends MeshInstance3D

# UN ARBRE, ET RIEN D'AUTRE. Ce noeud EST l'arbre : il pose sur lui-meme un
# maillage tronc + canopee, stylise et bas en polygones. Aucune simulation,
# aucun couvert, aucune dependance -- une piece isolee, faite pour etre
# regardee et refaite a la main.
#
# ENTREE : `hauteur` (metres) et `couleur` de la canopee, regles a l'inspecteur.
# SORTIE : `self.mesh`, un ArrayMesh a deux surfaces (tronc brun, canopee de la
# couleur donnee).
#
# LA FORME : un CylinderMesh de Godot pour le tronc, un second a top_radius=0
# pour le cone de canopee. Segments bas expres (6 cotes) -- une silhouette
# lisible de loin ne demande pas davantage.
#
# @tool : l'arbre se dessine dans l'editeur des qu'on ouvre la scene, pas
# seulement au lancement.

@export var hauteur: float = 6.0:
	set(v):
		hauteur = v
		_reconstruire()
@export var couleur: Color = Color(0.32, 0.55, 0.24):
	set(v):
		couleur = v
		_reconstruire()

const SEGMENTS := 6
const ANNEAUX := 1

func _ready() -> void:
	_reconstruire()

func _reconstruire() -> void:
	mesh = _maillage_arbre(hauteur, couleur)

# TRONC : 30 % de la hauteur, rayon 6 %, base au sol. CANOPEE : les 70 %
# restants, rayon a la base 23 %, pointe en haut. Un CylinderMesh a son
# origine au centre -- on decale ses sommets pour poser la base a y = 0.
func _maillage_arbre(h: float, coul: Color) -> ArrayMesh:
	var maillage := ArrayMesh.new()
	if h <= 0.0:
		return maillage

	var h_tronc := h * 0.30
	var r_tronc := h * 0.06
	var h_canopee := h * 0.70
	var r_canopee := h * 0.23

	var tronc := CylinderMesh.new()
	tronc.top_radius = r_tronc
	tronc.bottom_radius = r_tronc
	tronc.height = h_tronc
	tronc.radial_segments = SEGMENTS
	tronc.rings = ANNEAUX
	var arrays_tronc := tronc.surface_get_arrays(0)
	_decaler_vertices(arrays_tronc, h_tronc * 0.5)
	var mat_tronc := StandardMaterial3D.new()
	mat_tronc.albedo_color = Color(0.35, 0.22, 0.13)
	maillage.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_tronc)
	maillage.surface_set_material(0, mat_tronc)

	var canopee := CylinderMesh.new()
	canopee.top_radius = 0.0
	canopee.bottom_radius = r_canopee
	canopee.height = h_canopee
	canopee.radial_segments = SEGMENTS
	canopee.rings = ANNEAUX
	var arrays_canopee := canopee.surface_get_arrays(0)
	_decaler_vertices(arrays_canopee, h_tronc + h_canopee * 0.5)
	var mat_canopee := StandardMaterial3D.new()
	mat_canopee.albedo_color = coul
	maillage.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_canopee)
	maillage.surface_set_material(1, mat_canopee)

	return maillage

func _decaler_vertices(arrays: Array, dy: float) -> void:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(v.size()):
		v[i] += Vector3(0.0, dy, 0.0)
	arrays[Mesh.ARRAY_VERTEX] = v
