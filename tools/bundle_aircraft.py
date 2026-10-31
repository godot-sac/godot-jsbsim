"""Copy JSBSim aircraft from thirdparty/jsbsim into the distributed add-on (addons/jsbsim/data/).

The files are copied unmodified, together with the LGPL-2.1 text (addons/jsbsim/COPYING.JSBSim). Only models that
passed the licence review in PLAN.md (decision 8) are allowed: no GPL notice and no "not to be sold" note.

Usage (from the repository root):
    tools/.venv/Scripts/python.exe tools/bundle_aircraft.py [aircraft ...]     # default: the bundled set
    tools/.venv/Scripts/python.exe tools/bundle_aircraft.py --check            # verify the bundle is up to date
"""

from __future__ import annotations

import argparse
import filecmp
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "thirdparty" / "jsbsim"
ADDON = ROOT / "addons" / "jsbsim"
DATA = ADDON / "data"

# Reviewed and allowed (PLAN.md decision 8). Add a model here only after reading all of its files.
ALLOWED = ["pc7", "J3Cub", "DHC6", "global5000", "F450", "fokker50", "dr1"]
BUNDLED = ["pc7", "J3Cub"]

FORBIDDEN = re.compile(r"general public license|\bgpl\b|not\s+to\s+be\s+sold", re.IGNORECASE)
LESSER = re.compile(r"lesser general public license|\blgpl\b", re.IGNORECASE)


def licence_problems(folder: Path) -> list[str]:
    """Files that mention the GPL (but not only the LGPL) or a "not to be sold" note."""
    problems = []
    for path in sorted(folder.rglob("*")):
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in FORBIDDEN.finditer(text):
            line = text[text.rfind("\n", 0, match.start()) + 1:text.find("\n", match.end())]
            if not LESSER.search(line):
                problems.append(f"{path.relative_to(SOURCE)}: {line.strip()}")
    return problems


def bundle(aircraft: str) -> None:
    if aircraft not in ALLOWED:
        sys.exit(f"{aircraft} is not in the reviewed list (PLAN.md decision 8): {', '.join(ALLOWED)}")
    source = SOURCE / "aircraft" / aircraft
    if not source.is_dir():
        sys.exit(f"{source} is missing: run git submodule update --init")
    problems = licence_problems(source)
    if problems:
        sys.exit("licence check failed:\n  " + "\n  ".join(problems))
    target = DATA / "aircraft" / aircraft
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target)
    print(f"{aircraft}: {sum(1 for p in target.rglob('*') if p.is_file())} files -> {target.relative_to(ROOT)}")


def check(names: list[str]) -> int:
    failures = []
    if not filecmp.cmp(SOURCE / "COPYING", ADDON / "COPYING.JSBSim", shallow=False):
        failures.append("COPYING.JSBSim differs from thirdparty/jsbsim/COPYING")
    for aircraft in names:
        comparison = filecmp.dircmp(SOURCE / "aircraft" / aircraft, DATA / "aircraft" / aircraft)
        pending = [comparison]
        while pending:
            current = pending.pop()
            for name in current.left_only + current.right_only + current.diff_files:
                failures.append(f"{aircraft}: {name} differs")
            pending.extend(current.subdirs.values())
    for failure in failures:
        print(failure)
    print("bundle OK" if not failures else f"{len(failures)} problem(s)")
    return 1 if failures else 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("aircraft", nargs="*", default=BUNDLED)
    parser.add_argument("--check", action="store_true", help="compare the bundle with thirdparty/jsbsim")
    args = parser.parse_args()
    if args.check:
        sys.exit(check(args.aircraft))
    DATA.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE / "COPYING", ADDON / "COPYING.JSBSim")
    for aircraft in args.aircraft:
        bundle(aircraft)


if __name__ == "__main__":
    main()
