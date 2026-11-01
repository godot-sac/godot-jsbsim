#pragma once

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "fdm/jsbsim_fdm.h"
#include "geo/geo_math.h"

// A JSBSim aircraft in the scene. Steps its JSBSimFDM at a fixed rate from _physics_process (with a time
// accumulator) and places the node on the tangent plane of a geographic origin: +X east, +Y up, -Z north, 1 unit =
// 1 metre, the aircraft looking along -Z. The origin is the node at geo_origin_path (anything with latitude,
// longitude and height properties, e.g. godot-dis DisGeoOrigin) or the node's own origin_* properties.
// Until terrain support (Phase 3) JSBSim's ground is flat at the origin's height.
class JSBSimAircraft : public godot::Node3D {
	GDCLASS(JSBSimAircraft, godot::Node3D)

public:
	JSBSimAircraft();

	// Loads the model and applies the initial condition. Called from _ready() at run time; call it again after
	// changing aircraft or data_dir. Returns false (see get_fdm().get_last_error()) on failure.
	bool start();
	// Back to the initial condition (position, speed, trim). Keeps the loaded model, except after is_failed(), when
	// the model is loaded again.
	bool restart();
	bool is_started() const { return started; }
	// True after the JSBSim state became invalid (not finite or far out of range, typically after hitting the
	// ground hard); the aircraft stops until restart(). The `failed` signal is emitted once.
	bool is_failed() const { return failed; }
	// Advances the simulation by `delta` seconds of game time (scaled by time_scale) and updates the transform.
	// Called by _physics_process unless paused; call it directly to drive the aircraft yourself. Returns the
	// number of JSBSim steps done.
	int advance(double delta);

	godot::Ref<JSBSimFDM> get_fdm() const { return fdm; }
	godot::Vector3 get_linear_velocity() const { return linear_velocity; }
	godot::Vector3 get_angular_velocity() const { return angular_velocity; }
	// [latitude (deg), longitude (deg), height above the ellipsoid (m)].
	godot::PackedFloat64Array get_geodetic_position() const;

	void set_aircraft(const godot::String &value) { aircraft = value; }
	godot::String get_aircraft() const { return aircraft; }
	void set_data_dir(const godot::String &value) { data_dir = value; }
	godot::String get_data_dir() const { return data_dir; }

	void set_latitude(double value) { latitude = value; }
	double get_latitude() const { return latitude; }
	void set_longitude(double value) { longitude = value; }
	double get_longitude() const { return longitude; }
	void set_height(double value) { height = value; }
	double get_height() const { return height; }
	void set_heading(double value) { heading = value; }
	double get_heading() const { return heading; }
	void set_airspeed(double value) { airspeed = value; }
	double get_airspeed() const { return airspeed; }
	void set_trim_on_start(bool value) { trim_on_start = value; }
	bool get_trim_on_start() const { return trim_on_start; }

	void set_geo_origin_path(const godot::NodePath &value) { geo_origin_path = value; }
	godot::NodePath get_geo_origin_path() const { return geo_origin_path; }
	void set_origin_latitude(double value) { origin_latitude = value; }
	double get_origin_latitude() const { return origin_latitude; }
	void set_origin_longitude(double value) { origin_longitude = value; }
	double get_origin_longitude() const { return origin_longitude; }
	void set_origin_height(double value) { origin_height = value; }
	double get_origin_height() const { return origin_height; }

	void set_rate(double value);
	double get_rate() const { return rate; }
	void set_time_scale(double value);
	double get_time_scale() const { return time_scale; }
	void set_paused(bool value) { paused = value; }
	bool is_paused() const { return paused; }

	void set_aileron(double value);
	double get_aileron() const { return aileron; }
	void set_elevator(double value);
	double get_elevator() const { return elevator; }
	void set_rudder(double value);
	double get_rudder() const { return rudder; }
	void set_throttle(double value);
	double get_throttle() const { return throttle; }

	void _ready() override;
	void _physics_process(double delta) override;

protected:
	static void _bind_methods();

private:
	bool apply_initial_condition();
	void apply_controls();
	// Returns false (and stops the aircraft) if the JSBSim state is invalid.
	bool update_transform();

	godot::String aircraft = "J3Cub";
	godot::String data_dir = JSBSimFDM::DEFAULT_DATA_DIR;
	double latitude = 39.95; // degrees
	double longitude = 32.69; // degrees
	double height = 1500.0; // metres above the WGS84 ellipsoid
	double heading = 0.0; // degrees, true
	double airspeed = 70.0; // calibrated, knots
	bool trim_on_start = true;

	godot::NodePath geo_origin_path;
	double origin_latitude = 39.95;
	double origin_longitude = 32.69;
	double origin_height = 0.0;

	double rate = 120.0; // JSBSim steps per second
	double time_scale = 1.0;
	bool paused = false;

	// Pilot commands, normalised: stick and pedals -1..1 around the trimmed position, throttle 0..1.
	// aileron +1 rolls right, elevator +1 is stick forward (nose down), rudder +1 is the right pedal (nose right;
	// JSBSim's own rudder command has the opposite sign).
	double aileron = 0.0;
	double elevator = 0.0;
	double rudder = 0.0;
	double throttle = 0.8;

	godot::Ref<JSBSimFDM> fdm;
	gjsb::geo::LocalFrame frame;
	bool started = false;
	bool failed = false;
	double accumulator = 0.0;
	godot::Vector3 linear_velocity;
	godot::Vector3 angular_velocity;
};
