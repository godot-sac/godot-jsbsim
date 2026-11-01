extends GutTest
## JSBSimAircraft with a godot-dis DisEntity child: the Entity State PDU it would send is checked against JSBSim's
## own position, attitude, velocity and rates. Needs godot-dis linked (tools/link_siblings.py); skipped otherwise.
## godot-dis classes are reached by name so this script parses without them.

const LAT := 39.95
const LON := 32.69
const ORIGIN_HEIGHT := 1000.0
const M_PER_FT := 0.3048
const DESTROYED := 3 << 3  # appearance damage bits 3-4

var _origin: Node


func should_skip_script():
	return false if ClassDB.class_exists("DisEntity") else "godot-dis is not linked (tools/link_siblings.py)"


func before_each() -> void:
	_origin = ClassDB.instantiate("DisGeoOrigin")
	_origin.latitude = LAT
	_origin.longitude = LON
	_origin.height = ORIGIN_HEIGHT
	add_child_autofree(_origin)


## An airborne (or resting) J3Cub at the origin with a DisEntity child that publishes nothing (no network).
func _aircraft(on_ground := false) -> JSBSimAircraft:
	var a := JSBSimAircraft.new()
	a.latitude = LAT
	a.longitude = LON
	a.height = ORIGIN_HEIGHT + 300.0
	a.heading = 90.0
	a.airspeed = 60.0
	a.start_on_ground = on_ground
	a.geo_origin_path = _origin.get_path()
	var entity: Node = ClassDB.instantiate("DisEntity")
	entity.name = "DisEntity"
	entity.origin_path = _origin.get_path()
	entity.entity_id = Vector3i(1, 1, 1)
	entity.auto_update = false
	entity.publishing = false
	a.add_child(entity)
	add_child_autofree(a)
	a.paused = true
	return a


func _entity(a: JSBSimAircraft) -> Node:
	return a.get_node("DisEntity")


func _fly(a: JSBSimAircraft, seconds: float) -> void:
	for i in int(seconds * 60.0):
		a.advance(1.0 / 60.0)


## JSBSim's north / east / down velocity in ECEF axes at the aircraft's position (m/s).
func _jsbsim_ecef_velocity(a: JSBSimAircraft) -> Vector3:
	var fdm := a.get_fdm()
	var lat := deg_to_rad(fdm.get_property("position/lat-geod-deg"))
	var lon := deg_to_rad(fdm.get_property("position/long-gc-deg"))
	var east := Vector3(-sin(lon), cos(lon), 0.0)
	var north := Vector3(-sin(lat) * cos(lon), -sin(lat) * sin(lon), cos(lat))
	var up := Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
	return (east * fdm.get_property("velocities/v-east-fps") + north * fdm.get_property("velocities/v-north-fps")
			- up * fdm.get_property("velocities/v-down-fps")) * M_PER_FT


func test_entity_uses_jsbsim_velocities() -> void:
	var a := _aircraft()
	assert_true(a.is_started(), a.get_fdm().get_last_error())
	var entity := _entity(a)
	assert_eq(entity.velocity_source, 1, "VELOCITY_MANUAL")
	assert_almost_eq(entity.linear_velocity, a.get_linear_velocity(), Vector3.ONE * 1e-4)
	assert_gt(a.get_linear_velocity().length(), 25.0)


