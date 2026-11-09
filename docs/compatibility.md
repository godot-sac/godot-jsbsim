# Compatibility

What each godot-jsbsim version was actually tried with. "Declared" means the extension says it loads there
(`compatibility_minimum` in `jsbsim.gdextension`), not that it was run.

## godot-jsbsim 0.2.0 and 0.1.0
JSBSim 1.3.3 (shared library, LGPL-2.1), godot-cpp 10 built against the Godot 4.3 extension API.

| Godot | Platform | Build | Status | What was run |
|---|---|---|---|---|
| 4.7.2 | Windows 11 x86_64 | MSVC 2022 (`/MD`) | ✅ tested | GUT 84/84 with godot-geo and godot-dis linked, 75 + 2 skipped in a clean clone, doctest 3631 assertions, flight / terrain / many-aircraft demos, release zip in an empty project (`check_package.py`), [getting-started](getting-started.md) |
| 4.7.2 | Linux x86_64: Ubuntu 24.04 (WSL 2), glibc 2.39 | GCC 13 | ✅ tested | GUT 75 + 2 skipped in a clean clone (no sibling links), runway tests on the Istanbul terrain with godot-geo linked, doctest, flight demo `FLIGHT_CHECK`, the same release zip in an empty project, getting-started followed step by step in a clean directory |
| 4.7.2 | Windows 11 x86_64 | MSVC 2022 (`/MD`) | ✅ tested (0.2.0) | GUT with the `TUAV` trim and route tests, class reference check |
| 4.7.2 | Windows Server 2022, Linux x86_64: Ubuntu 22.04 (CI) | MSVC 2022, GCC 11 | ✅ tested (0.1.0, 0.2.0) | build, doctest, GUT, class reference check, release zip in an empty project |
| 4.7.2 | macOS universal (arm64 + x86_64) | Apple Clang (CI) | ⏳ not in 0.1 | Removed from CI and the zip until it can be tested; the build files support it |
| 4.3 – 4.6 | any | — | ❔ declared | not tried |
| 4.7.2 .NET (C#) build | any | — | ❔ untested | not tried |

Notes:
- **Bit-for-bit results:** the J3Cub oracle scenarios match the official `jsbsim` Python package exactly on both
  tested platforms, and the getting-started route prints the same numbers on Windows and Linux.
- **Exported games:** the data extraction from a `.pck` is tested with `PCKPacker` + `load_resource_pack`
  (`tests/unit/test_data.gd`), and a real export with Godot 4.7.2 release templates flies on Windows and Linux
  (2026-11-09, release zip 0.1.0, in godot-sim-demo; see godot-sim-demo's [export guide](https://github.com/godot-sac/godot-sim-demo/blob/main/docs/export.md)). Add `*.xml` to the export's include filter.
- **Linux libraries** of the release are built on Ubuntu 22.04 (CI), so they should run on glibc 2.35 or newer;
  older systems are not tried. A zip built locally on a newer distribution needs that distribution's glibc (the
local test zips came from Ubuntu 24.04 and need glibc 2.38): publish the CI zip, not a local one.
- **Windows** needs the Microsoft Visual C++ Redistributable 2015–2022 (x64).
- Only x86_64 on Windows and Linux; no ARM64 Linux / Windows, Android, iOS or Web builds.

Tried something not in this table? Please open an issue with the Godot version, the platform and what happened.
