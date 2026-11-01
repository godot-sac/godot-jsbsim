#include "jsbsim_aircraft.h"

#include <algorithm>
#include <cmath>

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <FGFDMExec.h>
#include <models/FGFCS.h>
#include <models/FGInertial.h>
#include <models/FGPropagate.h>

using namespace godot;
using namespace gjsb::geo;

namespace {

constexpr double M_PER_FT = 0.3048;
// Upper bound for steps in one advance() call, so a long hitch (debugger, loading) does not freeze the game.
constexpr int MAX_STEPS_PER_ADVANCE = 2400;
// Beyond these the state is treated as invalid. After a hard ground impact JSBSim's state grows huge (1e34 m) for a
// few steps before it becomes NaN.
constexpr double MAX_ECEF_DISTANCE = 1e9; // m, well past the Moon's orbit
constexpr double MAX_SPEED = 1e5; // m/s

bool is_finite(const Vec3 &v) {
	return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z);
}

Vec3 to_vec3(const JSBSim::FGColumnVector3 &v, double scale = 1.0) {
	// JSBSim vectors and matrices are 1-based.
	return { v(1) * scale, v(2) * scale, v(3) * scale };
}

Vector3 to_vector3(const Vec3 &v) {
	return Vector3(real_t(v.x), real_t(v.y), real_t(v.z));
}

Mat3 to_mat3(const JSBSim::FGMatrix33 &m) {
	Mat3 r;
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			r.m[i][j] = m(i + 1, j + 1);
		}
	}
	return r;
}

// Moves a trimmed command into its trim property (pitch trim, ...), so the pilot's stick can be centred at 0 while
// the surfaces keep the trimmed deflection. The Aeromatic control systems add the two.
void transfer_trim(JSBSimFDM *fdm, const char *command, const char *trim) {
	if (fdm->has_property(command) && fdm->has_property(trim)) {
		fdm->set_property(trim, fdm->get_property(trim) + fdm->get_property(command));
		fdm->set_property(command, 0.0);
	}
}

} // namespace

JSBSimAircraft::JSBSimAircraft() {
	fdm.instantiate();
}

void JSBSimAircraft::_ready() {
	if (Engine::get_singleton()->is_editor_hint()) {
		return;
	}
	start();
}

bool JSBSimAircraft::start() {
	started = false;
	failed = false;
	if (!fdm->load_model(aircraft, data_dir)) {
		return false;
	}
	if (!apply_initial_condition()) {
		return false;
	}
	started = true;
	return true;
}

bool JSBSimAircraft::restart() {
	ERR_FAIL_COND_V_MSG(!fdm->is_loaded(), false, "JSBSimAircraft: start() has not succeeded.");
	if (failed) {
		// After an invalid state some JSBSim models keep NaNs that ResetToInitialConditions does not clear.
		return start();
	}
	return apply_initial_condition();
}

bool JSBSimAircraft::apply_initial_condition() {
	double lat = origin_latitude;
	double lon = origin_longitude;
	double h = origin_height;
	if (!geo_origin_path.is_empty()) {
		Node *origin = get_node_or_null(geo_origin_path);
		ERR_FAIL_NULL_V_MSG(origin, false, "JSBSimAircraft: geo_origin_path does not point to a node.");
		lat = origin->get("latitude");
		lon = origin->get("longitude");
		h = origin->get("height");
	}
	frame = LocalFrame({ Math::deg_to_rad(lat), Math::deg_to_rad(lon), h });

	JSBSim::FGFDMExec *exec = fdm->get_exec();
	// Flat ground at the origin's height (the default ground callback uses height above the ellipsoid).
	exec->GetInertial()->SetTerrainElevation(h / M_PER_FT);
	fdm->set_initial_position(latitude, longitude, height);
	fdm->set_initial_orientation(heading, 0.0, 0.0);
	fdm->set_initial_airspeed(airspeed);
	// reset() rather than run_ic(): it also sets the sim time to 0 and reinitialises the models (restart()).
	if (!fdm->reset()) {
		return false;
	}
	fdm->start_engines();
	if (fdm->has_property("fcs/mixture-cmd-norm")) {
		fdm->set_property("fcs/mixture-cmd-norm", 1.0);
	}
	aileron = elevator = rudder = 0.0;
	if (trim_on_start) {
		exec->GetFCS()->SetThrottleCmd(-1, throttle);
		if (fdm->trim(JSBSimFDM::TRIM_FULL)) {
			transfer_trim(fdm.ptr(), "fcs/elevator-cmd-norm", "fcs/pitch-trim-cmd-norm");
			transfer_trim(fdm.ptr(), "fcs/aileron-cmd-norm", "fcs/roll-trim-cmd-norm");
			transfer_trim(fdm.ptr(), "fcs/rudder-cmd-norm", "fcs/yaw-trim-cmd-norm");
			throttle = fdm->get_property("fcs/throttle-cmd-norm");
		}
		// A failed trim is reported by JSBSimFDM; the aircraft still flies, untrimmed.
	}
	apply_controls();
	accumulator = 0.0;
	failed = false;
	return update_transform();
}

