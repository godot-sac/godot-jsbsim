@icon("res://addons/jsbsim/icons/jsbsim_input.svg")
class_name JSBSimInput
extends Node
## Flies a JSBSimAircraft with the keyboard, a gamepad or a flight stick. Uses the InputMap actions below; the ones
## missing from the project are added at start with the defaults of `profile`, so it works without setup and can be
## remapped in Project Settings (actions already in the project are left alone). Axis table: docs/input.md.
##
## Keyboard (both profiles): W/S or Up/Down pitch (S pulls), A/D or Left/Right roll, Q/E rudder, R/F or PgUp/PgDn
## throttle, B brakes, Home/End pitch trim, T autopilot on / off.
## GAMEPAD: left stick pitch and roll, right stick X rudder, right / left trigger throttle up / down, left shoulder
## brakes, D-pad up / down pitch trim, Y (top face button) autopilot.
## FLIGHT_STICK: axis 0 roll, axis 1 pitch, axis 2 twist rudder, axis 3 throttle lever (absolute), button 1 brakes,
## button 3 autopilot, button 4 / 5 pitch trim (the axis and button numbers are exports).

enum Profile { GAMEPAD, FLIGHT_STICK }

const PITCH_UP := &"jsbsim_pitch_up"
const PITCH_DOWN := &"jsbsim_pitch_down"
const ROLL_LEFT := &"jsbsim_roll_left"
const ROLL_RIGHT := &"jsbsim_roll_right"
const YAW_LEFT := &"jsbsim_yaw_left"
const YAW_RIGHT := &"jsbsim_yaw_right"
const THROTTLE_UP := &"jsbsim_throttle_up"
const THROTTLE_DOWN := &"jsbsim_throttle_down"
## Absolute throttle lever: the two halves of one axis (forward / back). Used when absolute_throttle is on.
const THROTTLE_LEVER_FORWARD := &"jsbsim_throttle_lever_forward"
const THROTTLE_LEVER_BACK := &"jsbsim_throttle_lever_back"
const BRAKE := &"jsbsim_brake"
const TRIM_UP := &"jsbsim_trim_nose_up"
const TRIM_DOWN := &"jsbsim_trim_nose_down"
const AUTOPILOT := &"jsbsim_autopilot_toggle"

## The aircraft to fly. Defaults to the parent node.
@export var aircraft: JSBSimAircraft
## Default device layout for the actions this node adds.
@export var profile := Profile.GAMEPAD
## Throttle from an absolute lever (THROTTLE_LEVER_* actions) instead of up / down rates, once the lever has moved
## (until then the keys work). Turned on by the FLIGHT_STICK profile.
@export var absolute_throttle := false
## Stick travel per second for digital (key) input; analog input is used directly.
@export var key_rate := 2.5
## Throttle change per second while a throttle key or trigger is fully pressed.
@export var throttle_rate := 0.5
## Pitch trim change per second while a trim key or button is held (JSBSim fcs/pitch-trim-cmd-norm, -1..1).
@export var trim_rate := 0.1
## Stick dead zone for the actions this node adds.
@export_range(0.0, 0.9) var dead_zone := 0.1
## Squares stick input (keeping the sign) for finer control near the centre.
@export var expo := true

@export_group("Flight stick")
@export var stick_roll_axis := 0
@export var stick_pitch_axis := 1
@export var stick_rudder_axis := 2
@export var stick_throttle_axis := 3
## Most throttle levers read -1 fully forward; then forward is full power.
@export var invert_throttle_axis := true
@export var stick_brake_button := 1
@export var stick_autopilot_button := 3
@export var stick_trim_up_button := 4
@export var stick_trim_down_button := 5

var _aileron := 0.0
var _elevator := 0.0
var _rudder := 0.0
var _lever_seen := false
var _analog := {}  # negative action of a control -> true when a joypad axis moved it last


func _ready() -> void:
	if aircraft == null:
		aircraft = get_parent() as JSBSimAircraft
	if profile == Profile.FLIGHT_STICK:
		absolute_throttle = true
	_add_default_actions()


