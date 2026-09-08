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
	ClassDB::bind_method(D_METHOD("separation_lot", "positions", "rayon"), &IndexSpatial::separation_lot);
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

PackedVector3Array IndexSpatial::separation_lot(const PackedVector3Array &positions, float rayon) const {
	PackedVector3Array out;
	int count = positions.size();
	out.resize(count);
	Vector3 *out_w = out.ptrw();
	// Init a zero -- neutre si aucun niveau planaire, rayon nul, count nul,
	// et base de l'accumulation par paires ci-dessous (chaque paire ajoute
	// une contribution a out_w[id] et l'opposee a out_w[voisin]).
	for (int i = 0; i < count; i++) {
		out_w[i] = Vector3();
	}
	if (count <= 0 || _niveaux.empty() || rayon <= 0.0f) {
		return out;
	}
	// CHOIX DU NIVEAU LU. La separation EXIGE un niveau PLANAIRE (voir
	// Niveau::planaire) -- balayer l'axe Y sur un niveau 3D interrogerait
	// hashmap.find pour rien sur des plans Y quasi tous vides
	// (piege verifie : ~330 000 us/frame a N=100 000 entasses). Sur un
	// niveau planaire, toutes les unites d'une meme colonne (fx, fz) sont
	// dans la meme case, une seule find par case-colonne. En plus : l'arete
	// du niveau doit rester du meme ordre que le rayon -- sinon chaque
	// case ramasse plus de candidats que le rayon n'en couvre et la boucle
	// interne degenere en quasi-N^2 local. On prend donc le plus petit
	// exposant PLANAIRE dont l'arete est >= rayon. Aucun niveau planaire
	// ouvert -> push_error + retour a zero (contrat clair, un seul chemin,
	// l'appelant doit ouvrir un ouvrir_niveau_planaire dedie).
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
		// Repli : plus grande arete PLANAIRE ouverte. Si aucune, l'appelant
		// n'a pas respecte le contrat -- alarme et retour a zero.
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
		ERR_PRINT("IndexSpatial::separation_lot : aucun niveau PLANAIRE ouvert -- appeler ouvrir_niveau_planaire(exposant) avant. Retour a zero.");
		return out;
	}
	const Niveau &niveau = *choisi;
	const float inv_a = niveau.inv_arete;
	const Vector3 *pos_r = positions.ptr();
	const float rayon2 = rayon * rayon;
	// DEMI-PAIRE : chaque paire (id, voisin > id) est visitee UNE fois. La
	// contribution est symetrique -- dx*w ajoute a id, -dx*w ajoute a voisin.
	// Puis normalisation en seconde passe courte. Resultat mathematique
	// identique a l'ancienne version qui accumulait par id dans des locales
	// ax/az (verrouille par scripts/test_separation_cpp.gd).
	for (int32_t id = 0; id < count; id++) {
		const Vector3 &p = pos_r[id];
		int cx_min = (int)std::floor((p.x - rayon) * inv_a);
		int cx_max = (int)std::floor((p.x + rayon) * inv_a);
		int cz_min = (int)std::floor((p.z - rayon) * inv_a);
		int cz_max = (int)std::floor((p.z + rayon) * inv_a);
		for (int cx = cx_min; cx <= cx_max; cx++) {
			for (int cz = cz_min; cz <= cz_max; cz++) {
				auto it = niveau.cases.find(Vector3i(cx, 0, cz));
				if (it == niveau.cases.end()) {
					continue;
				}
				const std::vector<int32_t> &contenu = it->second;
				const int n = (int)contenu.size();
				for (int k = 0; k < n; k++) {
					int32_t voisin = contenu[k];
					if (voisin <= id) {
						// Filtre demi-paire : la paire (id, voisin<id) a deja
						// ete traitee quand id iterait sur voisin (ou l'auto-
						// comparaison id==id, sautee).
						continue;
					}
					const Vector3 &q = pos_r[voisin];
					float dx = p.x - q.x;
					float dz = p.z - q.z;
					float d2 = dx * dx + dz * dz;
					if (d2 > rayon2 || d2 <= 1e-8f) {
						continue;
					}
					float d = std::sqrt(d2);
					float w = (rayon - d) / d;
					float wx = dx * w;
					float wz = dz * w;
					// Contribution symetrique : force sur id = (p - q) * w,
					// force sur voisin = (q - p) * w = -force sur id.
					out_w[id].x += wx;
					out_w[id].z += wz;
					out_w[voisin].x -= wx;
					out_w[voisin].z -= wz;
				}
			}
		}
	}
	// SECONDE PASSE : normaliser chaque accumulateur en direction unitaire
	// horizontale (Y=0). N sqrt supplementaires -- negligeables devant les
	// N*voisins sqrt evites dans la boucle principale (une paire = un sqrt
	// contre deux avant).
	for (int32_t id = 0; id < count; id++) {
		float x = out_w[id].x;
		float z = out_w[id].z;
		float len2 = x * x + z * z;
		if (len2 > 1e-8f) {
			float inv_len = 1.0f / std::sqrt(len2);
			out_w[id] = Vector3(x * inv_len, 0.0f, z * inv_len);
		} else {
			out_w[id] = Vector3();
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
