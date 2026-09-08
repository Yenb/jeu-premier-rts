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
// Entree "voisin retenu par filtre distance" pour vue_lot -- id + delta et
// distance precalcules pour eviter tout recalcul dans les boucles cone et
// occlusion. Un vector<VoisinVue> local a vue_lot remplace la boucle
// d'occlusion sur le voisinage brut (chantier "degraissage vue_lot",
// 2026-09-08) : les seuls corps qui peuvent occulter un voisin retenu sont
// eux-memes des voisins dans le rayon (un obstacle plus loin ne coupe pas
// le segment percepteur -> voisin, la geometrie de occlusion.gd::facteur
// avec t dans ]0,1[ le rejette de facto). Filtrer d'abord par distance rend
// la liste bien plus petite que le voisinage brut (typiquement 5-10x moins
// a densite du peuplement mobile_test), donc l'occlusion coute nv_r^2 au
// lieu de nv_brut^2 -- gain quadratique sur le poste vue.
struct VoisinVue {
	int32_t id;
	float dx; // pos_i.x - pos_k.x
	float dz; // pos_i.z - pos_k.z
	float d;  // distance horizontale
};
} // namespace anonyme

void IndexSpatial::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurer", "nombre_ids"), &IndexSpatial::configurer);
	ClassDB::bind_method(D_METHOD("ouvrir_niveau", "exposant"), &IndexSpatial::ouvrir_niveau);
	ClassDB::bind_method(D_METHOD("ouvrir_niveau_planaire", "exposant"), &IndexSpatial::ouvrir_niveau_planaire);
	ClassDB::bind_method(D_METHOD("deplacer_lot", "positions"), &IndexSpatial::deplacer_lot);
	ClassDB::bind_method(D_METHOD("cases_pour_niveau", "exposant"), &IndexSpatial::cases_pour_niveau);
	ClassDB::bind_method(D_METHOD("vue_lot", "positions", "orientations", "opacites", "rayon", "cos_moitie_angle", "largeur", "seuil_facteur"), &IndexSpatial::vue_lot);
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

