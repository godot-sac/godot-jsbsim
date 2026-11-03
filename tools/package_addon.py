"""Packs addons/jsbsim into a zip for users (the layout the Godot Asset Library expects: addons/jsbsim/ at the root).

Checks that every requested platform has the extension (debug and release) and the JSBSim library listed in
jsbsim.gdextension, checks the bundled aircraft (tools/bundle_aircraft.py --check), leaves out linker files
(.lib, .exp, .pdb) and editor import files, and adds LICENSE, THIRD_PARTY_NOTICES.md, the licences of the code
inside the JSBSim library (COPYING.Expat, COPYING.GeographicLib) and JSBSIM_SOURCE.txt (the
JSBSim version and where its source is, as the LGPL asks).

Usage (from the repo root, any Python 3):
    python tools/package_addon.py [--version 0.1.0] [--platforms windows,linux,macos] [--out build/package]
Without --platforms it packs the platforms that are built and says which are missing.
"""
import argparse
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "addons" / "jsbsim"
JSBSIM = ROOT / "thirdparty" / "jsbsim"
PLATFORMS = ["windows", "linux", "macos"]
SKIPPED_SUFFIXES = {".lib", ".exp", ".pdb", ".ilk", ".import"}
JSBSIM_URL = "https://github.com/JSBSim-Team/jsbsim"


def git(*args: str) -> str:
    try:
        return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def required_files(platform: str) -> list[str]:
    """Binary files jsbsim.gdextension names for one platform (paths relative to the addon)."""
    text = (ADDON / "jsbsim.gdextension").read_text(encoding="utf-8")
    paths = re.findall(r'^%s\.[^=]*=\s*(?:\{\s*)?"res://addons/jsbsim/([^"]+)"' % platform, text, re.M)
    return sorted(set(paths))


def jsbsim_tag() -> str:
    """The JSBSim release tag; CI's shallow submodule checkout has no tags, so fall back to its CMake version."""
    tag = git("-C", "thirdparty/jsbsim", "describe", "--tags", "--exact-match")
    if tag != "unknown":
        return tag
    cmake = (ROOT / "thirdparty" / "jsbsim" / "CMakeLists.txt").read_text(encoding="utf-8")
    parts = [re.search(r'set\(PROJECT_VERSION_%s "(\d+)"\)' % p, cmake) for p in ("MAJOR", "MINOR", "PATCH")]
    return "v" + ".".join(m.group(1) for m in parts) if all(parts) else "unknown"


def source_note(version: str) -> str:
    tag = jsbsim_tag()
    commit = git("rev-parse", "HEAD:thirdparty/jsbsim")
    return f"""JSBSim in this addon
====================

The JSBSim flight dynamics library is licensed under the GNU Lesser General Public License 2.1 (COPYING.JSBSim).
godot-jsbsim uses it unmodified, built as a separate shared library that the extension loads dynamically:

    bin/windows/JSBSim.dll, bin/linux/libJSBSim.so.1, bin/macos/libJSBSim.1.dylib

JSBSim version: {tag} (commit {commit})
JSBSim source:  {JSBSIM_URL}/tree/{tag}
Built with tools/build_jsbsim.py of godot-jsbsim {version} (commit {git("rev-parse", "HEAD")}).

You may replace the JSBSim library with your own build of a compatible JSBSim version: build JSBSim as a shared
library (godot-jsbsim's tools/build_jsbsim.py, or JSBSim's CMake with -DBUILD_SHARED_LIBS=ON) with the same compiler
family and overwrite the file above. When you ship a game, keep this library a separate file and include
COPYING.JSBSim and this note. See docs/licensing.md in the godot-jsbsim repository.
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", default="dev")
    parser.add_argument("--platforms", default="", help="comma-separated; all of them must be built")
    parser.add_argument("--out", type=Path, default=ROOT / "build" / "package")
    args = parser.parse_args()

    if args.platforms:
        platforms = [p.strip() for p in args.platforms.split(",") if p.strip()]
        unknown = set(platforms) - set(PLATFORMS)
        if unknown:
            print(f"unknown platforms: {', '.join(sorted(unknown))}", file=sys.stderr)
            return 1
    else:
        platforms = [p for p in PLATFORMS if (ADDON / "bin" / p).is_dir()]
    if not platforms:
        print("no platform is built (addons/jsbsim/bin/<platform>/); see docs/building.md", file=sys.stderr)
        return 1

    released = re.fullmatch(r"\d+\.\d+\.\d+", args.version)
    if released and f"## [{args.version}]" not in (ROOT / "CHANGELOG.md").read_text(encoding="utf-8"):
        print(f"CHANGELOG.md has no [{args.version}] section", file=sys.stderr)
        return 1

    missing = [f for p in platforms for f in required_files(p) if not (ADDON / f).is_file()]
    if missing:
        print("missing files:\n  " + "\n  ".join(missing), file=sys.stderr)
        return 1
    check = subprocess.run([sys.executable, str(ROOT / "tools" / "bundle_aircraft.py"), "--check"], cwd=ROOT)
    if check.returncode != 0:
        print("the bundled aircraft do not match the reviewed list", file=sys.stderr)
        return 1

    files: list[tuple[Path, str]] = []
    for path in sorted(ADDON.rglob("*")):
        rel = path.relative_to(ADDON)
        if path.is_dir() or path.suffix in SKIPPED_SUFFIXES:
            continue
        if rel.parts[0] == "bin" and (len(rel.parts) < 3 or rel.parts[1] not in platforms):
            continue
        files.append((path, "addons/jsbsim/" + rel.as_posix()))
    files.append((ROOT / "LICENSE", "addons/jsbsim/LICENSE"))
    files.append((ROOT / "THIRD_PARTY_NOTICES.md", "addons/jsbsim/THIRD_PARTY_NOTICES.md"))
    # Code compiled into the JSBSim library under its own (MIT) licences, whose notices must travel with it.
    files.append((JSBSIM / "src" / "simgear" / "xml" / "COPYING", "addons/jsbsim/COPYING.Expat"))
    files.append((JSBSIM / "src" / "GeographicLib" / "LICENSE.txt", "addons/jsbsim/COPYING.GeographicLib"))

    args.out.mkdir(parents=True, exist_ok=True)
    target = args.out / f"godot-jsbsim-{args.version}.zip"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path, name in files:
            archive.write(path, name)
        archive.writestr("addons/jsbsim/JSBSIM_SOURCE.txt", source_note(args.version))
    absent = [p for p in PLATFORMS if p not in platforms]
    print(f"{target.relative_to(ROOT) if target.is_relative_to(ROOT) else target}: {len(files) + 1} files, "
          f"{target.stat().st_size / 1e6:.1f} MB, platforms {', '.join(platforms)}"
          + (f" (not included: {', '.join(absent)})" if absent else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
