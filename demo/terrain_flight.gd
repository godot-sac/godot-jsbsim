extends "res://demo/flight.gd"
## The flight demo over real terrain: godot-geo's GeoTerrain (Istanbul, Copernicus DEM + Sentinel-2, OpenStreetMap
## buildings and roads) is both what you see and the ground JSBSim's landing gear touches (JSBSimAircraft.ground_path).
## The aircraft starts on Istanbul Sabiha Gökçen's (LTFJ) north runway, facing 064° true (runway 06). Needs the
## sibling repository: python tools/link_siblings.py (see README, Demos).
##
## Extra command line options (after `--`):
##   --terrain PATH      terrain package (default res://terrain/uskudar, godot-geo's 60 km Üsküdar package)
##   --agl M             start height above the terrain when starting in the air (default 300)
##   --route             JSBSimAutopilot flies a loop from the airport over the Marmara coast and the Bosphorus and
##                       back (ROUTE, ~66 km, half an hour); with --ground --takeoff once airborne. Y flies it too.
##   --start-at N        start in the air at route point N (0..5) at its height, flying to the next one

const PACKAGES := ["res://terrain/uskudar"]
const GEO_TERRAIN := "res://addons/geo/geo_terrain.gd"
## LTFJ north runway (06/24, 3 km) from OpenStreetMap (Overture 2026-10-21): the start is 150 m in from the
## south-west end, on the centre line.
const RUNWAY_06 := Vector2(40.892641, 29.293205)  # latitude, longitude
const RUNWAY_24 := Vector2(40.904441, 29.325242)
const START_LATITUDE := 40.893231
const START_LONGITUDE := 29.294808
const START_HEADING := 64.0
## The route: latitude, longitude, height above the ellipsoid (m). Civil landmarks only, well above the highest
## structures near the legs (Küçük Çamlıca TV tower ~590 m above sea level, the bridge towers 165 m); the geoid is
## ~37 m above the ellipsoid here.
const ROUTE := [
	["Marmara, off Maltepe", 40.905, 29.120, 600.0],
	["Marmara, off Moda", 40.985, 28.995, 800.0],
	["Maiden's Tower (Kız Kulesi)", 41.0213, 29.0055, 800.0],
	["15 July Martyrs Bridge", 41.0453, 29.0345, 800.0],
	["Büyük Çamlıca Mosque", 41.0261, 29.0708, 800.0],
	["Sabiha Gökçen, overhead", 40.8985, 29.3092, 800.0],
]

var terrain: Node3D


func _setup_world() -> void:
	if ground:
		ground.queue_free()
		ground = null
	if not ResourceLoader.exists(GEO_TERRAIN):
		_fail_setup("godot-geo is not linked: run python tools/link_siblings.py, then <godot> --path . --import")
		return
	var package := ""
	for candidate: String in [_options.get("terrain", "")] + PACKAGES:
		if candidate != "" and FileAccess.file_exists(candidate.path_join("terrain.json")):
			package = candidate
			break
	if package == "":
		_fail_setup("no terrain package; build or download godot-geo's terrain/uskudar (godot-geo docs/city.md)")
		return
	terrain = Node3D.new()
	terrain.set_script(load(GEO_TERRAIN))
	terrain.name = "Terrain"
	terrain.set("collision_enabled", false)  # JSBSim does its own ground contact
	# Buildings, roads and trees are only seen (not ground); headless test runs leave them out.
	terrain.set("auto_layers", DisplayServer.get_name() != "headless")
	add_child(terrain)
	move_child(terrain, 0)
	terrain.set("package_path", package)
	if terrain.get("package") == null:
		_fail_setup("cannot load terrain package " + package)
		return
	var info: Object = terrain.get("package")
	# The scene origin is the package origin, so JSBSim's frame and the terrain's frame are the same.
	aircraft.origin_latitude = info.get("latitude")
	aircraft.origin_longitude = info.get("longitude")
	aircraft.origin_height = info.get("origin_height")
	aircraft.ground_path = aircraft.get_path_to(terrain)
	aircraft.latitude = START_LATITUDE
	aircraft.longitude = START_LONGITUDE
	aircraft.heading = START_HEADING
	var start: Vector3 = terrain.call("geodetic_to_global", START_LATITUDE, START_LONGITUDE, 0.0)
	if not info.call("contains", start.x, start.z):
		_fail_setup("the start (Sabiha Gökçen) is outside %s; use the 60 km package terrain/uskudar" % package)
		return
	var ground_height: float = terrain.call("geodetic_height", START_LATITUDE, START_LONGITUDE)
	aircraft.height = ground_height + float(_options.get("agl", 300.0))
	if _options.has("start-at"):
		var from: Array = ROUTE[int(_options["start-at"]) % ROUTE.size()]
		var to: Array = ROUTE[(int(_options["start-at"]) + 1) % ROUTE.size()]
		aircraft.start_on_ground = false
		aircraft.latitude = from[1]
		aircraft.longitude = from[2]
		aircraft.height = from[3]
		var a: Vector3 = terrain.call("geodetic_to_global", from[1], from[2], 0.0)
		var b: Vector3 = terrain.call("geodetic_to_global", to[1], to[2], 0.0)
		aircraft.heading = fposmod(rad_to_deg(atan2(b.x - a.x, a.z - b.z)), 360.0)
	hud.set_attribution(terrain.call("attribution"))
	print("terrain: %s, ground at the start %.1f m (ellipsoid)" % [package, ground_height])


## The airport-Bosphorus loop instead of flight.gd's loop ahead of the start.
func _build_route() -> void:
	autopilot.clear_route()
	for point: Array in ROUTE:
		autopilot.add_waypoint(point[1], point[2], point[3])
	autopilot.loop_route = true
	if _options.has("start-at"):
		autopilot.set_active_waypoint((int(_options["start-at"]) + 1) % ROUTE.size())
	print("route: %s" % ", ".join(ROUTE.map(func(p: Array) -> String: return p[0])))
	_log_route_clearance()


## The lowest clearance above the terrain along the route legs (sampled every 50 m), as a check on the heights.
func _log_route_clearance() -> void:
	var points: Array[Vector3] = []
	for i in autopilot.get_waypoint_count():
		points.append(autopilot.get_waypoint(i).position)
	var lowest := INF
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var steps := maxi(1, int(a.distance_to(b) / 50.0))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			lowest = minf(lowest, p.y - terrain.call("height_at", p.x, p.z))
	print("route: %.0f km, lowest clearance above the terrain %.0f m" % [_route_length(points) / 1000.0, lowest])


func _route_length(points: Array[Vector3]) -> float:
	var length := 0.0
	for i in points.size():
		length += points[i].distance_to(points[(i + 1) % points.size()])
	return length


func _fail_setup(message: String) -> void:
	push_error("terrain demo: " + message)
	print("terrain demo: " + message)
	get_tree().quit(1)
