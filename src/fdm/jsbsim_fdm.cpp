#include "jsbsim_fdm.h"

#include <cmath>
#include <exception>
#include <string>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <FGFDMExec.h>
#include <initialization/FGInitialCondition.h>
#include <models/FGPropulsion.h>

#include "fdm/jsbsim_data.h"
#include "fdm/jsbsim_logger.h"

using namespace godot;

namespace {

constexpr double FT_PER_M = 1.0 / 0.3048;
int debug_level = 0;

std::string to_std(const String &text) {
	return std::string(text.utf8().get_data());
}

// Runs `body` and turns any JSBSim exception into an error message. JSBSim throws std::exception subclasses, but
// some older code paths throw std::string. Exceptions must never reach Godot, which is built without them.
template <typename F>
bool guarded(F body, String &r_error) {
	try {
		body();
		return true;
	} catch (const std::exception &e) {
		r_error = String::utf8(e.what());
	} catch (const std::string &e) {
		r_error = String::utf8(e.c_str());
	} catch (...) {
		r_error = "unknown exception";
	}
	return false;
}

} // namespace

JSBSimFDM::JSBSimFDM() {
	jsbsim_logger::install();
}

// Defined here, where FGFDMExec is a complete type, so unique_ptr can delete it.
JSBSimFDM::~JSBSimFDM() = default;

bool JSBSimFDM::fail(const String &message) {
	last_error = message;
	UtilityFunctions::push_error("JSBSimFDM: " + message);
	return false;
}

bool JSBSimFDM::load_model(const String &aircraft, const String &data_dir) {
	fdm.reset();
	data_path = String();
	last_error = String();
	jsbsim_logger::install();

	String error;
	const String path = jsbsim_data::resolve(data_dir, error);
	if (path.is_empty()) {
		return fail(error);
	}

	bool loaded = false;
	auto exec = std::make_unique<JSBSim::FGFDMExec>();
	const bool ok = guarded([&]() {
		exec->SetDebugLevel(debug_level);
		exec->SetRootDir(SGPath::fromUtf8(to_std(path)));
		exec->SetAircraftPath(SGPath("aircraft"));
		exec->SetEnginePath(SGPath("engine"));
		exec->SetSystemsPath(SGPath("systems"));
		loaded = exec->LoadModel(to_std(aircraft));
	},
			error);
	if (!ok) {
		return fail("loading '" + aircraft + "' failed: " + error);
	}
	if (!loaded) {
		return fail("loading '" + aircraft + "' from " + path + " failed (see the JSBSim messages above)");
	}
	// std::move hands the object over to the member; `exec` is empty afterwards.
	fdm = std::move(exec);
	data_path = path;
	return true;
}

bool JSBSimFDM::is_loaded() const {
	return fdm != nullptr;
}

String JSBSimFDM::get_model_name() const {
	return fdm ? String::utf8(fdm->GetModelName().c_str()) : String();
}

String JSBSimFDM::get_data_path() const {
	return data_path;
}

String JSBSimFDM::get_last_error() const {
	return last_error;
}

void JSBSimFDM::set_initial_position(double latitude, double longitude, double height) {
	ERR_FAIL_COND_MSG(!fdm, "No model loaded.");
	auto ic = fdm->GetIC();
	ic->SetGeodLatitudeDegIC(latitude);
	ic->SetLongitudeDegIC(longitude);
	// JSBSim only sets the altitude above "sea level" (geocentric radius minus the ellipsoid radius along the same
	// line), so iterate until the geodetic height matches. Converges in 2-3 steps; tools/oracle_fly.py does the same.
	const double target = height * FT_PER_M;
	double asl = target;
	for (int i = 0; i < 10; i++) {
		ic->SetAltitudeASLFtIC(asl);
		const double error = target - ic->GetPosition().GetGeodAltitude();
		if (std::abs(error) < 1e-9) {
			break;
		}
		asl += error;
	}
}

void JSBSimFDM::set_initial_orientation(double heading, double pitch, double roll) {
	ERR_FAIL_COND_MSG(!fdm, "No model loaded.");
	auto ic = fdm->GetIC();
	ic->SetPsiDegIC(heading);
	ic->SetThetaDegIC(pitch);
	ic->SetPhiDegIC(roll);
}

void JSBSimFDM::set_initial_airspeed(double calibrated_kts) {
	ERR_FAIL_COND_MSG(!fdm, "No model loaded.");
	fdm->GetIC()->SetVcalibratedKtsIC(calibrated_kts);
}

