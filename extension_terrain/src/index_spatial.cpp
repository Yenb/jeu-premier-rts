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

		// (1) FILTRES DISTANCE + CONE ELARGI. On ne garde que les voisins :
		//  - a distance strictement < rayon,
		//  - dans un CONE ELARGI par atan(largeur / rayon) par rapport au
		//    cone strict des cibles.
		// Le cone elargi couvre TOUS les occulteurs legitimes des cibles :
		// un occulteur K d'une cible J dans le cone strict a angle(K, orient)
		// ≤ angle(J, orient) + atan(L / distance_projetee_de_K_sur_AJ), avec
		// L ≤ largeur. En prenant distance_projetee ~= rayon (borne haute
		// realiste dans le regime peuplement), l'ecart angulaire max est
		// atan(largeur / rayon) -- l'ecart le plus large qu'un occulteur
		// legitime puisse avoir par rapport a l'axe de sa cible. Pour un
		// occulteur tres proche de A (distance projetee << largeur), l'ecart
		// theorique peut monter au-dela ; cas limite accepte, un occulteur
		// quasiment collé au percepteur qui sortirait du cone elargi n'est
		// pas geometriquement realiste dans le regime peuplement.
		//
		// La liste dans_rayon sert ainsi a la fois de SOURCE DE CANDIDATS
		// (filtre cone strict re-applique dans (3)) ET de LISTE D'OCCULTEURS
		// pour (4). Les voisins DERRIERE l'unite (angle > cone elargi) --
		// typiquement ~190 sur ~250 en foule dense -- sont ecartes des le
		// remplissage : tri et boucle occlusion portent sur ~60 corps au lieu
		// de ~250. Gain quadratique.
		dans_rayon.clear();
		const int nv = (int)voisinage.size();
		// Precalcul du cos du cone ELARGI. acos(cos_moitie_angle) donne
		// l'angle moitie du cone strict ; on ajoute atan(largeur/rayon) puis
		// on reprend le cos. Une trigo par frame par unite, negligeable
		// devant le voisinage. cos_moitie_angle <= -1 (sphere pure demandee
		// par l'appelant) : garder tel quel, pas d'elargissement -- accepte
		// deja tout.
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
			// Filtre cone ELARGI applique au REMPLISSAGE. diff_vers_voisin =
			// pos_k - pos_i = (-dx, -dz). dot . orient / d = cos(angle).
			float dot_vers = -(orient.x * dx + orient.z * dz);
			if (dot_vers < cos_moitie_elargi * d) {
				continue;
			}
			VoisinVue vv;
			vv.id = k;
			vv.dx = dx;
			vv.dz = dz;
			vv.d = d;
			dans_rayon.push_back(vv);
		}
		// TRI PAR DISTANCE CROISSANTE des CANDIDATS. Sert au COURT-CIRCUIT
		// PRECOCE : quand un candidat cible est cache par un occulteur proche
		// opaque (opacite ~ 1), le facteur tombe a 0.0 <= seuil des le premier
		// obstacle aligne et la boucle occulteurs sort par `break`. Traiter
		// les cibles du plus proche au plus loin maximise les chances que ce
		// break tombe tot pour chaque candidat cache.
		//
		// ATTENTION -- LA BOUCLE OCCULTEURS RESTE SUR TOUS LES CORPS (b != a),
		// PAS SUR LES PLUS PROCHES SEULEMENT. Un premier jet de ce chantier
		// bornait la boucle a `b < a` avec l'argument "l'occulteur est plus
		// proche que sa cible". CET ARGUMENT EST FAUX en regime largeur non
		// negligeable devant la distance : un occulteur k a distance(i, k)^2 =
		// (t * d_j)^2 + L^2, et pour L <= largeur non nul, distance(i, k) peut
		// depasser d_j (contre-exemple concret : d_j = 0.6, k a (0.55, 12,
		// 0.35), largeur = 0.5 -- t = 0.917 dans ]0,1[, L = 0.35 <= 0.5,
		// distance(i, k) = 0.652 > 0.6). Un tel k etait un occulteur legitime
		// silencieusement ignore par b < a. Le tri est donc gardE pour le
		// break precoce, mais la boucle occulteurs teste bien tous les corps
		// du voisinage (les corps hors segment sont rejetes par t hors ]0,1[
		// ou L > largeur, comme avant).
		std::sort(dans_rayon.begin(), dans_rayon.end(),
				[](const VoisinVue &a, const VoisinVue &b) { return a.d < b.d; });
		float ax = 0.0f;
		float az = 0.0f;
		const int nvr = (int)dans_rayon.size();
		for (int a = 0; a < nvr; a++) {
			const VoisinVue &vj = dans_rayon[a];
			// (2) CONE : cos(angle entre orient et diff_vers_voisin) >=
			// cos_moitie_angle. diff_vers_voisin = pos_j - pos_i = (-dx, -dz),
			// orient suppose unitaire horizontal. Comparaison sans acos.
			float dot_vers_voisin = -(orient.x * vj.dx + orient.z * vj.dz);
			if (dot_vers_voisin < cos_moitie_angle * vj.d) {
				continue;
			}
			// (3) OCCLUSION : geometrie de scripts/occlusion.gd::facteur portee
			// mot pour mot, contre TOUS les corps de dans_rayon (b != a). Le
			// tri par distance croissante des CIBLES sert au court-circuit
			// precoce : en foule dense, un corps proche opaque (opacite ~ 1)
			// donne facteur = 0 <= seuil des le premier occulteur aligne, la
			// boucle sort par break -- une direction bouchee est ecartee sans
			// examen supplementaire. La boucle occulteurs teste tous les corps
			// du voisinage (pas seulement les plus proches -- un occulteur k a
			// distance(i, k)^2 = (t * d_j)^2 + L^2 et peut avoir distance > d_j
			// quand L est non negligeable, contre-exemple d_j = 0.6, L = 0.35,
			// distance = 0.652 > d_j -- verrouille par test_vue_cpp cas 5).
			// vecteur = pos_j - pos_i = (-vj.dx, -vj.dz). longueur_carre = vj.d^2.
			// Pour chaque obstacle k :
			//   t = (pos_k - depuis) . vecteur / longueur_carre
			//   pos_k - depuis = (-vk.dx, -vk.dz) (deja stocke)
			//   si t <= 0 ou t >= 1 skip
			//   point_sur_segment = depuis + vecteur * t
			//   distance_laterale = |pos_k - point_sur_segment|
			//   si distance_laterale > largeur skip
			//   facteur *= (1 - clamp(opacite_k, 0, 1))
			float facteur = 1.0f;
			float vx = -vj.dx;
			float vz = -vj.dz;
			float d2_j = vj.d * vj.d;
			for (int b = 0; b < nvr; b++) {
				if (b == a) {
					continue;
				}
				const VoisinVue &vk = dans_rayon[b];
				float ok_x = -vk.dx; // pos_k.x - p.x
				float ok_z = -vk.dz;
				float t = (ok_x * vx + ok_z * vz) / d2_j;
				if (t <= 0.0f || t >= 1.0f) {
					continue;
				}
				float sx = p.x + t * vx;
				float sz = p.z + t * vz;
				float lat_x = (p.x + ok_x) - sx; // pos_k.x - sx = ok_x + p.x - sx
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
			// (4) SEPARATION : contribution accumulee dans le MEME parcours.
			float w = (rayon - vj.d) / vj.d;
			ax += vj.dx * w;
			az += vj.dz * w;
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
