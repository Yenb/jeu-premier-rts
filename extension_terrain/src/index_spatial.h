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

	// CHRONO TEMPORAIRE de perception_lot (a retirer une fois identifie le
	// poste couteux). UN SEUL poste : le parcours complet par agent (
	// rassemblement + test occlusion port de scripts/occlusion.gd::facteur).
	// Aucun autre sous-poste : plus d'argmin, plus de collecte-passe, plus
	// de secteurs. Expose par derniers_chronos_vue() sous la cle "occ_sep"
	// (nom conserve pour compat banc, meme si le geste est plus large que
	// l'ancienne "occlusion + separation").
	mutable int64_t _us_occ_sep = 0;

	// COMPTEURS TEMPORAIRES de vue_lot exposes par derniers_compteurs_vue() :
	//   _vue_voisins_total : somme des tailles brutes de dans_rayon_case avant
	//     filtre cone -- densite geometrique. voisins_moy = total / unites.
	//   _vue_vus_total : nombre de voisins qui atteignent l'accumulation de
	//     separation (facteur > seuil apres occlusion). Doit tomber a ~20-30
	//     en foule dense si la barriere d'occlusion mord. vus_moy = total / unites.
	//   _vue_unites_total : nombre d'unites traitees dans la frame.
	// A retirer une fois le modele d'occlusion valide et le mur identifie.
	mutable int64_t _vue_voisins_total = 0;
	mutable int64_t _vue_unites_total = 0;
	mutable int64_t _vue_vus_total = 0;

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

	// VUE = PERCEPTION (ce que l'agent voit : rayon + cone oriente + occlusion
	// selon scripts/occlusion.gd::facteur, portee mot pour mot). La sortie est
	// CE QUE CHAQUE AGENT VOIT (liste d'ids par agent), jamais une direction
	// de repulsion : la separation est un CONSOMMATEUR distinct (separation_lot).
	//
	// TROIS FILTRES CUMULES, dans cet ordre :
	// (1) DISTANCE : voisins du disque de rayon `rayon` (port de
	//     scripts/monde.gd::choses_dans_rayon -- basse/haute en cases derives
	//     de `p_i +/- rayon`, iteration du bounding box, test `d2 < rayon^2`
	//     par candidat).
	// (2) CONE : parmi ces voisins, la cible passe le cone strict si
	//     `orient . direction_vers_voisin >= cos_moitie_angle`. Patron
	//     scripts/perception.gd::_percevoir_cone_oriente.
	// (3) OCCLUSION MULTIPLICATIVE (scripts/occlusion.gd::facteur portee mot
	//     pour mot) : pour chaque cible qui passe cone, un facteur `f` dans
	//     [0,1] cumule multiplicativement l'attenuation de chaque autre voisin
	//     dont la projection sur le segment agent->cible tombe strictement dans
	//     ]0,1[ ET dont la distance laterale est <= `largeur`. La valeur
	//     multipliee est `1 - clamp(opacite[k], 0, 1)`. La cible est VUE si
	//     `f > seuil_facteur`. ORDRE LIBRE des obstacles (pas d'argmin, pas de
	//     tri, pas de bloqueurs-avec-base_k, pas de secteurs) -- le produit est
	//     commutatif, l'ordre n'a aucun effet sur le resultat.
	//
	// OPACITE PAR-ID : PackedFloat32Array de meme taille que positions,
	// opacites[k] = opacite de l'id k, aveugle au nom de la propriete (le banc
	// aplatit la colonne). Consomme par facteur() pour chaque obstacle candidat.
	//
	// ORIENTATION PAR-ID : PackedVector3Array de meme taille, vecteur unitaire
	// horizontal que l'id k regarde.
	//
	// COS_MOITIE_ANGLE : precalcule cote banc (cos(deg2rad(angle_deg/2))),
	// -1.0 pour un cone > 360 degres (sphere pure). Aucun acos en boucle.
	//
	// LARGEUR : tolerance laterale au segment cible->agent, meme sens que
	// largeur_obstacle de occlusion.gd. Un obstacle dont la distance laterale
	// depasse cette valeur ne compte pas.
	//
	// SEUIL_FACTEUR : facteur en dessous duquel la cible est ecartee (blocage
	// effectif). Convention historique du depot : 0.001 laisse passer un
	// obstacle transparent, refuse un obstacle opaque (f = 0).
	//
	// EXIGE UN NIVEAU PLANAIRE (voir ouvrir_niveau_planaire / Niveau::planaire).
	// Aucun niveau planaire ouvert : push_error, retour a listes vides.
	//
	// UN SEUL PARCOURS PAR AGENT. Voisinage local (voisins du disque) rassemble
	// et consomme dans le meme scope : il sert de liste des cibles ET de liste
	// des obstacles, aucune passe collecte distincte, aucun tri.
	//
	// UNE FRONTIERE GDScript->C++ par frame (perception_lot rend {ids, offsets}
	// pour tous les agents), pas d'appel GDScript par agent.
	//
	// Sortie CSR (Compressed Sparse Row) :
	//   Dictionary {
	//     "offsets": PackedInt32Array de taille count+1,
	//                offsets[i]..offsets[i+1] delimite les vus de l'agent i.
	//     "ids":     PackedInt32Array concatene, ids des voisins vus.
	//   }
	// Un agent qui ne voit personne a offsets[i] == offsets[i+1] (liste vide).
	Dictionary perception_lot(
			const PackedVector3Array &positions,
			const PackedVector3Array &orientations,
			const PackedFloat32Array &opacites,
			float rayon,
			float cos_moitie_angle,
			float largeur,
			float seuil_facteur) const;

	// SEPARATION_LOT : consomme une perception (ids + offsets) et rend une
	// direction unitaire horizontale de repulsion par agent. Somme ponderee
	// w = (rayon - d) / d sur ses voisins vus, normalisee. Le sqrt est
	// recalcule depuis positions -- structure compacte, pas de duplication
	// de dx/dz/d. Chaque consommateur de la perception (fuite, ciblage, ...)
	// est un cousin de cette fonction.
	PackedVector3Array separation_lot(
			const PackedVector3Array &positions,
			const PackedInt32Array &ids,
			const PackedInt32Array &offsets,
			float rayon) const;

	// Chrono interne du dernier perception_lot, en microsecondes (voir
	// declaration de _us_occ_sep plus haut). Dictionary { "occ_sep" }.
	// Temporaire : outil de diagnostic, a retirer une fois le poste couteux
	// identifie.
	Dictionary derniers_chronos_vue() const;

	// Compteurs internes du dernier vue_lot (voir declaration des mutable
	// _vue_voisins_total / _vue_unites_total). Dictionary { "voisins_total",
	// "unites_total" }. Temporaire, a retirer avec les chronos une fois le
	// vrai mur (calcul de paire vs densite) identifie.
	Dictionary derniers_compteurs_vue() const;
};

} // namespace godot

#endif // INDEX_SPATIAL_H