void JSBSimAircraft::_physics_process(double delta) {
	if (started && !failed && !paused) {
		advance(delta);
	}
}

int JSBSimAircraft::advance(double delta) {
	ERR_FAIL_COND_V_MSG(!started, 0, "JSBSimAircraft: start() has not succeeded.");
	if (failed) {
		return 0;
	}
	accumulator += delta * time_scale;
	const double dt = 1.0 / rate;
	int count = int(std::floor(accumulator / dt + 1e-9));
	if (count > MAX_STEPS_PER_ADVANCE) {
		count = MAX_STEPS_PER_ADVANCE;
		accumulator = 0.0;
	} else {
		accumulator = std::max(0.0, accumulator - count * dt);
	}
	if (count == 0) {
		return 0;
	}
	apply_controls();
	const int done = fdm->step(count);
	update_transform();
	return done;
}

void JSBSimAircraft::apply_controls() {
	JSBSim::FGFDMExec *exec = fdm->get_exec();
	if (!exec) {
		return;
	}
	exec->Setdt(1.0 / rate);
	auto fcs = exec->GetFCS();
	fcs->SetDaCmd(aileron);
	fcs->SetDeCmd(elevator);
	fcs->SetDrCmd(-rudder); // JSBSim: positive rudder command yaws left
	fcs->SetThrottleCmd(-1, throttle);
}

bool JSBSimAircraft::update_transform() {
	JSBSim::FGFDMExec *exec = fdm->get_exec();
	auto propagate = exec->GetPropagate();
	const Mat3 ecef_to_enu = frame.rotation().transposed();

	const Vec3 ecef = to_vec3(propagate->GetLocation(), M_PER_FT);
	const Mat3 body = to_mat3(propagate->GetTb2ec()); // columns: forward, right, down in ECEF
	const Vec3 velocity = to_vec3(propagate->GetECEFVelocity(), M_PER_FT);
	bool valid = is_finite(ecef) && is_finite(velocity) && ecef.length() < MAX_ECEF_DISTANCE &&
			velocity.length() < MAX_SPEED;
	for (int i = 0; i < 3; i++) {
		valid = valid && is_finite(body.column(i));
	}
	if (!valid) {
		if (!failed) {
			failed = true;
			const String reason = "JSBSim state is invalid at t = " + String::num(fdm->get_sim_time(), 3) +
					" s (usually a hard ground impact); call restart()";
			UtilityFunctions::push_warning("JSBSimAircraft: " + reason);
			emit_signal("failed", reason);
		}
		return false;
	}
	const Vec3 forward = enu_to_godot(ecef_to_enu * body.column(0));
	const Vec3 right = enu_to_godot(ecef_to_enu * body.column(1));
	const Vec3 down = enu_to_godot(ecef_to_enu * body.column(2));
	// Godot node axes: +X right, +Y up, +Z backward (same as godot-dis DisGeoOrigin::body_matrix_to_basis).
	const Basis basis(to_vector3(right), to_vector3(down * -1.0), to_vector3(forward * -1.0));
	set_transform(Transform3D(basis, to_vector3(enu_to_godot(frame.ecef_to_enu(ecef)))));

	linear_velocity = to_vector3(enu_to_godot(ecef_to_enu * velocity));
	const Vec3 rates = body * to_vec3(propagate->GetPQR());
	angular_velocity = to_vector3(enu_to_godot(ecef_to_enu * rates));
	return true;
}

PackedFloat64Array JSBSimAircraft::get_geodetic_position() const {
	PackedFloat64Array result;
	if (!fdm->is_loaded()) {
		return result;
	}
	result.push_back(fdm->get_property("position/lat-geod-deg"));
	result.push_back(fdm->get_property("position/long-gc-deg"));
	result.push_back(fdm->get_property("position/geod-alt-ft") * M_PER_FT);
	return result;
}

void JSBSimAircraft::set_rate(double value) {
	ERR_FAIL_COND_MSG(!(value > 0.0), "rate must be positive.");
	rate = value;
}

void JSBSimAircraft::set_time_scale(double value) {
	ERR_FAIL_COND_MSG(value < 0.0, "time_scale must not be negative.");
	time_scale = value;
}

void JSBSimAircraft::set_aileron(double value) {
	aileron = Math::clamp(value, -1.0, 1.0);
}

