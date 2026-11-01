#include "jsbsim_autopilot.h"

#include <algorithm>
#include <cmath>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/math.hpp>

#include <FGFDMExec.h>
#include <models/FGAuxiliary.h>
#include <models/FGPropagate.h>

#include "fdm/jsbsim_aircraft.h"

using namespace godot;
using namespace gjsb::geo;

namespace {

constexpr double M_PER_FT = 0.3048;
constexpr double RAD_TO_DEG = 57.29577951308232; // 180 / pi
// Below this ground speed the track is meaningless (on the ground, hovering): the heading is used instead.
constexpr double MIN_TRACK_SPEED = 5.0; // m/s
constexpr double GRAVITY = 9.80665; // m/s²

double wrap180(double degrees) {
	return std::remainder(degrees, 360.0);
}

double wrap360(double degrees) {
	const double d = std::fmod(degrees, 360.0);
	return d < 0.0 ? d + 360.0 : d;
}

} // namespace

void JSBSimAutopilot::_enter_tree() {
	aircraft = Object::cast_to<JSBSimAircraft>(get_parent());
	if (aircraft) {
		aircraft->set_autopilot_node(this);
	} else {
		WARN_PRINT("JSBSimAutopilot: the parent is not a JSBSimAircraft; the autopilot does nothing.");
	}
}

void JSBSimAutopilot::_exit_tree() {
	if (aircraft) {
		aircraft->set_autopilot_node(nullptr);
	}
	aircraft = nullptr;
}

void JSBSimAutopilot::engage() {
	ERR_FAIL_COND_MSG(!aircraft || !aircraft->is_started(), "JSBSimAutopilot: the aircraft has not started.");
	JSBSim::FGFDMExec *exec = aircraft->get_fdm()->get_exec();
	auto propagate = exec->GetPropagate();
	target_heading = wrap360(propagate->GetEulerDeg(3));
	target_altitude = propagate->GetGeodeticAltitude() * M_PER_FT;
	target_speed = exec->GetAuxiliary()->GetVcalibratedKTS();
	heading_hold = true;
	altitude_hold = true;
	speed_hold = true;
	enabled = true;
}

void JSBSimAutopilot::update(double dt) {
	if (!enabled || !aircraft) {
		was_enabled = false;
		was_speed_hold = false;
		return;
	}
	JSBSim::FGFDMExec *exec = aircraft->get_fdm()->get_exec();
	auto propagate = exec->GetPropagate();
	auto auxiliary = exec->GetAuxiliary();
	const double phi = propagate->GetEulerDeg(1);
	const double theta = propagate->GetEulerDeg(2);
	const double psi = propagate->GetEulerDeg(3);
	const double p = propagate->GetPQR(1) * RAD_TO_DEG;
	const double q = propagate->GetPQR(2) * RAD_TO_DEG;
	const double ias = auxiliary->GetVcalibratedKTS();
	const double beta = auxiliary->Getbeta() * RAD_TO_DEG;
	const double north = propagate->GetVel(1) * M_PER_FT;
	const double east = propagate->GetVel(2) * M_PER_FT;
	const double vertical_speed = -propagate->GetVel(3) * M_PER_FT;
	const Geodetic position{ propagate->GetGeodLatitudeRad(), propagate->GetLongitude(),
		propagate->GetGeodeticAltitude() * M_PER_FT };
	const JSBSim::FGLocation &location = propagate->GetLocation();
	const Vec3 position_ecef{ location(1) * M_PER_FT, location(2) * M_PER_FT, location(3) * M_PER_FT };

	if (!was_enabled) {
		// Start every loop from the current commands and attitude.
		roll_integral = aircraft->get_aileron();
		elevator_integral = -aircraft->get_elevator();
		pitch_integral = theta;
	}
	if (speed_hold && (!was_enabled || !was_speed_hold)) {
		throttle_integral = aircraft->get_throttle();
	}
	was_enabled = true;
	was_speed_hold = speed_hold;

	// Lateral: a track (route), a heading, or wings level.
	double bank = 0.0;
	const double ground_speed = std::hypot(north, east);
	const double track = follow_route ? route_track(position_ecef, position, ground_speed) : NAN;
	if (!std::isnan(track)) {
		const double actual = ground_speed > MIN_TRACK_SPEED ? std::atan2(east, north) * RAD_TO_DEG : psi;
		bank = track_gain * wrap180(track - actual);
	} else if (heading_hold) {
		bank = heading_gain * wrap180(target_heading - psi);
	}
	bank = Math::clamp(bank, -max_bank, max_bank);
	commanded_bank = bank;
	const double roll_error = bank - phi;
	roll_integral = Math::clamp(roll_integral + roll_ki * roll_error * dt, -0.3, 0.3);
	aircraft->set_aileron(roll_kp * roll_error + roll_integral - roll_kd * p);
	// Positive sideslip (wind from the right): right pedal.
	aircraft->set_rudder(yaw_kp * beta);

	// Vertical: height -> vertical speed -> pitch -> elevator.
	double climb = altitude_hold ? altitude_gain * (target_altitude - position.height) : target_vertical_speed;
	climb = Math::clamp(climb, -max_descent_rate, max_climb_rate);
	// Speed protection: less climb close to min_airspeed, a descent below it.
	if (ias < min_airspeed) {
		climb = std::min(climb, (ias - min_airspeed) * 0.3);
	} else {
		climb = std::min(climb, max_climb_rate * Math::clamp((ias - min_airspeed) / 10.0, 0.0, 1.0));
	}
	commanded_vertical_speed = climb;
	const double climb_error = climb - vertical_speed;
	pitch_integral = Math::clamp(pitch_integral + vertical_speed_ki * climb_error * dt, min_pitch, max_pitch);
	const double pitch = Math::clamp(pitch_integral + vertical_speed_kp * climb_error, min_pitch, max_pitch);
	commanded_pitch = pitch;
	const double pitch_error = pitch - theta;
	elevator_integral = Math::clamp(elevator_integral + pitch_ki * pitch_error * dt, -0.6, 0.6);
	// Positive elevator is nose down.
	aircraft->set_elevator(-(pitch_kp * pitch_error + elevator_integral) + pitch_kd * q);

	if (speed_hold) {
		const double speed_error = target_speed - ias;
		throttle_integral = Math::clamp(throttle_integral + speed_ki * speed_error * dt, min_throttle, max_throttle);
		aircraft->set_throttle(Math::clamp(throttle_integral + speed_kp * speed_error, min_throttle, max_throttle));
	}
}

