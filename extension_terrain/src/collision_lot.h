#ifndef COLLISION_LOT_H
#define COLLISION_LOT_H

// Portage C++ de jeu/Proto/collision.gd::detecter + resoudre.
// MIROIR NATIF -- collision.gd reste l'oracle de parite bit-a-bit
// (scripts/test_collision_lot_cpp.gd), plus un chemin de prod.
//
// CANEVAS ADN : porte le narrowphase GENERALISTE des le premier jet.
// Sphere, boite, capsule, hull ; orientation != Identity ; raccourci boite-boite
// AABB alignee = chemin rapide INTERNE, jamais l'unique chemin.
//
// PATRON godot-cpp identique a PhysiqueSimpleLot / IndexSpatial :
// GDCLASS(RefCounted), Dictionary d'entree/sortie, Packed*Array (ptrw/ptr,
// zero boxing Variant), une frontiere par appel.
//
// PARITE BIT-A-BIT : composantes Vector3 en real_t (float 32 par defaut godot-cpp),
// scalaires temporaires en DOUBLE avec promotion explicite (double)vec.dot(other)
// aux memes points que GDScript (`var d: float = n.dot(a)` promeut real_t -> double).
// L'ordre des operations Vector3 et l'ordre de parcours des supports/faces/aretes
// suit collision.gd ligne a ligne.
//
// SOA EN FRONTIERE : l'appelant decompose les entites en colonnes plates avant
// l'appel. Aucun Array de Dictionary boxe. Voir en-tete de detecter/resoudre pour
// les cles attendues.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <cstdint>

namespace godot {

class CollisionLot : public RefCounted {
	GDCLASS(CollisionLot, RefCounted)

	// CHRONOS TEMPORAIRES par appel, exposes par derniers_chronos(). Trois postes :
	// broadphase (counting sort + iteration 3x3x3 + filtres AABB/masque/dedup),
	// narrowphase (contact_forme_paire, GJK/EPA/raccourci), resoudre.
	// Somme = temps total detecter + resoudre. A retirer une fois le poste
	// dominant identifie.
	mutable int64_t _us_broadphase = 0;
	mutable int64_t _us_narrowphase = 0;
	mutable int64_t _us_resoudre = 0;

protected:
	static void _bind_methods();

public:
	CollisionLot();
	~CollisionLot();

	// DETECTER : broadphase locale + narrowphase, rend les contacts bruts.
	// Miroir de jeu/Proto/collision.gd::detecter(entites, delta).
	//
	// Cles attendues dans `entree` :
	//   "positions"        PackedVector3Array (N)
	//   "velocites"        PackedVector3Array (N)
	//   "orientations"     PackedFloat32Array (9*N, Basis row-major :
	//                      rows[0].x rows[0].y rows[0].z rows[1].x ...
	//                      rows[2].z ; identite = 1 0 0 0 1 0 0 0 1)
	//   "masques_c"        PackedInt32Array (N)   -- masque_collision
	//   "masques_r"        PackedInt32Array (N)   -- masque_reponse
	//   "reponses"         PackedByteArray (N)    -- 1 si "bloque", 0 sinon
	//   "formes_debut"     PackedInt32Array (N+1) -- offsets dans les pools formes
	//                      formes de l'entite i = [formes_debut[i], formes_debut[i+1])
	//   "formes_type"      PackedInt32Array (M) : 0=sphere 1=boite 2=capsule 3=hull
	//   "formes_tf_locale" PackedFloat32Array (12*M, Transform3D aplati :
	//                      basis row-major (9) puis origin (3))
	//   "formes_params"    PackedFloat32Array (4*M) :
	//                        sphere  : [rayon, 0, 0, 0]
	//                        boite   : [demi_x, demi_y, demi_z, 0]
	//                        capsule : [rayon, hauteur, 0, 0]
	//                        hull    : [debut_index_hull_points, count, 0, 0]
	//   "hull_points"      PackedVector3Array -- pool total des sommets hull
	//   "delta"            float
	//
	// Sortie :
	//   "contacts_a"          PackedInt32Array (K) -- indice entite A
	//   "contacts_b"          PackedInt32Array (K)
	//   "contacts_normale"    PackedVector3Array (K) -- unitaire, sens A->B
	//   "contacts_profondeur" PackedFloat32Array (K)
	Dictionary detecter(const Dictionary &entree) const;

	// RESOUDRE : mute les positions selon les contacts. Miroir de
	// jeu/Proto/collision.gd::resoudre(contacts, entites).
	//
	// Cles attendues :
	//   "positions"           PackedVector3Array (N) -- entree, sera mutee
	//   "velocites"           PackedVector3Array (N) -- lu pour vel_nz
	//   "reponses"            PackedByteArray (N)
	//   "masques_r"           PackedInt32Array (N)
	//   "contacts_a"          PackedInt32Array (K)
	//   "contacts_b"          PackedInt32Array (K)
	//   "contacts_normale"    PackedVector3Array (K)
	//   "contacts_profondeur" PackedFloat32Array (K)
	//
	// Sortie :
	//   "positions"           PackedVector3Array (N) -- positions mutees
	Dictionary resoudre(const Dictionary &entree) const;

	// Chronos du dernier appel (broadphase + narrowphase venant du dernier
	// detecter, resoudre venant du dernier resoudre). Dictionary { "broadphase",
	// "narrowphase", "resoudre" } en microsecondes.
	Dictionary derniers_chronos() const;
};

} // namespace godot

#endif // COLLISION_LOT_H
