#ifndef SIMULATION_ARBRE_H
#define SIMULATION_ARBRE_H

// Portage C++ du tick de jeu/bancs/simulation_arbre.gd.
// MIROIR NATIF -- simulation_arbre.gd reste l'oracle de parite bit-a-bit
// (scripts/test_simulation_arbre_cpp.gd).
//
// ETAPE 2  : passe 1 (senescence + stade + detection + mort vieillesse).
// ETAPE 2b : frontiere TYPEE (ptrcall) sur avancer_passe_1 / initialiser_stable.
// ETAPE 3  : RENDU MULTIMESH -- construire_buffers_rendu(...) construit
//            deux PackedFloat32Array (16 floats / instance : 12 transform
//            TRANSFORM_3D + 4 color) prets pour `MultiMesh.buffer = ...`
//            en UN push moteur par tick (2xN -> 2). Le patron buffer est
//            deja dans le depot (voir mesheur_tuile.h l.18-24), meme format
//            moteur, meme discipline. La reproduction stochastique (RNG)
//            reste GDScript a cette etape.
//
// PATRON godot-cpp : GDCLASS(RefCounted), _bind_methods statique, frontiere
// SoA plate, ptr/ptrw jamais element par element via Variant. Signatures
// TYPEES en entree (Packed*Array const&, scalaires nommes) -- patron
// index_spatial.h::perception_lot. Sortie Dictionary (aligne sur les 4
// soeurs : gain ptrcall EXCLUSIVEMENT sur l'entree).
//
// STABLES du tick (poussees UNE fois via initialiser_stable et
// initialiser_stable_rendu) : annees_par_seconde, duree_croissance_totale,
// duree_mort, bornes du statut adulte, seuils d'age par stade, ombrage par
// stade, durees des stades vivants, tables tronc/feuillage hauteur/largeur
// par stade, couleurs tronc/feuillage par stade, couleurs de repli, EPS
// taille. Aucune ne franchit la frontiere par tick.
//
// PARITE BIT-A-BIT : composantes en float 32 (godot-cpp real_t par defaut),
// ordre des multiplications senescence preserve strictement, stade
// « jamais un recul » par comparaison d'INDEX, lerp de rendu identique
// (formule lerp GDScript reproduite ligne a ligne), formule Y_tronc =
// y_sol + ht*0.5, Y_feuillage = y_sol + ht + hf*0.5, cas feuillage nul
// (scale zero, origin y_sol+ht) preserves.

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <unordered_map>
#include <utility>
#include <vector>

namespace godot {

class SimulationArbre : public RefCounted {
	GDCLASS(SimulationArbre, RefCounted)

	int _population = 0;

	// STABLES pousses par initialiser_stable(...).
	float _annees_par_seconde = 1.0f;
	float _duree_croissance_totale = 0.0f;
	float _duree_mort = 180.0f;
	int _stade_gros_min = 5;
	int _stade_gros_max = 7;
	std::vector<float> _seuils_ages_stade;
	std::vector<float> _ombrage_rayon_m;
	std::vector<float> _ombrage_magnitude;
	bool _stable_initialise = false;

	// STABLES du RENDU pousses par initialiser_stable_rendu(...).
	// Miroir des tables lues par _ecrire_slots_lot dans simulation_arbre.gd :
	// _durees (n_durees), _stades[k].tronc.hauteur/largeur et
	// _stades[k].feuillage.hauteur/largeur (n_stades), _couleur_tronc_par_stade
	// et _couleur_feuillage_par_stade (PackedColorArray, n_stades). Couleurs
	// de repli quand la table couleur ne couvre pas le stade demande.
	std::vector<float> _durees_stades;
	std::vector<float> _tronc_hauteur;
	std::vector<float> _tronc_largeur;
	std::vector<float> _feuillage_hauteur;
	std::vector<float> _feuillage_largeur;
	std::vector<Color> _couleur_tronc;
	std::vector<Color> _couleur_feuillage;
	Color _couleur_repli_tronc = Color(0.35f, 0.22f, 0.12f);
	Color _couleur_repli_feuillage = Color(0.15f, 0.45f, 0.2f);
	float _y_sol_defaut = 12.0f;
	bool _stable_rendu_initialise = false;

protected:
	static void _bind_methods();

public:
	SimulationArbre();
	~SimulationArbre();

