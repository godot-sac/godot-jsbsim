# Changelog

All notable changes to this project are documented here. Versions follow [semver](https://semver.org/).

## [Unreleased]
### Added
- Build chain: JSBSim 1.3.3 as a shared library (`tools/build_jsbsim.py`), the extension linked dynamically
  against it (SCons, godot-cpp 10, exceptions on, shared C runtime on Windows).
- `JSBSimFDM`: loads a JSBSim model; initial condition with geodetic position and ellipsoid height; `run_ic`, `trim`,
  `step`, `reset`; property access with checks for unknown names; property list. JSBSim exceptions become errors.
- JSBSim log messages routed to the Godot output (`set_log_level`, `set_debug_level`).
- Data folders inside an exported `.pck` are extracted to `user://jsbsim/` (`extract_data_dir`).
- Bundled aircraft `pc7` and `J3Cub` with `COPYING.JSBSim`; `tools/bundle_aircraft.py` copies reviewed models and
  checks their licence notes.
- `JSBSimAircraft` node: fixed-rate stepping with a time accumulator, placement in the local frame of a geographic
  origin (`geo_origin_path` or `origin_*`), orientation from JSBSim's body-to-ECEF matrix, trim on start with the
  trimmed commands moved into the trim properties, pilot commands, time scale, pause, restart, `failed` signal when
  the JSBSim state becomes invalid.
- `JSBSimInput` (GDScript): keyboard and gamepad input through InputMap actions.
- Flight demo `demo/flight.tscn` with chase / cockpit cameras, HUD, property panel, debug keys and command-line
  options for automated runs.
- C++ unit tests (doctest, `scons tests`): coordinate math (copied from godot-dis) and a cross-check of JSBSim's
  frames against it.
- Oracle scenarios (`tests/golden/`) run by both `JSBSimFDM` and the JSBSim Python package.
- CI workflow for Windows, Linux and macOS (not run yet).
