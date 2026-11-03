# Timing and ground contact

## Fixed simulation rate
JSBSim must run at a fixed step: its engine, propeller and landing-gear models are tuned for small, regular steps
(JSBSim issue #1322: stepping once per rendered frame made a piston engine's RPM collapse below ~40 FPS).
`JSBSimAircraft` keeps the two apart:

- `rate` (default 120 Hz) is JSBSim's step. It never changes with the frame rate.
- Every Godot physics frame (`_physics_process`, 60 Hz by default) adds `delta × time_scale` to an accumulator and
  runs as many whole JSBSim steps as fit; the remainder carries over. At 60 Hz physics that is 2 steps per frame; with
  `physics_ticks_per_second = 50` it alternates 2 and 3.
- The controls and `JSBSimAutopilot` are applied **before every JSBSim step**, not once per frame, so a flight is
  the same at any frame rate: `tests/unit/test_autopilot.gd` flies a route at 120, 60, 30, 20 and 7.5 FPS and ends at
  the same position, bit for bit.
- `get_last_step_count()` and `get_last_step_time_usec()` tell what the last `advance()` did.

### Below 40 FPS
Godot runs the physics frames a rendered frame owes, up to `physics/common/max_physics_steps_per_frame` (8) per
rendered frame. So:

| rendered FPS | physics frames per rendered frame (60 Hz physics) | JSBSim steps per rendered frame | simulation |
|---|---|---|---|
| 144 | 0–1 | 0–2 | real time |
| 60 | 1 | 2 | real time |
| 30 | 2 | 4 | real time |
| 20 | 3 | 6 | real time |
| 10 | 6 | 12 | real time |
| below 7.5 | 8 (the limit) | 16 | slower than real time; the step is still 1/120 s |

Checked with the demo: `--fixed-fps 144`, `60`, `20` and `10` with `--route --seconds 60` give the same
`FLIGHT_CHECK` line. A single very long frame (a debugger stop, loading) runs at most 2400 steps (20 s) and drops the
rest instead of freezing the game.

Input from the keyboard or a gamepad is read once per physics frame, so at low frame rates the pilot's commands
change in coarser steps; the simulation itself does not.

### Smooth drawing
The node's transform changes at the physics rate. On a high-refresh display enable
*Project Settings → Physics → Common → Physics Interpolation* so Godot interpolates the drawn position between physics
frames, or raise `physics_ticks_per_second` (for example to 120, one JSBSim step per physics frame).

## Ground contact on slopes
JSBSim asks the ground callback for the height **and the normal** under every gear contact point and under the
aircraft. `JSBSimAircraft`'s callback:

- returns the height of the `ground_path` node (`height_at(x, z)`) or the flat `ground_level` (a plane in the scene,
  so it rises above the ellipsoid away from the origin: 70 m at 30 km);
- returns the normal from the node's `normal_at(x, z)` if it has one, otherwise from the slope of the heights 1 m
  around the point (within one cell of a gridded terrain, that cell's own slope);
- computes everything from the queried location only and keeps nothing between calls (JSBSim discussion #1510 found
  a callback that leaked the nose gear's elevation into the next query).

Why the normal matters: JSBSim's gear model measures the strut compression and its speed along the normal. With a
vertical normal on a slope, the gear over-compresses and gets false damping (#1510). Measured on a 5 % (2.9°) ramp
with the J3Cub at rest (`tests/unit/test_slope.gd`):

| ground | total gear compression |
|---|---|
| flat | 0.390 m |
| 5 % slope, true normal | 0.402 m (+3 %, the weight shifts between the wheels) |
| 5 % slope, vertical normal | 0.521 m (+34 %) |

Taxiing up and down the ramp with the true normal, no gear unit loses and regains contact (no weight-on-wheels
bounce).
