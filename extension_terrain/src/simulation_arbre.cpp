#include "simulation_arbre.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
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
			D_METHOD("mettre_a_jour_buffers_rendu",
					"capacite",
					"libres",
					"ages",
					"slot_stade",
					"positions_x",
					"positions_y",
					"positions_z",
					"filtre_actif",
					"ox",
					"oz",
					"rayon_carre",
					"cone_actif",
					"dir_x",
					"dir_z",
					"cos_demi_angle",
					"obs_y",
					"pitch_y"),
			&SimulationArbre::mettre_a_jour_buffers_rendu);
	ClassDB::bind_method(D_METHOD("invalider_cache_rendu"), &SimulationArbre::invalider_cache_rendu);
	ClassDB::bind_method(
			D_METHOD("definir_fov_buffer", "fov_v_deg", "aspect"),
			&SimulationArbre::definir_fov_buffer);
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
	ClassDB::bind_method(
			D_METHOD("initialiser_stable_semis",
					"rayon_trouee",
					"facteur_trouee_gros",
					"rayon_exclusion",
					"trouee_max_voisins",
					"demi_carte",
					"seuil_couvert"),
			&SimulationArbre::initialiser_stable_semis);
	ClassDB::bind_method(
			D_METHOD("definir_zones_exclusion_cpp",
					"formes",
					"cx",
					"cz",
					"rayon",
					"demi_x",
					"demi_z"),
			&SimulationArbre::definir_zones_exclusion_cpp);
	ClassDB::bind_method(
			D_METHOD("semer_pre_filtre",
					"graines_x",
					"graines_z",
					"y_sol"),
			&SimulationArbre::semer_pre_filtre);
	ClassDB::bind_method(
			D_METHOD("semer_gate_decision",
					"graines_x",
					"graines_z",
					"naissances_deja_x",
					"naissances_deja_z",
					"indices_valides",
					"voisins_offsets",
					"voisins_slots",
					"couverts",
					"slot_stade"),
			&SimulationArbre::semer_gate_decision);
	ClassDB::bind_method(
			D_METHOD("retester_reveilles_gate",
					"pros_x",
					"pros_z",
					"naissances_deja_x",
					"naissances_deja_z",
					"voisins_offsets",
					"voisins_slots",
					"couverts",
					"slot_stade"),
			&SimulationArbre::retester_reveilles_gate);
	ClassDB::bind_method(
			D_METHOD("initialiser_stable_banque",
					"taille_case_dormantes",
					"rayon_reveil",
					"duree_vie_graine"),
			&SimulationArbre::initialiser_stable_banque);
	ClassDB::bind_method(D_METHOD("banque_reset"), &SimulationArbre::banque_reset);
	ClassDB::bind_method(D_METHOD("banque_ajouter_dormante", "x", "z"), &SimulationArbre::banque_ajouter_dormante);
	ClassDB::bind_method(D_METHOD("banque_retirer_dormante", "id"), &SimulationArbre::banque_retirer_dormante);
	ClassDB::bind_method(D_METHOD("banque_nombre"), &SimulationArbre::banque_nombre);
	ClassDB::bind_method(D_METHOD("banque_avancer_temps", "pas"), &SimulationArbre::banque_avancer_temps);
	ClassDB::bind_method(D_METHOD("banque_drainer_expirations"), &SimulationArbre::banque_drainer_expirations);
	ClassDB::bind_method(D_METHOD("banque_recuperer_reveils_ids_ordre"), &SimulationArbre::banque_recuperer_reveils_ids_ordre);
	ClassDB::bind_method(D_METHOD("banque_prospects_pour_ids", "ids"), &SimulationArbre::banque_prospects_pour_ids);
	ClassDB::bind_method(D_METHOD("banque_reveiller_autour_lot", "rev_x", "rev_z"), &SimulationArbre::banque_reveiller_autour_lot);
	ClassDB::bind_method(D_METHOD("banque_reveils_est_vide"), &SimulationArbre::banque_reveils_est_vide);
	ClassDB::bind_method(
			D_METHOD("remplir_colonnes_naissance",
					"slots",
					"slots_r",
					"naissances_x",
					"naissances_y",
					"naissances_z",
					"croissance_col",
					"longevite_col",
					"stade_initial",
					"annees_par_seconde",
					"graines_par_vie",
					"fenetre_fertile_age",
					"libres",
					"ages",
					"positions_x",
					"positions_y",
					"positions_z",
					"slot_stade",
					"facteur_croissance",
					"facteur_longevite",
					"intervalle_reprod",
					"derniere_couleur_stade",
					"slot_rendu_pour_data",
					"data_pour_slot_rendu"),
			&SimulationArbre::remplir_colonnes_naissance);
}

