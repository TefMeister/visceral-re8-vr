"""dpad.py <x> <y> [hold_s] [shot]: thumb on the LEFT thumb rest + the RIGHT stick at (x, y), held; 'shot' = stay held (screenshot)"""
import sys, os, json, time
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_settings as S
x, y = float(sys.argv[1]), float(sys.argv[2]); hold = float(sys.argv[3]) if len(sys.argv) > 3 else 0.6
def write(d):
    tmp = S.INPUT_FILE + ".tmp"; open(tmp, "w").write(json.dumps(d)); os.replace(tmp, S.INPUT_FILE)
write({"v": 1, "mode": {"poses": "pass", "buttons": "set"}, "vr": {"left": {"thumbrest": True}, "right": {"stick": [x, y]}}})
time.sleep(hold)
if "shot" not in sys.argv:
    write({"v": 1, "mode": {"poses": "pass", "buttons": "set"}, "vr": {}}); print("released")
