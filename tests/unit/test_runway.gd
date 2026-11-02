extends GutTest
## Takeoff and landing with FlightAutopilot (demo/autopilot.gd) on real terrain: Istanbul Sabiha Gökçen's (LTFJ) north
## runway in godot-geo's 60 km Üsküdar package, the ground JSBSim's gear touches (JSBSimAircraft.ground_path). Needs
## godot-geo and the package linked (tools/link_siblings.py); skipped otherwise.

const GEO_TERRAIN := "res://addons/geo/geo_terrain.gd"
const PACKAGE := "res://terrain/uskudar"
## Runway 06/24 ends (OpenStreetMap via Overture 2026-10-21) and its half width, like demo/terrain_flight.gd.
const RUNWAY_06 := Vector2(40.892641, 29.293205)
const RUNWAY_24 := Vector2(40.904441, 29.325242)
const HALF_WIDTH := 22.5
const HEADING := 64.0
const REST_HEIGHT := 1.15  # J3Cub CG above the ground on its gear (test_ground.gd)

var _terrain: Node3D
var _threshold: Vector3  # runway 06 end, scene position on the ground
var _direction: Vector3  # unit vector along the runway, 06 to 24
var _length := 0.0


func should_skip_script():
	if not ResourceLoader.exists(GEO_TERRAIN) or not FileAccess.file_exists(PACKAGE.path_join("terrain.json")):
		return "godot-geo or its terrain/uskudar package is not linked (tools/link_siblings.py)"
	return false


func before_all() -> void:
	_terrain = Node3D.new()
	_terrain.set_script(load(GEO_TERRAIN))
	_terrain.set("collision_enabled", false)
	_terrain.set("auto_layers", false)  # buildings and trees are not ground
	add_child(_terrain)
	_terrain.set("package_path", PACKAGE)
	_threshold = _terrain.call("geodetic_to_global", RUNWAY_06.x, RUNWAY_06.y, 0.0)
	var far: Vector3 = _terrain.call("geodetic_to_global", RUNWAY_24.x, RUNWAY_24.y, 0.0)
	_direction = Vector3(far.x - _threshold.x, 0.0, far.z - _threshold.z)
	_length = _direction.length()
	_direction /= _length


func after_all() -> void:
	_terrain.free()


## A J3Cub `along` metres down runway 06 from its end, on the gear or `agl` metres above the runway.
func _aircraft(along: float, on_ground: bool, agl := 0.0, airspeed := 60.0) -> JSBSimAircraft:
	var info: Object = _terrain.get("package")
	var at := _threshold + _direction * along
	var geo: PackedFloat64Array = _terrain.call("global_to_geodetic", at)
	var a := JSBSimAircraft.new()
	a.origin_latitude = info.get("latitude")
	a.origin_longitude = info.get("longitude")
	a.origin_height = info.get("origin_height")
	a.latitude = geo[0]
	a.longitude = geo[1]
	a.height = float(_terrain.call("geodetic_height", geo[0], geo[1])) + agl
	a.heading = HEADING
	a.airspeed = airspeed
	a.start_on_ground = on_ground
	add_child_autofree(a)
	a.ground_path = a.get_path_to(_terrain)
	a.paused = true
	assert_true(a.start(), "restarted on the terrain ground")
	return a


## Distance along the runway from the 06 end and from the centre line (+ right), metres.
func _runway_position(a: JSBSimAircraft) -> Vector2:
	var d := Vector3(a.position.x - _threshold.x, 0.0, a.position.z - _threshold.z)
	return Vector2(d.dot(_direction), d.dot(Vector3(-_direction.z, 0.0, _direction.x)))


func _agl(a: JSBSimAircraft) -> float:
	return a.position.y - float(_terrain.call("height_at", a.position.x, a.position.z)) - REST_HEIGHT


func test_runway_geometry() -> void:
	assert_almost_eq(_length, 2998.0, 10.0, "3 km runway")
	assert_almost_eq(fposmod(rad_to_deg(atan2(_direction.x, -_direction.z)), 360.0), HEADING, 1.0, "runway 06, true")
	var heights: Array[float] = []
	for k in 7:
		var p := _threshold + _direction * (_length * k / 6.0)
		heights.append(_terrain.call("height_at", p.x, p.z))
	assert_lt(heights.max() - heights.min(), 8.0, "nearly level along the runway")


func test_takeoff_from_runway_06() -> void:
	var a := _aircraft(150.0, true)
	assert_true(a.is_on_ground())
	var pilot := FlightAutopilot.new(a)
	pilot.heading = HEADING
	pilot.vertical_speed = 2.0
	var lift_off := Vector2(-1.0, 0.0)
	var worst_offset := 0.0
	for i in 3600:
		pilot.takeoff()
		a.advance(1.0 / 60.0)
		if a.is_crashed():
			break
		if lift_off.x < 0.0:
			worst_offset = maxf(worst_offset, absf(_runway_position(a).y))
			if not a.is_on_ground() and _agl(a) > 3.0:
				lift_off = _runway_position(a)
	assert_false(a.is_crashed())
	assert_between(lift_off.x, 300.0, 1500.0, "lifted off on the runway (metres from the 06 end)")
	assert_lt(worst_offset, HALF_WIDTH, "stayed on the runway")
	assert_gt(_agl(a), 40.0, "climbing after 60 s")


func test_landing_on_runway_06() -> void:
	var a := _aircraft(0.0, false, 60.0, 60.0)
	var pilot := FlightAutopilot.new(a)
	pilot.heading = HEADING
	a.throttle = 0.3
	for i in 150 * 60:
		var agl := _agl(a)
		pilot.vertical_speed = -2.0 if agl > 8.0 else (-0.6 if agl > 0.5 else -0.2)
		if agl < 8.0:
			a.throttle = 0.0
		if a.is_on_ground():
			pilot.vertical_speed = 0.0
			pilot.ground_pitch = 20.0  # stick back: keeps the tail down while braking
			a.brake = 0.4 if a.get_fdm().get_property("velocities/vc-kts") < 30.0 else 0.0
		pilot.update()
		a.advance(1.0 / 60.0)
		if a.is_crashed():
			break
	assert_false(a.is_crashed())
	assert_true(a.is_on_ground())
	assert_lt(a.get_linear_velocity().length(), 0.5, "stopped")
	var at := _runway_position(a)
	assert_between(at.x, 200.0, _length, "stopped on the runway")
	assert_lt(absf(at.y), HALF_WIDTH, "on the centre line")
	assert_almost_eq(_agl(a), 0.0, 0.2, "on the gear")
