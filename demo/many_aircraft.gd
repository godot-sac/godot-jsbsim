extends Node3D
## Many aircraft at once: N J3Cubs spaced evenly around a 6 x 3 km loop, each flown by its own JSBSimAutopilot.
## Shows and measures the cost of the simulation (docs/performance.md).
##
## Keys: Tab next aircraft, O overview camera, P pause, [ ] time scale, Esc quit.
## Command line (after `--`):
##   --count N           number of aircraft (default 20)
##   --seconds N         quit after N seconds of game time and print a PERF line (exit code 1 on a crash)
##   --time-scale X      simulation speed
##   --gdscript-ground   ground queries go to a GDScript node (flat_ground.gd) instead of the built-in flat ground
##   --terrain           godot-geo terrain (linked with tools/link_siblings.py) as everyone's ground, 700 m below
##   --no-models         no meshes: the simulation cost only
##   --no-autopilot      fixed controls (trimmed level flight) instead of the autopilot
##   --overview          start with the overview camera
##   --screenshot PATH   save a PNG just before quitting (needs a window, not --headless)

const LOOP := [Vector2(0, 0), Vector2(0, -6000), Vector2(3000, -6000), Vector2(3000, 0)]  # x east, z (north = -z)
const ROUTE_AGL := 500.0
const TERRAIN_AGL := 700.0
const GEO_TERRAIN := "res://addons/geo/geo_terrain.gd"
const TERRAIN_PACKAGES := ["res://terrain/uskudar"]
const MARKER_LAYER := 8  # visual layer 4: the overview markers, left out of the chase camera
const WGS84_A := 6378137.0
const WGS84_E2 := 0.00669437999014

@onready var chase_camera: Camera3D = $ChaseCamera
@onready var overview_camera: Camera3D = $OverviewCamera
@onready var label: Label = $HUD/Label

var aircraft: Array[JSBSimAircraft] = []
var origin := Vector3(40.893231, 29.294808, 126.0)  # latitude, longitude, ellipsoid height of the scene origin
var ground_y := 0.0  # scene y of the ground under the loop start
var _loop_offset := Vector3.ZERO  # scene position of the loop's first corner
var _options := {}
var _selected := 0
var _quit_at := -1.0
var _game_time := 0.0
var _wall_start := 0
var _frames := 0
var _steps := 0
var _step_usec := 0.0
var _worst_frame_usec := 0.0
var _crashes := 0


func _ready() -> void:
	_options = _parse_args(OS.get_cmdline_user_args())
	# After the aircraft's own _physics_process, to read what they did this frame.
	process_physics_priority = 10
	var ground := _setup_ground()
	var count := int(_options.get("count", 20))
	for i in count:
		_spawn(i, count, ground)
	_select(0)
	chase_camera.cull_mask &= ~MARKER_LAYER
	if _options.has("time-scale"):
		for plane in aircraft:
			plane.time_scale = float(_options["time-scale"])
	if _options.has("seconds"):
		_quit_at = float(_options.seconds)
	if _options.has("overview"):
		overview_camera.current = true
	_wall_start = Time.get_ticks_usec()
	print("many aircraft: %d J3Cub, ground %s, autopilot %s, models %s" % [count,
			"terrain" if _options.has("terrain") else ("GDScript node" if ground else "built-in flat"),
			not _options.has("no-autopilot"), not _options.has("no-models")])


func _setup_ground() -> Node:
	if _options.has("terrain"):
		return _setup_terrain()
	$Ground.position.y = 0.0
	if _options.has("gdscript-ground"):
		var node := Node.new()
		node.set_script(load("res://demo/flat_ground.gd"))
		node.name = "FlatGround"
		add_child(node)
		return node
	return null