	bool charge() const;
	int population() const;

	// INIT STABLE (signature TYPEE pour ptrcall). Voir simulation_arbre.h.
	void initialiser_stable(
			float annees_par_seconde,
			float duree_croissance_totale,
			float duree_mort,
			int stade_gros_min,
			int stade_gros_max,
			const PackedFloat32Array &seuils_ages_stade,
			const PackedFloat32Array &ombrage_rayon_m,
			const PackedFloat32Array &ombrage_magnitude);

	// INIT STABLE RENDU (signature TYPEE pour ptrcall). A appeler UNE fois
	// avant le premier construire_buffers_rendu.
	//   durees_stades       : durees_stades.gd = _durees (n_durees, n = n_stades - 1)
	//   tronc_hauteur       : _stades[k].tronc.hauteur (n_stades = n_durees + 1)
	//   tronc_largeur       : _stades[k].tronc.largeur
	//   feuillage_hauteur   : _stades[k].feuillage.hauteur
	//   feuillage_largeur   : _stades[k].feuillage.largeur
	//   couleur_tronc       : _couleur_tronc_par_stade
	//   couleur_feuillage   : _couleur_feuillage_par_stade
	//   couleur_repli_tronc/feuillage : repli si table couleur ne couvre pas.
	//   y_sol_defaut        : Y_SOL constant du .gd (fallback slot vide).
	void initialiser_stable_rendu(
			const PackedFloat32Array &durees_stades,
			const PackedFloat32Array &tronc_hauteur,
			const PackedFloat32Array &tronc_largeur,
			const PackedFloat32Array &feuillage_hauteur,
			const PackedFloat32Array &feuillage_largeur,
			const PackedColorArray &couleur_tronc,
			const PackedColorArray &couleur_feuillage,
			const Color &couleur_repli_tronc,
			const Color &couleur_repli_feuillage,
			float y_sol_defaut);

	// PASSE 1 du tick (voir en-tete pour le contrat).
	Dictionary avancer_passe_1(
			float pas,
			int capacite,
			const PackedByteArray &libres,
			const PackedFloat32Array &ages,
			const PackedInt32Array &slot_stade,
			const PackedFloat32Array &facteur_croissance,
			const PackedFloat32Array &facteur_longevite,
			const PackedFloat32Array &positions_x,
			const PackedFloat32Array &positions_z) const;

	// CONSTRUIRE BUFFERS RENDU. Rend deux PackedFloat32Array de 16 floats
	// par slot (12 transform TRANSFORM_3D + 4 color RGBA), prets pour
	// `MultiMesh.buffer = ...`. UN appel moteur par MultiMesh au lieu de
	// 2xN. Aucun cache C++ : le buffer est REGENERE a chaque appel (le skip
	// EPS_TAILLE du chemin GDScript n'a plus lieu d'etre en mode push
	// buffer -- on pousse tout le buffer en un coup). Consequence : parite
	// bit-a-bit contre un helper GDScript equivalent qui REGENERE aussi
	// (pas contre la boucle _ecrire_slots_lot originale, qui accumule via
	// skip). Le chemin oracle GDScript reste utilise quand utilise_cpp=false.
	//
	// LAYOUT (16 floats/slot) :
	//   [0..2]   basis.rows[0] (x, y, z)
	//   [3]      origin.x
	//   [4..6]   basis.rows[1]
	//   [7]      origin.y
	//   [8..10]  basis.rows[2]
	//   [11]     origin.z
	//   [12..15] color (r, g, b, a)
	//
	// Sortie Dictionary :
	//   "buffer_tronc"     PackedFloat32Array (16 * capacite)
	//   "buffer_feuillage" PackedFloat32Array (16 * capacite)
	Dictionary construire_buffers_rendu(
			int capacite,
			const PackedByteArray &libres,
			const PackedFloat32Array &ages,
			const PackedInt32Array &slot_stade,
			const PackedFloat32Array &positions_x,
			const PackedFloat32Array &positions_y,
			const PackedFloat32Array &positions_z) const;

