#ifndef MESHEUR_TUILE_H
#define MESHEUR_TUILE_H

// Classe portee C++ du meshing d'une tuile de terrain. Fait UN SEUL parcours
// de la tuile (visibilite + emission + collecte des trois derives dont le
// GDScript a besoin en aval) et rend son travail sous forme de BUFFERS
// PLATS (PackedFloat32Array) prets a etre passes a MultiMesh.set_buffer.
//
// PATRON "franchissement de frontiere UNE fois par tuile" (godot_voxel).
// Le GDScript assemble un blob (Dictionary) et le passe une fois a
// bake_tuile_a ; la sortie est convertie en Variants une seule fois a la
// fin. AUCUN Array<Transform3D> en sortie -- l'ancien contrat le faisait,
// il construisait un Variant par face (~500 par tuile) et cassait le gain
// C++ (godot-cpp issue #1063 : Variant en hot path = 10-50x un type natif).
// Le nouveau contrat rend chaque item comme { buffer, cellules } ou buffer
// est un PackedFloat32Array de 16 floats par instance (12 transform + 4
// color), pret a etre pose sur un MultiMesh avec use_colors=true.
//
// PORTE PAR CETTE VERSION :
//   - FACES CUBIQUES PROPRES (cellule cubique, sous_cubes plein, aucun PV).
//   - MINI-CUBES (cellule cubique cassee OU avec PV). Buffer inclut la
//     couleur PV par instance (blanc neuf, noir presque casse).
//   - NON-CUBES (item hors items_cubiques : rampe, cylindre, sphere).
//   - SORTIES DERIVEES : cellules_occl (cubes visibles au-dessus de
//     sommet_base -- pour l'occluder greedy), couche_min / couche_max
//     (AABB de tuile), cellules_teintables (candidates que le GDScript
//     testera avec _ressources.profil_de_cellule pour la teinte).

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

	// Fumee test de la chaine C++ -> GDScript.
	String bonjour() const;

	// Bake une tuile complete (cubes propres + mini-cubes + non-cubes), en
	// UN seul parcours, avec sorties derivees pour le GDScript.
	//
	// Cles attendues dans `entree` :
	//   -- SCALAIRES ET CONSTANTES --
	//   "origine_col"         Vector2i : coin bas-gauche (col.x, col.z).
	//   "taille"              int      : cote de tuile en cellules (10).
	//   "couche_base"         int      : couche_base de la carte.
	//   "couches_max"         int      : CarteTerrain.COUCHES_MAXIMALES (63).
	//   "cote"                float    : arete de cellule (2.0).
	//   "sommet_base"         int      : couche du sommet plein par defaut.
	//                                    Cube propre a ce niveau -> par_forme_sol.
	//                                    Cellules_occl = cubes visibles STRICTEMENT
	//                                    au-dessus de sommet_base.
	//   "item_limite"         int      : ITEM_LIMITE, ignore par le rendu.
	//   "item_defaut"         int      : ITEM_DEFAUT.
	//   "orientation_defaut"  int      : ORIENTATION_DEFAUT.
	//   "masque_sous_plein"   int      : MASQUE_SOUS_CUBE_PLEIN (27 bits).
	//   "max_pv_sous_cube"    int      : MAX_PV_SOUS_CUBE (50).
	//   "centre_offset"       Vector3  : _regle.map_to_local(Vector3i(0,0,0)),
	//                                    a ajouter a cellule * cote pour
	//                                    retrouver le centre monde.
	//
	//   -- COLONNES 12x12 (tuile + 4 anneaux) --
	//   "masques"             PackedInt64Array 144 : masque volume par colonne ;
	//                                    indice (lx+1) + (lz+1)*12.
	//   "couvrants"           PackedInt64Array 144 : masque couvrant par colonne.
	//
	//   -- CELLULES DE LA TUILE --
	//   "particularites"      PackedInt32Array : quadruplets x,y,z,code.
	//   "sous_cubes_partiels" PackedInt32Array : quadruplets x,y,z,masque_sous.
	//   "pv_par_cellule"      PackedInt32Array : quintuples x,y,z,sous_idx,pv.
	//
	//   -- TABLES ITEM --
	//   "items_cubiques"      PackedInt32Array : items dits cubiques.
	//   "items_hauteur_cle"   PackedInt32Array + "items_hauteur_val"
	//                         PackedFloat32Array : table parallele item -> hauteur.
	//   "bases_orthogonales"  PackedFloat32Array 216 : 24 bases x 9 floats
	//                         (rows[0..2] par basis).
	//   "mesh_transforms"     Dictionary { int item -> Transform3D } : pour
	//                         les items NON-cubiques.
	//
	// Rend :
	//   "par_forme"           Dict { int item -> {
	//                             "buffer":   PackedFloat32Array,
	//                             "cellules": PackedInt32Array
	//                         } }
	//                         Cubes propres (couche != sommet_base) ET non-cubes.
	//                         buffer = 16 floats/instance : m00,m01,m02,ox,
	//                         m10,m11,m12,oy, m20,m21,m22,oz, r,g,b,a.
	//                         cellules = 3 ints/instance (x,y,z) parallele.
	//                         Couleur par defaut = 1,1,1,1 (teinte posee par
	//                         GDScript via set_instance_color apres bake).
	//                         count instance = cellules.size() / 3.
	//   "par_forme_sol"       Dict identique, pour cubes propres a sommet_base.
	//   "par_forme_mini"      Dict identique, pour mini-cubes (couleur PV posee
	//                         dans le buffer, mesh = _mini_box_par_item cote GDScript).
	//   "cellules_occl"       PackedInt32Array (triplets x,y,z) des cubes
	//                         visibles STRICTEMENT au-dessus de sommet_base
	//                         (pour l'occluder greedy en phase 2).
	//   "cellules_teintables" PackedInt32Array (triplets x,y,z) des cubes
	//                         propres cubiques visibles -- candidats a la
	//                         teinte. GDScript filtre via
	//                         _ressources.profil_de_cellule.
	//   "couche_min"          int : couche la plus basse visible.
	//   "couche_max"          int : couche la plus haute visible. Si aucune
	//                         cellule visible, couche_min > couche_max
	//                         (sentinelle -- l'appelant peut construire une
	//                         AABB vide ou skip la tuile).
	Dictionary bake_tuile_a(const Dictionary &entree) const;
};

} // namespace godot

#endif // MESHEUR_TUILE_H
