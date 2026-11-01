#!/bin/bash
# Linux check in WSL: copy the working tree, build JSBSim + the extension, run the GUT tests.
set -e
SRC=$(cd "$(dirname "$0")/.." && pwd)
DST=~/gjsb-ci
mkdir -p $DST
rsync -a --delete --exclude .git --exclude build --exclude .godot --exclude 'tools/.venv' --exclude 'addons/jsbsim/bin' \
  --exclude '*.obj' --exclude '*.lib' --exclude '*.exp' --exclude '*.pdb' --exclude '*.os' --exclude '*.o' \
  "$SRC/" $DST/
cd $DST
[ -x tools/.venv/bin/python ] || python3 -m venv tools/.venv
tools/.venv/bin/python -m pip install -q -r tools/requirements.txt
tools/.venv/bin/python tools/build_jsbsim.py --jobs 24
tools/.venv/bin/python -m SCons -j24 target=template_debug
tools/.venv/bin/python -m SCons tests 2>&1 | tail -4
ls -la addons/jsbsim/bin/linux
readelf -d addons/jsbsim/bin/linux/libgodot_jsbsim.linux.template_debug.x86_64.so | grep -E "NEEDED|RUNPATH|RPATH"
G=${GODOT:-}
if [ -z "$G" ]; then G=$(find ~ -maxdepth 3 -name 'Godot_v4.7.2-stable_linux.x86_64' | head -1); fi
echo "godot: $G"
"$G" --headless --path . --import >/dev/null 2>&1 || true
"$G" --headless --path . -s addons/gut/gut_cmdln.gd 2>&1 | grep -E "Passing|Failing|Failed|Pending|worst"
"$G" --headless --path . res://demo/flight.tscn -- --seconds 60 --time-scale 4 2>&1 | grep -E "FLIGHT_CHECK|ERROR"