void JSBSimAircraft::set_elevator(double value) {
	elevator = Math::clamp(value, -1.0, 1.0);
}

void JSBSimAircraft::set_rudder(double value) {
	rudder = Math::clamp(value, -1.0, 1.0);
}

void JSBSimAircraft::set_throttle(double value) {
	throttle = Math::clamp(value, 0.0, 1.0);
}

#define BIND_PROPERTY(m_type, m_name, m_hint, m_hint_string)                                                  \
	ClassDB::bind_method(D_METHOD("set_" #m_name, "value"), &JSBSimAircraft::set_##m_name);                    \
	ClassDB::bind_method(D_METHOD("get_" #m_name), &JSBSimAircraft::get_##m_name);                             \
	ADD_PROPERTY(PropertyInfo(Variant::m_type, #m_name, m_hint, m_hint_string), "set_" #m_name, "get_" #m_name)

void JSBSimAircraft::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start"), &JSBSimAircraft::start);
	ClassDB::bind_method(D_METHOD("restart"), &JSBSimAircraft::restart);
	ClassDB::bind_method(D_METHOD("is_started"), &JSBSimAircraft::is_started);
	ClassDB::bind_method(D_METHOD("is_failed"), &JSBSimAircraft::is_failed);
	ADD_SIGNAL(MethodInfo("failed", PropertyInfo(Variant::STRING, "reason")));
	ClassDB::bind_method(D_METHOD("advance", "delta"), &JSBSimAircraft::advance);
	ClassDB::bind_method(D_METHOD("get_fdm"), &JSBSimAircraft::get_fdm);
	ClassDB::bind_method(D_METHOD("get_linear_velocity"), &JSBSimAircraft::get_linear_velocity);
	ClassDB::bind_method(D_METHOD("get_angular_velocity"), &JSBSimAircraft::get_angular_velocity);
	ClassDB::bind_method(D_METHOD("get_geodetic_position"), &JSBSimAircraft::get_geodetic_position);

	ADD_GROUP("Model", "");
	BIND_PROPERTY(STRING, aircraft, PROPERTY_HINT_NONE, "");
	BIND_PROPERTY(STRING, data_dir, PROPERTY_HINT_DIR, "");
	ADD_GROUP("Initial Condition", "");
	BIND_PROPERTY(FLOAT, latitude, PROPERTY_HINT_RANGE, "-90,90,0.000001,suffix:°");
	BIND_PROPERTY(FLOAT, longitude, PROPERTY_HINT_RANGE, "-180,180,0.000001,suffix:°");
	BIND_PROPERTY(FLOAT, height, PROPERTY_HINT_RANGE, "-500,20000,0.1,or_greater,suffix:m");
	BIND_PROPERTY(FLOAT, heading, PROPERTY_HINT_RANGE, "0,360,0.1,suffix:°");
	BIND_PROPERTY(FLOAT, airspeed, PROPERTY_HINT_RANGE, "0,600,0.1,or_greater,suffix:kt");
	BIND_PROPERTY(BOOL, trim_on_start, PROPERTY_HINT_NONE, "");
	ADD_GROUP("Origin", "");
	BIND_PROPERTY(NODE_PATH, geo_origin_path, PROPERTY_HINT_NONE, "");
	BIND_PROPERTY(FLOAT, origin_latitude, PROPERTY_HINT_RANGE, "-90,90,0.000001,suffix:°");
	BIND_PROPERTY(FLOAT, origin_longitude, PROPERTY_HINT_RANGE, "-180,180,0.000001,suffix:°");
	BIND_PROPERTY(FLOAT, origin_height, PROPERTY_HINT_RANGE, "-500,9000,0.1,suffix:m");
	ADD_GROUP("Simulation", "");
	BIND_PROPERTY(FLOAT, rate, PROPERTY_HINT_RANGE, "10,1000,1,suffix:Hz");
	BIND_PROPERTY(FLOAT, time_scale, PROPERTY_HINT_RANGE, "0,16,0.01");
	ClassDB::bind_method(D_METHOD("set_paused", "value"), &JSBSimAircraft::set_paused);
	ClassDB::bind_method(D_METHOD("is_paused"), &JSBSimAircraft::is_paused);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "paused"), "set_paused", "is_paused");
	ADD_GROUP("Controls", "");
	BIND_PROPERTY(FLOAT, aileron, PROPERTY_HINT_RANGE, "-1,1,0.01");
	BIND_PROPERTY(FLOAT, elevator, PROPERTY_HINT_RANGE, "-1,1,0.01");
	BIND_PROPERTY(FLOAT, rudder, PROPERTY_HINT_RANGE, "-1,1,0.01");
	BIND_PROPERTY(FLOAT, throttle, PROPERTY_HINT_RANGE, "0,1,0.01");
}
