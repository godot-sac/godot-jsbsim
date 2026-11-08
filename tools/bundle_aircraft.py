"""Copy JSBSim aircraft into the distributed add-on (addons/jsbsim/data/).

Two kinds of models: copies of JSBSim's own aircraft (thirdparty/jsbsim/aircraft/, unmodified) and our own models in
aircraft/ (generated with JSBSim's AeromatiC++ from the inputs in aircraft/<name>/aeromatic.param, then tuned).

The files are copied unmodified, together with the LGPL-2.1 text (addons/jsbsim/COPYING.JSBSim). Only models that
passed the licence review are allowed: no GPL notice and no "not to be sold" note in any file, and a provenance
reviewed in JSBSim's git history (PROVENANCE below). Each bundled model gets a NOTICE.md with its origin and licence,
and the data folder a LICENSE.md: the aircraft data is not covered by godot-jsbsim's MIT licence.

Usage (from the repository root):
    tools/.venv/Scripts/python.exe tools/bundle_aircraft.py [aircraft ...]     # default: the bundled set
    tools/.venv/Scripts/python.exe tools/bundle_aircraft.py --check            # verify the bundle is up to date
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "thirdparty" / "jsbsim"
ADDON = ROOT / "addons" / "jsbsim"
DATA = ADDON / "data"

# Headers reviewed (no GPL, no "not to be sold"). Add a model here only after reading all of its files.
ALLOWED = ["J3Cub", "DHC6", "global5000", "F450", "fokker50", "dr1"]
# Our own models in aircraft/<name>/ (source of truth; the bundle is a copy without the AeromatiC++ inputs).
OWN = {
    "TUAV": {
        "title": "generic tactical UAV",
        "description": "A fictional small fixed-wing UAV (piston pusher, fixed tricycle gear, about 136 kg, 4.9 m span) "
        "with round-number inputs typical of the class, not the data of any real aircraft.",
    },
}
OWN_SOURCE = ROOT / "aircraft"
OWN_SKIPPED = {"aeromatic.param"}
BUNDLED = ["J3Cub", "TUAV"]
# Refused although their current files pass the text check.
REFUSED = {
    "pc7": "its history includes syncs with FlightGear's (GPL) data in 2007-2009 and a \"not to be sold\" note "
    "(2012) that was dropped when the model was regenerated in 2016, without a recorded reason; JSBSim's maintainers "
    "say such notes should not be removed without the author's agreement (discussion #1531)",
}
# Origin of each bundled model, from `git log --follow` in thirdparty/jsbsim. Written to <model>/NOTICE.md.
PROVENANCE = {
    "J3Cub": {
        "title": "Piper J-3 Cub",
        "author": "Erik Hofman, generated with Aeromatic 3.2.0 and tuned by hand",
        "history": [
            "2015-12-22 `bd676b7f` added by Erik Hofman to the JSBSim repository (all four files)",
            "2016-01-03 `1fe6b114` last update by the author",
            "2018-2025 maintenance by JSBSim maintainers (`784eb889`, `150805ea`, `c4558970`)",
        ],
        "notes": "No version of the files carries a licence field, a GPL notice or a \"not to be sold\" note, and "
        "no change was synced from FlightGear.",
    },
}

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


NOTICE = "NOTICE.md"
JSBSIM_VERSION = "1.3.3"
AEROMATIC_VERSION = "3.3.21"


def source_of(aircraft: str) -> Path:
    return OWN_SOURCE / aircraft if aircraft in OWN else SOURCE / "aircraft" / aircraft


def source_files(aircraft: str) -> set[Path]:
    source = source_of(aircraft)
    return {p.relative_to(source) for p in source.rglob("*") if p.is_file() and p.name not in OWN_SKIPPED}


def notice_own(aircraft: str) -> str:
    info = OWN[aircraft]
    return f"""# {aircraft}: {info['title']}

{info['description']}

Made for godot-jsbsim: generated with AeromatiC++ {AEROMATIC_VERSION} (JSBSim {JSBSIM_VERSION}, `utils/aeromatic++`) from
the inputs in godot-jsbsim's `aircraft/{aircraft}/aeromatic.param`, copied here by `tools/bundle_aircraft.py`.

**Not covered by godot-jsbsim's MIT licence.** AeromatiC++ is part of JSBSim and licensed under the GNU Lesser General
Public License 2.1, and most of these files are its templates filled in with the inputs. Like JSBSim's own aircraft, the
files are distributed under the LGPL-2.1 (`COPYING.JSBSim` in the addon).

Use it as a stand-in for a small UAV in games and demos. It is not validated against flight test data.
"""


def notice(aircraft: str) -> str:
    if aircraft in OWN:
        return notice_own(aircraft)
    info = PROVENANCE[aircraft]
    history = "\n".join(f"- {line}" for line in info["history"])
    return f"""# {aircraft}: {info['title']}

