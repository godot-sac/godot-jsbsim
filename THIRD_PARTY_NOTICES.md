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

JSBSim bundles third-party code of its own, compiled into the JSBSim library; the release zip ships their licences
next to `COPYING.JSBSim`:
- Expat XML parser (`src/simgear/xml/`) — MIT License, Copyright (c) 1998-2000 Thai Open Source Software Center Ltd
  and Clark Cooper, Copyright (c) 2001-2019 Expat maintainers. Shipped as `COPYING.Expat`.
- GeographicLib (`src/GeographicLib/`) — MIT License, Copyright (c) 2008-2022 Charles Karney. Shipped as
  `COPYING.GeographicLib`.
- Parts of SimGear (LGPL, like JSBSim) and an MSIS atmosphere model (public domain); their notices are in the
  JSBSim source tree.

### JSBSim aircraft data
`addons/jsbsim/data/` — **not covered by this project's MIT license.** Copied by `tools/bundle_aircraft.py`, unmodified
from JSBSim 1.3.3 or generated with its AeromatiC++; part of the JSBSim distribution, distributed under its **LGPL-2.1** (`COPYING.JSBSim`).
The files name no licence of their own and JSBSim has not stated whether its repository licence covers such files
(JSBSim discussion #1531); `addons/jsbsim/data/LICENSE.md` and a `NOTICE.md` per model record the origin from
JSBSim's git history.
- `J3Cub` — Piper J-3 Cub, Erik Hofman using Aeromatic 3.2.0 (2015), added to JSBSim directly (`bd676b7f`); no GPL
  notice, no "not to be sold" note and no FlightGear sync in its history. Not endorsed by the manufacturer.

- `TUAV` — generic tactical UAV made for godot-jsbsim: generated with JSBSim's AeromatiC++ 3.3.21 (LGPL-2.1) from
  our inputs (`aircraft/TUAV/aeromatic.param`). Most of the files are AeromatiC++'s templates, so they are
  distributed under the LGPL-2.1 like JSBSim's own aircraft, not under MIT.

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

### Other Python tools (`tools/requirements.txt`)
SCons (MIT), CMake (BSD-3-Clause), NumPy (BSD-3-Clause), Open-DIS Python `opendis` (BSD-2-Clause, used by
`tools/dis_capture.py`), pymap3d (BSD-2-Clause); Pillow (MIT-CMU, only for `tools/make_media.py`). Installed by the
developer with pip, not copied into this repository.

### Sibling projects in the demos
`demo/terrain_flight.tscn`, the `--terrain` and `--dis` options use godot-geo and godot-dis (MIT), linked next to
this repository by `tools/link_siblings.py`; nothing of them is copied here.

## Data shown in the documentation images
`docs/images/terrain_flight.jpg`, `docs/images/social_preview.jpg` and the README animation show godot-geo's
Istanbul terrain package; the terrain demo shows the same lines on screen:
produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided
under COPERNICUS by the European Union and ESA; all rights reserved. Contains modified Copernicus Sentinel data 2025.
© OpenStreetMap contributors, Overture Maps Foundation (ODbL 1.0, https://www.openstreetmap.org/copyright).
© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover
consortium (CC BY 4.0). Canopy height: Lang, N., Jetz, W., Schindler, K., Wegner, J. D. (2023), A high-resolution
canopy height model of the Earth, Nature Ecology & Evolution; ETH Global Canopy Height 2020,
doi:10.3929/ethz-b-000609802 (CC BY 4.0). Building heights: Pesaresi, M., Politis, P. (2023), GHS-BUILT-H R2023A,
European Commission, Joint Research Centre, doi:10.2905/85005901-3A49-48DD-9D19-6261354F56FE (CC BY 4.0).
