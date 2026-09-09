#include "index_spatial.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

using namespace godot;

namespace {
// Entree "voisin retenu dans le disque" pour perception_lot -- id + delta et
// distance AU CARRE (sqrt differe a l'extraction argmin). Le rassemblement
// ne fait AUCUN sqrt : il pousse d2 tel que calcule par le filtre distance.
// L'argmin de la passe occlusion compare d2 (monotone equivalent). Le sqrt
// n'est paye qu'a l'instant ou le voisin est extrait par argmin -- les
// voisins jamais extraits (arret sans perte des secteurs) n'en paient pas.
// Les seuls corps qui peuvent occulter un voisin retenu sont eux-memes dans
// cette liste : un obstacle plus loin ne coupe pas le segment percepteur ->
// voisin (t dans ]0,1[ le rejette).
struct VoisinVue {
	int32_t id;
	float dx; // pos_i.x - pos_k.x
	float dz; // pos_i.z - pos_k.z
	float d2; // distance horizontale AU CARRE (sqrt differe a l'extraction)
};
} // namespace anonyme

void IndexSpatial::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurer", "nombre_ids"), &IndexSpatial::configurer);
	ClassDB::bind_method(D_METHOD("ouvrir_niveau", "exposant"), &IndexSpatial::ouvrir_niveau);
	ClassDB::bind_method(D_METHOD("ouvrir_niveau_planaire", "exposant"), &IndexSpatial::ouvrir_niveau_planaire);
	ClassDB::bind_method(D_METHOD("deplacer_lot", "positions"), &IndexSpatial::deplacer_lot);
	ClassDB::bind_method(D_METHOD("cases_pour_niveau", "exposant"), &IndexSpatial::cases_pour_niveau);
	ClassDB::bind_method(D_METHOD("perception_lot", "positions", "orientations", "opacites", "rayon", "cos_moitie_angle", "largeur", "seuil_facteur"), &IndexSpatial::perception_lot);
	ClassDB::bind_method(D_METHOD("separation_lot", "positions", "ids", "offsets", "rayon"), &IndexSpatial::separation_lot);
	ClassDB::bind_method(D_METHOD("derniers_chronos_vue"), &IndexSpatial::derniers_chronos_vue);
	ClassDB::bind_method(D_METHOD("derniers_compteurs_vue"), &IndexSpatial::derniers_compteurs_vue);
}

IndexSpatial::IndexSpatial() {}
IndexSpatial::~IndexSpatial() {}

void IndexSpatial::configurer(int nombre_ids) {
	_nombre_ids = nombre_ids;
	for (Niveau &niveau : _niveaux) {
		niveau.case_de.assign(_nombre_ids, Vector3i(0, 0, 0));
		niveau.idx_dans_case.assign(_nombre_ids, 0);
		niveau.presence.assign(_nombre_ids, 0);
	}
}

void IndexSpatial::ouvrir_niveau(int exposant) {
	for (const Niveau &niveau : _niveaux) {
		if (niveau.exposant == exposant) {
			return;
		}
	}
	Niveau niveau;
	niveau.exposant = exposant;
	niveau.planaire = false;
	float arete = std::pow(2.0f, (float)exposant);
	niveau.inv_arete = 1.0f / arete;
	if (_nombre_ids > 0) {
		niveau.case_de.assign(_nombre_ids, Vector3i(0, 0, 0));
		niveau.idx_dans_case.assign(_nombre_ids, 0);
		niveau.presence.assign(_nombre_ids, 0);
	}
	_niveaux.push_back(std::move(niveau));
}

void IndexSpatial::ouvrir_niveau_planaire(int exposant) {
	for (const Niveau &niveau : _niveaux) {
		if (niveau.exposant == exposant) {
			return;
		}
	}
	Niveau niveau;
	niveau.exposant = exposant;
	niveau.planaire = true;
	float arete = std::pow(2.0f, (float)exposant);
	niveau.inv_arete = 1.0f / arete;
	if (_nombre_ids > 0) {
		niveau.case_de.assign(_nombre_ids, Vector3i(0, 0, 0));
		niveau.idx_dans_case.assign(_nombre_ids, 0);
		niveau.presence.assign(_nombre_ids, 0);
	}
	_niveaux.push_back(std::move(niveau));
}

