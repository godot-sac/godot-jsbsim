"""Prints the Entity State PDUs on a DIS multicast group, decoded with Open-DIS Python (independent of godot-dis):
geodetic position, local heading and pitch, ground and vertical speed, acceleration and body rates per PDU, then
how far dead reckoning (DRM RVW) from each PDU lands from the next one. A command-line stand-in for Wireshark.

Usage (from the repo root): tools/.venv/Scripts/python tools/dis_capture.py [--port 3000] [--timeout 60]
then run a demo with --dis (and the same --port). Stops after --timeout seconds.
"""
import argparse
import math
import socket
import struct
import time

import numpy as np
import pymap3d
from opendis.PduFactory import createPdu

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=3000)
parser.add_argument("--group", default="239.1.2.3")
parser.add_argument("--timeout", type=float, default=60.0)
parser.add_argument("--ready", default="", help="file to create once listening (for scripts)")
args = parser.parse_args()

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("", args.port))
mreq = struct.pack("4s4s", socket.inet_aton(args.group), socket.inet_aton("0.0.0.0"))
sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
sock.settimeout(0.2)
if args.ready:
    open(args.ready, "w").write("ready\n")

records = []
start = time.monotonic()
while time.monotonic() - start < args.timeout:
    try:
        data, sender = sock.recvfrom(65536)
    except socket.timeout:
        continue
    t = time.monotonic() - start
    pdu = createPdu(data)
    if type(pdu).__name__ != "EntityStatePdu":
        print(f"{t:6.2f} {type(pdu).__name__}")
        continue
    loc = np.array([pdu.entityLocation.x, pdu.entityLocation.y, pdu.entityLocation.z])
    lat, lon, h = pymap3d.ecef2geodetic(*loc)
    v = np.array([pdu.entityLinearVelocity.x, pdu.entityLinearVelocity.y, pdu.entityLinearVelocity.z])
    e, n, u = pymap3d.ecef2enuv(*v, lat, lon)
    psi, theta, phi = pdu.entityOrientation.psi, pdu.entityOrientation.theta, pdu.entityOrientation.phi
    # Body x axis in ECEF from the DIS Z-Y-X Euler angles, then in local ENU.
    fwd = np.array([math.cos(theta) * math.cos(psi), math.cos(theta) * math.sin(psi), -math.sin(theta)])
    fe, fn, fu = pymap3d.ecef2enuv(*fwd, lat, lon)
    heading = math.degrees(math.atan2(fe, fn)) % 360
    pitch = math.degrees(math.asin(max(-1, min(1, fu))))
    acc = np.array([pdu.deadReckoningParameters.entityLinearAcceleration.x,
                    pdu.deadReckoningParameters.entityLinearAcceleration.y,
                    pdu.deadReckoningParameters.entityLinearAcceleration.z])
    w = pdu.deadReckoningParameters.entityAngularVelocity
    e_id = pdu.entityID
    t_ = pdu.entityType
    marking = bytes(c & 0xFF for c in pdu.marking.characters).rstrip(b"\0").decode("latin-1")
    print(f"{t:6.2f} {e_id.simulationAddress.site}:{e_id.simulationAddress.application}:{e_id.entityNumber} "
          f"{marking} type={t_.entityKind}:{t_.domain}:{t_.country}:{t_.category}:{t_.subcategory}:{t_.specific} "
          f"force={pdu.forceId} dr={pdu.deadReckoningParameters.deadReckoningAlgorithm} app=0x{pdu.entityAppearance:08x} "
          f"lat={lat:.6f} lon={lon:.6f} h={h:.1f} hdg={heading:.1f} pitch={pitch:.1f} "
          f"gs={math.hypot(e, n):.1f} m/s vs={u:.2f} m/s |a|={np.linalg.norm(acc):.2f} w=({w.x:.3f},{w.y:.3f},{w.z:.3f})")
    records.append((t, loc, v, acc))

# DR check: from each PDU, extrapolate to the next one (RVW: p + v dt + a dt²/2) and report the error.
errors = []
for (t0, p0, v0, a0), (t1, p1, _, _) in zip(records, records[1:]):
    dt = t1 - t0
    errors.append(np.linalg.norm(p0 + v0 * dt + 0.5 * a0 * dt * dt - p1))
if errors:
    print(f"{len(records)} PDUs; DR error at the next PDU: median {np.median(errors):.2f} m, max {max(errors):.2f} m")
else:
    print(f"{len(records)} PDUs")
