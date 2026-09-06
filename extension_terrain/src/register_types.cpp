// Point d'entree de l'extension : enregistre nos classes aupres du moteur.
// Godot appelle GDE_terrain_init au chargement de la .dll ; on y declare
// MesheurTuile pour que le GDScript puisse l'instancier.

#include "register_types.h"

#include "mesheur_tuile.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <gdextension_interface.h>

using namespace godot;

void initialize_terrain_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(MesheurTuile);
}

void uninitialize_terrain_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
// Symbole d'entree nomme dans terrain.gdextension (entry_symbol).
GDExtensionBool GDE_EXPORT GDE_terrain_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_terrain_module);
	init_obj.register_terminator(uninitialize_terrain_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
