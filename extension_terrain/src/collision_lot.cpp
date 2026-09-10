#include "collision_lot.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

using namespace godot;

namespace {

// --- Constantes miroir de collision.gd ---
constexpr double COL_EPS = 1e-8;
constexpr double COL_TOL_EPA = 1e-4;
constexpr int COL_GJK_ITER = 32;
constexpr int COL_EPA_ITER = 32;

// --- Types de forme (miroir des Strings de collision.gd) ---
constexpr int FORME_SPHERE = 0;
constexpr int FORME_BOITE = 1;
constexpr int FORME_CAPSULE = 2;
constexpr int FORME_HULL = 3;

// --- Constructeurs Basis / Transform depuis PackedFloat32Array aplati ---
// Basis : 9 floats row-major (rows[0].x, rows[0].y, rows[0].z, rows[1].x, ...).
inline Basis lire_basis(const float *p) {
	Basis b;
	b.rows[0] = Vector3(p[0], p[1], p[2]);
	b.rows[1] = Vector3(p[3], p[4], p[5]);
	b.rows[2] = Vector3(p[6], p[7], p[8]);
	return b;
}

// Transform3D : 9 basis + 3 origin.
inline Transform3D lire_transform(const float *p) {
	Transform3D t;
	t.basis = lire_basis(p);
	t.origin = Vector3(p[9], p[10], p[11]);
	return t;
}

inline bool basis_est_identity(const Basis &b) {
	return b == Basis();
}

// --- SUPPORT LOCAL (miroir de collision.gd::_support_local) ---
Vector3 support_local(int type, const float *params, const Vector3 *hull_points_ptr,
		const Vector3 &d) {
	switch (type) {
		case FORME_SPHERE: {
			real_t r = params[0];
			// dn = d.normalized() if length_squared > 0, sinon Vector3.RIGHT.
			// GDScript utilise length_squared() strict > 0.0 (double 0.0 comparaison).
			double lsq = (double)d.length_squared();
			Vector3 dn = (lsq > 0.0) ? d.normalized() : Vector3(1, 0, 0);
			return dn * r;
		}
		case FORME_BOITE: {
			real_t hx = params[0], hy = params[1], hz = params[2];
			return Vector3(
					d.x >= 0.0f ? hx : -hx,
					d.y >= 0.0f ? hy : -hy,
					d.z >= 0.0f ? hz : -hz);
		}
		case FORME_CAPSULE: {
			real_t r = params[0], ht = params[1];
			real_t demi_seg = std::max((real_t)0.0, (real_t)(ht * (real_t)0.5 - r));
			Vector3 base(0, d.y >= 0.0f ? demi_seg : -demi_seg, 0);
			double lsq = (double)d.length_squared();
			Vector3 dn = (lsq > 0.0) ? d.normalized() : Vector3(0, 1, 0);
			return base + dn * r;
		}
		case FORME_HULL: {
			int debut = (int)params[0];
			int count = (int)params[1];
			if (count <= 0) {
				return Vector3(0, 0, 0);
			}
			Vector3 meilleur = hull_points_ptr[debut];
			double meilleur_d = (double)meilleur.dot(d);
			for (int i = 0; i < count; i++) {
				Vector3 q = hull_points_ptr[debut + i];
				double qd = (double)q.dot(d);
				if (qd > meilleur_d) {
					meilleur_d = qd;
					meilleur = q;
				}
			}
			return meilleur;
		}
	}
	return Vector3(0, 0, 0);
}

// --- SUPPORT MONDE (miroir de collision.gd::support) ---
// dir ramenee en local par basis.inverse(), point remis en monde.
Vector3 support_monde(int type, const float *params, const Vector3 *hull_points_ptr,
		const Transform3D &tf_monde, const Vector3 &dir_monde) {
	Vector3 dir_local = tf_monde.basis.inverse().xform(dir_monde);
	Vector3 p_local = support_local(type, params, hull_points_ptr, dir_local);
	return tf_monde.xform(p_local);
}

// --- AABB par 6 supports (miroir de collision.gd::aabb_forme, boucle generique).
// Raccourci boite-alignee applique par l'appelant (aabb_locale_de_forme et
// aabb_monde_forme).
AABB aabb_via_supports(int type, const float *params, const Vector3 *hull_points_ptr,
		const Transform3D &tf_monde) {
	static const Vector3 axes[6] = {
			Vector3(1, 0, 0), Vector3(-1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, -1, 0),
			Vector3(0, 0, 1), Vector3(0, 0, -1)};
	Vector3 premier = support_monde(type, params, hull_points_ptr, tf_monde, axes[0]);
	Vector3 mn = premier;
	Vector3 mx = premier;
	for (int i = 1; i < 6; i++) {
		Vector3 s = support_monde(type, params, hull_points_ptr, tf_monde, axes[i]);
		mn.x = std::min(mn.x, s.x);
		mn.y = std::min(mn.y, s.y);
		mn.z = std::min(mn.z, s.z);
		mx.x = std::max(mx.x, s.x);
		mx.y = std::max(mx.y, s.y);
		mx.z = std::max(mx.z, s.z);
	}
	return AABB(mn, mx - mn);
}

// AABB monde d'une forme, avec raccourci boite-alignee (identique GDScript).
AABB aabb_monde_forme(int type, const float *params, const Vector3 *hull_points_ptr,
		const Transform3D &tf_monde) {
	if (type == FORME_BOITE && basis_est_identity(tf_monde.basis)) {
		Vector3 h(params[0], params[1], params[2]);
		return AABB(tf_monde.origin - h, h * (real_t)2.0);
	}
	return aabb_via_supports(type, params, hull_points_ptr, tf_monde);
}

// AABB LOCALE d'une forme (a l'origine, orient IDENTITY, avec transform_locale
// applique). Miroir de _aabb_locale_de_forme -> aabb_forme(forme, tf_locale).
AABB aabb_locale_forme(int type, const float *params, const Vector3 *hull_points_ptr,
		const Transform3D &tf_locale) {
	return aabb_monde_forme(type, params, hull_points_ptr, tf_locale);
}

// --- TAILLE MIN d'une forme (miroir de collision.gd::_taille_min_forme).
double taille_min_forme(int type, const float *params, const Vector3 *hull_points_ptr) {
	switch (type) {
		case FORME_SPHERE:
			return (double)params[0];
		case FORME_BOITE:
			return (double)std::min(params[0], std::min(params[1], params[2]));
		case FORME_CAPSULE:
			return (double)params[0];
		case FORME_HULL: {
			int debut = (int)params[0];
			int count = (int)params[1];
			if (count <= 0) {
				return 0.0;
			}
			Vector3 mn = hull_points_ptr[debut];
			Vector3 mx = mn;
			for (int i = 0; i < count; i++) {
				Vector3 q = hull_points_ptr[debut + i];
				mn.x = std::min(mn.x, q.x);
				mn.y = std::min(mn.y, q.y);
				mn.z = std::min(mn.z, q.z);
				mx.x = std::max(mx.x, q.x);
				mx.y = std::max(mx.y, q.y);
				mx.z = std::max(mx.z, q.z);
			}
			Vector3 half = (mx - mn) * (real_t)0.5;
			return (double)std::min(half.x, std::min(half.y, half.z));
		}
	}
	return 0.0;
}

// --- GJK ---
// _support_minkowski : support(A, d) - support(B, -d).
inline Vector3 support_minkowski(
		int type_a, const float *params_a, const Transform3D &tf_a,
		int type_b, const float *params_b, const Transform3D &tf_b,
		const Vector3 *hull_points_ptr, const Vector3 &dir) {
	Vector3 sa = support_monde(type_a, params_a, hull_points_ptr, tf_a, dir);
	Vector3 sb = support_monde(type_b, params_b, hull_points_ptr, tf_b, -dir);
	return sa - sb;
}

// Perpendiculaire non-nul (miroir _perpendiculaire).
inline Vector3 perpendiculaire(const Vector3 &v) {
	Vector3 c = v.cross(Vector3(1, 0, 0));
	if ((double)c.length_squared() < COL_EPS) {
		c = v.cross(Vector3(0, 1, 0));
	}
	return c;
}

// _do_simplexe / _ligne / _triangle / _tetra : mute `s` en place.
// Rend { contient: bool, dir: Vector3 } via out params.
void gjk_ligne(std::vector<Vector3> &s, bool &contient, Vector3 &dir_out) {
	Vector3 a = s[0];
	Vector3 b = s[1];
	Vector3 ab = b - a;
	Vector3 ao = -a;
	if ((double)ab.dot(ao) > 0.0) {
		Vector3 dir = ab.cross(ao).cross(ab);
		if ((double)dir.length_squared() < COL_EPS) {
			dir = perpendiculaire(ab);
		}
		contient = false;
		dir_out = dir;
		return;
	}
	s.clear();
	s.push_back(a);
	contient = false;
	dir_out = ao;
}

void gjk_triangle(std::vector<Vector3> &s, bool &contient, Vector3 &dir_out) {
	Vector3 a = s[0];
	Vector3 b = s[1];
	Vector3 c = s[2];
	Vector3 ab = b - a;
	Vector3 ac = c - a;
	Vector3 ao = -a;
	Vector3 abc = ab.cross(ac);
	if ((double)abc.cross(ac).dot(ao) > 0.0) {
		if ((double)ac.dot(ao) > 0.0) {
			s.clear();
			s.push_back(a);
			s.push_back(c);
			contient = false;
			dir_out = ac.cross(ao).cross(ac);
			return;
		}
		s.clear();
		s.push_back(a);
		s.push_back(b);
		gjk_ligne(s, contient, dir_out);
		return;
	}
	if ((double)ab.cross(abc).dot(ao) > 0.0) {
		s.clear();
		s.push_back(a);
		s.push_back(b);
		gjk_ligne(s, contient, dir_out);
		return;
	}
	if ((double)abc.dot(ao) > 0.0) {
		contient = false;
		dir_out = abc;
		return;
	}
	s.clear();
	s.push_back(a);
	s.push_back(c);
	s.push_back(b);
	contient = false;
	dir_out = -abc;
}

void gjk_tetra(std::vector<Vector3> &s, bool &contient, Vector3 &dir_out) {
	Vector3 a = s[0];
	Vector3 b = s[1];
	Vector3 c = s[2];
	Vector3 d = s[3];
	Vector3 ao = -a;
	Vector3 ab = b - a;
	Vector3 ac = c - a;
	Vector3 ad = d - a;
	if ((double)ab.cross(ac).dot(ao) > 0.0) {
		s.clear();
		s.push_back(a);
		s.push_back(b);
		s.push_back(c);
		gjk_triangle(s, contient, dir_out);
		return;
	}
	if ((double)ac.cross(ad).dot(ao) > 0.0) {
		s.clear();
		s.push_back(a);
		s.push_back(c);
		s.push_back(d);
		gjk_triangle(s, contient, dir_out);
		return;
	}
	if ((double)ad.cross(ab).dot(ao) > 0.0) {
		s.clear();
		s.push_back(a);
		s.push_back(d);
		s.push_back(b);
		gjk_triangle(s, contient, dir_out);
		return;
	}
	contient = true;
	dir_out = Vector3(0, 0, 0);
}

void gjk_do_simplexe(std::vector<Vector3> &s, bool &contient, Vector3 &dir_out) {
	switch (s.size()) {
		case 2:
			gjk_ligne(s, contient, dir_out);
			return;
		case 3:
			gjk_triangle(s, contient, dir_out);
			return;
		case 4:
			gjk_tetra(s, contient, dir_out);
			return;
	}
	contient = false;
	dir_out = Vector3(0, 0, 0);
}

// GJK : rend true si intersection, remplit simplexe (tetrahedre de Minkowski).
bool gjk(int type_a, const float *params_a, const Transform3D &tf_a,
		int type_b, const float *params_b, const Transform3D &tf_b,
		const Vector3 *hull_points_ptr, std::vector<Vector3> &simplexe_out) {
	Vector3 s0 = support_minkowski(type_a, params_a, tf_a, type_b, params_b, tf_b,
			hull_points_ptr, Vector3(1, 0, 0));
	simplexe_out.clear();
	simplexe_out.push_back(s0);
	Vector3 dir = -s0;
	for (int i = 0; i < COL_GJK_ITER; i++) {
		if ((double)dir.length_squared() < COL_EPS) {
			// Origine deja sur le simplexe : contact frontalier.
			return true;
		}
		Vector3 a = support_minkowski(type_a, params_a, tf_a, type_b, params_b, tf_b,
				hull_points_ptr, dir);
		if ((double)a.dot(dir) < 0.0) {
			return false;
		}
		// push_front(a) : GDScript insere a l'index 0.
		simplexe_out.insert(simplexe_out.begin(), a);
		bool contient = false;
		Vector3 nouv_dir(0, 0, 0);
		gjk_do_simplexe(simplexe_out, contient, nouv_dir);
		if (contient) {
			return true;
		}
		dir = nouv_dir;
	}
	return false;
}

// --- EPA ---
struct FaceEPA {
	int a, b, c;
	Vector3 normale;
	double distance;
};

// _face : normale sortante, distance signee >= 0 (retourne winding si negatif).
FaceEPA epa_face(const std::vector<Vector3> &verts, int ia, int ib, int ic) {
	Vector3 a = verts[ia];
	Vector3 b = verts[ib];
	Vector3 c = verts[ic];
	Vector3 n_vec = (b - a).cross(c - a);
	double l = (double)n_vec.length();
	FaceEPA f;
	if (l < COL_EPS) {
		f.a = ia; f.b = ib; f.c = ic;
		f.normale = Vector3(0, 0, 0);
		f.distance = std::numeric_limits<double>::infinity();
		return f;
	}
	Vector3 n = n_vec / (real_t)l;
	double dist = (double)n.dot(a);
	if (dist < 0.0) {
		f.a = ia; f.b = ic; f.c = ib;
		f.normale = -n;
		f.distance = -dist;
	} else {
		f.a = ia; f.b = ib; f.c = ic;
		f.normale = n;
		f.distance = dist;
	}
	return f;
}

int epa_face_plus_proche(const std::vector<FaceEPA> &faces) {
	int best = 0;
	double bd = faces[0].distance;
	for (size_t k = 1; k < faces.size(); k++) {
		if (faces[k].distance < bd) {
			bd = faces[k].distance;
			best = (int)k;
		}
	}
	return best;
}

void epa_ajouter_bord(std::vector<std::pair<int, int>> &aretes, int i, int j) {
	for (size_t k = 0; k < aretes.size(); k++) {
		if (aretes[k].first == j && aretes[k].second == i) {
			aretes.erase(aretes.begin() + k);
			return;
		}
	}
	aretes.push_back(std::make_pair(i, j));
}

// EPA : rend normale + profondeur.
void epa(const std::vector<Vector3> &simplexe,
		int type_a, const float *params_a, const Transform3D &tf_a,
		int type_b, const float *params_b, const Transform3D &tf_b,
		const Vector3 *hull_points_ptr,
		Vector3 &normale_out, double &profondeur_out) {
	if (simplexe.size() < 4) {
		normale_out = Vector3(0, 1, 0);
		profondeur_out = 0.0;
		return;
	}
	std::vector<Vector3> verts = simplexe;
	std::vector<FaceEPA> faces;
	faces.push_back(epa_face(verts, 0, 1, 2));
	faces.push_back(epa_face(verts, 0, 2, 3));
	faces.push_back(epa_face(verts, 0, 3, 1));
	faces.push_back(epa_face(verts, 1, 3, 2));

	for (int iter = 0; iter < COL_EPA_ITER; iter++) {
		int idx = epa_face_plus_proche(faces);
		FaceEPA f = faces[idx];
		Vector3 p = support_minkowski(type_a, params_a, tf_a, type_b, params_b, tf_b,
				hull_points_ptr, f.normale);
		double d = (double)p.dot(f.normale);
		if (d - f.distance < COL_TOL_EPA) {
			normale_out = f.normale;
			profondeur_out = f.distance;
			return;
		}
		int iv = (int)verts.size();
		verts.push_back(p);
		// Retire les faces qui voient p, recolte les aretes de bordure.
		std::vector<std::pair<int, int>> aretes;
		std::vector<FaceEPA> gardees;
		for (size_t fi = 0; fi < faces.size(); fi++) {
			const FaceEPA &face = faces[fi];
			Vector3 va = verts[face.a];
			if ((double)face.normale.dot(p - va) > 0.0) {
				epa_ajouter_bord(aretes, face.a, face.b);
				epa_ajouter_bord(aretes, face.b, face.c);
				epa_ajouter_bord(aretes, face.c, face.a);
			} else {
				gardees.push_back(face);
			}
		}
		for (size_t ai = 0; ai < aretes.size(); ai++) {
			gardees.push_back(epa_face(verts, aretes[ai].first, aretes[ai].second, iv));
		}
		faces = gardees;
	}
	int idx2 = epa_face_plus_proche(faces);
	normale_out = faces[idx2].normale;
	profondeur_out = faces[idx2].distance;
}

// --- contact_forme_paire ---
// Retourne true si contact, remplit normale et profondeur. Raccourci boite-boite
// AABB alignee (chemin rapide interne).
bool contact_forme_paire(
		int type_a, const float *params_a, const Transform3D &ta,
		int type_b, const float *params_b, const Transform3D &tb,
		const Vector3 *hull_points_ptr,
		Vector3 &normale_out, double &profondeur_out) {
	// RACCOURCI boite-boite AABB alignee.
	if (type_a == FORME_BOITE && type_b == FORME_BOITE
			&& basis_est_identity(ta.basis) && basis_est_identity(tb.basis)) {
		Vector3 ha(params_a[0], params_a[1], params_a[2]);
		Vector3 hb(params_b[0], params_b[1], params_b[2]);
		Vector3 delta_c = tb.origin - ta.origin;
		double rx = (double)(ha.x + hb.x) - std::abs((double)delta_c.x);
		if (rx <= 0.0) return false;
		double ry = (double)(ha.y + hb.y) - std::abs((double)delta_c.y);
		if (ry <= 0.0) return false;
		double rz = (double)(ha.z + hb.z) - std::abs((double)delta_c.z);
		if (rz <= 0.0) return false;
		if (rx <= ry && rx <= rz) {
			// GDScript signf : signf(0) == 0 ; on force +1 dans ce cas
			// (miroir : `s if s != 0.0 else 1.0`).
			double s = (delta_c.x > 0.0f) ? 1.0 : ((delta_c.x < 0.0f) ? -1.0 : 0.0);
			normale_out = Vector3((real_t)(s != 0.0 ? s : 1.0), 0, 0);
			profondeur_out = rx;
		} else if (ry <= rz) {
			double s = (delta_c.y > 0.0f) ? 1.0 : ((delta_c.y < 0.0f) ? -1.0 : 0.0);
			normale_out = Vector3(0, (real_t)(s != 0.0 ? s : 1.0), 0);
			profondeur_out = ry;
		} else {
			double s = (delta_c.z > 0.0f) ? 1.0 : ((delta_c.z < 0.0f) ? -1.0 : 0.0);
			normale_out = Vector3(0, 0, (real_t)(s != 0.0 ? s : 1.0));
			profondeur_out = rz;
		}
		return true;
	}
	// GJK -> EPA general.
	std::vector<Vector3> simplexe;
	if (!gjk(type_a, params_a, ta, type_b, params_b, tb, hull_points_ptr, simplexe)) {
		return false;
	}
	epa(simplexe, type_a, params_a, ta, type_b, params_b, tb, hull_points_ptr,
			normale_out, profondeur_out);
	return true;
}

// --- Fabrication Transform3D monde d'une forme d'entite ---
// Transform monde = Transform3D(orientation, position) * tf_locale.
inline Transform3D tf_monde_forme(const Basis &orient, const Vector3 &pos,
		const Transform3D &tf_locale) {
	Transform3D t_ent;
	t_ent.basis = orient;
	t_ent.origin = pos;
	return t_ent * tf_locale;
}

} // anonymous namespace

