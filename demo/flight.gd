extends Node3D
## Flight demo: a JSBSim aircraft over flat ground at Istanbul Sabiha Gökçen (LTFJ), keyboard / gamepad input, chase
## and cockpit cameras, HUD and debug keys. demo/terrain_flight.gd extends it with real terrain.
##
## Command line (after `--`):
##   --aircraft NAME     model from addons/jsbsim/data (default J3Cub)
##   --ground            start at rest on the ground (throttle up with R, brakes with B)
##   --seconds N         quit after N seconds of game time; prints a FLIGHT_CHECK line (exit code 1 on failure or
##                       crash)
##   --time-scale X      simulation speed (fast-forward tests)
##   --screenshot PATH   save a PNG just before quitting (needs a window, not --headless)
##   --cockpit           start with the cockpit camera
##   --no-hud            start with the HUD text hidden (H), for recordings
##   --aileron X         hold a fixed aileron command (input tests)
##   --takeoff           FlightAutopilot takes off (with --ground) and climbs straight ahead; with --route the
##                       JSBSimAutopilot takes over 150 m above the ground
##   --autopilot         JSBSimAutopilot holds the start heading, height and airspeed
##   --route             JSBSimAutopilot flies a 4 x 2 km loop ahead of the start, --route-agl above the start ground
##   --route-agl M       height of the route above the start ground (default 500)
##   --wind KT           steady wind speed in knots, --wind-from DEG its direction (default 270, from the west)
##   --turbulence N      MIL-F-8785C turbulence severity 0..7 (3 light, 4 moderate, 6 severe)
##   --dis               publish the aircraft on a DIS network with godot-dis (link it with tools/link_siblings.py):
##                       multicast 239.1.2.3, exercise 1, like the godot-dis and godot-geo demos
##   --port N            DIS port (default 3000); another port is a separate exercise, e.g. for tests
##   --marking TEXT      DIS marking (default the aircraft name)

const SCATTER_COUNT := 600
const SCATTER_RADIUS := 15000.0

@onready var aircraft: JSBSimAircraft = $Aircraft
@onready var pilot: JSBSimInput = $Aircraft/Input
@onready var chase_camera: Camera3D = $ChaseCamera
@onready var cockpit_camera: Camera3D = $Aircraft/CockpitCamera
@onready var hud: CanvasLayer = $HUD
@onready var ground: MeshInstance3D = get_node_or_null("Ground")
@onready var autopilot: JSBSimAutopilot = $Aircraft/Autopilot

var _options := {}
var _quit_at := -1.0
var _game_time := 0.0
var _start_position := Vector3.ZERO
var _min_agl := INF
var _max_agl := -INF
var _log_timer := 0.0
var _fixed_aileron := NAN
var _autopilot: FlightAutopilot
var _dis_entity: Node  # godot-dis DisEntity, created by name so the demo runs without godot-dis
var _start_ground := 0.0  # scene y of the ground under the start
var _waypoints_reached := 0


