class_name JSBSimInput
extends Node
## Flies a JSBSimAircraft with the keyboard or a gamepad. Uses the InputMap actions below; the ones missing from the
## project are added with default keys at start, so it works without setup and can be remapped in Project Settings.
##
## Default keys: W/S or Up/Down pitch (S pulls), A/D or Left/Right roll, Q/E rudder, R/F throttle, B brakes.
## Gamepad: left stick pitch and roll, right stick X rudder, right/left trigger throttle up/down, left shoulder
## brakes.

const PITCH_UP := &"jsbsim_pitch_up"
const PITCH_DOWN := &"jsbsim_pitch_down"
const ROLL_LEFT := &"jsbsim_roll_left"
const ROLL_RIGHT := &"jsbsim_roll_right"
const YAW_LEFT := &"jsbsim_yaw_left"
const YAW_RIGHT := &"jsbsim_yaw_right"
const THROTTLE_UP := &"jsbsim_throttle_up"
const THROTTLE_DOWN := &"jsbsim_throttle_down"
const BRAKE := &"jsbsim_brake"

## The aircraft to fly. Defaults to the parent node.
@export var aircraft: JSBSimAircraft
## Stick travel per second for digital (key) input; analog input is used directly.
@export var key_rate := 2.5
## Throttle change per second while a throttle key or trigger is fully pressed.
@export var throttle_rate := 0.5
## Gamepad stick dead zone for the actions this node adds.
@export_range(0.0, 0.9) var dead_zone := 0.1
## Squares stick input (keeping the sign) for finer control near the centre.
@export var expo := true

var _aileron := 0.0
var _elevator := 0.0
var _rudder := 0.0


func _ready() -> void:
	if aircraft == null:
		aircraft = get_parent() as JSBSimAircraft
	_add_default_actions()


func _physics_process(delta: float) -> void:
	if aircraft == null or not aircraft.is_started():
		return
	_aileron = _axis(_aileron, ROLL_LEFT, ROLL_RIGHT, delta)
	# JSBSim: positive elevator command is nose down, so pulling back (pitch up) is negative.
	_elevator = _axis(_elevator, PITCH_UP, PITCH_DOWN, delta)
	_rudder = _axis(_rudder, YAW_LEFT, YAW_RIGHT, delta)
	aircraft.aileron = _shape(_aileron)
	aircraft.elevator = _shape(_elevator)
	aircraft.rudder = _shape(_rudder)
	var throttle_input := Input.get_action_strength(THROTTLE_UP) - Input.get_action_strength(THROTTLE_DOWN)
	if throttle_input != 0.0:
		aircraft.throttle = clampf(aircraft.throttle + throttle_input * throttle_rate * delta, 0.0, 1.0)
	aircraft.brake = Input.get_action_strength(BRAKE)


## Resets the stick to the centre (after JSBSimAircraft.restart()).
func centre() -> void:
	_aileron = 0.0
	_elevator = 0.0
	_rudder = 0.0


func _axis(current: float, negative: StringName, positive: StringName, delta: float) -> float:
	var target := Input.get_axis(negative, positive)
	if _is_analog(negative) or _is_analog(positive):
		return target
	return move_toward(current, target, key_rate * delta)


func _shape(value: float) -> float:
	return value * absf(value) if expo else value


## True while the action is held by a gamepad axis rather than a key.
func _is_analog(action: StringName) -> bool:
	var strength := Input.get_action_raw_strength(action)
	return strength > 0.0 and strength < 1.0


func _add_default_actions() -> void:
	_add(PITCH_UP, [KEY_S, KEY_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_add(PITCH_DOWN, [KEY_W, KEY_UP], JOY_AXIS_LEFT_Y, -1.0)
	_add(ROLL_LEFT, [KEY_A, KEY_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_add(ROLL_RIGHT, [KEY_D, KEY_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_add(YAW_LEFT, [KEY_Q], JOY_AXIS_RIGHT_X, -1.0)
	_add(YAW_RIGHT, [KEY_E], JOY_AXIS_RIGHT_X, 1.0)
	_add(THROTTLE_UP, [KEY_R, KEY_PAGEUP], JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add(THROTTLE_DOWN, [KEY_F, KEY_PAGEDOWN], JOY_AXIS_TRIGGER_LEFT, 1.0)
	if not InputMap.has_action(BRAKE):
		InputMap.add_action(BRAKE)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_B
		InputMap.action_add_event(BRAKE, key)
		var button := InputEventJoypadButton.new()
		button.button_index = JOY_BUTTON_LEFT_SHOULDER
		InputMap.action_add_event(BRAKE, button)


func _add(action: StringName, keys: Array[Key], axis: JoyAxis, direction: float) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, dead_zone)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
	var motion := InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = direction
	InputMap.action_add_event(action, motion)
