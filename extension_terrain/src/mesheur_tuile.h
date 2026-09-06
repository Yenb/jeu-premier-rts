#ifndef MESHEUR_TUILE_H
#define MESHEUR_TUILE_H

// Meshing d'une tuile en C++, en UN parcours. Le GDScript ne monte pas de
// blob pre-calcule : il passe les dicts BRUTS de la carte + les scalaires.
// Le C++ filtre les dicts a la fenetre tuile+bord (une passe par dict), puis
// tout est natif.
//
// Sortie par item : PackedFloat32Array buffer (16 floats/instance = 12
// transform TRANSFORM_3D + 4 color) + cellules paralleles (3 ints/instance),
// pret pour `MultiMesh.buffer = ...` en UN appel. Plus les derives
// cellules_occl, cellules_teintables, couche_min, couche_max.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class MesheurTuile : public RefCounted {
	GDCLASS(MesheurTuile, RefCounted)

protected:
	static void _bind_methods();

public:
	MesheurTuile();
	~MesheurTuile();

	String bonjour() const;

	// Cles attendues dans `entree` :
	//   -- SCALAIRES --
	//   "origine_col"         Vector2i
	//   "taille"              int
	//   "couche_base"         int
	//   "couches_max"         int (COUCHES_MAXIMALES = 63)
	//   "demi_cote"           int (test d'emprise carte)
	//   "cote"                float
	//   "sommet_base"         int
	//   "masque_base"         int (masque du terrain plein par defaut,
	//                              `carte._masque_base`, retourne quand une
	//                              colonne n'est pas dans `volumes`)
	//   "masque_sous_plein"   int (27 bits)
	//   "max_pv_sous_cube"    int
	//   "item_defaut"         int
	//   "item_limite"         int
	//   "orientation_defaut"  int
	//   "centre_offset"       Vector3
	//
	//   -- TABLES ITEM --
	//   "items_cubiques"      PackedInt32Array
	//   "items_hauteur_cle"   PackedInt32Array + "items_hauteur_val" PackedFloat32Array
	//   "bases_orthogonales"  PackedFloat32Array 216 (24x9)
	//   "mesh_transforms"     Dictionary { int item -> Transform3D } (non-cubiques)
	//
	//   -- DICTS BRUTS DE LA CARTE (passes par reference, non copies par le
	//   GDScript) --
	//   "volumes"             Dictionary[Vector2i, int]  : carte.volumes
	//   "particularites"      Dictionary[Vector3i, int]  : carte.particularites
	//   "masques_sous_cube"   Dictionary[Vector3i, int]  : carte._masques_sous_cube
	//   "pv_sous_cubes"       Dictionary[Vector3i, Dictionary[int,int]] :
	//                                                     carte._pv_sous_cubes
	// Le C++ filtre chacun a la fenetre tuile+bord (une passe par dict) puis
	// travaille sur std::unordered_map natifs.
	//
	// Sortie identique a la version precedente :
	//   "par_forme"           Dict { item -> { buffer, cellules } }
	//   "par_forme_sol"       idem
	//   "par_forme_mini"      idem
	//   "cellules_occl"       PackedInt32Array (triplets)
	//   "cellules_teintables" PackedInt32Array (triplets)
	//   "couche_min"          int
	//   "couche_max"          int
	Dictionary bake_tuile_a(const Dictionary &entree) const;
};

} // namespace godot

#endif // MESHEUR_TUILE_H
