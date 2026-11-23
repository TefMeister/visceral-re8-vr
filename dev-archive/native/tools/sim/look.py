"""look.py <out.png> <label> [box] -- re-enter the left hand's spot (LG off, on) so the game re-reads the pose, then snap.py."""
import os, subprocess, sys, time
H = os.path.dirname(os.path.abspath(__file__)); py = sys.executable
subprocess.run([py, os.path.join(H, "keys.py"), open(os.path.join(H, "pid.txt")).read().strip()], capture_output=True)
if os.environ.get("LOOK_REGRAB", "1") == "1":
    subprocess.run([py, os.path.join(H, "hv.py"), "squeeze=0"]); time.sleep(0.6)
    subprocess.run([py, os.path.join(H, "hv.py"), "squeeze=1"]); time.sleep(1.1)
if len(sys.argv) > 3: os.environ["SNAP_BOX"] = sys.argv[3]
print(subprocess.run([py, os.path.join(H, "snap.py"), sys.argv[1], sys.argv[2]], capture_output=True, text=True).stdout.strip())
