#include "jsbsim_aircraft.h"

#include <algorithm>
#include <chrono>
#include <cmath>

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <FGFDMExec.h>
#include <initialization/FGInitialCondition.h>
#include <input_output/FGGroundCallback.h>
#include <models/FGAccelerations.h>
#include <models/FGFCS.h>
#include <models/FGGroundReactions.h>
#include <models/FGInertial.h>
#include <models/FGLGear.h>
#include <models/FGPropagate.h>

#include "fdm/jsbsim_autopilot.h"

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
// Start positions farther than this from the scene origin get a warning: the flat ground plane is 200 m above the
// ellipsoid at 50 km (d² / 2R).
constexpr double MAX_ORIGIN_DISTANCE = 50000.0; // m
// DIS entity appearance, air platform: bits 3-4 damage (3 = destroyed).
constexpr int64_t APPEARANCE_DAMAGE_MASK = 3 << 3;
constexpr int64_t APPEARANCE_DESTROYED = 3 << 3;
// godot-dis DisEntity::VELOCITY_MANUAL
constexpr int DIS_VELOCITY_MANUAL = 1;

bool is_finite(const Vec3 &v) {
	return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z);
}

Vec3 to_vec3(const JSBSim::FGColumnVector3 &v, double scale = 1.0) {
	// JSBSim vectors and matrices are 1-based.
	return { v(1) * scale, v(2) * scale, v(3) * scale };
}