func _setup_terrain() -> Node:
	$Ground.queue_free()
	var package := ""
	for candidate: String in TERRAIN_PACKAGES:
		if FileAccess.file_exists(candidate.path_join("terrain.json")):
			package = candidate
			break
	if not ResourceLoader.exists(GEO_TERRAIN) or package == "":
		push_error("--terrain needs godot-geo and a terrain package: run python tools/link_siblings.py")
		get_tree().quit(1)
		return null
	var terrain := Node3D.new()
	terrain.set_script(load(GEO_TERRAIN))
	terrain.name = "Terrain"
	terrain.set("collision_enabled", false)
	add_child(terrain)
	terrain.set("package_path", package)
	var info: Object = terrain.get("package")
	origin = Vector3(info.get("latitude"), info.get("longitude"), info.get("origin_height"))
	# The loop starts at Sabiha Gökçen, like the terrain demo.
	var start := _to_local_flat(40.893231, 29.294808)
	_loop_offset = start
	ground_y = terrain.call("height_at", start.x, start.z)
	return terrain




## Aircraft i of n: evenly spaced along the loop, heading along its leg, flying to the leg's end.
func _spawn(i: int, n: int, ground: Node) -> void:
	var perimeter := 0.0
	for k in LOOP.size():
		perimeter += (LOOP[(k + 1) % LOOP.size()] - LOOP[k]).length()
	var s := perimeter * i / n
	var leg := 0
	while s > (LOOP[(leg + 1) % LOOP.size()] - LOOP[leg]).length():
		s -= (LOOP[(leg + 1) % LOOP.size()] - LOOP[leg]).length()
		leg += 1
	var a2: Vector2 = LOOP[leg]
	var b2: Vector2 = LOOP[(leg + 1) % LOOP.size()]
	var at := a2 + (b2 - a2).normalized() * s
	var agl := TERRAIN_AGL if _options.has("terrain") else ROUTE_AGL
	var y := ground_y + agl + (i % 2) * 30.0
	var start_at := _loop_offset + Vector3(at.x, 0.0, at.y)
	var plane := JSBSimAircraft.new()
	plane.name = "Aircraft%02d" % i
	var geo := _to_geodetic(start_at.x, start_at.z)
	plane.latitude = geo.x
	plane.longitude = geo.y
	plane.height = origin.z + y
	plane.heading = fposmod(rad_to_deg(atan2(b2.x - a2.x, -(b2.y - a2.y))), 360.0)
	plane.airspeed = 70.0
	plane.origin_latitude = origin.x
	plane.origin_longitude = origin.y
	plane.origin_height = origin.z
	if ground:
		plane.ground_path = NodePath("../" + str(ground.name))
	var autopilot := JSBSimAutopilot.new()
	autopilot.name = "Autopilot"
	if not _options.has("no-autopilot"):
		plane.add_child(autopilot)
	if not _options.has("no-models"):
		var model := Node3D.new()
		model.set_script(load("res://demo/aircraft_model.gd"))
		plane.add_child(model)
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 40.0
		sphere.height = 80.0
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.55, 0.1)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sphere.material = material
		marker.mesh = sphere
		marker.layers = MARKER_LAYER
		plane.add_child(marker)
	add_child(plane)
	plane.crashed.connect(func(_reason: String) -> void: _crashes += 1)
	aircraft.append(plane)
	if autopilot.is_inside_tree():
		for k in LOOP.size():
			var corner: Vector2 = LOOP[k]
			autopilot.add_waypoint_local(_loop_offset + Vector3(corner.x, y, corner.y))
		autopilot.loop_route = true
		autopilot.engage()
		autopilot.target_altitude = plane.height
		autopilot.set_active_waypoint((leg + 1) % LOOP.size())
		autopilot.follow_route = true
	else:
		autopilot.free()


func _physics_process(delta: float) -> void:
	var frame_usec := 0.0
	for plane in aircraft:
		frame_usec += plane.get_last_step_time_usec()
		_steps += plane.get_last_step_count()
	_step_usec += frame_usec
	_worst_frame_usec = maxf(_worst_frame_usec, frame_usec)
	_frames += 1
	if aircraft.is_empty() or aircraft[0].paused:
		return
	_game_time += delta * aircraft[0].time_scale
	if _quit_at >= 0.0 and _game_time >= _quit_at:
		_quit_at = -1.0
		_finish()


