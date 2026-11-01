"""stroke.py <metres> [steps] [hold_s]: move the left controller back along the right controller's forward and home again"""
import sys, os, json, math, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import walk
p = walk.load(); dist = float(sys.argv[1]); steps = int(sys.argv[2]) if len(sys.argv) > 2 else 10; hold = float(sys.argv[3]) if len(sys.argv) > 3 else 0.3
yaw, pitch = math.radians(p["right"][3]), math.radians(p["right"][4])
fwd = (-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
home = list(p["left"])
def at(k):
    q = dict(p); q["left"] = [home[0] - fwd[0] * dist * k, home[1] - fwd[1] * dist * k, home[2] - fwd[2] * dist * k] + home[3:5]; walk.put(q)
for i in range(1, steps + 1): at(i / steps); time.sleep(0.04)
time.sleep(hold)
for i in range(steps - 1, -1, -1): at(i / steps); time.sleep(0.04)
print("stroke done", dist)
