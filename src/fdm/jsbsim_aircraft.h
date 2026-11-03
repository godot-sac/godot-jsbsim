#pragma once

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "fdm/jsbsim_fdm.h"
#include "geo/geo_math.h"

class JSBSimAutopilot;

// A JSBSim aircraft in the scene. Steps its JSBSimFDM at a fixed rate from _physics_process (with a time
// accumulator) and places the node on the tangent plane of a geographic origin: +X east, +Y up, -Z north, 1 unit =
// 1 metre, the aircraft looking along -Z. The origin is the node at geo_origin_path (anything with latitude,
// longitude and height properties, e.g. godot-dis DisGeoOrigin) or the node's own origin_* properties.
// The ground JSBSim's landing gear touches is the node at ground_path (anything with height_at(x, z), e.g. godot-geo
// GeoTerrain, and optionally normal_at(x, z)) or, where that has no data, a flat plane at y = ground_level.
// A JSBSimAutopilot child, if any, runs before every JSBSim step.
class JSBSimAircraft : public godot::Node3D {
	GDCLASS(JSBSimAircraft, godot::Node3D)
	friend class JSBSimGroundCallback;

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
	// True after a crash (a wing or other structure touched the ground, the gear hit it too fast, or the aircraft
	// went below the ground); the aircraft stops until restart(). The `crashed` signal is emitted once.
	bool is_crashed() const { return crashed; }
	// True while any landing gear touches the ground.
	bool is_on_ground() const;
	// Ground height (scene y) below a scene position, as JSBSim sees it.
	double get_ground_height(double x, double z) const;
	// Ground normal (scene axes, unit length) at a scene position, as JSBSim sees it: the ground node's
	// normal_at(x, z) if it has one, otherwise from the slope of the heights 1 m around the point.
	godot::Vector3 get_ground_normal(double x, double z) const;
	// Advances the simulation by `delta` seconds of game time (scaled by time_scale) and updates the transform.
	// Called by _physics_process unless paused; call it directly to drive the aircraft yourself. Returns the
	// number of JSBSim steps done.
	int advance(double delta);

	godot::Ref<JSBSimFDM> get_fdm() const { return fdm; }
	// The JSBSimAutopilot child, or null.
	JSBSimAutopilot *get_autopilot() const { return autopilot; }
	// Called by JSBSimAutopilot when it enters or leaves the tree under this node.
	void set_autopilot_node(JSBSimAutopilot *node) { autopilot = node; }
	// The scene's tangent-plane frame (valid after start()).
	const gjsb::geo::LocalFrame &local_frame() const { return frame; }
	// JSBSim steps done by the last advance() and the time they took (microseconds, wall clock).
	int get_last_step_count() const { return last_step_count; }
	double get_last_step_time_usec() const { return last_step_time_usec; }
	// Velocity and acceleration relative to the ground in scene axes (m/s, m/s²); angular velocity in scene axes
	// (rad/s). In simulation time: multiply by time_scale for game time.
	godot::Vector3 get_linear_velocity() const { return linear_velocity; }
	godot::Vector3 get_linear_acceleration() const { return linear_acceleration; }
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
	void set_start_on_ground(bool value) { start_on_ground = value; }
	bool get_start_on_ground() const { return start_on_ground; }

	void set_ground_path(const godot::NodePath &value) { ground_path = value; }
	godot::NodePath get_ground_path() const { return ground_path; }
	void set_ground_level(double value) { ground_level = value; }
	double get_ground_level() const { return ground_level; }
	void set_crash_detection(bool value) { crash_detection = value; }
	bool get_crash_detection() const { return crash_detection; }
	void set_crash_sink_rate(double value) { crash_sink_rate = value; }
	double get_crash_sink_rate() const { return crash_sink_rate; }

	// Steady wind (m/s) blowing from wind_direction (degrees true, where it comes from, like a weather report), and
	// MIL-F-8785C turbulence severity 0 (none) .. 7: 3 light, 4 moderate, 6 severe (JSBSim's milspec Dryden model).
	void set_wind_speed(double value);
	double get_wind_speed() const { return wind_speed; }
	void set_wind_direction(double value);
	double get_wind_direction() const { return wind_direction; }
	void set_turbulence(int value);
	int get_turbulence() const { return turbulence; }

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
	void set_brake(double value);
	double get_brake() const { return brake; }

	void _ready() override;
	void _physics_process(double delta) override;

protected:
	static void _bind_methods();

private:
	bool apply_initial_condition();
	void apply_controls();
	// Writes wind and turbulence into JSBSim (when a model is loaded).
	void apply_atmosphere();
	gjsb::geo::Vec3 ground_normal(double x, double z) const;
	// Checks the ground contacts after a step; sets `crashed` and emits the signal.
	void check_crash();
	// Returns false (and stops the aircraft) if the JSBSim state is invalid.
	bool update_transform();
	// Gives child DisEntity nodes (godot-dis, found by class name) JSBSim's velocities instead of their own
	// estimate, scaled to game time (zero while stopped), and marks the entity destroyed after a crash. Runs every
	// physics frame and after advance().
	void update_dis_entities();

	godot::String aircraft = "J3Cub";
	godot::String data_dir = JSBSimFDM::DEFAULT_DATA_DIR;
	double latitude = 39.95; // degrees
	double longitude = 32.69; // degrees
	double height = 1500.0; // metres above the WGS84 ellipsoid
	double heading = 0.0; // degrees, true
	double airspeed = 70.0; // calibrated, knots
	bool trim_on_start = true;
	bool start_on_ground = false; // at rest on the ground at latitude / longitude (height is ignored)

	godot::NodePath ground_path;
	double ground_level = 0.0; // scene y of the flat ground
	bool crash_detection = true;
	double crash_sink_rate = 4.0; // m/s: faster touchdowns are crashes
	double wind_speed = 0.0; // m/s
	double wind_direction = 270.0; // degrees true, from
	int turbulence = 0; // MIL-F-8785C severity 0..7
	godot::ObjectID ground_id;
	godot::Object *ground_node() const;
	bool ground_has_normal = false; // the ground node has normal_at(x, z)

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
	double brake = 0.0; // 0..1, both main wheels

	godot::Ref<JSBSimFDM> fdm;
	JSBSimAutopilot *autopilot = nullptr;
	gjsb::geo::LocalFrame frame;
	int last_step_count = 0;
	double last_step_time_usec = 0.0;
	bool started = false;
	bool failed = false;
	bool crashed = false;
	bool advanced = false; // advance() stepped since the last physics frame
	double accumulator = 0.0;
	godot::Vector3 linear_velocity;
	godot::Vector3 linear_acceleration;
	godot::Vector3 angular_velocity;
};
