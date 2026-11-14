extends GutTest
## JSBSimAutopilot with the J3Cub: holds, steps, a route with and without crosswind, frame-rate independence.
## tests/tune_autopilot.gd prints the same responses in more detail for tuning.

const LAT := 39.95
const LON := 32.69
const FT := 0.3048
const KT_TO_FPS := 1.68781


func _aircraft(with_autopilot := true) -> JSBSimAircraft:
	var a := JSBSimAircraft.new()
	a.aircraft = "J3Cub"
	a.latitude = LAT
	a.longitude = LON
	a.height = 1500.0
	a.heading = 0.0
	a.airspeed = 70.0
	a.origin_latitude = LAT
	a.origin_longitude = LON
	a.origin_height = 1000.0
	if with_autopilot:
		var ap := JSBSimAutopilot.new()
		ap.name = "Autopilot"
		a.add_child(ap)
	add_child_autofree(a)
	a.paused = true
	return a


func _fly(a: JSBSimAircraft, seconds: float, frame_rate := 60.0, each: Callable = Callable()) -> void:
	for i in int(round(seconds * frame_rate)):
		a.advance(1.0 / frame_rate)
		if each.is_valid():
			each.call()
		if a.is_crashed() or a.is_failed():
			return


func _height(a: JSBSimAircraft) -> float:
	return a.get_fdm().get_property("position/geod-alt-ft") * FT


func _square(a: JSBSimAircraft, side: float) -> void:
	var y := a.position.y
	for p: Vector3 in [Vector3(0, y, -side), Vector3(side, y, -side), Vector3(side, y, 0), Vector3(0, y, 0)]:
		a.get_autopilot().add_waypoint_local(p)


func test_found_by_the_aircraft() -> void:
	var a := _aircraft()
	assert_eq(a.get_autopilot(), a.get_node("Autopilot"))
	var ap: JSBSimAutopilot = a.get_autopilot()
	a.remove_child(ap)
	assert_null(a.get_autopilot(), "leaving the tree unregisters it")
	ap.free()
	assert_null(_aircraft(false).get_autopilot())


func test_disabled_leaves_the_controls_alone() -> void:
	var a := _aircraft()
	a.aileron = 0.2
	_fly(a, 1.0)
	assert_eq(a.aileron, 0.2)


func test_engage_holds_the_current_state() -> void:
	var a := _aircraft()
	var ap: JSBSimAutopilot = a.get_autopilot()
	ap.engage()
	assert_true(ap.enabled and ap.heading_hold and ap.altitude_hold and ap.speed_hold)
	assert_almost_eq(ap.target_altitude, 1500.0, 0.01)
	assert_almost_eq(ap.target_speed, 70.0, 0.01)
	_fly(a, 60.0)
	assert_almost_eq(_height(a), 1500.0, 5.0)
	assert_almost_eq(a.get_fdm().get_property("velocities/vc-kts"), 70.0, 1.0)
	assert_almost_eq(wrapf(a.get_fdm().get_property("attitude/psi-deg"), -180.0, 180.0), 0.0, 1.0)


func test_altitude_change() -> void:
	for delta: float in [305.0, -305.0]:
		var a := _aircraft()
		var ap: JSBSimAutopilot = a.get_autopilot()
		ap.engage()
		ap.target_altitude = 1500.0 + delta
		var peak := { "overshoot": 0.0 }
		_fly(a, 180.0, 60.0, func() -> void:
			peak.overshoot = maxf(peak.overshoot, (_height(a) - ap.target_altitude) * signf(delta)))
		assert_false(a.is_crashed())
		assert_almost_eq(_height(a), ap.target_altitude, 15.0, "%+.0f m within 15 m after 180 s" % delta)
		assert_lt(peak.overshoot, 30.0, "overshoot")
		# The climb is limited by the speed protection, not by stalling.
		assert_gt(a.get_fdm().get_property("velocities/vc-kts"), ap.min_airspeed)


