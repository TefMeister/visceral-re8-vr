"""drumtest.py -- RE3's MGL drum by robot (2026-11-23, Tefa: "push down and to the right to close, left and up to open, yes the grip").
The MGL in hand, the left controller on the drum (re_go.py _02) first. LG + LT, the hand round the hinge up and to the gun's left
(the drum's own arc: 9.6 cm under the hinge, 100 degrees) until it clicks open; let go (it must stay open); then LG + LT at the
FRONT GRIP (the drum's shut place) and the hand down and to the right back along the arc until it clicks shut. Prints the left
stage and the wrist-to-drum distance along the way; read the mod's `cylinder:` lines after. Needs keep.py, HV_HEAD, RV_GAME_DIR."""
import json, math, os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); os.chdir(HERE)
P = "pose_now.json"; py = sys.executable
def setp(**k):
    q = json.load(open(P)); q.update(k); json.dump(q, open(P, "w"))
def rv(c): return subprocess.run([py, "rv.py", c], capture_output=True, text=True).stdout.strip()
GUN = ("local pl=sdk.get_managed_singleton(sdk.game_namespace('PlayerManager')):call('get_CurrentPlayer') "
       "local eq=pl:call('getComponent(System.Type)', sdk.typeof(sdk.game_namespace('survivor.Equipment'))) "
       "local g=eq:get_field('<EquipWeapon>k__BackingField'):call('get_GameObject'):call('get_Transform') ")
ax = rv(GUN + "local r=g:call('get_Rotation') local x=r*Vector3f.new(1,0,0) local y=r*Vector3f.new(0,1,0) "
        "return string.format('%.4f %.4f %.4f %.4f %.4f %.4f',x.x,x.y,x.z,y.x,y.y,y.z)").split()[-6:]
Xw = [float(a) for a in ax[:3]]; Yw = [float(a) for a in ax[3:]]
# the robot's room is turned against the game's world: move the controller 6 cm along room x and room z and see where the drawn
# wrist goes in the world, then turn the gun's world axes into room axes (a turn about up only)
WR = "local tf=sdk.get_managed_singleton(sdk.game_namespace('PlayerManager')):call('get_CurrentPlayer'):call('get_Transform') " \
     "local p=tf:call('getJointByName','l_arm_wrist'):call('get_Position') return string.format('%.4f %.4f %.4f',p.x,p.y,p.z)"
def wrist(): return [float(a) for a in rv(WR).split()[-3:]]
s0 = list(json.load(open(P))["left"]); w0 = wrist()
setp(left=[s0[0] + 0.06, s0[1], s0[2]] + s0[3:]); time.sleep(0.6); wx = wrist()
setp(left=[s0[0], s0[1], s0[2] + 0.06] + s0[3:]); time.sleep(0.6); wz = wrist()
setp(left=s0); time.sleep(0.6)
# world (x, z) = M * room (x, z): M's columns are where room +x and room +z went (per metre); room = M^-1 * world
a, c_ = (wx[0] - w0[0]) / 0.06, (wx[2] - w0[2]) / 0.06
b, d = (wz[0] - w0[0]) / 0.06, (wz[2] - w0[2]) / 0.06
det = a * d - b * c_
def to_room(v): return [(d * v[0] - b * v[2]) / det, v[1], (-c_ * v[0] + a * v[2]) / det]
X = to_room(Xw); Y = to_room(Yw)
print("room x -> world (%.2f, %.2f), room z -> world (%.2f, %.2f)" % (a, c_, b, d))
def st(): return rv("local b=_G.visceral_bridge return b and tostring(b.r(649)) or '?'")
def gap(): return rv(GUN + "local tf=pl:call('get_Transform') local d=(g:call('getJointByName','_02'):call('get_Position')-"
                     "tf:call('getJointByName','l_arm_wrist'):call('get_Position')):length() return string.format('%.1f',d*100)")
s = list(json.load(open(P))["left"])
R = 0.096   # the drum's distance under its hinge (gun frame: hinge y 14.7, drum y 5.1)
def at(deg):   # the controller moved as the drum moves: round the hinge, left (+x) and up (+y) by the angle
    a = math.radians(deg); dx, dy = R * math.sin(a), R * (1 - math.cos(a))
    setp(left=[s[k] + X[k] * dx + Y[k] * dy for k in range(3)] + s[3:]); time.sleep(0.12)
setp(squeeze=1.0); time.sleep(0.5); setp(trigger=1.0); time.sleep(0.7)
for d in range(0, 151, 5):
    at(d)
    if d in (30, 60, 110, 150): print("open: hand %3d deg round the hinge: stage %s, wrist to drum %s cm" % (d, st(), gap()))
setp(trigger=0.0); time.sleep(0.3); setp(squeeze=0.0); time.sleep(0.8)
print("let go: wrist to drum %s cm" % gap())
at(0); time.sleep(0.8)   # the hand back at the drum's SHUT place: the front grip, the drum now 15 cm away
setp(squeeze=1.0); time.sleep(0.5); setp(trigger=1.0); time.sleep(0.7)
# from the grip the hand starts at the shut angle (0) with the drum at 100: pushing down and to the right turns the hand's angle
# round the hinge the closing way, and the drum follows it shut
for d in range(0, -151, -5):
    at(d)
    if d in (-30, -60, -110, -150): print("close from the grip: hand %4d deg: stage %s" % (d, st()))
setp(trigger=0.0); time.sleep(0.3); setp(squeeze=0.0); time.sleep(0.6)