// -----------------------------------------------------------------------------

void CollisionLot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("detecter", "entree"), &CollisionLot::detecter);
	ClassDB::bind_method(D_METHOD("resoudre", "entree"), &CollisionLot::resoudre);
	ClassDB::bind_method(D_METHOD("detecter_et_resoudre", "entree"), &CollisionLot::detecter_et_resoudre);
	ClassDB::bind_method(D_METHOD("init_soa_stable", "soa"), &CollisionLot::init_soa_stable);
	ClassDB::bind_method(D_METHOD("derniers_chronos"), &CollisionLot::derniers_chronos);
	ClassDB::bind_method(D_METHOD("derniers_compteurs"), &CollisionLot::derniers_compteurs);
}

void CollisionLot::init_soa_stable(const Dictionary &soa) {
	_velocites = soa["velocites"];
	_orientations = soa["orientations"];
	_masques_c = soa["masques_c"];
	_masques_r = soa["masques_r"];
	_reponses = soa["reponses"];
	_formes_debut = soa["formes_debut"];
	_formes_type = soa["formes_type"];
	_formes_tf_locale = soa["formes_tf_locale"];
	_formes_params = soa["formes_params"];
	_hull_points = soa["hull_points"];
	_soa_stable_initialise = true;
}

CollisionLot::CollisionLot() {}
CollisionLot::~CollisionLot() {}

