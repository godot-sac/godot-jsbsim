# Using other aircraft

godot-jsbsim flies any JSBSim model; it only bundles two (`pc7`, `J3Cub`). A model is a folder of JSBSim XML
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

## Where models come from
- **JSBSim's repository** (`thirdparty/jsbsim/aircraft/`, about 60 models). The files have mixed licences: most
  fall under JSBSim's LGPL-2.1, some state GPL, many carry a "not to be sold" note. Read each model's
  `<fileheader>` and the engine / system files it uses before you ship it. godot-jsbsim bundles only models with
  neither (`tools/bundle_aircraft.py` keeps the reviewed list and refuses the rest).
- **Aeromatic** (JSBSim's model generator, `thirdparty/jsbsim/utils/aeromatic++`) makes a first model from a few
  numbers (type, weight, wing span, engines); good enough to start, to be tuned against real data.
- **FlightGear aircraft** often include a JSBSim model, mostly under the GPL: fine for your own use, not for a game
  you ship under other terms.

## Make it fly well in Godot
- `JSBSimAircraft.trim_on_start` trims the model for level flight at the start airspeed. Some models do not trim
  (the bundled `pc7` does not in JSBSim 1.3.3): the aircraft then starts untrimmed; start on the ground instead
  (`start_on_ground`) or tune the start speed.
- The visual model looks along −Z with +Y up; the node's origin is JSBSim's centre of gravity, so the mesh is
  placed relative to it (JSBSim's `<location name="CG">`, in the model's structural frame).
- The controls the node writes are JSBSim's standard ones (`fcs/aileron-cmd-norm`, `fcs/elevator-cmd-norm`,
  `fcs/rudder-cmd-norm`, `fcs/throttle-cmd-norm[n]`, steering and brakes). A model with its own flight control
  system that reads other properties needs them set with `get_fdm().set_property(...)`.
- For DIS, add its SISO-REF-010 entity type to `JSBSimDisTypes.TYPES` or set `DisEntity.entity_type` yourself.
