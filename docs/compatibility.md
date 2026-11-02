# Compatibility

What each godot-jsbsim version was actually tried with. "Declared" means the extension says it loads there
(`compatibility_minimum` in `jsbsim.gdextension`), not that it was run.

## godot-jsbsim 0.1.0 (not released yet)
JSBSim 1.3.3 (shared library, LGPL-2.1), godot-cpp 10 built against the Godot 4.3 extension API.

| Godot | Platform | Build | Status | What was run |
|---|---|---|---|---|
| 4.7.2 | Windows 11 x86_64 | MSVC 2022 (`/MD`) | ✅ tested | GUT 78/78, doctest 3631 assertions, flight / terrain / many-aircraft demos, release zip in an empty project (`check_package.py`), [getting-started](getting-started.md) |
| 4.7.2 | Linux x86_64: Ubuntu 24.04 (WSL 2), glibc 2.39 | GCC 13 | ✅ tested | GUT 72 + 1 pending (no godot-dis / godot-geo links), doctest, flight demo `FLIGHT_CHECK`, the same release zip in an empty project, getting-started followed step by step in a clean directory |
| 4.7.2 | Linux x86_64: Ubuntu 22.04 (CI) | GCC 11 | ⏳ not run yet | CI job written (build, doctest, GUT, package check); runs after the first push |
| 4.7.2 | macOS universal (arm64 + x86_64) | Apple Clang (CI) | ⏳ not run yet | CI job written; never built or run |
| 4.3 – 4.6 | any | — | ❔ declared | not tried |
| 4.7.2 .NET (C#) build | any | — | ❔ untested | not tried |

Notes:
- **Bit-for-bit results:** the J3Cub oracle scenarios match the official `jsbsim` Python package exactly on both
  tested platforms, and the getting-started route prints the same numbers on Windows and Linux.
- **Exported games:** the data extraction from a `.pck` is tested with `PCKPacker` + `load_resource_pack`
  (`tests/unit/test_data.gd`); a real export with Godot's export templates has not been tried yet.
- **Linux libraries** of the release are built on Ubuntu 22.04 (CI), so they should run on glibc 2.35 or newer;
  older systems are not tried. The zips built locally for testing came from Ubuntu 24.04.
- **Windows** needs the Microsoft Visual C++ Redistributable 2015–2022 (x64).
- Only x86_64 on Windows and Linux; no ARM64 Linux / Windows, Android, iOS or Web builds.

Tried something not in this table? Please open an issue with the Godot version, the platform and what happened.