void IndexSpatial::deplacer_lot(const PackedVector3Array &positions) {
	int count = positions.size();
	if (count <= 0 || _niveaux.empty()) {
		return;
	}
	const Vector3 *pos_r = positions.ptr();
	for (Niveau &niveau : _niveaux) {
		if ((int)niveau.presence.size() < count) {
			// Pool agrandi apres configurer : etendre les vector du niveau.
			niveau.case_de.resize(count, Vector3i(0, 0, 0));
			niveau.idx_dans_case.resize(count, 0);
			niveau.presence.resize(count, 0);
		}
		const float inv_a = niveau.inv_arete;
		const bool planaire = niveau.planaire;
		for (int32_t id = 0; id < count; id++) {
			const Vector3 &p = pos_r[id];
			// PLANAIRE : la clef de case ecrase Y a 0 (voir Niveau::planaire).
			// Toutes les unites de la meme colonne (fx, fz) tombent dans la
			// meme entree unordered_map, quelle que soit leur altitude --
			// lecture de separation_lot en O(cases planaires) sans balayer Y.
			Vector3i visee(
					(int32_t)std::floor(p.x * inv_a),
					planaire ? 0 : (int32_t)std::floor(p.y * inv_a),
					(int32_t)std::floor(p.z * inv_a));
			if (niveau.presence[id]) {
				const Vector3i actuelle = niveau.case_de[id];
				if (actuelle == visee) {
					continue;
				}
				// Retrait swap-remove O(1) de l'ancienne case.
				auto it_a = niveau.cases.find(actuelle);
				if (it_a != niveau.cases.end()) {
					std::vector<int32_t> &contenu_a = it_a->second;
					int idx_a = niveau.idx_dans_case[id];
					int dernier = (int)contenu_a.size() - 1;
					if (idx_a != dernier) {
						int32_t autre = contenu_a[dernier];
						contenu_a[idx_a] = autre;
						niveau.idx_dans_case[autre] = idx_a;
					}
					contenu_a.pop_back();
					if (contenu_a.empty()) {
						niveau.cases.erase(it_a);
					}
				}
			}
			// Ajout dans la nouvelle case.
			std::vector<int32_t> &contenu_n = niveau.cases[visee];
			niveau.idx_dans_case[id] = (int32_t)contenu_n.size();
			contenu_n.push_back(id);
			niveau.case_de[id] = visee;
			niveau.presence[id] = 1;
		}
	}
}