	// ETAPE 4 : RESET COLONNES du drainage morts vieillesse. Pour chaque
	// indice mort, applique slot_stade[i] = -1, libres[i] = 1, ages[i] = 0.
	// Signature typée (ptrcall). Ne touche PAS aux structures GDScript non
	// plates (_choses_arbre, _slots_libres, _dormantes_par_case, _reveils,
	// _slot_rendu_pour_data, _population) : elles restent gerees cote GD
	// dans la meme boucle. Le C++ n'a de population interne qu'en scaffolding
	// (jamais mutee par cette methode) -- decrement _population reste GD.
	//
	// Rend colonnes mutees dans un Dictionary (patron Copy-on-Write des
	// autres methodes).
	Dictionary appliquer_reset_morts(
			const PackedInt32Array &morts,
			const PackedByteArray &libres,
			const PackedInt32Array &slot_stade,
			const PackedFloat32Array &ages) const;

	// ETAPE 5 : RNG DETERMINISTE. Instancie un RandomNumberGenerator du
	// moteur (godot-cpp Ref<RandomNumberGenerator>) et l'expose. Aucun
	// algorithme reimplemente a la main : c'est la MEME classe que
	// GDScript utilise, meme PCG32 sous-jacent, meme suite a seed egal.
	// La parite est par CONSTRUCTION, pas par reimplementation. Ne
	// remplace pas encore le _rng GDScript des postes gameplay (etapes
	// suivantes : reproduction, competition).
	void poser_seed_rng(uint64_t seed);

	// Tire N randf() du RNG C++ et rend PackedFloat32Array (N valeurs).
	// Test de parite : appeler la meme fonction sur _rng GDScript apres
	// re-seed, comparer bit-a-bit. Utile aussi pour bench et debug.
	PackedFloat32Array tirer_randf_lot(int n);

private:
	// RNG godot-cpp -- meme classe que GDScript, meme PCG32.
	Ref<RandomNumberGenerator> _rng;

	// ETAPE 8 : SHADOW INDEX SPATIAL du monde des arbres. Miroir minimal
	// de scripts/monde.gd (mode structure_simple). Multi-niveaux par
	// exposant : chaque niveau tient un unordered_map case (Vector3i) ->
	// vector<slot int32>, plus case_de[slot] pour retrait swap-remove.
	// Positions par slot stockees a part (test distance^2 xz). N'expose
	// PAS l'API monde complete -- seulement ce qu'il faut pour porter
	// choses_dans_rayons_brut_xz. Aucun framework touche.
	struct Vec3iHashArbre {
		size_t operator()(const Vector3i &v) const noexcept {
			size_t h = std::hash<int32_t>()(v.x);
			h ^= std::hash<int32_t>()(v.y) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
			h ^= std::hash<int32_t>()(v.z) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
			return h;
		}
	};
	struct NiveauArbre {
		double inv_arete = 1.0;
		int exposant = 0;
		std::unordered_map<Vector3i, std::vector<int32_t>, Vec3iHashArbre> cases;
		std::unordered_map<int32_t, Vector3i> case_de;
	};
	std::unordered_map<int, NiveauArbre> _niveaux_arbre;
	// slot -> (x, z) -- positions arbres pour le test distance^2 en xz.
	// Un arbre non present dans cette map = non inscrit.
	std::unordered_map<int32_t, std::pair<float, float>> _positions_arbre;