Dictionary CollisionLot::derniers_chronos() const {
	Dictionary out;
	out["prepasse"] = (int64_t)_us_prepasse;
	out["tri"] = (int64_t)_us_tri;
	out["parcours"] = (int64_t)_us_parcours;
	out["narrowphase"] = (int64_t)_us_narrowphase;
	out["resoudre"] = (int64_t)_us_resoudre;
	return out;
}

Dictionary CollisionLot::derniers_compteurs() const {
	Dictionary out;
	out["paires_distance"] = (int64_t)_n_paires_distance;
	out["paires_dedup"] = (int64_t)_n_paires_dedup;
	out["appels_nf"] = (int64_t)_n_appels_nf;
	out["appels_raccourci"] = (int64_t)_n_appels_raccourci;
	out["appels_gjk"] = (int64_t)_n_appels_gjk;
	out["contacts"] = (int64_t)_n_contacts;
	return out;
}

// =============================================================================
// DETECTER (implementation interne, contacts en std::vector natifs)
// =============================================================================
// Rempli par _detecter_impl, consomme par detecter (conversion en Packed*Array)
// et par detecter_et_resoudre (passe directement a _resoudre_impl). Aucun
// contact ne franchit la frontiere GDScript/C++ entre les deux voies.
void CollisionLot::_detecter_impl(
		const Dictionary &entree,
		bool utiliser_soa_stocke,
		std::vector<int32_t> &contacts_a,
		std::vector<int32_t> &contacts_b,
		std::vector<Vector3> &contacts_normale,
		std::vector<float> &contacts_profondeur) const {
	contacts_a.clear();
	contacts_b.clear();
	contacts_normale.clear();
	contacts_profondeur.clear();

	_us_prepasse = 0;
	_us_tri = 0;
	_us_parcours = 0;
	_us_narrowphase = 0;
	_n_paires_distance = 0;
	_n_paires_dedup = 0;
	_n_appels_nf = 0;
	_n_appels_raccourci = 0;
	_n_appels_gjk = 0;
	_n_contacts = 0;

	// "positions" et "delta" viennent TOUJOURS du Dictionary (le premier mute
	// par frame, le second aussi). Les 10 colonnes stables viennent des membres
	// si utiliser_soa_stocke, sinon du Dictionary (mode fallback pour detecter
	// individuel et pour la voie fusion sans init prealable).
	PackedVector3Array positions = entree["positions"];
	float delta = (float)(double)entree["delta"];

	const int N = positions.size();
	if (N <= 0) {
		return;
	}

	// Locales pour tenir les Packed*Array en vie tant que leurs pointeurs
	// sont deferences. Non allouees quand utiliser_soa_stocke est vrai.
	PackedVector3Array velocites_l;
	PackedFloat32Array orientations_l;
	PackedInt32Array masques_c_l;
	PackedInt32Array masques_r_l;
	PackedByteArray reponses_l;
	PackedInt32Array formes_debut_l;
	PackedInt32Array formes_type_l;
	PackedFloat32Array formes_tf_locale_l;
	PackedFloat32Array formes_params_l;
	PackedVector3Array hull_points_l;

	const Vector3 *pos_r = positions.ptr();
	const Vector3 *vel_r;
	const float *orient_r;
	const int32_t *masques_c_r;
	const int32_t *masques_r_r;
	const uint8_t *reponses_r;
	const int32_t *formes_debut_r;
	const int32_t *formes_type_r;
	const float *formes_tf_r;
	const float *formes_params_r;
	const Vector3 *hull_points_ptr;
	int M;

	if (utiliser_soa_stocke) {
		vel_r = _velocites.ptr();
		orient_r = _orientations.ptr();
		masques_c_r = _masques_c.ptr();
		masques_r_r = _masques_r.ptr();
		reponses_r = _reponses.ptr();
		formes_debut_r = _formes_debut.ptr();
		formes_type_r = _formes_type.ptr();
		formes_tf_r = _formes_tf_locale.ptr();
		formes_params_r = _formes_params.ptr();
		hull_points_ptr = _hull_points.ptr();
		M = _formes_type.size();
	} else {
		velocites_l = entree["velocites"];
		orientations_l = entree["orientations"];
		masques_c_l = entree["masques_c"];
		masques_r_l = entree["masques_r"];
		reponses_l = entree["reponses"];
		formes_debut_l = entree["formes_debut"];
		formes_type_l = entree["formes_type"];
		formes_tf_locale_l = entree["formes_tf_locale"];
		formes_params_l = entree["formes_params"];
		hull_points_l = entree["hull_points"];
		vel_r = velocites_l.ptr();
		orient_r = orientations_l.ptr();
		masques_c_r = masques_c_l.ptr();
		masques_r_r = masques_r_l.ptr();
		reponses_r = reponses_l.ptr();
		formes_debut_r = formes_debut_l.ptr();
		formes_type_r = formes_type_l.ptr();
		formes_tf_r = formes_tf_locale_l.ptr();
		formes_params_r = formes_params_l.ptr();
		hull_points_ptr = hull_points_l.ptr();
		M = formes_type_l.size();
	}

	auto t_prepasse_debut = std::chrono::steady_clock::now();

	// --- Cache par forme (calcule une fois par appel) ---
	// AABB LOCALE : forme placee a orient=IDENTITY, pos=ZERO, avec tf_locale
	// appliquee. Ne depend PAS de la position monde ni de l'orientation entite.
	// M est fourni plus haut (soit _formes_type.size() soit formes_type_l.size()).
	std::vector<AABB> aabb_locale_cache((size_t)M);
	std::vector<double> taille_min_cache((size_t)M);
	for (int fi = 0; fi < M; fi++) {
		Transform3D tf_l = lire_transform(formes_tf_r + fi * 12);
		int type = formes_type_r[fi];
		const float *params = formes_params_r + fi * 4;
		aabb_locale_cache[(size_t)fi] = aabb_locale_forme(type, params, hull_points_ptr, tf_l);
		taille_min_cache[(size_t)fi] = taille_min_forme(type, params, hull_points_ptr);
	}

	// --- Colonnes par entite (miroir des col_* de collision.gd) ---
	std::vector<AABB> col_aabb((size_t)N);
	std::vector<AABB> col_swept((size_t)N);
	std::vector<double> col_taille_min((size_t)N);
	std::vector<uint8_t> col_vel_nz((size_t)N);
	std::vector<double> col_vel_len((size_t)N);
	std::vector<Basis> col_orient((size_t)N);
	double rayon_max = 0.0;

	for (int i = 0; i < N; i++) {
		Basis orient = lire_basis(orient_r + i * 9);
		col_orient[(size_t)i] = orient;
		Vector3 pos = pos_r[i];
		Vector3 vel = vel_r[i];
		double vel_len = (double)vel.length();
		col_vel_len[(size_t)i] = vel_len;
		double vel_lsq = (double)vel.length_squared();
		bool vel_nz = vel_lsq > 0.0;
		col_vel_nz[(size_t)i] = vel_nz ? 1 : 0;

		int fd = formes_debut_r[i];
		int ff = formes_debut_r[i + 1];
		int nf = ff - fd;
		AABB aabb;
		if (nf <= 0) {
			aabb = AABB(pos, Vector3(0, 0, 0));
		} else if (basis_est_identity(orient)) {
			// Chemin rapide : AABB monde = AABB locale + pos.
			AABB l0 = aabb_locale_cache[(size_t)fd];
			aabb = AABB(l0.position + pos, l0.size);
			for (int fi = 1; fi < nf; fi++) {
				AABB li = aabb_locale_cache[(size_t)(fd + fi)];
				aabb = aabb.merge(AABB(li.position + pos, li.size));
			}
		} else {
			// Orient tournee : recalcul complet via aabb_forme(tf_monde).
			Transform3D tf_l0 = lire_transform(formes_tf_r + fd * 12);
			int t0 = formes_type_r[fd];
			const float *p0 = formes_params_r + fd * 4;
			Transform3D tm0 = tf_monde_forme(orient, pos, tf_l0);
			aabb = aabb_monde_forme(t0, p0, hull_points_ptr, tm0);
			for (int fi = 1; fi < nf; fi++) {
				Transform3D tf_li = lire_transform(formes_tf_r + (fd + fi) * 12);
				int ti = formes_type_r[fd + fi];
				const float *pi = formes_params_r + (fd + fi) * 4;
				Transform3D tmi = tf_monde_forme(orient, pos, tf_li);
				aabb = aabb.merge(aabb_monde_forme(ti, pi, hull_points_ptr, tmi));
			}
		}
		col_aabb[(size_t)i] = aabb;
		AABB swept = aabb;
		if (vel_nz) {
			swept = aabb.merge(AABB(aabb.position - vel * delta, aabb.size));
		}
		col_swept[(size_t)i] = swept;
		// Taille min = min sur formes de l'entite.
		double tm = std::numeric_limits<double>::infinity();
		for (int fi = 0; fi < nf; fi++) {
			double t = taille_min_cache[(size_t)(fd + fi)];
			if (t < tm) tm = t;
		}
		col_taille_min[(size_t)i] = (tm == std::numeric_limits<double>::infinity()) ? 0.0 : tm;
		double demi_diag = (double)aabb.size.length() * 0.5;
		if (demi_diag > rayon_max) rayon_max = demi_diag;
	}

	_us_prepasse = std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - t_prepasse_debut).count();
	auto t_tri_debut = std::chrono::steady_clock::now();

	// --- Broadphase : counting sort par cellule ---
	std::vector<double> r_par_i((size_t)N);
	double arete_max = 0.0;
	for (int i = 0; i < N; i++) {
		double hd = (double)col_aabb[(size_t)i].size.length() * 0.5;
		double r_i = hd + rayon_max + col_vel_len[(size_t)i] * (double)delta;
		r_par_i[(size_t)i] = r_i;
		if (r_i > arete_max) arete_max = r_i;
	}
	double arete = std::max(arete_max * 1.0001, 1e-6);
	double inv_arete = 1.0 / arete;

	std::vector<int32_t> cx_arr((size_t)N);
	std::vector<int32_t> cy_arr((size_t)N);
	std::vector<int32_t> cz_arr((size_t)N);
	int32_t cx_min = 0x7fffffff, cx_max = -0x7fffffff - 1;
	int32_t cy_min = 0x7fffffff, cy_max = -0x7fffffff - 1;
	int32_t cz_min = 0x7fffffff, cz_max = -0x7fffffff - 1;
	for (int i = 0; i < N; i++) {
		Vector3 p = pos_r[i];
		int32_t cx = (int32_t)std::floor((double)p.x * inv_arete);
		int32_t cy = (int32_t)std::floor((double)p.y * inv_arete);
		int32_t cz = (int32_t)std::floor((double)p.z * inv_arete);
		cx_arr[(size_t)i] = cx;
		cy_arr[(size_t)i] = cy;
		cz_arr[(size_t)i] = cz;
		if (cx < cx_min) cx_min = cx;
		if (cx > cx_max) cx_max = cx;
		if (cy < cy_min) cy_min = cy;
		if (cy > cy_max) cy_max = cy;
		if (cz < cz_min) cz_min = cz;
		if (cz > cz_max) cz_max = cz;
	}
	int64_t Nx = (int64_t)cx_max - cx_min + 1;
	int64_t Ny = (int64_t)cy_max - cy_min + 1;
	int64_t Nz = (int64_t)cz_max - cz_min + 1;
	int64_t NxNy = Nx * Ny;
	int64_t total = Nx * Ny * Nz;
	if (total > 1000000) {
		ERR_PRINT("CollisionLot::detecter : grille locale > 1M cases");
	}

	std::vector<int32_t> cell_ids((size_t)N);
	std::vector<int32_t> counts((size_t)total, 0);
	for (int i = 0; i < N; i++) {
		int64_t cid = (int64_t)(cx_arr[(size_t)i] - cx_min)
				+ (int64_t)(cy_arr[(size_t)i] - cy_min) * Nx
				+ (int64_t)(cz_arr[(size_t)i] - cz_min) * NxNy;
		cell_ids[(size_t)i] = (int32_t)cid;
		counts[(size_t)cid]++;
	}
	std::vector<int32_t> offsets((size_t)(total + 1));
	int32_t acc = 0;
	for (int64_t c = 0; c < total; c++) {
		offsets[(size_t)c] = acc;
		acc += counts[(size_t)c];
	}
	offsets[(size_t)total] = acc;
	std::vector<int32_t> sorted_idx((size_t)N);
	std::vector<int32_t> cursor((size_t)total, 0);
	for (int i = 0; i < N; i++) {
		int32_t cid = cell_ids[(size_t)i];
		sorted_idx[(size_t)(offsets[(size_t)cid] + cursor[(size_t)cid])] = i;
		cursor[(size_t)cid]++;
	}

	_us_tri = std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - t_tri_debut).count();

	// --- Parcours par cellule, DEMI-VOISINAGE, batch de paires ---
	// Chaque paire (i, j) est visitee UNE SEULE fois : la hashmap vus est
	// supprimee. Sur un peuplement dense, un find+insert par paire dans un
	// unordered_map dominait us_parcours (315k operations/frame a N=20000).
	//
	// GEOMETRIE : pour la cellule courante c, on visite
	//   - INTRA-cellule : paires (i, j) avec j apres i dans sorted_idx (donc
	//     j > i puisque le counting sort est stable et remplit sorted_idx dans
	//     l'ordre des IDs 0..N-1).
	//   - INTER-cellules : les 13 cellules d'offset (dx, dy, dz) STRICTEMENT
	//     superieur a (0, 0, 0) en ordre lexicographique (dz>0 OU (dz==0 ET
	//     dy>0) OU (dz==0 ET dy==0 ET dx>0)) -- couvre chaque paire de cellules
	//     adjacentes une seule fois.
	//
	// FILTRE DISTANCE : d2 <= max(r_i, r_j)^2. Le parcours actuel testait
	// d2 <= r_source^2 aux DEUX visites -> l'entree effective etait un OU
	// (max) ; en demi-voisinage on materialise ce max directement. Meme
	// ensemble de paires.
	//
	// LA BOUCLE N'APPELLE PAS contact_forme_paire : les paires retenues sont
	// poussees dans batch_paires, consommees juste apres par le narrowphase.
	struct PaireCandidat {
		int32_t i;
		int32_t j;
	};
	std::vector<PaireCandidat> batch_paires;
	batch_paires.reserve((size_t)N * 4);

	auto t_parcours_debut = std::chrono::steady_clock::now();

	// Les 13 offsets de cellules "superieures" en ordre lex : (dx, dy, dz) > (0, 0, 0).
	// Enumerer via dz de -1 a +1, dy de -1 a +1, dx de -1 a +1, en gardant seulement
	// ceux qui sont "> (0,0,0)" lexicographiquement. Ordre absolu peu important :
	// le tri stable final normalise l'ordre des contacts.
	static const int OFFSETS_DEMI[13][3] = {
		{1, 0, 0},
		{-1, 1, 0}, {0, 1, 0}, {1, 1, 0},
		{-1, -1, 1}, {0, -1, 1}, {1, -1, 1},
		{-1, 0, 1},  {0, 0, 1},  {1, 0, 1},
		{-1, 1, 1},  {0, 1, 1},  {1, 1, 1},
	};

	for (int64_t c = 0; c < total; c++) {
		int32_t start_c = offsets[(size_t)c];
		int32_t end_c = offsets[(size_t)(c + 1)];
		if (start_c == end_c) continue;
		int64_t lcz = c / NxNy;
		int64_t reste = c - lcz * NxNy;
		int64_t lcy = reste / Nx;
		int64_t lcx = reste - lcy * Nx;
		for (int32_t pi = start_c; pi < end_c; pi++) {
			int32_t i = sorted_idx[(size_t)pi];
			Vector3 pos_a = pos_r[i];
			double r_i = r_par_i[(size_t)i];
			int32_t masque_a = masques_c_r[i];
			AABB swept_a = col_swept[(size_t)i];

			// --- INTRA-cellule : paires (i, j) avec pj > pi (donc j > i) ---
			for (int32_t pj = pi + 1; pj < end_c; pj++) {
				int32_t j = sorted_idx[(size_t)pj];
				Vector3 pos_b = pos_r[j];
				double d2 = (double)pos_a.distance_squared_to(pos_b);
				double r_j = r_par_i[(size_t)j];
				double r_max = r_i > r_j ? r_i : r_j;
				double r_max_sq = r_max * r_max;
				if (d2 > r_max_sq) continue;
				_n_paires_distance++;
				_n_paires_dedup++;  // pas de dedup en demi-voisinage : identique a paires_distance
				if ((masque_a & masques_c_r[j]) == 0) continue;
				if (!swept_a.intersects(col_swept[(size_t)j])) continue;
				PaireCandidat pc;
				pc.i = i;
				pc.j = j;
				batch_paires.push_back(pc);
			}

			// --- INTER-cellules : 13 offsets "superieurs" ---
			for (int k_off = 0; k_off < 13; k_off++) {
				int64_t vcx = lcx + OFFSETS_DEMI[k_off][0];
				if (vcx < 0 || vcx >= Nx) continue;
				int64_t vcy = lcy + OFFSETS_DEMI[k_off][1];
				if (vcy < 0 || vcy >= Ny) continue;
				int64_t vcz = lcz + OFFSETS_DEMI[k_off][2];
				if (vcz < 0 || vcz >= Nz) continue;
				int64_t vc = vcx + vcy * Nx + vcz * NxNy;
				int32_t vs = offsets[(size_t)vc];
				int32_t ve = offsets[(size_t)(vc + 1)];
				for (int32_t pj = vs; pj < ve; pj++) {
					int32_t j = sorted_idx[(size_t)pj];
					Vector3 pos_b = pos_r[j];
					double d2 = (double)pos_a.distance_squared_to(pos_b);
					double r_j = r_par_i[(size_t)j];
					double r_max = r_i > r_j ? r_i : r_j;
					double r_max_sq = r_max * r_max;
					if (d2 > r_max_sq) continue;
					_n_paires_distance++;
					_n_paires_dedup++;
					if ((masque_a & masques_c_r[j]) == 0) continue;
					if (!swept_a.intersects(col_swept[(size_t)j])) continue;
					PaireCandidat pc;
					pc.i = i;
					pc.j = j;
					batch_paires.push_back(pc);
				}
			}
		}
	}

	_us_parcours = std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - t_parcours_debut).count();

	// --- Narrowphase batch : consomme les paires retenues dans l'ordre pousse ---
	// Un seul now() debut, un seul now() fin -- jamais un now() par paire.
	auto t_np_debut = std::chrono::steady_clock::now();
	const size_t n_batch = batch_paires.size();
	for (size_t bp = 0; bp < n_batch; bp++) {
		int32_t i = batch_paires[bp].i;
		int32_t j = batch_paires[bp].j;
		Vector3 pos_a = pos_r[i];
		Vector3 pos_b = pos_r[j];
		Vector3 vel_a = vel_r[i];
		Vector3 vel_b = vel_r[j];
		Basis orient_a = col_orient[(size_t)i];
		Basis orient_b = col_orient[(size_t)j];
		double tm_a = col_taille_min[(size_t)i];
		double tm_b = col_taille_min[(size_t)j];
		double vla = col_vel_len[(size_t)i];
		double vlb = col_vel_len[(size_t)j];
		int n_sub = 1;
		if (tm_a > 0.0 && vla * (double)delta > tm_a * 0.5) {
			int nn = (int)std::ceil(vla * (double)delta / (tm_a * 0.5));
			if (nn > n_sub) n_sub = nn;
		}
		if (tm_b > 0.0 && vlb * (double)delta > tm_b * 0.5) {
			int nn = (int)std::ceil(vlb * (double)delta / (tm_b * 0.5));
			if (nn > n_sub) n_sub = nn;
		}
		int fd_a = formes_debut_r[i];
		int ff_a = formes_debut_r[i + 1];
		int fd_b = formes_debut_r[j];
		int ff_b = formes_debut_r[j + 1];
		bool trouve = false;
		Vector3 n_hit(0, 0, 0);
		double prof_hit = 0.0;
		for (int k = 0; k <= n_sub && !trouve; k++) {
			double frac = (double)k / (double)n_sub;
			Vector3 pe = pos_a - vel_a * (real_t)(delta * frac);
			Vector3 po = pos_b - vel_b * (real_t)(delta * frac);
			for (int fa_idx = fd_a; fa_idx < ff_a && !trouve; fa_idx++) {
				Transform3D tf_la = lire_transform(formes_tf_r + fa_idx * 12);
				int type_a = formes_type_r[fa_idx];
				const float *params_a = formes_params_r + fa_idx * 4;
				Transform3D ta = tf_monde_forme(orient_a, pe, tf_la);
				for (int fb_idx = fd_b; fb_idx < ff_b && !trouve; fb_idx++) {
					Transform3D tf_lb = lire_transform(formes_tf_r + fb_idx * 12);
					int type_b = formes_type_r[fb_idx];
					const float *params_b = formes_params_r + fb_idx * 4;
					Transform3D tb = tf_monde_forme(orient_b, po, tf_lb);
					Vector3 n_pair(0, 0, 0);
					double prof_pair = 0.0;
					_n_appels_nf++;
					// Dispatch dupplique (test identique a celui interne
					// a contact_forme_paire) pour compter le chemin pris SANS
					// modifier la signature ni ajouter now()/alloc. La
					// condition suit exactement le raccourci interne.
					if (type_a == FORME_BOITE && type_b == FORME_BOITE
							&& basis_est_identity(ta.basis) && basis_est_identity(tb.basis)) {
						_n_appels_raccourci++;
					} else {
						_n_appels_gjk++;
					}
					if (contact_forme_paire(type_a, params_a, ta,
							type_b, params_b, tb, hull_points_ptr,
							n_pair, prof_pair)) {
						trouve = true;
						n_hit = n_pair;
						prof_hit = prof_pair;
					}
				}
			}
		}
		if (trouve) {
			contacts_a.push_back(i);
			contacts_b.push_back(j);
			contacts_normale.push_back(n_hit);
			contacts_profondeur.push_back((float)prof_hit);
		}
	}

	// --- TRI STABLE des contacts par (min(a,b), max(a,b)) ---
	// Rend `resoudre` deterministe par construction : l'ordre de composition
	// des separations ne depend plus de l'ordre de parcours des cellules.
	// std::stable_sort obligatoire : deux contacts de meme clef (paire multi-formes)
	// gardent leur ordre d'insertion, identique GDScript et C++ tant que le
	// narrowphase itere les formes (fa puis fb) dans le meme ordre -- c'est le cas.
	// PERMUTATION SUR LES 4 COLONNES : trier chaque colonne separement casserait
	// l'alignement. On trie un vector d'indices, puis on reconstruit les quatre
	// Packed*Array. Inclus dans us_narrowphase (borne fermee juste apres).
	const int K = (int)contacts_a.size();
	if (K > 1) {
		std::vector<int> perm((size_t)K);
		for (int k = 0; k < K; k++) perm[(size_t)k] = k;
		const int32_t *ca_ptr = contacts_a.data();
		const int32_t *cb_ptr = contacts_b.data();
		std::stable_sort(perm.begin(), perm.end(), [&](int x, int y) {
			int32_t ax = ca_ptr[x], bx = cb_ptr[x];
			int32_t ay = ca_ptr[y], by = cb_ptr[y];
			int32_t lo_x = ax < bx ? ax : bx;
			int32_t hi_x = ax < bx ? bx : ax;
			int32_t lo_y = ay < by ? ay : by;
			int32_t hi_y = ay < by ? by : ay;
			if (lo_x != lo_y) return lo_x < lo_y;
			return hi_x < hi_y;
		});
		std::vector<int32_t> new_a((size_t)K);
		std::vector<int32_t> new_b((size_t)K);
		std::vector<Vector3> new_n((size_t)K);
		std::vector<float> new_p((size_t)K);
		const Vector3 *cn_ptr = contacts_normale.data();
		const float *cp_ptr = contacts_profondeur.data();
		for (int k = 0; k < K; k++) {
			int src = perm[(size_t)k];
			new_a[(size_t)k] = ca_ptr[src];
			new_b[(size_t)k] = cb_ptr[src];
			new_n[(size_t)k] = cn_ptr[src];
			new_p[(size_t)k] = cp_ptr[src];
		}
		contacts_a = std::move(new_a);
		contacts_b = std::move(new_b);
		contacts_normale = std::move(new_n);
		contacts_profondeur = std::move(new_p);
	}

	_us_narrowphase = std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - t_np_debut).count();
	_n_contacts = (int64_t)contacts_a.size();

	(void)reponses_r;
	(void)masques_r_r;
}

