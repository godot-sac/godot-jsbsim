"""Installs a package made by tools/package_addon.py into a new, empty Godot project and flies the bundled J3Cub
for a few seconds there: the check that a user who only has the zip gets a working addon (libraries found, data
folder found, classes registered), with its licence notes and a first import without errors or warnings.

Usage (from the repo root, any Python 3):
    python tools/check_package.py build/package/godot-jsbsim-dev.zip --godot <path to the Godot executable>
Prints a PACKAGE_CHECK line; exit code 1 on failure.
"""
import argparse
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

PROJECT = """config_version=5

[application]
config/name="godot-jsbsim package check"
"""

SMOKE = """extends SceneTree

func _initialize() -> void:
	var ok := ClassDB.class_exists("JSBSimAircraft")
	var aircraft: Node3D
	if ok:
		print("JSBSim ", ClassDB.class_call_static("JSBSimFDM", "get_jsbsim_version"))
		aircraft = ClassDB.instantiate("JSBSimAircraft")
		aircraft.set("paused", true)
		root.add_child(aircraft)
		ok = aircraft.call("start")  # _ready() runs only after _initialize()
		if not ok:
			print("start failed: ", aircraft.call("get_fdm").call("get_last_error"))
	if ok:
		for i in 300:
			aircraft.call("advance", 1.0 / 60.0)
		var fdm: RefCounted = aircraft.call("get_fdm")
		ok = absf(fdm.call("get_sim_time") - 5.0) < 0.01 and not aircraft.call("is_crashed")
		print("data: ", fdm.call("get_data_path"), "  position: ", aircraft.position)
	ok = ok and load("res://addons/jsbsim/jsbsim_input.gd") != null
	print("PACKAGE_CHECK ", "ok" if ok else "FAILED")
	quit(0 if ok else 1)
"""


# Licence and source notes the zip must carry (the LGPL and the MIT licences of the code inside JSBSim ask for them).
NOTICES = ["LICENSE", "THIRD_PARTY_NOTICES.md", "COPYING.JSBSim", "COPYING.Expat", "COPYING.GeographicLib",
           "JSBSIM_SOURCE.txt", "data/LICENSE.md", "data/aircraft/J3Cub/NOTICE.md"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("package", type=Path)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="gjsb-package-") as tmp:
        project = Path(tmp)
        (project / "project.godot").write_text(PROJECT, encoding="utf-8")
        (project / "smoke.gd").write_text(SMOKE, encoding="utf-8")
        with zipfile.ZipFile(args.package) as archive:
            archive.extractall(project)
        missing = [n for n in NOTICES if not (project / "addons" / "jsbsim" / n).is_file()]
        if missing:
            print("PACKAGE_CHECK FAILED (missing in the zip: %s)" % ", ".join(missing))
            return 1
        # The first import discovers the extension mid-session; Godot 4.7 crashes at the end of it unless
        # src/editor_first_load_guard.cpp works around godotengine/godot#111048, so its exit code is checked.
        first = subprocess.run([args.godot, "--headless", "--path", str(project), "--import"],
                               capture_output=True, text=True, encoding="utf-8", errors="replace")
        problems = [line for line in (first.stdout + first.stderr).splitlines()
                    if line.startswith(("ERROR", "WARNING", "SCRIPT ERROR"))]
        print(f"first import: exit {first.returncode}, {len(problems)} errors or warnings")
        if first.returncode != 0 or problems:
            print("
".join(problems[:20]) or first.stderr.strip()[-2000:], file=sys.stderr)
            print("PACKAGE_CHECK FAILED (the first import did not exit cleanly)")
            return 1
        run = subprocess.run([args.godot, "--headless", "--path", str(project), "-s", "res://smoke.gd"],
                             capture_output=True, text=True, encoding="utf-8", errors="replace")
        print(run.stdout.strip())
        if run.returncode != 0:
            print(run.stderr.strip(), file=sys.stderr)
        if "PACKAGE_CHECK ok" not in run.stdout:
            if "PACKAGE_CHECK" not in run.stdout:
                print("PACKAGE_CHECK FAILED (the script did not run)")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
