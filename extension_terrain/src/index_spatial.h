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

	// SOUS-CHRONOS TEMPORAIRES de vue_lot (a retirer une fois identifie le
	// poste couteux). Le releve global `vue=` du banc enveloppe tout le corps
	// de vue_lot ; ces quatre compteurs decoupent ce corps en :
	//   _us_collecte : la boucle (2n+1)^2 de niveau.cases.find par case qui
	//                  remplit `voisinage`.
	//   _us_filtre   : le remplissage de `dans_rayon` (filtre distance +
	//                  cone elargi) par unite.
	//   _us_tri      : le std::sort de `dans_rayon` par distance croissante,
	//                  par unite.
	//   _us_occ_sep  : la double boucle occlusion + accumulation separation,
	//                  par unite.
	// La somme des quatre couvre tout le corps de vue_lot sans trou. Exposes
	// par derniers_chronos_vue() -- lus par le banc, imprimes a cote de vue=.
	mutable int64_t _us_collecte = 0;
	mutable int64_t _us_filtre = 0;
	mutable int64_t _us_tri = 0;
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
	// visuelle corps-traversee). Portage de scripts/perception.gd::_percevoir_cone_oriente
	// sur la masse en C++. La sortie est CE QUE CHAQUE AGENT VOIT (liste d'ids
	// par agent), jamais une direction de repulsion : la separation est un
	// CONSOMMATEUR distinct (voir separation_depuis_perception plus bas).
	//
	// Selection identique a l'ancienne (rayon + cone oriente + occlusion corps
	// traverse, chaque etape verrouillee par test_vue_cpp.gd) :
	// (1) voisins dans le rayon (distance horizontale strictement inferieure a
	// ), (2) filtre par cone d'angle autour de l'orientation de chaque
	// unite (cos(diff, orient) >= cos_moitie_angle, patron
	// scripts/perception.gd::_percevoir_cone_oriente), (3) test d'occlusion
	// contre les autres corps du meme voisinage 3x3 planaire (geometrie de
	// scripts/occlusion.gd::facteur portee mot pour mot -- t dans ]0,1[,
	// distance laterale <= largeur), un voisin cache par un corps plus proche
	// est RETIRE. (4) Ce qui reste dans le cone strict et non cache est ce que
	// l'agent VOIT -- son id est enregistre dans la perception.
	//
	// Sortie CSR (Compressed Sparse Row), format compact plat -- une seule
	// allocation par lot, jamais N listes :
	//   Dictionary {
	//     "offsets": PackedInt32Array de taille count+1,
	//                offsets[i]..offsets[i+1] delimite les vus de l'agent i.
	//     "vus":     PackedInt32Array concatene, ids des voisins vus.
	//   }
	// Un agent qui ne voit personne a offsets[i] == offsets[i+1] (liste vide).
	// A vus_moy ~1 en foule dense, N=100 000 -> vus ~400 Ko + offsets ~400 Ko.
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
	// OUTIL DE VOISINAGE MUTUALISE PAR CASE (patron boids : liste de voisinage
	// batie une fois par cellule, partagee entre tous les agents de la cellule).
	// Deux etapes par case :
	//   - PASSE 1a : voisinage BRUT etabli UNE fois. La liste {id, x, z} des
	//     corps du bloc (2*n_cases+1)^2 autour de la case est commune aux
	//     unites de la case courante. Un thread_local reutilise entre cases
	//     (clear + capacite gardee), aucune allocation par frame.
	//   - PASSE 1b : chaque unite de la case parcourt ce voisinage commun,
	//     calcule SES propres dx/dz (soustraction depuis sa position), teste
	//     d2<rayon2 puis PRE-FILTRE PAR LE CONE ELARGI (dot vs cos_elargi
	//     sur d2, SANS sqrt : ce qui est derriere l'agent ou hors marge sort
	//     avant tout sqrt). Le sqrt n'est paye que pour les voisins qui
	//     peuvent etre vus OU servir d'occulteur en passe 2. Le cone elargi
	//     = demi_cone_strict + atan2(largeur, rayon) garantit qu'aucun
	//     bloqueur legitime n'est perdu (un occulteur de taille `largeur` a
	//     distance `rayon` reste dans le cone elargi meme s'il est hors cone
	//     strict).
	// Ce qui reste PER-UNITE (jamais mutualisable, depend de orient_r[id]) :
	// selection par distance + occlusion visuelle corps-traversee + collecte
	// des ids vus (la separation est un consommateur separe, cf separation_lot).
	//
	// OCCLUSION VISUELLE : CORPS TRAVERSE. Un voisin J est CACHE si le segment
	// percepteur -> J traverse le VOLUME (disque horizontal rayon =
	// largeur/2) d'un corps K PLUS PROCHE que J (d_k < d_j). Un corps plus
	// loin ou lateralement decale sans traverser le segment ne cache JAMAIS
	// -- physiquement impossible. Modele "premier corps opaque bloque",
	// binaire (vu ou cache), sans opacite ni cumul. Un bloqueur hors cone
	// compte quand meme comme obstacle visuel (un corps a cote peut boucher
	// une ligne de vue), mais ne contribue pas lui-meme a la separation.
	// La densite fait tomber vus_moy : plus il y a de corps proches, plus
	// de lignes de vue sont bloquees, moins de voisins sont vus.
	//
	// DISTINCT de scripts/occlusion.gd (attenuation multiplicative pour
	// son/odeur, ou attenuer un signal a du sens). Le modele visuel binaire
	// ne s'applique JAMAIS aux canaux son/odeur ; scripts/occlusion.gd est
	// INTACT pour eux. Les parametres `opacites` et `seuil_facteur` restent
	// dans la signature de perception_lot pour compat mais ne sont plus consommes.
	//
	// Etapes de la passe 2 par unite :
	//   (1) SELECTION INCREMENTALE DU PLUS PROCHE. Pas de tas construit
	//       d'avance : a chaque tour, argmin lineaire sur les non traites +
	//       swap-remove. Cout par extraction O(reste), cout total O(K * N)
	//       avec K = nombre de voisins parcourus avant l'arret d'occlusion
	//       (petit a densite forte). Pas de passe O(N) payee AVANT de savoir
	//       combien on extrait.
	//   (2) Parcours proche->loin par l'argmin ci-dessus. Pour chaque J :
	//       (a) Preselection angulaire : pour chaque bloqueur K deja retenu,
	//           tester `vk . vj >= base_k * d_j` (avec base_k = sqrt(d2_k -
	//           r_corps2) precalcule). Contraposee sans perte du test segment-
	//           disque : ecarte les bloqueurs dont le secteur angulaire de
	//           demi-largeur asin(r_corps/d_k) ne couvre pas l'axe A->J.
	//       (b) Sur les candidats retenus, verdict final segment-disque exact
	//           -- verdict bit-a-bit identique.
	//   (3) J cache -> skip. J vu -> retenir comme bloqueur (avec son base_j),
	//       puis (si dans le cone strict) l'ajouter a la liste des vus de i.
	//   (4) MAJ union des secteurs angulaires clampes a [-demi_cone, +demi_cone].
	//       ARRET SANS PERTE quand l'union recouvre tout le cone : tous les
	//       voisins restants ont leur angle dans un secteur ferme, sont donc
	//       cachés (equivalence angulaire du segment-disque) ; les voisins
	//       hors cone restants ne contribuent pas et deviennent inutiles.
	//       C'est le levier qui realise "plus dense = moins cher".
	//
	// UNE frontiere par appel. Aucun appel par unite. Verrouille par
	// scripts/test_vue_cpp.gd (cas 5 re-verrouille par le modele corps
	// traverse : K PLUS PROCHE que J + traverse segment -> J cache).
	// PERCEPTION_LOT (ex-vue_lot) : rend, par agent, la liste des voisins VUS
	// (ceux qui passent rayon strict + cone strict + occlusion visuelle
	// corps-traverse). Sortie Dictionary { "ids", "offsets" } : voisins de
	// l'agent i = ids[offsets[i]..offsets[i+1]]. C'est de la PERCEPTION pure --
	// aucun calcul de repulsion, aucune direction. La separation devient un
	// consommateur separe (separation_lot).
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

	// Sous-chronos internes du dernier vue_lot, en microsecondes (voir
	// declaration des mutable _us_collecte / _us_filtre / _us_tri / _us_occ_sep
	// plus haut). Dictionary { "collecte", "filtre", "tri", "occ_sep" }.
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
