"""accuracy_test.py -- a handgun's accuracy by hold and movement (src/accuracy.h), on the OpenXR Simulator through VR Bench
(2026-11-11). After drive.sh, with the LEMI in hand (keys.py <pid> 2). Fires three shots in each case and prints the plugin's
"accuracy:" lines: one hand standing still; both hands (LG pressed on the seated magazine); a spare in the hand docked on the
magazine; then one hand with the left stick pushed forward (walking) and with the stick clicked as well (running, if the click
is the game's sprint). The percentages and the angles are in the log lines; the speeds too."""
import os, re, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import walk
import twomag_test as t
I, S = walk.I, walk.S

WANT = re.compile(r"accuracy:|twomag:|the left hand on the seated magazine")
pos = [os.path.getsize(t.LOG)]


def news(title):
    with open(t.LOG, "rb") as f:
        f.seek(pos[0]); data = f.read(); pos[0] += len(data)
    print(f"--- {title}", flush=True)
    for line in data.decode("utf-8", "replace").splitlines():
        if WANT.search(line): print("  " + line.split("] ", 2)[-1][:230], flush=True)


def put(left, squeeze=0.0, rtrigger=0.0, stick=None, click=False):
    t.front()
    inp = I.Input().mode(poses="set", buttons="set")
    r = I.pose_from_ypr(t.GUN[0:3], t.GUN[3], t.GUN[4]); inp.hand(S.HAND_RIGHT, grip=r, aim=r, trigger=rtrigger)
    l = I.pose_from_ypr(left[0:3], left[3], left[4])
    inp.hand(S.HAND_LEFT, grip=l, aim=l, squeeze=squeeze, stick=stick if stick else (0.0, 0.0), stick_click=click)
    I.write(inp)


def shots(n, left, squeeze=0.0, stick=None, click=False):
    for k in range(n):
        put(left, squeeze, 1.0, stick, click); time.sleep(0.15)
        put(left, squeeze, 0.0, stick, click); time.sleep(0.6)


def main():
    t.pose(t.AWAY, 0); time.sleep(1.5); news("start (the LEMI in hand)")
    shots(3, t.AWAY); time.sleep(0.5); news("one hand, standing still: 75%?")
    print(t.w("mag")); well = list(walk.load()["left"])
    put(t.AWAY); time.sleep(0.5)
    put(well, 0.0); time.sleep(0.4); put(well, 1.0); time.sleep(1.0)
    shots(3, well, 1.0); time.sleep(0.5); news("LG pressed on the seated magazine, standing still: both hands, 100%?")
    put(t.AWAY); time.sleep(0.8)
    put(t.POUCH); time.sleep(0.8); put(t.POUCH, 1.0); time.sleep(1.5)
    put(well, 1.0); time.sleep(1.5)
    shots(3, well, 1.0); time.sleep(0.5); news("a spare in the hand, docked on the magazine, standing still: 85%?")
    put(t.AWAY); time.sleep(1.0)
    put(t.AWAY, stick=(0.0, 1.0)); time.sleep(1.2)
    shots(3, t.AWAY, stick=(0.0, 1.0)); news("one hand, the stick forward: walking, 50%?")
    put(t.AWAY, stick=(0.0, 1.0), click=True); time.sleep(0.3); put(t.AWAY, stick=(0.0, 1.0)); time.sleep(1.2)
    shots(3, t.AWAY, stick=(0.0, 1.0)); news("one hand, the stick forward after a stick click: running, 30%?")
    put(t.AWAY); time.sleep(1.0); news("stopped")


if __name__ == "__main__":
    main()
