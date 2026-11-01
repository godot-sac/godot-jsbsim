#pragma once

#include <vector>

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "geo/geo_math.h"

class JSBSimAircraft;

// A simple autopilot for any JSBSimAircraft: add it as a child of the aircraft. It runs before every JSBSim step
// (at the aircraft's rate, independent of the frame rate) and writes the aircraft's pilot commands.
//
// With `enabled` it always flies the stick and pedals: wings level and the vertical speed in target_vertical_speed,
// or, with the modes on, a heading (heading_hold), a route (follow_route), a height (altitude_hold). speed_hold also
// takes the throttle; without it the throttle stays with the pilot. Cascaded PID loops on JSBSim's own state:
//   heading / route track -> bank -> aileron, beta -> rudder,
//   height -> vertical speed -> pitch -> elevator, airspeed -> throttle.
// The default gains suit the bundled J3Cub; see docs/autopilot.md for tuning other aircraft.
class JSBSimAutopilot : public godot::Node {
	GDCLASS(JSBSimAutopilot, godot::Node)

public:
	// Called by the aircraft before each JSBSim step of `dt` seconds.
	void update(double dt);
	// Turns the autopilot on holding the current heading, height and airspeed (all three modes on).
	void engage();

	// Route: points flown in order, each with an optional height (metres above the WGS84 ellipsoid) and calibrated
	// airspeed (knots) that become the targets when the point becomes active (NAN keeps the current target).
	void add_waypoint(double latitude, double longitude, double height, double speed);
	// Same with a scene position (the aircraft's frame: +X east, +Y up, -Z north); y is the height in the scene.
	void add_waypoint_local(const godot::Vector3 &position, double speed);
	void clear_route();
	int get_waypoint_count() const { return int(route.size()); }
	// {latitude, longitude, height, speed, position (scene)}.
	godot::Dictionary get_waypoint(int index) const;
	// Index of the waypoint being flown to, -1 without a route or after its end.
	int get_active_waypoint() const { return active; }
	// Flies to `index` next, from the current position.
	void set_active_waypoint(int index);

	// Guidance state, for HUDs and tests (valid while following a route).
	double get_distance_to_waypoint() const { return distance_to_waypoint; } // m
	double get_cross_track_error() const { return cross_track_error; } // m, positive right of the leg
	double get_desired_track() const { return desired_track; } // degrees true
	double get_commanded_bank() const { return commanded_bank; } // degrees, right positive
	double get_commanded_pitch() const { return commanded_pitch; } // degrees
	double get_commanded_vertical_speed() const { return commanded_vertical_speed; } // m/s, up positive

	void _enter_tree() override;
	void _exit_tree() override;

#define AP_PROPERTY(m_type, m_name, m_default)                                \
private:                                                                      \
	m_type m_name = m_default;                                                \
                                                                              \
public:                                                                       \
	void set_##m_name(m_type value) { m_name = value; }                       \
	m_type get_##m_name() const { return m_name; }

	// Modes
	AP_PROPERTY(bool, enabled, false)
	AP_PROPERTY(bool, heading_hold, false)
	AP_PROPERTY(bool, altitude_hold, false)
	AP_PROPERTY(bool, speed_hold, false)
	AP_PROPERTY(bool, follow_route, false)
	// Targets
	AP_PROPERTY(double, target_heading, 0.0) // degrees true
	AP_PROPERTY(double, target_altitude, 1500.0) // metres above the WGS84 ellipsoid
	AP_PROPERTY(double, target_speed, 70.0) // knots, calibrated
	AP_PROPERTY(double, target_vertical_speed, 0.0) // m/s, without altitude_hold
	// Route
	AP_PROPERTY(bool, loop_route, false)
	AP_PROPERTY(double, capture_radius, 150.0) // m: a waypoint this close counts as reached
	AP_PROPERTY(double, track_lookahead, 400.0) // m: distance ahead on the leg to steer to
	AP_PROPERTY(double, max_intercept, 45.0) // degrees between the track and the leg while returning to it
	// Limits
	AP_PROPERTY(double, max_bank, 25.0) // degrees
	AP_PROPERTY(double, max_climb_rate, 3.0) // m/s
	AP_PROPERTY(double, max_descent_rate, 4.0) // m/s
	AP_PROPERTY(double, min_pitch, -10.0) // degrees
	AP_PROPERTY(double, max_pitch, 15.0) // degrees
	AP_PROPERTY(double, min_airspeed, 45.0) // knots: below it the climb is reduced, then the nose goes down
	AP_PROPERTY(double, min_throttle, 0.0)
	AP_PROPERTY(double, max_throttle, 1.0)
	// Tuning (angles in degrees, rates in degrees per second)
	AP_PROPERTY(double, heading_gain, 1.0) // degrees of bank per degree of heading error
	AP_PROPERTY(double, track_gain, 1.5) // degrees of bank per degree of track error
	AP_PROPERTY(double, roll_kp, 0.03) // aileron per degree of bank error
	AP_PROPERTY(double, roll_ki, 0.01)
	AP_PROPERTY(double, roll_kd, 0.01) // aileron per degree per second of roll rate
	AP_PROPERTY(double, yaw_kp, 0.05) // rudder per degree of sideslip
	AP_PROPERTY(double, altitude_gain, 0.15) // m/s of climb per metre of height error
	AP_PROPERTY(double, vertical_speed_kp, 1.0) // degrees of pitch per m/s of vertical speed error
	AP_PROPERTY(double, vertical_speed_ki, 0.4)
	AP_PROPERTY(double, pitch_kp, 0.04) // elevator per degree of pitch error
	AP_PROPERTY(double, pitch_ki, 0.04)
	AP_PROPERTY(double, pitch_kd, 0.015) // elevator per degree per second of pitch rate
	AP_PROPERTY(double, speed_kp, 0.05) // throttle per knot of airspeed error
	AP_PROPERTY(double, speed_ki, 0.02)
#undef AP_PROPERTY

protected:
	static void _bind_methods();

private:
	struct Waypoint {
		gjsb::geo::Geodetic geodetic; // radians, metres
		gjsb::geo::Vec3 ecef;
		double speed = 0.0; // knots, NAN to keep the target
		bool has_height = false;
	};

	// Returns the track to fly (degrees) on the active leg and advances along the route; NAN when there is none.
	// The next leg starts early by the distance a turn at the ground speed needs (turn anticipation).
	double route_track(const gjsb::geo::Vec3 &position_ecef, const gjsb::geo::Geodetic &position, double ground_speed);
	void activate(int index, const gjsb::geo::Vec3 &from_ecef);

	JSBSimAircraft *aircraft = nullptr;
	std::vector<Waypoint> route;
	int active = -1;
	gjsb::geo::Vec3 leg_start;
	bool leg_start_pending = false; // the leg starts at the aircraft's position on the next update
	double distance_to_waypoint = 0.0;
	double cross_track_error = 0.0;
	double desired_track = 0.0;
	double commanded_bank = 0.0;
	double commanded_pitch = 0.0;
	double commanded_vertical_speed = 0.0;

	// Loop states; a loop that was off at the previous step starts from the current command (bumpless).
	bool was_enabled = false;
	bool was_speed_hold = false;
	double roll_integral = 0.0;
	double pitch_integral = 0.0; // pitch command from the vertical speed loop, degrees
	double elevator_integral = 0.0;
	double throttle_integral = 0.0;
};
