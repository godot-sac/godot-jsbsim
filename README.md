# godot-jsbsim

[JSBSim](https://github.com/JSBSim-Team/jsbsim) flight dynamics for Godot 4: load JSBSim aircraft models, fly them
in step with Godot's physics, and place them on the WGS84 globe in the same local frame as godot-dis and godot-geo.
A C++ GDExtension; JSBSim (LGPL-2.1) is linked **dynamically** as a separate, replaceable shared library.

> 🚧 Work in progress (Phase 1: core FDM wrapper). Usable from GDScript; no scene node or demo yet.
> See [PLAN.md](PLAN.md).

## Features
Done:
- JSBSim 1.3.3 built as a shared library on Windows (MSVC) and Linux (GCC) by `tools/build_jsbsim.py`
- The extension loads it from the addon folder, without changing `PATH`; JSBSim errors never crash Godot
- `JSBSimFDM`: load a model, set the initial condition (geodetic position, ellipsoid height), trim, step, read and
  write any JSBSim property; JSBSim messages go to the Godot output
- Works in exported games: the XML data is extracted from the `.pck` to `user://` on first use
- Bundled aircraft: `pc7` (Pilatus PC-7) and `J3Cub` (Piper J-3 Cub), unmodified JSBSim data (LGPL-2.1)
- Trajectories match the official JSBSim Python package bit for bit (60 s scenarios with trim and control inputs)

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
```gdscript
var fdm := JSBSimFDM.new()
if not fdm.load_model("J3Cub"):                  # from res://addons/jsbsim/data
	push_error(fdm.get_last_error())
	return
fdm.set_initial_position(39.95, 32.69, 1500.0)   # latitude, longitude (deg), height above the WGS84 ellipsoid (m)
fdm.set_initial_orientation(90.0, 0.0, 0.0)      # heading, pitch, roll (deg)
fdm.set_initial_airspeed(70.0)                   # calibrated airspeed (kt)
fdm.run_ic()
fdm.start_engines()
fdm.trim()                                       # false if the model cannot be trimmed here
fdm.set_property("fcs/aileron-cmd-norm", 0.1)
fdm.step(120)                                    # 120 steps of 1/120 s
print(fdm.get_property("position/geod-alt-ft"), " ft")
```
- Other data folders: `load_model("name", "res://my_aircraft")`, a folder with JSBSim's `aircraft/` and optionally
  `engine/` and `systems/` subfolders.
- **Exporting:** JSBSim reads plain XML files. Add `*.xml` to *Export → Resources → Filters to export non-resource
  files*, otherwise they are not in the `.pck`.
- `JSBSimFDM.set_log_level(JSBSimFDM.LOG_INFO)` shows more JSBSim messages; `set_debug_level(1)` turns on JSBSim's
  own console output (model summary, trim report).
- The bundled `pc7` does not trim in JSBSim 1.3.3 (its turboprop engine model); start it with fixed controls.

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
