# godot-jsbsim

[JSBSim](https://github.com/JSBSim-Team/jsbsim) flight dynamics for Godot 4: load JSBSim aircraft models, fly them
in step with Godot's physics, and place them on the WGS84 globe in the same local frame as godot-dis and godot-geo.
A C++ GDExtension; JSBSim (LGPL-2.1) is linked **dynamically** as a separate, replaceable shared library.

> 🚧 Work in progress (Phase 0: build chain). Not usable yet. See [PLAN.md](PLAN.md).

## Features
Done:
- JSBSim 1.3.3 built as a shared library on Windows (MSVC) and Linux (GCC) by `tools/build_jsbsim.py`
- The extension loads it from the addon folder, without changing `PATH`; JSBSim errors never crash Godot
- Results match the official JSBSim Python package (60 s flight, differences ~1e-14)

Planned (see [PLAN.md](PLAN.md)):
- `JSBSimAircraft` node: initial conditions, controls, any JSBSim property, keyboard / joystick input
- WGS84 / ECEF / local ENU / Godot conversions in doubles, aligned with godot-dis `DisGeoOrigin`
- Ground contact on flat ground or on any terrain with `height_at(x, z)` (e.g. godot-geo `GeoTerrain`)
- Publishing the aircraft on a DIS network with godot-dis
- Prebuilt libraries for Windows, Linux and macOS

## Requirements
- Godot 4.3 or newer (developed with 4.7.2)
- Windows x86_64 (with the Microsoft Visual C++ Redistributable 2015–2022), Linux x86_64; macOS through CI only
- To build from source: see [docs/building.md](docs/building.md)

## Installation
No release yet. Build from source ([docs/building.md](docs/building.md)), then copy `addons/jsbsim/` into your
project.

## Usage
Phase 0 provides only a smoke test:
```gdscript
print(JSBSimProbe.get_jsbsim_version())                      # "1.3.3 ..."
var r := JSBSimProbe.fly_test("res://path/to/jsbsim_data", "pc7", 10.0)
print(r["position/geod-alt-ft"], " ft, ", r["velocities/vc-kts"], " kt")
```
`root_dir` is a folder with JSBSim's `aircraft/`, `engine/` and `systems/` subfolders.

## Demos
Planned: an aircraft flying with keyboard / joystick input, then over real terrain with godot-geo.

## Documentation
- [docs/building.md](docs/building.md) — building JSBSim and the extension, tests, CI
- [docs/licensing.md](docs/licensing.md) — LGPL compliance, replacing the JSBSim library, aircraft data
- [docs/cpp-notes.md](docs/cpp-notes.md) — C++ / GDExtension notes (Turkish)

## Development
```sh
git clone --recursive <repository url> && cd godot-jsbsim
python -m venv tools/.venv && tools/.venv/Scripts/python -m pip install -r tools/requirements.txt
tools/.venv/Scripts/python tools/build_jsbsim.py
tools/.venv/Scripts/scons -j8 target=template_debug
godot --headless --path . --import && godot --headless --path . -s addons/gut/gut_cmdln.gd
```
(`tools/.venv/bin/...` on Linux and macOS.)

## Contributing
Bug reports, questions and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and the
[code of conduct](CODE_OF_CONDUCT.md).

## License
MIT for godot-jsbsim's own code. JSBSim is licensed under the **LGPL-2.1** and is used unmodified, built as a
separate shared library and linked dynamically; you can replace it with your own build. See
[docs/licensing.md](docs/licensing.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
