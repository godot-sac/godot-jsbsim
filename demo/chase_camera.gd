extends Camera3D
## Follows the aircraft from behind and above, turning with its heading but keeping the horizon level.

@export var target: Node3D
@export var distance := 12.0
@export var height := 3.0
## Higher is stiffer (1/s).
@export var stiffness := 4.0

var _heading := 0.0


func _ready() -> void:
	snap()


## Jumps to the follow position (after a reset).
func snap() -> void:
	if target == null:
		return
	_heading = _target_heading()
	global_position = _desired_position()
	_look(target.global_position)


func _process(delta: float) -> void:
	if target == null:
		return
	var weight := 1.0 - exp(-stiffness * delta)
	_heading = lerp_angle(_heading, _target_heading(), weight)
	global_position = global_position.lerp(_desired_position(), weight)
	_look(target.global_position + Vector3.UP)


func _look(at: Vector3) -> void:
	var direction := at - global_position
	if direction.length() < 0.01:
		return
	# Looking straight down (the aircraft dived below the camera): Vector3.UP cannot be the up vector.
	var up := Vector3.UP
	if absf(direction.normalized().y) > 0.99:
		up = -Vector3(sin(_heading), 0.0, cos(_heading))
	look_at(at, up)


func _target_heading() -> float:
	var forward := -target.global_basis.z
	if Vector2(forward.x, forward.z).length() < 0.2:
		return _heading  # nearly vertical: keep the last heading
	return atan2(-forward.x, -forward.z)


func _desired_position() -> Vector3:
	var back := Vector3(sin(_heading), 0.0, cos(_heading))
	return target.global_position + back * distance + Vector3.UP * height
