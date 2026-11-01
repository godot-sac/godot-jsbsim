# Making a release

1. Update `CHANGELOG.md`: move *Unreleased* to `## [x.y.z] - YYYY-MM-DD` (semver; 0.x while the API may change).
2. Check locally: GUT, `scons tests`, the demos' `FLIGHT_CHECK` runs, `tools/wsl_check.sh` (Linux) and
   `python tools/package_addon.py` + `python tools/check_package.py build/package/godot-jsbsim-dev.zip --godot <godot>`.
3. Commit, tag `vx.y.z` and push the tag. CI builds all platforms and uploads `godot-jsbsim-x.y.z.zip`
   (`addons/jsbsim/` with the libraries for Windows, Linux and macOS, `COPYING.JSBSim`, `LICENSE`,
   `THIRD_PARTY_NOTICES.md` and `JSBSIM_SOURCE.txt`), checked in a new project.
4. Create a GitHub release for the tag and attach that zip.

## Godot Asset Library
The Asset Library installs an asset by downloading the repository archive of one commit. The compiled libraries
are not in git, so that archive alone does not work. Options:
- a `release` branch (or a separate repository) where CI commits `addons/jsbsim/` with the libraries, and the
  Asset Library entry points to it;
- the newer Godot Asset Store, which takes an uploaded zip (the release zip as it is).

Entry text: name "godot-jsbsim", category *Scripts* (or *Misc*), licence MIT (JSBSim LGPL-2.1, noted in the
description), Godot 4.3+, the README's first paragraph as the description, `docs/images/terrain_flight.png` as the
preview. The icon is still to be made (128×128 PNG).
