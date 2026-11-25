"""bgpad.py <button> [<button> ...] - press buttons on a pretend Xbox pad (ViGEmBus), no keyboard, mouse or focus.
Buttons: a b x y start back lb rb up down left right ls rs. Plugs the pad in, waits for the game to see it, presses
each (0.15 s held, 0.8 s apart), unplugs."""
import sys, time
import vgamepad as vg

B = vg.XUSB_BUTTON
NAMES = {"a": B.XUSB_GAMEPAD_A, "b": B.XUSB_GAMEPAD_B, "x": B.XUSB_GAMEPAD_X, "y": B.XUSB_GAMEPAD_Y,
         "start": B.XUSB_GAMEPAD_START, "back": B.XUSB_GAMEPAD_BACK, "lb": B.XUSB_GAMEPAD_LEFT_SHOULDER,
         "rb": B.XUSB_GAMEPAD_RIGHT_SHOULDER, "up": B.XUSB_GAMEPAD_DPAD_UP, "down": B.XUSB_GAMEPAD_DPAD_DOWN,
         "left": B.XUSB_GAMEPAD_DPAD_LEFT, "right": B.XUSB_GAMEPAD_DPAD_RIGHT, "ls": B.XUSB_GAMEPAD_LEFT_THUMB,
         "rs": B.XUSB_GAMEPAD_RIGHT_THUMB}
pad = vg.VX360Gamepad()
pad.update(); time.sleep(2.0)
for name in sys.argv[1:]:
    pad.press_button(NAMES[name]); pad.update(); time.sleep(0.15)
    pad.release_button(NAMES[name]); pad.update(); time.sleep(0.8)
    print("pressed", name)
time.sleep(0.5)
del pad
