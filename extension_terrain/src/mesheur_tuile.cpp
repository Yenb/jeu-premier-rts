#include "mesheur_tuile.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <cstring>

using namespace godot;

namespace {

struct Vec2iHash {
	size_t operator()(const Vector2i &v) const noexcept {
		size_t h = std::hash<int32_t>()(v.x);
		h ^= std::hash<int32_t>()(v.y) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
		return h;
	}
};

struct Vec3iHash {
	size_t operator()(const Vector3i &v) const noexcept {
		size_t h = std::hash<int32_t>()(v.x);
		h ^= std::hash<int32_t>()(v.y) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
		h ^= std::hash<int32_t>()(v.z) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
		return h;
	}
};

struct BucketItem {
	std::vector<float> buffer;
	std::vector<int32_t> cellules;
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

inline Basis decode_basis(const std::vector<float> &arr, int orient) {
	int b = orient * 9;
	Basis out;
	out.rows[0] = Vector3((real_t)arr[b + 0], (real_t)arr[b + 1], (real_t)arr[b + 2]);
	out.rows[1] = Vector3((real_t)arr[b + 3], (real_t)arr[b + 4], (real_t)arr[b + 5]);
	out.rows[2] = Vector3((real_t)arr[b + 6], (real_t)arr[b + 7], (real_t)arr[b + 8]);
	return out;
}

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

void MesheurTuile::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bonjour"), &MesheurTuile::bonjour);
	ClassDB::bind_method(D_METHOD("configurer_catalogues", "catalogues"), &MesheurTuile::configurer_catalogues);
	ClassDB::bind_method(D_METHOD("bake_tuile_a", "entree"), &MesheurTuile::bake_tuile_a);
}

MesheurTuile::MesheurTuile() {}
MesheurTuile::~MesheurTuile() {}

String MesheurTuile::bonjour() const {
	return String("MesheurTuile C++ vivant.");
}

void MesheurTuile::configurer_catalogues(const Dictionary &c) {
	PackedInt32Array items_cubiques = c["items_cubiques"];
	PackedInt32Array items_h_cle = c["items_hauteur_cle"];
	PackedFloat32Array items_h_val = c["items_hauteur_val"];
	Dictionary mesh_transforms = c["mesh_transforms"];
	PackedFloat32Array bases_ortho = c["bases_orthogonales"];

	_is_cubic.clear();
	_is_cubic.reserve((size_t)items_cubiques.size());
	{
		const int32_t *ptr = items_cubiques.ptr();
		for (int i = 0; i < items_cubiques.size(); ++i) _is_cubic.insert(ptr[i]);
	}

	_hauteur_par_item.clear();
	{
		int nh = items_h_cle.size();
		const int32_t *cle = items_h_cle.ptr();
		const float *val = items_h_val.ptr();
		_hauteur_par_item.reserve((size_t)nh);
		for (int i = 0; i < nh; ++i) _hauteur_par_item[cle[i]] = val[i];
	}

	_mesh_transforms.clear();
	{
		Array keys = mesh_transforms.keys();
		int n = keys.size();
		_mesh_transforms.reserve((size_t)n);
		for (int i = 0; i < n; ++i) {
			Variant kv = keys[i];
			_mesh_transforms[(int)kv] = (Transform3D)mesh_transforms[kv];
		}
	}

	_bases_ortho.assign(bases_ortho.size(), 0.0f);
	if (bases_ortho.size() > 0) {
		std::memcpy(_bases_ortho.data(), bases_ortho.ptr(), (size_t)bases_ortho.size() * sizeof(float));
	}
}

Dictionary MesheurTuile::bake_tuile_a(const Dictionary &e) const {
	Vector2i origine_col = e["origine_col"];
	int taille = (int)e["taille"];
	int couche_base = (int)e["couche_base"];
	int couches_max = (int)e["couches_max"];
	int demi_cote = (int)e["demi_cote"];
	real_t cote = (real_t)(double)e["cote"];
	int sommet_base = (int)e["sommet_base"];
	int64_t masque_base = (int64_t)e["masque_base"];
	int masque_sous_plein = (int)e["masque_sous_plein"];
	int max_pv_sous_cube = (int)e["max_pv_sous_cube"];
	int item_defaut = (int)e["item_defaut"];
	int item_limite = (int)e["item_limite"];
	Vector3 centre_offset = e["centre_offset"];

	Dictionary volumes_dict = e["volumes"];
	Dictionary particularites_dict = e["particularites"];
	Dictionary masques_sc_dict = e["masques_sous_cube"];
	Dictionary pv_dict = e["pv_sous_cubes"];

	std::unordered_map<Vector2i, int64_t, Vec2iHash> volumes;
	{
		Array keys = volumes_dict.keys();
		int n = keys.size();
		volumes.reserve((size_t)n);
		for (int i = 0; i < n; ++i) {
			Variant kv = keys[i];
			volumes[(Vector2i)kv] = (int64_t)(int)volumes_dict[kv];
		}
	}

	std::unordered_map<Vector3i, int, Vec3iHash> particularites;
	{
		Array keys = particularites_dict.keys();
		int n = keys.size();
		particularites.reserve((size_t)n);
		for (int i = 0; i < n; ++i) {
			Variant kv = keys[i];
			particularites[(Vector3i)kv] = (int)particularites_dict[kv];
		}
	}

	std::unordered_map<Vector3i, int, Vec3iHash> masques_sous_cube;
	{
		Array keys = masques_sc_dict.keys();
		int n = keys.size();
		masques_sous_cube.reserve((size_t)n);
		for (int i = 0; i < n; ++i) {
			Variant kv = keys[i];
			masques_sous_cube[(Vector3i)kv] = (int)masques_sc_dict[kv];
		}
	}

	std::unordered_map<Vector3i, std::unordered_map<int, int>, Vec3iHash> pv_par_cellule;
	{
		Array keys = pv_dict.keys();
		int n = keys.size();
		pv_par_cellule.reserve((size_t)n);
		for (int i = 0; i < n; ++i) {
			Variant kv = keys[i];
			Dictionary inner = pv_dict[kv];
			Array inner_keys = inner.keys();
			int m = inner_keys.size();
			auto &inner_map = pv_par_cellule[(Vector3i)kv];
			inner_map.reserve((size_t)m);
			for (int j = 0; j < m; ++j) {
				Variant ikv = inner_keys[j];
				inner_map[(int)ikv] = (int)inner[ikv];
			}
		}
	}

	auto masque_col = [&](const Vector2i &col) -> int64_t {
		if (col.x < -demi_cote || col.x >= demi_cote ||
				col.y < -demi_cote || col.y >= demi_cote) return 0;
		auto it = volumes.find(col);
		if (it != volumes.end()) return it->second;
		return masque_base;
	};

	const int wsize = taille + 2;
	const int ORIENTATIONS = 32;

	std::vector<int64_t> masques_win((size_t)wsize * wsize);
	std::vector<int64_t> couvrants_win((size_t)wsize * wsize);

	for (int lx = -1; lx <= taille; ++lx) {
		for (int lz = -1; lz <= taille; ++lz) {
			Vector2i col(origine_col.x + lx, origine_col.y + lz);
			int idx = (lx + 1) + (lz + 1) * wsize;
			int64_t bits = masque_col(col);
			masques_win[idx] = bits;
			if (bits == 0) {
				couvrants_win[idx] = 0;
				continue;
			}
			int64_t couvrant = bits;
			for (int rang = 0; rang < couches_max; ++rang) {
				if ((bits & ((int64_t)1 << rang)) == 0) continue;
				Vector3i cellule(col.x, couche_base + rang, col.y);
				int code = -1;
				auto pit = particularites.find(cellule);
				if (pit != particularites.end()) code = pit->second;
				int item;
				if (code == -1) item = item_defaut;
				else item = code / ORIENTATIONS;
				if (_is_cubic.find(item) == _is_cubic.end()) {
					couvrant &= ~((int64_t)1 << rang);
					continue;
				}
				auto sit = masques_sous_cube.find(cellule);
				if (sit != masques_sous_cube.end() && sit->second != masque_sous_plein) {
					couvrant &= ~((int64_t)1 << rang);
				}
			}
			couvrants_win[idx] = couvrant;
		}
	}

	std::unordered_map<int, BucketItem> par_forme;
	std::unordered_map<int, BucketItem> par_forme_sol;
	std::unordered_map<int, BucketItem> par_forme_mini;
	std::vector<int32_t> cellules_occl;
	std::vector<int32_t> cellules_teintables;
	// teinte_candidats : 6-tuples (item, x, y, z, idx_start, count) par cellule
	// cubique propre visible. Pret pour le GDScript qui ne re-scannera plus
	// par_forme[item].cellules.
	std::vector<int32_t> teinte_cand_normal;
	std::vector<int32_t> teinte_cand_sol;
	int couche_min_out = couche_base + couches_max;
	int couche_max_out = couche_base;

	auto voisin_couvre = [couches_max](int64_t couvrant_voisin, int r) -> bool {
		if (r < 0 || r >= couches_max) return false;
		return (couvrant_voisin & ((int64_t)1 << r)) != 0;
	};

	for (int lx = 0; lx < taille; ++lx) {
		for (int lz = 0; lz < taille; ++lz) {
			int cx = origine_col.x + lx;
			int cz = origine_col.y + lz;
			int i_self = (lx + 1) + (lz + 1) * wsize;
			int64_t bits = masques_win[i_self];
			if (bits == 0) continue;

			int64_t mon_c = couvrants_win[i_self];
			int64_t nxp_c = couvrants_win[(lx + 2) + (lz + 1) * wsize];
			int64_t nxm_c = couvrants_win[(lx    ) + (lz + 1) * wsize];
			int64_t nzp_c = couvrants_win[(lx + 1) + (lz + 2) * wsize];
			int64_t nzm_c = couvrants_win[(lx + 1) + (lz    ) * wsize];

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

				if (couche < couche_min_out) couche_min_out = couche;
				if (couche > couche_max_out) couche_max_out = couche;
				bool cubique = (_is_cubic.find(item) != _is_cubic.end());
				if (cubique && couche > sommet_base) {
					ecrire_cellule(cellules_occl, cellule);
				}

				Vector3 pos(
					(real_t)cellule.x * cote + centre_offset.x,
					(real_t)cellule.y * cote + centre_offset.y,
					(real_t)cellule.z * cote + centre_offset.z);

				if (!cubique) {
					Basis base_ortho = decode_basis(_bases_ortho, orientation);
					Transform3D mesh_tf;
					auto mtit = _mesh_transforms.find(item);
					if (mtit != _mesh_transforms.end()) mesh_tf = mtit->second;
					Transform3D total = Transform3D(base_ortho, pos) * mesh_tf;
					BucketItem &bucket = par_forme[item];
					ecrire_instance(bucket.buffer, total.basis, total.origin, 1.0f, 1.0f, 1.0f, 1.0f);
					ecrire_cellule(bucket.cellules, cellule);
					continue;
				}

				int masque_sous = masque_sous_plein;
				auto sit = masques_sous_cube.find(cellule);
				if (sit != masques_sous_cube.end()) masque_sous = sit->second;
				auto pvit = pv_par_cellule.find(cellule);
				bool a_pv = (pvit != pv_par_cellule.end());

				if (masque_sous != masque_sous_plein || a_pv) {
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

				// CUBE PROPRE : candidat teinte + emission 6 faces exposees.
				ecrire_cellule(cellules_teintables, cellule);
				bool est_sol = (couche == sommet_base);
				BucketItem &bucket = est_sol ? par_forme_sol[item] : par_forme[item];
				int idx_start = (int)bucket.cellules.size() / 3;

				real_t h_item = cote;
				{
					auto ith = _hauteur_par_item.find(item);
					if (ith != _hauteur_par_item.end()) h_item = ith->second;
				}

				auto emettre_face = [&, h_item](int i, int64_t couvrant_neighbor, int rang_check) {
					if (voisin_couvre(couvrant_neighbor, rang_check)) return;
					real_t h = h_item;
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

				int count_faces = (int)bucket.cellules.size() / 3 - idx_start;
				if (count_faces > 0) {
					std::vector<int32_t> &tc = est_sol ? teinte_cand_sol : teinte_cand_normal;
					tc.push_back(item);
					tc.push_back(cellule.x);
					tc.push_back(cellule.y);
					tc.push_back(cellule.z);
					tc.push_back(idx_start);
					tc.push_back(count_faces);
				}
			}
		}
	}

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
	result["teinte_candidats_normal"] = to_packed_int(teinte_cand_normal);
	result["teinte_candidats_sol"] = to_packed_int(teinte_cand_sol);
	result["couche_min"] = couche_min_out;
	result["couche_max"] = couche_max_out;
	return result;
}