func _ready() -> void:
	_options = _parse_args(OS.get_cmdline_user_args())
	if _options.has("aircraft"):
		aircraft.aircraft = _options.aircraft
	aircraft.start_on_ground = _options.has("ground")
	aircraft.wind_speed = float(_options.get("wind", 0.0)) * 0.514444
	aircraft.wind_direction = float(_options.get("wind-from", 270.0))
	aircraft.turbulence = int(_options.get("turbulence", 0))
	_setup_world()
	if _options.has("dis"):
		_setup_dis()
	# The aircraft started in its own _ready(), before the options and the world were set up.
	if not aircraft.start():
		push_error("Cannot start %s: %s" % [aircraft.aircraft, aircraft.get_fdm().get_last_error()])
	if _options.has("time-scale"):
		aircraft.time_scale = float(_options["time-scale"])
	if _options.has("seconds"):
		_quit_at = float(_options.seconds)
	if _options.has("aileron"):
		_fixed_aileron = float(_options.aileron)
		pilot.process_mode = Node.PROCESS_MODE_DISABLED
	if _options.has("cockpit"):
		cockpit_camera.current = true
	if _options.has("no-hud"):
		hud.toggle_text()
	if _options.has("takeoff"):
		_autopilot = FlightAutopilot.new(aircraft)
		_autopilot.heading = aircraft.heading
		_autopilot.vertical_speed = 2.0
		pilot.process_mode = Node.PROCESS_MODE_DISABLED
	_start_ground = aircraft.get_ground_height(aircraft.position.x, aircraft.position.z)
	autopilot.waypoint_reached.connect(_on_waypoint_reached)
	if _options.has("route"):
		_build_route()
	if (_options.has("autopilot") or _options.has("route")) and not _autopilot:
		_engage_autopilot(_options.has("route"))
	aircraft.failed.connect(_on_stopped)
	aircraft.crashed.connect(_on_stopped)
	_start_position = aircraft.position
	chase_camera.snap()
	print("flight demo: %s, started=%s, data=%s" % [aircraft.aircraft, aircraft.is_started(),
			aircraft.get_fdm().get_data_path()])


func _physics_process(delta: float) -> void:
	if not is_nan(_fixed_aileron):
		aircraft.aileron = _fixed_aileron
	if _autopilot and not aircraft.paused:
		_autopilot.takeoff()
		var height_agl := aircraft.position.y - aircraft.get_ground_height(aircraft.position.x, aircraft.position.z)
		if _options.has("route") and height_agl > 150.0:
			print("takeoff done at t=%.1f s, the autopilot flies the route" % aircraft.get_fdm().get_sim_time())
			_autopilot = null
			_engage_autopilot(true)
	# Keep the ground mesh under the aircraft; the grid shader works in world space, so the lines stay put.
	if ground:
		ground.position = Vector3(snappedf(aircraft.position.x, 1000.0), aircraft.ground_level,
				snappedf(aircraft.position.z, 1000.0))
	if aircraft.paused or not aircraft.is_started():
		return
	_game_time += delta * aircraft.time_scale
	var agl := aircraft.get_fdm().get_property("position/h-agl-ft") * 0.3048
	_min_agl = minf(_min_agl, agl)
	_max_agl = maxf(_max_agl, agl)
	_log_timer += delta * aircraft.time_scale
	if _log_timer >= 10.0:
		_log_timer = 0.0
		_log_state()
	if _quit_at >= 0.0 and _game_time >= _quit_at:
		_quit_at = -1.0
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_P:
			aircraft.paused = not aircraft.paused
		KEY_N:
			if aircraft.paused:
				aircraft.advance(1.0 / 60.0)
		KEY_BRACKETLEFT:
			aircraft.time_scale = maxf(aircraft.time_scale * 0.5, 0.125)
		KEY_BRACKETRIGHT:
			aircraft.time_scale = minf(aircraft.time_scale * 2.0, 16.0)
		KEY_BACKSPACE:
			aircraft.restart()
			pilot.centre()
			chase_camera.snap()
		KEY_C:
			if chase_camera.current:
				cockpit_camera.current = true
			else:
				chase_camera.current = true
		KEY_F3:
			hud.toggle_properties()
		KEY_F4:
			hud.toggle_joypads()
		KEY_H:
			hud.toggle_text()
		KEY_Y:
			if autopilot.get_waypoint_count() == 0:
				_build_route()
			if autopilot.get_active_waypoint() < 0:
				autopilot.set_active_waypoint(0)
			autopilot.follow_route = not autopilot.follow_route
			if not autopilot.enabled:
				_engage_autopilot(autopilot.follow_route)
		KEY_COMMA:
			autopilot.heading_hold = true
			autopilot.follow_route = false
			autopilot.target_heading = fposmod(autopilot.target_heading - 10.0, 360.0)
		KEY_PERIOD:
			autopilot.heading_hold = true
			autopilot.follow_route = false
			autopilot.target_heading = fposmod(autopilot.target_heading + 10.0, 360.0)
		KEY_MINUS:
			autopilot.target_altitude -= 50.0
		KEY_EQUAL:
			autopilot.target_altitude += 50.0
		KEY_9:
			autopilot.target_speed -= 5.0
		KEY_0:
			autopilot.target_speed += 5.0
		KEY_ESCAPE:
			get_tree().quit()


