#include "index_spatial.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>
#include <cstring>

using namespace godot;

void IndexSpatial::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configurer", "nombre_ids"), &IndexSpatial::configurer);
	ClassDB::bind_method(D_METHOD("ouvrir_niveau", "exposant"), &IndexSpatial::ouvrir_niveau);
	ClassDB::bind_method(D_METHOD("ouvrir_niveau_planaire", "exposant"), &IndexSpatial::ouvrir_niveau_planaire);
	ClassDB::bind_method(D_METHOD("deplacer_lot", "positions"), &IndexSpatial::deplacer_lot);
	ClassDB::bind_method(D_METHOD("cases_pour_niveau", "exposant"), &IndexSpatial::cases_pour_niveau);
	ClassDB::bind_method(D_METHOD("vue_lot", "positions", "orientations", "opacites", "rayon", "cos_moitie_angle", "largeur", "seuil_facteur"), &IndexSpatial::vue_lot);
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

	// Voisinage local reutilise entre unites -- evite N=100000 allocations de
	// vector par frame. clear() garde la capacite acquise.
	std::vector<int32_t> voisinage;
	voisinage.reserve(64);

	for (int32_t id = 0; id < count; id++) {
		const Vector3 &p = pos_r[id];
		const Vector3 &orient = orient_r[id];
		int cx_min = (int)std::floor((p.x - rayon) * inv_a);
		int cx_max = (int)std::floor((p.x + rayon) * inv_a);
		int cz_min = (int)std::floor((p.z - rayon) * inv_a);
		int cz_max = (int)std::floor((p.z + rayon) * inv_a);

		// COLLECTE du voisinage 3x3 planaire (tous corps sauf id). Sert a la
		// fois pour l'iteration candidats ET pour la liste d'obstacles du test
		// d'occlusion -- jamais une requete spatiale supplementaire par paire
		// (c'est le n^2 a eviter, contrat prompt).
		voisinage.clear();
		for (int cx = cx_min; cx <= cx_max; cx++) {
			for (int cz = cz_min; cz <= cz_max; cz++) {
				auto it = niveau.cases.find(Vector3i(cx, 0, cz));
				if (it == niveau.cases.end()) {
					continue;
				}
				const std::vector<int32_t> &contenu = it->second;
				const int n = (int)contenu.size();
				for (int k = 0; k < n; k++) {
					int32_t v = contenu[k];
					if (v != id) {
						voisinage.push_back(v);
					}
				}
			}
		}

		float ax = 0.0f;
		float az = 0.0f;
		const int nv = (int)voisinage.size();
		for (int a = 0; a < nv; a++) {
			int32_t j = voisinage[a];
			const Vector3 &q = pos_r[j];
			float dx = p.x - q.x;
			float dz = p.z - q.z;
			float d2 = dx * dx + dz * dz;
			// (1) DISTANCE strictement inferieure au rayon.
			if (d2 >= rayon2 || d2 <= 1e-8f) {
				continue;
			}
			float d = std::sqrt(d2);
			// (2) CONE : cos(angle entre orient et diff_vers_voisin) >=
			// cos_moitie_angle. diff_vers_voisin = q - p (composantes -dx, -dz),
			// orient suppose unitaire horizontal. Comparaison sans acos.
			float dot_vers_voisin = -(orient.x * dx + orient.z * dz);
			if (dot_vers_voisin < cos_moitie_angle * d) {
				continue;
			}
			// (3) OCCLUSION : geometrie de scripts/occlusion.gd::facteur portee
			// mot pour mot. Obstacles = les autres corps du voisinage courant.
			// vecteur = vers - depuis = q - p (composantes planaires -dx, -dz).
			// longueur_carre = d2. Pour chaque obstacle k :
			//   t = (pos_k - depuis) . vecteur / longueur_carre
			//   si t <= 0 ou t >= 1 skip
			//   point_sur_segment = depuis + vecteur * t
			//   distance_laterale = |pos_k - point_sur_segment|
			//   si distance_laterale > largeur skip
			//   facteur *= (1 - clamp(opacite_k, 0, 1))
			float facteur = 1.0f;
			float vx = -dx;
			float vz = -dz;
			for (int b = 0; b < nv; b++) {
				if (b == a) {
					continue;
				}
				int32_t k = voisinage[b];
				const Vector3 &r = pos_r[k];
				float ok_x = r.x - p.x;
				float ok_z = r.z - p.z;
				float t = (ok_x * vx + ok_z * vz) / d2;
				if (t <= 0.0f || t >= 1.0f) {
					continue;
				}
				float sx = p.x + t * vx;
				float sz = p.z + t * vz;
				float lat_x = r.x - sx;
				float lat_z = r.z - sz;
				float lat2 = lat_x * lat_x + lat_z * lat_z;
				if (lat2 > largeur2) {
					continue;
				}
				float opac = opac_r[k];
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
			// (4) SEPARATION : contribution accumulee dans le MEME parcours.
			float w = (rayon - d) / d;
			ax += dx * w;
			az += dz * w;
		}
		// Normalisation en direction unitaire horizontale (Y=0).
		float len2 = ax * ax + az * az;
		if (len2 > 1e-8f) {
			float inv_len = 1.0f / std::sqrt(len2);
			out_w[id] = Vector3(ax * inv_len, 0.0f, az * inv_len);
		}
	}
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
