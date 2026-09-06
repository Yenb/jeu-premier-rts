#ifndef MESHEUR_TUILE_H
#define MESHEUR_TUILE_H

// Classe portee C++ du meshing d'une tuile de terrain. Le squelette expose
// bonjour() (fumee test de la chaine C++ -> GDScript). Le vrai travail est
// bake_tuile_a() : etape (a) du portage de _phase_parser du GDScript
// (res://jeu/terrain/rendu_terrain_multimesh.gd).
//
// PATRON "franchissement de frontiere UNE fois par tuile" (godot_voxel).
// L'appelant GDScript assemble un blob (Dictionary) d'entree pour LA tuile a
// baker : masques 12x12, particularites de la tuile, sous_cubes entames, pv,
// tables item->cubique / item->hauteur, constantes de la carte. Le C++ ne
// rappelle JAMAIS la carte ni le mesh_library en boucle : il monte les
// entrees en HashMap une fois puis calcule sur des buffers natifs. La sortie
// est convertie en Variants une seule fois a la fin.
//
// ETAPE (a) : SEULES les faces cubiques propres (sous_cubes plein + aucun PV
// en cours) sont produites ici. Les mini-cubes, non-cubes, occluder cells,
// tint restent geres par GDScript en complement (voir _phase_parser). Pour
// que la teinte survive au portage, bake_tuile_a rend aussi, par item, la
// liste PARALLELE des cellules d'origine de chaque face -- le GDScript pousse
// la teinte a partir de ce mapping (etapes suivantes : (b) mini-cubes +
// non-cubes, (c) teinte, (d) retrait du chemin GDScript mort).

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

	// Fumee test de la chaine C++ -> GDScript. A garder tant que le portage
	// n'est pas termine : sert de sonde en cas de bascule de version godot-cpp
	// ou de .dll.
	String bonjour() const;

	// ETAPE (a) : bake les faces cubiques PROPRES d'une tuile.
	// Voir l'en-tete du fichier pour le contrat. Cles attendues dans `entree` :
	//   "origine_col"         Vector2i : coin bas-gauche (col.x, col.z) de la tuile.
	//   "taille"              int      : cote de tuile en cellules (10).
	//   "couche_base"         int      : couche_base de la carte.
	//   "couches_max"         int      : CarteTerrain.COUCHES_MAXIMALES (63).
	//   "cote"                float    : arete de cellule, en metres (2.0).
	//   "sommet_base"         int      : couche du sommet plein par defaut,
	//                                    separe par_forme_sol de par_forme.
	//   "item_limite"         int      : ITEM_LIMITE, ignore par le rendu.
	//   "item_defaut"         int      : ITEM_DEFAUT.
	//   "orientation_defaut"  int      : ORIENTATION_DEFAUT.
	//   "masque_sous_plein"   int      : MASQUE_SOUS_CUBE_PLEIN (27 bits).
	//   "centre_offset"       Vector3  : ce que _regle.map_to_local(Vector3i(0,0,0))
	//                                    rend (centre cellule 0), a ajouter a
	//                                    cellule * cote pour retrouver le centre
	//                                    monde. Passe pour ne pas dependre des
	//                                    defauts cell_center_* du GridMap.
	//   "masques"             PackedInt64Array 144 : masque volume par colonne
	//                                    de la fenetre 12x12 ; indice
	//                                    (lx+1) + (lz+1)*12 avec lx,lz in [-1..taille].
	//   "couvrants"           PackedInt64Array 144 : masque couvrant par colonne
	//                                    (voir _masque_couvrant_col en GDScript).
	//                                    Meme indexation que "masques".
	//   "particularites"      PackedInt32Array : quadruplets x,y,z,code des
	//                                    cellules NON-DEFAUT de la tuile SEULE.
	//   "sous_cubes_partiels" PackedInt32Array : quadruplets x,y,z,masque_sous
	//                                    des cellules entamees de la tuile.
	//                                    Absent = masque_sous_plein.
	//   "cellules_pv"         PackedInt32Array : triples x,y,z des cellules de
	//                                    la tuile ayant des PV en cours.
	//   "items_cubiques"      PackedInt32Array : liste des items dits cubiques
	//                                    (ceux qui portent un PlaneMesh cote GDScript).
	//   "items_hauteur_cle"   PackedInt32Array +
	//   "items_hauteur_val"   PackedFloat32Array : table parallele item -> hauteur.
	//                                    Item absent = plein (h = cote).
	//
	// Rend un Dictionary avec :
	//   "par_forme"     Dict { int item -> { "transforms" : Array of Transform3D,
	//                                        "cellules"   : PackedInt32Array } }
	//   "par_forme_sol" Dict identique, pour les faces dont la cellule est sur la
	//                   couche sommet_base (cast_shadow_off cote appelant).
	// "cellules" est parallele a "transforms" -- triplets x,y,z par face.
	Dictionary bake_tuile_a(const Dictionary &entree) const;
};

} // namespace godot

#endif // MESHEUR_TUILE_H
