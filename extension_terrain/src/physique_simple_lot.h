#ifndef PHYSIQUE_SIMPLE_LOT_H
#define PHYSIQUE_SIMPLE_LOT_H

// Physique du profil "simple" en C++, une passe sur count unites.
// MIROIR NATIF de jeu/bancs/banc_peuplement.gd::physique_et_buffer (elle-meme
// miroir de scripts/mouvement_kinematic.gd::pas_simple_lot). Si l'un change,
// les DEUX autres doivent changer aussi. La parite est verrouillee par
// scripts/test_physique_simple_lot_cpp.gd.
//
// extension_terrain regroupe desormais tout le hot path natif du peuplement +
// terrain : mesheur du terrain (MesheurTuile) ET boucle physique du profil
// simple (PhysiqueSimpleLot). Une seule .dll, un seul SConstruct, un seul
// register_types. Ecart framework deja assume pour extension_terrain (voir
// CLAUDE.md § Frontiere).
//
// PATRON godot-cpp identique au mesheur : GDCLASS(RefCounted), entree/sortie
// Dictionary + Packed*Array, une frontiere par appel, aucun etat entre appels
// (contrairement au mesheur qui garde des buffers reutilises -- ici la boucle
// travaille sur les Packed*Array de l'appelant, deja alloues, deja
// dimensionnes). L'appelant garde le chemin GDScript comme oracle et rollback
// (@export utilise_cpp cote banc_peuplement).
//
// REPLI SUR MISS (case NAN ou plafonnee dans la table de sol) : cette classe
// N'APPELLE JAMAIS carte.sommet_sous -- c'est une autre fonction du coeur,
// hors perimetre C++. A la place, chaque indice qui a eu au MOINS un miss
// (sur les 3 tests sol : sous les pieds, devant, apres le pas) est renvoye
// dans "indices_a_repasser". Le C++ ne mute PAS ses colonnes ni son slot
// buffer -- GDScript rejoue physique_et_buffer GDScript pour CES indices
// seuls, apres l'appel, exactement comme le chemin non-CPP. En regime chaud
// (table stable), la liste est presque toujours vide.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class PhysiqueSimpleLot : public RefCounted {
	GDCLASS(PhysiqueSimpleLot, RefCounted)

protected:
	static void _bind_methods();

public:
	PhysiqueSimpleLot();
	~PhysiqueSimpleLot();

	// Cles attendues dans `entree` :
	//   "position"           PackedVector3Array (mutee -- rendue mutee)
	//   "velocite"           PackedVector3Array (mutee -- rendue mutee)
	//   "desiree"            PackedVector3Array (lue seulement)
	//   "au_sol"             PackedByteArray    (mutee -- rendue mutee)
	//   "slot"               PackedInt32Array   (lue seulement)
	//   "buffer"             PackedFloat32Array (mutee sur 3 floats par slot
	//                                            actif -- rendue mutee)
	//   "count"              int
	//   "gravite"            float
	//   "delta"              float
	//   "vitesse_terminale"  float (constante du profil simple, |vt| : le C++
	//                        applique -vt sur vy comme le miroir GDScript)
	//   "table"              PackedFloat32Array (table plate de sol, meme
	//                        format et indexation que
	//                        carte_terrain.gd::table_sommet)
	//   "demi_cote"          int
	//   "cote"               float
	//
	// Sortie :
	//   "position"                Packed*Array mutees (a reassigner dans les
	//   "velocite"                colonnes cote appelant, patron CoW)
	//   "au_sol"
	//   "buffer"
	//   "indices_a_repasser"      PackedInt32Array : indices d'unites qui ont
	//                             eu >=1 miss sur la table de sol -- l'appelant
	//                             rejoue la physique GDScript pour eux seuls,
	//                             leurs colonnes et leur slot buffer n'ont PAS
	//                             ete touches par le C++.
	Dictionary pas_simple_lot(const Dictionary &entree) const;
};

} // namespace godot

#endif // PHYSIQUE_SIMPLE_LOT_H
