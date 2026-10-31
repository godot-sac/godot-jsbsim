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

If you ship a game with godot-jsbsim, keep the JSBSim library a separate, replaceable file, include
`COPYING.JSBSim` and point to the JSBSim source. Your own code is not affected by the LGPL.

## Aircraft data
JSBSim's aircraft, engine and systems XML files are data with mixed licences (most fall under the repository's
LGPL-2.1, some state GPL, many carry a "not to be sold" note). godot-jsbsim only distributes models whose files
state neither GPL nor such a note; each one is listed in `THIRD_PARTY_NOTICES.md`. The tests use the files directly
from the `thirdparty/jsbsim` submodule; nothing from there is distributed with the addon yet.
