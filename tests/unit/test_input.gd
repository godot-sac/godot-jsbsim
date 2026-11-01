extends GutTest
## JSBSimInput: default InputMap actions per profile, joypad axes (a simulated device), absolute throttle lever,
## pitch trim, autopilot toggle. docs/input.md lists the same mapping.

const ACTIONS := [
	JSBSimInput.PITCH_UP, JSBSimInput.PITCH_DOWN, JSBSimInput.ROLL_LEFT, JSBSimInput.ROLL_RIGHT,
	JSBSimInput.YAW_LEFT, JSBSimInput.YAW_RIGHT, JSBSimInput.THROTTLE_UP, JSBSimInput.THROTTLE_DOWN,
	JSBSimInput.THROTTLE_LEVER_FORWARD, JSBSimInput.THROTTLE_LEVER_BACK, JSBSimInput.BRAKE, JSBSimInput.TRIM_UP,
	JSBSimInput.TRIM_DOWN, JSBSimInput.AUTOPILOT,
]
const DEVICE := 0


func before_each() -> void:
	# The actions are global: every test starts without them, so the profile's defaults are added.
	for action: StringName in ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)


func after_each() -> void:
	for axis in JOY_AXIS_MAX:
		_axis(axis, 0.0)
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _aircraft(profile: JSBSimInput.Profile, with_autopilot := false) -> JSBSimInput:
	var a := JSBSimAircraft.new()
	a.height = 1500.0
	a.origin_height = 1000.0
	if with_autopilot:
		a.add_child(JSBSimAutopilot.new())
	var input := JSBSimInput.new()
	input.profile = profile
	input.expo = false
	a.add_child(input)
	add_child_autofree(a)
	a.paused = true
	return input


func _axis(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = DEVICE
	event.axis = axis as JoyAxis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(input: JSBSimInput, count := 1) -> void:
	for i in count:
		input._physics_process(1.0 / 60.0)


func test_all_actions_added() -> void:
	_aircraft(JSBSimInput.Profile.GAMEPAD)
	for action: StringName in ACTIONS:
		assert_true(InputMap.has_action(action), action)


func test_project_actions_are_kept() -> void:
	InputMap.add_action(JSBSimInput.BRAKE)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	InputMap.action_add_event(JSBSimInput.BRAKE, key)
	_aircraft(JSBSimInput.Profile.GAMEPAD)
	var events := InputMap.action_get_events(JSBSimInput.BRAKE)
	assert_eq(events.size(), 1)
	assert_eq((events[0] as InputEventKey).physical_keycode, KEY_SPACE)


func test_gamepad_sticks() -> void:
	var input := _aircraft(JSBSimInput.Profile.GAMEPAD)
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_axis(JOY_AXIS_LEFT_Y, 1.0)  # stick pulled back
	_axis(JOY_AXIS_RIGHT_X, -1.0)
	_frames(input)
	assert_almost_eq(input.aircraft.aileron, 1.0, 1e-6, "left stick right: roll right")
	assert_almost_eq(input.aircraft.elevator, -1.0, 1e-6, "left stick back: nose up (negative elevator)")
	assert_almost_eq(input.aircraft.rudder, -1.0, 1e-6, "right stick left: left pedal")
	_axis(JOY_AXIS_LEFT_X, 0.5)
	_frames(input)
	assert_between(input.aircraft.aileron, 0.3, 0.5, "half stick, rescaled past the dead zone")
	_axis(JOY_AXIS_LEFT_X, 0.05)
	_frames(input)
	assert_eq(input.aircraft.aileron, 0.0, "inside the dead zone")


func test_gamepad_throttle_triggers() -> void:
	var input := _aircraft(JSBSimInput.Profile.GAMEPAD)
	var start := input.aircraft.throttle
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	_frames(input, 60)
	assert_almost_eq(input.aircraft.throttle, start - input.throttle_rate, 1e-3, "one second of left trigger")


func test_flight_stick_axes_and_lever() -> void:
	var input := _aircraft(JSBSimInput.Profile.FLIGHT_STICK)
	assert_true(input.absolute_throttle)
	_axis(0, -1.0)
	_axis(1, -1.0)  # stick forward
	_axis(2, 1.0)  # twist right
	_axis(3, -1.0)  # lever fully forward
	_frames(input)
	assert_almost_eq(input.aircraft.aileron, -1.0, 1e-6)
	assert_almost_eq(input.aircraft.elevator, 1.0, 1e-6, "stick forward: nose down")
	assert_almost_eq(input.aircraft.rudder, 1.0, 1e-6)
	assert_almost_eq(input.aircraft.throttle, 1.0, 1e-6, "lever forward: full power")
	_axis(3, 1.0)
	_frames(input)
	assert_almost_eq(input.aircraft.throttle, 0.0, 1e-6, "lever back: idle")
	_axis(3, 0.0)
	_frames(input)
	assert_almost_eq(input.aircraft.throttle, 0.5, 1e-6, "lever centred: half")


func test_flight_stick_keys_until_the_lever_moves() -> void:
	var input := _aircraft(JSBSimInput.Profile.FLIGHT_STICK)
	input.aircraft.throttle = 0.2
	Input.action_press(JSBSimInput.THROTTLE_UP)
	_frames(input, 30)
	assert_almost_eq(input.aircraft.throttle, 0.2 + input.throttle_rate * 0.5, 1e-3, "keys before the lever moves")
	Input.action_release(JSBSimInput.THROTTLE_UP)
	_axis(3, -0.5)
	_frames(input)
	assert_almost_eq(input.aircraft.throttle, 0.75, 1e-6, "then the lever takes over")


func test_pitch_trim() -> void:
	var input := _aircraft(JSBSimInput.Profile.GAMEPAD)
	var fdm := input.aircraft.get_fdm()
	var trim := fdm.get_property("fcs/pitch-trim-cmd-norm")
	Input.action_press(JSBSimInput.TRIM_UP)
	_frames(input, 60)
	assert_almost_eq(fdm.get_property("fcs/pitch-trim-cmd-norm"), trim - input.trim_rate, 1e-3,
			"nose-up trim is negative, like the elevator")


func test_autopilot_toggle_and_stick_override() -> void:
	var input := _aircraft(JSBSimInput.Profile.GAMEPAD, true)
	var autopilot := input.aircraft.get_autopilot()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_T
	key.pressed = true
	input._unhandled_input(key)
	assert_true(autopilot.enabled, "T engages")
	assert_true(autopilot.heading_hold and autopilot.altitude_hold and autopilot.speed_hold)
	input.aircraft.aileron = 0.3
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_frames(input)
	assert_eq(input.aircraft.aileron, 0.3, "the stick does not fight the autopilot")
	input._unhandled_input(key)
	assert_false(autopilot.enabled, "T again disengages")
	_frames(input)
	assert_almost_eq(input.aircraft.aileron, 1.0, 1e-6, "the stick is back")
