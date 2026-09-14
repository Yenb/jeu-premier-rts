#include "champ_saturation_plat.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>
#include <cstdlib>

// Voir champ_saturation_plat.h. Miroir bit-a-bit de scripts/
// champ_saturation_plat.gd. Rollback : bascule oracle GDScript.

namespace godot {

static inline int _floori(float v) { return int(std::floor(double(v))); }
static inline int _absi(int v) { return v < 0 ? -v : v; }
static inline int _maxi(int a, int b) { return a > b ? a : b; }

void ChampSaturationPlat::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurer", "x_min", "z_min", "x_max", "z_max"), &ChampSaturationPlat::configurer);
	ClassDB::bind_method(D_METHOD("deposer", "centre_x", "centre_z", "rayon_m", "taille_case", "magnitude", "signe"), &ChampSaturationPlat::deposer);
	ClassDB::bind_method(D_METHOD("deposer_lot", "centres_x", "centres_z", "rayons_m", "taille_case", "magnitudes", "signes"), &ChampSaturationPlat::deposer_lot);
	ClassDB::bind_method(D_METHOD("redeposer", "centre_x", "centre_z", "ancien_rayon_m", "nouveau_rayon_m", "taille_case", "ancienne_magnitude", "nouvelle_magnitude"), &ChampSaturationPlat::redeposer);
	ClassDB::bind_method(D_METHOD("redeposer_lot", "centres_x", "centres_z", "anciens_rayons_m", "nouveaux_rayons_m", "taille_case", "anciennes_magnitudes", "nouvelles_magnitudes"), &ChampSaturationPlat::redeposer_lot);
	ClassDB::bind_method(D_METHOD("lire", "x", "z", "taille_case"), &ChampSaturationPlat::lire);
	ClassDB::bind_method(D_METHOD("lire_lot", "positions_x", "positions_z", "taille_case"), &ChampSaturationPlat::lire_lot);
	ClassDB::bind_method(D_METHOD("nombre_cases"), &ChampSaturationPlat::nombre_cases);
}

ChampSaturationPlat::ChampSaturationPlat() {}
ChampSaturationPlat::~ChampSaturationPlat() {}

void ChampSaturationPlat::configurer(int x_min, int z_min, int x_max, int z_max) {
	_x_min = x_min;
	_z_min = z_min;
	_largeur = _maxi(0, x_max - x_min + 1);
	_hauteur = _maxi(0, z_max - z_min + 1);
	_valeurs.assign(size_t(_largeur) * size_t(_hauteur), 0.0f);
	_n_non_nulles = 0;
}

void ChampSaturationPlat::deposer(float centre_x, float centre_z, float rayon_m, float taille_case, float magnitude, int signe) {
	if (taille_case <= 0.0f || _largeur == 0) return;
	float mag = magnitude * float(signe);
	if (mag == 0.0f) return;
	int rayon = 0;
	if (rayon_m > 0.0f) rayon = int(std::ceil(double(rayon_m) / double(taille_case)));
	int cx0 = _floori(centre_x / taille_case);
	int cz0 = _floori(centre_z / taille_case);
	int x_min_l = _x_min;
	int z_min_l = _z_min;
	int largeur_l = _largeur;
	int hauteur_l = _hauteur;
	int dcx = -rayon;
	while (dcx <= rayon) {
		int dcz = -rayon;
		while (dcz <= rayon) {
			int d = _maxi(_absi(dcx), _absi(dcz));
			float poids = 1.0f;
			if (rayon > 0) poids = 1.0f - float(d) / float(rayon);
			if (poids <= 0.0f) { ++dcz; continue; }
			float apport = mag * poids;
			int cx = (cx0 + dcx) - x_min_l;
			int cz = (cz0 + dcz) - z_min_l;
			if (cx >= 0 && cx < largeur_l && cz >= 0 && cz < hauteur_l) {
				int idx = cz * largeur_l + cx;
				float ancien = _valeurs[idx];
				float v = ancien + apport;
				bool etait_non_nulle = std::fabs(ancien) >= EPS_COUVERT;
				if (std::fabs(v) < EPS_COUVERT) {
					_valeurs[idx] = 0.0f;
					if (etait_non_nulle) --_n_non_nulles;
				} else {
					_valeurs[idx] = v;
					if (!etait_non_nulle) ++_n_non_nulles;
				}
			}
			++dcz;
		}
		++dcx;
	}
}