Dictionary IndexSpatial::perception_lot(
		const PackedVector3Array &positions,
		const PackedVector3Array &orientations,
		const PackedFloat32Array &opacites,
		float rayon,
		float cos_moitie_angle,
		float largeur,
		float seuil_facteur) const {
	Dictionary out;
	PackedInt32Array offsets;
	PackedInt32Array ids_plat;
	int count = positions.size();
	offsets.resize(count + 1);
	int32_t *off_w = offsets.ptrw();
	for (int i = 0; i <= count; i++) {
		off_w[i] = 0;
	}
	// Reset des sous-chronos temporaires (voir en-tete). La somme des quatre
	// couvre tout le corps de perception_lot.
	_us_collecte = 0;
	_us_filtre = 0;
	_us_tri = 0;
	_us_occ_sep = 0;
	if (count <= 0 || _niveaux.empty() || rayon <= 0.0f) {
		out["ids"] = ids_plat;
		out["offsets"] = offsets;
		return out;
	}
	if (orientations.size() != count || opacites.size() != count) {
		ERR_PRINT("IndexSpatial::perception_lot : orientations/opacites de taille differente de positions. Retour a zero.");
		out["ids"] = ids_plat;
		out["offsets"] = offsets;
		return out;
	}
	// CHOIX DU NIVEAU PLANAIRE, meme regle qu'auparavant : plus petit exposant
	// planaire dont l'arete est >= rayon, sinon plus grande arete planaire en
	// repli, sinon push_error + zero (contrat un seul chemin).
	const Niveau *choisi = nullptr;
	float meilleure_arete = 0.0f;
	for (const Niveau &n : _niveaux) {
		if (!n.planaire) {
			continue;
		}
		float arete = std::pow(2.0f, (float)n.exposant);
		if (arete >= rayon) {
			if (choisi == nullptr || arete < meilleure_arete) {
				choisi = &n;
				meilleure_arete = arete;
			}
		}
	}
	if (choisi == nullptr) {
		for (const Niveau &n : _niveaux) {
			if (!n.planaire) {
				continue;
			}
			float arete = std::pow(2.0f, (float)n.exposant);
			if (choisi == nullptr || arete > meilleure_arete) {
				choisi = &n;
				meilleure_arete = arete;
			}
		}
	}
	if (choisi == nullptr) {
		ERR_PRINT("IndexSpatial::perception_lot : aucun niveau PLANAIRE ouvert -- appeler ouvrir_niveau_planaire(exposant) avant. Retour a zero.");
		out["ids"] = ids_plat;
		out["offsets"] = offsets;
		return out;
	}
	const Niveau &niveau = *choisi;
	const float inv_a = niveau.inv_arete;
	const Vector3 *pos_r = positions.ptr();
	const Vector3 *orient_r = orientations.ptr();
	const float rayon2 = rayon * rayon;
	// `opacites` et `seuil_facteur` ne sont plus consommes par le modele
	// visuel (corps traversee = opaque binaire, pas d'attenuation). Signature
	// preservee pour compat -- restent dans occlusion.gd pour son/odeur.
	(void)opacites;
	(void)seuil_facteur;
	const float rayon_corps = 0.5f * largeur;
	const float r_corps2 = rayon_corps * rayon_corps;

	// PERCEPTION MATERIALISEE : `vus_par_id` accumule pendant la passe 2 les
	// ids vus par chaque agent, puis serialise en `ids_plat` + `offsets` a la
	// fin. thread_local pour amortir l'allocation entre frames.
	static thread_local std::vector<std::vector<int32_t>> vus_par_id;
	if ((int)vus_par_id.size() < count) {
		vus_par_id.resize((size_t)count);
	}
	for (int i = 0; i < count; i++) {
		vus_par_id[(size_t)i].clear();
	}
	// LISTE DES VOISINS DANS LE RAYON, per-agent. thread_local : capacite
	// gardee entre agents et entre frames, seul `clear()` est paye a chaque
	// nouvel agent.
	static thread_local std::vector<VoisinVue> dans_rayon;
	// Compteurs TEMPORAIRES : voisins bruts (rayon), voisins VUS (rayon + cone
	// + occlusion), unites traitees.
	_vue_voisins_total = 0;
	_vue_unites_total = 0;
	_vue_vus_total = 0;

	// PRE-FILTRE CONE ELARGI (avant sqrt dans la collecte per-agent).
	// demi_cone_elargi = demi_cone_strict + atan2(largeur, rayon). La marge
	// atan2(largeur, rayon) garantit qu'aucun bloqueur legitime n'est perdu :
	// un occulteur de taille `largeur` a distance `rayon` reste dans le cone
	// elargi meme s'il est hors cone strict. Le verdict final (cone strict +
	// occlusion) reste en passe 2.
	float cos_moitie_elargi = cos_moitie_angle;
	if (cos_moitie_angle > -1.0f + 1e-6f) {
		float demi_angle = std::acos(cos_moitie_angle);
		float extra = std::atan2(largeur, rayon);
		float elargi = demi_angle + extra;
		if (elargi >= 3.14159265f) {
			cos_moitie_elargi = -1.0f;
		} else {
			cos_moitie_elargi = std::cos(elargi);
		}
	}
	const float cos_elargi_sq = cos_moitie_elargi * cos_moitie_elargi;
	const bool cos_elargi_positif = (cos_moitie_elargi >= 0.0f);
	const bool cone_ferme = (cos_moitie_elargi > -1.0f + 1e-6f);

	// PORT DE scripts/monde.gd::choses_dans_rayon EN LOT. Chaque agent lit son
	// disque depuis SA position -- basse/haute en cases derives de `position +/-
	// rayon`, iteration des cases du bounding box, filtre `distance^2 <= rayon^2`
	// par candidat. Une frontiere GDScript->C++ par frame (perception_lot rend
	// {ids, offsets} pour tous les agents), pas d'appel GDScript par agent.
	for (int i = 0; i < count; i++) {
		const int32_t id = i;
		const Vector3 &p_i = pos_r[id];
		const Vector3 &orient_i = orient_r[id];

		// BASSE / HAUTE en cases, derives de la position de l'agent : cases
		// touchees par le disque de rayon `rayon` centre sur p_i. Meme geste
		// que _case_pour(position - rayon) et _case_pour(position + rayon) dans
		// scripts/monde.gd::choses_dans_rayon.
		const int cx_min = (int)std::floor((p_i.x - rayon) * inv_a);
		const int cx_max = (int)std::floor((p_i.x + rayon) * inv_a);
		const int cz_min = (int)std::floor((p_i.z - rayon) * inv_a);
		const int cz_max = (int)std::floor((p_i.z + rayon) * inv_a);

		// COLLECTE : itere les cases du bounding box du disque, filtre
		// `d2 < rayon2` (test candidat identique a monde.gd:_collecter) puis
		// pre-filtre cone elargi sans sqrt. Le sqrt n'est paye que pour les
		// voisins qui peuvent etre vus OU servir d'occulteur en passe 2.
		auto t_col_debut = std::chrono::steady_clock::now();
		dans_rayon.clear();
		for (int cx = cx_min; cx <= cx_max; cx++) {
			for (int cz = cz_min; cz <= cz_max; cz++) {
				Vector3i cle(cx, 0, cz);
				auto it = niveau.cases.find(cle);
				if (it == niveau.cases.end()) {
					continue;
				}
				const std::vector<int32_t> &unites_cle = it->second;
				const int nu = (int)unites_cle.size();
				for (int jj = 0; jj < nu; jj++) {
					int32_t k_id = unites_cle[jj];
					if (k_id == id) {
						continue;  // exclure soi
					}
					const Vector3 &p_k = pos_r[k_id];
					float dx = p_i.x - p_k.x;
					float dz = p_i.z - p_k.z;
					float d2 = dx * dx + dz * dz;
					if (d2 >= rayon2) {
						continue;
					}
					// PRE-FILTRE CONE ELARGI (sans sqrt). Test dot_vers >=
					// cos_moitie_elargi * d. dot_vers = orient . (percepteur->
					// voisin) = -(orient.x * dx + orient.z * dz).
					// Cas cos_elargi_positif : rejeter si dot <= 0 (voisin
					// derriere) OU dot^2 < cos_elargi_sq * d2 (hors cone).
					// Cas cos_elargi < 0 (cone > 180 deg) : accepte tout.
					if (cone_ferme && cos_elargi_positif) {
						float dot_vers = -(orient_i.x * dx + orient_i.z * dz);
						if (dot_vers <= 0.0f) {
							continue;
						}
						if (dot_vers * dot_vers < cos_elargi_sq * d2) {
							continue;
						}
					}
					// Pas de sqrt ici : `d` differe a l'extraction argmin
					// (les voisins skippes par l'arret sans perte n'en paient pas).
					VoisinVue vv;
					vv.id = k_id;
					vv.dx = dx;
					vv.dz = dz;
					vv.d2 = d2;
					dans_rayon.push_back(vv);
				}
			}
		}
		_us_collecte += std::chrono::duration_cast<std::chrono::microseconds>(
				std::chrono::steady_clock::now() - t_col_debut).count();

		// Compteurs diagnostic : accumule taille de dans_rayon (candidats
		// apres filtre distance + cone elargi) et compte l'unite.
		_vue_voisins_total += (int64_t)dans_rayon.size();
		_vue_unites_total += 1;

		{
			const Vector3 &orient = orient_i;
			std::vector<VoisinVue> &liste = dans_rayon;

			// MODULE OCCLUSION VISUELLE CORPS-TRAVERSE + SEPARATION.
			// Modele inchange : la vue s'arrete au premier corps opaque, un
			// voisin J est CACHE si le segment percepteur->J traverse le
			// VOLUME (disque horizontal rayon = largeur/2) d'un corps K PLUS
			// PROCHE. Bloqueurs hors cone bouchent quand meme sans contribuer
			// a la separation. Verdict final : segment-disque exact (bit-a-bit
			// identique).
			//
			// SELECTION INCREMENTALE DU PLUS PROCHE (pas de tas complet).
			// Un simple argmin lineaire sur liste[0..reste-1] a chaque tour +
			// swap-remove en fin. Cout par extraction O(reste), cout total
			// O(K * N) avec K = voisins parcourus avant l'arret d'occlusion
			// (petit a densite forte, ~1-2). Pas de passe O(N) de construction
			// de tas payee AVANT de savoir qu'on s'arretera a K=2. Chrono `tri`
			// mesure les balayages lineaires. Pire cas K=N (peu d'occlusion) :
			// O(N^2), acceptable pour cette version simple.
			//
			// PRESELECTION ANGULAIRE (heritee, sans perte) : `cos_num >=
			// base_k * d_j` avec `base_k = sqrt(d2_k - r_corps2)` -- contraposee
			// exacte du critere segment-disque. Les rares bloqueurs qui passent
			// la preselection sont re-verifies par le segment-disque exact.
			//
			// ARRET SANS PERTE quand le CONE de vue est bouche : l'union des
			// secteurs angulaires clampes au cone (par bloqueur ajoute) est
			// tenue trie. Des qu'elle recouvre [-demi_cone, +demi_cone], tous
			// les voisins restants dans le cone ont leur angle dans un secteur
			// ferme -> ils sont caches (le segment-disque tranche de toute
			// facon par equivalence). Les voisins hors cone restants ne
			// contribuent pas a la separation et deviennent inutiles comme
			// bloqueurs supplementaires (les cibles dans le cone sont deja
			// couvertes). L'arret est prouvablement sans perte.
			auto t_occ_debut = std::chrono::steady_clock::now();
			std::vector<int32_t> &vus_ids_i = vus_par_id[(size_t)id];
			// Bloqueurs : copies des VoisinVue (la liste change avec le
			// swap-remove, on ne peut plus indexer). thread_local pour amortir.
			struct Bloqueur {
				VoisinVue v;
				float base_k;
			};
			static thread_local std::vector<Bloqueur> bloqueurs;
			bloqueurs.clear();
			// Secteurs angulaires fermes, TOUS clampes a [-demi_cone, +demi_cone].
			// Tri par borne min, fusion des chevauchants. Cone bouche quand
			// l'union = un seul intervalle qui couvre [-demi_cone, +demi_cone].
			static thread_local std::vector<std::pair<float, float>> secteurs;
			secteurs.clear();
			// Angle de l'orientation de l'unite + demi-cone (en rad). Precalc.
			const float angle_orient = std::atan2(orient.z, orient.x);
			float cos_clamp = cos_moitie_angle;
			if (cos_clamp < -1.0f) cos_clamp = -1.0f;
			if (cos_clamp > 1.0f) cos_clamp = 1.0f;
			const float demi_cone = std::acos(cos_clamp);
			const float PI_F = 3.14159265f;
			const float TAU_F = 6.2831853f;
			int reste = (int)liste.size();
			while (reste > 0) {
				// Extraire le plus proche : argmin lineaire sur [0..reste-1] +
				// swap-remove en fin. Comparaison sur d2 (monotone equivalente
				// a d, aucune sqrt payee ici). Le chrono `tri` couvre ce balayage.
				auto t_sel_debut = std::chrono::steady_clock::now();
				int min_idx = 0;
				float min_d2 = liste[0].d2;
				for (int s = 1; s < reste; s++) {
					if (liste[(size_t)s].d2 < min_d2) {
						min_d2 = liste[(size_t)s].d2;
						min_idx = s;
					}
				}
				if (min_idx != reste - 1) {
					std::swap(liste[(size_t)min_idx], liste[(size_t)(reste - 1)]);
				}
				reste--;
				const VoisinVue vj = liste[(size_t)reste];
				_us_tri += std::chrono::duration_cast<std::chrono::microseconds>(
						std::chrono::steady_clock::now() - t_sel_debut).count();
				const float d2_j = vj.d2;
				// SQRT DIFFERE : d n'est calcule qu'ici, une fois pour ce voisin
				// (les voisins jamais extraits par l'argmin ne le paient jamais).
				const float d_j = std::sqrt(d2_j);
				// Test cache par un bloqueur plus proche (preselection +
				// segment-disque exact sur les candidats).
				bool cache = false;
				const int nb = (int)bloqueurs.size();
				for (int b = 0; b < nb; b++) {
					const Bloqueur &bc = bloqueurs[(size_t)b];
					const VoisinVue &vk = bc.v;
					float cos_num = vj.dx * vk.dx + vj.dz * vk.dz;
					if (cos_num <= 0.0f) {
						continue;
					}
					if (cos_num < bc.base_k * d_j) {
						continue;
					}
					float t_proj = cos_num / d2_j;
					if (t_proj <= 0.0f || t_proj >= 1.0f) {
						continue;
					}
					float lat_x = -vk.dx - t_proj * (-vj.dx);
					float lat_z = -vk.dz - t_proj * (-vj.dz);
					float lat2 = lat_x * lat_x + lat_z * lat_z;
					if (lat2 <= r_corps2) {
						cache = true;
						break;
					}
				}
				if (cache) {
					continue;
				}
				// J vu -- devient bloqueur pour les voisins suivants.
				Bloqueur bc;
				bc.v = vj;
				bc.base_k = std::sqrt(std::max(d2_j - r_corps2, 0.0f));
				bloqueurs.push_back(bc);
				// Mise a jour de l'union des secteurs (clampes au cone).
				float angle_v = std::atan2(-vj.dz, -vj.dx) - angle_orient;
				while (angle_v > PI_F) angle_v -= TAU_F;
				while (angle_v < -PI_F) angle_v += TAU_F;
				float sin_arg = rayon_corps / d_j;
				if (sin_arg > 1.0f) sin_arg = 1.0f;
				float demi_v = std::asin(sin_arg);
				// Un secteur [angle - demi, angle + demi] est eclate en deux si
				// il deborde de [-PI, PI]. Chaque morceau est clampe a
				// [-demi_cone, +demi_cone] puis fusionne dans `secteurs`.
				float morceaux[2][2];
				int nb_morceaux = 0;
				float lo_v = angle_v - demi_v;
				float hi_v = angle_v + demi_v;
				if (hi_v > PI_F) {
					morceaux[nb_morceaux][0] = lo_v; morceaux[nb_morceaux][1] = PI_F; nb_morceaux++;
					morceaux[nb_morceaux][0] = -PI_F; morceaux[nb_morceaux][1] = hi_v - TAU_F; nb_morceaux++;
				} else if (lo_v < -PI_F) {
					morceaux[nb_morceaux][0] = -PI_F; morceaux[nb_morceaux][1] = hi_v; nb_morceaux++;
					morceaux[nb_morceaux][0] = lo_v + TAU_F; morceaux[nb_morceaux][1] = PI_F; nb_morceaux++;
				} else {
					morceaux[nb_morceaux][0] = lo_v; morceaux[nb_morceaux][1] = hi_v; nb_morceaux++;
				}
				for (int m = 0; m < nb_morceaux; m++) {
					float lo = morceaux[m][0];
					float hi = morceaux[m][1];
					// Clamp au cone.
					if (hi < -demi_cone || lo > demi_cone) continue;
					if (lo < -demi_cone) lo = -demi_cone;
					if (hi > demi_cone) hi = demi_cone;
					// Fusion avec les chevauchants existants.
					auto it = secteurs.begin();
					while (it != secteurs.end()) {
						if (it->second < lo || it->first > hi) {
							++it;
						} else {
							if (it->first < lo) lo = it->first;
							if (it->second > hi) hi = it->second;
							it = secteurs.erase(it);
						}
					}
					// Insertion triee par borne min.
					auto pos = secteurs.begin();
					while (pos != secteurs.end() && pos->first < lo) ++pos;
					secteurs.insert(pos, std::make_pair(lo, hi));
				}
				// Contribution PERCEPTION si J dans le cone strict : ajouter
				// son id a la liste des vus de l'agent. La separation (et tout
				// autre consommateur) lira cette liste hors de perception_lot.
				float dot_vers_voisin = -(orient.x * vj.dx + orient.z * vj.dz);
				if (dot_vers_voisin >= cos_moitie_angle * d_j) {
					_vue_vus_total += 1;
					vus_ids_i.push_back(vj.id);
				}
				// ARRET SANS PERTE : union recouvre tout le cone.
				if (secteurs.size() == 1
						&& secteurs[0].first <= -demi_cone + 1e-4f
						&& secteurs[0].second >= demi_cone - 1e-4f) {
					break;
				}
			}
			_us_occ_sep += std::chrono::duration_cast<std::chrono::microseconds>(
					std::chrono::steady_clock::now() - t_occ_debut).count();
		}
	}
	// SERIALISATION de vus_par_id -> ids_plat + offsets. Deux passes :
	// (1) offsets[i+1] = offsets[i] + vus_par_id[i].size(). (2) copie plate.
	int total = 0;
	for (int i = 0; i < count; i++) {
		offsets.set(i, total);
		total += (int)vus_par_id[(size_t)i].size();
	}
	offsets.set(count, total);
	ids_plat.resize(total);
	int32_t *ids_w = ids_plat.ptrw();
	int pos = 0;
	for (int i = 0; i < count; i++) {
		const std::vector<int32_t> &v = vus_par_id[(size_t)i];
		const int n = (int)v.size();
		for (int k = 0; k < n; k++) {
			ids_w[pos++] = v[(size_t)k];
		}
	}
	out["ids"] = ids_plat;
	out["offsets"] = offsets;
	return out;
}

