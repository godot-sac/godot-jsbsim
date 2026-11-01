extends "res://demo/flight.gd"
## The flight demo over real terrain: godot-geo's GeoTerrain (Ankara, Copernicus DEM + Sentinel-2) is both what you
## see and the ground JSBSim's landing gear touches (JSBSimAircraft.ground_path). Needs the sibling repository:
## python tools/link_siblings.py (see README, Demos).
##
## Extra command line options (after `--`):
##   --terrain PATH      terrain package (default res://terrain/ankara_60km, then res://terrain/ankara)
##   --agl M             start height above the terrain when starting in the air (default 300)

const PACKAGES := ["res://terrain/ankara_60km", "res://terrain/ankara"]
const GEO_TERRAIN := "res://addons/geo/geo_terrain.gd"
## Ankara Esenboğa airport reference point (approximate) and runway direction.
const START_LATITUDE := 40.1283
const START_LONGITUDE := 32.9950
const START_HEADING := 33.0

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
		_fail_setup("no terrain package; build godot-geo terrain/ankara_60km (godot-geo docs/demo-3d.md)")
		return
	terrain = Node3D.new()
	terrain.set_script(load(GEO_TERRAIN))
	terrain.name = "Terrain"
	terrain.set("collision_enabled", false)  # JSBSim does its own ground contact
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
	var ground_height: float = terrain.call("geodetic_height", START_LATITUDE, START_LONGITUDE)
	aircraft.height = ground_height + float(_options.get("agl", 300.0))
	hud.set_attribution(terrain.call("attribution"))
	print("terrain: %s, ground at the start %.1f m (ellipsoid)" % [package, ground_height])


func _fail_setup(message: String) -> void:
	push_error("terrain demo: " + message)
	print("terrain demo: " + message)
	get_tree().quit(1)
