# Third-Party Notices

godot-jsbsim itself is MIT licensed (`LICENSE`). It uses the following third-party software.

## Distributed with the addon

### JSBSim 1.3.3
https://github.com/JSBSim-Team/jsbsim (tag `v1.3.3`, git submodule `thirdparty/jsbsim`, unmodified).
**GNU Lesser General Public License 2.1** — not covered by this project's MIT license. Full text:
`thirdparty/jsbsim/COPYING`, shipped with the addon as `COPYING.JSBSim`.

JSBSim is built as a separate shared library (`JSBSim.dll`, `libJSBSim.so.1`, `libJSBSim.1.dylib`) and loaded
dynamically by the extension; it can be replaced by the user. Copyright the JSBSim authors (see
`thirdparty/jsbsim/AUTHORS`). Details: [docs/licensing.md](docs/licensing.md).

JSBSim bundles third-party code of its own (Expat, parts of SimGear, GeographicLib, an MSIS atmosphere model);
their notices are in the JSBSim source tree.

### JSBSim aircraft data
`addons/jsbsim/data/` — **not covered by this project's MIT license.** Copied unmodified from JSBSim 1.3.3 by
`tools/bundle_aircraft.py`; part of the JSBSim distribution, distributed under its **LGPL-2.1** (`COPYING.JSBSim`).
The files name no licence of their own and JSBSim has not stated whether its repository licence covers such files
(JSBSim discussion #1531); `addons/jsbsim/data/LICENSE.md` and a `NOTICE.md` per model record the origin from
JSBSim's git history.
- `J3Cub` — Piper J-3 Cub, Erik Hofman using Aeromatic 3.2.0 (2015), added to JSBSim directly (`bd676b7f`); no GPL
  notice, no "not to be sold" note and no FlightGear sync in its history. Not endorsed by the manufacturer.

Not distributed: JSBSim's `pc7` (used by the tests from the submodule only); see docs/licensing.md.

### godot-cpp 10.0.0
https://github.com/godotengine/godot-cpp — MIT License, Copyright (c) 2017-present Godot Engine contributors.
Compiled into the extension.

## Development and tests only (not distributed)

### GUT 9.7.1 (Godot Unit Test)
`addons/gut/` — MIT License, Copyright (c) 2018 Tom "Butch" Wesley. Full text: `addons/gut/LICENSE.md`.

### godot-dis coordinate math
`src/geo/geo_math.*`, `tests/cpp/test_geo.cpp` and `tests/golden/geo_cases.txt` are copied from godot-dis, a sibling
project under the same MIT license.

### doctest 2.4.12
`thirdparty/doctest/doctest.h` — MIT License, Copyright (c) 2016-2023 Viktor Kirilov.
Full text: `thirdparty/doctest/LICENSE.txt`.

### JSBSim Python package 1.3.3
`pip install jsbsim==1.3.3` (LGPL-2.1), used by `tools/oracle_fly.py` as a reference in the tests.
