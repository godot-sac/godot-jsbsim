# Making a release

1. Update `CHANGELOG.md`: move *Unreleased* to `## [x.y.z] - YYYY-MM-DD` (semver; 0.x while the API may change).
2. Check locally: GUT, `scons tests`, the demos' `FLIGHT_CHECK` runs, `tools/wsl_check.sh` (Linux) and
   `python tools/package_addon.py` + `python tools/check_package.py build/package/godot-jsbsim-dev.zip --godot <godot>`.
3. Commit, tag `vx.y.z` and push the tag. CI builds all platforms, packs `godot-jsbsim-x.y.z.zip`
   (`addons/jsbsim/` with the libraries for Windows, Linux and macOS, `COPYING.JSBSim`, `LICENSE`,
   `THIRD_PARTY_NOTICES.md` and `JSBSIM_SOURCE.txt`), checks it in a new project and creates a **draft** GitHub
   release for the tag with the zip attached and the CHANGELOG section as notes (job `release`).
4. Attach the README animation to the draft (see *Media*), read it through and publish it. The README shows the
   animation from `releases/latest/download/`, so it appears once a release is published.

## Media
Kept out of git because of their size; regenerate them for a release when the demo looks different:
- `python tools/make_media.py --godot <godot>` records the terrain demo (needs a window and the godot-geo terrain,
  ~10 minutes) and writes `build/media/godot-jsbsim-flight.webp` (README animation, ~3 MB) and
  `godot-jsbsim-flight.gif` (the same clip as a GIF, ~20 MB, for places that take only GIFs). Attach both to the
  release under these names.
- `docs/images/social_preview.jpg` (1280×640): upload it in the repository's *Settings → General → Social preview*.
- `docs/images/icon.png` (128×128, from `icon.svg`): the Asset Library icon. Editor icons of the nodes are in
  `addons/jsbsim/icons/` and ship with the addon.
- `docs/images/getting_started_*.jpg`: screenshots of the [getting-started](getting-started.md) project.

## Godot Asset Library
The Asset Library installs an asset by downloading the repository archive of one commit. The compiled libraries
are not in git, so that archive alone does not work. Options:
- a `release` branch (or a separate repository) where CI commits `addons/jsbsim/` with the libraries, and the
  Asset Library entry points to it;
- the newer Godot Asset Store, which takes an uploaded zip (the release zip as it is).

Entry text: name "godot-jsbsim", category *Scripts* (or *Misc*), licence MIT (JSBSim LGPL-2.1, noted in the
description), Godot 4.3+, the README's first paragraph as the description, `docs/images/terrain_flight.jpg` as the
preview, `docs/images/icon.png` as the icon.