bool JSBSimFDM::run_ic() {
	ERR_FAIL_COND_V_MSG(!fdm, false, "No model loaded.");
	bool ok = false;
	String error;
	if (!guarded([&]() { ok = fdm->RunIC(); }, error)) {
		return fail("run_ic failed: " + error);
	}
	return ok ? true : fail("run_ic failed (see the JSBSim messages above)");
}

bool JSBSimFDM::reset() {
	ERR_FAIL_COND_V_MSG(!fdm, false, "No model loaded.");
	String error;
	if (!guarded([&]() { fdm->ResetToInitialConditions(0); }, error)) {
		return fail("reset failed: " + error);
	}
	return true;
}

void JSBSimFDM::start_engines() {
	ERR_FAIL_COND_MSG(!fdm, "No model loaded.");
	String error;
	if (!guarded([&]() { fdm->GetPropulsion()->InitRunning(-1); }, error)) {
		fail("start_engines failed: " + error);
	}
}

bool JSBSimFDM::trim(int mode) {
	ERR_FAIL_COND_V_MSG(!fdm, false, "No model loaded.");
	String error;
	if (!guarded([&]() { fdm->DoTrim(mode); }, error)) {
		return fail("trim failed: " + error);
	}
	return true;
}

int JSBSimFDM::step(int count) {
	ERR_FAIL_COND_V_MSG(!fdm, 0, "No model loaded.");
	int done = 0;
	String error;
	const bool ok = guarded([&]() {
		while (done < count && fdm->Run()) {
			done++;
		}
	},
			error);
	if (!ok) {
		fail("step failed: " + error);
	}
	return done;
}

double JSBSimFDM::get_sim_time() const {
	ERR_FAIL_COND_V_MSG(!fdm, 0.0, "No model loaded.");
	return fdm->GetSimTime();
}

double JSBSimFDM::get_dt() const {
	ERR_FAIL_COND_V_MSG(!fdm, 0.0, "No model loaded.");
	return fdm->GetDeltaT();
}

void JSBSimFDM::set_dt(double dt) {
	ERR_FAIL_COND_MSG(!fdm, "No model loaded.");
	ERR_FAIL_COND_MSG(!(dt > 0.0), "dt must be positive.");
	fdm->Setdt(dt);
}

bool JSBSimFDM::has_property(const String &name) const {
	return fdm && fdm->GetPropertyManager()->HasNode(to_std(name));
}

double JSBSimFDM::get_property(const String &name) const {
	ERR_FAIL_COND_V_MSG(!fdm, 0.0, "No model loaded.");
	ERR_FAIL_COND_V_MSG(!has_property(name), 0.0, "Unknown JSBSim property: " + name);
	return fdm->GetPropertyValue(to_std(name));
}

bool JSBSimFDM::set_property(const String &name, double value) {
	ERR_FAIL_COND_V_MSG(!fdm, false, "No model loaded.");
	ERR_FAIL_COND_V_MSG(!has_property(name), false, "Unknown JSBSim property: " + name);
	// Some properties are tied to functions that act immediately (simulation/do_simple_trim) and may throw.
	String error;
	if (!guarded([&]() { fdm->SetPropertyValue(to_std(name), value); }, error)) {
		return fail("setting " + name + " failed: " + error);
	}
	return true;
}

PackedStringArray JSBSimFDM::get_property_names(const String &filter) const {
	PackedStringArray names;
	ERR_FAIL_COND_V_MSG(!fdm, names, "No model loaded.");
	// Catalog entries look like "position/h-sl-ft (RW)".
	for (const std::string &entry : fdm->GetPropertyCatalog()) {
		const String name = String::utf8(entry.substr(0, entry.rfind(" (")).c_str());
		if (filter.is_empty() || name.contains(filter)) {
			names.push_back(name);
		}
	}
	return names;
}

String JSBSimFDM::get_jsbsim_version() {
	return String::utf8(JSBSim::FGJSBBase::GetVersion().c_str());
}

void JSBSimFDM::set_log_level(int level) {
	jsbsim_logger::set_min_level(level);
}

int JSBSimFDM::get_log_level() {
	return jsbsim_logger::get_min_level();
}

void JSBSimFDM::set_debug_level(int level) {
	debug_level = level;
}

int JSBSimFDM::get_debug_level() {
	return debug_level;
}

String JSBSimFDM::resolve_data_dir(const String &data_dir) {
	String error;
	const String path = jsbsim_data::resolve(data_dir, error);
	if (path.is_empty()) {
		UtilityFunctions::push_error("JSBSimFDM: " + error);
	}
	return path;
}

