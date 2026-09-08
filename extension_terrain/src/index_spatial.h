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

	// VUE (cone_oriente) + OCCLUSION EN LOT (chantier "vue avec occlusion en
	// C++", 2026-09-08). UN SEUL PARCOURS DU VOISINAGE PAR FRAME, fait tout :
	// (1) voisins dans le rayon (distance horizontale strictement inferieure a
	// ), (2) filtre par cone d'angle autour de l'orientation de chaque
	// unite (cos(diff, orient) >= cos_moitie_angle, patron
	// scripts/perception.gd::_percevoir_cone_oriente), (3) test d'occlusion
	// contre les autres corps du meme voisinage 3x3 planaire (geometrie de
	// scripts/occlusion.gd::facteur portee mot pour mot -- t dans ]0,1[,
	// distance laterale <= largeur, cumul multiplicatif de (1 - opacite)), un
	// voisin dont le facteur final <=  est RETIRE, (4)
	// accumulation de la separation dans le MEME parcours -- les voisins vus
	// sont deja la, aucun re-parcours. Sortie normalisee en direction unitaire
	// horizontale (Y=0) par unite.
	//
	// OBSTACLES = voisinage courant : JAMAIS une requete spatiale par paire
	// percepteur-voisin (ce serait le piege n^2 documente dans le prompt). Les
	// obstacles sont les corps deja lus dans les cases 3x3 planaires visitees.
	//
	// OPACITE PAR-ID :  est un PackedFloat32Array de meme taille que
	// , opacites[k] est l'opacite de l'id k. Aveugle au nom de la
	// propriete du monde -- c'est l'appelant (banc) qui aplatit la propriete
	// en colonne AVANT l'appel. Ce fichier ne connait aucun nom de propriete.
	//
	// ORIENTATION PAR-ID :  est un PackedVector3Array de meme
	// taille, orientations[k] est le vecteur unitaire (horizontal) que l'id k
	// regarde. Le banc alimente cette colonne (typiquement la direction de
	// deplacement d'errance).
	//
	// COS_MOITIE_ANGLE : precalcule cote banc (cos(deg2rad(angle_deg/2))),
	// -1.0 pour un cone > 360 degres (sphere pure). Aucun acos en boucle.
	//
	// EXIGE UN NIVEAU PLANAIRE (voir ouvrir_niveau_planaire / Niveau::planaire).
	// Aucun niveau planaire ouvert : push_error, retour a directions nulles.
	//
	// UNE frontiere par appel. Aucun appel par unite. Verrouille par
	// scripts/test_vue_cpp.gd contre l'oracle GDScript.
	PackedVector3Array vue_lot(
			const PackedVector3Array &positions,
			const PackedVector3Array &orientations,
			const PackedFloat32Array &opacites,
			float rayon,
			float cos_moitie_angle,
			float largeur,
			float seuil_facteur) const;
};

} // namespace godot

#endif // INDEX_SPATIAL_H
