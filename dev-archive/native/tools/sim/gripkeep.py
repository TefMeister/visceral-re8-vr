"""gripkeep.py <yaw> <pitch> <roll> [down_cm=4] [fwd_cm=0] -- keep a two-handed front grip spot for the gun in hand by robot: the gun held
side-on (pointing to the view's left, level), the left controller put under the `grip` zone's middle (down_cm below it, fwd_cm
toward the muzzle) turned yaw / pitch / roll (hv numbers; 90 0 0 = pointing along the barrel), `grip keep 1` written, then LG held
so the hold shows. Prints the mod's lines. Needs keep.py and HV_HEAD. 2026-11-23."""
import json, subprocess, sys, time, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import hv
GAME = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
y, p, r = [float(x) for x in sys.argv[1:4]]; down = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0; fwd = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0
P = os.path.join(HERE, "pose_now.json"); py = sys.executable
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
subprocess.run([py, os.path.join(HERE, "keys.py"), open(os.path.join(HERE, "pid.txt")).read().strip()], capture_output=True)
setp(left=hv.room(-0.35, -0.40, 0.20) + [hv.YAW, 0], squeeze=0.0, trigger=0.0); time.sleep(0.5)
subprocess.run([py, os.path.join(HERE, "frame.py"), "grip", "yaw=90", "pitch=90", "at=0.0,0.0,0.42"], capture_output=True)
t = subprocess.run([py, os.path.join(HERE, "rv.py"), "-f", os.path.join(HERE, "q_zonehv.lua")], capture_output=True, text=True).stdout
z = {l.split()[0]: [float(x) / 100.0 for x in l.split()[1:4]] for l in t.splitlines() if len(l.split()) == 4}
if "grip" not in z: print("no grip zone on"); sys.exit(1)
g = z["grip"]; at = hv.room(g[0] - fwd / 100.0, g[1] - down / 100.0, g[2])
setp(left=at + [hv.YAW + y, p, r]); time.sleep(0.8)
m = os.path.getsize(os.path.join(GAME, "re2_framework_log.txt"))
open(os.path.join(GAME, "reframework", "data", "re_scope_cmd.txt"), "w").write("grip keep 1"); time.sleep(3.2)
with open(os.path.join(GAME, "re2_framework_log.txt"), "rb") as f: f.seek(m); new = f.read().decode("utf-8", "replace")
print("\n".join(l[l.find("grip]"):][:150] for l in new.splitlines() if "grip]" in l and "KEPT" in l))
setp(squeeze=1.0); time.sleep(1.2)
