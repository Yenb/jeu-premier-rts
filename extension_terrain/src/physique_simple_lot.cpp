#include "physique_simple_lot.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>

using namespace godot;

namespace {

// floori compatible avec le miroir GDScript (floori(x * inv_cote)) : arrondi
// vers moins l'infini, pas troncature.
inline int floori(float v) {
	return (int)std::floor(v);
}

inline int clampi(int v, int lo, int hi) {
	if (v < lo) return lo;
	if (v > hi) return hi;
	return v;
}

} // namespace

void PhysiqueSimpleLot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("pas_simple_lot", "entree"), &PhysiqueSimpleLot::pas_simple_lot);
}

PhysiqueSimpleLot::PhysiqueSimpleLot() {}
PhysiqueSimpleLot::~PhysiqueSimpleLot() {}

Dictionary PhysiqueSimpleLot::pas_simple_lot(const Dictionary &entree) const {
	Dictionary sortie;

	PackedVector3Array positions = entree["position"];
	PackedVector3Array velocites = entree["velocite"];
	PackedVector3Array desirees = entree["desiree"];
	PackedByteArray au_sols = entree["au_sol"];
	PackedInt32Array slots = entree["slot"];
	PackedFloat32Array buffer = entree["buffer"];
	int count = (int)entree["count"];
	float gravite = (float)(double)entree["gravite"];
	float delta = (float)(double)entree["delta"];
	float vitesse_terminale = (float)(double)entree["vitesse_terminale"];
	PackedFloat32Array table = entree["table"];
	int demi_cote = (int)entree["demi_cote"];
	float cote = (float)(double)entree["cote"];

	PackedInt32Array indices_a_repasser;

	if (delta <= 0.0f || count <= 0 || cote <= 0.0f) {
		sortie["position"] = positions;
		sortie["velocite"] = velocites;
		sortie["au_sol"] = au_sols;
		sortie["buffer"] = buffer;
		sortie["indices_a_repasser"] = indices_a_repasser;
		return sortie;
	}

	// Pointeurs bruts ptrw : muter en place, aucun appel per-index sur
	// operator[] Godot Variant.
	Vector3 *pos_w = positions.ptrw();
	Vector3 *vel_w = velocites.ptrw();
	const Vector3 *des_r = desirees.ptr();
	uint8_t *au_sol_w = au_sols.ptrw();
	const int32_t *slot_r = slots.ptr();
	float *buffer_w = buffer.ptrw();
	const float *table_r = table.ptr();

	const float inv_cote = 1.0f / cote;
	const float trois_sur_cote = 3.0f * inv_cote;
	const int cote_lin = 2 * demi_cote;
	const float g_dt = gravite * delta;
	const float vt = -vitesse_terminale;

	for (int i = 0; i < count; i++) {
		// --- S.2 a S.4 : gravite, terminale, composition horizontale ---
		Vector3 ve = vel_w[i];
		ve.y -= g_dt;
		if (ve.y < vt) {
			ve.y = vt;
		}
		Vector3 vdh = des_r[i];
		ve.x = vdh.x;
		ve.z = vdh.z;

		// --- S.5 : deplacement candidat ---
		float dep_x = ve.x * delta;
		float dep_y = ve.y * delta;
		float dep_z = ve.z * delta;
		Vector3 pos = pos_w[i];

		// --- sol sous les pieds ---
		float x1 = pos.x;
		float z1 = pos.z;
		float ymax1 = pos.y + cote;
		int cx1 = floori(x1 * inv_cote);
		int cz1 = floori(z1 * inv_cote);
		float sol_ici_val = 0.0f;
		bool sol_ici_present = false;
		if (cx1 >= -demi_cote && cx1 < demi_cote && cz1 >= -demi_cote && cz1 < demi_cote) {
			float xl1 = x1 - (float)cx1 * cote;
			float zl1 = z1 - (float)cz1 * cote;
			int ix1 = clampi(floori(xl1 * trois_sur_cote), 0, 2);
			int iz1 = clampi(floori(zl1 * trois_sur_cote), 0, 2);
			int idx1 = ((cx1 + demi_cote) + (cz1 + demi_cote) * cote_lin) * 9 + ix1 + iz1 * 3;
			float cache1 = table_r[idx1];
			if (!std::isnan(cache1) && cache1 <= ymax1) {
				sol_ici_val = cache1;
				sol_ici_present = true;
			}
		}

		// --- sol devant ---
		float x2 = pos.x + dep_x;
		float z2 = pos.z + dep_z;
		float ymax2 = pos.y + cote;
		int cx2 = floori(x2 * inv_cote);
		int cz2 = floori(z2 * inv_cote);
		float sol_dv_val = 0.0f;
		bool sol_dv_present = false;
		if (cx2 >= -demi_cote && cx2 < demi_cote && cz2 >= -demi_cote && cz2 < demi_cote) {
			float xl2 = x2 - (float)cx2 * cote;
			float zl2 = z2 - (float)cz2 * cote;
			int ix2 = clampi(floori(xl2 * trois_sur_cote), 0, 2);
			int iz2 = clampi(floori(zl2 * trois_sur_cote), 0, 2);
			int idx2 = ((cx2 + demi_cote) + (cz2 + demi_cote) * cote_lin) * 9 + ix2 + iz2 * 3;
			float cache2 = table_r[idx2];
			if (!std::isnan(cache2) && cache2 <= ymax2) {
				sol_dv_val = cache2;
				sol_dv_present = true;
			}
		}

		// --- MISS : au moins un des deux tests amont a rate. Renvoyer l'indice
		// a l'appelant (rejeu GDScript sur cet indice seul). AUCUNE mutation ici
		// pour cette unite -- ni ve/pos/au_sol, ni le buffer. C'est ce contrat
		// qui garantit que le rejeu GDScript part de l'etat exact d'entree.
		if (!sol_ici_present || !sol_dv_present) {
			indices_a_repasser.push_back(i);
			continue;
		}

		if (sol_dv_val - sol_ici_val > cote) {
			dep_x = 0.0f;
			dep_z = 0.0f;
			ve.x = 0.0f;
			ve.z = 0.0f;
		}

		// --- S.7 : application ---
		pos.x += dep_x;
		pos.z += dep_z;
		pos.y += dep_y;

		// --- S.8 : snap sol (3e lecture) ---
		float x3 = pos.x;
		float z3 = pos.z;
		float ymax3 = pos.y + cote;
		int cx3 = floori(x3 * inv_cote);
		int cz3 = floori(z3 * inv_cote);
		float sol_val = 0.0f;
		bool sol_present = false;
		if (cx3 >= -demi_cote && cx3 < demi_cote && cz3 >= -demi_cote && cz3 < demi_cote) {
			float xl3 = x3 - (float)cx3 * cote;
			float zl3 = z3 - (float)cz3 * cote;
			int ix3 = clampi(floori(xl3 * trois_sur_cote), 0, 2);
			int iz3 = clampi(floori(zl3 * trois_sur_cote), 0, 2);
			int idx3 = ((cx3 + demi_cote) + (cz3 + demi_cote) * cote_lin) * 9 + ix3 + iz3 * 3;
			float cache3 = table_r[idx3];
			if (!std::isnan(cache3) && cache3 <= ymax3) {
				sol_val = cache3;
				sol_present = true;
			}
		}
		if (!sol_present) {
			// Miss sur le 3e test aussi -- rejeu GDScript. On a deja mute pos/ve
			// localement (variables de pile), mais on n'a PAS ecrit dans les
			// PackedArray de sortie pour cet indice -- rien a annuler.
			indices_a_repasser.push_back(i);
			continue;
		}

		bool contact = pos.y <= sol_val;
		if (contact) {
			pos.y = sol_val;
		}
		bool au_sol_final = contact && ve.y <= 0.0f;
		au_sol_w[i] = au_sol_final ? 1 : 0;
		if (au_sol_final) {
			ve.y = 0.0f;
		}

		// --- S.10 : ecriture colonnes ---
		vel_w[i] = ve;
		pos_w[i] = pos;

		// --- Buffer MultiMesh (layout TRANSFORM_3D 12 floats/slot) ---
		int slot = slot_r[i];
		if (slot >= 0) {
			int base = slot * 12;
			buffer_w[base + 3] = pos.x;
			buffer_w[base + 7] = pos.y;
			buffer_w[base + 11] = pos.z;
		}
	}

	sortie["position"] = positions;
	sortie["velocite"] = velocites;
	sortie["au_sol"] = au_sols;
	sortie["buffer"] = buffer;
	sortie["indices_a_repasser"] = indices_a_repasser;
	return sortie;
}
