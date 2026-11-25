"""bgwalk.py <secs> [x y] - hold the pretend pad's left stick (default straight forward) for <secs>, and print how far
Village's player moved (asked through rv.py, no focus)."""
import os, subprocess, sys, time
import vgamepad as vg

RV = os.path.expanduser(r"~\github-backups\visceral-re8-vr\dev-archive\native\tools\sim\rv.py")
# BG_PLAYER_LUA: a Lua expression for the player's GameObject in another game (RV_GAME_DIR points rv.py there)
PL = os.environ.get("BG_PLAYER_LUA", "re8vr.player")
Q = ('local p = (' + PL + '):call("get_Transform"):call("get_Position") '
     'return string.format("%.3f %.3f %.3f", p.x, p.y, p.z)')


def pos():
    out = subprocess.run([sys.executable, RV, Q], capture_output=True, text=True, timeout=20).stdout.strip()
    return [float(v) for v in out.split()]


secs = float(sys.argv[1]); x = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0; y = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
pad = vg.VX360Gamepad(); pad.update(); time.sleep(2.0)
a = pos()
pad.left_joystick_float(x, y); pad.update(); time.sleep(secs)
pad.left_joystick_float(0.0, 0.0); pad.update(); time.sleep(0.8)
b = pos()
d = sum((b[i] - a[i]) ** 2 for i in range(3)) ** 0.5
print("moved %.2f m in %.1f s  (%s -> %s)" % (d, secs, a, b))
del pad
