"""walk_to.py <gameobject name> [stop_m]: steer Village's Ethan to a named object by the VR Bench sticks (turn with the right
stick, walk with the left), re-aiming every step; prints each step. Stops within stop_m (default 1.3) or after 40 steps."""
import json, os, subprocess, sys, time
sys.path.insert(0, os.path.expanduser("~/github-backups/_lanes-next-wt/plugins/lanes/tools/vrbench"))
import vb_input as I, vb_settings as S

RV = os.path.expanduser("~/github-backups/visceral-re8-vr/dev-archive/native/tools/sim/rv.py")
name = sys.argv[1]
stop_m = float(sys.argv[2]) if len(sys.argv) > 2 else 1.3
Q = ('local pt = re8vr.player:call("get_Transform"); local pp = pt:call("get_Position"); '
     'local c = sdk.get_primary_camera():call("get_WorldMatrix"):to_quat() * Vector3f.new(0,0,-1); local cy = math.atan(c.x, c.z); '
     'local sm = sdk.get_native_singleton("via.SceneManager"); local scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene"); '
     'E.wt = E.wt or {}; local g = E.wt["%s"]; if not g then local all = scene:call("findComponents(System.Type)", sdk.typeof("via.Transform")); '
     'for i = 0, all:call("get_Count") - 1 do local t = all:call("get_Item", i); local o = t:call("get_GameObject"); if o and o:call("get_Name") == "%s" then g = o; break end end; E.wt["%s"] = g end; '
     'local p = g:call("get_Transform"):call("get_Position"); local dx, dz = p.x - pp.x, p.z - pp.z; '
     'local rel = math.deg(math.atan(dx, dz) - cy); while rel > 180 do rel = rel - 360 end; while rel < -180 do rel = rel + 360 end; '
     'return string.format("%%.2f %%.2f %%.2f %%.2f", math.sqrt(dx*dx + dz*dz), rel, p.y - pp.y, pp.y)') % (name, name, name)


def ask():
    out = subprocess.run([sys.executable, RV, "--front", Q], capture_output=True, text=True).stdout.strip()
    d, rel, dy, y = (float(v) for v in out.split()[:4])
    return d, rel, dy, y


def stick(hand, x, y, sec):
    I.write(I.Input().mode(poses="pass", buttons="set").hand(hand, stick=(x, y)))
    time.sleep(sec)
    I.write(I.Input().mode(poses="pass", buttons="set").hand(hand, stick=(0.0, 0.0)))


last = None
for step in range(int(os.environ.get('STEPS', '40'))):
    d, rel, dy, y = ask()
    print(f"step {step}: {d:.2f} m away, {rel:+.0f} deg off the view, dy {dy:+.2f}", flush=True)
    if d <= stop_m:
        print("arrived"); break
    if abs(rel) > 25:
        print(f"TURN NEEDED: {rel:+.0f} deg (turn the head, then run again)"); break
    stick(S.HAND_LEFT, 0.0, 1.0, 0.8 if d > 3 else 0.35)
    time.sleep(0.2)
    if last is not None and abs(last - d) < 0.05:
        print("not getting closer: sidestep a little"); stick(S.HAND_LEFT, 1.0, 0.3, 0.5)
    last = d
