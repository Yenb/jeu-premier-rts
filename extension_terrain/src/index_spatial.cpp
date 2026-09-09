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

void IndexSpatial::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurer", "nombre_ids"), &IndexSpatial::configurer);
	ClassDB::bind_method(D_METHOD("ouvrir_niveau", "exposant"), &IndexSpatial::ouvrir_niveau);
	ClassDB::bind_method(D_METHOD("ouvrir_niveau_planaire", "exposant"), &IndexSpatial::ouvrir_niveau_planaire);
	ClassDB::bind_method(D_METHOD("deplacer_lot", "positions"), &IndexSpatial::deplacer_lot);
	ClassDB::bind_method(D_METHOD("cases_pour_niveau", "exposant"), &IndexSpatial::cases_pour_niveau);
	ClassDB::bind_method(D_METHOD("perception_lot", "positions", "orientations", "opacites", "rayon", "cos_moitie_angle", "largeur", "seuil_facteur"), &IndexSpatial::perception_lot);
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
			// la lecture planaire en O(cases planaires) sans balayer Y.
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
	// PORT DE scripts/occlusion.gd::facteur EN LOT. Modele MULTIPLICATIF de
	// l'occlusion (aucun argmin, aucun tri, aucun ordre proche->loin) : pour
	// chaque cible dans le cone strict, un facteur `f` dans [0,1] cumule
	// multiplicativement l'attenuation de chaque autre voisin dont la
	// projection sur le segment agent->cible tombe strictement dans ]0,1[ et
	// dont la distance laterale est <= largeur. La cible est VUE si
	// f > seuil_facteur. `opacites[k]` fournit la valeur d'attenuation (clampee
	// [0,1]) pour l'obstacle k.
	//
	// UN SEUL PARCOURS PAR AGENT (chrono `_us_occ_sep`). Le voisinage local
	// (voisins dans le disque de rayon `rayon`) sert a la fois de liste des
	// cibles potentielles et de liste des obstacles. Rassemblement et test
	// occlusion dans le meme scope, aucune passe collecte distincte.
	const float *opacite_r = opacites.ptr();
	const float largeur2 = largeur * largeur;

	struct VoisinLocal {
		int32_t id;
		float dx; // p_i.x - p_k.x
		float dz; // p_i.z - p_k.z
		float d;  // distance horizontale
	};
	static thread_local std::vector<VoisinLocal> voisinage_local;

	// vus_par_id : accumule les ids vus par chaque agent, serialise a la fin.
	static thread_local std::vector<std::vector<int32_t>> vus_par_id;
	if ((int)vus_par_id.size() < count) {
		vus_par_id.resize((size_t)count);
	}
	for (int i = 0; i < count; i++) {
		vus_par_id[(size_t)i].clear();
	}

	// Compteurs TEMPORAIRES.
	_vue_voisins_total = 0;
	_vue_unites_total = 0;
	_vue_vus_total = 0;

	for (int i = 0; i < count; i++) {
		const int32_t id = i;
		const Vector3 &p_i = pos_r[id];
		const Vector3 &orient_i = orient_r[id];
		auto t_agent_debut = std::chrono::steady_clock::now();

		// BASSE / HAUTE en cases, port de scripts/monde.gd::choses_dans_rayon :
		// cases touchees par le disque de rayon `rayon` centre sur p_i.
		const int cx_min = (int)std::floor((p_i.x - rayon) * inv_a);
		const int cx_max = (int)std::floor((p_i.x + rayon) * inv_a);
		const int cz_min = (int)std::floor((p_i.z - rayon) * inv_a);
		const int cz_max = (int)std::floor((p_i.z + rayon) * inv_a);

		// RASSEMBLEMENT du voisinage local (voisins dans le disque). AUCUN
		// filtre cone ici : un voisin hors cone peut encore etre OBSTACLE pour
		// une cible dans le cone -- la geometrie de facteur() tranche.
		voisinage_local.clear();
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
					VoisinLocal vl;
					vl.id = k_id;
					vl.dx = dx;
					vl.dz = dz;
					vl.d = std::sqrt(d2);
					voisinage_local.push_back(vl);
				}
			}
		}

		_vue_voisins_total += (int64_t)voisinage_local.size();
		_vue_unites_total += 1;

		std::vector<int32_t> &vus_ids_i = vus_par_id[(size_t)id];
		const int nvl = (int)voisinage_local.size();

		// TEST OCCLUSION per cible (voisins du cone strict), port de
		// scripts/occlusion.gd::facteur. Ordre libre des obstacles, cumul
		// multiplicatif, aucun tri, aucun argmin.
		for (int c = 0; c < nvl; c++) {
			const VoisinLocal &vj = voisinage_local[(size_t)c];

			// CONE STRICT : orient.dot(direction_vers_voisin) >= cos_moitie_angle.
			// direction_vers_voisin = -(vj.dx, vj.dz) / vj.d, donc :
			//   orient.dot(...) = -(orient.x * vj.dx + orient.z * vj.dz) / vj.d.
			// Multiplier des deux cotes par vj.d (positif) : cos_moitie_angle * vj.d.
			float dot_vers = -(orient_i.x * vj.dx + orient_i.z * vj.dz);
			if (dot_vers < cos_moitie_angle * vj.d) {
				continue;  // hors cone strict, cible non testee
			}

			// FACTEUR = port de occlusion.gd::facteur en repere relatif a
			// l'agent (agent a l'origine 0,0). depuis=(0,0), vers=(-vj.dx,-vj.dz),
			// vecteur=(-vj.dx,-vj.dz), longueur_carre=vj.d*vj.d.
			// Pour chaque obstacle vk :
			//   position_k = (-vk.dx, -vk.dz)
			//   t_dot = (position_k - depuis) . vecteur = vk.dx * vj.dx + vk.dz * vj.dz
			//   t = t_dot / longueur_carre
			//   Condition t dans ]0,1[ : t_dot > 0 ET t_dot < longueur_carre.
			//   point_sur_segment = vecteur * t = (-vj.dx * t, -vj.dz * t)
			//   distance_laterale^2 = (position_k - point_sur_segment).len_sq
			//                       = (-vk.dx + vj.dx * t)^2 + (-vk.dz + vj.dz * t)^2
			const float d2_j = vj.d * vj.d;
			const float inv_d2_j = 1.0f / d2_j;
			float f = 1.0f;
			for (int o = 0; o < nvl; o++) {
				if (o == c) {
					continue;  // ids_exclus = la cible elle-meme
				}
				const VoisinLocal &vk = voisinage_local[(size_t)o];
				float t_dot = vk.dx * vj.dx + vk.dz * vj.dz;
				if (t_dot <= 0.0f) {
					continue;  // t <= 0
				}
				if (t_dot >= d2_j) {
					continue;  // t >= 1
				}
				float t = t_dot * inv_d2_j;
				float lat_x = -vk.dx + vj.dx * t;
				float lat_z = -vk.dz + vj.dz * t;
				float lat2 = lat_x * lat_x + lat_z * lat_z;
				if (lat2 > largeur2) {
					continue;
				}
				// valeur = clamp(opacite[vk.id], 0, 1) ; f *= (1 - valeur).
				float valeur = opacite_r[vk.id];
				if (valeur < 0.0f) valeur = 0.0f;
				if (valeur > 1.0f) valeur = 1.0f;
				f *= (1.0f - valeur);
			}

			if (f > seuil_facteur) {
				vus_ids_i.push_back(vj.id);
				_vue_vus_total += 1;
			}
		}

		_us_occ_sep += std::chrono::duration_cast<std::chrono::microseconds>(
				std::chrono::steady_clock::now() - t_agent_debut).count();
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

Dictionary IndexSpatial::derniers_chronos_vue() const {
	Dictionary out;
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
