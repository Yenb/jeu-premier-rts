#ifndef INDEX_SPATIAL_H
#define INDEX_SPATIAL_H

// Index spatial du mode structure_simple de scripts/monde.gd, en C++ natif.
// Une classe RefCounted qui tient N niveaux (un par arete ouverte), chaque
// niveau portant :
//   - unordered_map<Vector3i, vector<int32_t>> cases   (case -> ids)
//   - vector<Vector3i> case_de                          (id -> case, indexe)
//   - vector<int32_t>  idx_dans_case                    (id -> position dans cases[case])
//   - vector<uint8_t>  presence                         (id present ou pas)
//   - float inv_arete, int exposant
//
// Miroir 1-pour-1 de scripts/niveau_monde.gd (voir son en-tete), les
// unordered_map remplacant les Dictionary GDScript. Les IDs sont des int32
// LINEAIRES (0..N-1) : le peuplement utilise le slot du pool comme ID, aucun
// hashing de String par frame. `case_de` et `idx_dans_case` sont des vector
// indexes par ID (acces O(1) direct), pas des map.
//
// PATRON godot-cpp identique au mesheur (extension_terrain/src/mesheur_tuile.h) :
// GDCLASS(RefCounted), entree/sortie Packed*Array, UNE frontiere par appel.
// Le peuplement fait deplacer_lot(positions) UNE fois par frame -- N=100 000
// unites traitees en un seul franchissement de frontiere GDScript->C++, au
// lieu de N franchissements pour N appels a deplacer_simple.
//
// FLOTTABILITE DU MODE : quand banc_peuplement.gd:deplacer_cpp = true,
// l'index C++ est la verite ; l'index GDScript de monde.gd (mode
// structure_simple) n'est plus tenu a jour (aucun appel a deplacer_simple).
// Le peuplement n'interroge pas choses_dans_rayon en jeu, donc cette
// divergence n'a aucun effet observable pour ce chantier. Une future
// interrogation en jeu devra soit basculer sur l'index C++ (methode
// cases_pour_niveau expose le contenu pour lecture), soit reporter la mesure
// en GDScript.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

class IndexSpatial : public RefCounted {
	GDCLASS(IndexSpatial, RefCounted)

	struct Vec3iHash {
		size_t operator()(const Vector3i &v) const noexcept {
			size_t h = std::hash<int32_t>()(v.x);
			h ^= std::hash<int32_t>()(v.y) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
			h ^= std::hash<int32_t>()(v.z) + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
			return h;
		}
	};

	struct Niveau {
		float inv_arete = 1.0f;
		int exposant = 0;
		// PLANAIRE (chantier "degraissage separation_lot", 2026-09-08) : quand
		// vrai, deplacer_lot force le composant Y de la case-clef a 0 lors de
		// l'insertion -- toutes les unites de la meme colonne (fx, fz) tombent
		// dans la MEME entree unordered_map, quelle que soit leur altitude.
		// separation_lot exige un niveau planaire (voir sa doc) : elle lit UNE
		// case cases[(cx, 0, cz)] par colonne cible, jamais une pile de plans Y
		// dont la plupart seraient vides -- gain massif de hashmap.find sur un
		// terrain fait de 100 000 unites entassees. Niveau non planaire (defaut) :
		// deplacer_lot insere en 3D pur, comportement historique. Le niveau du
		// deplacer (arete 16) reste 3D ; seul un second niveau dedie a la
		// separation est ouvert planaire par le banc.
		bool planaire = false;
		std::unordered_map<Vector3i, std::vector<int32_t>, Vec3iHash> cases;
		std::vector<Vector3i> case_de;
		std::vector<int32_t> idx_dans_case;
		std::vector<uint8_t> presence;
	};

	int _nombre_ids = 0;
	std::vector<Niveau> _niveaux;

protected:
	static void _bind_methods();

public:
	IndexSpatial();
	~IndexSpatial();

	// Alloue les vector case_de / idx_dans_case / presence a `nombre_ids`
	// entrees sur TOUS les niveaux (ouverts avant ou apres). A appeler AVANT
	// le premier deplacer_lot. Peut etre rappele pour agrandir le pool.
	void configurer(int nombre_ids);

	// Ouvre un niveau a `exposant` (arete = 2^exposant). No-op si deja
	// ouvert. A appeler apres `configurer` (les vector internes sont
	// dimensionnes a _nombre_ids).
	void ouvrir_niveau(int exposant);

	// Meme geste que ouvrir_niveau, mais le niveau est marque PLANAIRE (voir
	// struct Niveau::planaire). deplacer_lot y insere avec y=0 dans la clef,
	// separation_lot le lit sans jamais boucler sur l'axe Y. No-op si un niveau
	// (planaire ou non) au meme exposant est deja ouvert.
	void ouvrir_niveau_planaire(int exposant);

	// Met a jour l'index avec les positions courantes des IDs 0..count-1,
	// pour chaque niveau ouvert. count = positions.size(). Chaque ID k a
	// pour position positions[k]. Sur miss (case actuelle != case visee),
	// swap-remove + append inline. Un ID pas encore present (presence == 0)
	// est simplement ajoute. UNE passe sur tous les IDs par niveau.
	void deplacer_lot(const PackedVector3Array &positions);