double JSBSimAutopilot::route_track(const Vec3 &position_ecef, const Geodetic &position, double ground_speed) {
	if (active < 0 || active >= int(route.size())) {
		return NAN;
	}
	if (leg_start_pending) {
		leg_start = position_ecef;
		leg_start_pending = false;
	}
	// The leg in the tangent plane at the aircraft (x east, y north).
	const LocalFrame here({ position.latitude, position.longitude, 0.0 });
	for (int guard = 0; guard < int(route.size()) + 1; guard++) {
		const Waypoint &target = route[active];
		const Vec3 a = here.ecef_to_enu(leg_start);
		const Vec3 b = here.ecef_to_enu(target.ecef);
		const Vec3 p = here.ecef_to_enu(position_ecef);
		const double dx = b.x - a.x;
		const double dy = b.y - a.y;
		const double length = std::hypot(dx, dy);
		distance_to_waypoint = std::hypot(b.x - p.x, b.y - p.y);
		double ux = 0.0, uy = 1.0;
		double along = 0.0;
		if (length > 1.0) {
			ux = dx / length;
			uy = dy / length;
			along = (p.x - a.x) * ux + (p.y - a.y) * uy;
		}
		// Turn anticipation: radius of a turn at 80 % of max_bank, lead = radius * tan(turn / 2).
		double lead = 0.0;
		const int next = active + 1 < int(route.size()) ? active + 1 : (loop_route ? 0 : -1);
		if (next >= 0 && next != active && length > 1.0) {
			const Vec3 c = here.ecef_to_enu(route[next].ecef);
			const double turn = std::abs(wrap180((std::atan2(c.x - b.x, c.y - b.y) - std::atan2(dx, dy)) * RAD_TO_DEG));
			const double radius = ground_speed * ground_speed / (GRAVITY * std::tan(Math::deg_to_rad(max_bank * 0.8)));
			lead = std::min(radius * std::tan(Math::deg_to_rad(std::min(turn, 150.0)) * 0.5), length * 0.5);
		}
		const bool reached = length <= 1.0 || distance_to_waypoint < std::max(capture_radius, lead) ||
				along >= length - lead;
		if (!reached) {
			cross_track_error = uy * (p.x - a.x) - ux * (p.y - a.y);
			const double course = std::atan2(ux, uy) * RAD_TO_DEG;
			const double intercept = Math::clamp(std::atan(cross_track_error / track_lookahead) * RAD_TO_DEG,
					-max_intercept, max_intercept);
			desired_track = wrap360(course - intercept);
			return desired_track;
		}
		const int reached_index = active;
		const bool last = active + 1 >= int(route.size());
		emit_signal("waypoint_reached", reached_index);
		// A loop needs two waypoints; one is reached once.
		if (last && (!loop_route || route.size() == 1)) {
			// Keep flying the last leg's course.
			active = -1;
			follow_route = false;
			heading_hold = true;
			target_heading = wrap360(length > 1.0 ? std::atan2(ux, uy) * RAD_TO_DEG : desired_track);
			emit_signal("route_finished");
			return NAN;
		}
		// Signal handlers may have changed the route: then fly what they set, from here.
		if (active != reached_index || reached_index >= int(route.size()) || last != (active + 1 >= int(route.size()))) {
			return active >= 0 && active < int(route.size()) ? desired_track : NAN;
		}
		activate(last ? 0 : active + 1, route[reached_index].ecef);
	}
	return NAN;
}

