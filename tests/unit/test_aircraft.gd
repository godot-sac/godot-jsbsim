extends GutTest
## JSBSimAircraft: placement in the local frame, stepping with the accumulator, controls.

const LAT := 39.95
const LON := 32.69
const KT := 0.514444


func _aircraft(heading := 90.0, origin_height := 1000.0) -> JSBSimAircraft:
	var a := JSBSimAircraft.new()
	a.aircraft = "J3Cub"
	a.latitude = LAT
	a.longitude = LON
	a.height = 1500.0
	a.heading = heading
	a.airspeed = 70.0
	a.origin_latitude = LAT
	a.origin_longitude = LON
	a.origin_height = origin_height
	add_child_autofree(a)  # _ready() calls start()
	a.paused = true  # the tests drive it with advance()
	return a


func test_starts_at_origin_column() -> void:
	var a := _aircraft()
	assert_true(a.is_started(), a.get_fdm().get_last_error())
	assert_almost_eq(a.position.x, 0.0, 1e-3)
	assert_almost_eq(a.position.z, 0.0, 1e-3)
	assert_almost_eq(a.position.y, 500.0, 1e-3, "1500 m over a 1000 m origin")
	var geo := a.get_geodetic_position()
	assert_almost_eq(geo[0], LAT, 1e-9)
	assert_almost_eq(geo[2], 1500.0, 1e-6)


func test_heading_east_looks_along_plus_x() -> void:
	var a := _aircraft(90.0)
	var forward := -a.basis.z
	var pitch := rad_to_deg(asin(forward.y))
	assert_almost_eq(forward.x, cos(deg_to_rad(pitch)), 1e-4, "forward is east")
	assert_almost_eq(forward.z, 0.0, 1e-4)
	assert_almost_eq(pitch, a.get_fdm().get_property("attitude/theta-deg"), 1e-3, "trimmed pitch")
	assert_almost_eq(a.basis.y.y, cos(deg_to_rad(pitch)), 1e-3, "wings level")


func test_heading_north_looks_along_minus_z() -> void:
	var a := _aircraft(0.0)
	var forward := -a.basis.z
	assert_lt(forward.z, -0.99)


func test_trimmed_flight_east() -> void:
	var a := _aircraft(90.0)
	var steps := 0
	for i in 600:  # 10 s at 60 Hz
		steps += a.advance(1.0 / 60.0)
	assert_eq(steps, 1200, "120 Hz")
	assert_almost_eq(a.get_fdm().get_sim_time(), 10.0, 1e-6)
	assert_almost_eq(a.position.y, 500.0, 1.0, "level")
	# True airspeed is above 70 kt calibrated at 1500 m: about 75 kt ≈ 38.5 m/s.
	assert_almost_eq(a.position.x, 385.0, 20.0)
	assert_almost_eq(a.position.z, 0.0, 2.0)
	var v := a.get_linear_velocity()
	assert_almost_eq(v.x, a.position.x / 10.0, 1.0)
	assert_almost_eq(v.y, 0.0, 0.3)
	assert_lt(a.get_angular_velocity().length(), 0.01)


func test_trim_centres_the_stick() -> void:
	var a := _aircraft()
	assert_eq(a.elevator, 0.0)
	assert_eq(a.aileron, 0.0)
	assert_ne(a.get_fdm().get_property("fcs/pitch-trim-cmd-norm"), 0.0, "trim moved into pitch trim")
	assert_almost_eq(a.throttle, a.get_fdm().get_property("fcs/throttle-cmd-norm"), 1e-12)
	assert_gt(a.throttle, 0.3)


func test_roll_input_turns() -> void:
	var a := _aircraft(90.0)
	a.aileron = 0.3
	for i in 120:
		a.advance(1.0 / 60.0)
	assert_gt(a.get_fdm().get_property("attitude/phi-deg"), 10.0, "right roll")
	a.aileron = 0.0
	for i in 600:
		a.advance(1.0 / 60.0)
	assert_gt(a.position.z, 10.0, "a right turn from east heads south (+Z)")