func _process(_delta: float) -> void:
	if aircraft.is_empty():
		return
	var sim_seconds := maxf(aircraft[0].get_fdm().get_sim_time(), 1e-6)
	# CPU time per simulated second: the share of one core the aircraft need at time scale 1.
	var core_load := _step_usec / (sim_seconds * 1e6) * 100.0
	var lines := PackedStringArray([
		"%d aircraft   x%s   %d FPS" % [aircraft.size(), aircraft[0].time_scale, Engine.get_frames_per_second()],
		"JSBSim + autopilot: %.1f µs per aircraft step, %.0f µs per simulated second per aircraft" % [
			_step_usec / maxf(_steps, 1), _step_usec / sim_seconds / aircraft.size()],
		"real-time load: %.1f %% of one CPU core   worst physics frame %.2f ms" % [core_load, _worst_frame_usec / 1000.0],
		"following %s   crashes %d" % [aircraft[_selected].name, _crashes],
		"Tab next aircraft   O overview   P pause   [ ] time   Esc quit",
	])
	label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_TAB:
			_select((_selected + 1) % aircraft.size())
		KEY_O:
			if overview_camera.current:
				chase_camera.current = true
			else:
				overview_camera.current = true
		KEY_P:
			for plane in aircraft:
				plane.paused = not plane.paused
		KEY_BRACKETLEFT:
			for plane in aircraft:
				plane.time_scale = maxf(plane.time_scale * 0.5, 0.125)
		KEY_BRACKETRIGHT:
			for plane in aircraft:
				plane.time_scale = minf(plane.time_scale * 2.0, 16.0)
		KEY_ESCAPE:
			get_tree().quit()


func _select(index: int) -> void:
	_selected = index
	chase_camera.set("target", aircraft[index])
	chase_camera.call("snap")
	# Overview: above the loop's centre, looking down at it.
	var centre := _loop_offset + Vector3(1500.0, ground_y, -3000.0)
	overview_camera.position = centre + Vector3(0.0, 7000.0, 6000.0)
	overview_camera.look_at(centre)


func _finish() -> void:
	var sim_seconds := aircraft[0].get_fdm().get_sim_time()
	var wall := (Time.get_ticks_usec() - _wall_start) / 1e6
	var per_step := _step_usec / maxf(_steps, 1)
	print(("PERF aircraft=%d ground=%s autopilot=%s models=%s sim_seconds=%.1f wall_seconds=%.1f steps=%d "
			+ "usec_per_aircraft_step=%.2f realtime_load_percent=%.1f worst_frame_ms=%.2f fps=%d crashes=%d") % [
		aircraft.size(), "terrain" if _options.has("terrain") else ("gdscript" if _options.has("gdscript-ground") else "flat"),
		not _options.has("no-autopilot"), not _options.has("no-models"), sim_seconds, wall, _steps, per_step,
		_step_usec / (sim_seconds * 1e6) * 100.0, _worst_frame_usec / 1000.0, Engine.get_frames_per_second(), _crashes])
	if _options.has("screenshot"):
		await RenderingServer.frame_post_draw
		var path: String = _options.screenshot
		var error := get_viewport().get_texture().get_image().save_png(path)
		print("screenshot: %s (%s)" % [path, error_string(error)])
	get_tree().quit(1 if _crashes > 0 else 0)


## Scene x, z on the tangent plane -> geodetic latitude, longitude (good to a few metres within 10 km).
func _to_geodetic(x: float, z: float) -> Vector2:
	var lat := deg_to_rad(origin.x)
	var w := 1.0 - WGS84_E2 * sin(lat) * sin(lat)
	var meridian := WGS84_A * (1.0 - WGS84_E2) / pow(w, 1.5)
	var normal := WGS84_A / sqrt(w)
	return Vector2(origin.x + rad_to_deg(-z / meridian), origin.y + rad_to_deg(x / (normal * cos(lat))))


func _to_local_flat(latitude: float, longitude: float) -> Vector3:
	var lat := deg_to_rad(origin.x)
	var w := 1.0 - WGS84_E2 * sin(lat) * sin(lat)
	var meridian := WGS84_A * (1.0 - WGS84_E2) / pow(w, 1.5)
	var normal := WGS84_A / sqrt(w)
	return Vector3(deg_to_rad(longitude - origin.y) * normal * cos(lat), 0.0,
			-deg_to_rad(latitude - origin.x) * meridian)


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
