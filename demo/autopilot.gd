class_name FlightAutopilot
extends RefCounted
## A crude autopilot for the tests and the demo's automated runs (--takeoff): holds a heading with rudder (on the
## ground) or bank (in the air) and a vertical speed with the elevator. Proportional-derivative loops on JSBSim's own
## angles and rates. Tuned for the J3Cub.

var aircraft: JSBSimAircraft
var heading := 90.0  ## degrees
var vertical_speed := 0.0  ## m/s, up positive
## When set (knots, calibrated), the elevator holds this airspeed instead of vertical_speed: a full-power climb.
var climb_speed := NAN
var max_bank := 20.0  ## degrees
## Pitch held while rolling on the ground (degrees); a taildragger raises its tail by pushing towards 0.
var ground_pitch := NAN
## Takeoff speeds (knots, calibrated) and the taildragger's three-point pitch (degrees).
var tail_up_speed := 20.0
var rotate_speed := 42.0
var three_point_pitch := 12.0


func _init(p_aircraft: JSBSimAircraft) -> void:
	aircraft = p_aircraft


## One takeoff step for a taildragger: full power, tail down, tail up from tail_up_speed, rotate at rotate_speed,
## then climb at climb_speed (55 kt if not set). Call every physics frame instead of update().
func takeoff() -> void:
	var ias := aircraft.get_fdm().get_property("velocities/vc-kts")
	aircraft.throttle = 1.0
	aircraft.brake = 0.0
	if is_nan(climb_speed):
		climb_speed = 55.0
	ground_pitch = three_point_pitch if ias < tail_up_speed else (2.0 if ias < rotate_speed else NAN)
	update()
	if ias >= rotate_speed and aircraft.is_on_ground():
		aircraft.elevator = -0.4


func update() -> void:
	var fdm := aircraft.get_fdm()
	var psi := fdm.get_property("attitude/psi-deg")
	var phi := fdm.get_property("attitude/phi-deg")
	var theta := fdm.get_property("attitude/theta-deg")
	var p := rad_to_deg(fdm.get_property("velocities/p-rad_sec"))
	var q := rad_to_deg(fdm.get_property("velocities/q-rad_sec"))
	var r := rad_to_deg(fdm.get_property("velocities/r-rad_sec"))
	var heading_error := wrapf(heading - psi, -180.0, 180.0)
	if aircraft.is_on_ground():
		aircraft.rudder = clampf(heading_error * 0.15 - r * 0.15, -1.0, 1.0)
		aircraft.aileron = clampf(-phi * 0.05 - p * 0.02, -1.0, 1.0)
		if not is_nan(ground_pitch):
			aircraft.elevator = clampf((theta - ground_pitch) * 0.08 + q * 0.03, -1.0, 1.0)
		return
	var bank := clampf(heading_error * 1.0, -max_bank, max_bank)
	aircraft.aileron = clampf((bank - phi) * 0.03 - p * 0.01, -1.0, 1.0)
	# Positive sideslip (wind from the right): right rudder.
	aircraft.rudder = clampf(rad_to_deg(fdm.get_property("aero/beta-rad")) * 0.05, -1.0, 1.0)
	var vs := fdm.get_property("velocities/h-dot-fps") * 0.3048
	var pitch_target := clampf(theta + (vertical_speed - vs) * 1.5, -10.0, 15.0)
	if not is_nan(climb_speed):
		var ias := fdm.get_property("velocities/vc-kts")
		pitch_target = clampf(theta + (ias - climb_speed) * 0.5, -10.0, 15.0)
	# Positive elevator is nose down.
	aircraft.elevator = clampf(aircraft.elevator + (theta - pitch_target) * 0.0015 + q * 0.002, -1.0, 1.0)
