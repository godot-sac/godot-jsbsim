#include "jsbsim_probe.h"

#include <exception>

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <FGFDMExec.h>
#include <initialization/FGInitialCondition.h>
#include <models/FGPropulsion.h>

using namespace godot;

void JSBSimProbe::_bind_methods() {
	ClassDB::bind_static_method("JSBSimProbe", D_METHOD("get_jsbsim_version"), &JSBSimProbe::get_jsbsim_version);
	ClassDB::bind_static_method("JSBSimProbe", D_METHOD("fly_test", "root_dir", "aircraft", "seconds"),
			&JSBSimProbe::fly_test);
}

String JSBSimProbe::get_jsbsim_version() {
	return String::utf8(JSBSim::FGJSBBase::GetVersion().c_str());
}

Dictionary JSBSimProbe::fly_test(const String &root_dir, const String &aircraft, double seconds) {
	Dictionary result;
	result["ok"] = false;
	const String root = ProjectSettings::get_singleton()->globalize_path(root_dir);

	// JSBSim throws on errors (missing files, bad XML). An exception must never leave this function: Godot is
	// built without exception support and would terminate.
	try {
		JSBSim::FGFDMExec fdm;
		fdm.SetDebugLevel(0);
		fdm.SetRootDir(SGPath::fromUtf8(root.utf8().get_data()));
		fdm.SetAircraftPath(SGPath("aircraft"));
		fdm.SetEnginePath(SGPath("engine"));
		fdm.SetSystemsPath(SGPath("systems"));
		if (!fdm.LoadModel(aircraft.utf8().get_data())) {
			result["error"] = "LoadModel failed for '" + aircraft + "' in " + root;
			return result;
		}

		// In the air near Ankara Esenboğa: 39.95 N, 32.69 E, 5000 ft, heading north, 150 kt.
		auto ic = fdm.GetIC();
		ic->SetGeodLatitudeDegIC(39.95);
		ic->SetLongitudeDegIC(32.69);
		ic->SetAltitudeASLFtIC(5000.0);
		ic->SetPsiDegIC(0.0);
		ic->SetVcalibratedKtsIC(150.0);
		if (!fdm.RunIC()) {
			result["error"] = "RunIC failed";
			return result;
		}
		fdm.GetPropulsion()->InitRunning(-1);
		fdm.SetPropertyValue("fcs/throttle-cmd-norm", 0.8);
		fdm.SetPropertyValue("fcs/mixture-cmd-norm", 1.0);

		int steps = 0;
		while (fdm.GetSimTime() < seconds) {
			if (!fdm.Run()) {
				break;
			}
			steps++;
		}

		result["ok"] = true;
		result["steps"] = steps;
		result["dt"] = fdm.GetDeltaT();
		result["sim_time"] = fdm.GetSimTime();
		const char *props[] = { "position/lat-geod-deg", "position/long-gc-deg", "position/geod-alt-ft",
			"position/h-sl-ft", "velocities/vc-kts", "attitude/psi-deg", "attitude/theta-deg", "attitude/phi-deg" };
		for (const char *name : props) {
			result[String(name)] = fdm.GetPropertyValue(name);
		}
	} catch (const std::exception &e) {
		result["error"] = String("JSBSim error: ") + String::utf8(e.what());
	} catch (...) {
		result["error"] = "JSBSim error (unknown exception)";
	}
	return result;
}
