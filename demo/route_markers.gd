extends Node3D
## Draws a JSBSimAutopilot's route: a pole and a ball at each waypoint (the active one in orange) and the legs.

@export var autopilot: JSBSimAutopilot
## Pole length below each waypoint (m).
@export var pole := 400.0

var _count := -1
var _active := -2
var _balls: Array[MeshInstance3D] = []
var _normal := _material(Color(0.2, 0.8, 1.0))
var _highlight := _material(Color(1.0, 0.55, 0.1))
var _legs := MeshInstance3D.new()


func _ready() -> void:
	_legs.mesh = ImmediateMesh.new()
	_legs.material_override = _material(Color(0.2, 0.8, 1.0, 0.6))
	add_child(_legs)


func _process(_delta: float) -> void:
	if autopilot == null:
		return
	if autopilot.get_waypoint_count() != _count:
		_rebuild()
	if autopilot.get_active_waypoint() != _active:
		_active = autopilot.get_active_waypoint()
		for i in _balls.size():
			_balls[i].material_override = _highlight if i == _active else _normal


func _rebuild() -> void:
	for child in get_children():
		if child != _legs:
			child.queue_free()
	_balls.clear()
	_count = autopilot.get_waypoint_count()
	var points: Array[Vector3] = []
	for i in _count:
		var w := autopilot.get_waypoint(i)
		if not w.has("position"):
			continue
		var at: Vector3 = w.position
		points.append(at)
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 25.0
		sphere.height = 50.0
		ball.mesh = sphere
		ball.position = at
		add_child(ball)
		_balls.append(ball)
		var stick := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 4.0
		cylinder.bottom_radius = 4.0
		cylinder.height = pole
		stick.mesh = cylinder
		stick.material_override = _normal
		stick.position = at - Vector3(0, pole * 0.5, 0)
		add_child(stick)
	var mesh: ImmediateMesh = _legs.mesh
	mesh.clear_surfaces()
	if points.size() >= 2:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in points:
			mesh.surface_add_vertex(p)
		if autopilot.loop_route:
			mesh.surface_add_vertex(points[0])
		mesh.surface_end()
	_active = -2


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
