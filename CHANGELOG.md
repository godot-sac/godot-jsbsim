# Changelog

All notable changes to this project are documented here. Versions follow [semver](https://semver.org/).

## [Unreleased]
### Added
- `docs/getting-started.md`: from an empty project and the release zip to a flying aircraft and an autopilot
  route, with screenshots (tried step by step in a clean Linux directory); `docs/compatibility.md`: what was tested
  with which Godot version and platform.
- Editor icons for `JSBSimAircraft`, `JSBSimAutopilot` and `JSBSimInput` (`addons/jsbsim/icons/`); Asset Library
  icon and social preview image (`docs/images/icon.png`, `social_preview.jpg`).
- CI: a `vX.Y.Z` tag creates a draft GitHub release with the checked zip and the CHANGELOG section.
- `tools/make_media.py`: records the README animation (WebP and GIF, release assets) with Godot's Movie Maker.
- Flight demos: `H` hides the HUD text, `--no-hud` starts that way (the data source lines stay).
- `JSBSimAutopilot` node (child of `JSBSimAircraft`): heading / altitude / airspeed / vertical-speed holds, waypoint
  routes by geodetic or scene position with per-waypoint height and speed, ground-track guidance with crosswind
  correction and turn anticipation, `loop_route`, `waypoint_reached` and `route_finished` signals, stall protection,
  bumpless engagement, `engage()`. Runs before every JSBSim step. `docs/autopilot.md`.
- Flight demo: autopilot keys (T, Y, `,` `.`, `-` `=`, `9` `0`), `--autopilot`, `--route`, `--route-agl`, route
  markers, autopilot line in the HUD and `autopilot` / `waypoints` in `FLIGHT_CHECK`; the terrain demo takes off and
  flies the route with `--ground --takeoff --route`.
- `JSBSimAircraft.wind_speed`, `wind_direction` (from, degrees true) and `turbulence` (MIL-F-8785C severity 0–7,
  JSBSim's milspec model); applied after the trim and kept by `restart()`. Demo `--wind`, `--wind-from`,
  `--turbulence`, HUD line.
- `demo/many_aircraft.tscn` (N aircraft with autopilots on one loop, overview camera, `PERF` line) and
  `docs/performance.md`.
- `JSBSimAircraft.get_ground_normal()`; a ground node may provide `normal_at(x, z)`, used for JSBSim's gear instead
  of the slope estimate. `get_last_step_count()`, `get_last_step_time_usec()`.
- `JSBSimInput`: `profile` (`GAMEPAD`, `FLIGHT_STICK` with configurable axis and button numbers),
  `absolute_throttle` lever actions, pitch trim actions (Home / End), autopilot toggle action (T); the stick leaves
  the controls to an engaged `JSBSimAutopilot`. Flight demo: F4 joypad panel (devices, raw axes and buttons).
  `docs/input.md`.
- Tests: autopilot responses and frame-rate independence (`test_autopilot.gd`), gear on a 5 % slope with the true
  and a vertical normal, no state between ground queries (`test_slope.gd`), joypad mapping (`test_input.gd`), wind and turbulence (`test_atmosphere.gd`);
  `docs/timing.md`.
### Fixed
- `tools/package_addon.py`: the JSBSim version in `JSBSIM_SOURCE.txt` was "unknown" in CI's shallow submodule
  checkout (now from JSBSim's CMake version); editor `.import` files are left out of the zip.
- `JSBSimInput` treated a gamepad stick at full deflection as a key and ramped it; the control now follows the
  device that moved it last.
- Build chain: JSBSim 1.3.3 as a shared library (`tools/build_jsbsim.py`), the extension linked dynamically
  against it (SCons, godot-cpp 10, exceptions on, shared C runtime on Windows).
- `JSBSimFDM`: loads a JSBSim model; initial condition with geodetic position and ellipsoid height; `run_ic`, `trim`,
  `step`, `reset`; property access with checks for unknown names; property list. JSBSim exceptions become errors.
- JSBSim log messages routed to the Godot output (`set_log_level`, `set_debug_level`).
- Data folders inside an exported `.pck` are extracted to `user://jsbsim/` (`extract_data_dir`).
- Bundled aircraft `J3Cub` with `COPYING.JSBSim`, `data/LICENSE.md` and a per-model `NOTICE.md` (origin from
  JSBSim's git history; the data is LGPL-2.1, not MIT); `tools/bundle_aircraft.py` copies reviewed models, checks
  their licence notes and writes the notices. JSBSim's `pc7` is not bundled (unclear provenance).
- `JSBSimAircraft` node: fixed-rate stepping with a time accumulator, placement in the local frame of a geographic
  origin (`geo_origin_path` or `origin_*`), orientation from JSBSim's body-to-ECEF matrix, trim on start with the
  trimmed commands moved into the trim properties, pilot commands, time scale, pause, restart, `failed` signal when
  the JSBSim state becomes invalid.
- Ground contact through a JSBSim ground callback: flat ground (`ground_level`) or a node with `height_at(x, z)`
  (`ground_path`, e.g. godot-geo `GeoTerrain`), with the terrain normal from the slope.
- `start_on_ground` (ground trim), `brake`, nose / tail wheel steering with the rudder, `is_on_ground()`,
  `get_ground_height()`.
- Crash detection (`crashed` signal, `crash_detection`, `crash_sink_rate`): structure contact, hard touchdown or
  below the ground; `restart()` reloads the model after a crash.
- Terrain demo `demo/terrain_flight.tscn` (godot-geo, linked with `tools/link_siblings.py`), `--ground` and
  `--takeoff` (a simple autopilot, `demo/autopilot.gd`) options.
- DIS through godot-dis (no build dependency): a `DisEntity` child of `JSBSimAircraft` gets JSBSim's velocity,
  acceleration and body rates in game time (zero while paused or crashed) and the destroyed appearance after a
  crash; `get_linear_acceleration()`; `JSBSimDisTypes` with the SISO-REF-010 types of the bundled aircraft.
- `--dis`, `--port`, `--marking` demo options; `tools/link_siblings.py` also links godot-dis; `tools/dis_capture.py`
  decodes the PDUs on the network with Open-DIS.
- `tools/package_addon.py` (release zip with the libraries of each platform, `LICENSE`, `THIRD_PARTY_NOTICES.md`,
  `JSBSIM_SOURCE.txt`) and `tools/check_package.py` (installs the zip in a new project and flies the J3Cub).
- CI: JSBSim build cached per JSBSim commit, GUT on macOS too, the package checked in a new project.
- Documentation: other aircraft (`docs/aircraft.md`), troubleshooting, replacing the JSBSim library, release steps.
- `JSBSimInput` (GDScript): keyboard and gamepad input through InputMap actions.
- Flight demo `demo/flight.tscn` with chase / cockpit cameras, HUD, property panel, debug keys and command-line
  options for automated runs.
- C++ unit tests (doctest, `scons tests`): coordinate math (copied from godot-dis) and a cross-check of JSBSim's
  frames against it.
- Oracle scenarios (`tests/golden/`) run by both `JSBSimFDM` and the JSBSim Python package.
- CI workflow for Windows, Linux and macOS (not run yet).

### Fixed
- The first headless import of a new project (`--import`, `--editor --quit`) no longer crashes on exit: works
  around godotengine/godot#111048 by unregistering the classes early when a headless editor loads the
  extension mid-session (`src/editor_first_load_guard.cpp`).