// =============================================================================
// DETECTER (wrapper Dictionary -> Dictionary)
// =============================================================================
Dictionary CollisionLot::detecter(const Dictionary &entree) const {
	std::vector<int32_t> ca;
	std::vector<int32_t> cb;
	std::vector<Vector3> cn;
	std::vector<float> cp;
	// FORCE le mode Dictionary : detecter individuel ignore les membres stockes
	// (le test de parite n'appelle jamais init_soa_stable).
	_detecter_impl(entree, false, ca, cb, cn, cp);

	const int K = (int)ca.size();
	PackedInt32Array contacts_a; contacts_a.resize(K);
	PackedInt32Array contacts_b; contacts_b.resize(K);
	PackedVector3Array contacts_normale; contacts_normale.resize(K);
	PackedFloat32Array contacts_profondeur; contacts_profondeur.resize(K);
	if (K > 0) {
		std::memcpy(contacts_a.ptrw(), ca.data(), sizeof(int32_t) * (size_t)K);
		std::memcpy(contacts_b.ptrw(), cb.data(), sizeof(int32_t) * (size_t)K);
		std::memcpy(contacts_normale.ptrw(), cn.data(), sizeof(Vector3) * (size_t)K);
		std::memcpy(contacts_profondeur.ptrw(), cp.data(), sizeof(float) * (size_t)K);
	}

	Dictionary sortie;
	sortie["contacts_a"] = contacts_a;
	sortie["contacts_b"] = contacts_b;
	sortie["contacts_normale"] = contacts_normale;
	sortie["contacts_profondeur"] = contacts_profondeur;
	return sortie;
}

