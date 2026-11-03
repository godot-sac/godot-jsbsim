extends GutTest
## JSBSimFDM: loading, initial condition, trim, stepping, properties and error handling.

const LAT := 39.95
const LON := 32.69
const HEIGHT := 1500.0
const FT := 0.3048
## pc7 is not bundled (unclear provenance, see THIRD_PARTY_NOTICES.md); the tests read it from the JSBSim submodule.
const JSBSIM_DIR := "res://thirdparty/jsbsim"


func _airborne(aircraft: String, kts: float) -> JSBSimFDM:
	var fdm := JSBSimFDM.new()
	var ok := fdm.load_model(aircraft) if aircraft == "J3Cub" else fdm.load_model(aircraft, JSBSIM_DIR)
	assert_true(ok, fdm.get_last_error())
	fdm.set_initial_position(LAT, LON, HEIGHT)
	fdm.set_initial_orientation(90.0, 0.0, 0.0)
	fdm.set_initial_airspeed(kts)
	assert_true(fdm.run_ic(), fdm.get_last_error())
	fdm.start_engines()
	return fdm


func test_class_and_version() -> void:
	assert_true(ClassDB.class_exists("JSBSimFDM"))
	assert_false(ClassDB.class_exists("JSBSimProbe"), "Phase 0 probe removed")
	assert_string_starts_with(JSBSimFDM.get_jsbsim_version(), "1.3.3")


func test_load_bundled_model() -> void:
	var fdm := JSBSimFDM.new()
	assert_false(fdm.is_loaded())
	assert_true(fdm.load_model("J3Cub"), fdm.get_last_error())
	assert_true(fdm.is_loaded())
	assert_eq(fdm.get_model_name(), "J3Cub")
	assert_true(DirAccess.dir_exists_absolute(fdm.get_data_path().path_join("aircraft/J3Cub")))
	assert_eq(fdm.get_last_error(), "")


func test_initial_position_is_geodetic() -> void:
	var fdm := _airborne("pc7", 150.0)
	assert_almost_eq(fdm.get_property("position/lat-geod-deg"), LAT, 1e-9)
	assert_almost_eq(fdm.get_property("position/long-gc-deg"), LON, 1e-9)
	# Ellipsoid height, not JSBSim's h-sl-ft (geocentric radius difference, ~22 m off at this latitude).
	assert_almost_eq(fdm.get_property("position/geod-alt-ft") * FT, HEIGHT, 1e-6)
	assert_almost_eq(fdm.get_property("attitude/psi-deg"), 90.0, 1e-9)
	assert_almost_eq(fdm.get_property("velocities/vc-kts"), 150.0, 1e-6)


func test_step_and_time() -> void:
	var fdm := _airborne("pc7", 150.0)
	assert_almost_eq(fdm.get_dt(), 1.0 / 120.0, 1e-12)
	assert_eq(fdm.step(120), 120)
	assert_almost_eq(fdm.get_sim_time(), 1.0, 1e-9)
	assert_eq(fdm.step(), 1)
	fdm.set_dt(1.0 / 60.0)
	fdm.step(60)
	assert_almost_eq(fdm.get_sim_time(), 1.0 + 1.0 / 120.0 + 1.0, 1e-9)


func test_trim_holds_level_flight() -> void:
	var fdm := _airborne("J3Cub", 70.0)
	assert_true(fdm.trim(JSBSimFDM.TRIM_FULL), fdm.get_last_error())
	var altitude := fdm.get_property("position/geod-alt-ft")
	fdm.step(1200)
	assert_almost_eq(fdm.get_property("position/geod-alt-ft"), altitude, 1.0, "10 s trimmed: within 1 ft")
	assert_almost_eq(fdm.get_property("velocities/vc-kts"), 70.0, 0.1)
	assert_almost_eq(fdm.get_property("attitude/phi-deg"), 0.0, 0.5)


