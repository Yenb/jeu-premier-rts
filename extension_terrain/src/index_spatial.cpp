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
// Voisinage BRUT d'une case (patron boids : liste de voisinage batie une fois
// par cellule, partagee entre tous les agents de la cellule). Contient
// {id, x, z} de chaque corps du bloc (2*n_cases+1)^2 autour de la case, sans
// dedoublonnage necessaire (chaque case adjacente ne contient qu'une fois un
// id donne). Chaque unite de la case courante lit ce voisinage commun pour
// calculer SES propres dx/dz/d (soustraction depuis sa position + sqrt) --
// la LISTE DES CORPS a considerer n'est etablie qu'une fois par case.
struct VoisinBrut {
	int32_t id;
	float x;
	float z;
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

		// PASSE 1a : voisinage BRUT de la case, etabli UNE FOIS.
		// La liste des corps du bloc (2*n_cases+1)^2 autour de la case est
		// commune aux unites de la case -- seul le calcul dx/dz/d depuis leur
		// position est per-unite. Patron boids : liste de voisinage batie une
		// fois par cellule, partagee entre tous les agents. Reutilise entre
		// cases via un thread_local (clear + capacite gardee).
		auto t_col_debut = std::chrono::steady_clock::now();
		static thread_local std::vector<VoisinBrut> voisinage_case;
		voisinage_case.clear();
		for (int dcx = -n_cases; dcx <= n_cases; dcx++) {
			for (int dcz = -n_cases; dcz <= n_cases; dcz++) {
				Vector3i Cadj(C1.x + dcx, 0, C1.z + dcz);
				auto it = niveau.cases.find(Cadj);
				if (it == niveau.cases.end()) {
					continue;
				}
				const std::vector<int32_t> &unites_adj = it->second;
				const int na = (int)unites_adj.size();
				for (int jj = 0; jj < na; jj++) {
					int32_t k_id = unites_adj[jj];
					const Vector3 &p_k = pos_r[k_id];
					VoisinBrut vb;
					vb.id = k_id;
					vb.x = p_k.x;
					vb.z = p_k.z;
					voisinage_case.push_back(vb);
				}
			}
		}
		// PASSE 1b : chaque unite de la case lit le voisinage commun pour
		// calculer SES propres dx/dz/d et remplir sa liste. Le sqrt et le
		// filtre distance restent per-unite (dependent de la position de
		// l'unite -- irreductible), mais la LISTE DES CORPS n'est plus
		// re-etablie 60 fois.
		if ((int)dans_rayon_case.size() < n1) {
			dans_rayon_case.resize((size_t)n1);
		}
		const int nvb = (int)voisinage_case.size();
		for (int ii = 0; ii < n1; ii++) {
			int32_t i_id = unites_case[ii];
			const Vector3 &p_i = pos_r[i_id];
			std::vector<VoisinVue> &liste_ii = dans_rayon_case[(size_t)ii];
			liste_ii.clear();
			for (int a = 0; a < nvb; a++) {
				const VoisinBrut &vb = voisinage_case[(size_t)a];
				if (vb.id == i_id) {
					continue;  // exclure soi
				}
				float dx = p_i.x - vb.x;
				float dz = p_i.z - vb.z;
				float d2 = dx * dx + dz * dz;
				if (d2 >= rayon2) {
					continue;
				}
				float d = std::sqrt(d2);
				VoisinVue vv;
				vv.id = vb.id;
				vv.dx = dx;
				vv.dz = dz;
				vv.d = d;
				liste_ii.push_back(vv);
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
			float ax = 0.0f;
			float az = 0.0f;
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
				// swap-remove en fin. Le chrono `tri` couvre ce balayage.
				auto t_sel_debut = std::chrono::steady_clock::now();
				int min_idx = 0;
				float min_d = liste[0].d;
				for (int s = 1; s < reste; s++) {
					if (liste[(size_t)s].d < min_d) {
						min_d = liste[(size_t)s].d;
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
				const float d2_j = vj.d * vj.d;
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
					if (cos_num < bc.base_k * vj.d) {
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
				float sin_arg = rayon_corps / vj.d;
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
				// Contribution separation si J dans le cone strict.
				float dot_vers_voisin = -(orient.x * vj.dx + orient.z * vj.dz);
				if (dot_vers_voisin >= cos_moitie_angle * vj.d) {
					_vue_vus_total += 1;
					float w = (rayon - vj.d) / vj.d;
					ax += vj.dx * w;
					az += vj.dz * w;
				}
				// ARRET SANS PERTE : union recouvre tout le cone.
				if (secteurs.size() == 1
						&& secteurs[0].first <= -demi_cone + 1e-4f
						&& secteurs[0].second >= demi_cone - 1e-4f) {
					break;
				}
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
