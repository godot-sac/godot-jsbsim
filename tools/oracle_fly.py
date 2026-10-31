"""Oracle for JSBSimProbe.fly_test: the same flight with the official JSBSim Python package (same version).

Usage: tools/.venv/Scripts/python.exe tools/oracle_fly.py <root_dir> <aircraft> <seconds>
Prints the final state as one JSON object (same keys as JSBSimProbe.fly_test).
"""

from __future__ import annotations

import json
import sys

import jsbsim

PROPS = ["position/lat-geod-deg", "position/long-gc-deg", "position/geod-alt-ft", "position/h-sl-ft",
         "velocities/vc-kts", "attitude/psi-deg", "attitude/theta-deg", "attitude/phi-deg"]


def main() -> None:
    root, aircraft, seconds = sys.argv[1], sys.argv[2], float(sys.argv[3])
    fdm = jsbsim.FGFDMExec(root)
    fdm.set_debug_level(0)
    if not fdm.load_model(aircraft):
        sys.exit(f"load_model failed: {aircraft}")
    # Keep in sync with src/jsbsim_probe.cpp.
    fdm["ic/lat-geod-deg"] = 39.95
    fdm["ic/long-gc-deg"] = 32.69
    fdm["ic/h-sl-ft"] = 5000.0
    fdm["ic/psi-true-deg"] = 0.0
    fdm["ic/vc-kts"] = 150.0
    fdm.run_ic()
    fdm.get_propulsion().init_running(-1)
    fdm["fcs/throttle-cmd-norm"] = 0.8
    fdm["fcs/mixture-cmd-norm"] = 1.0
    steps = 0
    while fdm.get_sim_time() < seconds:
        if not fdm.run():
            break
        steps += 1
    out = {"ok": True, "steps": steps, "dt": fdm.get_delta_t(), "sim_time": fdm.get_sim_time(),
           "version": jsbsim.__version__}
    out.update({p: fdm[p] for p in PROPS})
    print(json.dumps(out))


if __name__ == "__main__":
    main()