// =============================================================================
// RESOUDRE (implementation interne, pointeurs bruts)
// =============================================================================
// Mute pos_w en place. Chrono us_resoudre ecrit ici. Les pointeurs bruts
// laissent l'appelant passer soit .ptr() (PackedArray depuis Dictionary), soit
// .data() (std::vector produit par _detecter_impl).
void CollisionLot::_resoudre_impl(
		Vector3 *pos_w,
		const Vector3 *vel_r,
		const uint8_t *reponses_r,
		const int32_t *masques_r_r,
		const int32_t *ca_r,
		const int32_t *cb_r,
		const Vector3 *cn_r,
		const float *cp_r,
		int K) const {
	_us_resoudre = 0;
	auto t_debut = std::chrono::steady_clock::now();

	for (int k = 0; k < K; k++) {
		double prof = (double)cp_r[k];
		Vector3 normale = cn_r[k];
		if (prof <= COL_EPS || (double)normale.length_squared() < COL_EPS) {
			continue;
		}
		int32_t ia = ca_r[k];
		int32_t ib = cb_r[k];
		if (reponses_r[ia] != 1 || reponses_r[ib] != 1) continue;
		if ((masques_r_r[ia] & masques_r_r[ib]) == 0) continue;
		bool a_mobile = (double)vel_r[ia].length_squared() > 0.0;
		bool b_mobile = (double)vel_r[ib].length_squared() > 0.0;
		double part_a = 0.5;
		double part_b = 0.5;
		if (a_mobile && !b_mobile) {
			part_a = 1.0;
			part_b = 0.0;
		} else if (b_mobile && !a_mobile) {
			part_a = 0.0;
			part_b = 1.0;
		}
		pos_w[ia] -= normale * (real_t)(prof * part_a);
		pos_w[ib] += normale * (real_t)(prof * part_b);
	}

	_us_resoudre += std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now() - t_debut).count();
}

