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
- Oracle scenarios (`tests/golden/`) run by both `JSBSimFDM` and the JSBSim Python package.
- CI workflow for Windows, Linux and macOS (not run yet).