Vec3 to_vec3(const JSBSim::FGLocation &l, double scale) {
	return { l(1) * scale, l(2) * scale, l(3) * scale };
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

// JSBSim asks this for the ground under every gear contact point and under the aircraft: we answer with the scene's
// ground (JSBSimAircraft::get_ground_height), converted between JSBSim's ECEF feet and the scene frame. Owned by
// JSBSim's FGInertial, which deletes it with the model.
class JSBSimGroundCallback : public JSBSim::FGGroundCallback {
public:
	JSBSimGroundCallback(const JSBSimAircraft *p_owner, double p_semimajor, double p_semiminor) :
			owner(p_owner), semimajor(p_semimajor), semiminor(p_semiminor) {}

	double GetAGLevel(double t, const JSBSim::FGLocation &location, JSBSim::FGLocation &contact,
			JSBSim::FGColumnVector3 &normal, JSBSim::FGColumnVector3 &velocity,
			JSBSim::FGColumnVector3 &angular_velocity) const override {
		// The ground does not move (in the Earth-fixed frame).
		velocity.InitMatrix();
		angular_velocity.InitMatrix();
		const LocalFrame &frame = owner->frame;
		const Vec3 p = enu_to_godot(frame.ecef_to_enu(to_vec3(location, M_PER_FT)));
		const double h = owner->get_ground_height(p.x, p.z);
		// Contact point straight below in the scene, which is the local vertical within a fraction of a degree.
		const Vec3 ground = frame.enu_to_ecef(godot_to_enu({ p.x, h, p.z })) * (1.0 / M_PER_FT);
		contact = JSBSim::FGLocation(JSBSim::FGColumnVector3(ground.x, ground.y, ground.z));
		contact.SetEllipse(semimajor, semiminor);
		const double agl = p.y - h;
		// The normal only matters near the ground (JSBSim's gear model uses it for the strut direction and the
		// compression speed: a vertical normal on a slope gives false damping, JSBSim discussion #1510).
		// Everything is computed from this call's location only: no state is kept between calls.
		Vec3 up{ 0.0, 1.0, 0.0 };
		if (agl < NORMAL_RANGE) {
			up = owner->ground_normal(p.x, p.z);
		}
		const Vec3 n = frame.rotation() * godot_to_enu(up);
		normal = JSBSim::FGColumnVector3(n.x, n.y, n.z);
		return agl / M_PER_FT;
	}

private:
	static constexpr double NORMAL_RANGE = 100.0; // m
	const JSBSimAircraft *owner;
	double semimajor;
	double semiminor;
};

JSBSimAircraft::JSBSimAircraft() {
	fdm.instantiate();
}

JSBSimAircraft::~JSBSimAircraft() {
	// get_fdm() hands the FDM out, so it may outlive this node: give it back JSBSim's own ground, which does not
	// point here (the ground callback below keeps a pointer to its aircraft).
	JSBSim::FGFDMExec *exec = fdm->get_exec();
	if (exec) {
		auto inertial = exec->GetInertial();
		inertial->SetGroundCallback(
				new JSBSim::FGDefaultGroundCallback(inertial->GetSemimajor(), inertial->GetSemiminor()));
	}
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
	crashed = false;
	if (!fdm->load_model(aircraft, data_dir)) {
		return false;
	}
	start_throttle = throttle;
	if (!apply_initial_condition()) {
		return false;
	}
	started = true;
	return true;
}

bool JSBSimAircraft::restart() {
	ERR_FAIL_COND_V_MSG(!fdm->is_loaded(), false, "JSBSimAircraft: start() has not succeeded.");
	if (failed || crashed) {
		// After an invalid state or a crash some JSBSim models keep NaNs or broken engine and gear states that
		// ResetToInitialConditions does not clear.
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
	// The scene is a tangent plane at the origin: far from it the flat ground (and float precision) are off.
	const Vec3 start = frame.ecef_to_enu(geodetic_to_ecef({ Math::deg_to_rad(latitude), Math::deg_to_rad(longitude), h }));
	const double distance = std::hypot(start.x, start.y);
	if (distance > MAX_ORIGIN_DISTANCE) {
		UtilityFunctions::push_warning(vformat("JSBSimAircraft: the start is %.0f km from the scene origin; set "
											   "origin_latitude / origin_longitude (or geo_origin_path) near the aircraft.",
				distance / 1000.0));
	}

	ground_id = ObjectID();
	ground_has_normal = false;
	if (!ground_path.is_empty()) {
		Node *ground = get_node_or_null(ground_path);
		ERR_FAIL_NULL_V_MSG(ground, false, "JSBSimAircraft: ground_path does not point to a node.");
		ERR_FAIL_COND_V_MSG(!ground->has_method("height_at"), false,
				"JSBSimAircraft: the ground_path node has no height_at(x, z) method.");
		ground_id = ground->get_instance_id();
		ground_has_normal = ground->has_method("normal_at");
	}

	JSBSim::FGFDMExec *exec = fdm->get_exec();
	auto inertial = exec->GetInertial();
	inertial->SetGroundCallback(new JSBSimGroundCallback(this, inertial->GetSemimajor(), inertial->GetSemiminor()));
	auto ic = exec->GetIC();
	if (start_on_ground) {
		fdm->set_initial_position(latitude, longitude, 0.0);
		// The ground trim below settles the height on the gear; start a little above to avoid a deep compression.
		ic->SetAltitudeAGLFtIC(1.0);
		fdm->set_initial_orientation(heading, 0.0, 0.0);
		fdm->set_initial_airspeed(0.0);
	} else {
		fdm->set_initial_position(latitude, longitude, height);
		fdm->set_initial_orientation(heading, 0.0, 0.0);
		fdm->set_initial_airspeed(airspeed);
	}
	// reset() rather than run_ic(): it also sets the sim time to 0 and reinitialises the models (restart()).
	if (!fdm->reset()) {
		return false;
	}
	fdm->start_engines();
	if (fdm->has_property("fcs/mixture-cmd-norm")) {
		fdm->set_property("fcs/mixture-cmd-norm", 1.0);
	}
	aileron = elevator = rudder = brake = 0.0;
	if (autopilot) {
		autopilot->reset_loops();
	}
	crashed = false;
	if (start_on_ground) {
		throttle = 0.0;
		apply_controls();
		if (trim_on_start) {
			fdm->trim(JSBSimFDM::TRIM_GROUND);
		}
	} else {
		throttle = start_throttle; // restart() begins like start(), not with the throttle of the last flight
	}
	if (!start_on_ground && trim_on_start) {
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
	// The wind after the trim: JSBSim's trim does not converge with a crosswind and resets the winds. The aircraft
	// meets the wind as a gust at the start and settles within seconds.
	apply_atmosphere();
	accumulator = 0.0;
	failed = false;
	const bool valid = update_transform();
	update_dis_entities();
	return valid;
}

void JSBSimAircraft::_physics_process(double delta) {
	if (started && !failed && !crashed && !paused) {
		advance(delta);
	}
	update_dis_entities();
	advanced = false;
}

void JSBSimAircraft::update_dis_entities() {
	// Paused but driven with advance() (tests, single steps) still counts as moving.
	const bool moving = fdm->is_loaded() && !failed && !crashed && (!paused || advanced);
	const double scale = moving ? time_scale : 0.0;
	// The entity is a child: its own axes are the aircraft's.
	const Basis to_local = get_transform().basis.transposed();
	for (int i = 0; i < get_child_count(); i++) {
		Node *child = get_child(i);
		if (!child->is_class("DisEntity")) {
			continue;
		}
		child->set("velocity_source", DIS_VELOCITY_MANUAL);
		child->set("linear_velocity", linear_velocity * scale);
		child->set("linear_acceleration", linear_acceleration * (scale * scale));
		child->set("angular_velocity", to_local.xform(angular_velocity) * scale);
		const int64_t appearance = child->get("appearance");
		const int64_t wanted = (appearance & ~APPEARANCE_DAMAGE_MASK) | (crashed ? APPEARANCE_DESTROYED : 0);
		if (wanted != appearance) {
			child->set("appearance", wanted);
		}
	}
}

int JSBSimAircraft::advance(double delta) {
	ERR_FAIL_COND_V_MSG(!started, 0, "JSBSimAircraft: start() has not succeeded.");
	if (failed || crashed) {
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
	last_step_count = 0;
	last_step_time_usec = 0.0;
	if (count == 0) {
		return 0;
	}
	const auto start_time = std::chrono::steady_clock::now();
	int done = 0;
	// One step at a time, so a crash stops the aircraft at the step it happens, and the autopilot and the controls
	// act at every step (the same trajectory at any frame rate).
	while (done < count && !crashed) {
		if (autopilot) {
			autopilot->update(dt);
		}
		apply_controls();
		if (fdm->step(1) != 1) {
			break;
		}
		done++;
		if (crash_detection) {
			check_crash();
		}
	}
	update_transform();
	last_step_count = done;
	last_step_time_usec =
			std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - start_time).count();
	advanced = done > 0;
	update_dis_entities();
	return done;
}

void JSBSimAircraft::check_crash() {
	JSBSim::FGFDMExec *exec = fdm->get_exec();
	auto reactions = exec->GetGroundReactions();
	String reason;
	const double sink = exec->GetPropagate()->GetVel(3) * M_PER_FT; // NED down velocity, m/s
	for (int i = 0; i < reactions->GetNumGearUnits() && reason.is_empty(); i++) {
		auto unit = reactions->GetGearUnit(i);
		if (!unit->GetWOW()) {
			continue;
		}
		const String name = String::utf8(unit->GetName().c_str());
		if (!unit->IsBogey()) {
			reason = name + String(" touched the ground");
		} else if (sink > crash_sink_rate) {
			reason = name + String(" touched down at ") + String::num(sink, 1) + String(" m/s");
		}
	}
	if (reason.is_empty() && fdm->get_property("position/h-agl-ft") < 0.0) {
		reason = "the aircraft is below the ground";
	}
	if (!reason.is_empty()) {
		crashed = true;
		reason = "crash at t = " + String::num(fdm->get_sim_time(), 2) + " s: " + reason;
		UtilityFunctions::print("JSBSimAircraft: ", reason);
		emit_signal("crashed", reason);
	}
}

// The ground_path node, if it still exists and is in the scene tree (a Node3D outside the tree has no transform,
// e.g. while the scene is being freed).
Object *JSBSimAircraft::ground_node() const {
	if (!ground_id.is_valid()) {
		return nullptr;
	}
	Object *ground = ObjectDB::get_instance(ground_id);
	Node *node = Object::cast_to<Node>(ground);
	return node && !node->is_inside_tree() ? nullptr : ground;
}

double JSBSimAircraft::get_ground_height(double x, double z) const {
	Object *ground = ground_node();
	if (ground) {
		const double h = ground->call("height_at", x, z);
		if (std::isfinite(h)) {
			return h;
		}
	}
	return ground_level;
}

Vec3 JSBSimAircraft::ground_normal(double x, double z) const {
	if (ground_has_normal) {
		Object *ground = ground_node();
		if (ground) {
			const Vector3 n = ground->call("normal_at", x, z);
			const double length = n.length();
			if (std::isfinite(length) && length > 1e-6 && n.y > 0.0) {
				return Vec3{ n.x, n.y, n.z } * (1.0 / length);
			}
		}
	}
	// Central differences over 1 m: inside one cell of a gridded terrain, the cell's own slope.
	const double dx = (get_ground_height(x + 1.0, z) - get_ground_height(x - 1.0, z)) * 0.5;
	const double dz = (get_ground_height(x, z + 1.0) - get_ground_height(x, z - 1.0)) * 0.5;
	return Vec3{ -dx, 1.0, -dz } * (1.0 / std::sqrt(dx * dx + 1.0 + dz * dz));
}

Vector3 JSBSimAircraft::get_ground_normal(double x, double z) const {
	return to_vector3(ground_normal(x, z));
}

bool JSBSimAircraft::is_on_ground() const {
	JSBSim::FGFDMExec *exec = fdm->get_exec();
	if (!exec) {
		return false;
	}
	auto reactions = exec->GetGroundReactions();
	for (int i = 0; i < reactions->GetNumGearUnits(); i++) {
		auto unit = reactions->GetGearUnit(i);
		if (unit->IsBogey() && unit->GetWOW()) {
			return true;
		}
	}
	return false;
}

void JSBSimAircraft::apply_atmosphere() {
	if (!fdm->is_loaded()) {
		return;
	}
	// JSBSim's wind vector points where the wind blows to.
	const double to = Math::deg_to_rad(wind_direction + 180.0);
	const double fps = wind_speed / M_PER_FT;
	fdm->set_property("atmosphere/wind-north-fps", fps * std::cos(to));
	fdm->set_property("atmosphere/wind-east-fps", fps * std::sin(to));
	fdm->set_property("atmosphere/wind-down-fps", 0.0);
	// FGWinds::tType: 0 none, 3 milspec (FGWinds.h's comment says 4, the enum says 3). Near the ground the milspec
	// intensity follows the wind at 20 ft: at least JSBSim's reference value for the severity (light 3: 25 ft/s,
	// moderate 4: 50 ft/s, severe 6: 75 ft/s).
	fdm->set_property("atmosphere/turb-type", turbulence > 0 ? 3.0 : 0.0);
	const double reference = turbulence >= 6 ? 75.0 : (turbulence >= 4 ? 50.0 : 25.0);
	fdm->set_property("atmosphere/turbulence/milspec/windspeed_at_20ft_AGL-fps", std::max(fps, reference));
	fdm->set_property("atmosphere/turbulence/milspec/severity", double(turbulence));
}

void JSBSimAircraft::set_wind_speed(double value) {
	ERR_FAIL_COND_MSG(!(value >= 0.0), "wind_speed must not be negative.");
	wind_speed = value;
	apply_atmosphere();
}

void JSBSimAircraft::set_wind_direction(double value) {
	wind_direction = Math::fposmod(value, 360.0);
	apply_atmosphere();
}

void JSBSimAircraft::set_turbulence(int value) {
	turbulence = Math::clamp(value, 0, 7);
	apply_atmosphere();
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
	fcs->SetDsCmd(rudder); // nose / tail wheel steering, positive turns right with the right pedal
	fcs->SetThrottleCmd(-1, throttle);
	fcs->SetLBrake(brake);
	fcs->SetRBrake(brake);
	fcs->SetCBrake(brake);
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
	const Vec3 pqr = to_vec3(propagate->GetPQR()); // body rates relative to the Earth
	angular_velocity = to_vector3(enu_to_godot(ecef_to_enu * (body * pqr)));
	// Acceleration relative to the Earth: JSBSim's UVWdot is the derivative of the body-axis velocity in the
	// rotating body frame, so add the rotation term (pqr × uvw) before turning it into Earth axes.
	const Vec3 uvw = to_vec3(propagate->GetUVW(), M_PER_FT);
	const Vec3 uvw_dot = to_vec3(exec->GetAccelerations()->GetUVWdot(), M_PER_FT);
	const Vec3 acceleration = body * (uvw_dot + pqr.cross(uvw));
	linear_acceleration = is_finite(acceleration) ? to_vector3(enu_to_godot(ecef_to_enu * acceleration)) : Vector3();
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

void JSBSimAircraft::set_brake(double value) {
	brake = Math::clamp(value, 0.0, 1.0);
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
	ClassDB::bind_method(D_METHOD("is_crashed"), &JSBSimAircraft::is_crashed);
	ClassDB::bind_method(D_METHOD("is_on_ground"), &JSBSimAircraft::is_on_ground);
	ClassDB::bind_method(D_METHOD("get_ground_height", "x", "z"), &JSBSimAircraft::get_ground_height);
	ClassDB::bind_method(D_METHOD("get_ground_normal", "x", "z"), &JSBSimAircraft::get_ground_normal);
	ClassDB::bind_method(D_METHOD("get_autopilot"), &JSBSimAircraft::get_autopilot);
	ClassDB::bind_method(D_METHOD("get_last_step_count"), &JSBSimAircraft::get_last_step_count);
	ClassDB::bind_method(D_METHOD("get_last_step_time_usec"), &JSBSimAircraft::get_last_step_time_usec);
	ADD_SIGNAL(MethodInfo("failed", PropertyInfo(Variant::STRING, "reason")));
	ADD_SIGNAL(MethodInfo("crashed", PropertyInfo(Variant::STRING, "reason")));
	ClassDB::bind_method(D_METHOD("advance", "delta"), &JSBSimAircraft::advance);
	ClassDB::bind_method(D_METHOD("get_fdm"), &JSBSimAircraft::get_fdm);
	ClassDB::bind_method(D_METHOD("get_linear_velocity"), &JSBSimAircraft::get_linear_velocity);
	ClassDB::bind_method(D_METHOD("get_linear_acceleration"), &JSBSimAircraft::get_linear_acceleration);
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
	BIND_PROPERTY(BOOL, start_on_ground, PROPERTY_HINT_NONE, "");
	ADD_GROUP("Origin", "");
	BIND_PROPERTY(NODE_PATH, geo_origin_path, PROPERTY_HINT_NONE, "");
	BIND_PROPERTY(FLOAT, origin_latitude, PROPERTY_HINT_RANGE, "-90,90,0.000001,suffix:°");
	BIND_PROPERTY(FLOAT, origin_longitude, PROPERTY_HINT_RANGE, "-180,180,0.000001,suffix:°");
	BIND_PROPERTY(FLOAT, origin_height, PROPERTY_HINT_RANGE, "-500,9000,0.1,suffix:m");
	ADD_GROUP("Ground", "");
	BIND_PROPERTY(NODE_PATH, ground_path, PROPERTY_HINT_NONE, "");
	BIND_PROPERTY(FLOAT, ground_level, PROPERTY_HINT_RANGE, "-1000,1000,0.01,or_less,or_greater,suffix:m");
	BIND_PROPERTY(BOOL, crash_detection, PROPERTY_HINT_NONE, "");
	BIND_PROPERTY(FLOAT, crash_sink_rate, PROPERTY_HINT_RANGE, "0.5,20,0.1,suffix:m/s");
	ADD_GROUP("Atmosphere", "");
	BIND_PROPERTY(FLOAT, wind_speed, PROPERTY_HINT_RANGE, "0,60,0.1,or_greater,suffix:m/s");
	BIND_PROPERTY(FLOAT, wind_direction, PROPERTY_HINT_RANGE, "0,360,1,suffix:°");
	BIND_PROPERTY(INT, turbulence, PROPERTY_HINT_ENUM,
			"None,1,2,Light (3),Moderate (4),5,Severe (6),Extreme (7)");
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
	BIND_PROPERTY(FLOAT, brake, PROPERTY_HINT_RANGE, "0,1,0.01");
}
