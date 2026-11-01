extends Node
## A flat ground node with height_at(x, z) in GDScript, for many_aircraft.gd --gdscript-ground: the cost of JSBSim's
## ground queries going through a script, without godot-geo.

@export var height := 0.0


func height_at(_x: float, _z: float) -> float:
	return height
