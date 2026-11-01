extends GutTest
## JSBSimAircraft on the ground: resting on the gear, takeoff and landing with FlightAutopilot (demo/autopilot.gd),
## crashes, and a ground node with height_at(x, z).

const LAT := 39.95
const LON := 32.69
## J3Cub CG height above the ground when resting on its gear, from the ground trim.
const REST_HEIGHT := 1.15


func _aircraft(on_ground: bool, agl := 0.0, airspeed := 60.0) -> JSBSimAircraft:
	var a := JSBSimAircraft.new()
	a.latitude = LAT
	a.longitude = LON
	a.origin_latitude = LAT
	a.origin_longitude = LON
	a.origin_height = 1000.0
	a.height = 1000.0 + agl
	a.heading = 90.0
	a.airspeed = airspeed
	a.start_on_ground = on_ground
	add_child_autofree(a)
	a.paused = true
	return a


func _fly(a: JSBSimAircraft, pilot: FlightAutopilot, seconds: float, each: Callable = Callable()) -> void:
	for i in int(seconds * 60.0):
		if each.is_valid():
			each.call()
		pilot.update()
		a.advance(1.0 / 60.0)
		if a.is_crashed():
			return


func test_rests_on_the_gear() -> void:
	var a := _aircraft(true)
	assert_true(a.is_started(), a.get_fdm().get_last_error())
	assert_true(a.is_on_ground())
	assert_eq(a.throttle, 0.0, "starts at idle")
	assert_almost_eq(a.position.y, REST_HEIGHT, 0.1)
	assert_almost_eq(a.get_fdm().get_property("attitude/theta-deg"), 12.2, 0.5, "taildragger: three-point attitude")
	for i in 300:
		a.advance(1.0 / 60.0)
	assert_false(a.is_crashed())
	assert_almost_eq(a.position.y, REST_HEIGHT, 0.1, "still on the gear after 5 s")
	assert_lt(Vector2(a.position.x, a.position.z).length(), 5.0, "idle creep only")


func test_takeoff() -> void:
	var a := _aircraft(true)
	var pilot := FlightAutopilot.new(a)
	pilot.vertical_speed = 1.5
	var lifted_off_at := -1.0
	for i in 3600:
		pilot.takeoff()
		a.advance(1.0 / 60.0)
		if lifted_off_at < 0.0 and not a.is_on_ground() and a.position.y > 3.0:
			lifted_off_at = a.get_fdm().get_sim_time()
	assert_false(a.is_crashed())
	assert_between(lifted_off_at, 15.0, 35.0, "lift-off time")
	assert_gt(a.position.y, 40.0, "climbing")
	assert_almost_eq(fposmod(a.get_fdm().get_property("attitude/psi-deg"), 360.0), 90.0, 3.0, "kept the heading")
	assert_almost_eq(a.position.z, 0.0, 30.0, "stayed on the runway line")


func test_landing_to_a_stop() -> void:
	var a := _aircraft(false, 60.0, 60.0)
	var pilot := FlightAutopilot.new(a)
	a.throttle = 0.3
	_fly(a, pilot, 150.0, func() -> void:
		var agl := a.position.y - REST_HEIGHT
		pilot.vertical_speed = -2.0 if agl > 8.0 else (-0.6 if agl > 0.5 else -0.2)
		if agl < 8.0:
			a.throttle = 0.0
		if a.is_on_ground():
			pilot.vertical_speed = 0.0
			pilot.ground_pitch = 20.0  # stick back: keeps the tail down while braking
			a.brake = 0.4 if a.get_fdm().get_property("velocities/vc-kts") < 30.0 else 0.0)
	assert_false(a.is_crashed())
	assert_true(a.is_on_ground())
	assert_lt(a.get_linear_velocity().length(), 0.5, "stopped")
	assert_almost_eq(a.position.y, REST_HEIGHT, 0.1)
	assert_almost_eq(fposmod(a.get_fdm().get_property("attitude/psi-deg"), 360.0), 90.0, 3.0)


func test_dive_into_the_ground_crashes() -> void:
	var a := _aircraft(false, 100.0, 70.0)
	watch_signals(a)
	a.elevator = 0.6
	for i in 1200:
		a.advance(1.0 / 60.0)
	assert_true(a.is_crashed())
	assert_false(a.is_failed(), "caught before JSBSim's state blows up")
	assert_signal_emit_count(a, "crashed", 1)
	assert_string_contains(str(get_signal_parameters(a, "crashed")[0]), "touched down at")
	var time := a.get_fdm().get_sim_time()
	assert_eq(a.advance(1.0 / 60.0), 0, "stopped")
	assert_eq(a.get_fdm().get_sim_time(), time)
	assert_true(a.restart())
	assert_false(a.is_crashed())
	assert_almost_eq(a.position.y, 100.0, 1e-3)


func test_crash_detection_can_be_turned_off() -> void:
	var a := _aircraft(false, 100.0, 70.0)
	a.crash_detection = false
	a.elevator = 0.6
	for i in 600:
		a.advance(1.0 / 60.0)
	assert_false(a.is_crashed())


func test_ground_node_height() -> void:
	var ground := Node.new()
	ground.set_script(load("res://tests/unit/fake_ground.gd"))
	ground.name = "Ground"
	add_child_autofree(ground)
	var a := JSBSimAircraft.new()
	a.latitude = LAT
	a.longitude = LON
	a.origin_latitude = LAT
	a.origin_longitude = LON
	a.origin_height = 1000.0
	a.heading = 90.0
	a.start_on_ground = true
	a.ground_path = NodePath("../Ground")
	add_child_autofree(a)
	assert_true(a.is_started(), a.get_fdm().get_last_error())
	assert_almost_eq(a.position.y, 100.0 + REST_HEIGHT, 0.1, "rests on the node's ground, 100 m up")
	assert_almost_eq(a.get_fdm().get_property("position/h-agl-ft") * 0.3048, REST_HEIGHT, 0.1)
	assert_eq(a.get_ground_height(0.0, 0.0), 100.0)
	assert_eq(a.get_ground_height(9000.0, 0.0), 0.0, "ground_level where the node has no data")


func test_ground_slope_tilts_the_aircraft() -> void:
	var ground := Node.new()
	ground.set_script(load("res://tests/unit/fake_ground.gd"))
	ground.name = "Ground"
	ground.set("slope", 0.05)  # rising towards +X, the direction the aircraft faces
	add_child_autofree(ground)
	var a := JSBSimAircraft.new()
	a.latitude = LAT
	a.longitude = LON
	a.origin_latitude = LAT
	a.origin_longitude = LON
	a.origin_height = 1000.0
	a.heading = 90.0
	a.start_on_ground = true
	a.ground_path = NodePath("../Ground")
	add_child_autofree(a)
	assert_true(a.is_on_ground())
	# Three-point attitude plus the slope angle (atan(0.05) = 2.86°).
	assert_almost_eq(a.get_fdm().get_property("attitude/theta-deg"), 12.2 + 2.86, 0.5)


func test_brakes_hold_against_power() -> void:
	var a := _aircraft(true)
	var pilot := FlightAutopilot.new(a)
	pilot.ground_pitch = 15.0  # stick back
	a.throttle = 0.5
	_fly(a, pilot, 10.0, func() -> void: a.brake = 1.0)
	assert_false(a.is_crashed())
	assert_lt(a.position.x, 3.0, "brakes hold half power")
