# Keyboard, gamepad and flight stick

`JSBSimInput` (a child of `JSBSimAircraft`) reads Godot InputMap actions and writes the aircraft's commands. At start
it adds the actions the project does not define yet, with the defaults below; actions already in the project (your
own mapping in *Project Settings → Input Map*) are left as they are.

```gdscript
var input := JSBSimInput.new()
input.profile = JSBSimInput.Profile.FLIGHT_STICK   # or GAMEPAD (default)
aircraft.add_child(input)
```

## Default mapping
| action | does | keyboard | `GAMEPAD` | `FLIGHT_STICK` |
|---|---|---|---|---|
| `jsbsim_roll_left` / `_right` | aileron | A / D, ← / → | left stick X (axis 0) | axis 0 |
| `jsbsim_pitch_up` / `_down` | elevator (up = pull back) | S / W, ↓ / ↑ | left stick Y (axis 1) | axis 1 |
| `jsbsim_yaw_left` / `_right` | rudder, nose / tail wheel | Q / E | right stick X (axis 2) | axis 2 (twist) |
| `jsbsim_throttle_up` / `_down` | throttle up / down at `throttle_rate` | R / F, PgUp / PgDn | right / left trigger (axes 5 / 4) | — |
| `jsbsim_throttle_lever_forward` / `_back` | absolute throttle lever (halves of one axis) | — | — | axis 3 (`invert_throttle_axis`) |
| `jsbsim_brake` | wheel brakes | B | left shoulder (button 9) | button 1 |
| `jsbsim_trim_nose_up` / `_down` | pitch trim at `trim_rate` | Home / End | D-pad down / up (buttons 12 / 11) | buttons 4 / 5 |
| `jsbsim_autopilot_toggle` | `JSBSimAutopilot` child on (holding the current state) / off | T | Y, top face button (button 3) | button 3 |

The `FLIGHT_STICK` numbers are exports (`stick_roll_axis`, `stick_pitch_axis`, `stick_rudder_axis`,
`stick_throttle_axis`, `stick_brake_button`, `stick_autopilot_button`, `stick_trim_up_button`,
`stick_trim_down_button`), so a stick with another layout needs no project changes.

Behaviour:
- A key ramps the control at `key_rate` per second and recentres when released; a joypad axis is used directly.
  The control follows whichever moved it last.
- `dead_zone` (default 0.1) is the dead zone of the actions this node adds; `expo` squares stick input (finer near
  the centre).
- `absolute_throttle` (on with `FLIGHT_STICK`): the lever sets the throttle (fully forward = 1, back = 0). Until the
  lever first moves, the throttle keys still work, so the same setup flies without a stick.
- While the aircraft's `JSBSimAutopilot` is on, the stick and pedals are left to it, and the throttle too with
  `speed_hold`; brakes and trim stay with the pilot.

## Finding your device's numbers
Gamepads known to SDL's controller database (Xbox, PlayStation, Switch Pro and most others) arrive in Godot with the
standard layout above. Flight sticks, throttles and pedals are usually not in that database: Godot then numbers their
axes and buttons in the order the device reports them, which differs between models.

In the flight demo press **F4**: it lists every connected device (name, GUID) with its raw axis values and pressed
buttons. Move each control and note its number, then set the `stick_*` exports or map the actions in the Input Map.
Separate throttle quadrants or pedals are separate devices; InputMap events with device "All devices" (the default
this node uses) accept them all.

Godot's own reference: *Input examples* and *Controllers, gamepads and joysticks* in the Godot documentation.
