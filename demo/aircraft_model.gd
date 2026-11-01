extends Node3D
## Simple high-wing light aircraft built from boxes (about the size of a J-3 Cub), looking along -Z.
## The propeller spins with the engine's propeller RPM. Parts the pilot would not see are on visual layer 2, which
## the cockpit camera leaves out (cull_mask).

const YELLOW := Color(0.95, 0.78, 0.15)
const DARK := Color(0.12, 0.12, 0.12)
const OUTSIDE_ONLY := 2  # visual layer

@export var aircraft: JSBSimAircraft

var _propeller: Node3D


func _ready() -> void:
	if aircraft == null:
		aircraft = get_parent() as JSBSimAircraft
	_box(Vector3(0.8, 1.0, 6.6), Vector3(0, 0, 0.2), YELLOW, self, OUTSIDE_ONLY)  # fuselage
	_box(Vector3(0.7, 0.6, 1.0), Vector3(0, -0.15, -3.3), DARK.lightened(0.3))  # cowling
	_box(Vector3(10.7, 0.14, 1.6), Vector3(0, 0.75, -0.9), YELLOW)  # wing
	_box(Vector3(0.82, 0.5, 1.4), Vector3(0, 0.55, -1.0), Color(0.55, 0.75, 0.9, 0.6), self, OUTSIDE_ONLY)  # cabin
	_box(Vector3(3.4, 0.08, 0.9), Vector3(0, 0.1, 3.3), YELLOW)  # horizontal tail
	_box(Vector3(0.08, 1.1, 1.0), Vector3(0, 0.65, 3.3), YELLOW)  # fin
	for side in [-1.0, 1.0]:
		_box(Vector3(0.08, 1.1, 0.08), Vector3(side * 0.7, -0.75, -1.8), DARK, self, OUTSIDE_ONLY)  # gear leg
		_box(Vector3(0.18, 0.55, 0.55), Vector3(side * 0.95, -1.3, -1.8), DARK, self, OUTSIDE_ONLY)  # wheel
	_propeller = Node3D.new()
	_propeller.position = Vector3(0, -0.15, -3.85)
	add_child(_propeller)
	_box(Vector3(1.9, 0.14, 0.04), Vector3.ZERO, DARK, _propeller)
	_box(Vector3(0.22, 0.22, 0.25), Vector3(0, 0, -0.1), Color(0.8, 0.8, 0.8), _propeller)  # spinner


func _process(delta: float) -> void:
	if aircraft == null or not aircraft.is_started() or aircraft.paused:
		return
	var fdm := aircraft.get_fdm()
	var rpm := 0.0
	if fdm.has_property("propulsion/engine/propeller-rpm"):
		rpm = fdm.get_property("propulsion/engine/propeller-rpm")
	# Real RPM strobes at the frame rate; cap the visible speed.
	_propeller.rotate_z(-minf(rpm / 60.0 * TAU, 40.0) * delta * aircraft.time_scale)


func _box(size: Vector3, at: Vector3, color: Color, parent: Node3D = self, layers := 1) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.layers = layers
	parent.add_child(instance)
	return instance