	// STABLES REPRODUCTION posees une fois par initialiser_stable_reproduction.
	float _debut_fertilite = 0.0f;
	float _fin_fertilite = 0.0f;
	float _rayon_graine = 6.0f;

public:
	// ETAPE 6 : INIT STABLE REPRODUCTION. Voir _passe_reproduction cote GDScript.
	void initialiser_stable_reproduction(
			float debut_fertilite,
			float fin_fertilite,
			float rayon_graine);

	// ETAPE 6 : PASSE REPRODUCTION portee. Miroir de _passe_reproduction
	// (simulation_arbre.gd l.2106-2131). Ordre 0..cap-1 preserve, skip
	// libres et morts. Fertile => tirage randf() sur _rng C++ (parite
	// prouvee etape 5 : meme suite que GDScript a seed egal), puis angle
	// et rayon disque uniforme, append aux deux colonnes de graines.
	// Aucune mutation d'etat GDScript autre que l'append -- graines
	// rendues au GDScript qui append_array a _graines_lot_x/z.
	//
	// Cles retour Dictionary :
	//   "graines_x" PackedFloat32Array (K)
	//   "graines_z" PackedFloat32Array (K)
	Dictionary passe_reproduction(
			float pas,
			int capacite,
			const PackedByteArray &libres,
			const PackedFloat32Array &ages,
			const PackedFloat32Array &intervalle_reprod,
			const PackedFloat32Array &positions_x,
			const PackedFloat32Array &positions_z,
			const PackedInt32Array &morts_vieillesse);

	// ETAPE 6 : partager le RNG C++ avec GDScript. Rend la meme Ref
	// que le membre interne, GDScript peut l'assigner a son `_rng` et
	// TOUS les tirages (repro C++ + variance naissance GDScript +
	// competition GDScript) passent alors par le MEME RandomNumberGenerator.
	// Sans partage, la reproduction en C++ desynchroniserait les tirages
	// GDScript restants (variance/competition) -> parite cassee.
	Ref<RandomNumberGenerator> obtenir_rng() const;

	// ETAPE 7 : COEUR DECISIONNEL COMPETITION. Deux appels typees
	// encadrant la requete monde GDScript (option (a) : _monde n'est
	// pas encore C++, on le laisse GDScript, la requete se fait entre
	// deux appels C++). Le drainage des morts reste GDScript.
	//
	// selection_competition : boucle curseur tournant, meme arithmetique
	// _n_slots_avc que le .gd (l.1505-1523). Skip libres et stade >
	// stade_competition_max. Rend positions_batch (Y = y_sol constant),
	// slots_batch, curseur_avance.
	Dictionary selection_competition(
			float pas,
			int capacite,
			float cadence_competition,
			int stade_competition_max,
			int curseur_competition,
			const PackedByteArray &libres,
			const PackedInt32Array &slot_stade,
			const PackedFloat32Array &positions_x,
			const PackedFloat32Array &positions_z,
			float y_sol) const;

	// decider_morts_competition : recoit slots_batch + CSR des voisins
	// (offsets, slots) construit par GDScript apres appel monde. Compte
	// voisins moins ceux deja morts ce tick (set interne au tour de
	// boucle), tire _rng->randf() < proba (miroir l.1539-1547 du .gd).
	// L'ordre du parcours et l'ordre des randf() sont STRICTEMENT
	// identiques a l'oracle -- condition de parite seed-egal.
	// Rend PackedInt32Array des slots morts.
	PackedInt32Array decider_morts_competition(
			const PackedInt32Array &slots_batch,
			const PackedInt32Array &voisins_offsets,
			const PackedInt32Array &voisins_slots,
			int competition_max_voisins);

	// ETAPE 8 : shadow monde -- ouvrir un niveau pour un exposant. Batit
	// depuis les positions deja enregistrees (miroir _batir de monde.gd).
	// Miroir de _exposant_pour (l.860-863) : ceil(log2(rayon)), clampe.
	void arbre_ouvrir_niveau(int exposant);

