#include "mesheur_tuile.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <cstring>
#include <unordered_map>
#include <unordered_set>
#include <vector>

using namespace godot;

// ----- helpers de hash pour Vector3i dans std::unordered_map/set -------------
// godot-cpp n'expose pas de std::hash<Vector3i>. Combinateur derive de
// boost::hash_combine. Pas critique en collisions ici : nos jeux de cles font
// au plus quelques centaines d'entrees par tuile.
namespace {
struct Vec3iHash {
	size_t operator()(const Vector3i &v) const noexcept {
		size_t h = std::hash<int32_t>()(v.x);
		h ^= std::hash<int32_t>()(v.y) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
		h ^= std::hash<int32_t>()(v.z) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
		return h;
	}
};

// Buffers natifs par item, pour les CUBES PROPRES et les NON-CUBES : transforms
// + cellules d'origine (parallelle). L'appelant s'en sert pour reposer la
// teinte via _cache_profil_cellule (etape c).
struct BucketNormal {
	std::vector<Transform3D> transforms;
	std::vector<int32_t> cellules; // triplets x, y, z, parallelles a transforms
};

// Buffers natifs par item, pour les MINI-CUBES : transforms + couleurs
// (parallelles). Convertis a la fin en Array<Dictionary{transform, couleur}>
// pour rester compatible avec _mmi_mini_cubes GDScript (deux formats
// existent aujourd'hui : le format Dict de mini-cube est celui que le nœud
// consomme depuis 2026-08).
struct BucketMini {
	std::vector<Transform3D> transforms;
	std::vector<Color> couleurs;
};

// PI en real_t (godot-cpp fournit Math_PI dans core/math.hpp mais il est plus
// simple de ne pas dependre de la constante et d'ancrer notre valeur ici).
constexpr double PI_D = 3.14159265358979323846;

// Base de la face i, avant scale-Y eventuel pour un item plus court que la
// cellule. Meme ordre que rendu_terrain_multimesh.gd:203-210 : +Y, -Y, +X, -X,
// +Z, -Z.
inline Basis face_base(int i) {
	switch (i) {
		case 0: return Basis();
		case 1: return Basis(Vector3(1, 0, 0), (real_t)PI_D);
		case 2: return Basis(Vector3(0, 0, 1), -(real_t)PI_D * (real_t)0.5);
		case 3: return Basis(Vector3(0, 0, 1),  (real_t)PI_D * (real_t)0.5);
		case 4: return Basis(Vector3(1, 0, 0),  (real_t)PI_D * (real_t)0.5);
		case 5: return Basis(Vector3(1, 0, 0), -(real_t)PI_D * (real_t)0.5);
	}
	return Basis();
}

// Normale de la face i, vers le vide.
inline Vector3 face_normale(int i) {
	switch (i) {
		case 0: return Vector3(0,  1, 0);
		case 1: return Vector3(0, -1, 0);
		case 2: return Vector3( 1, 0, 0);
		case 3: return Vector3(-1, 0, 0);
		case 4: return Vector3(0, 0,  1);
		case 5: return Vector3(0, 0, -1);
	}
	return Vector3();
}

// Decode la base orthogonale d'index `orient` depuis PackedFloat32Array
// (24 bases x 9 floats = 216 floats). rows[0..2] chacune 3 floats.
inline Basis decode_basis(const PackedFloat32Array &arr, int orient) {
	int b = orient * 9;
	Basis out;
	out.rows[0] = Vector3((real_t)arr[b + 0], (real_t)arr[b + 1], (real_t)arr[b + 2]);
	out.rows[1] = Vector3((real_t)arr[b + 3], (real_t)arr[b + 4], (real_t)arr[b + 5]);
	out.rows[2] = Vector3((real_t)arr[b + 6], (real_t)arr[b + 7], (real_t)arr[b + 8]);
	return out;
}

} // namespace

// -----------------------------------------------------------------------------

void MesheurTuile::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bonjour"), &MesheurTuile::bonjour);
	ClassDB::bind_method(D_METHOD("bake_tuile_a", "entree"), &MesheurTuile::bake_tuile_a);
}

MesheurTuile::MesheurTuile() {}
MesheurTuile::~MesheurTuile() {}

String MesheurTuile::bonjour() const {
	return String("MesheurTuile C++ vivant.");
}

