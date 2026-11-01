# Troubleshooting

**`JSBSimAircraft` / `JSBSimFDM` is not a known class, or "Can't open dynamic library"**
- The libraries for your platform must be in `addons/jsbsim/bin/<platform>/`: the extension (debug and release)
  and the JSBSim library (`JSBSim.dll`, `libJSBSim.so.1` or `libJSBSim.1.dylib`). Building from source puts them
  there ([building.md](building.md)); a release zip has them.
- Windows: the Microsoft Visual C++ Redistributable 2015–2022 (x64) must be installed (it usually is).
- After replacing a library, restart the Godot editor: it does not reload this extension while running.

**The first `godot --headless --import` of a project exits with a crash**
A Godot editor bug (godotengine/godot#111048, fix pending in #123658): a headless editor that discovers a
GDExtension during its first scan can crash on exit, after the import is done. This extension works around it
(`src/editor_first_load_guard.cpp`). If another extension in the project still triggers it, run the command again;
from then on the extension is loaded at startup and the editor exits normally.

**"JSBSimFDM: ..." errors when loading a model**
`get_fdm().get_last_error()` has JSBSim's message. Usually the aircraft name does not match the folder and file
name (`aircraft/<name>/<name>.xml`, case-sensitive on Linux and macOS) or an engine file is missing. See
[aircraft.md](aircraft.md).

**Works in the editor, not in the exported game**
Add `*.xml` to *Export → Resources → Filters to export non-resource files*. The data is extracted to
`user://jsbsim/` on first start; delete that folder to force a fresh copy.

**The aircraft stops, `failed` signal / "JSBSim state is invalid"**
JSBSim's state became infinite or NaN, almost always after hitting the ground very hard with crash detection off.
`restart()` reloads the model.

**The aircraft stops, `crashed` signal**
A wing or another structure touched the ground, a wheel touched down faster than `crash_sink_rate` (4 m/s), or the
aircraft went below the ground. Turn `crash_detection` off to let JSBSim carry on.

**Trim failed**
The model cannot hold level flight at that airspeed and height (or never trims, like JSBSim's `pc7` in 1.3.3). The
aircraft still flies, untrimmed. Try another start airspeed, or start on the ground.

**The aircraft floats above or sinks into the terrain**
JSBSim's ground and the drawn ground must be the same: set `ground_path` to the terrain node (anything with
`height_at(x, z)`), and the same geographic origin for the aircraft and the terrain (`geo_origin_path` or
`origin_*`). Heights are above the WGS84 ellipsoid, not above sea level.

**Other DIS simulations see the aircraft jump or drift**
Use dead reckoning with rotation and acceleration (`DisEntity.dr_algorithm = 4`, RVW), the same `DisGeoOrigin` for
the aircraft and the entity, and keep the `DisEntity` a direct child of the aircraft. With `time_scale` ≠ 1 the
aircraft is published at its game-time speed.

**More output**
`JSBSimFDM.set_log_level(JSBSimFDM.LOG_INFO)` (or `LOG_DEBUG`) shows more JSBSim messages;
`JSBSimFDM.set_debug_level(1)` turns on JSBSim's own console output (model summary, trim report).
