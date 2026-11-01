#pragma once

#include <memory>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace JSBSim {
class FGFDMExec;
}

// One JSBSim flight dynamics model (FGFDMExec): load an aircraft, set the initial condition, trim, step and read or
// write properties. Errors never crash: JSBSim exceptions are caught, reported with push_error and kept in
// get_last_error(). Units follow JSBSim's property names (ft, kts, deg); the convenience setters say theirs.
class JSBSimFDM : public godot::RefCounted {
	GDCLASS(JSBSimFDM, godot::RefCounted)

public:
	// JSBSim::TrimMode values.
	enum TrimMode {
		TRIM_LONGITUDINAL = 0,
		TRIM_FULL = 1,
		TRIM_GROUND = 2,
		TRIM_PULLUP = 3,
		TRIM_TURN = 5,
	};

	// JSBSim::LogLevel values, for set_log_level().
	enum LogLevel {
		LOG_BULK = 0,
		LOG_DEBUG = 1,
		LOG_INFO = 2,
		LOG_WARN = 3,
		LOG_ERROR = 4,
		LOG_FATAL = 5,
	};

	static constexpr const char *DEFAULT_DATA_DIR = "res://addons/jsbsim/data";

	JSBSimFDM();
	~JSBSimFDM() override;

	// Loads `aircraft` from `data_dir` (a folder with aircraft/, optionally engine/ and systems/). A previously
	// loaded model is discarded.
	bool load_model(const godot::String &aircraft, const godot::String &data_dir = DEFAULT_DATA_DIR);
	bool is_loaded() const;
	godot::String get_model_name() const;
	// Absolute OS path JSBSim reads the data from (extracted to user:// in exported games).
	godot::String get_data_path() const;
	godot::String get_last_error() const;

	// Initial condition, applied by run_ic(). Latitude/longitude in degrees, height above the WGS84 ellipsoid in
	// metres (not JSBSim's ic/h-sl-ft, which is a geocentric radius difference).
	void set_initial_position(double latitude, double longitude, double height);
	// Heading (true), pitch and roll in degrees.
	void set_initial_orientation(double heading, double pitch, double roll);
	// Calibrated airspeed in knots.
	void set_initial_airspeed(double calibrated_kts);
	bool run_ic();
	// Restarts from the initial condition (sim time 0).
	bool reset();

	// Starts all engines (running, not cranking).
	void start_engines();
	// Trims the aircraft for the current condition; false (and get_last_error()) if the trim does not converge.
	bool trim(int mode = TRIM_FULL);

	// Advances `count` time steps; returns the number of steps done (fewer if JSBSim stops or fails).
	int step(int count = 1);
	double get_sim_time() const;
	double get_dt() const;
	void set_dt(double dt);

	bool has_property(const godot::String &name) const;
	double get_property(const godot::String &name) const;
	// Only existing properties can be set (a typo would otherwise create a new, unused property).
	bool set_property(const godot::String &name, double value);
	// Property names of the loaded model, optionally only those containing `filter`.
	godot::PackedStringArray get_property_names(const godot::String &filter = godot::String()) const;

	static godot::String get_jsbsim_version();
	// Godot output for JSBSim messages at or above `level` (LogLevel). Default LOG_WARN.
	static void set_log_level(int level);
	static int get_log_level();
	// JSBSim's own verbosity (debug_lvl bitmask, global for all models): 0 silent (default), 1 normal console
	// output (model summary, trim report). Applies to models loaded afterwards.
	static void set_debug_level(int level);
	static int get_debug_level();
	// Absolute OS path for a data folder, extracting res:// data from the .pck in exported games. Empty on failure.
	static godot::String resolve_data_dir(const godot::String &data_dir);
	// Copies a res:// data folder to user://jsbsim/<name>-<fingerprint>/ and returns its absolute OS path (reused
	// when unchanged). load_model() does this automatically in exported games; call it to extract ahead of time.
	static godot::String extract_data_dir(const godot::String &res_dir);

	// C++ only (JSBSimAircraft): the wrapped executive, null before a successful load_model().
	JSBSim::FGFDMExec *get_exec() const { return fdm.get(); }

protected:
	static void _bind_methods();

private:
	bool fail(const godot::String &message);

	// unique_ptr: the FGFDMExec is deleted automatically with this object or when a new model is loaded.
	std::unique_ptr<JSBSim::FGFDMExec> fdm;
	godot::String data_path;
	godot::String last_error;
};

VARIANT_ENUM_CAST(JSBSimFDM::TrimMode);
VARIANT_ENUM_CAST(JSBSimFDM::LogLevel);
