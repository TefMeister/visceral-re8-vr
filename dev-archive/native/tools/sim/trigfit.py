"""trigfit.py <ri id> ... -- the right index finger against the gun's own Trigger joint, by numbers (2026-11-23, Tefa: "right hand
index finger on the trigger, right hand other 3 fingers gripping the handle"). For each gun: it is taken into the hand, then
q_trigfit.lua reads, in the gun's root frame (cm; +x the gun's left, +y up, +z the muzzle), the Trigger joint (its pivot: the
blade hangs below it) and the index finger's PAD (the last bone's middle, 1.2 cm past the last joint), and how closed the other
three fingers are (wrist to their last joints). "pad - trigger" should be about x 0 +-1.5 (across the gun), y -1 to -3 (down the
blade), z 0 to +1.5 (on the blade's face). A gun with no Trigger joint says so. Needs the game up with the plugin's zones script."""
import json, os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); py = sys.executable
GAME = os.environ.get("RV_GAME_DIR", r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE")
STATE = os.path.join(GAME, "reframework", "data", "visceral_re8", "zones_state.json")
def gun_now():
    try: return json.load(open(STATE)).get("gun", 0)
    except Exception: return 0
for g in sys.argv[1:]:
    num = int(g[2:])
    if gun_now() != num:
        open(os.path.join(GAME, "reframework", "data", "finger_rec", "command.txt"), "w").write("equip " + g)
        for _ in range(24):
            time.sleep(0.5)
            if gun_now() == num: break
        time.sleep(2.5)
    if gun_now() != num: print("%s NOT IN HAND" % g); continue
    out = subprocess.run([py, os.path.join(HERE, "rv.py"), "-f", os.path.join(HERE, "q_trigfit.lua")], capture_output=True, text=True).stdout.strip()
    print("%s  %s" % (g, out))