func test_trim_failure_is_reported() -> void:
	# The pc7 turboprop does not trim in JSBSim 1.3.3 ("udot doesn't appear to be trimmable").
	var fdm := _airborne("pc7", 150.0)
	assert_false(fdm.trim())
	assert_string_contains(fdm.get_last_error(), "trim failed")
	assert_eq(fdm.step(10), 10, "still usable after a failed trim")
	assert_push_error_count(2, "JSBSim's message and ours")


func test_properties() -> void:
	var fdm := _airborne("pc7", 150.0)
	assert_true(fdm.has_property("fcs/throttle-cmd-norm"))
	assert_false(fdm.has_property("fcs/no-such-property"))
	assert_true(fdm.set_property("fcs/throttle-cmd-norm", 0.75))
	assert_almost_eq(fdm.get_property("fcs/throttle-cmd-norm"), 0.75, 1e-12)
	var names := fdm.get_property_names("position/")
	assert_has(names, "position/geod-alt-ft")
	for name: String in names:
		assert_string_contains(name, "position/")
	assert_gt(fdm.get_property_names().size(), names.size())


func test_unknown_property_is_an_error() -> void:
	var fdm := _airborne("pc7", 150.0)
	assert_false(fdm.set_property("fcs/throtle-cmd-norm", 1.0), "typo is not created")
	assert_false(fdm.has_property("fcs/throtle-cmd-norm"))
	assert_eq(fdm.get_property("fcs/throtle-cmd-norm"), 0.0)
	assert_engine_error_count(2, "set_property and get_property")


func test_unparsable_property_name_is_no_property() -> void:
	# SimGear throws for such names; JSBSimFDM must catch it (an uncaught exception ends the Godot process).
	var fdm := _airborne("pc7", 150.0)
	for name: String in ["fcs/throttle cmd", "1fcs", "fcs/[x]", "fcs/a..b"]:
		assert_false(fdm.has_property(name), "'%s'" % name)
	assert_true(fdm.has_property("fcs/throttle-cmd-norm[0]"))


func test_reset_returns_to_initial_condition() -> void:
	var fdm := _airborne("pc7", 150.0)
	fdm.set_property("fcs/throttle-cmd-norm", 0.8)
	fdm.step(600)
	assert_gt(absf(fdm.get_property("position/geod-alt-ft") * FT - HEIGHT), 1.0)
	assert_true(fdm.reset())
	assert_almost_eq(fdm.get_sim_time(), 0.0, 1e-12)
	assert_almost_eq(fdm.get_property("position/geod-alt-ft") * FT, HEIGHT, 1e-6)
	assert_almost_eq(fdm.get_property("position/lat-geod-deg"), LAT, 1e-9)


func test_missing_aircraft() -> void:
	var fdm := JSBSimFDM.new()
	assert_false(fdm.load_model("no_such_aircraft"))
	assert_false(fdm.is_loaded())
	assert_string_contains(fdm.get_last_error(), "no_such_aircraft")
	assert_push_error_count(3, "two JSBSim messages and ours")


func test_missing_data_dir() -> void:
	var fdm := JSBSimFDM.new()
	assert_false(fdm.load_model("pc7", "res://no_such_dir"))
	assert_string_contains(fdm.get_last_error(), "not found")
	assert_push_error_count(1)


func test_calls_without_model_do_not_crash() -> void:
	var fdm := JSBSimFDM.new()
	assert_false(fdm.run_ic())
	assert_eq(fdm.step(5), 0)
	assert_false(fdm.trim())
	assert_eq(fdm.get_property("position/geod-alt-ft"), 0.0)
	assert_engine_error_count(4)


func test_log_level() -> void:
	var saved := JSBSimFDM.get_log_level()
	JSBSimFDM.set_log_level(JSBSimFDM.LOG_ERROR)
	assert_eq(JSBSimFDM.get_log_level(), JSBSimFDM.LOG_ERROR)
	JSBSimFDM.set_log_level(saved)
	assert_eq(JSBSimFDM.get_log_level(), JSBSimFDM.LOG_WARN, "default")
	assert_eq(JSBSimFDM.get_debug_level(), 0, "JSBSim console output off by default")