SimulationArbre::SimulationArbre() {
	_rng.instantiate();
	_buffer_2d.assign(size_t(BUFFER_2D_LARGEUR * BUFFER_2D_HAUTEUR), std::numeric_limits<float>::infinity());
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

// ETAPE 10 : SEMIS -- init stables.
void SimulationArbre::initialiser_stable_semis(
		float rayon_trouee,
		float facteur_trouee_gros,
		float rayon_exclusion,
		int trouee_max_voisins,
		float demi_carte,
		float seuil_couvert) {
	_rayon_trouee = rayon_trouee;
	_facteur_trouee_gros = facteur_trouee_gros;
	_rayon_exclusion = rayon_exclusion;
	_trouee_max_voisins = trouee_max_voisins;
	_demi_carte = demi_carte;
	_seuil_couvert = seuil_couvert;
}

// ETAPE 10 : zones d'exclusion, PUSH une seule fois.
void SimulationArbre::definir_zones_exclusion_cpp(
		const PackedByteArray &formes,
		const PackedFloat32Array &cx,
		const PackedFloat32Array &cz,
		const PackedFloat32Array &rayon,
		const PackedFloat32Array &demi_x,
		const PackedFloat32Array &demi_z) {
	int n = formes.size();
	_zones_exclusion_cpp.clear();
	_zones_exclusion_cpp.reserve(n);
	const uint8_t *f = formes.ptr();
	const float *pcx = cx.ptr();
	const float *pcz = cz.ptr();
	const float *pr = rayon.ptr();
	const float *pdx = demi_x.ptr();
	const float *pdz = demi_z.ptr();
	for (int i = 0; i < n; ++i) {
		ZoneExclusionCpp z;
		z.forme = int(f[i]);
		z.cx = pcx[i];
		z.cz = pcz[i];
		z.rayon = pr[i];
		z.demi_x = pdx[i];
		z.demi_z = pdz[i];
		_zones_exclusion_cpp.push_back(z);
	}
}

// ETAPE 10 : pre-filtre (miroir l.1147-1176 de _semer_lot).
Dictionary SimulationArbre::semer_pre_filtre(
		const PackedFloat32Array &graines_x,
		const PackedFloat32Array &graines_z,
		float y_sol) const {
	Dictionary out;
	PackedInt32Array indices_valides;
	PackedVector3Array positions_valides;
	int n = graines_x.size();
	const float *gx = graines_x.ptr();
	const float *gz = graines_z.ptr();
	int n_zones = int(_zones_exclusion_cpp.size());
	for (int k = 0; k < n; ++k) {
		float px = gx[k];
		float pz = gz[k];
		if (std::fabs(px) > _demi_carte || std::fabs(pz) > _demi_carte) continue;
		bool dans_zone = false;
		for (int zi = 0; zi < n_zones; ++zi) {
			const ZoneExclusionCpp &z = _zones_exclusion_cpp[zi];
			if (z.forme == 0) {
				float dx = px - z.cx;
				float dz = pz - z.cz;
				if (dx * dx + dz * dz <= z.rayon * z.rayon) {
					dans_zone = true;
					break;
				}
			} else {
				if (std::fabs(px - z.cx) <= z.demi_x && std::fabs(pz - z.cz) <= z.demi_z) {
					dans_zone = true;
					break;
				}
			}
		}
		if (dans_zone) continue;
		indices_valides.append(k);
		positions_valides.append(Vector3(px, y_sol, pz));
	}
	out["indices_valides"] = indices_valides;
	out["positions_valides"] = positions_valides;
	return out;
}

// ETAPE 10 : gate trouee + decision (miroir l.1185-1231 de _semer_lot).
// L'inscription banque + dormantes reste GDScript, appliquee sur banque_x/z.
Dictionary SimulationArbre::semer_gate_decision(
		const PackedFloat32Array &graines_x,
		const PackedFloat32Array &graines_z,
		const PackedFloat32Array &naissances_deja_x,
		const PackedFloat32Array &naissances_deja_z,
		const PackedInt32Array &indices_valides,
		const PackedInt32Array &voisins_offsets,
		const PackedInt32Array &voisins_slots,
		const PackedFloat32Array &couverts,
		const PackedInt32Array &slot_stade) const {
	Dictionary out;
	PackedFloat32Array naissances_ajouts_x;
	PackedFloat32Array naissances_ajouts_z;
	PackedFloat32Array banque_x;
	PackedFloat32Array banque_z;

	const float *gx = graines_x.ptr();
	const float *gz = graines_z.ptr();
	const int32_t *iv = indices_valides.ptr();
	const int32_t *off = voisins_offsets.ptr();
	const int32_t *vsl = voisins_slots.ptr();
	const float *cov = couverts.ptr();
	const int32_t *ss = slot_stade.ptr();
	int taille_slot_stade = slot_stade.size();

	// Naissances dynamiques : le lot initial (naissances_deja_*) plus les
	// nouvelles produites par ce semis (l.1211-1223 du .gd). Buffer local
	// pour eviter de reboucler sur PackedFloat32Array a chaque graine.
	std::vector<float> nx;
	std::vector<float> nz;
	int n_deja = naissances_deja_x.size();
	nx.reserve(n_deja + 32);
	nz.reserve(n_deja + 32);
	if (n_deja > 0) {
		const float *ndx = naissances_deja_x.ptr();
		const float *ndz = naissances_deja_z.ptr();
		for (int i = 0; i < n_deja; ++i) {
			nx.push_back(ndx[i]);
			nz.push_back(ndz[i]);
		}
	}

	float carre_normal = _rayon_trouee * _rayon_trouee;
	float carre_min = _rayon_exclusion * _rayon_exclusion;
	int nv = indices_valides.size();
	for (int j = 0; j < nv; ++j) {
		int kk = iv[j];
		float pos_x = gx[kk];
		float pos_z = gz[kk];
		int compte_normal = 0;
		bool passe = true;

		// Voisins arbres (offsets CSR sur le j-ieme valide).
		int off_beg = off[j];
		int off_end = off[j + 1];
		for (int oi = off_beg; oi < off_end; ++oi) {
			int32_t slot_v = vsl[oi];
			int stade_num = 0;
			if (slot_v >= 0 && slot_v < taille_slot_stade) {
				stade_num = ss[slot_v] + 1;
			}
			if (stade_num >= _stade_gros_min && stade_num <= _stade_gros_max) {
				passe = false;
				break;
			}
			// Distance^2 xz (y_sol egal des deux cotes, dy = 0).
			auto it_pos = _positions_arbre.find(slot_v);
			if (it_pos == _positions_arbre.end()) continue;
			float vx = it_pos->second.first;
			float vz = it_pos->second.second;
			float dx = vx - pos_x;
			float dz = vz - pos_z;
			float d2 = dx * dx + dz * dz;
			if (d2 < carre_min) {
				passe = false;
				break;
			}
			if (d2 <= carre_normal) {
				++compte_normal;
			}
		}

		if (passe) {
			// Voisins naissances du meme lot (dynamique).
			int m = int(nx.size());
			for (int js = 0; js < m; ++js) {
				float dx = nx[js] - pos_x;
				float dz = nz[js] - pos_z;
				float d2n = dx * dx + dz * dz;
				if (d2n < carre_min) {
					passe = false;
					break;
				}
				if (d2n <= carre_normal) {
					++compte_normal;
				}
			}
		}

		if (passe && compte_normal > _trouee_max_voisins) {
			passe = false;
		}
		if (!passe) continue;

		if (cov[kk] < _seuil_couvert) {
			naissances_ajouts_x.append(pos_x);
			naissances_ajouts_z.append(pos_z);
			nx.push_back(pos_x);
			nz.push_back(pos_z);
			continue;
		}
		banque_x.append(pos_x);
		banque_z.append(pos_z);
	}

	out["naissances_ajouts_x"] = naissances_ajouts_x;
	out["naissances_ajouts_z"] = naissances_ajouts_z;
	out["banque_x"] = banque_x;
	out["banque_z"] = banque_z;
	return out;
}

// ETAPE 11 : gate re-test des reveilles (miroir _tick_banque l.1407-1489).
Dictionary SimulationArbre::retester_reveilles_gate(
		const PackedFloat32Array &pros_x,
		const PackedFloat32Array &pros_z,
		const PackedFloat32Array &naissances_deja_x,
		const PackedFloat32Array &naissances_deja_z,
		const PackedInt32Array &voisins_offsets,
		const PackedInt32Array &voisins_slots,
		const PackedFloat32Array &couverts,
		const PackedInt32Array &slot_stade) const {
	Dictionary out;
	PackedInt32Array naissances_indices;

	int n = pros_x.size();
	const float *px = pros_x.ptr();
	const float *pz = pros_z.ptr();
	const int32_t *off = voisins_offsets.ptr();
	const int32_t *vsl = voisins_slots.ptr();
	const float *cov = couverts.ptr();
	const int32_t *ss = slot_stade.ptr();
	int taille_slot_stade = slot_stade.size();
	int n_zones = int(_zones_exclusion_cpp.size());

	// Naissances dynamiques : le lot initial (naissances du semis) plus les
	// nouvelles produites par les reveilles (l.1459-1470, l.1488-1489 du .gd).
	std::vector<float> nx;
	std::vector<float> nz;
	int n_deja = naissances_deja_x.size();
	nx.reserve(n_deja + 32);
	nz.reserve(n_deja + 32);
	if (n_deja > 0) {
		const float *ndx = naissances_deja_x.ptr();
		const float *ndz = naissances_deja_z.ptr();
		for (int i = 0; i < n_deja; ++i) {
			nx.push_back(ndx[i]);
			nz.push_back(ndz[i]);
		}
	}

	float carre_normal = _rayon_trouee * _rayon_trouee;
	float carre_min = _rayon_exclusion * _rayon_exclusion;

	for (int j = 0; j < n; ++j) {
		float pos_x = px[j];
		float pos_z = pz[j];

		// Zones filtrees INLINE (miroir l.1416-1434 du .gd).
		if (n_zones > 0) {
			bool dans_zone = false;
			for (int zi = 0; zi < n_zones; ++zi) {
				const ZoneExclusionCpp &z = _zones_exclusion_cpp[zi];
				if (z.forme == 0) {
					float zdx = pos_x - z.cx;
					float zdz = pos_z - z.cz;
					if (zdx * zdx + zdz * zdz <= z.rayon * z.rayon) {
						dans_zone = true;
						break;
					}
				} else {
					if (std::fabs(pos_x - z.cx) <= z.demi_x && std::fabs(pos_z - z.cz) <= z.demi_z) {
						dans_zone = true;
						break;
					}
				}
			}
			if (dans_zone) continue;
		}

		int compte_normal = 0;
		bool passe = true;

		// Voisins arbres via CSR sur j.
		int off_beg = off[j];
		int off_end = off[j + 1];
		for (int oi = off_beg; oi < off_end; ++oi) {
			int32_t slot_v = vsl[oi];
			int stade_num = 0;
			if (slot_v >= 0 && slot_v < taille_slot_stade) {
				stade_num = ss[slot_v] + 1;
			}
			if (stade_num >= _stade_gros_min && stade_num <= _stade_gros_max) {
				passe = false;
				break;
			}
			auto it_pos = _positions_arbre.find(slot_v);
			if (it_pos == _positions_arbre.end()) continue;
			float vx = it_pos->second.first;
			float vz = it_pos->second.second;
			float dx = vx - pos_x;
			float dz = vz - pos_z;
			float d2 = dx * dx + dz * dz;
			if (d2 < carre_min) {
				passe = false;
				break;
			}
			if (d2 <= carre_normal) {
				++compte_normal;
			}
		}

		if (passe) {
			// Voisins naissances du meme lot (dynamique).
			int m = int(nx.size());
			for (int js = 0; js < m; ++js) {
				float dx = nx[js] - pos_x;
				float dz = nz[js] - pos_z;
				float d2n = dx * dx + dz * dz;
				if (d2n < carre_min) {
					passe = false;
					break;
				}
				if (d2n <= carre_normal) {
					++compte_normal;
				}
			}
		}

		if (passe && compte_normal > _trouee_max_voisins) {
			passe = false;
		}
		if (!passe) continue;

		// Reveil : couvert >= seuil -> skip (le prospect reste en banque).
		if (cov[j] >= _seuil_couvert) continue;

		naissances_indices.append(j);
		nx.push_back(pos_x);
		nz.push_back(pos_z);
	}

	out["naissances_indices"] = naissances_indices;
	return out;
}

// ETAPE 12 : remplissage colonnes plates naissance (miroir _naitre_lot
// l.1587-1628, colonnes plates + INF ordre float preserve). Aucune touche
// aux structures non-plates (_derniere_params Array, _choses_arbre,
// _entries_monde_ntl, monde, shadow, ombrage) : elles restent GDScript.
Dictionary SimulationArbre::remplir_colonnes_naissance(
		const PackedInt32Array &slots,
		const PackedInt32Array &slots_r,
		const PackedFloat32Array &naissances_x,
		const PackedFloat32Array &naissances_y,
		const PackedFloat32Array &naissances_z,
		const PackedFloat32Array &croissance_col,
		const PackedFloat32Array &longevite_col,
		int stade_initial,
		float annees_par_seconde,
		float graines_par_vie,
		float fenetre_fertile_age,
		const PackedByteArray &libres,
		const PackedFloat32Array &ages,
		const PackedFloat32Array &positions_x,
		const PackedFloat32Array &positions_y,
		const PackedFloat32Array &positions_z,
		const PackedInt32Array &slot_stade,
		const PackedFloat32Array &facteur_croissance,
		const PackedFloat32Array &facteur_longevite,
		const PackedFloat32Array &intervalle_reprod,
		const PackedInt32Array &derniere_couleur_stade,
		const PackedInt32Array &slot_rendu_pour_data,
		const PackedInt32Array &data_pour_slot_rendu) const {
	Dictionary out;
	// COW-copy chaque colonne, ptrw() la met en propriete privee.
	PackedByteArray out_libres = libres;
	PackedFloat32Array out_ages = ages;
	PackedFloat32Array out_px = positions_x;
	PackedFloat32Array out_py = positions_y;
	PackedFloat32Array out_pz = positions_z;
	PackedInt32Array out_stade = slot_stade;
	PackedFloat32Array out_fc = facteur_croissance;
	PackedFloat32Array out_fl = facteur_longevite;
	PackedFloat32Array out_ir = intervalle_reprod;
	PackedInt32Array out_dcs = derniere_couleur_stade;
	PackedInt32Array out_srpd = slot_rendu_pour_data;
	PackedInt32Array out_dpsr = data_pour_slot_rendu;

	uint8_t *w_libres = out_libres.ptrw();
	float *w_ages = out_ages.ptrw();
	float *w_px = out_px.ptrw();
	float *w_py = out_py.ptrw();
	float *w_pz = out_pz.ptrw();
	int32_t *w_stade = out_stade.ptrw();
	float *w_fc = out_fc.ptrw();
	float *w_fl = out_fl.ptrw();
	float *w_ir = out_ir.ptrw();
	int32_t *w_dcs = out_dcs.ptrw();
	int32_t *w_srpd = out_srpd.ptrw();
	int32_t *w_dpsr = out_dpsr.ptrw();

	int n = slots.size();
	const int32_t *r_slots = slots.ptr();
	const int32_t *r_slots_r = slots_r.ptr();
	const float *r_nx = naissances_x.ptr();
	const float *r_ny = naissances_y.ptr();
	const float *r_nz = naissances_z.ptr();
	const float *r_cc = croissance_col.ptr();
	const float *r_lc = longevite_col.ptr();

	float denom_prefixe = annees_par_seconde * graines_par_vie;
	const float INF32 = std::numeric_limits<float>::infinity();

	for (int k = 0; k < n; ++k) {
		int32_t slot = r_slots[k];
		float pos_x = r_nx[k];
		float pos_y = r_ny[k];
		float pos_z = r_nz[k];
		w_libres[slot] = 0;
		w_ages[slot] = 0.0f;
		w_px[slot] = pos_x;
		w_pz[slot] = pos_z;
		w_py[slot] = pos_y;
		int32_t slot_r = r_slots_r[k];
		w_srpd[slot] = slot_r;
		if (slot_r >= 0) {
			w_dpsr[slot_r] = slot;
		}
		w_stade[slot] = stade_initial;
		float cc = r_cc[k];
		float lc = r_lc[k];
		w_fc[slot] = cc;
		w_fl[slot] = lc;
		w_dcs[slot] = -1;
		// MEME formule + ordre float : denom = denom_prefixe * cc.
		float denom = denom_prefixe * cc;
		if (fenetre_fertile_age > 0.0f && denom > 0.0f) {
			w_ir[slot] = fenetre_fertile_age / denom;
		} else {
			w_ir[slot] = INF32;
		}
	}

	out["libres"] = out_libres;
	out["ages"] = out_ages;
	out["positions_x"] = out_px;
	out["positions_y"] = out_py;
	out["positions_z"] = out_pz;
	out["slot_stade"] = out_stade;
	out["facteur_croissance"] = out_fc;
	out["facteur_longevite"] = out_fl;
	out["intervalle_reprod"] = out_ir;
	out["derniere_couleur_stade"] = out_dcs;
	out["slot_rendu_pour_data"] = out_srpd;
	out["data_pour_slot_rendu"] = out_dpsr;
	return out;
}

// ============================================================================
// ETAPE 14 : banque + dormantes + expirations + reveils (etat interne).
// ============================================================================
void SimulationArbre::initialiser_stable_banque(
		float taille_case_dormantes,
		float rayon_reveil,
		float duree_vie_graine) {
	_taille_case_dormantes = taille_case_dormantes;
	_rayon_reveil = rayon_reveil;
	_duree_vie_graine = duree_vie_graine;
}

void SimulationArbre::banque_reset() {
	_prospects_ordre.clear();
	_prospects_idx.clear();
	_prochain_id_banque = 0;
	_dormantes_par_case_cpp.clear();
	_case_de_dormante_cpp.clear();
	_expirations_cpp.clear();
	_expirations_head_cpp = 0;
	_reveils_ordre.clear();
	_reveils_idx.clear();
	_temps_banque = 0.0f;
}

int SimulationArbre::banque_ajouter_dormante(float x, float z) {
	int32_t id = _prochain_id_banque;
	_prochain_id_banque += 1;
	BanqueProspect p;
	p.x = x;
	p.z = z;
	auto it = _prospects_ordre.insert(_prospects_ordre.end(), std::make_pair(id, p));
	_prospects_idx[id] = it;
	_inscrire_dormante_cpp(id, x, z);
	_expirations_cpp.push_back(std::make_pair(_temps_banque + _duree_vie_graine, id));
	return int(id);
}

void SimulationArbre::banque_retirer_dormante(int id) {
	auto it_idx = _prospects_idx.find(int32_t(id));
	if (it_idx == _prospects_idx.end()) return;
	_prospects_ordre.erase(it_idx->second);
	_prospects_idx.erase(it_idx);
	_retirer_dormante_cpp(int32_t(id));
}

int SimulationArbre::banque_nombre() const {
	return int(_prospects_ordre.size());
}

void SimulationArbre::banque_avancer_temps(float pas) {
	_temps_banque += pas;
}

void SimulationArbre::banque_drainer_expirations() {
	// Miroir l.1354-1377 du .gd : avance _head tant que temps <= _temps_banque,
	// retire chaque id encore present dans _prospects (retirer_dormante inclus).
	int n = int(_expirations_cpp.size());
	while (_expirations_head_cpp < n) {
		auto &entry = _expirations_cpp[_expirations_head_cpp];
		if (entry.first > _temps_banque) break;
		_expirations_head_cpp += 1;
		int32_t id = entry.second;
		auto it_idx = _prospects_idx.find(id);
		if (it_idx != _prospects_idx.end()) {
			_prospects_ordre.erase(it_idx->second);
			_prospects_idx.erase(it_idx);
			_retirer_dormante_cpp(id);
		}
	}
	// Compaction (miroir l.1375-1377) : _head > 1024 et _head > size/2.
	if (_expirations_head_cpp > 1024 && _expirations_head_cpp > int(_expirations_cpp.size() >> 1)) {
		_expirations_cpp.erase(_expirations_cpp.begin(), _expirations_cpp.begin() + _expirations_head_cpp);
		_expirations_head_cpp = 0;
	}
}

PackedInt32Array SimulationArbre::banque_recuperer_reveils_ids_ordre() {
	PackedInt32Array out;
	out.resize(int(_reveils_ordre.size()));
	int32_t *w = out.ptrw();
	int k = 0;
	for (int32_t id : _reveils_ordre) {
		w[k] = id;
		++k;
	}
	_reveils_ordre.clear();
	_reveils_idx.clear();
	return out;
}

Dictionary SimulationArbre::banque_prospects_pour_ids(const PackedInt32Array &ids) const {
	Dictionary out;
	int n = ids.size();
	PackedByteArray presents;
	PackedFloat32Array x;
	PackedFloat32Array z;
	presents.resize(n);
	x.resize(n);
	z.resize(n);
	uint8_t *pw = presents.ptrw();
	float *xw = x.ptrw();
	float *zw = z.ptrw();
	const int32_t *r = ids.ptr();
	for (int k = 0; k < n; ++k) {
		int32_t id = r[k];
		auto it = _prospects_idx.find(id);
		if (it == _prospects_idx.end()) {
			pw[k] = 0;
			xw[k] = 0.0f;
			zw[k] = 0.0f;
		} else {
			pw[k] = 1;
			xw[k] = it->second->second.x;
			zw[k] = it->second->second.z;
		}
	}
	out["presents"] = presents;
	out["x"] = x;
	out["z"] = z;
	return out;
}

void SimulationArbre::banque_reveiller_autour_lot(
		const PackedFloat32Array &rev_x,
		const PackedFloat32Array &rev_z) {
	// Miroir _reveiller_dormantes_autour_lot (l.1042-1072 morts_v du .gd).
	int n = rev_x.size();
	if (n == 0) return;
	if (_rayon_reveil <= 0.0f) return;
	if (_taille_case_dormantes <= 0.0f) return;
	if (_dormantes_par_case_cpp.empty()) return;
	float inv_case = 1.0f / _taille_case_dormantes;
	float carre = _rayon_reveil * _rayon_reveil;
	const float *px = rev_x.ptr();
	const float *pz = rev_z.ptr();
	for (int k = 0; k < n; ++k) {
		float pos_x = px[k];
		float pos_z = pz[k];
		int cx_min = int(std::floor((pos_x - _rayon_reveil) * inv_case));
		int cx_max = int(std::floor((pos_x + _rayon_reveil) * inv_case));
		int cz_min = int(std::floor((pos_z - _rayon_reveil) * inv_case));
		int cz_max = int(std::floor((pos_z + _rayon_reveil) * inv_case));
		for (int cx = cx_min; cx <= cx_max; ++cx) {
			for (int cz = cz_min; cz <= cz_max; ++cz) {
				Vector2i cle(cx, cz);
				auto it_case = _dormantes_par_case_cpp.find(cle);
				if (it_case == _dormantes_par_case_cpp.end()) continue;
				const std::vector<int32_t> &ids = it_case->second;
				for (int32_t id : ids) {
					if (_reveils_idx.find(id) != _reveils_idx.end()) continue;
					auto it_pros = _prospects_idx.find(id);
					if (it_pros == _prospects_idx.end()) continue;
					float vx = it_pros->second->second.x;
					float vz = it_pros->second->second.z;
					float dx = vx - pos_x;
					float dz = vz - pos_z;
					if (dx * dx + dz * dz <= carre) {
						auto it_r = _reveils_ordre.insert(_reveils_ordre.end(), id);
						_reveils_idx[id] = it_r;
					}
				}
			}
		}
	}
}

bool SimulationArbre::banque_reveils_est_vide() const {
	return _reveils_ordre.empty();
}

// Helper prive : miroir _inscrire_dormante(id, pos_x, pos_z) l.1237-1246 du .gd.
void SimulationArbre::_inscrire_dormante_cpp(int32_t id, float x, float z) {
	if (_taille_case_dormantes <= 0.0f) return;
	float inv_case = 1.0f / _taille_case_dormantes;
	Vector2i cle(int(std::floor(x * inv_case)), int(std::floor(z * inv_case)));
	_dormantes_par_case_cpp[cle].push_back(id);
	_case_de_dormante_cpp[id] = cle;
}

// Helper prive : miroir _retirer_dormante(id).
// Preserve l'ordre des ids restants dans la case (erase par valeur, pas swap).
void SimulationArbre::_retirer_dormante_cpp(int32_t id) {
	auto it_cle = _case_de_dormante_cpp.find(id);
	if (it_cle == _case_de_dormante_cpp.end()) return;
	Vector2i cle = it_cle->second;
	_case_de_dormante_cpp.erase(it_cle);
	auto it_case = _dormantes_par_case_cpp.find(cle);
	if (it_case == _dormantes_par_case_cpp.end()) return;
	std::vector<int32_t> &vec = it_case->second;
	// Erase par valeur (preserve ordre restant, miroir Array.erase() GDScript).
	for (size_t i = 0; i < vec.size(); ++i) {
		if (vec[i] == id) {
			vec.erase(vec.begin() + i);
			break;
		}
	}
	if (vec.empty()) _dormantes_par_case_cpp.erase(it_case);
}

// ============================================================================
// ETAPE B2 : mise a jour incrementale des buffers rendu (cache EPS_TAILLE).
// ============================================================================
static constexpr float EPS_TAILLE_RENDU = 0.001f;

void SimulationArbre::invalider_cache_rendu() {
	_cache_rendu_force_reset = true;
}

void SimulationArbre::definir_fov_buffer(float fov_v_deg, float aspect) {
	constexpr float PI_F = 3.14159265358979323846f;
	float fv = fov_v_deg;
	if (fv < 1.0f) fv = 1.0f;
	if (fv > 170.0f) fv = 170.0f;
	float fh = fv * (aspect > 0.01f ? aspect : 1.0f);
	if (fh > 170.0f) fh = 170.0f;
	_fov_v_rad_buffer = fv * PI_F / 180.0f;
	_fov_h_rad_buffer = fh * PI_F / 180.0f;
}

Dictionary SimulationArbre::mettre_a_jour_buffers_rendu(
		int capacite,
		const PackedByteArray &libres,
		const PackedFloat32Array &ages,
		const PackedInt32Array &slot_stade,
		const PackedFloat32Array &positions_x,
		const PackedFloat32Array &positions_y,
		const PackedFloat32Array &positions_z,
		bool filtre_actif,
		float ox,
		float oz,
		float rayon_carre,
		bool cone_actif,
		float dir_x,
		float dir_z,
		float cos_demi_angle,
		float obs_y,
		float pitch_y) {
	Dictionary out;
	int cap = capacite;

	// Detection changement de capacite / cache reset -> tout_dirty.
	bool tout_dirty = false;
	if (cap != _rendu_cap_actuelle || _cache_rendu_force_reset) {
		tout_dirty = true;
		_rendu_cap_actuelle = cap;
		_cache_rendu_force_reset = false;
		_buf_tronc_p.assign(size_t(cap) * 16, 0.0f);
		_buf_feuillage_p.assign(size_t(cap) * 16, 0.0f);
		_cache_valide.assign(size_t(cap), 0);
		_cache_libres_ecrit.assign(size_t(cap), 0);
		_cache_stade_ecrit.assign(size_t(cap), -1);
		_cache_p_ht.assign(size_t(cap), 0.0f);
		_cache_p_lt.assign(size_t(cap), 0.0f);
		_cache_p_hf.assign(size_t(cap), 0.0f);
		_cache_p_lf.assign(size_t(cap), 0.0f);
		_cache_terminal.assign(size_t(cap), 0);
	}

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

	float *bt = _buf_tronc_p.data();
	float *bf = _buf_feuillage_p.data();

	// Liste des dirty slots ce tick.
	std::vector<int32_t> dirty;
	dirty.reserve(size_t(cap));

	for (int i = 0; i < cap; ++i) {
		int base = i * 16;
		uint8_t libres_i = libres_r[i];

		// Slot LIBRE (mort ou vide) : cache_libres==1 et pas invalide -> skip.
		if (libres_i == 1) {
			if (_cache_valide[i] == 1 && _cache_libres_ecrit[i] == 1) {
				continue;
			}
			// Ecrit slot vide (miroir _ecrire_slot_vide oracle).
			bt[base + 0] = 0.0f; bt[base + 1] = 0.0f; bt[base + 2] = 0.0f; bt[base + 3] = 0.0f;
			bt[base + 4] = 0.0f; bt[base + 5] = 0.0f; bt[base + 6] = 0.0f; bt[base + 7] = y_sol_def;
			bt[base + 8] = 0.0f; bt[base + 9] = 0.0f; bt[base + 10] = 0.0f; bt[base + 11] = 0.0f;
			bt[base + 12] = 0.0f; bt[base + 13] = 0.0f; bt[base + 14] = 0.0f; bt[base + 15] = 1.0f;
			bf[base + 0] = 0.0f; bf[base + 1] = 0.0f; bf[base + 2] = 0.0f; bf[base + 3] = 0.0f;
			bf[base + 4] = 0.0f; bf[base + 5] = 0.0f; bf[base + 6] = 0.0f; bf[base + 7] = y_sol_def;
			bf[base + 8] = 0.0f; bf[base + 9] = 0.0f; bf[base + 10] = 0.0f; bf[base + 11] = 0.0f;
			bf[base + 12] = 0.0f; bf[base + 13] = 0.0f; bf[base + 14] = 0.0f; bf[base + 15] = 1.0f;
			_cache_valide[i] = 1;
			_cache_libres_ecrit[i] = 1;
			_cache_stade_ecrit[i] = -1;
			_cache_p_ht[i] = 0.0f;
			_cache_p_lt[i] = 0.0f;
			_cache_p_hf[i] = 0.0f;
			_cache_p_lf[i] = 0.0f;
			_cache_terminal[i] = 0;
			dirty.push_back(int32_t(i));
			continue;
		}

		// Slot VIVANT.
		// FIX B2 : EARLY-EXIT avant compute lerp. En regime stable, la
		// grande majorite des slots sont "terminaux" (age > sum(durees) ->
		// trouve==false, ht/lt/hf/lf figes aux valeurs du dernier stade).
		// Si le cache l'atteste et que stade/libres n'ont pas change, le
		// buffer est deja bon -> skip SANS calculer lerp. Sans ce test,
		// le lerp est calcule pour tous les slots vivants chaque tick
		// (cause des ~10ms en regime stable a N=8400).
		int stade_actuel_early = stade_r[i];
		if (_cache_valide[i] == 1
				&& _cache_libres_ecrit[i] == 0
				&& _cache_stade_ecrit[i] == stade_actuel_early
				&& _cache_terminal[i] == 1) {
			continue;
		}
		float age = ages_r[i];
		double ht = 0.0, lt = 0.0, hf = 0.0, lf = 0.0;
		double duree_cumulee = 0.0;
		bool trouve = false;
		for (int j = 0; j < n_durees; ++j) {
			double duree_segment = double(dur[j]);
			if (double(age) <= duree_cumulee + duree_segment) {
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
		float ht_f = float(ht);
		float lt_f = float(lt);
		float hf_f = float(hf);
		float lf_f = float(lf);

		// SKIP EPS_TAILLE : slot vivant deja ecrit, meme stade, |delta| < EPS
		// sur les 4 params (ht/lt/hf/lf). Miroir _derniere_params oracle.
		bool slot_meme_stade_cache = (_cache_valide[i] == 1 && _cache_libres_ecrit[i] == 0 && _cache_stade_ecrit[i] == stade_actuel);
		if (slot_meme_stade_cache) {
			float d_ht = std::fabs(ht_f - _cache_p_ht[i]);
			float d_lt = std::fabs(lt_f - _cache_p_lt[i]);
			float d_hf = std::fabs(hf_f - _cache_p_hf[i]);
			float d_lf = std::fabs(lf_f - _cache_p_lf[i]);
			if (d_ht < EPS_TAILLE_RENDU && d_lt < EPS_TAILLE_RENDU
					&& d_hf < EPS_TAILLE_RENDU && d_lf < EPS_TAILLE_RENDU) {
				continue;
			}
		}

		// Recalcul complet du slot.
		Color ct = _couleur_repli_tronc;
		Color cf = _couleur_repli_feuillage;
		if (stade_actuel >= 0 && stade_actuel < n_col_t) ct = _couleur_tronc[stade_actuel];
		if (stade_actuel >= 0 && stade_actuel < n_col_f) cf = _couleur_feuillage[stade_actuel];

		float pos_x = px_r[i];
		double pos_y_sol = double(py_r[i]);
		float pos_z = pz_r[i];

		bt[base + 0] = lt_f; bt[base + 1] = 0.0f;  bt[base + 2] = 0.0f;  bt[base + 3] = pos_x;
		bt[base + 4] = 0.0f; bt[base + 5] = ht_f;  bt[base + 6] = 0.0f;  bt[base + 7] = float(pos_y_sol + ht * 0.5);
		bt[base + 8] = 0.0f; bt[base + 9] = 0.0f;  bt[base + 10] = lt_f; bt[base + 11] = pos_z;
		bt[base + 12] = ct.r; bt[base + 13] = ct.g; bt[base + 14] = ct.b; bt[base + 15] = ct.a;

		if (hf <= 0.0 || lf <= 0.0) {
			bf[base + 0] = 0.0f; bf[base + 1] = 0.0f; bf[base + 2] = 0.0f; bf[base + 3] = pos_x;
			bf[base + 4] = 0.0f; bf[base + 5] = 0.0f; bf[base + 6] = 0.0f; bf[base + 7] = float(pos_y_sol + ht);
			bf[base + 8] = 0.0f; bf[base + 9] = 0.0f; bf[base + 10] = 0.0f; bf[base + 11] = pos_z;
		} else {
			bf[base + 0] = lf_f; bf[base + 1] = 0.0f; bf[base + 2] = 0.0f; bf[base + 3] = pos_x;
			bf[base + 4] = 0.0f; bf[base + 5] = hf_f; bf[base + 6] = 0.0f; bf[base + 7] = float(pos_y_sol + ht + hf * 0.5);
			bf[base + 8] = 0.0f; bf[base + 9] = 0.0f; bf[base + 10] = lf_f; bf[base + 11] = pos_z;
		}
		bf[base + 12] = cf.r; bf[base + 13] = cf.g; bf[base + 14] = cf.b; bf[base + 15] = cf.a;

		_cache_valide[i] = 1;
		_cache_libres_ecrit[i] = 0;
		_cache_stade_ecrit[i] = stade_actuel;
		_cache_p_ht[i] = ht_f;
		_cache_p_lt[i] = lt_f;
		_cache_p_hf[i] = hf_f;
		_cache_p_lf[i] = lf_f;
		// FIX B2 : marquer terminal si trouve==false (age depasse sum(durees) ->
		// valeurs figees au dernier stade). Le prochain tick, le early-exit
		// skippera SANS relancer le lerp.
		_cache_terminal[i] = trouve ? 0 : 1;
		dirty.push_back(int32_t(i));
	}

	int dirty_count = int(dirty.size());
	out["tout_dirty"] = tout_dirty;
	out["dirty_count"] = dirty_count;

	// RENDU COMPACT (prompt 2026-09-14 + filtre cercle 2026-09-15). Le
	// buffer emis contient UNIQUEMENT les slots vivants ET dans le cercle
	// autour de l'observateur si filtre_actif=true (sinon TOUS les vivants).
	// Ranges 0..pop-1 dans l'ordre croissant des slots data. Le cache/lerp
	// /EPS restent indexes par slot data ; seule l'ECRITURE finale est
	// compacte. La sim GDScript ne depend PAS de ce filtre : la boucle 0..cap
	// continue sur TOUS les arbres, ceux hors cercle grandissent normalement.
	//
	// Table slot_data -> index_rendu (cap ints, -1 si libre OU hors cercle
	// OU hors cone).
	// EPS_CONE_XZ_CARRE : sous ce seuil de distance^2 (~0.01 m^2), l'arbre est
	// considere "sur" l'observateur et TOUJOURS inclus, cone bypasse. Evite la
	// division par ~0 dans la normalisation et le pop visuel d'un arbre qui
	// passerait entre les jambes du joueur.
	constexpr float EPS_CONE_XZ_CARRE = 0.01f;
	// Occlusion Intel MOC : refill inconditionnel des bloqueurs depuis la
	// CAMERA a chaque tick. Coherence de reference frame -- meme observateur
	// pour le filtrage, le remplissage buffer 2D et la lecture.
	_bloqueurs_camera.clear();
	for (int i = 0; i < cap; ++i) {
		if (libres_r[i] == 1) continue;
		if (_cache_p_ht[i] < HAUTEUR_MIN_BLOQUEUR_M) continue;
		float dx = px_r[i] - ox;
		float dz = pz_r[i] - oz;
		float d2 = dx * dx + dz * dz;
		if (d2 > rayon_carre) continue;
		_bloqueurs_camera.push_back(int32_t(i));
	}
	// Etape 4/8 occlusion 2D projete camera : fonction de projection monde
	// -> pixel du buffer 2D. Rend visible=false si point derriere camera ou
	// hors du FOV.
	// FOV du buffer pousses par la coquille via definir_fov_buffer (canal
	// GD -> C++). Sans appel, valeurs par defaut du header (~115 h / 80 v).
	const float FOV_H_RAD_4 = _fov_h_rad_buffer;
	const float FOV_V_RAD_4 = _fov_v_rad_buffer;
	// Reconstruire le vecteur regard 3D depuis dir_x/dir_z (XZ normalise)
	// et pitch_y (sin(tangage)).
	float pitch_clamped = pitch_y;
	if (pitch_clamped > 1.0f) pitch_clamped = 1.0f;
	if (pitch_clamped < -1.0f) pitch_clamped = -1.0f;
	float fwd_h = std::sqrt(1.0f - pitch_clamped * pitch_clamped);
	float fwd_x = dir_x * fwd_h;
	float fwd_y = pitch_clamped;
	float fwd_z = dir_z * fwd_h;
	// Base camera : right = fwd x (0,1,0), up = right x fwd.
	float right_x = fwd_z;
	float right_y = 0.0f;
	float right_z = -fwd_x;
	float right_len = std::sqrt(right_x * right_x + right_z * right_z);
	if (right_len > 0.0001f) {
		right_x /= right_len;
		right_z /= right_len;
	}
	float up_x = right_y * fwd_z - right_z * fwd_y;
	float up_y = right_z * fwd_x - right_x * fwd_z;
	float up_z = right_x * fwd_y - right_y * fwd_x;
	auto world_to_pixel = [&](float wx, float wy, float wz,
							  int &out_px, int &out_py, float &out_depth) -> bool {
		float vx = wx - ox;
		float vy = wy - obs_y;
		float vz = wz - oz;
		float fwd_v = vx * fwd_x + vy * fwd_y + vz * fwd_z;
		constexpr float NEAR_PLANE_M = 1.0f;
		if (fwd_v <= NEAR_PLANE_M) return false;
		float right_v = vx * right_x + vy * right_y + vz * right_z;
		float up_v = vx * up_x + vy * up_y + vz * up_z;
		float alpha = std::atan2(right_v, fwd_v);
		float beta = std::atan2(up_v, fwd_v);
		int px = int((alpha + FOV_H_RAD_4 * 0.5f) / FOV_H_RAD_4 * float(BUFFER_2D_LARGEUR));
		int py = int((FOV_V_RAD_4 * 0.5f - beta) / FOV_V_RAD_4 * float(BUFFER_2D_HAUTEUR));
		out_px = px;
		out_py = py;
		out_depth = fwd_v;
		return (px >= 0 && px < BUFFER_2D_LARGEUR && py >= 0 && py < BUFFER_2D_HAUTEUR);
	};
	// Etape 5/8 : reset buffer 2D + projection des bloqueurs.
	// CYCLE ATOMIQUE (2026-09-17) : le reset ne s'execute QUE si le remplissage
	// va effectivement l'accompagner (au moins un bloqueur candidat). Sans ce
	// garde, un tick avec _bloqueurs_camera vide (aucun arbre >= 3m dans le
	// cercle, ou capacite=0) laisserait le buffer entierement a INF apres
	// reset et l'occlusion s'eteindrait sur ce tick. Preserver le contenu
	// precedent (stale mais non vide) vaut mieux qu'un buffer vide qui
	// declenche buffer_troue et desactive l'occlusion.
	if (!_bloqueurs_camera.empty()) {
		for (int p = 0; p < BUFFER_2D_LARGEUR * BUFFER_2D_HAUTEUR; ++p) {
			_buffer_2d[p] = std::numeric_limits<float>::infinity();
		}
	}
	int pixels_couverts_buffer = 0;
	for (int32_t idx : _bloqueurs_camera) {
		float bx = px_r[idx];
		float bz = pz_r[idx];
		float by_bas = py_r[idx];
		float ht = _cache_p_ht[idx];
		float hf = _cache_p_hf[idx];
		float lt = _cache_p_lt[idx];
		float lf = _cache_p_lf[idx];
		float by_haut = by_bas + ht + hf;
		constexpr float INV_SQRT2 = 0.70710678f;
		float rayon_reel = (lt > lf ? lt : lf) * 0.5f;
		float demi_l = rayon_reel * INV_SQRT2;
		int px_min = BUFFER_2D_LARGEUR;
		int px_max = -1;
		int py_min = BUFFER_2D_HAUTEUR;
		int py_max = -1;
		float depth_max_bloq = 0.0f;
		float coins_x[8] = {bx - demi_l, bx + demi_l, bx - demi_l, bx + demi_l,
							bx - demi_l, bx + demi_l, bx - demi_l, bx + demi_l};
		float coins_y[8] = {by_bas, by_bas, by_haut, by_haut,
							by_bas, by_bas, by_haut, by_haut};
		float coins_z[8] = {bz - demi_l, bz - demi_l, bz - demi_l, bz - demi_l,
							bz + demi_l, bz + demi_l, bz + demi_l, bz + demi_l};
		// Partner Y-swap : coin k et coin partner_y[k] partagent X et Z,
		// diffèrent uniquement par by_bas <-> by_haut. Sert au clip near
		// plane sur l'arete verticale (rasterizer standard : point
		// d'intersection exact, pas d'extension au bord).
		static constexpr int partner_y[8] = {2, 3, 0, 1, 6, 7, 4, 5};
		constexpr float NEAR_PLANE_M_LOCAL = 1.0f;   // miroir de world_to_pixel
		// Cible du clip : legerement au-dessus du near pour que world_to_pixel
		// (strict `<= NEAR`) accepte le point clippe.
		constexpr float NEAR_TARGET = NEAR_PLANE_M_LOCAL * 1.0001f;
		bool au_moins_un_visible = false;
		// Cache fwd_v par coin pour ne pas recalculer sur l'arete du partner.
		float f_v_coin[8];
		for (int k = 0; k < 8; ++k) {
			float vx_c = coins_x[k] - ox;
			float vy_c = coins_y[k] - obs_y;
			float vz_c = coins_z[k] - oz;
			f_v_coin[k] = vx_c * fwd_x + vy_c * fwd_y + vz_c * fwd_z;
		}
		for (int k = 0; k < 8; ++k) {
			float px_k = coins_x[k];
			float py_k = coins_y[k];
			float pz_k = coins_z[k];
			if (f_v_coin[k] <= NEAR_PLANE_M_LOCAL) {
				// Coin sous near plane -> clip sur l'arete verticale vers le
				// coin partner (meme X, meme Z, autre Y). Si le partner est
				// aussi derriere le near, toute l'arete verticale est occlue
				// par le near : ignorer ce coin.
				int q = partner_y[k];
				float f_q = f_v_coin[q];
				if (f_q <= NEAR_PLANE_M_LOCAL) continue;
				// Interpolation lineaire le long de l'arete P_q -> P_k, en
				// resolvant fwd_v(P_q + t*(P_k - P_q)) = NEAR_TARGET.
				// fwd_v est lineaire, donc t = (f_q - NEAR_TARGET)/(f_q - f_k).
				float t = (f_q - NEAR_TARGET) / (f_q - f_v_coin[k]);
				if (t < 0.0f) t = 0.0f;
				if (t > 1.0f) t = 1.0f;
				// Seul Y change entre q et k (X et Z sont identiques par la
				// topologie AABB, cf. partner_y).
				py_k = coins_y[q] + t * (coins_y[k] - coins_y[q]);
				// px_k / pz_k restent inchanges (deja = coins_x[q] / coins_z[q]).
			}
			int cpx = -1, cpy = -1;
			float cdepth = 0.0f;
			bool cvis = world_to_pixel(px_k, py_k, pz_k, cpx, cpy, cdepth);
			if (!cvis) continue;   // hors buffer lateralement
			au_moins_un_visible = true;
			if (cpx < px_min) px_min = cpx;
			if (cpx > px_max) px_max = cpx;
			if (cpy < py_min) py_min = cpy;
			if (cpy > py_max) py_max = cpy;
			if (cdepth > depth_max_bloq) depth_max_bloq = cdepth;
		}
		if (!au_moins_un_visible) continue;
		if (px_min < 0) px_min = 0;
		if (px_max >= BUFFER_2D_LARGEUR) px_max = BUFFER_2D_LARGEUR - 1;
		if (py_min < 0) py_min = 0;
		if (py_max >= BUFFER_2D_HAUTEUR) py_max = BUFFER_2D_HAUTEUR - 1;
		px_min += 1; px_max -= 1; py_min += 1; py_max -= 1;
		if (px_min > px_max || py_min > py_max) continue;
		for (int y = py_min; y <= py_max; ++y) {
			for (int x = px_min; x <= px_max; ++x) {
				int p = y * BUFFER_2D_LARGEUR + x;
				if (depth_max_bloq < _buffer_2d[p]) {
					_buffer_2d[p] = depth_max_bloq;
				}
			}
		}
	}
	for (int p = 0; p < BUFFER_2D_LARGEUR * BUFFER_2D_HAUTEUR; ++p) {
		if (!std::isinf(_buffer_2d[p])) ++pixels_couverts_buffer;
	}
	auto dans_cercle = [&](int i) -> bool {
		if (!filtre_actif) return true;
		float dx = px_r[i] - ox;
		float dy = py_r[i] - obs_y;
		float dz = pz_r[i] - oz;
		float d2 = dx * dx + dz * dz;
		if (d2 > rayon_carre) return false;
		if (!cone_actif) return true;
		if (d2 <= EPS_CONE_XZ_CARRE) return true;
		// Frustum radar : projeter (dx,dy,dz) sur les axes camera.
		// Reference : Lighthouse3D "Radar Approach - Testing Points".
		float fwd_v = dx * fwd_x + dy * fwd_y + dz * fwd_z;
		if (fwd_v <= 0.0f) return false;               // derriere la camera
		float right_v = dx * right_x + dy * right_y + dz * right_z;
		float up_v    = dx * up_x    + dy * up_y    + dz * up_z;
		// Demi-ouvertures = tan(demi-FOV). Marge MARGE_FRUSTUM pour eviter le
		// clignotement au bord quand la camera pivote entre deux ticks.
		constexpr float MARGE_FRUSTUM = 1.15f;
		float tan_h = std::tan(FOV_H_RAD_4 * 0.5f) * MARGE_FRUSTUM;
		float tan_v = std::tan(FOV_V_RAD_4 * 0.5f) * MARGE_FRUSTUM;
		if (std::abs(right_v) > tan_h * fwd_v) return false;
		if (std::abs(up_v)    > tan_v * fwd_v) return false;
		// Etape 6/8 : test occlusion par lecture buffer 2D.
		// Projette l'arbre en AABB verticale, prend depth_min et compare au
		// max des profondeurs buffer sur son rectangle (test conservatif :
		// occulte seulement si TOUT le rectangle buffer devant l'arbre est
		// plus proche que le bord le plus proche de l'arbre, ET aucun pixel
		// INF -- une trouee dans cette direction empeche l'occlusion).
		{
			float bx = px_r[i];
			float bz = pz_r[i];
			float by_bas = py_r[i];
			float ht = _cache_p_ht[i];
			float hf = _cache_p_hf[i];
			float lt = _cache_p_lt[i];
			float lf = _cache_p_lf[i];
			float by_haut = by_bas + ht + hf;
			float demi_l = (lt > lf ? lt : lf) * 0.5f;
			float coins_x[8] = {bx - demi_l, bx + demi_l, bx - demi_l, bx + demi_l,
								bx - demi_l, bx + demi_l, bx - demi_l, bx + demi_l};
			float coins_y[8] = {by_bas, by_bas, by_haut, by_haut,
								by_bas, by_bas, by_haut, by_haut};
			float coins_z[8] = {bz - demi_l, bz - demi_l, bz - demi_l, bz - demi_l,
								bz + demi_l, bz + demi_l, bz + demi_l, bz + demi_l};
			int px_min = BUFFER_2D_LARGEUR;
			int px_max = -1;
			int py_min = BUFFER_2D_HAUTEUR;
			int py_max = -1;
			float depth_min_arbre = std::numeric_limits<float>::infinity();
			bool au_moins_un_visible_arbre = false;
			for (int k = 0; k < 8; ++k) {
				int cpx = -1, cpy = -1;
				float cdepth = 0.0f;
				bool cvis = world_to_pixel(coins_x[k], coins_y[k], coins_z[k], cpx, cpy, cdepth);
				if (!cvis) continue;
				au_moins_un_visible_arbre = true;
				if (cpx < px_min) px_min = cpx;
				if (cpx > px_max) px_max = cpx;
				if (cpy < py_min) py_min = cpy;
				if (cpy > py_max) py_max = cpy;
				if (cdepth < depth_min_arbre) depth_min_arbre = cdepth;
			}
			if (au_moins_un_visible_arbre) {
				if (px_min < 0) px_min = 0;
				if (px_max >= BUFFER_2D_LARGEUR) px_max = BUFFER_2D_LARGEUR - 1;
				if (py_min < 0) py_min = 0;
				if (py_max >= BUFFER_2D_HAUTEUR) py_max = BUFFER_2D_HAUTEUR - 1;
				// Test conservatif Intel MOC : arbre occulte SEULEMENT si son
				// bord le plus proche est plus loin que le MAX du buffer sur
				// TOUT le rectangle. Un pixel INF (aucun bloqueur) -> pas
				// d'occlusion (l'arbre est visible dans cette direction).
				// Seuil de couverture : occulter si la fraction de pixels vides
				// (aucun bloqueur -> INF) reste sous FRACTION_TROUS_MAX. Depart
				// TRES strict a 0.05 (5%), a diminuer au fur et a mesure.
				constexpr float FRACTION_TROUS_MAX = 0.05f;
				float depth_max_buffer = 0.0f;
				int pixels_total = 0;
				int pixels_vides = 0;
				for (int y = py_min; y <= py_max; ++y) {
					for (int x = px_min; x <= px_max; ++x) {
						int p = y * BUFFER_2D_LARGEUR + x;
						float dp = _buffer_2d[p];
						++pixels_total;
						if (std::isinf(dp)) { ++pixels_vides; continue; }
						if (dp > depth_max_buffer) depth_max_buffer = dp;
					}
				}
				bool trop_de_trous = (pixels_total == 0)
					|| (float(pixels_vides) > FRACTION_TROUS_MAX * float(pixels_total));
				if (!trop_de_trous && depth_min_arbre > depth_max_buffer) {
					return false;
				}
			}
		}
		return true;
	};
	int pop = 0;
	for (int i = 0; i < cap; ++i) {
		if (libres_r[i] == 0 && dans_cercle(i)) ++pop;
	}
	PackedFloat32Array pb_t;
	PackedFloat32Array pb_f;
	PackedInt32Array srpd;
	pb_t.resize(pop * 16);
	pb_f.resize(pop * 16);
	srpd.resize(cap);
	int32_t *srpd_w = srpd.ptrw();
	float *pb_t_w = pb_t.ptrw();
	float *pb_f_w = pb_f.ptrw();
	int rank = 0;
	for (int i = 0; i < cap; ++i) {
		if (libres_r[i] == 1 || !dans_cercle(i)) {
			srpd_w[i] = -1;
			continue;
		}
		srpd_w[i] = int32_t(rank);
		int src = i * 16;
		int dst = rank * 16;
		std::memcpy(pb_t_w + dst, bt + src, 16 * sizeof(float));
		std::memcpy(pb_f_w + dst, bf + src, 16 * sizeof(float));
		++rank;
	}
	out["pop"] = pop;
	out["buffer_tronc"] = pb_t;
	out["buffer_feuillage"] = pb_f;
	out["slot_rendu_pour_data"] = srpd;

	// BUFFER TRONC CERCLE SEUL (prompt 2026-09-15) pour l'occludeur.
	// L'occludeur doit couvrir tous les troncs du cercle de rendu, pas
	// seulement ceux dans le cone : sans ca, tourner la camera rebati
	// l'occludeur sur un autre sous-ensemble et l'occlusion saute. Filtre
	// ici : d² <= rayon_carre uniquement (ni cone, ni occlusion CPU).
	// Layout identique a pb_t (16 floats/instance, TRANSFORM_3D + color).
	int pop_cercle = 0;
	if (filtre_actif) {
		for (int i = 0; i < cap; ++i) {
			if (libres_r[i] == 1) continue;
			float dx = px_r[i] - ox;
			float dz = pz_r[i] - oz;
			float d2 = dx * dx + dz * dz;
			if (d2 <= rayon_carre) ++pop_cercle;
		}
	} else {
		for (int i = 0; i < cap; ++i) {
			if (libres_r[i] == 0) ++pop_cercle;
		}
	}
	PackedFloat32Array pb_t_cercle;
	PackedFloat32Array pb_f_cercle;
	pb_t_cercle.resize(pop_cercle * 16);
	pb_f_cercle.resize(pop_cercle * 16);
	float *pb_t_cercle_w = pb_t_cercle.ptrw();
	float *pb_f_cercle_w = pb_f_cercle.ptrw();
	int rank_cercle = 0;
	for (int i = 0; i < cap; ++i) {
		if (libres_r[i] == 1) continue;
		if (filtre_actif) {
			float dx = px_r[i] - ox;
			float dz = pz_r[i] - oz;
			float d2 = dx * dx + dz * dz;
			if (d2 > rayon_carre) continue;
		}
		int src = i * 16;
		int dst = rank_cercle * 16;
		std::memcpy(pb_t_cercle_w + dst, bt + src, 16 * sizeof(float));
		std::memcpy(pb_f_cercle_w + dst, bf + src, 16 * sizeof(float));
		++rank_cercle;
	}
	out["pop_cercle"] = pop_cercle;
	out["buffer_tronc_cercle"] = pb_t_cercle;
	// Meme filtrage cercle, meme layout, mais depuis le buffer feuillage :
	// l'occludeur cote coquille bati des quads en croix avec ces donnees,
	// comme pour le tronc. Le feuillage devient bloqueur au meme titre.
	out["buffer_feuillage_cercle"] = pb_f_cercle;
	out["cone_actif"] = cone_actif;
	out["nb_bloqueurs_camera"] = int(_bloqueurs_camera.size());
	out["buffer_2d_largeur"] = BUFFER_2D_LARGEUR;
	out["buffer_2d_hauteur"] = BUFFER_2D_HAUTEUR;
	out["cam_hauteur"] = int(obs_y * 10.0f);
	out["cam_pitch"] = int(pitch_y * 100.0f);
	// Test projection etape 4 : premier arbre vivant.
	int test_px = -1, test_py = -1;
	float test_depth = 0.0f;
	int test_visible = 0;
	for (int i = 0; i < cap; ++i) {
		if (libres_r[i] == 1) continue;
		int tpx = -1, tpy = -1;
		float tdepth = 0.0f;
		bool tvis = world_to_pixel(px_r[i], py_r[i], pz_r[i], tpx, tpy, tdepth);
		test_px = tpx;
		test_py = tpy;
		test_depth = tdepth;
		test_visible = tvis ? 1 : 0;
		break;
	}
	out["test_px"] = test_px;
	out["test_py"] = test_py;
	out["test_depth"] = int(test_depth);
	out["test_visible"] = test_visible;
	out["pixels_couverts_buffer_2d"] = pixels_couverts_buffer;
	// Instrumentation diagnostic buf2D=0 : compteur monotone incremente ici
	// (une fois par remplissage complet du buffer 2D). Si le compteur ne
	// bouge pas entre deux prints, mettre_a_jour_buffers_rendu n'a pas ete
	// appele (gate coquille) et pixels_couverts_buffer_2d = 0 est attendu.
	++_nb_remplissages_buffer;
	out["nb_remplissages_buffer"] = int64_t(_nb_remplissages_buffer);
	// Instrumentation etape 6/8 : compter les arbres occultes par le buffer 2D.
	int occultes_2d = 0;
	int self_occ = 0;             // bloqueurs (ht >= 3m) qui sont occultes
	int faux_pos_proches = 0;     // arbres a moins de 20 m de la camera occultes
	// Dump cible : premier bloqueur adulte occulte du tick.
	int dump_i = -1;
	int dump_pxi_min = 0, dump_pxi_max = 0, dump_pyi_min = 0, dump_pyi_max = 0;
	int dump_depth_arbre = 0;
	int dump_depth_max_buffer = 0;
	int dump_depth_max_buffer_zone = 0;
	for (int i = 0; i < cap; ++i) {
		if (libres_r[i] == 1) continue;
		float bx = px_r[i], bz = pz_r[i], by_bas = py_r[i];
		float ht = _cache_p_ht[i], hf = _cache_p_hf[i];
		float lt = _cache_p_lt[i], lf = _cache_p_lf[i];
		float by_haut = by_bas + ht + hf;
		float demi_l = (lt > lf ? lt : lf) * 0.5f;
		float coins_x[8] = {bx - demi_l, bx + demi_l, bx - demi_l, bx + demi_l,
							bx - demi_l, bx + demi_l, bx - demi_l, bx + demi_l};
		float coins_y[8] = {by_bas, by_bas, by_haut, by_haut,
							by_bas, by_bas, by_haut, by_haut};
		float coins_z[8] = {bz - demi_l, bz - demi_l, bz - demi_l, bz - demi_l,
							bz + demi_l, bz + demi_l, bz + demi_l, bz + demi_l};
		int pxi_min = BUFFER_2D_LARGEUR, pxi_max = -1;
		int pyi_min = BUFFER_2D_HAUTEUR, pyi_max = -1;
		float depth_min_a = std::numeric_limits<float>::infinity();
		bool visi = false;
		for (int k = 0; k < 8; ++k) {
			int cpx = -1, cpy = -1;
			float cdepth = 0.0f;
			if (!world_to_pixel(coins_x[k], coins_y[k], coins_z[k], cpx, cpy, cdepth)) continue;
			visi = true;
			if (cpx < pxi_min) pxi_min = cpx;
			if (cpx > pxi_max) pxi_max = cpx;
			if (cpy < pyi_min) pyi_min = cpy;
			if (cpy > pyi_max) pyi_max = cpy;
			if (cdepth < depth_min_a) depth_min_a = cdepth;
		}
		if (!visi) continue;
		if (pxi_min < 0) pxi_min = 0;
		if (pxi_max >= BUFFER_2D_LARGEUR) pxi_max = BUFFER_2D_LARGEUR - 1;
		if (pyi_min < 0) pyi_min = 0;
		if (pyi_max >= BUFFER_2D_HAUTEUR) pyi_max = BUFFER_2D_HAUTEUR - 1;
		// Seuil de couverture (miroir du test principal dans dans_cercle).
		constexpr float FRACTION_TROUS_MAX_INSTR = 0.05f;
		float dmax_buf = 0.0f;
		int pxls_total = 0;
		int pxls_vides = 0;
		for (int y = pyi_min; y <= pyi_max; ++y) {
			for (int x = pxi_min; x <= pxi_max; ++x) {
				int p = y * BUFFER_2D_LARGEUR + x;
				float dp = _buffer_2d[p];
				++pxls_total;
				if (std::isinf(dp)) { ++pxls_vides; continue; }
				if (dp > dmax_buf) dmax_buf = dp;
			}
		}
		bool troue = (pxls_total == 0)
			|| (float(pxls_vides) > FRACTION_TROUS_MAX_INSTR * float(pxls_total));
		if (!troue && depth_min_a > dmax_buf) {
			++occultes_2d;
			if (_cache_p_ht[i] >= 3.0f) ++self_occ;
			float ddx = px_r[i] - ox;
			float ddz = pz_r[i] - oz;
			if (ddx * ddx + ddz * ddz < 400.0f) ++faux_pos_proches; // < 20 m
			if (dump_i == -1 && _cache_p_ht[i] >= 3.0f) {
				dump_i = i;
				dump_pxi_min = pxi_min;
				dump_pxi_max = pxi_max;
				dump_pyi_min = pyi_min;
				dump_pyi_max = pyi_max;
				dump_depth_arbre = int(depth_min_a);
				dump_depth_max_buffer = 0; // non calcule dans la variante MAX-buffer
				dump_depth_max_buffer_zone = int(dmax_buf);
			}
		}
	}
	out["occultes_2d"] = occultes_2d;
	out["self_occ"] = self_occ;
	out["faux_pos_proches"] = faux_pos_proches;
	// Histogramme buffer 2D : min, mediane, max des pixels non-INF.
	float buf2d_min = std::numeric_limits<float>::infinity();
	float buf2d_max = 0.0f;
	std::vector<float> buf2d_vals;
	buf2d_vals.reserve(size_t(BUFFER_2D_LARGEUR * BUFFER_2D_HAUTEUR));
	for (int p = 0; p < BUFFER_2D_LARGEUR * BUFFER_2D_HAUTEUR; ++p) {
		float v = _buffer_2d[p];
		if (!std::isinf(v)) {
			if (v < buf2d_min) buf2d_min = v;
			if (v > buf2d_max) buf2d_max = v;
			buf2d_vals.push_back(v);
		}
	}
	float buf2d_med = 0.0f;
	if (!buf2d_vals.empty()) {
		std::sort(buf2d_vals.begin(), buf2d_vals.end());
		buf2d_med = buf2d_vals[buf2d_vals.size() / 2];
	}
	if (std::isinf(buf2d_min)) buf2d_min = 0.0f;
	out["buf2d_min"] = int(buf2d_min);
	out["buf2d_med"] = int(buf2d_med);
	out["buf2d_max"] = int(buf2d_max);
	out["dump_i"] = dump_i;
	out["dump_rect_x"] = dump_pxi_min * 100 + dump_pxi_max;
	out["dump_rect_y"] = dump_pyi_min * 100 + dump_pyi_max;
	out["dump_d_arbre"] = dump_depth_arbre;
	out["dump_d_min_buf"] = dump_depth_max_buffer;
	out["dump_d_max_buf"] = dump_depth_max_buffer_zone;
	return out;
}

} // namespace godot
