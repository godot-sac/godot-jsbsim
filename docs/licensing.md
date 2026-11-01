# Licensing

- **godot-jsbsim** (the extension, GDScript, tools, demo): MIT, see `LICENSE`.
- **JSBSim**: GNU Lesser General Public License 2.1 (LGPL-2.1), see `thirdparty/jsbsim/COPYING`
  (shipped with the addon as `COPYING.JSBSim`).

## How godot-jsbsim complies with the LGPL
- JSBSim is used **unmodified** (git submodule pinned to tag `v1.3.3`).
- JSBSim is built as a **separate shared library** and the extension links to it **dynamically**. No JSBSim source
  is compiled into the extension, and JSBSim is never linked statically.
- The JSBSim library sits as its own file next to the extension (`addons/jsbsim/bin/<platform>/`). You can replace
  it with your own build of a compatible JSBSim version (same major version, same compiler family):
  build it with `tools/build_jsbsim.py` (or JSBSim's CMake with `-DBUILD_SHARED_LIBS=ON`) and overwrite the file.
- The LGPL-2.1 text is shipped with the addon, and the source of the exact JSBSim version is available from the
  JSBSim project (https://github.com/JSBSim-Team/jsbsim, tag `v1.3.3`) and through this repository's submodule.

The release zip carries `JSBSIM_SOURCE.txt` with the exact JSBSim tag and commit and where to get the source.

If you ship a game with godot-jsbsim, keep the JSBSim library a separate, replaceable file, include
`COPYING.JSBSim` and `JSBSIM_SOURCE.txt` and point to the JSBSim source. Your own code is not affected by the LGPL.

## Replacing the JSBSim library
The LGPL lets every user run the program with a modified JSBSim. With godot-jsbsim:
1. Get the JSBSim source of a compatible version (same major version; godot-jsbsim uses JSBSim's C++ classes, so a
   version with a changed API will not load) and change it as you like.
2. Build it as a shared library with the same compiler family as the extension (MSVC with the dynamic C runtime
   `/MD` on Windows, GCC or Clang on Linux, Apple Clang on macOS): `python tools/build_jsbsim.py` with the source in
   `thirdparty/jsbsim`, or JSBSim's CMake with `-DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release` and the
   `libJSBSim` target.
3. Overwrite the file in `addons/jsbsim/bin/<platform>/` (`JSBSim.dll`, `libJSBSim.so.1`, `libJSBSim.1.dylib`) or, in
   an exported game, the copy next to the game's executable (Windows, Linux) or in `Contents/Frameworks` (macOS).
4. Restart Godot or the game.

## Aircraft data
JSBSim's aircraft, engine and systems XML files are data with mixed licences (most fall under the repository's
LGPL-2.1, some state GPL, many carry a "not to be sold" note), and the data is **not** covered by godot-jsbsim's MIT
licence. Most files name no licence of their own; JSBSim's maintainers have not said whether the repository's
LGPL-2.1 applies to them (discussion #1531, October 2026). godot-jsbsim therefore distributes as little as possible:

- One model, `J3Cub`, copied unmodified into `addons/jsbsim/data/` by `tools/bundle_aircraft.py`. Its files and its
  whole git history show no GPL notice, no "not to be sold" note and no data synced from FlightGear (one author,
  added to JSBSim directly in 2015). `addons/jsbsim/data/LICENSE.md` and `aircraft/J3Cub/NOTICE.md` say this next
  to the files.
- Refused although its current header is clean: `pc7`. It was synced with FlightGear's (GPL) data in 2007–2009,
  JSBSim's lead added "This model is not to be sold" in 2012, and the note disappeared when the model was
  regenerated with Aeromatic in 2016, with no recorded reason. The tests still fly it, from the submodule.
- `bundle_aircraft.py` refuses models outside the reviewed list and files that mention the GPL or "not to be sold";
  `--check` compares the bundle with the submodule and the notices with the review.

Other JSBSim models can be used from your own data folder at your own responsibility. If you need data that is
free of these doubts, generate your own model from your own inputs with Aeromatic (JSBSim's `utils/aeromatic++`,
LGPL-2.1 as a tool; its output from your data is yours).
