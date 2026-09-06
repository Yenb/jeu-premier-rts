#include "mesheur_tuile.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/basis.hpp>
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

// Buffers natifs par item : transforms + cellules d'origine (parallelle).
struct BucketItem {
	std::vector<Transform3D> transforms;
	std::vector<int32_t> cellules; // triplets x, y, z, parallelles a transforms
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
	(void)orientation_defaut; // etape (a) ne consomme pas l'orientation
	int masque_sous_plein = (int)e["masque_sous_plein"];
	Vector3 centre_offset = e["centre_offset"];

	PackedInt64Array masques = e["masques"];
	PackedInt64Array couvrants = e["couvrants"];
	PackedInt32Array part_arr = e["particularites"];
	PackedInt32Array sc_arr = e["sous_cubes_partiels"];
	PackedInt32Array pv_arr = e["cellules_pv"];
	PackedInt32Array items_cubiques = e["items_cubiques"];
	PackedInt32Array items_h_cle = e["items_hauteur_cle"];
	PackedFloat32Array items_h_val = e["items_hauteur_val"];

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

	std::unordered_set<Vector3i, Vec3iHash> cellules_pv;
	cellules_pv.reserve((size_t)(pv_arr.size() / 3));
	for (int k = 0; k + 2 < pv_arr.size(); k += 3) {
		cellules_pv.insert(Vector3i(pv_arr[k], pv_arr[k + 1], pv_arr[k + 2]));
	}

	// ----- buffers de sortie natifs ------------------------------------------
	std::unordered_map<int, BucketItem> par_forme;
	std::unordered_map<int, BucketItem> par_forme_sol;

	// Voisin couvre-t-il ? Reduit a un test de bit sur le masque couvrant du
	// voisin, apres verification de la plage de rang. Voir la reduction dans
	// l'entete du fichier .gd -- meme semantique que _voisin_couvre GDScript.
	auto voisin_couvre = [&](int64_t couvrant_voisin, int rang) -> bool {
		if (rang < 0 || rang >= couches_max) return false;
		return (couvrant_voisin & ((int64_t)1 << rang)) != 0;
	};

	// Ajout d'UNE face i sur item, centree en `centre`. Portage exact de
	// _ajouter_face (rendu_terrain_multimesh.gd:773-801) : dessus/dessous
	// abaissee pour un item plus court que la cellule ; faces laterales avec
	// Y-scale (ratio = h/cote) et recentrage a mi-hauteur du slab.
	auto ajouter_face = [&](BucketItem &bucket, int item, const Vector3 &centre,
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
			// Scale la composante Y de CHAQUE colonne de la base (equivalent
			// GDScript : b.x.y *= ratio, b.y.y *= ratio, b.z.y *= ratio). En
			// stockage lignes de Godot, rows[1] tient m10/m11/m12 = Y-comp
			// des 3 colonnes -- multiplier la ligne entiere fait exactement ca.
			base.rows[1] = base.rows[1] * ratio;
			origine = centre + n * (cote * (real_t)0.5) + Vector3(0, (h - cote) * (real_t)0.5, 0);
		}
		bucket.transforms.emplace_back(base, origine);
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

			int64_t nxp = masques[(lx + 2) + (lz + 1) * wsize];
			int64_t nxm = masques[(lx    ) + (lz + 1) * wsize];
			int64_t nzp = masques[(lx + 1) + (lz + 2) * wsize];
			int64_t nzm = masques[(lx + 1) + (lz    ) * wsize];
			(void)nxp; (void)nxm; (void)nzp; (void)nzm; // reserves pour etape (b) non-cubes

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
				if (code == -1) {
					item = item_defaut;
				} else {
					item = code / ORIENTATIONS;
				}
				if (item == item_limite) continue;

				// ETAPE (a) : le C++ ne prend en charge QUE les cubes propres.
				// Non-cubes -> laisses au GDScript (etape (b)).
				if (is_cubic.find(item) == is_cubic.end()) continue;

				// Cellule entamee ou sous PV -> mini-cubes GDScript (etape (b)).
				int masque_sous = masque_sous_plein;
				auto sit = sous_cubes_partiels.find(cellule);
				if (sit != sous_cubes_partiels.end()) masque_sous = sit->second;
				bool a_pv = (cellules_pv.find(cellule) != cellules_pv.end());
				if (masque_sous != masque_sous_plein || a_pv) continue;

				// Cube propre : emission des 6 faces exposees.
				Vector3 pos(
					(real_t)cellule.x * cote + centre_offset.x,
					(real_t)cellule.y * cote + centre_offset.y,
					(real_t)cellule.z * cote + centre_offset.z);
				BucketItem &bucket = (couche == sommet_base) ? par_forme_sol[item] : par_forme[item];

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
	auto to_dict = [](std::unordered_map<int, BucketItem> &m) -> Dictionary {
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
			// std::vector<int32_t> contigu, memcpy legal vers PackedInt32Array
			// dont le buffer sous-jacent est int32_t.
			if (nc > 0) {
				std::memcpy(cells.ptrw(), kv.second.cellules.data(), (size_t)nc * sizeof(int32_t));
			}
			d["transforms"] = tf;
			d["cellules"] = cells;
			out[kv.first] = d;
		}
		return out;
	};

	Dictionary result;
	result["par_forme"] = to_dict(par_forme);
	result["par_forme_sol"] = to_dict(par_forme_sol);
	return result;
}