Dictionary MesheurTuile::bake_tuile_a(const Dictionary &e) const {
	// ----- decodage des scalaires du blob ------------------------------------
	Vector2i origine_col = e["origine_col"];
	int taille = (int)e["taille"];
	int couche_base = (int)e["couche_base"];
	int couches_max = (int)e["couches_max"];
	real_t cote = (real_t)(double)e["cote"];
	int sommet_base = (int)e["sommet_base"];
	int item_limite = (int)e["item_limite"];
	int item_defaut = (int)e["item_defaut"];
	int orientation_defaut = (int)e["orientation_defaut"];
	int masque_sous_plein = (int)e["masque_sous_plein"];
	int max_pv_sous_cube = (int)e["max_pv_sous_cube"];
	Vector3 centre_offset = e["centre_offset"];

	PackedInt64Array masques = e["masques"];
	PackedInt64Array couvrants = e["couvrants"];
	PackedInt32Array part_arr = e["particularites"];
	PackedInt32Array sc_arr = e["sous_cubes_partiels"];
	PackedInt32Array pv_arr = e["pv_par_cellule"];
	PackedInt32Array items_cubiques = e["items_cubiques"];
	PackedInt32Array items_h_cle = e["items_hauteur_cle"];
	PackedFloat32Array items_h_val = e["items_hauteur_val"];
	PackedFloat32Array bases_ortho = e["bases_orthogonales"];
	Dictionary mesh_transforms = e["mesh_transforms"];

	const int wsize = taille + 2; // 12 pour taille=10
	const int ORIENTATIONS = 32;   // meme constante que carte_terrain.gd

	// ----- montage des caches locaux (une seule fois par tuile) --------------
	std::unordered_set<int> is_cubic;
	is_cubic.reserve((size_t)items_cubiques.size());
	for (int i = 0; i < items_cubiques.size(); ++i) {
		is_cubic.insert(items_cubiques[i]);
	}

	std::unordered_map<int, real_t> hauteur_par_item;
	int nh = items_h_cle.size();
	hauteur_par_item.reserve((size_t)nh);
	for (int i = 0; i < nh; ++i) {
		hauteur_par_item[items_h_cle[i]] = (real_t)items_h_val[i];
	}

	std::unordered_map<Vector3i, int, Vec3iHash> particularites;
	particularites.reserve((size_t)(part_arr.size() / 4));
	for (int k = 0; k + 3 < part_arr.size(); k += 4) {
		particularites[Vector3i(part_arr[k], part_arr[k + 1], part_arr[k + 2])] = part_arr[k + 3];
	}

	std::unordered_map<Vector3i, int, Vec3iHash> sous_cubes_partiels;
	sous_cubes_partiels.reserve((size_t)(sc_arr.size() / 4));
	for (int k = 0; k + 3 < sc_arr.size(); k += 4) {
		sous_cubes_partiels[Vector3i(sc_arr[k], sc_arr[k + 1], sc_arr[k + 2])] = sc_arr[k + 3];
	}

	// PV par cellule : Vector3i cellule -> HashMap<sous_idx, pv>. Absent = 0
	// partout. Sert a la couleur des mini-cubes.
	std::unordered_map<Vector3i, std::unordered_map<int, int>, Vec3iHash> pv_par_cellule;
	for (int k = 0; k + 4 < pv_arr.size(); k += 5) {
		Vector3i cellule(pv_arr[k], pv_arr[k + 1], pv_arr[k + 2]);
		pv_par_cellule[cellule][pv_arr[k + 3]] = pv_arr[k + 4];
	}

	// ----- buffers de sortie natifs ------------------------------------------
	std::unordered_map<int, BucketNormal> par_forme;
	std::unordered_map<int, BucketNormal> par_forme_sol;
	std::unordered_map<int, BucketMini> par_forme_mini;

	// Voisin couvre-t-il ? Reduit a un test de bit sur le masque couvrant du
	// voisin, apres verification de la plage de rang. Voir la reduction dans
	// l'entete du fichier .gd -- meme semantique que _voisin_couvre GDScript.
	auto voisin_couvre = [&](int64_t couvrant_voisin, int rang) -> bool {
		if (rang < 0 || rang >= couches_max) return false;
		return (couvrant_voisin & ((int64_t)1 << rang)) != 0;
	};

	// Ajout d'UNE face i sur item, centree en `centre`. Portage exact de
	// _ajouter_face (rendu_terrain_multimesh.gd:773-801).
	auto ajouter_face = [&](BucketNormal &bucket, int item, const Vector3 &centre,
									int i, const Vector3i &cellule) {
		real_t h = cote;
		auto ith = hauteur_par_item.find(item);
		if (ith != hauteur_par_item.end()) h = ith->second;

		Basis base = face_base(i);
		Vector3 n = face_normale(i);
		Vector3 origine;
		if (i == 0) {
			origine = centre + Vector3(0, h - cote * (real_t)0.5, 0);
		} else if (i == 1) {
			origine = centre + n * (cote * (real_t)0.5);
		} else {
			real_t ratio = h / cote;
			base.rows[1] = base.rows[1] * ratio;
			origine = centre + n * (cote * (real_t)0.5) + Vector3(0, (h - cote) * (real_t)0.5, 0);
		}
		bucket.transforms.emplace_back(base, origine);
		bucket.cellules.push_back(cellule.x);
		bucket.cellules.push_back(cellule.y);
		bucket.cellules.push_back(cellule.z);
	};

	// Ajout des mini-cubes pour une cellule cassee / avec PV. Portage exact de
	// _ajouter_mini_cubes (rendu_terrain_multimesh.gd:701-726) : un mini-cube
	// (cote/3) par bit a 1 dans le masque, position centre + offset selon (ix,
	// iy, iz), couleur BLANC (pv 0) -> NOIR (pv MAX).
	auto ajouter_mini_cubes = [&](BucketMini &bucket, const Vector3 &centre,
			int masque, const std::unordered_map<int, int> *pv_map) {
		const real_t pas = cote / (real_t)3.0;
		for (int i = 0; i < 27; ++i) {
			if ((masque & (1 << i)) == 0) continue;
			int ix = i % 3;
			int iy = (i / 3) % 3;
			int iz = i / 9;
			Vector3 offset(
				(real_t)(ix - 1) * pas,
				(real_t)(iy - 1) * pas,
				(real_t)(iz - 1) * pas);
			int pv = 0;
			if (pv_map != nullptr) {
				auto it = pv_map->find(i);
				if (it != pv_map->end()) pv = it->second;
			}
			real_t t = (real_t)1.0 - (real_t)pv / (real_t)max_pv_sous_cube;
			if (t < 0) t = 0;
			if (t > 1) t = 1;
			bucket.transforms.emplace_back(Basis(), centre + offset);
			bucket.couleurs.emplace_back(t, t, t, (real_t)1.0);
		}
	};

	// Ajout d'un NON-CUBE (rampe, cylindre, sphere) : UNE instance, transform
	// = base_orthogonale x mesh_transform, position au centre de cellule.
	auto ajouter_non_cube = [&](int item, int orientation, const Vector3 &pos,
			const Vector3i &cellule) {
		Basis base_ortho = decode_basis(bases_ortho, orientation);
		Variant mtv = mesh_transforms.get(item, Variant());
		Transform3D mesh_tf;
		if (mtv.get_type() == Variant::TRANSFORM3D) {
			mesh_tf = (Transform3D)mtv;
		}
		Transform3D total = Transform3D(base_ortho, pos) * mesh_tf;
		BucketNormal &bucket = par_forme[item];
		bucket.transforms.push_back(total);
		bucket.cellules.push_back(cellule.x);
		bucket.cellules.push_back(cellule.y);
		bucket.cellules.push_back(cellule.z);
	};

	// ----- boucle principale, portage a l'identique de _phase_parser ---------
	for (int lx = 0; lx < taille; ++lx) {
		for (int lz = 0; lz < taille; ++lz) {
			int cx = origine_col.x + lx;
			int cz = origine_col.y + lz;
			int i_self = (lx + 1) + (lz + 1) * wsize;
			int64_t bits = masques[i_self];
			if (bits == 0) continue;

			int64_t mon_c = couvrants[i_self];
			int64_t nxp_c = couvrants[(lx + 2) + (lz + 1) * wsize];
			int64_t nxm_c = couvrants[(lx    ) + (lz + 1) * wsize];
			int64_t nzp_c = couvrants[(lx + 1) + (lz + 2) * wsize];
			int64_t nzm_c = couvrants[(lx + 1) + (lz    ) * wsize];

			// visible_bits_col : reprise exacte de la ligne 399 du GDScript.
			int64_t sealed = (mon_c >> 1) & nxp_c & nxm_c & nzp_c & nzm_c;
			int64_t visible = bits & ~sealed;
			if (visible == 0) continue;

			// rang_le_plus_haut : dichotomie a 6 shifts, identique carte_terrain.gd.
			int r_top = 0;
			{
				int64_t r = bits;
				if (r >= ((int64_t)1 << 32)) { r_top += 32; r >>= 32; }
				if (r >= ((int64_t)1 << 16)) { r_top += 16; r >>= 16; }
				if (r >= ((int64_t)1 << 8))  { r_top += 8;  r >>= 8; }
				if (r >= ((int64_t)1 << 4))  { r_top += 4;  r >>= 4; }
				if (r >= ((int64_t)1 << 2))  { r_top += 2;  r >>= 2; }
				if (r >= 2) r_top += 1;
			}

			for (int rang = 0; rang <= r_top; ++rang) {
				if ((visible & ((int64_t)1 << rang)) == 0) continue;
				int couche = couche_base + rang;
				Vector3i cellule(cx, couche, cz);

				// Decode item / orientation depuis particularites.
				int code = -1;
				auto pit = particularites.find(cellule);
				if (pit != particularites.end()) code = pit->second;
				int item;
				int orientation;
				if (code == -1) {
					item = item_defaut;
					orientation = orientation_defaut;
				} else {
					item = code / ORIENTATIONS;
					orientation = code % ORIENTATIONS;
				}
				if (item == item_limite) continue;

				Vector3 pos(
					(real_t)cellule.x * cote + centre_offset.x,
					(real_t)cellule.y * cote + centre_offset.y,
					(real_t)cellule.z * cote + centre_offset.z);

				bool cubique = (is_cubic.find(item) != is_cubic.end());
				if (!cubique) {
					// NON-CUBE : une seule instance, hors par_forme_sol.
					ajouter_non_cube(item, orientation, pos, cellule);
					continue;
				}

				// CUBIQUE. Distinguer mini-cubes (cellule cassee ou avec PV) et
				// cube propre (6 faces exposees).
				int masque_sous = masque_sous_plein;
				auto sit = sous_cubes_partiels.find(cellule);
				if (sit != sous_cubes_partiels.end()) masque_sous = sit->second;
				auto pvit = pv_par_cellule.find(cellule);
				bool a_pv = (pvit != pv_par_cellule.end());

				if (masque_sous != masque_sous_plein || a_pv) {
					// MINI-CUBES.
					const std::unordered_map<int, int> *pv_map = nullptr;
					if (a_pv) pv_map = &pvit->second;
					ajouter_mini_cubes(par_forme_mini[item], pos, masque_sous, pv_map);
					continue;
				}

				// Cube propre : emission des 6 faces exposees.
				BucketNormal &bucket = (couche == sommet_base) ? par_forme_sol[item] : par_forme[item];
				if (!voisin_couvre(mon_c, rang + 1)) ajouter_face(bucket, item, pos, 0, cellule);
				if (!voisin_couvre(mon_c, rang - 1)) ajouter_face(bucket, item, pos, 1, cellule);
				if (!voisin_couvre(nxp_c, rang))     ajouter_face(bucket, item, pos, 2, cellule);
				if (!voisin_couvre(nxm_c, rang))     ajouter_face(bucket, item, pos, 3, cellule);
				if (!voisin_couvre(nzp_c, rang))     ajouter_face(bucket, item, pos, 4, cellule);
				if (!voisin_couvre(nzm_c, rang))     ajouter_face(bucket, item, pos, 5, cellule);
			}
		}
	}

	// ----- conversion en Variants, UNE fois -----------------------------------
	auto normal_to_dict = [](std::unordered_map<int, BucketNormal> &m) -> Dictionary {
		Dictionary out;
		for (auto &kv : m) {
			Dictionary d;
			Array tf;
			int n = (int)kv.second.transforms.size();
			tf.resize(n);
			for (int i = 0; i < n; ++i) {
				tf[i] = kv.second.transforms[(size_t)i];
			}
			PackedInt32Array cells;
			int nc = (int)kv.second.cellules.size();
			cells.resize(nc);
			if (nc > 0) {
				std::memcpy(cells.ptrw(), kv.second.cellules.data(), (size_t)nc * sizeof(int32_t));
			}
			d["transforms"] = tf;
			d["cellules"] = cells;
			out[kv.first] = d;
		}
		return out;
	};
	auto mini_to_dict = [](std::unordered_map<int, BucketMini> &m) -> Dictionary {
		// _mmi_mini_cubes cote GDScript lit Array< Dictionary{transform, couleur} >
		// -- on reconstruit ce format ici (une allocation Dict par mini-cube).
		Dictionary out;
		for (auto &kv : m) {
			int n = (int)kv.second.transforms.size();
			Array liste;
			liste.resize(n);
			for (int i = 0; i < n; ++i) {
				Dictionary d;
				d["transform"] = kv.second.transforms[(size_t)i];
				d["couleur"] = kv.second.couleurs[(size_t)i];
				liste[i] = d;
			}
			out[kv.first] = liste;
		}
		return out;
	};

	Dictionary result;
	result["par_forme"] = normal_to_dict(par_forme);
	result["par_forme_sol"] = normal_to_dict(par_forme_sol);
	result["par_forme_mini"] = mini_to_dict(par_forme_mini);
	return result;
}
