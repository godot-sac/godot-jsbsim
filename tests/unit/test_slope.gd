extends GutTest
## Ground contact on a slope (JSBSim discussion #1510): the callback returns the terrain normal and keeps no state
## between calls. A J3Cub rests and taxis on a 5 % (2.9°) ramp rising towards +X; with the true normal the gear
## behaves as on flat ground, with a vertical normal (what #1510 reported) it does not.

const LAT := 39.95
const LON := 32.69
const SLOPE := 0.05
const GEAR := ["gear/unit[0]", "gear/unit[1]", "gear/unit[2]"]


func _ground(script: String, slope: float) -> Node:
	var ground := Node.new()
	ground.set_script(load(script))
	ground.name = "Ground"
	ground.set("slope", slope)
	ground.set("base", 0.0)
	add_child_autofree(ground)
	return ground


func _aircraft(heading: float) -> JSBSimAircraft:
	var a := JSBSimAircraft.new()
	a.latitude = LAT
	a.longitude = LON
	a.origin_latitude = LAT
	a.origin_longitude = LON
	a.origin_height = 1000.0
	a.heading = heading
	a.start_on_ground = true
	a.ground_path = NodePath("../Ground")
	add_child_autofree(a)
	a.paused = true
	return a


func _compressions(a: JSBSimAircraft) -> Array[float]:
	var result: Array[float] = []
	for unit: String in GEAR:
		result.append(a.get_fdm().get_property(unit + "/compression-ft") * 0.3048)
	return result


## Rests 10 s; returns the mean gear compressions (m) over the last 5 s.
func _rest(a: JSBSimAircraft) -> Array[float]:
	var sum: Array[float] = [0.0, 0.0, 0.0]
	for i in 600:
		a.advance(1.0 / 60.0)
		if i >= 300:
			var c := _compressions(a)
			for j in 3:
				sum[j] += c[j] / 300.0
	return sum


## Taxis `seconds` at a fixed throttle holding the heading (FlightAutopilot, tail down); returns the number of
## weight-on-wheels changes of each gear unit and the final ground speed.
func _taxi(a: JSBSimAircraft, throttle: float, seconds: float) -> Dictionary:
	var pilot := FlightAutopilot.new(a)
	pilot.heading = a.heading
	pilot.ground_pitch = 12.0
	a.throttle = throttle
	var last: Array[bool] = []
	var changes: Array[int] = [0, 0, 0]
	for unit: String in GEAR:
		last.append(a.get_fdm().get_property(unit + "/WOW") > 0.5)
	for i in int(seconds * 60.0):
		pilot.update()
		a.advance(1.0 / 60.0)
		for j in 3:
			var wow := a.get_fdm().get_property(GEAR[j] + "/WOW") > 0.5
			if wow != last[j]:
				changes[j] += 1
				last[j] = wow
	return { "changes": changes, "speed": a.get_linear_velocity().length(), "crashed": a.is_crashed() }


func test_normal_from_the_slope() -> void:
	_ground("res://tests/unit/fake_ground.gd", SLOPE)
	var a := _aircraft(90.0)
	var n := a.get_ground_normal(10.0, -20.0)
	assert_almost_eq(n.distance_to(Vector3(-SLOPE, 1.0, 0.0).normalized()), 0.0, 1e-6)


func test_ground_node_normal_is_used() -> void:
	var ground := _ground("res://tests/unit/fake_ground_normal.gd", SLOPE)
	ground.set("vertical", true)
	var a := _aircraft(90.0)
	assert_eq(a.get_ground_normal(0.0, 0.0), Vector3.UP)
	assert_gt(ground.get("normal_calls"), 0, "JSBSim's gear queries went through normal_at")


## The CG's height above the ground, asked after every gear unit at other heights, is still the ground right below
## the CG: nothing leaks from one call to the next (the bug found in #1510's own callback).
func test_no_state_between_calls() -> void:
	_ground("res://tests/unit/fake_ground.gd", SLOPE)
	var a := _aircraft(90.0)
	for i in 120:
		a.advance(1.0 / 60.0)
		var agl := a.get_fdm().get_property("position/h-agl-ft") * 0.3048
		var expected := a.position.y - a.get_ground_height(a.position.x, a.position.z)
		if i % 30 == 0:
			assert_almost_eq(agl, expected, 0.02, "frame %d" % i)
	# Same answers in any order.
	var points := [Vector2(3, 4), Vector2(-50, 7), Vector2(1200, -3), Vector2(3, 4)]
	var first := []
	for p: Vector2 in points:
		first.append([a.get_ground_height(p.x, p.y), a.get_ground_normal(p.x, p.y)])
	points.reverse()
	for k in points.size():
		var p: Vector2 = points[k]
		assert_eq([a.get_ground_height(p.x, p.y), a.get_ground_normal(p.x, p.y)], first[points.size() - 1 - k])


func test_resting_on_a_slope_compresses_like_flat_ground() -> void:
	_ground("res://tests/unit/fake_ground.gd", 0.0)
	var flat := _rest(_aircraft(90.0))
	remove_child(get_node("Ground"))
	_ground("res://tests/unit/fake_ground.gd", SLOPE)
	var slope := _rest(_aircraft(90.0))
	var total_flat: float = flat[0] + flat[1] + flat[2]
	var total_slope: float = slope[0] + slope[1] + slope[2]
	gut.p("compression (m) flat %s, uphill-facing on 5 %% %s" % [str(flat), str(slope)])
	assert_gt(total_flat, 0.0)
	assert_almost_eq(total_slope, total_flat, total_flat * 0.15, "total within 15 %")


func test_taxi_on_a_slope_does_not_bounce() -> void:
	for heading: float in [90.0, 270.0]:  # uphill, downhill
		for script: String in ["res://tests/unit/fake_ground.gd", "res://tests/unit/fake_ground_normal.gd"]:
			if has_node("Ground"):
				var old := get_node("Ground")
				remove_child(old)
				old.free()
			_ground(script, SLOPE)
			var result := _taxi(_aircraft(heading), 0.6 if heading == 90.0 else 0.25, 20.0)
			gut.p("heading %.0f, %s: WOW changes %s, speed %.1f m/s" % [
				heading, script.get_file(), str(result.changes), result.speed])
			assert_false(result.crashed)
			assert_gt(result.speed, 2.0, "it moves")
			for j in 3:
				assert_lte(result.changes[j], 1, "%s, heading %.0f, unit %d" % [script.get_file(), heading, j])


## What #1510 reported, reproduced: the same aircraft on the same ramp with a vertical normal over-compresses its
## gear at rest and bounces more when taxiing downhill. Shows that the normal reaches JSBSim and matters.
func test_vertical_normal_over_compresses() -> void:
	var ground := _ground("res://tests/unit/fake_ground_normal.gd", SLOPE)
	var true_normal := _rest(_aircraft(90.0))
	remove_child(ground)
	ground.free()
	ground = _ground("res://tests/unit/fake_ground_normal.gd", SLOPE)
	ground.set("vertical", true)
	var vertical := _rest(_aircraft(90.0))
	var downhill := _taxi(_aircraft(270.0), 0.25, 20.0)
	gut.p("compression (m) on 5 %%: true normal %s, vertical normal %s; downhill taxi with a vertical normal: WOW changes %s" % [
		str(true_normal), str(vertical), str(downhill.changes)])
	var total_true: float = true_normal[0] + true_normal[1] + true_normal[2]
	var total_vertical: float = vertical[0] + vertical[1] + vertical[2]
	assert_gt(total_vertical, total_true * 1.2, "a vertical normal compresses the gear over 20 % more")
