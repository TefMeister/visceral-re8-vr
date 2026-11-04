"""Village on the OpenXR Simulator with VR Bench: launch, title A, Continue A, stick up, A (Yes), wait, A (chapter), then
take the rifle out (key 4) and hold it up with the right controller. Prints what it did."""
import os, subprocess, sys, time, ctypes
VB = os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench")
sys.path.insert(0, VB)
import vb_input as I, vb_settings as S
G = r"C:\Steam\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE"
SIM = r"D:\claude video game stuff\tools\OpenXR-Simulator\openxr_simulator.json"
def press(name, hold=0.2):
    I.write(I.Input().mode(poses="pass", buttons="set").hand(S.HAND_RIGHT, **{name: True})); time.sleep(hold)
    I.write(I.Input().mode(poses="pass", buttons="set").hand(S.HAND_RIGHT, **{name: False}))
    print(time.strftime("%H:%M:%S"), "pressed", name, flush=True)
def stick(x, y, hold=0.4):
    I.write(I.Input().mode(poses="pass", buttons="set").hand(S.HAND_LEFT, stick=(x, y))); time.sleep(hold)
    I.write(I.Input().mode(poses="pass", buttons="set").hand(S.HAND_LEFT, stick=(0, 0)))
    print(time.strftime("%H:%M:%S"), "stick", x, y, flush=True)
# 2026-11-04 22:2x: the VR Bench layer must be ON before the game starts (a close-out switches it off; without it the
# virtual buttons reach nothing and the game sits at the title screen)
subprocess.run([sys.executable, os.path.join(VB, "vrbench.py"), "start", os.path.join(G, "re8.exe")], check=False)
env = dict(os.environ, XR_RUNTIME_JSON=SIM, SteamAppId="1196590")
p = subprocess.Popen([os.path.join(G, "re8.exe")], cwd=G, env=env)
print(time.strftime("%H:%M:%S"), "launched pid", p.pid, flush=True)
time.sleep(75)
for k in range(2):
    press("a"); time.sleep(4)
stick(0, 1); time.sleep(1.5); press("a"); time.sleep(30); press("a"); time.sleep(6)
print(time.strftime("%H:%M:%S"), "boot done", flush=True)
