# Changelog

All notable changes to this project are documented here. Versions follow [semver](https://semver.org/).

## [Unreleased]
### Fixed
- `JSBSimAutopilot`: a waypoint added after the route finished is flown (it becomes active and `follow_route` is
  turned on again); before, the new waypoint stayed inactive.
- `JSBSimAutopilot.get_waypoint()`: a waypoint without a height is placed at the aircraft's current height (where it
  is flown), not at the frame origin's height.
- `JSBSimAircraft.restart()` in the air starts with the throttle of `start()`, like the other pilot commands,
  instead of the throttle of the last flight (seen without trim or when the trim failed).
### Documentation
- Exported games tested with Godot 4.7.2 release templates on Windows and Linux (docs/compatibility.md).

## [0.2.0] - 2026-11-09
### Added
- Class reference in the editor: F1 on `JSBSimFDM`, `JSBSimAircraft` and `JSBSimAutopilot` shows their
  description, methods, properties, signals and constants (`doc_classes/`, built into the debug library).
  `tools/check_docs.py` and a CI step keep it complete and in step with the API.
- Second bundled aircraft `TUAV`: a generic small tactical UAV generated with JSBSim's AeromatiC++ from our inputs
  (`aircraft/TUAV/`, LGPL-2.1 like the other aircraft data); trims 55–90 kt and flies `JSBSimAutopilot` routes
  with the default gains (`tests/unit/test_tuav.gd`). DIS type `[1, 2, 0, 50, 0, 0, 0]` (unmanned) in
  `JSBSimDisTypes`. `tools/bundle_aircraft.py` bundles our own models next to JSBSim's.

## [0.1.0] - 2026-11-08
First release.

### Added
**Build and packaging**
- JSBSim 1.3.3 built as a shared library on Windows (MSVC) and Linux (GCC) by `tools/build_jsbsim.py`; the
  extension (godot-cpp 10, SCons, exceptions on, shared C runtime on Windows) links to it dynamically and loads it
  from the addon folder without changing `PATH`.
- `tools/package_addon.py`: the release zip with the libraries of each platform, `LICENSE`,
  `THIRD_PARTY_NOTICES.md`, `COPYING.JSBSim`, `COPYING.Expat`, `COPYING.GeographicLib` and `JSBSIM_SOURCE.txt`
  (JSBSim tag, commit and source). `tools/check_package.py` installs the zip in a new, empty project, checks the
  licence notes and a first import without errors or warnings, and flies the J3Cub.
- CI for Windows and Linux: JSBSim build cached per commit, GUT, C++ tests, the package checked in a new
  project; a `vX.Y.Z` tag creates a draft GitHub release with the zip and this file's section as notes.

**Flight model**
- `JSBSimFDM`: loads a JSBSim model; initial condition with geodetic position and ellipsoid height; `run_ic`,
  `trim`, `step`, `reset`; property access with checks for unknown names and a property list. JSBSim exceptions
  become Godot errors; JSBSim log messages go to the Godot output (`set_log_level`, `set_debug_level`).
- Data folders inside an exported `.pck` are extracted to `user://jsbsim/` (`extract_data_dir`).
- `JSBSimAircraft` node: fixed-rate stepping (120 Hz) with a time accumulator, the controls applied at every JSBSim
  step (the same flight at any frame rate), placement in the local frame of a geographic origin (`geo_origin_path`
  or `origin_*`; +X east, +Y up, −Z north, like godot-dis `DisGeoOrigin`), orientation from JSBSim's body-to-ECEF
  matrix, trim on start, pilot commands, time scale, pause, `advance()`, `restart()`, `failed` signal when the
  JSBSim state becomes invalid, `get_last_step_count()`, `get_last_step_time_usec()`.
- Ground contact through a JSBSim ground callback: flat ground (`ground_level`) or a node with `height_at(x, z)`
  (`ground_path`, e.g. godot-geo `GeoTerrain`), with the terrain normal from the node's `normal_at(x, z)` or from
  the slope (`get_ground_normal()`); `start_on_ground`, `brake`, wheel steering, `is_on_ground()`,
  `get_ground_height()`.
