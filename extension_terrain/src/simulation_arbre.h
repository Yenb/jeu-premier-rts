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
#include <godot_cpp/variant/projection.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <list>
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

	// ETAPE B2 : mise a jour INCREMENTALE des buffers rendu, avec cache par
	// slot (miroir du skip EPS_TAILLE oracle). Buffers persistants en membres
	// C++ : jamais realloues sauf changement de capacite. Un slot n'est
	// recalcule QUE si son age/stade/libres a franchi le seuil EPS_TAILLE
	// depuis le dernier tick.
	//
	// Retour Dictionary (RENDU COMPACT, prompt 2026-09-14) :
	//   "tout_dirty" (bool) : true si capacite changee ou cache reset.
	//   "dirty_count" (int) : nombre de slots data reellement modifies ce tick
	//     (informatif -- ne conditionne plus le chemin push).
	//   "pop" (int) : nombre de slots vivants (libres==0) dans la capacite.
	//   "buffer_tronc"/"buffer_feuillage" (PackedFloat32Array, 16*pop) : buffer
	//     COMPACT dans l'ordre croissant des slots data vivants. GDScript pose
	//     _mm.instance_count = pop et pousse pop*16 floats -- independant de cap.
	//   "slot_rendu_pour_data" (PackedInt32Array, taille cap) : -1 si libre,
	//     sinon le rang du slot data dans le buffer compact (0..pop-1).
	//
	// Seuil EPS_TAILLE = 0.001f (identique constante EPS_TAILLE GDScript).
	// Cache invalide via invalider_cache_rendu() -- a appeler au
	// _agrandir_capacite ou tout reset structurel du buffer GPU.
	// FILTRE CERCLE RENDU (streaming, prompt 2026-09-15) :
	//   filtre_actif=false : buffer compact sur TOUS les vivants (comportement
	//     historique) ; ox/oz/rayon_carre ignores.
	//   filtre_actif=true  : un slot vivant est INCLUS dans le buffer compact
	//     UNIQUEMENT si (px-ox)^2 + (pz-oz)^2 <= rayon_carre. La sim GDScript
	//     ne depend PAS de ce filtre (aucune colonne mutee ici).
	//
	// CANAL CAMERA UNIQUE (2026-09-18) : le C++ lit droite/haut/avant/oeil dans
	// la base du Transform3D affiche par Godot, et FOV_H/FOV_V dans les tangentes
	// de la Projection. Aucun recalcul manuel de la base ; camera_active remplace
	// cone_actif (drapeau leve des qu'un Transform valide est pousse).
	Dictionary mettre_a_jour_buffers_rendu(
			int capacite,
			const PackedByteArray &libres,
			const PackedFloat32Array &ages,
			const PackedInt32Array &slot_stade,
			const PackedFloat32Array &positions_x,
			const PackedFloat32Array &positions_y,
			const PackedFloat32Array &positions_z,
			bool filtre_actif,
			float rayon_carre,
			bool camera_active,
			const Transform3D &cam_transform,
			const Projection &cam_projection);

	// Invalide le cache : force tout_dirty=true au prochain appel.
	// Miroir : agrandissement de capacite qui reset le buffer GPU.
	void invalider_cache_rendu();
	// Marge du frustum radar (tan_h/tan_v * marge). Bornee [1.0, 3.0] cote
	// setter (recadrage defensif). Coquille pousse chaque frame.
	void definir_marge_frustum(float m);
	// DUMP FRAME D'OCCLUSION (2026-09-18). Sur demande, la prochaine
	// mettre_a_jour_buffers_rendu ecrit frame.json + buffer_2d.pgm + 4 CSV
	// dans le dossier fourni, puis remet le drapeau a false. Cout nul le
	// reste du temps.
	void demander_dump(const String &chemin);
	// Masque de couverture Intel MOC (test_volume_occulte). SEUIL_COUVERTURE
	// clampe [0.0, 1.0], MARGE_PROFONDEUR clampe [0.0, 10.0]. Coquille pousse
	// chaque frame (regles @export + surcharge JSON).
	void definir_seuil_couverture(float s);
	void definir_marge_profondeur(float m);

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

	// ETAPE 12 : REMPLISSAGE COLONNES PLATES NAISSANCE. Miroir de la boucle
	// _naitre_lot (l.1587-1628 du .gd), COLONNES PLATES + population
	// UNIQUEMENT. Reste GDScript : allocation slots, tirage RNG
	// FacteurVariance (ordre RNG intact), _derniere_params (Array Vector4),
	// _choses_arbre, _monde.ajouter_lot, arbre_ajouter_lot, depot ombrage.
	//
	// Entrees :
	//   slots            : slots alloues (n)
	//   slots_r          : slots rendu correspondants (n), -1 si aucun
	//   naissances_x/y/z : positions (n) -- y deja calcule GDScript
	//                      (Y_SOL ou carte_terrain.sommet)
	//   croissance_col   : deja tires (n) via FacteurVariance
	//   longevite_col    : deja tires (n) via FacteurVariance
	//   stade_initial    : index stade a la naissance (typiquement -1 avant
	//                      passage +1, comme _index_pour_age(0.0) du .gd)
	//   annees_par_seconde, graines_par_vie, fenetre_fertile_age : stables
	//   colonnes actuelles (COW) : libres, ages, positions_x/y/z, slot_stade,
	//     facteur_croissance, facteur_longevite, intervalle_reprod,
	//     derniere_couleur_stade, slot_rendu_pour_data, data_pour_slot_rendu
	//
	// Sortie Dictionary : chaque colonne mutee, meme nom que la cle GDScript.
	Dictionary remplir_colonnes_naissance(
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
			const PackedInt32Array &data_pour_slot_rendu) const;

	// ETAPE 14 : BANQUE + DORMANTES + EXPIRATIONS + REVEILS.
	// Miroir de attente_seuil.gd + _dormantes_par_case + _case_de_dormante +
	// _expirations + _reveils cote GDScript. Ordre d'insertion PRESERVE
	// bit-a-bit : les ids attribues (_prochain_id monotone jamais reutilise)
	// et l'ordre de parcours de _prospects / _reveils / _dormantes_par_case[cle]
	// determinent quelles graines deviennent des naissances -> foret entiere.
	//
	// initialiser_stable_banque : pose stables (taille_case_dormantes,
	// rayon_reveil, duree_vie_graine). Idempotent.
	void initialiser_stable_banque(
			float taille_case_dormantes,
			float rayon_reveil,
			float duree_vie_graine);

	// banque_reset : vide tout etat banque (prospects, dormantes, expirations,
	// reveils, temps_banque=0, _prochain_id_banque=0). Appele au setup du banc.
	void banque_reset();

	// banque_ajouter_dormante : miroir des 3 gestes GDScript qui suivent
	// _banque_graines.ajouter (l.1229-1243 du .gd) :
	//   1. ajouter au registre _prospects (attribue id monotone)
	//   2. _inscrire_dormante(id, x, z) : ajout a la grille _dormantes_par_case
	//   3. _expirations.append([_temps_banque + _duree_vie_graine, id])
	// Rend l'id attribue. Miroir ORDRE d'insertion exact.
	int banque_ajouter_dormante(float x, float z);

	// banque_retirer_dormante : miroir des 3 gestes GDScript qui suivent
	// _banque_graines.retirer (drainer_expirations + _tick_banque naissance) :
	//   1. retirer du registre _prospects
	//   2. _retirer_dormante(id) : retire de la grille _dormantes_par_case
	//      (preserve l'ordre des ids restants dans la case)
	// L'entree correspondante dans _expirations n'est PAS retiree (miroir GD :
	// la file n'est purgee que par la tete lors du drain ; les ids absents de
	// _prospects sont ignores l.1360-1362).
	void banque_retirer_dormante(int id);

	// banque_nombre : miroir _banque_graines.nombre().
	int banque_nombre() const;

	// banque_avancer_temps : _temps_banque += pas (avant drainer_expirations).
	void banque_avancer_temps(float pas);

	// banque_drainer_expirations : miroir l.1354-1377 du .gd.
	// Avance _expirations_head tant que temps <= _temps_banque, retire chaque
	// id encore present dans _prospects (retirer_dormante inclus). Compaction
	// _expirations quand _head > 1024 et _head > size/2.
	void banque_drainer_expirations();

	// banque_recuperer_reveils_ids_ordre : rend les ids de _reveils dans
	// leur ordre d'insertion (Dictionary GDScript = insertion-ordered) puis
	// CLEAR _reveils. Miroir de `_ids_tbq = _reveils.keys() ; _reveils.clear()`
	// (l.1379-1381). GDScript appelle ensuite banque_prospects_pour_ids pour
	// obtenir les positions.
	PackedInt32Array banque_recuperer_reveils_ids_ordre();

	// banque_prospects_pour_ids : pour chaque id demande, rend (present, x, z)
	// dans l'ordre d'entree. Sortie :
	//   "presents" PackedByteArray (n) : 1 si _prospects.has(id), 0 sinon
	//   "x" PackedFloat32Array (n) : position x (0 si absent)
	//   "z" PackedFloat32Array (n) : position z (0 si absent)
	// GDScript filtre alors les absents pour construire pros_ids_tbq / pros_x_tbq /
	// pros_z_tbq dans le meme ordre que l'oracle (miroir l.1382-1389).
	Dictionary banque_prospects_pour_ids(const PackedInt32Array &ids) const;

	// banque_reveiller_autour_lot : miroir _reveiller_dormantes_autour_lot
	// (l.1042-1072 morts_v, l.1081-1112 reveil-en-lot, l.1902-1932 morts_c).
	// Meme parcours cx/cz avec floori, meme test distance^2 <= _rayon_reveil^2,
	// skip si deja reveille ou absent des _prospects. Preserve l'ordre
	// d'insertion dans _reveils (insertion-ordered map).
	void banque_reveiller_autour_lot(
			const PackedFloat32Array &rev_x,
			const PackedFloat32Array &rev_z);

	// banque_reveils_est_vide : test rapide (miroir _reveils.is_empty()).
	bool banque_reveils_est_vide() const;

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

	// Etat buffers rendu persistants (etape B2). Non realloues sauf
	// changement de capacite. Cache par slot : dernieres valeurs ecrites
	// pour le comparer via EPS_TAILLE (miroir _derniere_params GDScript).
	std::vector<float> _buf_tronc_p;
	std::vector<float> _buf_feuillage_p;
	int _rendu_cap_actuelle = 0;
	std::vector<uint8_t> _cache_valide;   // 0 = jamais ecrit, 1 = ecrit
	std::vector<uint8_t> _cache_libres_ecrit;
	std::vector<int32_t> _cache_stade_ecrit;
	std::vector<float> _cache_p_ht;
	std::vector<float> _cache_p_lt;
	std::vector<float> _cache_p_hf;
	std::vector<float> _cache_p_lf;
	// HYSTERESIS DU VERDICT D'OCCLUSION (GPU Gems 2 ch.6, persistance
	// N frames). Etat de visibilite affiche stabilise et compteur de
	// bascules opposees consecutives. Un basculement n'affecte l'affichage
	// que s'il tient HYSTERESIS_FRAMES ticks d'affilee.
	std::vector<uint8_t> _visible_stable;
	std::vector<uint8_t> _compteur_bascule;
	std::vector<uint8_t> _dernier_brut;   // verdict brut du tick precedent (par slot)
	// FIX B2 : flag "au terminal" par slot -- 1 quand le dernier recalcul
	// a trouve==false (age > sum(durees), valeurs figees au dernier stade).
	// Permet un SKIP EARLY avant la boucle lerp l.1673 : en regime stable,
	// evite le compute pour ~90% de la population. Sinon le lerp est calcule
	// pour tous les slots vivants meme quand ils vont etre skippes.
	std::vector<uint8_t> _cache_terminal;
	// Hysterese temporelle sur l'occlusion (prompt 2026-09-15). Compteur
	// signe par slot : +1 quand le test dit "cache", -1 quand "visible",
	// borne dans [0, SEUIL]. L'arbre n'est REELLEMENT occulte que quand
	// le compteur atteint SEUIL -> les vacillements courts (1-2 ticks)
	// n'atteignent jamais le seuil, aucun changement visible.
	bool _cache_rendu_force_reset = true; // premier appel = tout_dirty
	// Occlusion Intel MOC : liste des arbres susceptibles d'etre bloqueurs
	// depuis la CAMERA (refill inconditionnel chaque tick).
	std::vector<int32_t> _bloqueurs_camera;
	// Seuil de hauteur minimale pour qu'un arbre soit inscrit comme bloqueur.
	// Un jeune arbre de moins de 3 m ne cache pas grand chose ; l'exclure
	// reduit la taille du cache et le cout du precalcul.
	static constexpr float HAUTEUR_MIN_BLOQUEUR_M = 3.0f;
	// Chantier occlusion 2D projete camera (etape 2/8) : buffer de profondeur.
	// Chaque pixel = distance camera au plus proche bloqueur qui y est projete.
	// INFINITY = pixel vide.
	static constexpr int BUFFER_2D_LARGEUR = 512;
	static constexpr int BUFFER_2D_HAUTEUR = 256;
	std::vector<float> _buffer_2d;
	// Marge multiplicative appliquee aux demi-ouvertures du frustum radar
	// (tan_h/tan_v * marge). Reglable a chaud via definir_marge_frustum,
	// canal pousse chaque frame par la coquille. Defaut 1.15 = ancien
	// comportement (constante en dur avant 2026-09-18).
	float _marge_frustum = 1.15f;
	// Masque de couverture Intel MOC : fraction min de pixels de l'empreinte
	// strictement plus proches que la face de l'arbre pour occulter, et
	// marge en metres pour absorber l'epaisseur d'un arbre. Reglables via
	// definir_seuil_couverture / definir_marge_profondeur, pousses chaque
	// frame par la coquille.
	float _seuil_couverture = 0.90f;
	float _marge_profondeur = 0.5f;
	// DUMP FRAME (2026-09-18) : declenche par demander_dump, consomme et
	// remis a false par le prochain mettre_a_jour_buffers_rendu.
	bool _dump_demande = false;
	String _dump_chemin;

	// Stables banque (etape 14).
	float _taille_case_dormantes = 0.0f;
	float _rayon_reveil = 0.0f;
	float _duree_vie_graine = 0.0f;
	float _temps_banque = 0.0f;

	// Etat banque : registre _prospects INSERTION-ORDERED (list + hash).
	struct BanqueProspect {
		float x = 0.0f;
		float z = 0.0f;
	};
	std::list<std::pair<int32_t, BanqueProspect>> _prospects_ordre;
	std::unordered_map<int32_t, std::list<std::pair<int32_t, BanqueProspect>>::iterator> _prospects_idx;
	int32_t _prochain_id_banque = 0;

	// Grille dormantes : case -> vector<id> (ordre d'insertion), + inverse.
	struct Vec2iHashBanque {
		size_t operator()(const Vector2i &v) const noexcept {
			size_t h = std::hash<int32_t>()(v.x);
			h ^= std::hash<int32_t>()(v.y) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
			return h;
		}
	};
	struct Vec2iEqBanque {
		bool operator()(const Vector2i &a, const Vector2i &b) const noexcept {
			return a.x == b.x && a.y == b.y;
		}
	};
	std::unordered_map<Vector2i, std::vector<int32_t>, Vec2iHashBanque, Vec2iEqBanque> _dormantes_par_case_cpp;
	std::unordered_map<int32_t, Vector2i> _case_de_dormante_cpp;

	// File des expirations : vector + curseur tete. Compaction quand
	// _head > 1024 et > size/2 (miroir GDScript l.1375-1377).
	std::vector<std::pair<float, int32_t>> _expirations_cpp;
	int32_t _expirations_head_cpp = 0;

	// Set _reveils INSERTION-ORDERED (list + hash).
	std::list<int32_t> _reveils_ordre;
	std::unordered_map<int32_t, std::list<int32_t>::iterator> _reveils_idx;

	// Helper prive : inscription grille dormantes (miroir _inscrire_dormante).
	void _inscrire_dormante_cpp(int32_t id, float x, float z);
	// Helper prive : retrait grille dormantes (miroir _retirer_dormante).
	void _retirer_dormante_cpp(int32_t id);
};

} // namespace godot

#endif // SIMULATION_ARBRE_H