void JSBSimAutopilot::activate(int index, const Vec3 &from_ecef) {
	active = index;
	leg_start = from_ecef;
	leg_start_pending = false;
	const Waypoint &target = route[index];
	if (target.has_height) {
		target_altitude = target.geodetic.height;
	}
	if (!std::isnan(target.speed)) {
		target_speed = target.speed;
	}
}

void JSBSimAutopilot::add_waypoint(double latitude, double longitude, double height, double speed) {
	ERR_FAIL_COND_MSG(!std::isfinite(latitude) || !std::isfinite(longitude) || std::abs(latitude) > 90.0,
			"JSBSimAutopilot: invalid waypoint position.");
	Waypoint w;
	w.has_height = std::isfinite(height);
	w.geodetic = { Math::deg_to_rad(latitude), Math::deg_to_rad(longitude), w.has_height ? height : 0.0 };
	w.ecef = geodetic_to_ecef(w.geodetic);
	w.speed = std::isfinite(speed) ? speed : NAN;
	route.push_back(w);
	if (active < 0 && route.size() == 1) {
		set_active_waypoint(0);
	}
}

void JSBSimAutopilot::add_waypoint_local(const Vector3 &position, double speed) {
	ERR_FAIL_COND_MSG(!aircraft || !aircraft->is_started(),
			"JSBSimAutopilot: add_waypoint_local needs a started parent aircraft (its frame).");
	const Vec3 ecef = aircraft->local_frame().enu_to_ecef(godot_to_enu({ position.x, position.y, position.z }));
	const Geodetic g = ecef_to_geodetic(ecef);
	add_waypoint(Math::rad_to_deg(g.latitude), Math::rad_to_deg(g.longitude), g.height, speed);
}

void JSBSimAutopilot::clear_route() {
	route.clear();
	active = -1;
	distance_to_waypoint = 0.0;
	cross_track_error = 0.0;
}

void JSBSimAutopilot::set_active_waypoint(int index) {
	ERR_FAIL_INDEX_MSG(index, int(route.size()), "JSBSimAutopilot: no such waypoint.");
	activate(index, Vec3{});
	leg_start_pending = true;
}

Dictionary JSBSimAutopilot::get_waypoint(int index) const {
	Dictionary result;
	ERR_FAIL_INDEX_V(index, int(route.size()), result);
	const Waypoint &w = route[index];
	result["latitude"] = Math::rad_to_deg(w.geodetic.latitude);
	result["longitude"] = Math::rad_to_deg(w.geodetic.longitude);
	result["height"] = w.has_height ? w.geodetic.height : NAN;
	result["speed"] = w.speed;
	if (aircraft && aircraft->is_started()) {
		Geodetic g = w.geodetic;
		if (!w.has_height) {
			g.height = aircraft->local_frame().origin().height;
		}
		const Vec3 local = enu_to_godot(aircraft->local_frame().ecef_to_enu(geodetic_to_ecef(g)));
		result["position"] = Vector3(real_t(local.x), real_t(local.y), real_t(local.z));
	}
	return result;
}

