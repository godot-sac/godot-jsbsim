"""Links the sibling repositories the terrain demo and the DIS option of the demos need into this project:

    addons/geo   <- ../godot-geo/addons/geo     (GeoTerrain, GDScript; demo/terrain_flight.tscn)
    terrain      <- ../godot-geo/terrain         (terrain packages built by godot-geo tools/build_terrain.py)
    addons/dis   <- ../godot-dis/addons/dis     (DisNetwork, DisEntity; the demos' --dis option; build godot-dis first)

Directory junctions on Windows (no admin rights or developer mode needed), symbolic links elsewhere; all are
git-ignored. The addon, its tests and demo/flight.tscn work without them; a missing sibling is skipped.

Usage (from the repo root, any Python 3): python tools/link_siblings.py [--workspace ..]
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

LINKS = [
    ("addons/geo", "godot-geo/addons/geo"),
    ("terrain", "godot-geo/terrain"),
    ("addons/dis", "godot-dis/addons/dis"),
]


def link(target: Path, source: Path) -> None:
    if os.name == "nt":
        subprocess.run(["cmd", "/c", "mklink", "/J", str(target), str(source)], check=True,
                       stdout=subprocess.DEVNULL)
    else:
        target.symlink_to(source, target_is_directory=True)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--workspace", type=Path, default=root.parent, help="folder holding the sibling repos")
    args = parser.parse_args()
    missing = 0
    for target_rel, source_rel in LINKS:
        target = root / target_rel
        source = (args.workspace / source_rel).resolve()
        if target.exists() or target.is_symlink():
            print(f"{target_rel} already exists")
            continue
        if not source.is_dir():
            print(f"skipped {target_rel}: missing {source}; clone the sibling repository next to this one "
                  "(and build its terrain or extension)", file=sys.stderr)
            missing += 1
            continue
        link(target, source)
        print(f"linked {target_rel} -> {source}")
    print("Run once so Godot registers the classes: <godot> --headless --path . --import")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
