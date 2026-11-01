extends Node
## Stands in for godot-geo GeoTerrain in test_ground.gd: JSBSimAircraft only calls height_at(x, z).
## A plane at `base` metres rising `slope` metres per metre towards +X, with no data beyond `extent`.

var base := 100.0
var slope := 0.0
var extent := 5000.0


func height_at(x: float, z: float) -> float:
	if absf(x) > extent or absf(z) > extent:
		return NAN
	return base + slope * x
