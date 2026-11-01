# Building

godot-jsbsim has two native libraries:
1. **JSBSim** (LGPL-2.1), built from `thirdparty/jsbsim` with JSBSim's own CMake build as a **shared library**
   (`JSBSim.dll`, `libJSBSim.so.1`, `libJSBSim.1.dylib`) by `tools/build_jsbsim.py`.
2. **The extension** (MIT), built with SCons and godot-cpp, linked dynamically against JSBSim.

Both end up in `addons/jsbsim/bin/<platform>/`. Keeping JSBSim a separate shared library is what the LGPL asks
for (see [licensing.md](licensing.md)).

## Requirements
- Python 3.10+ (SCons, CMake and the JSBSim Python package come from `tools/requirements.txt`)
- Windows: Visual Studio 2022 with the "Desktop development with C++" workload (MSVC 14.4x)
- Linux: GCC 11+ or Clang 14+
- Godot 4.3 or newer to run it (developed with 4.7.2)

## First time
PowerShell (Windows), from the repo root:
```powershell
git clone --recursive <repo>          # or: git submodule update --init
py -3.13 -m venv tools\.venv
.\tools\.venv\Scripts\python.exe -m pip install -r tools\requirements.txt
```
Linux/macOS: `python3 -m venv tools/.venv && tools/.venv/bin/pip install -r tools/requirements.txt`.

## Build
```powershell
.\tools\.venv\Scripts\python.exe tools\build_jsbsim.py            # JSBSim, once (about a minute)
.\tools\.venv\Scripts\scons.exe -j16 target=template_debug       # editor and debug exports
.\tools\.venv\Scripts\scons.exe -j16 target=template_release     # release exports
```
Linux/macOS: the same with `tools/.venv/bin/python` and `tools/.venv/bin/scons`; on macOS add
`--arch "arm64;x86_64"` to `build_jsbsim.py` and `arch=universal` to SCons.

`build_jsbsim.py` uses the Visual Studio 2022 CMake generator on Windows (no developer prompt needed) and puts the
import library / link-time copy in `build/jsbsim/<platform>/lib/`, which `SConstruct` links against.
After rebuilding, restart the Godot editor if it had the old libraries loaded.

## How the libraries find each other
- **Windows:** Godot loads GDExtension libraries with the library's own folder on the DLL search path, so
  `JSBSim.dll` next to `libgodot_jsbsim.*.dll` is found without changing `PATH`.
- **Linux:** the extension is linked with `RUNPATH=$ORIGIN`, so `libJSBSim.so.1` is found next to it.
- **macOS:** linked with `@loader_path` in the rpath; on export the dylib goes to `Contents/Frameworks`.
- The `[dependencies]` section of `jsbsim.gdextension` makes Godot copy the JSBSim library on export.

## Compiler settings that matter
- **Exceptions on:** JSBSim reports errors with C++ exceptions; godot-cpp disables them by default. `SConstruct`
  sets `disable_exceptions=no`, and every call into JSBSim is wrapped in `try`/`catch`.
- **Shared C runtime on Windows (`/MD`):** JSBSim's API passes `std::string` and other STL objects between the two
  DLLs, so both must use the same C runtime. `SConstruct` sets `use_static_cpp=no` (godot-cpp's default is `/MT`).
  Users therefore need the Microsoft Visual C++ Redistributable (2015–2022), which most Windows systems have.
- Both libraries must be built with the same compiler family (MSVC with MSVC, GCC with GCC).

## Continuous integration
`.github/workflows/ci.yml` (not run yet; the repository is not on GitHub): Windows, Linux (Ubuntu 22.04) and macOS
(universal) build JSBSim and the extension; Windows and Linux run the GUT tests, including the comparison with the
JSBSim Python package. A final job packs `addons/jsbsim` with all libraries and `COPYING.JSBSim`.
The Linux steps were checked locally in WSL (Ubuntu 24.04, GCC 13); macOS has not been tried.

## Test
```powershell
$godot = "C:\path\to\godot.exe"   # your Godot path
& $godot --headless --path . --import
& $godot --headless --path . -s addons/gut/gut_cmdln.gd
```
C++ unit tests (doctest, no Godot; they link the JSBSim library):
```sh
tools/.venv/Scripts/scons tests
```
`tests/cpp/test_geo.cpp` checks the coordinate math against pymap3d values (copied from godot-dis);
`test_jsbsim_frame.cpp` checks that JSBSim's ECEF location and body-to-ECEF matrix agree with that math and with
JSBSim's own heading / pitch / roll.

`test_ground.gd` flies takeoff and landing with the simple autopilot in `demo/autopilot.gd`.

`test_dis.gd` needs godot-dis (`tools/link_siblings.py`; skipped otherwise): it compares the Entity State PDU of a
`DisEntity` on the aircraft with JSBSim's position, attitude, velocity and body rates. On the network:
`tools/.venv/Scripts/python tools/dis_capture.py --port 3920` and a demo with `--dis --port 3920` (any free port, so
open demos are not disturbed); it decodes each PDU with Open-DIS and reports the dead reckoning error.

The flight demo can run unattended: `godot --headless --path . res://demo/flight.tscn -- --seconds 60` prints a
`FLIGHT_CHECK` line and exits with 1 if the aircraft failed or touched the ground.

`test_oracle.gd` runs every `tests/golden/*_scenario.json` (aircraft, initial condition, trim, control inputs, sampled
properties) with `JSBSimFDM` and with `tools/oracle_fly.py` (the official `jsbsim` Python package, same version) and
compares the trajectories; it is "pending" if `tools/.venv` is missing. `test_data.gd` builds a `.pck` with
`PCKPacker` to check the extraction used by exported games.

## Bundled aircraft
```sh
tools/.venv/Scripts/python tools/bundle_aircraft.py            # copy the bundled models and COPYING.JSBSim
tools/.venv/Scripts/python tools/bundle_aircraft.py --check    # verify the bundle matches the submodule
```