	// ETAPE 8 : inscrit les arbres du lot dans TOUS les niveaux ouverts,
	// et enregistre leurs positions. Ordre d'insertion des slots dans
	// case[cle] preserve (append) -- condition de parite.
	void arbre_ajouter_lot(
			const PackedInt32Array &slots,
			const PackedFloat32Array &positions_x,
			const PackedFloat32Array &positions_z,
			float y_sol);

	// ETAPE 8 : retire les arbres du lot de TOUS les niveaux ouverts.
	// swap-remove dans le vector case (miroir _deranger de monde.gd
	// mode structure_simple) -- O(1) par slot.
	void arbre_retirer_lot(const PackedInt32Array &slots);

	// ETAPE 8 : requete spatiale, miroir bit-a-bit de monde.gd::
	// choses_dans_rayons_brut_xz (l.664-714).
	Dictionary arbre_choses_dans_rayons_brut_xz(
			const PackedFloat32Array &positions_x,
			const PackedFloat32Array &positions_z,
			float y_sol,
			float rayon) const;

	// ETAPE 10 : SEMIS -- stables + zones + pre-filtre + gate + decision.
	// Le semis ne tire PAS de RNG. Le drainage banque + dormantes reste
	// GDScript, applique sur les listes rendues par semer_gate_decision.
	void initialiser_stable_semis(
			float rayon_trouee,
			float facteur_trouee_gros,
			float rayon_exclusion,
			int trouee_max_voisins,
			float demi_carte,
			float seuil_couvert);

	// Zones d'exclusion : cercle (forme=0, rayon utilise) ou rectangle
	// (forme=1, demi_x/demi_z utilises). Poussees une fois a l'init du
	// banc (constantes pour la vie de la sim, verifie sur disque).
	void definir_zones_exclusion_cpp(
			const PackedByteArray &formes,
			const PackedFloat32Array &cx,
			const PackedFloat32Array &cz,
			const PackedFloat32Array &rayon,
			const PackedFloat32Array &demi_x,
			const PackedFloat32Array &demi_z);

	// Pre-filtre : filtrage hors-carte + zones d'exclusion. Miroir
	// l.1147-1176 du .gd. Rend :
	//   "indices_valides" PackedInt32Array : k dans le lot qui passe
	//   "positions_valides" PackedVector3Array : Vector3(x, y_sol, z)
	// GDScript appelle ensuite monde.choses_dans_rayons_brut_xz sur
	// positions_valides et couvert.lire_lot sur les graines completes.
	Dictionary semer_pre_filtre(
			const PackedFloat32Array &graines_x,
			const PackedFloat32Array &graines_z,
			float y_sol) const;

	// Gate trouee + decision naissance vs banque. Miroir l.1185-1246 du .gd.
	// Entrees :
	//   graines_x/z : lot complet
	//   naissances_deja_x/z : naissances DEJA dans le lot au moment de
	//     l'appel (initialement vide). La sortie s'ajoute a ces listes en
	//     interne pour que les graines suivantes voient les nouvelles
	//     naissances comme voisins (l.1212-1223 du .gd).
	//   indices_valides : PackedInt32Array (rendu par semer_pre_filtre)
	//   voisins_offsets, voisins_slots : CSR des voisins pour les graines
	//     valides (rendu par arbre_choses_dans_rayons_brut_xz)
	//   couverts : couvert lu a chaque graine (via _couvert.lire_lot)
	//   slot_stade : PackedInt32Array (pour lire stade des voisins)
	//
	// Sortie Dictionary :
	//   "naissances_ajouts_x/z" PackedFloat32Array : nouvelles naissances
	//     produites par ce semis (a append_array aux _naissances_lot_x/z)
	//   "banque_x/z" PackedFloat32Array : graines qui vont en banque
	//     (GDScript les inscrit via _banque_graines.ajouter + _inscrire_dormante)
	Dictionary semer_gate_decision(
			const PackedFloat32Array &graines_x,
			const PackedFloat32Array &graines_z,
			const PackedFloat32Array &naissances_deja_x,
			const PackedFloat32Array &naissances_deja_z,
			const PackedInt32Array &indices_valides,
			const PackedInt32Array &voisins_offsets,
			const PackedInt32Array &voisins_slots,
			const PackedFloat32Array &couverts,
			const PackedInt32Array &slot_stade) const;

