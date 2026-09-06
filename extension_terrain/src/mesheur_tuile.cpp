#include "mesheur_tuile.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
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

// ----- helpers ---------------------------------------------------------------
namespace {

struct Vec3iHash {
	size_t operator()(const Vector3i &v) const noexcept {
		size_t h = std::hash<int32_t>()(v.x);
		h ^= std::hash<int32_t>()(v.y) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
		h ^= std::hash<int32_t>()(v.z) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
		return h;
	}
};

// Buffer natif d'un item : buffer plat (16 floats/instance) et cellules
// paralleles (3 ints/instance). Reserve() peut etre appele apres estimation
// rapide pour eviter les reallocations.
struct BucketItem {
	std::vector<float> buffer;   // 16 floats par instance
	std::vector<int32_t> cellules; // 3 ints par instance (x,y,z)
	inline int count() const { return (int)(cellules.size() / 3); }
};

constexpr double PI_D = 3.14159265358979323846;

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

inline Basis decode_basis(const PackedFloat32Array &arr, int orient) {
	int b = orient * 9;
	Basis out;
	out.rows[0] = Vector3((real_t)arr[b + 0], (real_t)arr[b + 1], (real_t)arr[b + 2]);
	out.rows[1] = Vector3((real_t)arr[b + 3], (real_t)arr[b + 4], (real_t)arr[b + 5]);
	out.rows[2] = Vector3((real_t)arr[b + 6], (real_t)arr[b + 7], (real_t)arr[b + 8]);
	return out;
}

// Ecrit UNE instance dans le buffer plat : 12 floats de transform (layout
// TRANSFORM_3D de MultiMesh : rows[0].xyz + origin.x, rows[1].xyz + origin.y,
// rows[2].xyz + origin.z) puis 4 floats de couleur.
inline void ecrire_instance(std::vector<float> &buffer, const Basis &b, const Vector3 &origin,
		float r, float g, float bl, float a) {
	buffer.push_back((float)b.rows[0].x);
	buffer.push_back((float)b.rows[0].y);
	buffer.push_back((float)b.rows[0].z);
	buffer.push_back((float)origin.x);
	buffer.push_back((float)b.rows[1].x);
	buffer.push_back((float)b.rows[1].y);
	buffer.push_back((float)b.rows[1].z);
	buffer.push_back((float)origin.y);
	buffer.push_back((float)b.rows[2].x);
	buffer.push_back((float)b.rows[2].y);
	buffer.push_back((float)b.rows[2].z);
	buffer.push_back((float)origin.z);
	buffer.push_back(r);
	buffer.push_back(g);
	buffer.push_back(bl);
	buffer.push_back(a);
}

inline void ecrire_cellule(std::vector<int32_t> &cellules, const Vector3i &c) {
	cellules.push_back(c.x);
	cellules.push_back(c.y);
	cellules.push_back(c.z);
}

// Conversion std::vector<float> -> PackedFloat32Array en UN memcpy.
inline PackedFloat32Array to_packed_float(const std::vector<float> &v) {
	PackedFloat32Array out;
	out.resize((int)v.size());
	if (!v.empty()) {
		std::memcpy(out.ptrw(), v.data(), v.size() * sizeof(float));
	}
	return out;
}

inline PackedInt32Array to_packed_int(const std::vector<int32_t> &v) {
	PackedInt32Array out;
	out.resize((int)v.size());
	if (!v.empty()) {
		std::memcpy(out.ptrw(), v.data(), v.size() * sizeof(int32_t));
	}
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
	(void)orientation_defaut;
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

	const int wsize = taille + 2;
	const int ORIENTATIONS = 32;

	// Cache scalaire des Packed*Array pour lecture inline sans indirection.
	const int64_t *masques_ptr = masques.ptr();
	const int64_t *couvrants_ptr = couvrants.ptr();

	// ----- montage des caches locaux (une seule fois par tuile) --------------
	std::unordered_set<int> is_cubic;
	is_cubic.reserve((size_t)items_cubiques.size());
	{
		const int32_t *ptr = items_cubiques.ptr();
		for (int i = 0; i < items_cubiques.size(); ++i) {
			is_cubic.insert(ptr[i]);
		}
	}

	std::unordered_map<int, real_t> hauteur_par_item;
	{
		int nh = items_h_cle.size();
		hauteur_par_item.reserve((size_t)nh);
		const int32_t *cle = items_h_cle.ptr();
		const float *val = items_h_val.ptr();
		for (int i = 0; i < nh; ++i) {
			hauteur_par_item[cle[i]] = (real_t)val[i];
		}
	}

	std::unordered_map<Vector3i, int, Vec3iHash> particularites;
	{
		int n = part_arr.size();
		particularites.reserve((size_t)(n / 4));
		const int32_t *ptr = part_arr.ptr();
		for (int k = 0; k + 3 < n; k += 4) {
			particularites[Vector3i(ptr[k], ptr[k + 1], ptr[k + 2])] = ptr[k + 3];
		}
	}

	std::unordered_map<Vector3i, int, Vec3iHash> sous_cubes_partiels;
	{
		int n = sc_arr.size();
		sous_cubes_partiels.reserve((size_t)(n / 4));
		const int32_t *ptr = sc_arr.ptr();
		for (int k = 0; k + 3 < n; k += 4) {
			sous_cubes_partiels[Vector3i(ptr[k], ptr[k + 1], ptr[k + 2])] = ptr[k + 3];
		}
	}

	std::unordered_map<Vector3i, std::unordered_map<int, int>, Vec3iHash> pv_par_cellule;
	{
		int n = pv_arr.size();
		const int32_t *ptr = pv_arr.ptr();
		for (int k = 0; k + 4 < n; k += 5) {
			Vector3i cellule(ptr[k], ptr[k + 1], ptr[k + 2]);
			pv_par_cellule[cellule][ptr[k + 3]] = ptr[k + 4];
		}
	}

	// ----- buffers de sortie natifs ------------------------------------------
	std::unordered_map<int, BucketItem> par_forme;
	std::unordered_map<int, BucketItem> par_forme_sol;
	std::unordered_map<int, BucketItem> par_forme_mini;
	std::vector<int32_t> cellules_occl;
	std::vector<int32_t> cellules_teintables;
	int couche_min_out = couche_base + couches_max;
	int couche_max_out = couche_base;

	// ----- boucle principale, portage a l'identique de _phase_parser ---------
	for (int lx = 0; lx < taille; ++lx) {
		for (int lz = 0; lz < taille; ++lz) {
			int cx = origine_col.x + lx;
			int cz = origine_col.y + lz;
			int i_self = (lx + 1) + (lz + 1) * wsize;
			int64_t bits = masques_ptr[i_self];
			if (bits == 0) continue;

			int64_t mon_c = couvrants_ptr[i_self];
			int64_t nxp_c = couvrants_ptr[(lx + 2) + (lz + 1) * wsize];
			int64_t nxm_c = couvrants_ptr[(lx    ) + (lz + 1) * wsize];
			int64_t nzp_c = couvrants_ptr[(lx + 1) + (lz + 2) * wsize];
			int64_t nzm_c = couvrants_ptr[(lx + 1) + (lz    ) * wsize];

			int64_t sealed = (mon_c >> 1) & nxp_c & nxm_c & nzp_c & nzm_c;
			int64_t visible = bits & ~sealed;
			if (visible == 0) continue;

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

				int code = -1;
				auto pit = particularites.find(cellule);
				if (pit != particularites.end()) code = pit->second;
				int item;
				int orientation;
				if (code == -1) {
					item = item_defaut;
					orientation = 0;
				} else {
					item = code / ORIENTATIONS;
					orientation = code % ORIENTATIONS;
				}
				if (item == item_limite) continue;

				// Derives : couche_min/max et cellules_occl (visible + cubique + couche > sommet_base).
				if (couche < couche_min_out) couche_min_out = couche;
				if (couche > couche_max_out) couche_max_out = couche;
				bool cubique = (is_cubic.find(item) != is_cubic.end());
				if (cubique && couche > sommet_base) {
					ecrire_cellule(cellules_occl, cellule);
				}

				Vector3 pos(
					(real_t)cellule.x * cote + centre_offset.x,
					(real_t)cellule.y * cote + centre_offset.y,
					(real_t)cellule.z * cote + centre_offset.z);

				if (!cubique) {
					// NON-CUBE : une seule instance, transform = base_ortho * mesh_transform.
					Basis base_ortho = decode_basis(bases_ortho, orientation);
					Variant mtv = mesh_transforms.get(item, Variant());
					Transform3D mesh_tf;
					if (mtv.get_type() == Variant::TRANSFORM3D) {
						mesh_tf = (Transform3D)mtv;
					}
					Transform3D total = Transform3D(base_ortho, pos) * mesh_tf;
					BucketItem &bucket = par_forme[item];
					ecrire_instance(bucket.buffer, total.basis, total.origin, 1.0f, 1.0f, 1.0f, 1.0f);
					ecrire_cellule(bucket.cellules, cellule);
					continue;
				}

				// CUBIQUE : distinguer mini-cubes (cellule cassee ou avec PV) et cube propre.
				int masque_sous = masque_sous_plein;
				auto sit = sous_cubes_partiels.find(cellule);
				if (sit != sous_cubes_partiels.end()) masque_sous = sit->second;
				auto pvit = pv_par_cellule.find(cellule);
				bool a_pv = (pvit != pv_par_cellule.end());

				if (masque_sous != masque_sous_plein || a_pv) {
					// MINI-CUBES : un par bit du masque_sous.
					BucketItem &bucket = par_forme_mini[item];
					const real_t pas = cote / (real_t)3.0;
					const std::unordered_map<int, int> *pv_map = a_pv ? &pvit->second : nullptr;
					Basis identity;
					for (int i = 0; i < 27; ++i) {
						if ((masque_sous & (1 << i)) == 0) continue;
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
						float t = 1.0f - (float)pv / (float)max_pv_sous_cube;
						if (t < 0.f) t = 0.f;
						if (t > 1.f) t = 1.f;
						ecrire_instance(bucket.buffer, identity, pos + offset, t, t, t, 1.0f);
						ecrire_cellule(bucket.cellules, cellule);
					}
					continue;
				}

				// CUBE PROPRE : candidat teinte + emission des 6 faces exposees.
				ecrire_cellule(cellules_teintables, cellule);
				BucketItem &bucket = (couche == sommet_base) ? par_forme_sol[item] : par_forme[item];

				// Voisin couvre reduit a un test de bit sur les couvrants.
				auto voisin_couvre = [couches_max](int64_t couvrant_voisin, int r) -> bool {
					if (r < 0 || r >= couches_max) return false;
					return (couvrant_voisin & ((int64_t)1 << r)) != 0;
				};

				// Emission d'UNE face i (portage exact de _ajouter_face GDScript).
				auto emettre_face = [&](int i, int64_t couvrant_neighbor, int rang_check) {
					if (voisin_couvre(couvrant_neighbor, rang_check)) return;
					real_t h = cote;
					auto ith = hauteur_par_item.find(item);
					if (ith != hauteur_par_item.end()) h = ith->second;
					Basis base = face_base(i);
					Vector3 n = face_normale(i);
					Vector3 origine;
					if (i == 0) {
						origine = pos + Vector3(0, h - cote * (real_t)0.5, 0);
					} else if (i == 1) {
						origine = pos + n * (cote * (real_t)0.5);
					} else {
						real_t ratio = h / cote;
						base.rows[1] = base.rows[1] * ratio;
						origine = pos + n * (cote * (real_t)0.5) + Vector3(0, (h - cote) * (real_t)0.5, 0);
					}
					ecrire_instance(bucket.buffer, base, origine, 1.0f, 1.0f, 1.0f, 1.0f);
					ecrire_cellule(bucket.cellules, cellule);
				};

				emettre_face(0, mon_c, rang + 1);
				emettre_face(1, mon_c, rang - 1);
				emettre_face(2, nxp_c, rang);
				emettre_face(3, nxm_c, rang);
				emettre_face(4, nzp_c, rang);
				emettre_face(5, nzm_c, rang);
			}
		}
	}

	// ----- conversion en Variants, UNE fois -----------------------------------
	auto items_to_dict = [](std::unordered_map<int, BucketItem> &m) -> Dictionary {
		Dictionary out;
		for (auto &kv : m) {
			Dictionary d;
			d["buffer"] = to_packed_float(kv.second.buffer);
			d["cellules"] = to_packed_int(kv.second.cellules);
			out[kv.first] = d;
		}
		return out;
	};

	Dictionary result;
	result["par_forme"] = items_to_dict(par_forme);
	result["par_forme_sol"] = items_to_dict(par_forme_sol);
	result["par_forme_mini"] = items_to_dict(par_forme_mini);
	result["cellules_occl"] = to_packed_int(cellules_occl);
	result["cellules_teintables"] = to_packed_int(cellules_teintables);
	result["couche_min"] = couche_min_out;
	result["couche_max"] = couche_max_out;
	return result;
}
