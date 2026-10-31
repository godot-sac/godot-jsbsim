# Changelog

All notable changes to this project are documented here. Versions follow [semver](https://semver.org/).

## [Unreleased]
### Added
- Build chain: JSBSim 1.3.3 as a shared library (`tools/build_jsbsim.py`), the extension linked dynamically
  against it (SCons, godot-cpp 10, exceptions on, shared C runtime on Windows).
- `JSBSimProbe`: smoke test that loads and flies a JSBSim model from GDScript; compared with the JSBSim Python package.
- CI workflow for Windows, Linux and macOS (not run yet).