## A DIS network, an origin at the aircraft's origin and a DisEntity on the aircraft. JSBSimAircraft gives the entity
## its velocities; the entity decides when to send (dead reckoning thresholds, heartbeat).
func _setup_dis() -> void:
	if not ClassDB.class_exists("DisEntity"):
		push_error("--dis needs godot-dis: run tools/link_siblings.py, then <godot> --headless --path . --import")
		return
	var network: Node = ClassDB.instantiate("DisNetwork")
	network.name = "DisNetwork"
	network.mode = 2  # multicast
	network.multicast_group = "239.1.2.3"
	network.port = int(_options.get("port", 3000))
	network.share_port = true  # next to other simulations on this computer
	network.exercise_id = 1
	network.site_id = 7
	network.application_id = 1
	add_child(network)
	var origin: Node = ClassDB.instantiate("DisGeoOrigin")
	origin.name = "DisGeoOrigin"
	origin.latitude = aircraft.origin_latitude
	origin.longitude = aircraft.origin_longitude
	origin.height = aircraft.origin_height
	add_child(origin)
	aircraft.geo_origin_path = aircraft.get_path_to(origin)
	_dis_entity = ClassDB.instantiate("DisEntity")
	_dis_entity.name = "DisEntity"
	_dis_entity.network_path = NodePath("../../DisNetwork")
	_dis_entity.origin_path = NodePath("../../DisGeoOrigin")
	_dis_entity.entity_id = Vector3i(0, 0, 1)  # site / application from the network
	_dis_entity.force_id = 1  # friendly
	_dis_entity.entity_type = JSBSimDisTypes.for_aircraft(aircraft.aircraft)
	_dis_entity.marking = str(_options.get("marking", aircraft.aircraft)).left(11)
	_dis_entity.dr_algorithm = 4  # DRM(R, V, W): rotation, velocity and acceleration, for manoeuvring aircraft
	aircraft.add_child(_dis_entity)
	print("DIS: publishing %s as %s, type %s, on 239.1.2.3:%d exercise 1" % [_dis_entity.marking,
			_dis_entity.get_effective_entity_id(), _dis_entity.entity_type, network.port])


## Turns the JSBSimAutopilot on with the current heading and airspeed; following the route, at its height.
## Keyboard and gamepad stay connected (throttle and brakes; the autopilot overrides the stick) unless the run is
## automated (--autopilot, --route).
func _engage_autopilot(follow_route: bool) -> void:
	if _options.has("route") or _options.has("autopilot"):
		pilot.process_mode = Node.PROCESS_MODE_DISABLED
	autopilot.engage()
	if follow_route and autopilot.get_waypoint_count() > 0:
		autopilot.target_altitude = autopilot.get_waypoint(maxi(autopilot.get_active_waypoint(), 0)).height
		autopilot.target_speed = maxf(autopilot.target_speed, aircraft.airspeed)  # not the climb speed
		autopilot.follow_route = true
	print("autopilot on: hdg %.0f, alt %.0f m, %.0f kt, route %s" % [autopilot.target_heading,
			autopilot.target_altitude, autopilot.target_speed, autopilot.follow_route])