	// ETAPE 11 : GATE RE-TEST DES REVEILLES. Miroir l.1407-1489 du .gd
	// (_tick_banque, boucle prospects reveilles). Meme math du gate que
	// le semis (voisins arbres via CSR + naissances du lot en dynamique +
	// trouee_max) MAIS :
	//   - zones filtrees INLINE (pas de pre-filtre separe)
	//   - pas de filtre hors-carte (prospects deja dans la carte par
	//     construction)
	//   - itere TOUS les prospects (pas d'indices_valides)
	//   - decision : `passe && couvert < seuil` -> naissance ;
	//     `couvert >= seuil` -> SKIP (le prospect reste en banque,
	//     re-teste au prochain reveil), pas de re-inscription banque.
	// Aucune modification du _banque_graines/_dormantes cote C++ :
	// GDScript recoit les indices j des prospects qui produisent naissance,
	// et applique _banque_graines.retirer + _retirer_dormante + append
	// _naissances_lot_x/z, dans le meme ordre.
	//
	// Entrees :
	//   pros_x/z : positions des prospects reveilles (dans l'ordre de
	//     l'iteration GDScript, meme ordre que _pros_ids_tbq)
	//   naissances_deja_x/z : naissances DEJA dans le lot au moment de
	//     l'appel (le semis a deja tourne ce tick, donc contient les
	//     naissances du semis). Les naissances reveilles s'ajoutent en
	//     interne pour que les prospects suivants les voient (l.1459-1470
	//     du .gd).
	//   voisins_offsets, voisins_slots : CSR des voisins par prospect,
	//     rendu par arbre_choses_dans_rayons_brut_xz sur pros_x/pros_z.
	//   couverts : PackedFloat32Array (n_pros) -- lu par _couvert.lire_lot
	//   slot_stade : lecture stade des voisins
	//
	// Sortie Dictionary :
	//   "naissances_indices" PackedInt32Array : indices j des prospects
	//     qui passent le gate ET dont couvert < seuil, dans l'ordre de
	//     l'iteration (pour que GDScript retire prospects[j] et append
	//     _naissances_lot_x/z dans le meme ordre).
	Dictionary retester_reveilles_gate(
			const PackedFloat32Array &pros_x,
			const PackedFloat32Array &pros_z,
			const PackedFloat32Array &naissances_deja_x,
			const PackedFloat32Array &naissances_deja_z,
			const PackedInt32Array &voisins_offsets,
			const PackedInt32Array &voisins_slots,
			const PackedFloat32Array &couverts,
			const PackedInt32Array &slot_stade) const;

private:
	// Stables semis (etape 10).
	float _rayon_trouee = 0.0f;
	float _facteur_trouee_gros = 0.0f;
	float _rayon_exclusion = 0.0f;
	int _trouee_max_voisins = 0;
	float _demi_carte = 0.0f;
	float _seuil_couvert = 0.0f;

	struct ZoneExclusionCpp {
		int forme = 0; // 0 = cercle, 1 = rectangle
		float cx = 0.0f;
		float cz = 0.0f;
		float rayon = 0.0f;
		float demi_x = 0.0f;
		float demi_z = 0.0f;
	};
	std::vector<ZoneExclusionCpp> _zones_exclusion_cpp;
};

} // namespace godot

#endif // SIMULATION_ARBRE_H
