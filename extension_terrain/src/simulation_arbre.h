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

#include <cstdint>
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
};

} // namespace godot

#endif // SIMULATION_ARBRE_H
