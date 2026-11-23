"""rcopy.py <from ri id> ["<spot>"] -- send one gun's kept RIGHT-hand pose (fingers and thumb) through the Hand Poser window onto the
pose the window is on now (the gun in hand): a start for a gun whose right hand was never posed. 2026-11-23."""
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.environ.get("RV_GAME_DIR", r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE")
name = sys.argv[1] + "_Inventory" + ((" @ " + sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else "")
d = json.load(open(os.path.join(GAME, "reframework", "data", "hand_poser", "guns", name + ".json")))["joints"]
args = ["%s=%.1f,%.1f,%.1f" % (k, *v) for k, v in d.items() if k.startswith("R_") and k != "R_Hand" and isinstance(v, list)]
print(subprocess.run([sys.executable, os.path.join(HERE, "pose.py")] + args, capture_output=True, text=True).stdout.strip())
