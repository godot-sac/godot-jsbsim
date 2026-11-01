extends GutTest
## JSBSimAircraft wind and turbulence: the steady wind drifts the aircraft, turbulence shakes it.


func _aircraft(wind := 0.0, from := 270.0, turbulence := 0) -> JSBSimAircraft:
	var a := JSBSimAircraft.new()
	a.height = 1500.0
	a.origin_height = 1000.0
	a.heading = 0.0
	a.airspeed = 70.0
	a.wind_speed = wind
	a.wind_direction = from
	a.turbulence = turbulence
	var autopilot := JSBSimAutopilot.new()
	a.add_child(autopilot)
	add_child_autofree(a)
	a.paused = true
	autopilot.engage()
	return a


func _fly(a: JSBSimAircraft, seconds: float, each: Callable = Callable()) -> void:
	for i in int(seconds * 60.0):
		a.advance(1.0 / 60.0)
		if each.is_valid():
			each.call()


## Heading held north in a wind from the west: the nose stays north, the aircraft drifts east with the wind.
func test_wind_from_the_west_drifts_east() -> void:
	var a := _aircraft(10.0, 270.0)
	assert_almost_eq(a.get_fdm().get_property("atmosphere/wind-east-fps") * 0.3048, 10.0, 1e-9, "blows towards the east")
	assert_almost_eq(a.get_fdm().get_property("atmosphere/wind-north-fps") * 0.3048, 0.0, 1e-9)
	_fly(a, 30.0)
	var v := a.get_linear_velocity()
	assert_almost_eq(wrapf(a.get_fdm().get_property("attitude/psi-deg"), -180.0, 180.0), 0.0, 1.0, "heading north")
	assert_almost_eq(v.x, 10.0, 1.0, "ground velocity east = the wind")
	assert_almost_eq(-v.z, a.get_fdm().get_property("velocities/vtrue-kts") * 0.514444, 1.0, "north = the true airspeed")
	assert_almost_eq(a.get_fdm().get_property("velocities/vc-kts"), 70.0, 1.5, "the airspeed is held")


func test_wind_set_in_flight() -> void:
	var a := _aircraft()
	_fly(a, 1.0)
	a.wind_direction = 180.0  # from the south: a tailwind
	a.wind_speed = 5.0
	assert_almost_eq(a.get_fdm().get_property("atmosphere/wind-north-fps") * 0.3048, 5.0, 1e-9)
	assert_almost_eq(a.get_fdm().get_property("atmosphere/wind-east-fps") * 0.3048, 0.0, 1e-9)
	a.wind_direction = 450.0
	assert_eq(a.wind_direction, 90.0, "wrapped to 0..360")


func test_wind_survives_restart() -> void:
	var a := _aircraft(8.0, 90.0)
	_fly(a, 2.0)
	assert_true(a.restart())
	assert_almost_eq(a.get_fdm().get_property("atmosphere/wind-east-fps") * 0.3048, -8.0, 1e-9)


func test_turbulence_shakes() -> void:
	var rates := []
	for severity in [0, 4]:
		var a := _aircraft(0.0, 270.0, severity)
		assert_eq(a.get_fdm().get_property("atmosphere/turb-type"), 3.0 if severity > 0 else 0.0)
		var sum := { "p2": 0.0, "n": 0 }
		_fly(a, 20.0, func() -> void:
			sum.p2 += pow(a.get_fdm().get_property("velocities/p-rad_sec"), 2)
			sum.n += 1)
		rates.append(sqrt(sum.p2 / sum.n))
		assert_false(a.is_crashed() or a.is_failed())
	gut.p("RMS roll rate: calm %.5f rad/s, moderate turbulence %.5f rad/s" % rates)
	assert_lt(rates[0], 0.002, "calm air")
	assert_gt(rates[1], 0.01, "moderate turbulence rolls the aircraft")
	assert_eq(_aircraft(0.0, 0.0, 12).turbulence, 7, "clamped to 7")