## A 4 x 2 km loop: 3 km ahead of the start, 2 km to the right, back past the start, --route-agl above the start
## ground (scene y, which the autopilot keeps as a height above the ellipsoid).
func _build_route() -> void:
	var forward := Vector3(sin(deg_to_rad(aircraft.heading)), 0.0, -cos(deg_to_rad(aircraft.heading)))
	var right := Vector3(-forward.z, 0.0, forward.x)
	var y := _start_ground + float(_options.get("route-agl", 500.0))
	var start := Vector3(aircraft.position.x, y, aircraft.position.z)
	autopilot.clear_route()
	for offset: Vector2 in [Vector2(0, 3000), Vector2(2000, 3000), Vector2(2000, -1000), Vector2(0, -1000)]:
		autopilot.add_waypoint_local(start + right * offset.x + forward * offset.y)
	autopilot.loop_route = true
	print("route: %d waypoints, %.0f m above the start ground" % [autopilot.get_waypoint_count(), y - _start_ground])


func _on_waypoint_reached(index: int) -> void:
	_waypoints_reached += 1
	print("waypoint %d reached at t=%.1f s" % [index, aircraft.get_fdm().get_sim_time()])


## The scenery around the aircraft; terrain_flight.gd replaces it with real terrain.
func _setup_world() -> void:
	_scatter_landmarks()


func _on_stopped(reason: String) -> void:
	print("aircraft stopped: ", reason)
	if _quit_at >= 0.0:  # a --seconds run ends here instead of waiting
		_quit_at = -1.0
		_finish.call_deferred()


func _log_state() -> void:
	var fdm := aircraft.get_fdm()
	print("t=%5.1f s  pos=(%.0f, %.0f, %.0f) m  ias=%.1f kt  hdg=%.1f  pitch=%.1f  roll=%.1f  thr=%.2f" % [
		fdm.get_sim_time(), aircraft.position.x, aircraft.position.y, aircraft.position.z,
		fdm.get_property("velocities/vc-kts"), fposmod(fdm.get_property("attitude/psi-deg"), 360.0),
		fdm.get_property("attitude/theta-deg"), fdm.get_property("attitude/phi-deg"), aircraft.throttle]
		+ ("  dis_sent=%d" % _dis_entity.get_published_count() if _dis_entity else ""))


func _finish() -> void:
	var fdm := aircraft.get_fdm()
	var distance := aircraft.position.distance_to(_start_position)
	var ok := aircraft.is_started() and not aircraft.is_failed() and not aircraft.is_crashed()
	print(("FLIGHT_CHECK %s aircraft=%s sim_time=%.2f distance=%.0f m agl=%.1f..%.1f m ias=%.1f kt hdg=%.1f "
			+ "on_ground=%s crashed=%s dis_sent=%d autopilot=%s waypoints=%d") % [
		"ok" if ok else "FAILED", aircraft.aircraft, fdm.get_sim_time() if fdm.is_loaded() else 0.0, distance,
		_min_agl, _max_agl, fdm.get_property("velocities/vc-kts") if fdm.is_loaded() else 0.0,
		fposmod(fdm.get_property("attitude/psi-deg"), 360.0) if fdm.is_loaded() else 0.0,
		aircraft.is_on_ground() if fdm.is_loaded() else false, aircraft.is_crashed(),
		_dis_entity.get_published_count() if _dis_entity else -1, autopilot.enabled, _waypoints_reached])
	if _options.has("screenshot"):
		await RenderingServer.frame_post_draw
		var path: String = _options.screenshot
		var error := get_viewport().get_texture().get_image().save_png(path)
		print("screenshot: %s (%s)" % [path, error_string(error)])
	get_tree().quit(0 if ok else 1)


## Boxes of different sizes on the ground, to judge height and speed.
func _scatter_landmarks() -> void:
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.72, 0.65)
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = SCATTER_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in SCATTER_COUNT:
		var size := Vector3(rng.randf_range(10, 40), rng.randf_range(5, 60), rng.randf_range(10, 40))
		var at := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * SCATTER_RADIUS
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(size)
		multimesh.set_instance_transform(i, Transform3D(basis, Vector3(at.x, size.y * 0.5, at.y)))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	add_child(instance)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var result := {}
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg.begins_with("--"):
			var name := arg.substr(2)
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				result[name] = args[i + 1]
				i += 1
			else:
				result[name] = true
		i += 1
	return result
