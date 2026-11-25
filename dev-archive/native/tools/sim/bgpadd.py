"""bgpadd.py - a pretend Xbox pad that stays plugged in for a whole run (games that pause when their pad
disappears, e.g. The Darkness). No keyboard, mouse or focus.

  bgpadd.py serve [cmdfile]       keep the pad; obey lines appended to cmdfile (default: bgpad_cmd.txt beside this)
  bgpadd.py send <words...>       append one command line, e.g.:  send a   send start   send stick 0 1 2.5   send quit

Commands: a button name (a b x y start back lb rb up down left right ls rs) = a 150 ms tap;
`stick <x> <y> <secs>` holds the left stick; `rstick <x> <y> <secs>` the right; `quit` unplugs and ends.
"""
import os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
CMD = os.path.join(HERE, "bgpad_cmd.txt")

if sys.argv[1] == "send":
    with open(CMD, "a", encoding="utf-8") as f:
        f.write(" ".join(sys.argv[2:]) + "\n")
    sys.exit(0)

import vgamepad as vg
B = vg.XUSB_BUTTON
NAMES = {"a": B.XUSB_GAMEPAD_A, "b": B.XUSB_GAMEPAD_B, "x": B.XUSB_GAMEPAD_X, "y": B.XUSB_GAMEPAD_Y,
         "start": B.XUSB_GAMEPAD_START, "back": B.XUSB_GAMEPAD_BACK, "lb": B.XUSB_GAMEPAD_LEFT_SHOULDER,
         "rb": B.XUSB_GAMEPAD_RIGHT_SHOULDER, "up": B.XUSB_GAMEPAD_DPAD_UP, "down": B.XUSB_GAMEPAD_DPAD_DOWN,
         "left": B.XUSB_GAMEPAD_DPAD_LEFT, "right": B.XUSB_GAMEPAD_DPAD_RIGHT, "ls": B.XUSB_GAMEPAD_LEFT_THUMB,
         "rs": B.XUSB_GAMEPAD_RIGHT_THUMB}
cmdfile = sys.argv[2] if len(sys.argv) > 2 else CMD
open(cmdfile, "w").close()
pad = vg.VX360Gamepad(); pad.update()
print("pad plugged in", flush=True)
done = 0
while True:
    lines = open(cmdfile, encoding="utf-8").read().splitlines()
    for line in lines[done:]:
        done += 1
        w = line.split()
        if not w:
            continue
        if w[0] == "quit":
            print("quit", flush=True); del pad; sys.exit(0)
        if w[0] in ("stick", "rstick"):
            x, y, secs = float(w[1]), float(w[2]), float(w[3])
            (pad.left_joystick_float if w[0] == "stick" else pad.right_joystick_float)(x, y); pad.update(); time.sleep(secs)
            (pad.left_joystick_float if w[0] == "stick" else pad.right_joystick_float)(0.0, 0.0); pad.update()
        elif w[0] in NAMES:
            pad.press_button(NAMES[w[0]]); pad.update(); time.sleep(0.15)
            pad.release_button(NAMES[w[0]]); pad.update()
        print("%s done" % line, flush=True)
    time.sleep(0.05)