func _physics_process(delta: float) -> void:
	if aircraft == null or not aircraft.is_started():
		return
	var autopilot := aircraft.get_autopilot()
	var flying_itself := autopilot != null and autopilot.enabled
	if not flying_itself:
		_aileron = _axis(_aileron, ROLL_LEFT, ROLL_RIGHT, delta)
		# JSBSim: positive elevator command is nose down, so pulling back (pitch up) is negative.
		_elevator = _axis(_elevator, PITCH_UP, PITCH_DOWN, delta)
		_rudder = _axis(_rudder, YAW_LEFT, YAW_RIGHT, delta)
		aircraft.aileron = _shape(_aileron)
		aircraft.elevator = _shape(_elevator)
		aircraft.rudder = _shape(_rudder)
	if not (flying_itself and autopilot.speed_hold):
		var lever := Input.get_action_raw_strength(THROTTLE_LEVER_FORWARD) \
				- Input.get_action_raw_strength(THROTTLE_LEVER_BACK)
		# The keys work until the lever moves (no stick connected, or not touched yet).
		_lever_seen = _lever_seen or lever != 0.0
		if absolute_throttle and _lever_seen:
			aircraft.throttle = clampf((lever + 1.0) * 0.5, 0.0, 1.0)
		else:
			var throttle_input := Input.get_action_strength(THROTTLE_UP) - Input.get_action_strength(THROTTLE_DOWN)
			if throttle_input != 0.0:
				aircraft.throttle = clampf(aircraft.throttle + throttle_input * throttle_rate * delta, 0.0, 1.0)
	aircraft.brake = Input.get_action_strength(BRAKE)
	var trim := Input.get_action_strength(TRIM_UP) - Input.get_action_strength(TRIM_DOWN)
	var fdm := aircraft.get_fdm()
	if trim != 0.0 and fdm.has_property("fcs/pitch-trim-cmd-norm"):
		# Nose up is negative, like the elevator.
		var value := fdm.get_property("fcs/pitch-trim-cmd-norm") - trim * trim_rate * delta
		fdm.set_property("fcs/pitch-trim-cmd-norm", clampf(value, -1.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(AUTOPILOT) and not event.is_echo():
		toggle_autopilot()


## Turns the aircraft's JSBSimAutopilot child on (holding the current heading, height and airspeed) or off.
func toggle_autopilot() -> void:
	var autopilot := aircraft.get_autopilot() if aircraft else null
	if autopilot == null:
		return
	if autopilot.enabled:
		autopilot.enabled = false
		centre()
		aircraft.aileron = 0.0
		aircraft.elevator = 0.0
		aircraft.rudder = 0.0
	else:
		var follow_route := autopilot.follow_route and autopilot.get_active_waypoint() >= 0
		autopilot.engage()
		autopilot.follow_route = follow_route


## Resets the stick to the centre (after JSBSimAircraft.restart()).
func centre() -> void:
	_aileron = 0.0
	_elevator = 0.0
	_rudder = 0.0


## Remembers whether a joypad axis or a key last moved each control: an axis is used as it is, a key ramps.
func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadMotion or event is InputEventKey):
		return
	for pair: Array in [[ROLL_LEFT, ROLL_RIGHT], [PITCH_UP, PITCH_DOWN], [YAW_LEFT, YAW_RIGHT]]:
		if event.is_action(pair[0]) or event.is_action(pair[1]):
			_analog[pair[0]] = event is InputEventJoypadMotion


func _axis(current: float, negative: StringName, positive: StringName, delta: float) -> float:
	var target := Input.get_axis(negative, positive)
	if _analog.get(negative, false):
		return target
	return move_toward(current, target, key_rate * delta)


func _shape(value: float) -> float:
	return value * absf(value) if expo else value


func _add_default_actions() -> void:
	var stick := profile == Profile.FLIGHT_STICK
	_add(PITCH_UP, [KEY_S, KEY_DOWN], stick_pitch_axis if stick else JOY_AXIS_LEFT_Y, 1.0)
	_add(PITCH_DOWN, [KEY_W, KEY_UP], stick_pitch_axis if stick else JOY_AXIS_LEFT_Y, -1.0)
	_add(ROLL_LEFT, [KEY_A, KEY_LEFT], stick_roll_axis if stick else JOY_AXIS_LEFT_X, -1.0)
	_add(ROLL_RIGHT, [KEY_D, KEY_RIGHT], stick_roll_axis if stick else JOY_AXIS_LEFT_X, 1.0)
	_add(YAW_LEFT, [KEY_Q], stick_rudder_axis if stick else JOY_AXIS_RIGHT_X, -1.0)
	_add(YAW_RIGHT, [KEY_E], stick_rudder_axis if stick else JOY_AXIS_RIGHT_X, 1.0)
	_add(THROTTLE_UP, [KEY_R, KEY_PAGEUP], -1 if stick else JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add(THROTTLE_DOWN, [KEY_F, KEY_PAGEDOWN], -1 if stick else JOY_AXIS_TRIGGER_LEFT, 1.0)
	var forward := -1.0 if invert_throttle_axis else 1.0
	_add(THROTTLE_LEVER_FORWARD, [], stick_throttle_axis if stick else -1, forward, 0.0)
	_add(THROTTLE_LEVER_BACK, [], stick_throttle_axis if stick else -1, -forward, 0.0)
	_add(BRAKE, [KEY_B], -1, 0.0, 0.5, stick_brake_button if stick else JOY_BUTTON_LEFT_SHOULDER)
	_add(TRIM_UP, [KEY_HOME], -1, 0.0, 0.5, stick_trim_up_button if stick else JOY_BUTTON_DPAD_DOWN)
	_add(TRIM_DOWN, [KEY_END], -1, 0.0, 0.5, stick_trim_down_button if stick else JOY_BUTTON_DPAD_UP)
	_add(AUTOPILOT, [KEY_T], -1, 0.0, 0.5, stick_autopilot_button if stick else JOY_BUTTON_Y)


## Adds `action` unless the project has it: keys, an axis half (axis >= 0) and a button (button >= 0).
func _add(action: StringName, keys: Array[Key], axis: int, direction: float, zone := -1.0, button := -1) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, dead_zone if zone < 0.0 else zone)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
	if axis >= 0:
		var motion := InputEventJoypadMotion.new()
		motion.axis = axis as JoyAxis
		motion.axis_value = direction
		InputMap.action_add_event(action, motion)
	if button >= 0:
		var press := InputEventJoypadButton.new()
		press.button_index = button as JoyButton
		InputMap.action_add_event(action, press)
