extends Node3D
## Flight demo: a JSBSim aircraft over flat ground near Ankara Esenboğa, keyboard / gamepad input, chase and cockpit
## cameras, HUD and debug keys. demo/terrain_flight.gd extends it with real terrain.
##
## Command line (after `--`):
##   --aircraft NAME     model from addons/jsbsim/data (default J3Cub)
##   --ground            start at rest on the ground (throttle up with R, brakes with B)
##   --seconds N         quit after N seconds of game time; prints a FLIGHT_CHECK line (exit code 1 on failure or
##                       crash)
##   --time-scale X      simulation speed (fast-forward tests)
##   --screenshot PATH   save a PNG just before quitting (needs a window, not --headless)
##   --cockpit           start with the cockpit camera
##   --aileron X         hold a fixed aileron command (input tests)
##   --takeoff           FlightAutopilot takes off (with --ground) and climbs straight ahead

const SCATTER_COUNT := 600
const SCATTER_RADIUS := 15000.0

@onready var aircraft: JSBSimAircraft = $Aircraft
@onready var pilot: JSBSimInput = $Aircraft/Input
@onready var chase_camera: Camera3D = $ChaseCamera
@onready var cockpit_camera: Camera3D = $Aircraft/CockpitCamera
@onready var hud: CanvasLayer = $HUD
@onready var ground: MeshInstance3D = get_node_or_null("Ground")

var _options := {}
var _quit_at := -1.0
var _game_time := 0.0
var _start_position := Vector3.ZERO
var _min_agl := INF
var _max_agl := -INF
var _log_timer := 0.0
var _fixed_aileron := NAN
var _autopilot: FlightAutopilot


func _ready() -> void:
	_options = _parse_args(OS.get_cmdline_user_args())
	if _options.has("aircraft"):
		aircraft.aircraft = _options.aircraft
	aircraft.start_on_ground = _options.has("ground")
	_setup_world()
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
	if _options.has("takeoff"):
		_autopilot = FlightAutopilot.new(aircraft)
		_autopilot.heading = aircraft.heading
		_autopilot.vertical_speed = 2.0
		pilot.process_mode = Node.PROCESS_MODE_DISABLED
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
		KEY_ESCAPE:
			get_tree().quit()


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
		fdm.get_property("attitude/theta-deg"), fdm.get_property("attitude/phi-deg"), aircraft.throttle])


func _finish() -> void:
	var fdm := aircraft.get_fdm()
	var distance := aircraft.position.distance_to(_start_position)
	var ok := aircraft.is_started() and not aircraft.is_failed() and not aircraft.is_crashed()
	print(("FLIGHT_CHECK %s aircraft=%s sim_time=%.2f distance=%.0f m agl=%.1f..%.1f m ias=%.1f kt hdg=%.1f "
			+ "on_ground=%s crashed=%s") % [
		"ok" if ok else "FAILED", aircraft.aircraft, fdm.get_sim_time() if fdm.is_loaded() else 0.0, distance,
		_min_agl, _max_agl, fdm.get_property("velocities/vc-kts") if fdm.is_loaded() else 0.0,
		fposmod(fdm.get_property("attitude/psi-deg"), 360.0) if fdm.is_loaded() else 0.0,
		aircraft.is_on_ground() if fdm.is_loaded() else false, aircraft.is_crashed()])
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
