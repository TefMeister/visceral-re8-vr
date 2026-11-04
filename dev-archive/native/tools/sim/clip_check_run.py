"""clip_check_run.py <gun> <event> [<key>] - with Village in play on the simulator: tap the quick-slot key (draw a gun), record the
fingers while the named clip plays (play.txt), take a picture 0.8 s in, stop, and run check_finger_clip.py on the take.
(2026-11-04)"""
import os, subprocess, sys, time, glob
G = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
HERE = os.path.dirname(os.path.abspath(__file__))
gun, event = sys.argv[1], sys.argv[2]
key = sys.argv[3] if len(sys.argv) > 3 else ""
T = os.environ["TEMP"]
pid = subprocess.run(["tasklist", "/FI", "IMAGENAME eq re8.exe", "/FO", "CSV"], capture_output=True, text=True).stdout.strip().splitlines()[-1].split(",")[1].strip('"')
if key:
    subprocess.run([sys.executable, os.path.join(HERE, "keys.py"), pid, key], capture_output=True); time.sleep(4)
label = f"clip_{gun}_{event}"
open(os.path.join(G, "reframework", "data", "finger_rec", "command.txt"), "w").write(f"start {label}\n"); time.sleep(1.5)
open(os.path.join(G, "reframework", "data", "visceral_re8", "clips", "play.txt"), "w").write(f"{gun} {event}\n"); time.sleep(0.8)
subprocess.run([sys.executable, os.path.join(HERE, "..", "scope_measure.py"), "shot", os.path.join(T, f"{label}.png")], capture_output=True)
time.sleep(2.5)
open(os.path.join(G, "reframework", "data", "finger_rec", "command.txt"), "w").write("stop\n"); time.sleep(1.5)
takes = sorted(glob.glob(os.path.join(G, "reframework", "data", "finger_rec", f"{label}__*.csv")), key=os.path.getmtime)
print("take:", os.path.basename(takes[-1]) if takes else "NONE")
from PIL import Image
im = Image.open(os.path.join(T, f"{label}.png")); w, h = im.size
im.crop((0, 0, w // 2, h)).resize((480, 516)).save(os.path.join(T, f"{label}_small.png"))
if takes:
    r = subprocess.run([sys.executable, os.path.join(HERE, "..", "check_finger_clip.py"), takes[-1],
                        os.path.join(G, "reframework", "data", "visceral_re8", "clips", f"{gun}_{event}.csv")], capture_output=True, text=True)
    print((r.stdout + r.stderr).strip()[-700:])
