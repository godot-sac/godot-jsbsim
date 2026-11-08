# Using other aircraft

godot-jsbsim flies any JSBSim model; it bundles two (`J3Cub` and `TUAV`, below). A model is a folder of JSBSim XML
files. JSBSim looks for it in a *data folder*:

```
my_data/
  aircraft/
    MyPlane/
      MyPlane.xml          # the model: metrics, mass, gear, propulsion, flight control, aerodynamics
      Engines/             # engine and thruster files the model names (or my_data/engine/)
      Systems/             # optional system files (or my_data/systems/)
```

## Load it
```gdscript
var fdm := JSBSimFDM.new()
fdm.load_model("MyPlane", "res://my_data")       # data folder, res:// or an absolute path
```
or set `JSBSimAircraft.aircraft = "MyPlane"` and `JSBSimAircraft.data_dir = "res://my_data"`.
`JSBSimFDM.get_last_error()` tells what JSBSim could not find; `JSBSimFDM.set_log_level(JSBSimFDM.LOG_INFO)` shows
what it loads.

In an exported game the folder is extracted from the `.pck` to `user://jsbsim/` on first use; add `*.xml` to the
export filter (*Export → Resources → Filters to export non-resource files*).

## Bundled models
| Name | | Speeds | Notes |
|---|---|---|---|
| `J3Cub` | Piper J-3 Cub, unmodified from JSBSim 1.3.3 | trims about 40–85 kt | tail wheel; the autopilot gains are tuned with it |
| `TUAV` | generic small tactical UAV (piston pusher, fixed tricycle gear, 136 kg, 4.9 m span), our own | trims 55–90 kt, about 300 m/min climb at full power | a stand-in for a UAV in games and demos, not data of a real aircraft |

`TUAV` is generated with JSBSim's AeromatiC++ 3.3.21 from the inputs in `aircraft/TUAV/aeromatic.param` (this
repository; class-typical round numbers) and copied into the add-on by `tools/bundle_aircraft.py`. To change it, edit
the inputs, regenerate (build `thirdparty/jsbsim/utils/aeromatic++` with CMake, then run `aeromatic -i
aeromatic.param` in an empty folder, see the header of `tools/bundle_aircraft.py`), copy the result over
`aircraft/TUAV/` and run `tools/bundle_aircraft.py` and the tests (`tests/unit/test_tuav.gd`). It is LGPL-2.1 like
the rest of JSBSim's data: most of the files are AeromatiC++'s templates.

## Where models come from
- **JSBSim's repository** (`thirdparty/jsbsim/aircraft/`, about 60 models). The files have mixed licences: most
  fall under JSBSim's LGPL-2.1, some state GPL, many carry a "not to be sold" note. Read each model's
  `<fileheader>` and the engine / system files it uses before you ship it, and look at its git history: a clean
  header today does not mean a clean origin (the `pc7` was synced with FlightGear's GPL data and once carried a
  "not to be sold" note that a later regeneration dropped). godot-jsbsim bundles only models whose files and
  history show neither (`tools/bundle_aircraft.py` keeps the reviewed list, refuses the rest and writes a
  `NOTICE.md` with the origin of each bundled model).
- **Aeromatic** (JSBSim's model generator, `thirdparty/jsbsim/utils/aeromatic++`) makes a first model from a few
  numbers (type, weight, wing span, engines); good enough to start, to be tuned against real data.
- **FlightGear aircraft** often include a JSBSim model, mostly under the GPL: fine for your own use, not for a game
  you ship under other terms.

## Make it fly well in Godot
- `JSBSimAircraft.trim_on_start` trims the model for level flight at the start airspeed. Some models do not trim
  (JSBSim's `pc7` does not in JSBSim 1.3.3): the aircraft then starts untrimmed; start on the ground instead
  (`start_on_ground`) or tune the start speed.
- The visual model looks along −Z with +Y up; the node's origin is JSBSim's centre of gravity, so the mesh is
  placed relative to it (JSBSim's `<location name="CG">`, in the model's structural frame).
- The controls the node writes are JSBSim's standard ones (`fcs/aileron-cmd-norm`, `fcs/elevator-cmd-norm`,
  `fcs/rudder-cmd-norm`, `fcs/throttle-cmd-norm[n]`, steering and brakes). A model with its own flight control
  system that reads other properties needs them set with `get_fdm().set_property(...)`.
- For DIS, add its SISO-REF-010 entity type to `JSBSimDisTypes.TYPES` or set `DisEntity.entity_type` yourself.