PackedVector3Array IndexSpatial::separation_lot(
		const PackedVector3Array &positions,
		const PackedInt32Array &ids,
		const PackedInt32Array &offsets,
		float rayon) const {
	PackedVector3Array out;
	int count = offsets.size() - 1;
	if (count <= 0) {
		return out;
	}
	out.resize(count);
	Vector3 *out_w = out.ptrw();
	for (int i = 0; i < count; i++) {
		out_w[i] = Vector3();
	}
	if (positions.size() < count) {
		ERR_PRINT("IndexSpatial::separation_lot : positions trop petit vs offsets. Retour a zero.");
		return out;
	}
	const Vector3 *pos_r = positions.ptr();
	const int32_t *ids_r = ids.ptr();
	const int32_t *off_r = offsets.ptr();
	for (int i = 0; i < count; i++) {
		int debut = off_r[i];
		int fin = off_r[i + 1];
		if (debut == fin) {
			continue;
		}
		const Vector3 &p_i = pos_r[i];
		float ax = 0.0f;
		float az = 0.0f;
		for (int j = debut; j < fin; j++) {
			int32_t id_k = ids_r[j];
			const Vector3 &p_k = pos_r[id_k];
			float dx = p_i.x - p_k.x;
			float dz = p_i.z - p_k.z;
			float d2 = dx * dx + dz * dz;
			if (d2 <= 1e-8f) {
				continue;
			}
			float d = std::sqrt(d2);
			float w = (rayon - d) / d;
			ax += dx * w;
			az += dz * w;
		}
		float len2 = ax * ax + az * az;
		if (len2 > 1e-8f) {
			float inv_len = 1.0f / std::sqrt(len2);
			out_w[i] = Vector3(ax * inv_len, 0.0f, az * inv_len);
		}
	}
	return out;
}

Dictionary IndexSpatial::derniers_chronos_vue() const {
	Dictionary out;
	out["collecte"] = (int64_t)_us_collecte;
	out["filtre"] = (int64_t)_us_filtre;
	out["tri"] = (int64_t)_us_tri;
	out["occ_sep"] = (int64_t)_us_occ_sep;
	return out;
}

Dictionary IndexSpatial::derniers_compteurs_vue() const {
	Dictionary out;
	out["voisins_total"] = (int64_t)_vue_voisins_total;
	out["unites_total"] = (int64_t)_vue_unites_total;
	out["vus_total"] = (int64_t)_vue_vus_total;
	return out;
}

Dictionary IndexSpatial::cases_pour_niveau(int exposant) const {
	Dictionary out;
	for (const Niveau &niveau : _niveaux) {
		if (niveau.exposant != exposant) {
			continue;
		}
		for (const auto &kv : niveau.cases) {
			const std::vector<int32_t> &contenu = kv.second;
			PackedInt32Array arr;
			arr.resize((int)contenu.size());
			if (!contenu.empty()) {
				std::memcpy(arr.ptrw(), contenu.data(), contenu.size() * sizeof(int32_t));
			}
			out[kv.first] = arr;
		}
		return out;
	}
	return out;
}
