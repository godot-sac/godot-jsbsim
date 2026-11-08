#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "class_reference.h"
#include "editor_first_load_guard.h"
#include "fdm/jsbsim_aircraft.h"
#include "fdm/jsbsim_autopilot.h"
#include "fdm/jsbsim_fdm.h"

using namespace godot;

void initialize_godot_jsbsim(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		// Skipped when the guard is needed: the editor would crash at exit generating docs for it.
		if (!install_editor_first_load_guard()) {
			load_class_reference();
		}
		return;
	}
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(JSBSimFDM);
	GDREGISTER_CLASS(JSBSimAircraft);
	GDREGISTER_CLASS(JSBSimAutopilot);
}

void uninitialize_godot_jsbsim(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		remove_editor_first_load_guard();
		return;
	}
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
// Entry point named in addons/jsbsim/jsbsim.gdextension (entry_symbol).
GDExtensionBool GDE_EXPORT godot_jsbsim_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_godot_jsbsim);
	init_obj.register_terminator(uninitialize_godot_jsbsim);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
