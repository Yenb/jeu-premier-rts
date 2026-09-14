#ifndef CHAMP_SATURATION_PLAT_H
#define CHAMP_SATURATION_PLAT_H

// Portage C++ de scripts/champ_saturation_plat.gd. Miroir bit-a-bit.
// 6eme classe extension_terrain. Rollback si divergence : bascule
// GDScript reprend.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <cstdint>
#include <vector>

namespace godot {

class ChampSaturationPlat : public RefCounted {
	GDCLASS(ChampSaturationPlat, RefCounted)

	static constexpr float EPS_COUVERT = 1.0e-6f;

	std::vector<float> _valeurs;
	int _n_non_nulles = 0;
	int _x_min = 0;
	int _z_min = 0;
	int _largeur = 0;
	int _hauteur = 0;

protected:
	static void _bind_methods();

public:
	ChampSaturationPlat();
	~ChampSaturationPlat();

	void configurer(int x_min, int z_min, int x_max, int z_max);
	void deposer(float centre_x, float centre_z, float rayon_m, float taille_case, float magnitude, int signe);
	void deposer_lot(
			const PackedFloat32Array &centres_x,
			const PackedFloat32Array &centres_z,
			const PackedFloat32Array &rayons_m,
			float taille_case,
			const PackedFloat32Array &magnitudes,
			const PackedByteArray &signes);
	void redeposer(
			float centre_x,
			float centre_z,
			float ancien_rayon_m,
			float nouveau_rayon_m,
			float taille_case,
			float ancienne_magnitude,
			float nouvelle_magnitude);
	void redeposer_lot(
			const PackedFloat32Array &centres_x,
			const PackedFloat32Array &centres_z,
			const PackedFloat32Array &anciens_rayons_m,
			const PackedFloat32Array &nouveaux_rayons_m,
			float taille_case,
			const PackedFloat32Array &anciennes_magnitudes,
			const PackedFloat32Array &nouvelles_magnitudes);
	float lire(float x, float z, float taille_case) const;
	PackedFloat32Array lire_lot(
			const PackedFloat32Array &positions_x,
			const PackedFloat32Array &positions_z,
			float taille_case) const;
	int nombre_cases() const;
};

} // namespace godot

#endif // CHAMP_SATURATION_PLAT_H
