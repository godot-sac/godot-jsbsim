#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

// Phase 0 smoke test: proves that the extension loads the JSBSim shared library and can fly a model.
// Replaced by JSBSimFDM / JSBSimAircraft in later phases.
class JSBSimProbe : public godot::RefCounted {
	GDCLASS(JSBSimProbe, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// Version string of the loaded JSBSim library, e.g. "1.3.3".
	static godot::String get_jsbsim_version();

	// Loads `aircraft` from `root_dir` (a folder with aircraft/, engine/, systems/; res:// paths allowed), starts it
	// in the air with the engines running, flies `seconds` with fixed controls and returns the final state.
	// On failure the result has `ok = false` and `error`.
	static godot::Dictionary fly_test(const godot::String &root_dir, const godot::String &aircraft, double seconds);
};
