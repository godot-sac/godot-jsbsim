extends "res://tests/unit/fake_ground.gd"
## fake_ground.gd with normal_at(x, z), which JSBSimAircraft uses instead of its own slope estimate. `vertical`
## returns straight up whatever the slope: the error JSBSim discussion #1510 is about, for comparison.

var vertical := false
var normal_calls := 0


func normal_at(_x: float, _z: float) -> Vector3:
	normal_calls += 1
	if vertical:
		return Vector3.UP
	return Vector3(-slope, 1.0, 0.0).normalized()
