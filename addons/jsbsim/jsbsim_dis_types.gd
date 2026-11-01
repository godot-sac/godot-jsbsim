class_name JSBSimDisTypes
extends RefCounted
## DIS entity types (SISO-REF-010) of the bundled aircraft, for godot-dis DisEntity.entity_type:
## [kind, domain, country, category, subcategory, specific, extra]. Add your own models to TYPES.

const TYPES := {
	# Platform, air, United States (225), civilian fixed wing small (85), single piston (11), Piper J-3 Cub (8)
	"J3Cub": [1, 2, 225, 85, 11, 8, 0],
	# Platform, air, Switzerland (206), trainer (40), Pilatus PC-7 (1), PC-7 Turbo Trainer (1)
	"pc7": [1, 2, 206, 40, 1, 1, 0],
}


## The entity type of a model by its JSBSim name (JSBSimAircraft.aircraft); empty if not in TYPES.
static func for_aircraft(aircraft_name: String) -> PackedInt32Array:
	return PackedInt32Array(TYPES.get(aircraft_name, []))
