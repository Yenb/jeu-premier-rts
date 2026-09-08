#include "index_spatial.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <algorithm>
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
	const float *opac_r = opacites.ptr();
	const float rayon2 = rayon * rayon;
	const float largeur2 = largeur * largeur;
	// Reset compteurs temporaires (chantier "mesurer gain reel").
	_vue_cibles_totales = 0;
	_vue_breaks_dist = 0;
	_vue_tests_faits = 0;
	_vue_tests_evites = 0;

	// Voisinage local reutilise entre unites -- evite N=100000 allocations de
	// vector par frame. clear() garde la capacite acquise.
	std::vector<int32_t> voisinage;
	voisinage.reserve(64);
	// Sous-ensemble du voisinage filtre par DISTANCE (< rayon), avec dx/dz/d
	// precalcules. Sert de LISTE D'OCCULTEURS pour tester chaque candidat
	// retenu par le cone : un occulteur est necessairement dans le rayon (le
	// segment percepteur -> voisin a longueur < rayon, un corps hors du rayon
	// ne peut pas avoir t dans ]0,1[ sur ce segment sans etre lui-meme dans
	// le rayon). Chantier "degraissage vue_lot" (2026-09-08) : cette liste
	// est TYPIQUEMENT 5-10x plus courte que le voisinage brut, l'occlusion
	// passe donc de nv_brut^2 a nv_r^2 -- gain quadratique.
	std::vector<VoisinVue> dans_rayon;
	dans_rayon.reserve(64);

	// ITERATION PAR CASE OCCUPEE (chantier "collecte voisinage par case",
	// 2026-09-08). Le voisinage (2n+1)^2 planaire autour d'une case est le
	// MEME pour toutes les unites qui vivent dans cette case, tant que
	// n = ceil(rayon / arete) : une unite au bord de sa case voit au plus
	// n cases plus loin, donc rester dans [case.x -/+ n, case.z -/+ n] suffit.
	// Pour arete = 2 et rayon = 2, n = 1 -> 3x3 (identique au comportement
	// par unite precedent). Pour rayon > arete, n > 1 -- generalise sans
	// nombre en dur. On collecte donc le voisinage UNE fois par case (find
	// hashmap divise par nb_unites_dans_case, typiquement ~62 en foule
	// dense), puis on applique les filtres per-unite (distance / cone /
	// occlusion / separation) sur le voisinage partage. Le RESULTAT PAR
	// UNITE est identique -- seul le partage de la collecte change.
	const int n_cases = (int)std::ceil(rayon * inv_a);
	// Precalcul du cos du cone ELARGI. Une fois par appel (independant de
	// l'unite : le cone elargi est calibre sur rayon/largeur, pas sur la
	// position). acos + atan + cos hors boucle par unite.
	float cos_moitie_elargi_all = cos_moitie_angle;
	if (cos_moitie_angle > -1.0f + 1e-6f) {
		float demi_angle = std::acos(cos_moitie_angle);
		float extra = std::atan2(largeur, rayon);
		float elargi = demi_angle + extra;
		if (elargi >= 3.14159265f) {
			cos_moitie_elargi_all = -1.0f;
		} else {
			cos_moitie_elargi_all = std::cos(elargi);
		}
	}
	for (const auto &kv_case : niveau.cases) {
		const Vector3i &case_courante = kv_case.first;
		const std::vector<int32_t> &unites_case = kv_case.second;
		if (unites_case.empty()) {
			continue;
		}
		// COLLECTE UNE FOIS PAR CASE : (2n+1)^2 find hashmap, tous les corps
		// des cases voisines pousses dans le vector partage. Inclut les unites
		// de la case courante elles-memes -- filtrees par d2 <= 1e-8f dans le
		// filtre distance ci-dessous (distance a soi = 0).
		voisinage.clear();
		for (int dcx = -n_cases; dcx <= n_cases; dcx++) {
			for (int dcz = -n_cases; dcz <= n_cases; dcz++) {
				Vector3i cle(case_courante.x + dcx, 0, case_courante.z + dcz);
				auto it = niveau.cases.find(cle);
				if (it == niveau.cases.end()) {
					continue;
				}
				const std::vector<int32_t> &contenu = it->second;
				const int n = (int)contenu.size();
				for (int k = 0; k < n; k++) {
					voisinage.push_back(contenu[k]);
				}
			}
		}
		const int nv = (int)voisinage.size();

		// FILTRES PER-UNITE sur le voisinage partage.
		for (size_t iu = 0; iu < unites_case.size(); iu++) {
			int32_t id = unites_case[iu];
			const Vector3 &p = pos_r[id];
			const Vector3 &orient = orient_r[id];

			// (1) FILTRES DISTANCE + CONE ELARGI. dans_rayon ne contient que
			// les voisins qui passent distance ET cone elargi. La distance de
			// soi a soi = 0 -> filtre par d2 <= 1e-8f exclut naturellement soi.
			dans_rayon.clear();
			for (int a = 0; a < nv; a++) {
				int32_t k = voisinage[a];
				const Vector3 &q = pos_r[k];
				float dx = p.x - q.x;
				float dz = p.z - q.z;
				float d2 = dx * dx + dz * dz;
				if (d2 >= rayon2 || d2 <= 1e-8f) {
					continue;
				}
				float d = std::sqrt(d2);
				float dot_vers = -(orient.x * dx + orient.z * dz);
				if (dot_vers < cos_moitie_elargi_all * d) {
					continue;
				}
				VoisinVue vv;
				vv.id = k;
				vv.dx = dx;
				vv.dz = dz;
				vv.d = d;
				dans_rayon.push_back(vv);
			}
			// TRI PAR DISTANCE CROISSANTE (voir docs chantiers precedents :
			// break precoce facteur + borne d_j + largeur).
			std::sort(dans_rayon.begin(), dans_rayon.end(),
					[](const VoisinVue &a, const VoisinVue &b) { return a.d < b.d; });
			float ax = 0.0f;
			float az = 0.0f;
			const int nvr = (int)dans_rayon.size();
			for (int a = 0; a < nvr; a++) {
				const VoisinVue &vj = dans_rayon[a];
				// (2) CONE STRICT sur les cibles.
				float dot_vers_voisin = -(orient.x * vj.dx + orient.z * vj.dz);
				if (dot_vers_voisin < cos_moitie_angle * vj.d) {
					continue;
				}
				// (3) OCCLUSION -- geometrie de occlusion.gd::facteur mot pour
				// mot, boucle occulteurs bornee par distance (vk.d > vj.d + largeur
				// -> break, tri croissant).
				_vue_cibles_totales++;
				float facteur = 1.0f;
				float vx = -vj.dx;
				float vz = -vj.dz;
				float d2_j = vj.d * vj.d;
				float seuil_dist_occulteur = vj.d + largeur;
				for (int b = 0; b < nvr; b++) {
					const VoisinVue &vk = dans_rayon[b];
					if (vk.d > seuil_dist_occulteur) {
						_vue_breaks_dist++;
						_vue_tests_evites += (int64_t)(nvr - b);
						break;
					}
					if (b == a) {
						continue;
					}
					_vue_tests_faits++;
					float ok_x = -vk.dx;
					float ok_z = -vk.dz;
					float t = (ok_x * vx + ok_z * vz) / d2_j;
					if (t <= 0.0f || t >= 1.0f) {
						continue;
					}
					float sx = p.x + t * vx;
					float sz = p.z + t * vz;
					float lat_x = (p.x + ok_x) - sx;
					float lat_z = (p.z + ok_z) - sz;
					float lat2 = lat_x * lat_x + lat_z * lat_z;
					if (lat2 > largeur2) {
						continue;
					}
					float opac = opac_r[vk.id];
					if (opac < 0.0f) opac = 0.0f;
					if (opac > 1.0f) opac = 1.0f;
					facteur *= (1.0f - opac);
					if (facteur <= seuil_facteur) {
						break;
					}
				}
				if (facteur <= seuil_facteur) {
					continue;
				}
				// (4) SEPARATION dans le meme parcours.
				float w = (rayon - vj.d) / vj.d;
				ax += vj.dx * w;
				az += vj.dz * w;
			}
			float len2 = ax * ax + az * az;
			if (len2 > 1e-8f) {
				float inv_len = 1.0f / std::sqrt(len2);
				out_w[id] = Vector3(ax * inv_len, 0.0f, az * inv_len);
			}
		}
	}
	return out;
}

Dictionary IndexSpatial::derniers_compteurs_vue() const {
	Dictionary out;
	out["cibles_totales"] = (int)_vue_cibles_totales;
	out["breaks_dist"] = (int)_vue_breaks_dist;
	out["tests_faits"] = (int)_vue_tests_faits;
	out["tests_evites"] = (int)_vue_tests_evites;
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