#define BIND_AP_PROPERTY(m_type, m_name, m_hint, m_hint_string)                                                \
	ClassDB::bind_method(D_METHOD("set_" #m_name, "value"), &JSBSimAutopilot::set_##m_name);                    \
	ClassDB::bind_method(D_METHOD("get_" #m_name), &JSBSimAutopilot::get_##m_name);                             \
	ADD_PROPERTY(PropertyInfo(Variant::m_type, #m_name, m_hint, m_hint_string), "set_" #m_name, "get_" #m_name)

void JSBSimAutopilot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("engage"), &JSBSimAutopilot::engage);
	ClassDB::bind_method(D_METHOD("update", "dt"), &JSBSimAutopilot::update);
	ClassDB::bind_method(D_METHOD("add_waypoint", "latitude", "longitude", "height", "speed"),
			&JSBSimAutopilot::add_waypoint, DEFVAL(NAN), DEFVAL(NAN));
	ClassDB::bind_method(D_METHOD("add_waypoint_local", "position", "speed"), &JSBSimAutopilot::add_waypoint_local,
			DEFVAL(NAN));
	ClassDB::bind_method(D_METHOD("clear_route"), &JSBSimAutopilot::clear_route);
	ClassDB::bind_method(D_METHOD("get_waypoint_count"), &JSBSimAutopilot::get_waypoint_count);
	ClassDB::bind_method(D_METHOD("get_waypoint", "index"), &JSBSimAutopilot::get_waypoint);
	ClassDB::bind_method(D_METHOD("get_active_waypoint"), &JSBSimAutopilot::get_active_waypoint);
	ClassDB::bind_method(D_METHOD("set_active_waypoint", "index"), &JSBSimAutopilot::set_active_waypoint);
	ClassDB::bind_method(D_METHOD("get_distance_to_waypoint"), &JSBSimAutopilot::get_distance_to_waypoint);
	ClassDB::bind_method(D_METHOD("get_cross_track_error"), &JSBSimAutopilot::get_cross_track_error);
	ClassDB::bind_method(D_METHOD("get_desired_track"), &JSBSimAutopilot::get_desired_track);
	ClassDB::bind_method(D_METHOD("get_commanded_bank"), &JSBSimAutopilot::get_commanded_bank);
	ClassDB::bind_method(D_METHOD("get_commanded_pitch"), &JSBSimAutopilot::get_commanded_pitch);
	ClassDB::bind_method(D_METHOD("get_commanded_vertical_speed"), &JSBSimAutopilot::get_commanded_vertical_speed);
	ADD_SIGNAL(MethodInfo("waypoint_reached", PropertyInfo(Variant::INT, "index")));
	ADD_SIGNAL(MethodInfo("route_finished"));

	ADD_GROUP("Modes", "");
	BIND_AP_PROPERTY(BOOL, enabled, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(BOOL, heading_hold, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(BOOL, altitude_hold, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(BOOL, speed_hold, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(BOOL, follow_route, PROPERTY_HINT_NONE, "");
	ADD_GROUP("Targets", "");
	BIND_AP_PROPERTY(FLOAT, target_heading, PROPERTY_HINT_RANGE, "0,360,0.1,suffix:°");
	BIND_AP_PROPERTY(FLOAT, target_altitude, PROPERTY_HINT_RANGE, "-500,20000,0.1,or_greater,suffix:m");
	BIND_AP_PROPERTY(FLOAT, target_speed, PROPERTY_HINT_RANGE, "0,600,0.1,or_greater,suffix:kt");
	BIND_AP_PROPERTY(FLOAT, target_vertical_speed, PROPERTY_HINT_RANGE, "-20,20,0.1,suffix:m/s");
	ADD_GROUP("Route", "");
	BIND_AP_PROPERTY(BOOL, loop_route, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, capture_radius, PROPERTY_HINT_RANGE, "1,5000,1,or_greater,suffix:m");
	BIND_AP_PROPERTY(FLOAT, track_lookahead, PROPERTY_HINT_RANGE, "10,5000,1,or_greater,suffix:m");
	BIND_AP_PROPERTY(FLOAT, max_intercept, PROPERTY_HINT_RANGE, "5,90,0.1,suffix:°");
	ADD_GROUP("Limits", "");
	BIND_AP_PROPERTY(FLOAT, max_bank, PROPERTY_HINT_RANGE, "1,80,0.1,suffix:°");
	BIND_AP_PROPERTY(FLOAT, max_climb_rate, PROPERTY_HINT_RANGE, "0,50,0.1,suffix:m/s");
	BIND_AP_PROPERTY(FLOAT, max_descent_rate, PROPERTY_HINT_RANGE, "0,50,0.1,suffix:m/s");
	BIND_AP_PROPERTY(FLOAT, min_pitch, PROPERTY_HINT_RANGE, "-45,0,0.1,suffix:°");
	BIND_AP_PROPERTY(FLOAT, max_pitch, PROPERTY_HINT_RANGE, "0,45,0.1,suffix:°");
	BIND_AP_PROPERTY(FLOAT, min_airspeed, PROPERTY_HINT_RANGE, "0,300,0.1,or_greater,suffix:kt");
	BIND_AP_PROPERTY(FLOAT, min_throttle, PROPERTY_HINT_RANGE, "0,1,0.01");
	BIND_AP_PROPERTY(FLOAT, max_throttle, PROPERTY_HINT_RANGE, "0,1,0.01");
	ADD_GROUP("Tuning", "");
	BIND_AP_PROPERTY(FLOAT, heading_gain, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, track_gain, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, roll_kp, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, roll_ki, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, roll_kd, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, yaw_kp, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, altitude_gain, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, vertical_speed_kp, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, vertical_speed_ki, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, pitch_kp, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, pitch_ki, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, pitch_kd, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, speed_kp, PROPERTY_HINT_NONE, "");
	BIND_AP_PROPERTY(FLOAT, speed_ki, PROPERTY_HINT_NONE, "");
}
