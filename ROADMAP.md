# Roadmap

Where godot-jsbsim stands and what may come next. Nothing here is a promise; issues and pull requests that move an
item forward are welcome (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Status: 0.1.0 (first release)
Done and tested on Godot 4.7.2, Windows and Linux (see [docs/compatibility.md](docs/compatibility.md)):
- JSBSim 1.3.3 as a separate shared library (LGPL-2.1), loaded dynamically; JSBSim errors never crash Godot.
- `JSBSimFDM` (model loading, initial conditions with ellipsoid heights, trim, stepping, properties) and the
  `JSBSimAircraft` node (fixed-rate stepping, WGS84 placement in the godot-dis / godot-geo local frame, controls,
  ground contact on flat ground or any `height_at(x, z)` node, crash detection, wind and turbulence).
- `JSBSimAutopilot`: heading, height, airspeed and vertical-speed holds and waypoint routes for any model.
- `JSBSimInput`: keyboard, gamepad and flight stick profiles.
- DIS output through a godot-dis `DisEntity` child (no build dependency).
- Many aircraft at once (about 7 µs per aircraft step, measured in [docs/performance.md](docs/performance.md)).
- One bundled aircraft, the J3Cub, with its provenance recorded.

Not tried yet: macOS (CI builds it, nobody has run it), Godot 4.3–4.6, the CI workflow itself.

## Next (0.2 candidates)
- macOS checked on real hardware (`@rpath` / `@loader_path`, universal binary).
- Older Godot versions (4.3–4.6) tried and listed in the compatibility table.
- Interpolation between JSBSim states for drawing at frame rates far above the simulation rate.
- Gust inputs (JSBSim's cosine gust) exposed on `JSBSimAircraft` (today through `get_fdm().set_property()`).
- More controls and state on the node instead of raw properties: flaps, gear, mixture, per-engine throttle, initial
  pitch / roll / climb rate, alpha / beta getters, fuel and mass, repositioning without `restart()`.

## Later
- JSBSim scripts (`<runscript>`) run from Godot.
- Controls for multi-engine aircraft and helicopters; cockpit instruments.
- Stepping many aircraft on worker threads (not needed so far: 50 aircraft use about 4 % of one core).
- Android and Web builds.
- A bridge to an ArduPilot SITL autopilot.