func test_time_scale_and_accumulator() -> void:
	var a := _aircraft()
	a.time_scale = 4.0
	assert_eq(a.advance(1.0 / 60.0), 8)
	a.time_scale = 0.25
	var steps := 0
	for i in 4:
		steps += a.advance(1.0 / 60.0)
	assert_eq(steps, 2, "fractions accumulate")


func test_restart() -> void:
	var a := _aircraft()
	a.aileron = 0.5
	for i in 120:
		a.advance(1.0 / 60.0)
	assert_true(a.restart())
	assert_eq(a.aileron, 0.0)
	assert_almost_eq(a.get_fdm().get_sim_time(), 0.0, 1e-9)
	assert_almost_eq(a.position.y, 500.0, 1e-3)
	assert_almost_eq(a.position.x, 0.0, 1e-3)


func test_geo_origin_path() -> void:
	var origin := Node.new()
	origin.set_script(load("res://tests/unit/fake_origin.gd"))
	origin.name = "Origin"
	add_child_autofree(origin)
	var a := JSBSimAircraft.new()
	a.latitude = LAT
	a.longitude = LON + 0.01
	a.height = 1500.0
	a.geo_origin_path = NodePath("../Origin")
	add_child_autofree(a)
	assert_true(a.is_started())
	# Reference from pymap3d.geodetic2enu(39.95, 32.70, 1500, 39.95, 32.69, 900): E 854.7618, N 0.0479, U 599.9428.
	assert_almost_eq(a.position.x, 854.7618, 1e-3)
	assert_almost_eq(a.position.z, -0.0479, 1e-3)
	assert_almost_eq(a.position.y, 599.9428, 1e-3, "the tangent plane rises above the curved ground")


func test_missing_model() -> void:
	var a := JSBSimAircraft.new()
	a.aircraft = "no_such_aircraft"
	add_child_autofree(a)
	assert_false(a.is_started())
	assert_push_error_count(3)


func test_rudder_right_yaws_right() -> void:
	var a := _aircraft(90.0)
	a.rudder = 0.5
	for i in 60:
		a.advance(1.0 / 60.0)
	assert_gt(a.get_fdm().get_property("attitude/psi-deg"), 91.0, "positive rudder: nose right")


func test_invalid_state_stops_the_aircraft() -> void:
	var a := _aircraft()
	a.trim_on_start = false
	watch_signals(a)
	# An absurd initial airspeed makes JSBSim's state blow up within a few steps.
	a.airspeed = 1e30
	a.restart()
	for i in 10:
		a.advance(1.0 / 60.0)
	assert_true(a.is_failed())
	assert_signal_emit_count(a, "failed", 1)
	assert_eq(a.advance(1.0 / 60.0), 0, "stopped")
	a.airspeed = 70.0
	a.trim_on_start = true
	assert_true(a.restart())
	assert_false(a.is_failed())
	assert_almost_eq(a.position.y, 500.0, 1e-3)


func test_input_moves_the_controls() -> void:
	var a := _aircraft()
	var input := JSBSimInput.new()
	input.expo = false
	a.add_child(input)
	Input.action_press(JSBSimInput.ROLL_RIGHT)
	Input.action_press(JSBSimInput.PITCH_UP)
	Input.action_press(JSBSimInput.THROTTLE_DOWN)
	var throttle := a.throttle
	for i in 30:
		input._physics_process(1.0 / 60.0)
	Input.action_release(JSBSimInput.ROLL_RIGHT)
	Input.action_release(JSBSimInput.PITCH_UP)
	Input.action_release(JSBSimInput.THROTTLE_DOWN)
	assert_almost_eq(a.aileron, 1.0, 1e-6, "keys ramp to full deflection in 0.4 s")
	assert_almost_eq(a.elevator, -1.0, 1e-6, "pulling back is negative elevator (nose up)")
	assert_almost_eq(a.throttle, throttle - 0.25, 1e-6)
	for i in 30:
		input._physics_process(1.0 / 60.0)
	assert_almost_eq(a.aileron, 0.0, 1e-6, "recentres when released")
