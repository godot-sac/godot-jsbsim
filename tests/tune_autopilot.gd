extends SceneTree
## Autopilot step responses for tuning (not a test): prints overshoot, settling and tracking numbers for the J3Cub.
## godot --headless --path . -s res://tests/tune_autopilot.gd [-- --aircraft J3Cub]

const FT := 0.3048


func _init() -> void:
	await process_frame
	_altitude_step(305.0)
	_altitude_step(-305.0)
	_heading_step(90.0)
	_heading_step(180.0)
	_speed_step(-10.0)
	_square(0.0)
	_square(20.0)
	quit()


func _make() -> Array:
	var a := JSBSimAircraft.new()
	a.aircraft = "J3Cub"
	a.height = 1500.0
	a.airspeed = 70.0
	a.heading = 0.0
	var ap := JSBSimAutopilot.new()
	a.add_child(ap)
	root.add_child(a)
	a.paused = true
	return [a, ap]


func _run(a: JSBSimAircraft, seconds: float, each: Callable) -> void:
	var t := 0.0
	while t < seconds and not a.is_crashed() and not a.is_failed():
		a.advance(1.0 / 60.0)
		t += 1.0 / 60.0
		each.call(t)


func _done(a: JSBSimAircraft) -> void:
	a.queue_free()


func _alt(a: JSBSimAircraft) -> float:
	return a.get_fdm().get_property("position/geod-alt-ft") * FT


func _altitude_step(delta: float) -> void:
	var pair := _make()
	var a: JSBSimAircraft = pair[0]
	var ap: JSBSimAutopilot = pair[1]
	ap.engage()
	ap.target_altitude += delta
	var target := ap.target_altitude
	# GDScript lambdas capture locals by value: keep what they change in a dictionary.
	var stats := { "min_ias": 999.0, "peak": 0.0, "settled": -1.0 }
	_run(a, 240.0, func(t: float) -> void:
		var e := _alt(a) - target
		stats.peak = maxf(stats.peak, e * signf(delta))
		if absf(e) > 15.0:
			stats.settled = -1.0
		elif stats.settled < 0.0:
			stats.settled = t
		stats.min_ias = minf(stats.min_ias, a.get_fdm().get_property("velocities/vc-kts")))
	print("altitude %+.0f m: final error %.1f m, overshoot %.1f m, settled (15 m) at %.0f s, min ias %.1f kt, crashed %s" % [
		delta, _alt(a) - target, stats.peak, stats.settled, stats.min_ias, a.is_crashed()])
	_done(a)


func _heading_step(delta: float) -> void:
	var pair := _make()
	var a: JSBSimAircraft = pair[0]
	var ap: JSBSimAutopilot = pair[1]
	ap.engage()
	ap.target_heading = wrapf(ap.target_heading + delta, 0.0, 360.0)
	var stats := { "alt_dev": 0.0, "max_bank": 0.0, "settled": -1.0, "over": 0.0 }
	var start_alt := _alt(a)
	_run(a, 120.0, func(t: float) -> void:
		var psi := a.get_fdm().get_property("attitude/psi-deg")
		var e := wrapf(psi - ap.target_heading, -180.0, 180.0)
		if absf(e) > 3.0:
			stats.settled = -1.0
		elif stats.settled < 0.0:
			stats.settled = t
		if stats.settled > 0.0:
			stats.over = maxf(stats.over, absf(e))
		stats.alt_dev = maxf(stats.alt_dev, absf(_alt(a) - start_alt))
		stats.max_bank = maxf(stats.max_bank, absf(a.get_fdm().get_property("attitude/phi-deg"))))
	var psi := a.get_fdm().get_property("attitude/psi-deg")
	print("heading %+.0f: final error %.2f deg, settled (3 deg) at %.0f s, max error after %.2f, max bank %.1f, height dev %.1f m" % [
		delta, wrapf(psi - ap.target_heading, -180.0, 180.0), stats.settled, stats.over, stats.max_bank, stats.alt_dev])
	_done(a)


func _speed_step(delta: float) -> void:
	var pair := _make()
	var a: JSBSimAircraft = pair[0]
	var ap: JSBSimAutopilot = pair[1]
	ap.engage()
	ap.target_speed += delta
	var stats := { "alt_dev": 0.0 }
	var start_alt := _alt(a)
	_run(a, 120.0, func(_t: float) -> void:
		stats.alt_dev = maxf(stats.alt_dev, absf(_alt(a) - start_alt)))
	print("speed %+.0f kt: final error %.2f kt, throttle %.2f, height dev %.1f m" % [
		delta, a.get_fdm().get_property("velocities/vc-kts") - ap.target_speed, a.throttle, stats.alt_dev])
	_done(a)


func _square(wind_kt: float) -> void:
	var pair := _make()
	var a: JSBSimAircraft = pair[0]
	var ap: JSBSimAutopilot = pair[1]
	ap.engage()
	# Crosswind from the east (blowing west) for the north and south legs.
	a.get_fdm().set_property("atmosphere/wind-east-fps", -wind_kt * 1.68781)
	var y := a.position.y
	for p: Vector3 in [Vector3(0, y, -2000), Vector3(2000, y, -2000), Vector3(2000, y, 0), Vector3(0, y, 0)]:
		ap.add_waypoint_local(p)
	ap.follow_route = true
	var stats := { "reached": [], "worst_mid": 0.0, "finished": -1.0 }
	ap.waypoint_reached.connect(func(i: int) -> void: stats.reached.append(i))
	_run(a, 600.0, func(t: float) -> void:
		if stats.finished < 0.0 and ap.get_active_waypoint() < 0:
			stats.finished = t
		# Middle of a leg: more than 600 m from both ends.
		if ap.get_active_waypoint() >= 0 and ap.get_distance_to_waypoint() > 600.0 and ap.get_distance_to_waypoint() < 1400.0:
			stats.worst_mid = maxf(stats.worst_mid, absf(ap.get_cross_track_error())))
	print("square, wind %.0f kt: reached %s, finished at %.0f s, worst mid-leg cross track %.1f m, crashed %s" % [
		wind_kt, stats.reached, stats.finished, stats.worst_mid, a.is_crashed()])
	_done(a)