	// Retourne pour le niveau `exposant` un Dictionary
	// Vector3i -> PackedInt32Array (les ids par case). Pour tests de parite
	// avec l'index GDScript. Reserve aux tests, pas au hot path.
	Dictionary cases_pour_niveau(int exposant) const;

	// SEPARATION EN LOT -- premiere brique d'IA de masse (perception +
	// intention en une passe C++). Pour chaque id, lit les cases touchees
	// par `rayon` autour de sa position (l'index est fait pour ca : voisinage
	// borne par le rayon sur chaque axe, JAMAIS de scan global) et rend une
	// direction horizontale UNITAIRE de repulsion (Y = 0). Vecteur nul si
	// aucun voisin dans rayon.
	//
	// EXIGE UN NIVEAU PLANAIRE (voir ouvrir_niveau_planaire et
	// Niveau::planaire) : la separation est planaire, elle NE BALAIE JAMAIS
	// l'axe Y. Sur un niveau 3D, deplacer_lot insererait chaque unite avec
	// son propre cy = floor(y * inv_a) -- deux unites de meme (x, z) mais
	// altitudes differentes tomberaient dans des cases distinctes et se
	// louperaient. Le niveau planaire force cy=0 dans la clef d'insertion,
	// separation_lot lit UNE case cases[(cx, 0, cz)] par colonne autour de
	// l'id -- gain massif de hashmap.find (chantier "degraissage
	// separation_lot", 2026-09-08 : ~330 000 us/frame avec balayage Y ->
	// nettement moins sur un niveau planaire, releve en jeu).
	// Aucun niveau planaire ouvert : push_error, retour a zero (contrat
	// clair, un seul chemin -- l'appelant doit ouvrir explicitement un
	// niveau planaire dedie a la separation).
	//
	// DEMI-PAIRE (meme chantier) : la force de separation est SYMETRIQUE
	// (poussee A->B = -(poussee B->A)). La passe visite chaque paire (id,
	// voisin > id) UNE fois, calcule le poids UNE fois (un sqrt au lieu de
	// deux), accumule dans out_w[id] ET (avec signe oppose) dans
	// out_w[voisin]. La normalisation, qui vivait dans des locales par id,
	// est deportee en SECONDE PASSE courte sur les count sorties -- N sqrt
	// finaux, negligeables devant N*voisins sqrt evites dans la boucle. Le
	// resultat mathematique final est identique (verrouille par
	// scripts/test_separation_cpp.gd contre l'oracle O(N^2)).
	//
	// Voisinage : sur chaque axe, cases visitees = floor((p - rayon)/arete)
	// a floor((p + rayon)/arete). Pour un rayon < arete, c'est la case de
	// l'id + jusqu'a 27 voisines (3 x 3 x 3 en 3D), typiquement 4 a 8. Le
	// choix documente le contrat : le rayon doit rester inferieur ou egal a
	// l'arete du niveau pour rester dans le regime borne ; au-dela le nombre
	// de cases visitees croit en cube. L'appelant fixe le rayon en connaissance.
	//
	// CHOIX DU NIVEAU LU (auto). separation_lot cherche parmi les niveaux
	// ouverts le PLUS PETIT dont l'arete est >= rayon -- une case couvre
	// alors le rayon sur chaque axe, la boucle interne ne voit qu'une
	// poignee de voisins. Sinon (aucun niveau assez fin ouvert) : plus
	// grande arete disponible en repli. REGLE STRUCTURELLE : l'arete d'un
	// niveau doit suivre le rayon de la requete qui le lit ; une requete
	// sur un niveau d'arete >> rayon degenere en quasi-N^2 local (chaque
	// case ramasse des milliers de candidats hors rayon). L'appelant qui
	// veut de la separation ouvre donc un niveau d'exposant adapte au
	// rayon EN PLUS du niveau du deplacer (deplacer_lot itere tous les
	// niveaux ouverts, chacun coute une passe -- prix acceptable pour la
	// baisse de la separation qui domine autrement).
	//
	// Distance : horizontale seule (dx, dz), y ignore -- les unites du
	// peuplement vivent au sol, un ecart vertical de quelques cellules
	// n'entre pas dans la separation d'un tapis d'unites. Poids classique
	// boid : diff * (rayon - d) / d, sommes puis normalisation finale.
	//
	// Utilise le PREMIER niveau ouvert (le peuplement n'en ouvre qu'un). NE
	// MODIFIE PAS l'index (const). L'appelant a du appeler deplacer_lot avec
	// les memes positions avant cet appel pour que l'index soit a jour --
	// sinon la separation lit des voisinages d'une frame en retard.
	//
	// UNE frontiere par appel : entree PackedVector3Array, sortie
	// PackedVector3Array (une direction par id). Aucun appel par unite.
	PackedVector3Array separation_lot(const PackedVector3Array &positions, float rayon) const;
};

} // namespace godot

#endif // INDEX_SPATIAL_H
