#ifndef MESHEUR_TUILE_H
#define MESHEUR_TUILE_H

// Meshing d'une tuile en C++, en UN parcours. Catalogues d'items partages
// (invariants inter-tuiles) montes UNE fois via `configurer_catalogues` au
// _ready du rendu, puis les tuiles n'envoient plus que leurs donnees
// specifiques.
//
// Sortie par item : PackedFloat32Array buffer (16 floats/instance = 12
// transform TRANSFORM_3D + 4 color), pret pour `MultiMesh.buffer = ...`
// en UN appel natif cote GDScript. Plus les derives cellules_occl,
// couche_min/max, et l'INDEX teinte pret-a-l'emploi
// (teinte_candidats_normal / _sol : 6-tuples (item, x, y, z, idx_start,
// count) par cellule cubique propre visible, evite le re-parcours du buffer
// cote GDScript).

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace godot {

class MesheurTuile : public RefCounted {
	GDCLASS(MesheurTuile, RefCounted)

	// Catalogues d'items invariants entre tuiles. Montes une fois par
	// `configurer_catalogues`. Utilises tels quels par `bake_tuile_a`.
	mutable std::unordered_set<int> _is_cubic;
	mutable std::unordered_map<int, float> _hauteur_par_item;
	mutable std::unordered_map<int, Transform3D> _mesh_transforms;
	mutable std::vector<float> _bases_ortho; // 216 floats

protected:
	static void _bind_methods();

public:
	MesheurTuile();
	~MesheurTuile();

	String bonjour() const;

	// Appele UNE fois au _ready du rendu. Cles attendues :
	//   "items_cubiques"      PackedInt32Array
	//   "items_hauteur_cle"   PackedInt32Array
	//   "items_hauteur_val"   PackedFloat32Array
	//   "mesh_transforms"     Dictionary { int item -> Transform3D }
	//   "bases_orthogonales"  PackedFloat32Array 216 (24x9)
	void configurer_catalogues(const Dictionary &catalogues);

	// Cles attendues dans `entree` (donnees SPECIFIQUES a la tuile
	// seulement -- les catalogues d'items sont deja poses via
	// `configurer_catalogues`) :
	//   -- SCALAIRES --
	//   "origine_col"         Vector2i
	//   "taille"              int
	//   "couche_base"         int
	//   "couches_max"         int (COUCHES_MAXIMALES = 63)
	//   "demi_cote"           int
	//   "cote"                float
	//   "sommet_base"         int
	//   "masque_base"         int
	//   "masque_sous_plein"   int
	//   "max_pv_sous_cube"    int
	//   "item_defaut"         int
	//   "item_limite"         int
	//   "centre_offset"       Vector3
	//
	//   -- 9 ENTREES D'INDEX BRUTES (self + 8 voisins, entrees vides omises) --
	//   "entrees_index"       Array de Dictionary, chacun portant les 4 sous-
	//                         dicts tuile-locaux sous leurs cles officielles :
	//                           "volumes"           Dictionary[Vector2i, int]
	//                           "particularites"    Dictionary[Vector3i, int]
	//                           "masques_sous_cube" Dictionary[Vector3i, int]
	//                           "pv_sous_cubes"     Dictionary[Vector3i, Dictionary[int, int]]
	//                         Le C++ itere ces 9 entrees a l'entree et peuple
	//                         ses unordered_map natifs directement -- chaque
	//                         cellule vit dans UNE seule tuile (clefs
	//                         disjointes), donc iterer 9 entrees peuple
	//                         exactement les memes maps qu'un merge cote
	//                         GDScript produisait.
	//
	// Sortie :
	//   "par_forme"                Dict { item -> { buffer: PackedFloat32Array } }
	//                              -- le GDScript construit le MultiMesh
	//                              (MultiMesh.new + transform_format +
	//                              use_colors + mesh + instance_count +
	//                              buffer).
	//   "par_forme_sol"            idem
	//   "par_forme_mini"           idem
	//   "cellules_occl"            PackedInt32Array (triplets)
	//   "cellules_teintables"      PackedInt32Array (triplets) -- alimente
	//                              le cache profil GDScript
	//   "teinte_candidats_normal"  PackedInt32Array (6-tuples : item, x, y,
	//                              z, idx_start, count) -- une entree par
	//                              cellule cubique propre visible dans le
	//                              bucket normal ; count = nombre de faces
	//                              emises (1..6), idx_start = index de
	//                              la premiere face dans le buffer
	//                              (offset en instances, buffer/16).
	//   "teinte_candidats_sol"     idem, bucket sol.
	//   "couche_min"               int
	//   "couche_max"               int
	Dictionary bake_tuile_a(const Dictionary &entree) const;
};

} // namespace godot

#endif // MESHEUR_TUILE_H