String JSBSimFDM::extract_data_dir(const String &res_dir) {
	String error;
	const String path = jsbsim_data::extract(res_dir, error);
	if (path.is_empty()) {
		UtilityFunctions::push_error("JSBSimFDM: " + error);
	}
	return path;
}

void JSBSimFDM::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_model", "aircraft", "data_dir"), &JSBSimFDM::load_model,
			DEFVAL(String(DEFAULT_DATA_DIR)));
	ClassDB::bind_method(D_METHOD("is_loaded"), &JSBSimFDM::is_loaded);
	ClassDB::bind_method(D_METHOD("get_model_name"), &JSBSimFDM::get_model_name);
	ClassDB::bind_method(D_METHOD("get_data_path"), &JSBSimFDM::get_data_path);
	ClassDB::bind_method(D_METHOD("get_last_error"), &JSBSimFDM::get_last_error);
	ClassDB::bind_method(D_METHOD("set_initial_position", "latitude", "longitude", "height"),
			&JSBSimFDM::set_initial_position);
	ClassDB::bind_method(D_METHOD("set_initial_orientation", "heading", "pitch", "roll"),
			&JSBSimFDM::set_initial_orientation);
	ClassDB::bind_method(D_METHOD("set_initial_airspeed", "calibrated_kts"), &JSBSimFDM::set_initial_airspeed);
	ClassDB::bind_method(D_METHOD("run_ic"), &JSBSimFDM::run_ic);
	ClassDB::bind_method(D_METHOD("reset"), &JSBSimFDM::reset);
	ClassDB::bind_method(D_METHOD("start_engines"), &JSBSimFDM::start_engines);
	ClassDB::bind_method(D_METHOD("trim", "mode"), &JSBSimFDM::trim, DEFVAL(TRIM_FULL));
	ClassDB::bind_method(D_METHOD("step", "count"), &JSBSimFDM::step, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("get_sim_time"), &JSBSimFDM::get_sim_time);
	ClassDB::bind_method(D_METHOD("get_dt"), &JSBSimFDM::get_dt);
	ClassDB::bind_method(D_METHOD("set_dt", "dt"), &JSBSimFDM::set_dt);
	ClassDB::bind_method(D_METHOD("has_property", "name"), &JSBSimFDM::has_property);
	ClassDB::bind_method(D_METHOD("get_property", "name"), &JSBSimFDM::get_property);
	ClassDB::bind_method(D_METHOD("set_property", "name", "value"), &JSBSimFDM::set_property);
	ClassDB::bind_method(D_METHOD("get_property_names", "filter"), &JSBSimFDM::get_property_names, DEFVAL(String()));

	ClassDB::bind_static_method("JSBSimFDM", D_METHOD("get_jsbsim_version"), &JSBSimFDM::get_jsbsim_version);
	ClassDB::bind_static_method("JSBSimFDM", D_METHOD("set_log_level", "level"), &JSBSimFDM::set_log_level);
	ClassDB::bind_static_method("JSBSimFDM", D_METHOD("get_log_level"), &JSBSimFDM::get_log_level);
	ClassDB::bind_static_method("JSBSimFDM", D_METHOD("set_debug_level", "level"), &JSBSimFDM::set_debug_level);
	ClassDB::bind_static_method("JSBSimFDM", D_METHOD("get_debug_level"), &JSBSimFDM::get_debug_level);
	ClassDB::bind_static_method("JSBSimFDM", D_METHOD("resolve_data_dir", "data_dir"), &JSBSimFDM::resolve_data_dir);
	ClassDB::bind_static_method("JSBSimFDM", D_METHOD("extract_data_dir", "res_dir"), &JSBSimFDM::extract_data_dir);

	BIND_ENUM_CONSTANT(TRIM_LONGITUDINAL);
	BIND_ENUM_CONSTANT(TRIM_FULL);
	BIND_ENUM_CONSTANT(TRIM_GROUND);
	BIND_ENUM_CONSTANT(TRIM_PULLUP);
	BIND_ENUM_CONSTANT(TRIM_TURN);
	BIND_ENUM_CONSTANT(LOG_BULK);
	BIND_ENUM_CONSTANT(LOG_DEBUG);
	BIND_ENUM_CONSTANT(LOG_INFO);
	BIND_ENUM_CONSTANT(LOG_WARN);
	BIND_ENUM_CONSTANT(LOG_ERROR);
	BIND_ENUM_CONSTANT(LOG_FATAL);
}
