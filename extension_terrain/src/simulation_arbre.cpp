#include "simulation_arbre.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <algorithm>
#include <cmath>
#include <unordered_set>

// Voir simulation_arbre.h pour le contrat complet (etapes 1, 2, 2b, 3).
// ROLLBACK si divergence : bascule utilise_cpp = false cote GDScript,
// oracle GDScript reprend.

namespace godot {

void SimulationArbre::_bind_methods() {
	ClassDB::bind_method(D_METHOD("charge"), &SimulationArbre::charge);
	ClassDB::bind_method(D_METHOD("population"), &SimulationArbre::population);
	ClassDB::bind_method(
			D_METHOD("initialiser_stable",
					"annees_par_seconde",
					"duree_croissance_totale",
					"duree_mort",
					"stade_gros_min",
					"stade_gros_max",
					"seuils_ages_stade",
					"ombrage_rayon_m",
					"ombrage_magnitude"),
			&SimulationArbre::initialiser_stable);
	ClassDB::bind_method(
			D_METHOD("initialiser_stable_rendu",
					"durees_stades",
					"tronc_hauteur",
					"tronc_largeur",
					"feuillage_hauteur",
					"feuillage_largeur",
					"couleur_tronc",
					"couleur_feuillage",
					"couleur_repli_tronc",
					"couleur_repli_feuillage",
					"y_sol_defaut"),
			&SimulationArbre::initialiser_stable_rendu);
	ClassDB::bind_method(
			D_METHOD("avancer_passe_1",
					"pas",
					"capacite",
					"libres",
					"ages",
					"slot_stade",
					"facteur_croissance",
					"facteur_longevite",
					"positions_x",
					"positions_z"),
			&SimulationArbre::avancer_passe_1);
	ClassDB::bind_method(
			D_METHOD("construire_buffers_rendu",
					"capacite",
					"libres",
					"ages",
					"slot_stade",
					"positions_x",
					"positions_y",
					"positions_z"),
			&SimulationArbre::construire_buffers_rendu);
	ClassDB::bind_method(
			D_METHOD("appliquer_reset_morts",
					"morts",
					"libres",
					"slot_stade",
					"ages"),
			&SimulationArbre::appliquer_reset_morts);
	ClassDB::bind_method(D_METHOD("poser_seed_rng", "seed"), &SimulationArbre::poser_seed_rng);
	ClassDB::bind_method(D_METHOD("tirer_randf_lot", "n"), &SimulationArbre::tirer_randf_lot);
	ClassDB::bind_method(
			D_METHOD("initialiser_stable_reproduction",
					"debut_fertilite",
					"fin_fertilite",
					"rayon_graine"),
			&SimulationArbre::initialiser_stable_reproduction);
	ClassDB::bind_method(
			D_METHOD("passe_reproduction",
					"pas",
					"capacite",
					"libres",
					"ages",
					"intervalle_reprod",
					"positions_x",
					"positions_z",
					"morts_vieillesse"),
			&SimulationArbre::passe_reproduction);
	ClassDB::bind_method(D_METHOD("obtenir_rng"), &SimulationArbre::obtenir_rng);
	ClassDB::bind_method(
			D_METHOD("selection_competition",
					"pas",
					"capacite",
					"cadence_competition",
					"stade_competition_max",
					"curseur_competition",
					"libres",
					"slot_stade",
					"positions_x",
					"positions_z",
					"y_sol"),
			&SimulationArbre::selection_competition);
	ClassDB::bind_method(
			D_METHOD("decider_morts_competition",
					"slots_batch",
					"voisins_offsets",
					"voisins_slots",
					"competition_max_voisins"),
			&SimulationArbre::decider_morts_competition);
	ClassDB::bind_method(D_METHOD("arbre_ouvrir_niveau", "exposant"), &SimulationArbre::arbre_ouvrir_niveau);
	ClassDB::bind_method(
			D_METHOD("arbre_ajouter_lot",
					"slots",
					"positions_x",
					"positions_z",
					"y_sol"),
			&SimulationArbre::arbre_ajouter_lot);
	ClassDB::bind_method(D_METHOD("arbre_retirer_lot", "slots"), &SimulationArbre::arbre_retirer_lot);
	ClassDB::bind_method(
			D_METHOD("arbre_choses_dans_rayons_brut_xz",
					"positions_x",
					"positions_z",
					"y_sol",
					"rayon"),
			&SimulationArbre::arbre_choses_dans_rayons_brut_xz);
}

SimulationArbre::SimulationArbre() {
	_rng.instantiate();
}
SimulationArbre::~SimulationArbre() {}

void SimulationArbre::poser_seed_rng(uint64_t seed) {
	if (_rng.is_null()) {
		_rng.instantiate();
	}
	_rng->set_seed(seed);
}

PackedFloat32Array SimulationArbre::tirer_randf_lot(int n) {
	PackedFloat32Array out;
	if (_rng.is_null() || n <= 0) return out;
	out.resize(n);
	float *w = out.ptrw();
	for (int i = 0; i < n; ++i) {
		w[i] = _rng->randf();
	}
	return out;
}

bool SimulationArbre::charge() const { return true; }
int SimulationArbre::population() const { return _population; }

void SimulationArbre::initialiser_stable(
		float annees_par_seconde,
		float duree_croissance_totale,
		float duree_mort,
		int stade_gros_min,
		int stade_gros_max,
		const PackedFloat32Array &seuils_ages_stade,
		const PackedFloat32Array &ombrage_rayon_m,
		const PackedFloat32Array &ombrage_magnitude) {
	_annees_par_seconde = annees_par_seconde;
	_duree_croissance_totale = duree_croissance_totale;
	_duree_mort = duree_mort;
	_stade_gros_min = stade_gros_min;
	_stade_gros_max = stade_gros_max;
	_seuils_ages_stade.assign(seuils_ages_stade.ptr(), seuils_ages_stade.ptr() + seuils_ages_stade.size());
	_ombrage_rayon_m.assign(ombrage_rayon_m.ptr(), ombrage_rayon_m.ptr() + ombrage_rayon_m.size());
	_ombrage_magnitude.assign(ombrage_magnitude.ptr(), ombrage_magnitude.ptr() + ombrage_magnitude.size());
	_stable_initialise = true;
}

void SimulationArbre::initialiser_stable_rendu(
		const PackedFloat32Array &durees_stades,
		const PackedFloat32Array &tronc_hauteur,
		const PackedFloat32Array &tronc_largeur,
		const PackedFloat32Array &feuillage_hauteur,
		const PackedFloat32Array &feuillage_largeur,
		const PackedColorArray &couleur_tronc,
		const PackedColorArray &couleur_feuillage,
		const Color &couleur_repli_tronc,
		const Color &couleur_repli_feuillage,
		float y_sol_defaut) {
	_durees_stades.assign(durees_stades.ptr(), durees_stades.ptr() + durees_stades.size());
	_tronc_hauteur.assign(tronc_hauteur.ptr(), tronc_hauteur.ptr() + tronc_hauteur.size());
	_tronc_largeur.assign(tronc_largeur.ptr(), tronc_largeur.ptr() + tronc_largeur.size());
	_feuillage_hauteur.assign(feuillage_hauteur.ptr(), feuillage_hauteur.ptr() + feuillage_hauteur.size());
	_feuillage_largeur.assign(feuillage_largeur.ptr(), feuillage_largeur.ptr() + feuillage_largeur.size());
	_couleur_tronc.resize(couleur_tronc.size());
	for (int i = 0; i < couleur_tronc.size(); ++i) _couleur_tronc[i] = couleur_tronc[i];
	_couleur_feuillage.resize(couleur_feuillage.size());
	for (int i = 0; i < couleur_feuillage.size(); ++i) _couleur_feuillage[i] = couleur_feuillage[i];
	_couleur_repli_tronc = couleur_repli_tronc;
	_couleur_repli_feuillage = couleur_repli_feuillage;
	_y_sol_defaut = y_sol_defaut;
	_stable_rendu_initialise = true;
}

Dictionary SimulationArbre::avancer_passe_1(
		float pas,
		int capacite,
		const PackedByteArray &libres,
		const PackedFloat32Array &ages,
		const PackedInt32Array &slot_stade,
		const PackedFloat32Array &facteur_croissance,
		const PackedFloat32Array &facteur_longevite,
		const PackedFloat32Array &positions_x,
		const PackedFloat32Array &positions_z) const {
	PackedFloat32Array ages_out = ages;
	PackedInt32Array slot_stade_out = slot_stade;

	int cap = capacite;
	float *ages_w = ages_out.ptrw();
	int32_t *slot_stade_w = slot_stade_out.ptrw();
	const uint8_t *libres_r = libres.ptr();
	const float *fc_r = facteur_croissance.ptr();
	const float *fl_r = facteur_longevite.ptr();
	const float *px_r = positions_x.ptr();
	const float *pz_r = positions_z.ptr();

	int n_stades = int(_seuils_ages_stade.size());
	int n_ombrage = int(_ombrage_rayon_m.size());
	const float *seuils_r = _seuils_ages_stade.data();
	const float *omb_r_r = _ombrage_rayon_m.data();
	const float *omb_m_r = _ombrage_magnitude.data();

	PackedInt32Array morts;
	PackedFloat32Array tx, tz, tra, trn, tma, tmn;
	PackedFloat32Array rx, rz;
	PackedFloat32Array sx, sz;
	PackedInt32Array ss, sg;

	for (int i = 0; i < cap; ++i) {
		if (libres_r[i] == 1) continue;
		ages_w[i] = ages_w[i] + pas * (_annees_par_seconde * fc_r[i]);
		float age_i = ages_w[i];
		int ancien = slot_stade_w[i];
		if (n_stades > 0) {
			int index_trouve = -1;
			for (int k = 0; k < n_stades; ++k) {
				if (age_i >= seuils_r[k]) index_trouve = k;
			}
			if (index_trouve > ancien) slot_stade_w[i] = index_trouve;
		}
		float seuil_mort = (_duree_croissance_totale + _duree_mort) * fl_r[i];
		if (age_i >= seuil_mort) {
			slot_stade_w[i] = ancien;
			morts.append(i);
			continue;
		}
		int nouveau_index = slot_stade_w[i];
		if (nouveau_index != ancien) {
			if (ancien >= 0 && nouveau_index >= 0) {
				int stade_a = ancien + 1;
				int stade_n = nouveau_index + 1;
				if (stade_a >= 1 && stade_a <= n_ombrage && stade_n >= 1 && stade_n <= n_ombrage) {
					tx.append(px_r[i]);
					tz.append(pz_r[i]);
					tra.append(omb_r_r[stade_a - 1]);
					trn.append(omb_r_r[stade_n - 1]);
					tma.append(omb_m_r[stade_a - 1]);
					tmn.append(omb_m_r[stade_n - 1]);
				}
			} else if (ancien >= 0) {
				sx.append(px_r[i]);
				sz.append(pz_r[i]);
				ss.append(ancien + 1);
				sg.append(-1);
			} else if (nouveau_index >= 0) {
				sx.append(px_r[i]);
				sz.append(pz_r[i]);
				ss.append(nouveau_index + 1);
				sg.append(1);
			}
			bool degageant = false;
			if (ancien >= 0 && nouveau_index >= 0) {
				bool ancien_adulte = (ancien + 1) >= _stade_gros_min && (ancien + 1) <= _stade_gros_max;
				bool nouveau_adulte = (nouveau_index + 1) >= _stade_gros_min && (nouveau_index + 1) <= _stade_gros_max;
				if (ancien_adulte && !nouveau_adulte) {
					degageant = true;
				} else if (n_ombrage > ancien && n_ombrage > nouveau_index) {
					float mag_a = omb_m_r[ancien];
					float mag_n = omb_m_r[nouveau_index];
					float ray_a = omb_r_r[ancien];
					float ray_n = omb_r_r[nouveau_index];
					if (mag_n < mag_a) degageant = true;
					else if (ray_n < ray_a) degageant = true;
				}
			}
			if (degageant) {
				rx.append(px_r[i]);
				rz.append(pz_r[i]);
			}
		}
	}

	Dictionary out;
	out["ages"] = ages_out;
	out["slot_stade"] = slot_stade_out;
	out["morts_vieillesse"] = morts;
	out["transitions_x"] = tx;
	out["transitions_z"] = tz;
	out["transitions_rayon_a"] = tra;
	out["transitions_rayon_n"] = trn;
	out["transitions_mag_a"] = tma;
	out["transitions_mag_n"] = tmn;
	out["reveils_x"] = rx;
	out["reveils_z"] = rz;
	out["simple_x"] = sx;
	out["simple_z"] = sz;
	out["simple_stade"] = ss;
	out["simple_signe"] = sg;
	return out;
}

Dictionary SimulationArbre::construire_buffers_rendu(
		int capacite,
		const PackedByteArray &libres,
		const PackedFloat32Array &ages,
		const PackedInt32Array &slot_stade,
		const PackedFloat32Array &positions_x,
		const PackedFloat32Array &positions_y,
		const PackedFloat32Array &positions_z) const {
	int cap = capacite;
	PackedFloat32Array buf_t;
	PackedFloat32Array buf_f;
	buf_t.resize(cap * 16);
	buf_f.resize(cap * 16);
	float *bt = buf_t.ptrw();
	float *bf = buf_f.ptrw();

	const uint8_t *libres_r = libres.ptr();
	const float *ages_r = ages.ptr();
	const int32_t *stade_r = slot_stade.ptr();
	const float *px_r = positions_x.ptr();
	const float *py_r = positions_y.ptr();
	const float *pz_r = positions_z.ptr();

	int n_durees = int(_durees_stades.size());
	int n_stades_full = int(_tronc_hauteur.size());
	int n_col_t = int(_couleur_tronc.size());
	int n_col_f = int(_couleur_feuillage.size());
	const float *tr_h = _tronc_hauteur.data();
	const float *tr_l = _tronc_largeur.data();
	const float *fe_h = _feuillage_hauteur.data();
	const float *fe_l = _feuillage_largeur.data();
	const float *dur = _durees_stades.data();
	float y_sol_def = _y_sol_defaut;

	for (int i = 0; i < cap; ++i) {
		int base = i * 16;
		if (libres_r[i] == 1) {
			// Slot vide : Basis IDENTITY scaled Vector3.ZERO + origin (0, Y_SOL, 0).
			// Miroir de _ecrire_slot_vide GDScript.
			bt[base + 0] = 0.0f; bt[base + 1] = 0.0f; bt[base + 2] = 0.0f; bt[base + 3] = 0.0f;
			bt[base + 4] = 0.0f; bt[base + 5] = 0.0f; bt[base + 6] = 0.0f; bt[base + 7] = y_sol_def;
			bt[base + 8] = 0.0f; bt[base + 9] = 0.0f; bt[base + 10] = 0.0f; bt[base + 11] = 0.0f;
			bt[base + 12] = 0.0f; bt[base + 13] = 0.0f; bt[base + 14] = 0.0f; bt[base + 15] = 1.0f;
			bf[base + 0] = 0.0f; bf[base + 1] = 0.0f; bf[base + 2] = 0.0f; bf[base + 3] = 0.0f;
			bf[base + 4] = 0.0f; bf[base + 5] = 0.0f; bf[base + 6] = 0.0f; bf[base + 7] = y_sol_def;
			bf[base + 8] = 0.0f; bf[base + 9] = 0.0f; bf[base + 10] = 0.0f; bf[base + 11] = 0.0f;
			bf[base + 12] = 0.0f; bf[base + 13] = 0.0f; bf[base + 14] = 0.0f; bf[base + 15] = 1.0f;
			continue;
		}

		float age = ages_r[i];
		// ht/lt/hf/lf en DOUBLE : le calcul Y (pos + ht + hf * 0.5) est
		// en double cote GDScript (float GDScript = double), cast float32
		// seulement au write buffer. Sans, divergence de 1 ULP sur origin.y.
		double ht = 0.0, lt = 0.0, hf = 0.0, lf = 0.0;
		// duree_cumulee et duree_segment en DOUBLE : GDScript accumule
		// _duree_cumulee_esl += _duree_segment_esl en double (float GDScript
		// = double). Sans ce cast, divergence de 1 ULP apres 4-5 stages.
		double duree_cumulee = 0.0;
		bool trouve = false;
		for (int j = 0; j < n_durees; ++j) {
			double duree_segment = double(dur[j]);
			if (double(age) <= duree_cumulee + duree_segment) {
				float t = 0.0f;
				if (duree_segment > 0.0f) t = (age - duree_cumulee) / duree_segment;
				if (t < 0.0f) t = 0.0f;
				else if (t > 1.0f) t = 1.0f;
				// Formule lerp GDScript : a + t * (b - a). Calcul en DOUBLE
				// pour matcher le GDScript (float GDScript = double). Le
				// cast en float32 se fait au write final dans le buffer.
				double d_t = 0.0;
				if (duree_segment > 0.0) d_t = (double(age) - duree_cumulee) / duree_segment;
				if (d_t < 0.0) d_t = 0.0;
				else if (d_t > 1.0) d_t = 1.0;
				double d_ath = double(tr_h[j]);
				double d_bth = double(tr_h[j + 1]);
				double d_atl = double(tr_l[j]);
				double d_btl = double(tr_l[j + 1]);
				double d_afh = double(fe_h[j]);
				double d_bfh = double(fe_h[j + 1]);
				double d_afl = double(fe_l[j]);
				double d_bfl = double(fe_l[j + 1]);
				ht = d_ath + d_t * (d_bth - d_ath);
				lt = d_atl + d_t * (d_btl - d_atl);
				hf = d_afh + d_t * (d_bfh - d_afh);
				lf = d_afl + d_t * (d_bfl - d_afl);
				trouve = true;
				break;
			}
			duree_cumulee = duree_cumulee + duree_segment;
		}
		if (!trouve) {
			int idx = n_stades_full - 1;
			ht = double(tr_h[idx]);
			lt = double(tr_l[idx]);
			hf = double(fe_h[idx]);
			lf = double(fe_l[idx]);
		}

		int stade_actuel = stade_r[i];
		Color ct = _couleur_repli_tronc;
		Color cf = _couleur_repli_feuillage;
		if (stade_actuel >= 0 && stade_actuel < n_col_t) ct = _couleur_tronc[stade_actuel];
		if (stade_actuel >= 0 && stade_actuel < n_col_f) cf = _couleur_feuillage[stade_actuel];

		float pos_x = px_r[i];
		double pos_y_sol = double(py_r[i]);
		float pos_z = pz_r[i];

		// TRONC : Basis IDENTITY.scaled(Vector3(lt, ht, lt))
		//         + origin (pos_x, pos_y_sol + ht*0.5, pos_z).
		// Scale ecrite en float32 direct (ht/lt en double, GDScript passe
		// par Basis.scaled(Vector3(lt,ht,lt)) qui cast Vector3->float32).
		// Y en double : calcul + cast final au write buffer.
		bt[base + 0] = float(lt); bt[base + 1] = 0.0f;  bt[base + 2] = 0.0f;  bt[base + 3] = pos_x;
		bt[base + 4] = 0.0f;      bt[base + 5] = float(ht); bt[base + 6] = 0.0f;  bt[base + 7] = float(pos_y_sol + ht * 0.5);
		bt[base + 8] = 0.0f;      bt[base + 9] = 0.0f;  bt[base + 10] = float(lt); bt[base + 11] = pos_z;
		bt[base + 12] = ct.r; bt[base + 13] = ct.g; bt[base + 14] = ct.b; bt[base + 15] = ct.a;

		// FEUILLAGE : cas nul (Vector3.ZERO) ou plein.
		if (hf <= 0.0 || lf <= 0.0) {
			bf[base + 0] = 0.0f;  bf[base + 1] = 0.0f;  bf[base + 2] = 0.0f;  bf[base + 3] = pos_x;
			bf[base + 4] = 0.0f;  bf[base + 5] = 0.0f;  bf[base + 6] = 0.0f;  bf[base + 7] = float(pos_y_sol + ht);
			bf[base + 8] = 0.0f;  bf[base + 9] = 0.0f;  bf[base + 10] = 0.0f; bf[base + 11] = pos_z;
		} else {
			bf[base + 0] = float(lf); bf[base + 1] = 0.0f;  bf[base + 2] = 0.0f;  bf[base + 3] = pos_x;
			bf[base + 4] = 0.0f;      bf[base + 5] = float(hf); bf[base + 6] = 0.0f;  bf[base + 7] = float(pos_y_sol + ht + hf * 0.5);
			bf[base + 8] = 0.0f;      bf[base + 9] = 0.0f;  bf[base + 10] = float(lf); bf[base + 11] = pos_z;
		}
		bf[base + 12] = cf.r; bf[base + 13] = cf.g; bf[base + 14] = cf.b; bf[base + 15] = cf.a;
	}

	Dictionary out;
	out["buffer_tronc"] = buf_t;
	out["buffer_feuillage"] = buf_f;
	return out;
}

Dictionary SimulationArbre::appliquer_reset_morts(
		const PackedInt32Array &morts,
		const PackedByteArray &libres,
		const PackedInt32Array &slot_stade,
		const PackedFloat32Array &ages) const {
	// Duplication Copy-on-Write des colonnes mutees.
	PackedByteArray libres_out = libres;
	PackedInt32Array slot_stade_out = slot_stade;
	PackedFloat32Array ages_out = ages;
	uint8_t *libres_w = libres_out.ptrw();
	int32_t *slot_stade_w = slot_stade_out.ptrw();
	float *ages_w = ages_out.ptrw();
	const int32_t *morts_r = morts.ptr();
	int n = morts.size();
	int cap = libres.size();
	for (int k = 0; k < n; ++k) {
		int i = morts_r[k];
		if (i < 0 || i >= cap) continue;
		slot_stade_w[i] = -1;
		libres_w[i] = 1;
		ages_w[i] = 0.0f;
	}
	Dictionary out;
	out["libres"] = libres_out;
	out["slot_stade"] = slot_stade_out;
	out["ages"] = ages_out;
	return out;
}

void SimulationArbre::initialiser_stable_reproduction(
		float debut_fertilite,
		float fin_fertilite,
		float rayon_graine) {
	_debut_fertilite = debut_fertilite;
	_fin_fertilite = fin_fertilite;
	_rayon_graine = rayon_graine;
}

Dictionary SimulationArbre::passe_reproduction(
		float pas,
		int capacite,
		const PackedByteArray &libres,
		const PackedFloat32Array &ages,
		const PackedFloat32Array &intervalle_reprod,
		const PackedFloat32Array &positions_x,
		const PackedFloat32Array &positions_z,
		const PackedInt32Array &morts_vieillesse) {
	PackedFloat32Array gx, gz;
	Dictionary out;
	if (_rng.is_null()) {
		out["graines_x"] = gx;
		out["graines_z"] = gz;
		return out;
	}
	int cap = capacite;

	// morts_set : PackedByteArray temporaire, pareil que GDScript. Skip
	// slots fraichement morts dans la passe 1 -- meme filtre.
	std::vector<uint8_t> morts_set(cap, 0);
	const int32_t *morts_r = morts_vieillesse.ptr();
	int n_morts = morts_vieillesse.size();
	for (int k = 0; k < n_morts; ++k) {
		int mi = morts_r[k];
		if (mi >= 0 && mi < cap) morts_set[mi] = 1;
	}

	const uint8_t *libres_r = libres.ptr();
	const float *ages_r = ages.ptr();
	const float *ir_r = intervalle_reprod.ptr();
	const float *px_r = positions_x.ptr();
	const float *pz_r = positions_z.ptr();
	double d_pas = double(pas);
	double d_debut = double(_debut_fertilite);
	double d_fin = double(_fin_fertilite);
	double d_rayon_graine = double(_rayon_graine);

	// BOUCLE STRICTE 0..cap-1 -- ordre des tirages randf() preserve.
	// Miroir de _passe_reproduction (simulation_arbre.gd l.2117-2130).
	// Tous les calculs float en DOUBLE (GDScript float = double), cast
	// float32 UNIQUEMENT au append PackedFloat32Array final.
	for (int i = 0; i < cap; ++i) {
		if (libres_r[i] == 1 || morts_set[i] == 1) continue;
		double age_i = double(ages_r[i]);
		if (age_i < d_debut || age_i >= d_fin) continue;
		double intervalle_i = double(ir_r[i]);
		if (intervalle_i <= 0.0 || std::isinf(intervalle_i)) continue;
		double randf1 = double(_rng->randf());
		if (randf1 < d_pas / intervalle_i) {
			double angle = double(_rng->randf()) * Math_TAU;
			double rayon = std::sqrt(double(_rng->randf())) * d_rayon_graine;
			gx.append(float(double(px_r[i]) + std::cos(angle) * rayon));
			gz.append(float(double(pz_r[i]) + std::sin(angle) * rayon));
		}
	}
	out["graines_x"] = gx;
	out["graines_z"] = gz;
	return out;
}

Ref<RandomNumberGenerator> SimulationArbre::obtenir_rng() const {
	return _rng;
}

Dictionary SimulationArbre::selection_competition(
		float pas,
		int capacite,
		float cadence_competition,
		int stade_competition_max,
		int curseur_competition,
		const PackedByteArray &libres,
		const PackedInt32Array &slot_stade,
		const PackedFloat32Array &positions_x,
		const PackedFloat32Array &positions_z,
		float y_sol) const {
	PackedVector3Array positions_batch;
	PackedInt32Array slots_batch;
	Dictionary out;
	int cap = capacite;
	int curseur = curseur_competition;
	if (cap <= 0 || cadence_competition <= 0.0f) {
		out["positions_batch"] = positions_batch;
		out["slots_batch"] = slots_batch;
		out["curseur_avance"] = curseur;
		return out;
	}
	// Miroir ligne 1505-1509 du .gd : ceil en DOUBLE (GDScript float=double).
	int n_slots = int(std::ceil(double(cap) * double(pas) / double(cadence_competition)));
	if (n_slots < 1) n_slots = 1;
	if (n_slots > cap) n_slots = cap;
	const uint8_t *libres_r = libres.ptr();
	const int32_t *stade_r = slot_stade.ptr();
	const float *px_r = positions_x.ptr();
	const float *pz_r = positions_z.ptr();
	int count = 0;
	while (count < n_slots) {
		int i = curseur;
		curseur = (curseur + 1) % cap;
		++count;
		if (libres_r[i] == 1) continue;
		int index_stade = stade_r[i];
		if (index_stade < 0 || index_stade + 1 > stade_competition_max) continue;
		positions_batch.append(Vector3(px_r[i], y_sol, pz_r[i]));
		slots_batch.append(i);
	}
	out["positions_batch"] = positions_batch;
	out["slots_batch"] = slots_batch;
	out["curseur_avance"] = curseur;
	return out;
}

PackedInt32Array SimulationArbre::decider_morts_competition(
		const PackedInt32Array &slots_batch,
		const PackedInt32Array &voisins_offsets,
		const PackedInt32Array &voisins_slots,
		int competition_max_voisins) {
	PackedInt32Array morts_slots;
	if (_rng.is_null()) return morts_slots;
	int m = slots_batch.size();
	if (m == 0) return morts_slots;
	const int32_t *slots_r = slots_batch.ptr();
	const int32_t *off_r = voisins_offsets.ptr();
	const int32_t *vs_r = voisins_slots.ptr();
	// morts_du_tick : set des slots deja decides morts dans ce lot,
	// utilise pour decompter les voisins morts du tick (miroir du
	// Dictionary GDScript, mais indexe par slot int32 au lieu d'id
	// String -- correspondance directe car _voisin.slot == chose.slot).
	std::unordered_set<int32_t> morts_du_tick;
	int max_v = std::max(1, competition_max_voisins);
	for (int k = 0; k < m; ++k) {
		int slot = slots_r[k];
		int deb = off_r[k];
		int fin = off_r[k + 1];
		int voisins_n = fin - deb;
		if (!morts_du_tick.empty()) {
			for (int j = deb; j < fin; ++j) {
				if (morts_du_tick.find(vs_r[j]) != morts_du_tick.end()) {
					--voisins_n;
				}
			}
		}
		if (voisins_n > competition_max_voisins) {
			int exces = voisins_n - competition_max_voisins;
			// Miroir clampf(exces/max, 0, 1) GDScript en DOUBLE.
			double proba = double(exces) / double(max_v);
			if (proba < 0.0) proba = 0.0;
			else if (proba > 1.0) proba = 1.0;
			double randf = double(_rng->randf());
			if (randf < proba) {
				morts_du_tick.insert(slot);
				morts_slots.append(slot);
			}
		}
	}
	return morts_slots;
}

void SimulationArbre::arbre_ouvrir_niveau(int exposant) {
	if (_niveaux_arbre.find(exposant) != _niveaux_arbre.end()) return;
	NiveauArbre n;
	n.exposant = exposant;
	n.inv_arete = 1.0 / std::pow(2.0, double(exposant));
	// Repopule depuis _positions_arbre (miroir _batir monde.gd).
	// Ordre : parcours des slots dans l'ordre d'insertion de la map.
	// Note : unordered_map ne garantit pas un ordre stable ; ce niveau
	// s'ouvre AVANT tout ajout d'arbre pour eviter la dependance a l'ordre.
	for (auto &p : _positions_arbre) {
		int32_t slot = p.first;
		double x = double(p.second.first);
		double z = double(p.second.second);
		// cy calcule sur position.y = y_sol supposee constante. On ne
		// stocke pas y : ici on met cy = 0 par convention et on reconstruit
		// cy a la requete via floori(y_sol * inv_a). Ecart avec le GDScript
		// qui stocke cy dans la clef -- corrige : je reinsere lors du
		// premier arbre_ajouter_lot avec le vrai y_sol. Ce chemin n'est
		// pas exercice tant qu'on ouvre les niveaux avant ajout.
		Vector3i cle(int(std::floor(x * n.inv_arete)), 0, int(std::floor(z * n.inv_arete)));
		n.cases[cle].push_back(slot);
		n.case_de[slot] = cle;
	}
	_niveaux_arbre[exposant] = std::move(n);
}

void SimulationArbre::arbre_ajouter_lot(
		const PackedInt32Array &slots,
		const PackedFloat32Array &positions_x,
		const PackedFloat32Array &positions_z,
		float y_sol) {
	int n = slots.size();
	const int32_t *sr = slots.ptr();
	const float *px = positions_x.ptr();
	const float *pz = positions_z.ptr();
	for (int k = 0; k < n; ++k) {
		int32_t slot = sr[k];
		float x = px[k];
		float z = pz[k];
		_positions_arbre[slot] = std::make_pair(x, z);
		// Inscrit dans TOUS les niveaux ouverts.
		for (auto &kv : _niveaux_arbre) {
			NiveauArbre &niveau = kv.second;
			int cy = int(std::floor(double(y_sol) * niveau.inv_arete));
			Vector3i cle(int(std::floor(double(x) * niveau.inv_arete)),
					cy,
					int(std::floor(double(z) * niveau.inv_arete)));
			niveau.cases[cle].push_back(slot);
			niveau.case_de[slot] = cle;
		}
	}
}

void SimulationArbre::arbre_retirer_lot(const PackedInt32Array &slots) {
	int n = slots.size();
	const int32_t *sr = slots.ptr();
	for (int k = 0; k < n; ++k) {
		int32_t slot = sr[k];
		_positions_arbre.erase(slot);
		for (auto &kv : _niveaux_arbre) {
			NiveauArbre &niveau = kv.second;
			auto it_case = niveau.case_de.find(slot);
			if (it_case == niveau.case_de.end()) continue;
			Vector3i cle = it_case->second;
			auto it_v = niveau.cases.find(cle);
			if (it_v != niveau.cases.end()) {
				auto &vec = it_v->second;
				// swap-remove : miroir monde.gd _deranger mode simple.
				for (size_t i = 0; i < vec.size(); ++i) {
					if (vec[i] == slot) {
						int32_t last = vec.back();
						vec[i] = last;
						vec.pop_back();
						if (last != slot) {
							niveau.case_de[last] = cle;
						}
						break;
					}
				}
				if (vec.empty()) niveau.cases.erase(cle);
			}
			niveau.case_de.erase(slot);
		}
	}
}

Dictionary SimulationArbre::arbre_choses_dans_rayons_brut_xz(
		const PackedFloat32Array &positions_x,
		const PackedFloat32Array &positions_z,
		float y_sol,
		float rayon) const {
	Dictionary out;
	PackedInt32Array offsets;
	PackedInt32Array slots;
	int n_pos = positions_x.size();
	offsets.resize(n_pos + 1);
	int32_t *off_w = offsets.ptrw();
	off_w[0] = 0;
	if (n_pos == 0 || rayon <= 0.0f) {
		out["offsets"] = offsets;
		out["slots"] = slots;
		return out;
	}
	// Miroir _exposant_pour l.860-863 : ceil(log2(rayon)), clampe.
	// Bornes EXPOSANT_MIN/MAX de monde.gd : je ne connais pas les
	// constantes, je clamp large [-16, 16]. En pratique tous les rayons
	// du banc arbre tombent dans [1, 20].
	int exposant = int(std::ceil(std::log(double(rayon)) / std::log(2.0)));
	if (exposant < -16) exposant = -16;
	if (exposant > 16) exposant = 16;
	auto it_niv = _niveaux_arbre.find(exposant);
	if (it_niv == _niveaux_arbre.end()) {
		// Niveau non ouvert : rendre resultat vide (offsets tous a 0).
		for (int k = 1; k <= n_pos; ++k) off_w[k] = 0;
		out["offsets"] = offsets;
		out["slots"] = slots;
		return out;
	}
	const NiveauArbre &niveau = it_niv->second;
	double inv_a = niveau.inv_arete;
	const float *px = positions_x.ptr();
	const float *pz = positions_z.ptr();
	double d_rayon = double(rayon);
	double carre = d_rayon * d_rayon;
	int cy = int(std::floor(double(y_sol) * inv_a));
	int total = 0;
	for (int k = 0; k < n_pos; ++k) {
		double px_r = double(px[k]);
		double pz_r = double(pz[k]);
		double pos_bas_x = px_r - d_rayon;
		double pos_bas_z = pz_r - d_rayon;
		double pos_haut_x = px_r + d_rayon;
		double pos_haut_z = pz_r + d_rayon;
		int cx_min = int(std::floor(pos_bas_x * inv_a));
		int cx_max = int(std::floor(pos_haut_x * inv_a));
		int cz_min = int(std::floor(pos_bas_z * inv_a));
		int cz_max = int(std::floor(pos_haut_z * inv_a));
		for (int cx = cx_min; cx <= cx_max; ++cx) {
			for (int cz = cz_min; cz <= cz_max; ++cz) {
				Vector3i cle(cx, cy, cz);
				auto it_case = niveau.cases.find(cle);
				if (it_case == niveau.cases.end()) continue;
				const auto &vec = it_case->second;
				for (int32_t s : vec) {
					auto it_pos = _positions_arbre.find(s);
					if (it_pos == _positions_arbre.end()) continue;
					double vx = double(it_pos->second.first);
					double vz = double(it_pos->second.second);
					// Distance^2 3D avec dy = 0 (tous a Y_SOL) = distance^2 xz.
					double dx = vx - px_r;
					double dz = vz - pz_r;
					if (dx * dx + dz * dz <= carre) {
						slots.append(s);
						++total;
					}
				}
			}
		}
		off_w[k + 1] = total;
	}
	out["offsets"] = offsets;
	out["slots"] = slots;
	return out;
}

} // namespace godot