- Crash detection (`crashed` signal, `crash_detection`, `crash_sink_rate`): structure contact, hard touchdown or
  below the ground.
- Wind and turbulence: `wind_speed`, `wind_direction` (from, degrees true) and `turbulence` (MIL-F-8785C severity
  0–7, JSBSim's milspec model), applied after the trim and kept by `restart()`.
- `JSBSimAutopilot` node (child of `JSBSimAircraft`): heading, altitude, airspeed and vertical-speed holds, waypoint
  routes by geodetic or scene position with per-waypoint height and speed, ground-track guidance with crosswind
  correction and turn anticipation, `loop_route`, `waypoint_reached` and `route_finished` signals, stall
  protection, bumpless engagement. Runs before every JSBSim step; works with any model.
- `JSBSimInput` (GDScript): keyboard, gamepad and flight stick (`profile`, configurable axes and buttons, dead
  zone, expo, absolute throttle lever, pitch trim, autopilot toggle); it leaves the controls to an engaged
  `JSBSimAutopilot`.
- DIS through godot-dis without a build dependency: a `DisEntity` child of `JSBSimAircraft` gets JSBSim's velocity,
  acceleration and body rates in game time and the destroyed appearance after a crash;
  `get_linear_acceleration()`; `JSBSimDisTypes` with the SISO-REF-010 type of the bundled aircraft.
- Bundled aircraft `J3Cub` with `COPYING.JSBSim`, `data/LICENSE.md` and a `NOTICE.md` (origin from JSBSim's git
  history; the data is LGPL-2.1, not MIT); `tools/bundle_aircraft.py` copies reviewed models and checks their
  licence notes.
- Editor icons for `JSBSimAircraft`, `JSBSimAutopilot` and `JSBSimInput`.

**Demos**
- `demo/flight.tscn` (main scene): a J3Cub over flat ground at Istanbul Sabiha Gökçen, chase and cockpit cameras,
  HUD, property panel (F3), joypad panel (F4), debug keys, autopilot keys, `H` / `--no-hud`, and command-line options
  for automated runs (`--seconds` with a `FLIGHT_CHECK` line, `--time-scale`, `--ground`, `--takeoff`, `--autopilot`,
  `--route`, `--wind`, `--turbulence`, `--screenshot`, `--dis`, `--port`, `--marking`).
- `demo/terrain_flight.tscn`: the same on godot-geo's 60 km Istanbul terrain (linked by `tools/link_siblings.py`),
  from Sabiha Gökçen's north runway (06); `--route` flies a 66 km loop over the Marmara coast, the Maiden's Tower,
  the 15 July Martyrs Bridge and Büyük Çamlıca and back; `--start-at N`; the terrain's data sources on screen.
- `demo/many_aircraft.tscn`: N aircraft with their own autopilots, overview camera, `PERF` line.
- Tools: `tools/dis_capture.py` (decodes the demo's PDUs with Open-DIS), `tools/make_media.py` (README animation).

**Tests and documentation**
- GUT tests (aircraft, ground and slopes, takeoff and landing, runway on real terrain, autopilot and frame-rate
  independence, input, wind, DIS, data extraction), oracle scenarios compared with the JSBSim Python package, and
  C++ unit tests (doctest) for the coordinate math and JSBSim's frames.
- Documentation: getting started, autopilot, timing, input, performance, other aircraft, troubleshooting, building,
  compatibility, release, licensing (replacing the JSBSim library); [ROADMAP.md](ROADMAP.md).

### Known issues
- Godot 4.7's first headless import of a new project could crash on exit when it discovers the extension
  (godotengine/godot#111048); `src/editor_first_load_guard.cpp` works around it.
- Tested on Godot 4.7.2 only, on Windows and Linux; macOS has not been built or run yet.