Unmodified JSBSim aircraft data, copied from JSBSim {JSBSIM_VERSION} (`aircraft/{aircraft}/`,
https://github.com/JSBSim-Team/jsbsim) by godot-jsbsim's `tools/bundle_aircraft.py`. This file is the only addition.

**Not covered by godot-jsbsim's MIT licence.** The files are part of the JSBSim distribution, which is licensed under
the GNU Lesser General Public License 2.1 (`COPYING.JSBSim` in the addon). The files themselves name no licence;
JSBSim's maintainers have not stated whether the repository licence applies to aircraft files without a header of
their own (JSBSim discussion #1531, October 2026). Treat them as LGPL-2.1 and check them yourself before a commercial
release.

Author: {info['author']}.

History (JSBSim git):
{history}

{info['notes']}

The model was made from publicly available data and is meant for educational and entertainment use; it is not
endorsed by the manufacturer (the note in the model's own `<fileheader>`).
"""


def data_licence() -> str:
    models = "\n".join(f"- `aircraft/{name}/` ({(OWN.get(name) or PROVENANCE[name])['title']}): see its `{NOTICE}`"
                       for name in BUNDLED)
    return f"""# Aircraft data licence

The files in this folder are JSBSim aircraft data, **not** part of godot-jsbsim's MIT-licensed code. They are copied
unmodified from JSBSim {JSBSIM_VERSION} or generated with JSBSim's AeromatiC++, and distributed under JSBSim's licence,
the GNU Lesser General Public License 2.1 (`../COPYING.JSBSim`), with the per-model notes below.

{models}

You can delete this folder and use your own data folder instead (`JSBSimAircraft.data_dir`); godot-jsbsim works
without it. Generated by `tools/bundle_aircraft.py`.
"""


def bundle(aircraft: str) -> None:
    if aircraft in REFUSED:
        sys.exit(f"{aircraft} is refused: {REFUSED[aircraft]}")
    if aircraft in OWN:
        _copy(aircraft)
        return
    if aircraft not in ALLOWED:
        sys.exit(f"{aircraft} is not in the reviewed list: {', '.join(ALLOWED)}")
    if aircraft not in PROVENANCE:
        sys.exit(f"{aircraft} has no PROVENANCE entry: review its git history in thirdparty/jsbsim first")
    source = SOURCE / "aircraft" / aircraft
    if not source.is_dir():
        sys.exit(f"{source} is missing: run git submodule update --init")
    problems = licence_problems(source)
    if problems:
        sys.exit("licence check failed:\n  " + "\n  ".join(problems))
    _copy(aircraft)


def _copy(aircraft: str) -> None:
    source = source_of(aircraft)
    target = DATA / "aircraft" / aircraft
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target, ignore=shutil.ignore_patterns(*OWN_SKIPPED))
    (target / NOTICE).write_text(notice(aircraft), encoding="utf-8", newline="\n")
    print(f"{aircraft}: {sum(1 for p in target.rglob('*') if p.is_file())} files -> {target.relative_to(ROOT)}")


def same_text(a: Path, b: Path) -> bool:
    """Equal apart from line endings: git may check either copy out with CRLF or LF (JSBSim stores COPYING with
    CRLF and the XML files with LF; core.autocrlf converts on Windows)."""
    return a.read_bytes().replace(b"\r\n", b"\n") == b.read_bytes().replace(b"\r\n", b"\n")


def check(names: list[str]) -> int:
    failures = []
    if not same_text(SOURCE / "COPYING", ADDON / "COPYING.JSBSim"):
        failures.append("COPYING.JSBSim differs from thirdparty/jsbsim/COPYING")
    for aircraft in names:
        source, target = source_of(aircraft), DATA / "aircraft" / aircraft
        ours = {p.relative_to(target) for p in target.rglob("*") if p.is_file()} - {Path(NOTICE)}
        theirs = source_files(aircraft)
        for name in sorted(ours ^ theirs):
            failures.append(f"{aircraft}: {name.as_posix()} differs")
        for name in sorted(ours & theirs):
            if not same_text(source / name, target / name):
                failures.append(f"{aircraft}: {name.as_posix()} differs")
        notice_path = DATA / "aircraft" / aircraft / NOTICE
        if not notice_path.is_file() or notice_path.read_text(encoding="utf-8") != notice(aircraft):
            failures.append(f"{aircraft}: {NOTICE} is missing or out of date")
    licence = DATA / "LICENSE.md"
    if not licence.is_file() or licence.read_text(encoding="utf-8") != data_licence():
        failures.append("data/LICENSE.md is missing or out of date")
    present = sorted(p.name for p in (DATA / "aircraft").iterdir() if p.is_dir())
    if present != sorted(BUNDLED):
        failures.append(f"data/aircraft holds {present}, expected {sorted(BUNDLED)}")
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
    (DATA / "LICENSE.md").write_text(data_licence(), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
