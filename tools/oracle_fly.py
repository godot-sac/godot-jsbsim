"""Oracle for JSBSimFDM: runs a scenario file with the official JSBSim Python package (same version).

Usage: tools/.venv/Scripts/python.exe tools/oracle_fly.py <scenario.json> [<data_dir>]
The scenario format is described in tests/golden/pc7_scenario.json; tests/unit/test_oracle.gd runs the same file
with JSBSimFDM. Prints one JSON object: {"ok", "steps", "sim_time", "trim_ok", "samples": [{"step", <property>...}]}.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import jsbsim

ROOT = Path(__file__).resolve().parent.parent
FT_PER_M = 1.0 / 0.3048


def set_geodetic_height(fdm: jsbsim.FGFDMExec, height_m: float) -> None:
    # Same iteration as JSBSimFDM::set_initial_position (src/fdm/jsbsim_fdm.cpp).
    target = height_m * FT_PER_M
    asl = target
    for _ in range(10):
        fdm["ic/h-sl-ft"] = asl
        error = target - fdm["ic/geod-alt-ft"]
        if abs(error) < 1e-9:
            break
        asl += error


def run(scenario: dict, data_dir: Path) -> dict:
    fdm = jsbsim.FGFDMExec(str(data_dir))
    fdm.set_debug_level(0)
    if not fdm.load_model(scenario["aircraft"]):
        sys.exit(f"load_model failed: {scenario['aircraft']}")
    # Same order as tests/unit/test_oracle.gd.
    fdm["ic/lat-geod-deg"] = scenario["latitude"]
    fdm["ic/long-gc-deg"] = scenario["longitude"]
    set_geodetic_height(fdm, scenario["height_m"])
    fdm["ic/psi-true-deg"] = scenario["heading_deg"]
    fdm["ic/theta-deg"] = scenario["pitch_deg"]
    fdm["ic/phi-deg"] = scenario["roll_deg"]
    fdm["ic/vc-kts"] = scenario["vc_kts"]
    fdm.run_ic()
    fdm.get_propulsion().init_running(-1)
    trim_ok = True
    if scenario.get("trim_mode", -1) >= 0:
        try:
            fdm["simulation/do_simple_trim"] = scenario["trim_mode"]
        except jsbsim.TrimFailureError:
            trim_ok = False

    inputs = {entry["step"]: entry for entry in scenario.get("inputs", [])}
    samples = []

    def sample(step: int) -> None:
        samples.append({"step": step, **{p: fdm[p] for p in scenario["properties"]}})

    step = 0
    sample(0)
    while step < scenario["steps"]:
        entry = inputs.get(step)
        if entry:
            for name, value in entry.get("set", {}).items():
                fdm[name] = value
            for name, value in entry.get("add", {}).items():
                fdm[name] = fdm[name] + value
        if not fdm.run():
            break
        step += 1
        if step % scenario["sample_every"] == 0:
            sample(step)
    return {"ok": True, "steps": step, "sim_time": fdm.get_sim_time(), "trim_ok": trim_ok,
            "version": jsbsim.__version__, "samples": samples}


def main() -> None:
    scenario_path = Path(sys.argv[1])
    scenario = json.loads(scenario_path.read_text(encoding="utf-8"))
    data_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / scenario["data_dir"]
    print(json.dumps(run(scenario, data_dir)))


if __name__ == "__main__":
    main()