func test_heading_change() -> void:
	for delta: float in [90.0, 180.0]:
		var a := _aircraft()
		var ap: JSBSimAutopilot = a.get_autopilot()
		ap.engage()
		ap.target_heading = delta
		var worst := { "bank": 0.0, "height": 0.0 }
		_fly(a, 60.0, 60.0, func() -> void:
			worst.bank = maxf(worst.bank, absf(a.get_fdm().get_property("attitude/phi-deg")))
			worst.height = maxf(worst.height, absf(_height(a) - 1500.0)))
		var psi := a.get_fdm().get_property("attitude/psi-deg")
		assert_almost_eq(wrapf(psi - delta, -180.0, 180.0), 0.0, 3.0, "turned %.0f°" % delta)
		assert_lt(worst.bank, ap.max_bank + 5.0, "bank stays near max_bank")
		assert_lt(worst.height, 15.0, "height held in the turn")


func test_speed_change() -> void:
	var a := _aircraft()
	var ap: JSBSimAutopilot = a.get_autopilot()
	ap.engage()
	ap.target_speed = 60.0
	_fly(a, 90.0)
	assert_almost_eq(a.get_fdm().get_property("velocities/vc-kts"), 60.0, 2.0)
	assert_lt(a.throttle, 0.8, "less power for less speed")


func test_square_route() -> void:
	for wind: float in [0.0, 20.0]:
		var a := _aircraft()
		var ap: JSBSimAutopilot = a.get_autopilot()
		ap.engage()
		# From the east: a crosswind on the north and south legs, head / tail wind on the others.
		a.get_fdm().set_property("atmosphere/wind-east-fps", -wind * KT_TO_FPS)
		_square(a, 2000.0)
		ap.follow_route = true
		assert_eq(ap.get_waypoint_count(), 4)
		assert_eq(ap.get_active_waypoint(), 0)
		watch_signals(ap)
		var stats := { "reached": [], "worst": 0.0 }
		ap.waypoint_reached.connect(func(i: int) -> void: stats.reached.append(i))
		_fly(a, 400.0, 60.0, func() -> void:
			var d := ap.get_distance_to_waypoint()
			if ap.get_active_waypoint() >= 0 and d > 600.0 and d < 1400.0:
				stats.worst = maxf(stats.worst, absf(ap.get_cross_track_error())))
		assert_false(a.is_crashed())
		assert_eq(stats.reached, [0, 1, 2, 3], "all waypoints in order, wind %.0f kt" % wind)
		assert_signal_emitted(ap, "route_finished")
		assert_lt(stats.worst, 30.0 if wind == 0.0 else 50.0, "mid-leg cross track, wind %.0f kt" % wind)
		assert_eq(ap.get_active_waypoint(), -1)
		assert_true(ap.heading_hold and not ap.follow_route, "keeps the last course afterwards")
		assert_almost_eq(ap.target_heading, 270.0, 1.0, "the last leg runs west")


func test_loop_route_and_waypoint_targets() -> void:
	var a := _aircraft()
	var ap: JSBSimAutopilot = a.get_autopilot()
	ap.engage()
	ap.loop_route = true
	ap.add_waypoint(LAT + 1500.0 / 111000.0, LON)  # 1.5 km north, no height or speed: keeps the targets
	ap.add_waypoint(LAT, LON, 1600.0, 65.0)  # back over the origin, higher and slower
	assert_true(is_nan(ap.get_waypoint(0).height))
	assert_true(is_nan(ap.get_waypoint(0).speed))
	ap.follow_route = true
	var reached := { "list": [] }
	ap.waypoint_reached.connect(func(i: int) -> void: reached.list.append(i))
	_fly(a, 240.0)
	assert_gt(reached.list.size(), 2, "keeps looping")
	assert_eq(reached.list.slice(0, 3), [0, 1, 0])
	assert_true(ap.follow_route)
	assert_almost_eq(ap.target_altitude, 1600.0, 0.01, "the second waypoint set the height")
	assert_almost_eq(ap.target_speed, 65.0, 0.01)


