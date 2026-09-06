#ifndef MESHEUR_TUILE_H
#define MESHEUR_TUILE_H

// Classe portee C++ du meshing d'une tuile de terrain. Le squelette expose
// bonjour() (fumee test de la chaine C++ -> GDScript). Le vrai travail est
// bake_tuile_a() : portage face-par-face IDENTIQUE de _phase_parser du GDScript
// (res://jeu/terrain/rendu_terrain_multimesh.gd).
//
// PATRON "franchissement de frontiere UNE fois par tuile" (godot_voxel).
// L'appelant GDScript assemble un blob (Dictionary) d'entree pour LA tuile a
// baker : masques 12x12, particularites de la tuile, sous_cubes entames, pv
// par sous-index, tables item->cubique / item->hauteur, 24 bases orthogonales
// et mesh_transforms des items non-cubiques. Le C++ ne rappelle JAMAIS la
// carte ni le mesh_library en boucle : il monte les entrees en HashMap une
// fois puis calcule sur des buffers natifs. La sortie est convertie en
// Variants une seule fois a la fin.
//
// PORTEE PAR CETTE VERSION (etapes (a) + (b) du portage) :
//   - FACES CUBIQUES PROPRES (cellule cubique, sous_cubes plein, aucun PV) --
//     etape (a).
//   - MINI-CUBES (cellule cubique cassee OU avec PV) -- etape (b). Un
//     mini-cube (cote/3) par bit a 1 dans le masque sous-cube, colorie du
//     blanc au noir selon ses PV (MAX_PV_SOUS_CUBE = tout noir).
//   - NON-CUBES (item hors items_cubiques : rampe, cylindre, sphere) --
//     etape (b). Une seule instance par cellule, transform = base_orthogonale
//     x mesh_transform, position au centre monde.
//
// A VENIR :
//   - (c) TEINTE : le mapping face->cellule des cubes propres est deja rendu
//     ici pour que l'etape (c) puisse s'y brancher sans re-parcourir la tuile.
//   - (d) SUPPRESSION du chemin GDScript equivalent -- gate par un flag chez
//     l'appelant tant que la validation visuelle n'a pas ete faite.

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

	// Bake une tuile complete (cubes propres + mini-cubes + non-cubes).
	// Cles attendues dans `entree` :
	//   -- SCALAIRES ET CONSTANTES --
	//   "origine_col"         Vector2i : coin bas-gauche (col.x, col.z) de la tuile.
	//   "taille"              int      : cote de tuile en cellules (10).
	//   "couche_base"         int      : couche_base de la carte.
	//   "couches_max"         int      : CarteTerrain.COUCHES_MAXIMALES (63).
	//   "cote"                float    : arete de cellule en metres (2.0).
	//   "sommet_base"         int      : couche du sommet plein par defaut.
	//                                    Une cellule cubique propre a ce niveau
	//                                    va dans par_forme_sol.
	//   "item_limite"         int      : ITEM_LIMITE, ignore par le rendu.
	//   "item_defaut"         int      : ITEM_DEFAUT.
	//   "orientation_defaut"  int      : ORIENTATION_DEFAUT.
	//   "masque_sous_plein"   int      : MASQUE_SOUS_CUBE_PLEIN (27 bits).
	//   "max_pv_sous_cube"    int      : MAX_PV_SOUS_CUBE (50). Utilise pour la
	//                                    couleur des mini-cubes : couleur =
	//                                    1 - pv/max_pv (0 = noir, 1 = blanc).
	//   "centre_offset"       Vector3  : ce que _regle.map_to_local(Vector3i(0,0,0))
	//                                    rend, a ajouter a cellule * cote pour
	//                                    retrouver le centre monde de la cellule.
	//
	//   -- COLONNES 12x12 (tuile + 4 anneaux) --
	//   "masques"             PackedInt64Array 144 : masque volume par colonne ;
	//                                    indice (lx+1) + (lz+1)*12, lx,lz in [-1..taille].
	//   "couvrants"           PackedInt64Array 144 : masque couvrant par colonne
	//                                    (meme indexation) -- voir _masque_couvrant_col
	//                                    GDScript.
	//
	//   -- CELLULES DE LA TUILE --
	//   "particularites"      PackedInt32Array : quadruplets x,y,z,code des
	//                                    cellules NON-DEFAUT de la tuile.
	//   "sous_cubes_partiels" PackedInt32Array : quadruplets x,y,z,masque_sous
	//                                    des cellules entamees de la tuile.
	//                                    Absent = masque_sous_plein.
	//   "pv_par_cellule"      PackedInt32Array : quintuples x,y,z,sous_idx,pv --
	//                                    UN quintuple par sous-cube endommage.
	//                                    Absent = pv 0. Sert a la couleur des
	//                                    mini-cubes emis.
	//
	//   -- TABLES ITEM (petites, une entree par forme de la bibliotheque) --
	//   "items_cubiques"      PackedInt32Array : items dits cubiques (portent
	//                                    un PlaneMesh cote GDScript).
	//   "items_hauteur_cle"   PackedInt32Array +
	//   "items_hauteur_val"   PackedFloat32Array : table parallele item -> hauteur.
	//                                    Item absent = hauteur = cote.
	//   "bases_orthogonales"  PackedFloat32Array 216 : 24 bases (une par
	//                                    orientation GridMap) x 9 floats
	//                                    (rows[0], rows[1], rows[2] en float).
	//                                    Precalculees en GDScript via
	//                                    _regle.get_basis_with_orthogonal_index.
	//   "mesh_transforms"     Dictionary { int item -> Transform3D } : transform
	//                                    interne du mesh, pour les items
	//                                    NON-cubiques uniquement. Passe une fois
	//                                    par tuile.
	//
	// Rend un Dictionary avec :
	//   "par_forme"       Dict { int item -> { "transforms" : Array of Transform3D,
	//                                          "cellules"   : PackedInt32Array } }
	//                     Cubes propres (couche != sommet_base) ET non-cubes.
	//                     Le mapping cellules parallele sert a la teinte (etape c).
	//   "par_forme_sol"   Dict identique, pour les cubes propres de la couche
	//                     sommet_base (cast_shadow_off cote appelant).
	//   "par_forme_mini"  Dict { int item -> Array of Dictionary{transform, couleur} }.
	//                     Un element par mini-cube, format compatible directement
	//                     avec _mmi_mini_cubes cote GDScript.
	Dictionary bake_tuile_a(const Dictionary &entree) const;
};

} // namespace godot

#endif // MESHEUR_TUILE_H