PackedVector3Array IndexSpatial::vue_lot(
		const PackedVector3Array &positions,
		const PackedVector3Array &orientations,
		const PackedFloat32Array &opacites,
		float rayon,
		float cos_moitie_angle,
		float largeur,
		float seuil_facteur) const {
	PackedVector3Array out;
	int count = positions.size();
	out.resize(count);
	Vector3 *out_w = out.ptrw();
	for (int i = 0; i < count; i++) {
		out_w[i] = Vector3();
	}
	// Reset des sous-chronos temporaires (voir en-tete). La somme des quatre
	// couvre tout le corps de vue_lot.
	_us_collecte = 0;
	_us_filtre = 0;
	_us_tri = 0;
	_us_occ_sep = 0;
	if (count <= 0 || _niveaux.empty() || rayon <= 0.0f) {
		return out;
	}
	if (orientations.size() != count || opacites.size() != count) {
		ERR_PRINT("IndexSpatial::vue_lot : orientations/opacites de taille differente de positions. Retour a zero.");
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
		ERR_PRINT("IndexSpatial::vue_lot : aucun niveau PLANAIRE ouvert -- appeler ouvrir_niveau_planaire(exposant) avant. Retour a zero.");
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

	// OUTIL DE VOISINAGE MUTUALISE PAR CASE (patron Verlet neighbor list,
	// reconstruit par frame). dans_rayon_case est indexe par POSITION dans la
	// case courante et EFFACE a chaque nouvelle case (buffer reutilise +
	// capacite gardee, jamais N allocations par frame). Intra-case en demi-
	// paire (i<j distribuee aux deux), inter-case ecrit uniquement dans la
	// liste de l'unite courante.
	std::vector<std::vector<VoisinVue>> dans_rayon_case;
	// Compteurs TEMPORAIRES : voisins bruts (rayon), voisins VUS (rayon + cone),
	// unites traitees. Sans occlusion-attenuation dans la vue, vus_moy ~= la
	// fraction dans le cone -- il tomberait avec un vrai filtre visuel
	// (balayage angulaire, chantier suivant).
	_vue_voisins_total = 0;
	_vue_unites_total = 0;
	_vue_vus_total = 0;

	const int n_cases = (int)std::ceil(rayon * inv_a);

	for (const auto &kv_case : niveau.cases) {
		const Vector3i &C1 = kv_case.first;
		const std::vector<int32_t> &unites_case = kv_case.second;
		if (unites_case.empty()) {
			continue;
		}
		const int n1 = (int)unites_case.size();

		// PASSE 1 : outil de voisinage mutualise par case (buffer local reutilise).
		auto t_col_debut = std::chrono::steady_clock::now();
		if ((int)dans_rayon_case.size() < n1) {
			dans_rayon_case.resize((size_t)n1);
		}
		for (int ii = 0; ii < n1; ii++) {
			dans_rayon_case[(size_t)ii].clear();
		}
		// Intra-case : paires (i<j) parmi unites_case, distribuees aux deux
		// listes (demi-paire correcte -- une seule paire de cases (C1, C1)).
		for (int ii = 0; ii < n1; ii++) {
			int32_t i_id = unites_case[ii];
			const Vector3 &p_i = pos_r[i_id];
			for (int jj = ii + 1; jj < n1; jj++) {
				int32_t j_id = unites_case[jj];
				const Vector3 &p_j = pos_r[j_id];
				float dx = p_i.x - p_j.x;
				float dz = p_i.z - p_j.z;
				float d2 = dx * dx + dz * dz;
				if (d2 >= rayon2 || d2 <= 1e-8f) {
					continue;
				}
				float d = std::sqrt(d2);
				VoisinVue vi;
				vi.id = j_id;
				vi.dx = dx;
				vi.dz = dz;
				vi.d = d;
				dans_rayon_case[(size_t)ii].push_back(vi);
				VoisinVue vj;
				vj.id = i_id;
				vj.dx = -dx;
				vj.dz = -dz;
				vj.d = d;
				dans_rayon_case[(size_t)jj].push_back(vj);
			}
		}
		// Inter-case : chaque unite i de C1 contre chaque voisin externe k des
		// cases adjacentes. Ecrit UNIQUEMENT dans dans_rayon_case[ii] (la
		// liste de k sera batie quand SA case sera visitee comme case courante).
		for (int dcx = -n_cases; dcx <= n_cases; dcx++) {
			for (int dcz = -n_cases; dcz <= n_cases; dcz++) {
				if (dcx == 0 && dcz == 0) {
					continue;
				}
				Vector3i C2(C1.x + dcx, 0, C1.z + dcz);
				auto it = niveau.cases.find(C2);
				if (it == niveau.cases.end()) {
					continue;
				}
				const std::vector<int32_t> &unites_C2 = it->second;
				const int n2 = (int)unites_C2.size();
				for (int ii = 0; ii < n1; ii++) {
					int32_t i_id = unites_case[ii];
					const Vector3 &p_i = pos_r[i_id];
					std::vector<VoisinVue> &liste_ii = dans_rayon_case[(size_t)ii];
					for (int jj = 0; jj < n2; jj++) {
						int32_t k_id = unites_C2[jj];
						const Vector3 &p_k = pos_r[k_id];
						float dx = p_i.x - p_k.x;
						float dz = p_i.z - p_k.z;
						float d2 = dx * dx + dz * dz;
						if (d2 >= rayon2 || d2 <= 1e-8f) {
							continue;
						}
						float d = std::sqrt(d2);
						VoisinVue vv;
						vv.id = k_id;
						vv.dx = dx;
						vv.dz = dz;
						vv.d = d;
						liste_ii.push_back(vv);
					}
				}
			}
		}
		_us_collecte += std::chrono::duration_cast<std::chrono::microseconds>(
				std::chrono::steady_clock::now() - t_col_debut).count();

		// PASSE 2 : per-unite (cone elargi + tri + cone strict + occlusion + separation).
		for (int iu = 0; iu < n1; iu++) {
			int32_t id = unites_case[iu];
			const Vector3 &orient = orient_r[id];
			std::vector<VoisinVue> &liste = dans_rayon_case[(size_t)iu];
			// Compteurs diagnostic : accumule taille des listes brutes (avant
			// filtre cone) et compte l'unite. Voisins_moy = total / unites.
			_vue_voisins_total += (int64_t)liste.size();
			_vue_unites_total += 1;

			// MODULE OCCLUSION VISUELLE CORPS-TRAVERSE + SEPARATION.
			// Modele : la vue s'arrete au premier corps opaque. Un voisin J
			// est CACHE si le segment percepteur->J traverse le VOLUME (disque
			// horizontal rayon = largeur/2) d'un corps K PLUS PROCHE (d_k <
			// d_j garanti par tri + iteration sur les seuls "vus" deja retenus).
			// Un corps plus loin ou lateralement decale sans traverser le
			// segment ne cache jamais. Distinct de scripts/occlusion.gd
			// (attenuation multiplicative pour son/odeur) : ici la vue est
			// binaire (vu ou cache), sans opacite, sans cumul. Les bloqueurs
			// hors cone comptent quand meme comme obstacles visuels (un
	   // corps a cote peut boucher la ligne de vue), mais ils ne
	   // contribuent pas eux-memes a la separation.
			// Etapes :
			//   (1) Tri de dans_rayon_case[iu] par distance croissante.
			//   (2) Parcours proche->loin. Pour chaque J : test segment-disque
			//       contre chaque bloqueur deja retenu. Si J traverse un
			//       bloqueur -> cache, skip. Sinon -> retenir comme bloqueur
			//       pour les suivants ET, si J est dans le cone strict,
			//       accumuler la separation.
			auto t_filtre_debut = std::chrono::steady_clock::now();
			std::sort(liste.begin(), liste.end(),
					[](const VoisinVue &a, const VoisinVue &b) { return a.d < b.d; });
			_us_tri += std::chrono::duration_cast<std::chrono::microseconds>(
					std::chrono::steady_clock::now() - t_filtre_debut).count();
			auto t_occ_debut = std::chrono::steady_clock::now();
			float ax = 0.0f;
			float az = 0.0f;
			// Indices dans `liste` des voisins retenus comme bloqueurs (vus).
			// thread_local pour amortir l'allocation entre unites et frames.
			static thread_local std::vector<int> bloqueurs;
			bloqueurs.clear();
			const int nl = (int)liste.size();
			for (int a = 0; a < nl; a++) {
				const VoisinVue &vj = liste[a];
				// Test segment percepteur->J traverse un bloqueur plus proche ?
				bool cache = false;
				const float d2_j = vj.d * vj.d;
				const int nb = (int)bloqueurs.size();
				for (int b = 0; b < nb; b++) {
					const VoisinVue &vk = liste[(size_t)bloqueurs[(size_t)b]];
					// direction A->J : v = (-vj.dx, -vj.dz), |v|^2 = d2_j.
					// ok = pos_k - pos_a = (-vk.dx, -vk.dz).
					// t = (ok . v) / (v . v) = (vk.dx*vj.dx + vk.dz*vj.dz)/d2_j
					float dot_num = vj.dx * vk.dx + vj.dz * vk.dz;
					float t_proj = dot_num / d2_j;
					if (t_proj <= 0.0f || t_proj >= 1.0f) {
						continue;
					}
					// Distance laterale : ok - t_proj * v.
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
				bloqueurs.push_back(a);
				// Cone strict : J contribue a la separation SEULEMENT dans le cone.
				float dot_vers_voisin = -(orient.x * vj.dx + orient.z * vj.dz);
				if (dot_vers_voisin < cos_moitie_angle * vj.d) {
					continue;
				}
				_vue_vus_total += 1;
				float w = (rayon - vj.d) / vj.d;
				ax += vj.dx * w;
				az += vj.dz * w;
			}
			float len2 = ax * ax + az * az;
			if (len2 > 1e-8f) {
				float inv_len = 1.0f / std::sqrt(len2);
				out_w[id] = Vector3(ax * inv_len, 0.0f, az * inv_len);
			}
			_us_occ_sep += std::chrono::duration_cast<std::chrono::microseconds>(
					std::chrono::steady_clock::now() - t_occ_debut).count();
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
