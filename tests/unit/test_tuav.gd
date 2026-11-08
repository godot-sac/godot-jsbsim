extends GutTest
## The bundled TUAV model (aircraft/TUAV/, a generic small UAV made with AeromatiC++): it trims, holds the autopilot
## targets and flies a route in wind with the default JSBSimAutopilot gains, and rests on its gear on the ground.

const LAT := 41.02
const LON := 29.05
const FT := 0.3048
const KT_TO_FPS := 1.68781


func _aircraft(height := 600.0, speed := 65.0) -> JSBSimAircraft:
	var a := JSBSimAircraft.new()
	a.aircraft = "TUAV"
	a.latitude = LAT
	a.longitude = LON
	a.height = height
	a.heading = 0.0
	a.airspeed = speed
	a.origin_latitude = LAT
	a.origin_longitude = LON
	a.origin_height = 0.0
	var ap := JSBSimAutopilot.new()
	a.add_child(ap)
	add_child_autofree(a)
	a.paused = true
	return a


func _fly(a: JSBSimAircraft, seconds: float, each: Callable = Callable()) -> void:
	for i in int(round(seconds * 60.0)):
		a.advance(1.0 / 60.0)
		if each.is_valid():
			each.call()
		if a.is_crashed() or a.is_failed():
			return


func _height(a: JSBSimAircraft) -> float:
	return a.get_fdm().get_property("position/geod-alt-ft") * FT


func _kias(a: JSBSimAircraft) -> float:
	return a.get_fdm().get_property("velocities/vc-kts")


func test_loads_and_trims_across_its_speed_range() -> void:
	for speed: float in [55.0, 65.0, 80.0]:
		var a := _aircraft(600.0, speed)
		assert_true(a.is_started(), "loaded at %.0f kt" % speed)
		_fly(a, 30.0)
		assert_almost_eq(_height(a), 600.0, 10.0, "level after trim at %.0f kt" % speed)
		assert_almost_eq(_kias(a), speed, 2.0)


func test_autopilot_holds_and_steps() -> void:
	var a := _aircraft()
	var ap: JSBSimAutopilot = a.get_autopilot()
	ap.engage()
	_fly(a, 60.0)
	assert_almost_eq(_height(a), 600.0, 5.0)
	assert_almost_eq(_kias(a), 65.0, 1.5)
	ap.target_altitude = 900.0
	ap.target_heading = 180.0
	ap.target_speed = 70.0
	var worst := {"bank": 0.0}
	_fly(a, 180.0, func() -> void: worst.bank = maxf(worst.bank, absf(a.get_fdm().get_property("attitude/phi-deg"))))
	assert_false(a.is_crashed())
	assert_almost_eq(_height(a), 900.0, 15.0, "climbed 300 m")
	assert_almost_eq(wrapf(a.get_fdm().get_property("attitude/psi-deg") - 180.0, -180.0, 180.0), 0.0, 3.0)
	assert_almost_eq(_kias(a), 70.0, 2.5)
	# Lighter and quicker in roll than the J3Cub the default gains were tuned with: a few degrees past max_bank.
	assert_lt(worst.bank, ap.max_bank + 8.0)


func test_route_in_crosswind() -> void:
	var a := _aircraft()
	var ap: JSBSimAutopilot = a.get_autopilot()
	ap.engage()
	a.get_fdm().set_property("atmosphere/wind-east-fps", -15.0 * KT_TO_FPS)
	var y := a.position.y
	for p: Vector3 in [Vector3(0, y, -2000), Vector3(2000, y, -2000), Vector3(2000, y, 0), Vector3(0, y, 0)]:
		ap.add_waypoint_local(p)
	ap.follow_route = true
	var stats := {"reached": [], "worst": 0.0}
	ap.waypoint_reached.connect(func(i: int) -> void: stats.reached.append(i))
	_fly(a, 420.0, func() -> void:
		var d := ap.get_distance_to_waypoint()
		if ap.get_active_waypoint() >= 0 and d > 600.0 and d < 1400.0:
			stats.worst = maxf(stats.worst, absf(ap.get_cross_track_error())))
	assert_false(a.is_crashed())
	assert_eq(stats.reached, [0, 1, 2, 3], "all waypoints in order")
	assert_lt(stats.worst, 50.0, "mid-leg cross track with 15 kt crosswind")


func test_rests_on_its_gear() -> void:
	var a := JSBSimAircraft.new()
	a.aircraft = "TUAV"
	a.latitude = LAT
	a.longitude = LON
	a.origin_latitude = LAT
	a.origin_longitude = LON
	a.start_on_ground = true
	a.ground_level = 0.0
	add_child_autofree(a)
	a.paused = true
	assert_true(a.is_started())
	a.brake = 1.0
	_fly(a, 10.0)
	assert_false(a.is_crashed())
	assert_lt(a.get_fdm().get_property("position/h-agl-ft"), 3.0, "on the ground")
	assert_lt(_kias(a), 2.0, "standing still with the brakes on")
