"""Installs a package made by tools/package_addon.py into a new, empty Godot project and flies the bundled J3Cub
for a few seconds there: the check that a user who only has the zip gets a working addon (libraries found, data
folder found, classes registered).

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
        # The first import of a project may exit with a crash after it is done (seen with Godot 4.7.2 and any
        # GDExtension that is new to the project); the import itself is complete, so its exit code is ignored.
        subprocess.run([args.godot, "--headless", "--path", str(project), "--import"], capture_output=True)
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