void ChampSaturationPlat::deposer_lot(
		const PackedFloat32Array &centres_x,
		const PackedFloat32Array &centres_z,
		const PackedFloat32Array &rayons_m,
		float taille_case,
		const PackedFloat32Array &magnitudes,
		const PackedByteArray &signes) {
	if (taille_case <= 0.0f || _largeur == 0) return;
	int n = centres_x.size();
	if (n == 0) return;
	int x_min_l = _x_min;
	int z_min_l = _z_min;
	int largeur_l = _largeur;
	int hauteur_l = _hauteur;
	const float *cx_r = centres_x.ptr();
	const float *cz_r = centres_z.ptr();
	const float *rm_r = rayons_m.ptr();
	const float *mag_r = magnitudes.ptr();
	const uint8_t *sg_r = signes.ptr();
	for (int k = 0; k < n; ++k) {
		float magnitude = mag_r[k];
		int signe = (sg_r[k] == 1) ? 1 : -1;
		float mag = magnitude * float(signe);
		if (mag == 0.0f) continue;
		float rayon_m = rm_r[k];
		int rayon = 0;
		if (rayon_m > 0.0f) rayon = int(std::ceil(double(rayon_m) / double(taille_case)));
		int cx0 = _floori(cx_r[k] / taille_case);
		int cz0 = _floori(cz_r[k] / taille_case);
		int dcx = -rayon;
		while (dcx <= rayon) {
			int dcz = -rayon;
			while (dcz <= rayon) {
				int d = _maxi(_absi(dcx), _absi(dcz));
				float poids = 1.0f;
				if (rayon > 0) poids = 1.0f - float(d) / float(rayon);
				if (poids <= 0.0f) { ++dcz; continue; }
				float apport = mag * poids;
				int cx = (cx0 + dcx) - x_min_l;
				int cz = (cz0 + dcz) - z_min_l;
				if (cx >= 0 && cx < largeur_l && cz >= 0 && cz < hauteur_l) {
					int idx = cz * largeur_l + cx;
					float ancien = _valeurs[idx];
					float v = ancien + apport;
					bool etait_non_nulle = std::fabs(ancien) >= EPS_COUVERT;
					if (std::fabs(v) < EPS_COUVERT) {
						_valeurs[idx] = 0.0f;
						if (etait_non_nulle) --_n_non_nulles;
					} else {
						_valeurs[idx] = v;
						if (!etait_non_nulle) ++_n_non_nulles;
					}
				}
				++dcz;
			}
			++dcx;
		}
	}
}

void ChampSaturationPlat::redeposer(
		float centre_x,
		float centre_z,
		float ancien_rayon_m,
		float nouveau_rayon_m,
		float taille_case,
		float ancienne_magnitude,
		float nouvelle_magnitude) {
	if (taille_case <= 0.0f || _largeur == 0) return;
	int rayon_ancien = 0;
	if (ancien_rayon_m > 0.0f) rayon_ancien = int(std::ceil(double(ancien_rayon_m) / double(taille_case)));
	int rayon_nouveau = 0;
	if (nouveau_rayon_m > 0.0f) rayon_nouveau = int(std::ceil(double(nouveau_rayon_m) / double(taille_case)));
	int rayon_max = _maxi(rayon_ancien, rayon_nouveau);
	if (ancienne_magnitude == 0.0f && nouvelle_magnitude == 0.0f) return;
	int cx0 = _floori(centre_x / taille_case);
	int cz0 = _floori(centre_z / taille_case);
	int x_min_l = _x_min;
	int z_min_l = _z_min;
	int largeur_l = _largeur;
	int hauteur_l = _hauteur;
	int dcx = -rayon_max;
	while (dcx <= rayon_max) {
		int dcz = -rayon_max;
		while (dcz <= rayon_max) {
			int d = _maxi(_absi(dcx), _absi(dcz));
			float apport = 0.0f;
			if (ancienne_magnitude != 0.0f && d <= rayon_ancien) {
				float poids_a = 1.0f;
				if (rayon_ancien > 0) poids_a = 1.0f - float(d) / float(rayon_ancien);
				if (poids_a > 0.0f) apport -= ancienne_magnitude * poids_a;
			}
			if (nouvelle_magnitude != 0.0f && d <= rayon_nouveau) {
				float poids_n = 1.0f;
				if (rayon_nouveau > 0) poids_n = 1.0f - float(d) / float(rayon_nouveau);
				if (poids_n > 0.0f) apport += nouvelle_magnitude * poids_n;
			}
			if (apport == 0.0f) { ++dcz; continue; }
			int cx = (cx0 + dcx) - x_min_l;
			int cz = (cz0 + dcz) - z_min_l;
			if (cx >= 0 && cx < largeur_l && cz >= 0 && cz < hauteur_l) {
				int idx = cz * largeur_l + cx;
				float ancien = _valeurs[idx];
				float v = ancien + apport;
				bool etait_non_nulle = std::fabs(ancien) >= EPS_COUVERT;
				if (std::fabs(v) < EPS_COUVERT) {
					_valeurs[idx] = 0.0f;
					if (etait_non_nulle) --_n_non_nulles;
				} else {
					_valeurs[idx] = v;
					if (!etait_non_nulle) ++_n_non_nulles;
				}
			}
			++dcz;
		}
		++dcx;
	}
}