// =============================================================================
// RESOUDRE (wrapper Dictionary -> Dictionary)
// =============================================================================
Dictionary CollisionLot::resoudre(const Dictionary &entree) const {
	Dictionary sortie;

	PackedVector3Array positions = entree["positions"];
	PackedVector3Array velocites = entree["velocites"];
	PackedByteArray reponses = entree["reponses"];
	PackedInt32Array masques_r = entree["masques_r"];
	PackedInt32Array contacts_a = entree["contacts_a"];
	PackedInt32Array contacts_b = entree["contacts_b"];
	PackedVector3Array contacts_normale = entree["contacts_normale"];
	PackedFloat32Array contacts_profondeur = entree["contacts_profondeur"];

	_resoudre_impl(
			positions.ptrw(),
			velocites.ptr(),
			reponses.ptr(),
			masques_r.ptr(),
			contacts_a.ptr(),
			contacts_b.ptr(),
			contacts_normale.ptr(),
			contacts_profondeur.ptr(),
			contacts_a.size());

	sortie["positions"] = positions;
	return sortie;
}

// =============================================================================
// DETECTER_ET_RESOUDRE (une seule frontiere aller-retour)
// =============================================================================
// Enchaine _detecter_impl puis _resoudre_impl : les contacts restent en
// std::vector cote C++, ne sortent jamais. 4 traversees GDScript/C++ par frame
// (detecter dict-in dict-out + resoudre dict-in dict-out) deviennent 2.
Dictionary CollisionLot::detecter_et_resoudre(const Dictionary &entree) const {
	Dictionary sortie;

	std::vector<int32_t> ca;
	std::vector<int32_t> cb;
	std::vector<Vector3> cn;
	std::vector<float> cp;
	_detecter_impl(entree, _soa_stable_initialise, ca, cb, cn, cp);

	// positions vient TOUJOURS du Dictionary (mute par frame). Les trois
	// autres (velocites, reponses, masques_r) viennent des membres si le SoA
	// est initialise, sinon du Dictionary (fallback si l'appelant a saute
	// init_soa_stable).
	PackedVector3Array positions = entree["positions"];
	PackedVector3Array velocites_l;
	PackedByteArray reponses_l;
	PackedInt32Array masques_r_l;
	const Vector3 *vel_r;
	const uint8_t *reponses_r;
	const int32_t *masques_r_r;
	if (_soa_stable_initialise) {
		vel_r = _velocites.ptr();
		reponses_r = _reponses.ptr();
		masques_r_r = _masques_r.ptr();
	} else {
		velocites_l = entree["velocites"];
		reponses_l = entree["reponses"];
		masques_r_l = entree["masques_r"];
		vel_r = velocites_l.ptr();
		reponses_r = reponses_l.ptr();
		masques_r_r = masques_r_l.ptr();
	}

	_resoudre_impl(
			positions.ptrw(),
			vel_r,
			reponses_r,
			masques_r_r,
			ca.data(),
			cb.data(),
			cn.data(),
			cp.data(),
			(int)ca.size());

	sortie["positions"] = positions;
	return sortie;
}