func test_pdu_matches_jsbsim() -> void:
	var a := _aircraft()
	a.aileron = 0.3
	a.elevator = -0.1
	_fly(a, 3.0)
	assert_false(a.is_crashed())
	var fdm := a.get_fdm()
	var pdu: Object = _entity(a).create_pdu()

	var geodetic: PackedFloat64Array = ClassDB.class_call_static("DisGeo", "ecef_to_geodetic", pdu.location_ecef)
	var expected := a.get_geodetic_position()
	assert_almost_eq(geodetic[0], expected[0], 1e-7, "latitude (~1 cm)")
	assert_almost_eq(geodetic[1], expected[1], 1e-7, "longitude (~1 cm)")
	assert_almost_eq(geodetic[2], expected[2], 0.02, "height above the ellipsoid")

	var hpr: Vector3 = ClassDB.class_call_static("DisGeo", "dis_euler_to_heading_pitch_roll", pdu.orientation,
			geodetic[0], geodetic[1])
	assert_almost_eq(wrapf(rad_to_deg(hpr.x) - fdm.get_property("attitude/psi-deg"), -180.0, 180.0), 0.0, 0.01,
			"heading")
	assert_almost_eq(rad_to_deg(hpr.y), fdm.get_property("attitude/theta-deg"), 0.01, "pitch")
	assert_almost_eq(rad_to_deg(hpr.z), fdm.get_property("attitude/phi-deg"), 0.01, "roll")
	assert_gt(absf(fdm.get_property("attitude/phi-deg")), 5.0, "banked, so roll is really tested")

	assert_almost_eq(pdu.linear_velocity, _jsbsim_ecef_velocity(a), Vector3.ONE * 0.01, "ECEF velocity")
	var pqr := Vector3(fdm.get_property("velocities/p-rad_sec"), fdm.get_property("velocities/q-rad_sec"),
			fdm.get_property("velocities/r-rad_sec"))
	assert_almost_eq(pdu.dr_angular_velocity, pqr, Vector3.ONE * 1e-4, "body rates p, q, r")
	assert_gt(pqr.length(), 0.02, "turning, so the rates are really tested")


func test_acceleration_matches_velocity_change() -> void:
	var a := _aircraft()
	a.aileron = 0.4
	_fly(a, 4.0)
	var entity := _entity(a)
	var v0: Vector3 = entity.create_pdu().linear_velocity
	var acc0: Vector3 = entity.create_pdu().dr_linear_acceleration
	a.advance(1.0 / 60.0)
	var v1: Vector3 = entity.create_pdu().linear_velocity
	var acc1: Vector3 = entity.create_pdu().dr_linear_acceleration
	var measured := (v1 - v0) * 60.0
	assert_gt(measured.length(), 1.0, "turning: the acceleration is not small")
	assert_almost_eq((acc0 + acc1) * 0.5, measured, Vector3.ONE * 0.05, "ECEF acceleration")


func test_time_scale_and_pause() -> void:
	var a := _aircraft()
	a.time_scale = 2.0
	a.advance(1.0 / 60.0)
	var entity := _entity(a)
	assert_almost_eq(entity.linear_velocity, a.get_linear_velocity() * 2.0, Vector3.ONE * 1e-4,
			"velocity in game time")
	assert_almost_eq(entity.angular_velocity.length(), a.get_angular_velocity().length() * 2.0, 1e-5)
	await wait_physics_frames(3)
	assert_eq(entity.linear_velocity, Vector3.ZERO, "paused and not advanced: stationary")
	assert_eq(entity.linear_acceleration, Vector3.ZERO)


func test_crash_marks_the_entity_destroyed() -> void:
	var a := _aircraft()
	var entity := _entity(a)
	entity.appearance = 1  # another bit, kept
	a.elevator = 0.6
	_fly(a, 30.0)
	assert_true(a.is_crashed())
	assert_eq(entity.appearance, DESTROYED | 1)
	assert_eq(entity.linear_velocity, Vector3.ZERO, "stopped")
	assert_true(a.restart())
	assert_eq(entity.appearance, 1, "repaired after restart")


func test_bundled_aircraft_types() -> void:
	var enums: Script = load("res://addons/dis/dis_enums.gd")
	assert_string_contains(enums.get_entity_type_name(JSBSimDisTypes.for_aircraft("J3Cub")), "J-3 Cub")
	assert_string_contains(enums.get_entity_type_name(JSBSimDisTypes.for_aircraft("pc7")), "PC-7")
	assert_eq(JSBSimDisTypes.for_aircraft("unknown").size(), 0)
