"""geo.py -- small quaternion helpers for the hand / magazine numbers q_rel.lua prints (2026-11-23)."""
import math
def qmul(a, b):
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return (aw*bx + ax*bw + ay*bz - az*by, aw*by - ax*bz + ay*bw + az*bx, aw*bz + ax*by - ay*bx + az*bw, aw*bw - ax*bx - ay*by - az*bz)
def qinv(q): return (-q[0], -q[1], -q[2], q[3])
def qnorm(q): n = math.sqrt(sum(c*c for c in q)); return tuple(c/n for c in q)
def rot(q, v):
    x, y, z, w = qmul(qmul(q, (v[0], v[1], v[2], 0.0)), qinv(q)); return (x, y, z)
def add(a, b): return tuple(a[i] + b[i] for i in range(3))
def sub(a, b): return tuple(a[i] - b[i] for i in range(3))
def ypr(yaw, pitch, roll):   # the plugin's quat_from_ypr: yaw about Z, then pitch about Y, then roll about X (degrees)
    d = math.pi / 360.0
    return qnorm(qmul(qmul((0, 0, math.sin(yaw*d), math.cos(yaw*d)), (0, math.sin(pitch*d), 0, math.cos(pitch*d))), (math.sin(roll*d), 0, 0, math.cos(roll*d))))
def to_ypr(q):   # inverse of ypr(): q = Rz(yaw) Ry(pitch) Rx(roll)
    x, y, z, w = qnorm(q)
    m = lambda v: rot((x, y, z, w), v)
    X, Y, Z = m((1, 0, 0)), m((0, 1, 0)), m((0, 0, 1))   # columns
    pitch = math.asin(max(-1.0, min(1.0, -X[2])))
    yaw = math.atan2(X[1], X[0]); roll = math.atan2(Y[2], Z[2])
    return tuple(math.degrees(a) for a in (yaw, pitch, roll))
def fmt(v): return " ".join("%6.2f" % c for c in v)