func test_local_waypoint_round_trip() -> void:
	var a := _aircraft()
	var ap: JSBSimAutopilot = a.get_autopilot()
	ap.add_waypoint_local(Vector3(1234.5, 321.0, -5678.25), 80.0)
	var w := ap.get_waypoint(0)
	assert_almost_eq((w.position as Vector3).distance_to(Vector3(1234.5, 321.0, -5678.25)), 0.0, 0.01)
	assert_almost_eq(w.height, 1000.0 + 321.0, 3.0, "scene y over a 1000 m origin, plus the curvature at 5.8 km")
	assert_eq(w.speed, 80.0)
	ap.clear_route()
	assert_eq(ap.get_waypoint_count(), 0)
	assert_eq(ap.get_active_waypoint(), -1)


func test_clearing_the_route_from_a_signal() -> void:
	var a := _aircraft()
	var ap: JSBSimAutopilot = a.get_autopilot()
	ap.engage()
	ap.add_waypoint_local(Vector3(0, 0, -500))
	ap.add_waypoint_local(Vector3(500, 0, -500))
	ap.follow_route = true
	ap.waypoint_reached.connect(func(_i: int) -> void: ap.clear_route())
	_fly(a, 60.0)
	assert_false(a.is_crashed())
	assert_eq(ap.get_waypoint_count(), 0)


## The autopilot and the controls act at every JSBSim step, so the frame rate does not change the flight.
func test_same_flight_at_any_frame_rate() -> void:
	var results: Array[PackedFloat64Array] = []
	for frame_rate: float in [120.0, 60.0, 30.0, 20.0, 7.5]:
		var a := _aircraft()
		var ap: JSBSimAutopilot = a.get_autopilot()
		ap.engage()
		_square(a, 1500.0)
		ap.follow_route = true
		_fly(a, 90.0, frame_rate)
		assert_almost_eq(a.get_fdm().get_sim_time(), 90.0, 1e-6, "%.1f FPS" % frame_rate)
		results.append(a.get_geodetic_position())
	for i in range(1, results.size()):
		assert_eq(results[i], results[0], "identical position, run %d" % i)


func test_single_waypoint_loop_is_reached_once() -> void:
	var a := _aircraft()
	var ap: JSBSimAutopilot = a.get_autopilot()
	ap.engage()
	ap.loop_route = true
	ap.add_waypoint_local(Vector3(0, a.position.y, -800))
	ap.follow_route = true
	watch_signals(ap)
	_fly(a, 60.0)
	assert_signal_emit_count(ap, "waypoint_reached", 1)
	assert_signal_emitted(ap, "route_finished")


func test_restart_keeps_flying() -> void:
	var a := _aircraft()
	var ap: JSBSimAutopilot = a.get_autopilot()
	ap.engage()
	ap.target_altitude = 1700.0
	_fly(a, 30.0)
	assert_true(a.restart())
	assert_true(ap.enabled, "the autopilot stays on")
	_fly(a, 120.0)
	assert_false(a.is_crashed())
	assert_almost_eq(_height(a), 1700.0, 15.0, "climbs again from the restart")


func test_a_waypoint_added_after_the_route_ended_is_flown() -> void:
	var a := _aircraft()
	var ap: JSBSimAutopilot = a.get_autopilot()
	ap.engage()
	ap.add_waypoint_local(Vector3(0, a.position.y, -800))
	ap.follow_route = true
	watch_signals(ap)
	_fly(a, 40.0)
	assert_signal_emitted(ap, "route_finished")
	assert_false(ap.follow_route)
	# A new waypoint after the end picks the route up again, from where the aircraft is.
	ap.add_waypoint_local(Vector3(1500, a.position.y, -800))
	assert_eq(ap.get_active_waypoint(), 1)
	assert_true(ap.follow_route)
	_fly(a, 90.0)
	assert_signal_emit_count(ap, "waypoint_reached", 2)
	assert_signal_emit_count(ap, "route_finished", 2)


func test_waypoint_without_height_is_shown_at_the_aircraft_height() -> void:
	var a := _aircraft()
	var ap: JSBSimAutopilot = a.get_autopilot()
	ap.add_waypoint(LAT + 0.01, LON)  # no height: flown at the current height
	var w := ap.get_waypoint(0)
	assert_true(is_nan(w.height))
	assert_almost_eq((w.position as Vector3).y, a.position.y, 2.0, "about the aircraft's scene height")
