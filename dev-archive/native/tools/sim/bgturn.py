"""bgturn.py <x> <secs> - hold the pretend pad's RIGHT stick (x -1 left .. 1 right) for <secs>: turns the camera, no focus."""
import sys, time
import vgamepad as vg
x, secs = float(sys.argv[1]), float(sys.argv[2])
pad = vg.VX360Gamepad(); pad.update(); time.sleep(2.0)
pad.right_joystick_float(x_value_float=x, y_value_float=0.0); pad.update(); time.sleep(secs)
pad.right_joystick_float(x_value_float=0.0, y_value_float=0.0); pad.update(); time.sleep(0.3)
del pad
print("turned", x, secs)