void ChampSaturationPlat::redeposer_lot(
		const PackedFloat32Array &centres_x,
		const PackedFloat32Array &centres_z,
		const PackedFloat32Array &anciens_rayons_m,
		const PackedFloat32Array &nouveaux_rayons_m,
		float taille_case,
		const PackedFloat32Array &anciennes_magnitudes,
		const PackedFloat32Array &nouvelles_magnitudes) {
	if (taille_case <= 0.0f || _largeur == 0) return;
	int n = centres_x.size();
	if (n == 0) return;
	int x_min_l = _x_min;
	int z_min_l = _z_min;
	int largeur_l = _largeur;
	int hauteur_l = _hauteur;
	const float *cx_r = centres_x.ptr();
	const float *cz_r = centres_z.ptr();
	const float *arm_r = anciens_rayons_m.ptr();
	const float *nrm_r = nouveaux_rayons_m.ptr();
	const float *am_r = anciennes_magnitudes.ptr();
	const float *nm_r = nouvelles_magnitudes.ptr();
	for (int k = 0; k < n; ++k) {
		float ancienne_magnitude = am_r[k];
		float nouvelle_magnitude = nm_r[k];
		if (ancienne_magnitude == 0.0f && nouvelle_magnitude == 0.0f) continue;
		float ancien_rayon_m = arm_r[k];
		float nouveau_rayon_m = nrm_r[k];
		int rayon_ancien = 0;
		if (ancien_rayon_m > 0.0f) rayon_ancien = int(std::ceil(double(ancien_rayon_m) / double(taille_case)));
		int rayon_nouveau = 0;
		if (nouveau_rayon_m > 0.0f) rayon_nouveau = int(std::ceil(double(nouveau_rayon_m) / double(taille_case)));
		int rayon_max = _maxi(rayon_ancien, rayon_nouveau);
		int cx0 = _floori(cx_r[k] / taille_case);
		int cz0 = _floori(cz_r[k] / taille_case);
		int dcx = -rayon_max;
		while (dcx <= rayon_max) {
			int dcz = -rayon_max;
			while (dcz <= rayon_max) {
				int d = _maxi(_absi(dcx), _absi(dcz));
				float apport = 0.0f;
				if (ancienne_magnitude != 0.0f && d <= rayon_ancien) {
					float poids_a = 1.0f;
					if (rayon_ancien > 0) poids_a = 1.0f - float(d) / float(rayon_ancien);
					if (poids_a > 0.0f) apport -= ancienne_magnitude * poids_a;
				}
				if (nouvelle_magnitude != 0.0f && d <= rayon_nouveau) {
					float poids_n = 1.0f;
					if (rayon_nouveau > 0) poids_n = 1.0f - float(d) / float(rayon_nouveau);
					if (poids_n > 0.0f) apport += nouvelle_magnitude * poids_n;
				}
				if (apport == 0.0f) { ++dcz; continue; }
				int cx = (cx0 + dcx) - x_min_l;
				int cz = (cz0 + dcz) - z_min_l;
				if (cx >= 0 && cx < largeur_l && cz >= 0 && cz < hauteur_l) {
					int idx = cz * largeur_l + cx;
					float ancien = _valeurs[idx];
					float v = ancien + apport;
					bool etait_non_nulle = std::fabs(ancien) >= EPS_COUVERT;
					if (std::fabs(v) < EPS_COUVERT) {
						_valeurs[idx] = 0.0f;
						if (etait_non_nulle) --_n_non_nulles;
					} else {
						_valeurs[idx] = v;
						if (!etait_non_nulle) ++_n_non_nulles;
					}
				}
				++dcz;
			}
			++dcx;
		}
	}
}

float ChampSaturationPlat::lire(float x, float z, float taille_case) const {
	if (taille_case <= 0.0f || _largeur == 0) return 0.0f;
	int cx = _floori(x / taille_case) - _x_min;
	int cz = _floori(z / taille_case) - _z_min;
	if (cx < 0 || cx >= _largeur || cz < 0 || cz >= _hauteur) return 0.0f;
	return _valeurs[cz * _largeur + cx];
}

PackedFloat32Array ChampSaturationPlat::lire_lot(
		const PackedFloat32Array &positions_x,
		const PackedFloat32Array &positions_z,
		float taille_case) const {
	int n = positions_x.size();
	PackedFloat32Array out;
	out.resize(n);
	if (taille_case <= 0.0f || _largeur == 0) return out;
	float *out_w = out.ptrw();
	const float *px_r = positions_x.ptr();
	const float *pz_r = positions_z.ptr();
	for (int k = 0; k < n; ++k) {
		int cx = _floori(px_r[k] / taille_case) - _x_min;
		int cz = _floori(pz_r[k] / taille_case) - _z_min;
		if (cx >= 0 && cx < _largeur && cz >= 0 && cz < _hauteur) {
			out_w[k] = _valeurs[cz * _largeur + cx];
		}
	}
	return out;
}

int ChampSaturationPlat::nombre_cases() const {
	return _n_non_nulles;
}

} // namespace godot
