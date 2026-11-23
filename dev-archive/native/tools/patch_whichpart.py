"""patch_whichpart.py -- one-off (2026-11-23): wires whichpart.cpp into rack.cpp, reload.cpp, the headers, settings.h and CMakeLists.txt.
Run once from dev-archive/native; it refuses when a place it expects is not there."""
import io, os, sys
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

def sub(path, old, new, count=1):
    s = io.open(path, encoding="utf-8", newline="").read()
    if new in s:
        print("already:", path); return
    if s.count(old) < 1 and "\r\n" in s:   # a file with Windows line ends
        old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
        if new in s:
            print("already:", path); return
    if s.count(old) < 1:
        sys.exit("NOT FOUND in %s: %r" % (path, old[:70]))
    io.open(path, "w", encoding="utf-8", newline="").write(s.replace(old, new, count)); print("patched:", path)

sub("CMakeLists.txt", "    src/rack.cpp\n", "    src/rack.cpp\n    src/whichpart.cpp\n")
sub("src/settings.h", "constexpr float RACK_BOLT_GRAB_M = 0.09f;",
    "constexpr float WHICHPART_DUE_BIAS = 0.6f;       // whichpart.cpp (2026-11-23): a rack that is due counts as this much nearer (its distance times this)\n"
    "constexpr float RACK_BOLT_GRAB_M = 0.09f;")
sub("src/rack.h", "bool bolt_wants_left(float mag_dist_m = -1.0f);",
    "bool part_reach(float& d, float& r);   // whichpart.cpp (2026-11-23): the left controller's distance from the slide / pump / bolt zone's middle, and its reach; false = none to take\n"
    "bool grip_reach(float& d, float& r);   // the same for the front grip zone (as smooth.cpp publishes it)\n"
    "bool due_now();                        // a rack is due or a bolt is mid-cycle (not: merely empty)\n"
    "bool long_gun();                       // not a pistol\n"
    "bool bolt_wants_left(float mag_dist_m = -1.0f);")
sub("src/reload.h", "bool hand_near_mag();",
    "bool mag_reach(float& d, float& r);   // whichpart.cpp (2026-11-23): the left controller's distance from the seated magazine zone's middle, and its reach\n"
    "bool hand_near_mag();")
sub("src/reload.cpp", "bool hand_near_mag() {\n",
    "bool mag_reach(float& d, float& r) {\n"
    "    if (!managed_now() || g_w->reload != Reload::MAG || g_joint == nullptr || g_st != St::SEATED) return false;\n"
    "    Vec3 mp, cp;\n"
    "    Quat mq;\n"
    "    if (!mag_world(mp, mq) || !bridge::room_to_world(bridge::hand_pos(bridge::LEFT), cp)) return false;\n"
    "    d = dist(zones::center(zones::MAG, mp), cp);\n"
    "    r = zones::radius(zones::MAG);\n"
    "    return true;\n"
    "}\n"
    "bool hand_near_mag() {\n")
sub("src/reload.cpp",
    'if (rack::bolt_wants_left(d)) { LOGI("%s reload: the hand is near the bolt too and a rack is due: the bolt takes it, not the magazine", TAG); return; }',
    '// 2026-11-23 (whichpart.h): inside more than one zone, the part whose middle is nearest for its size takes the hand\n'
    '        const whichpart::Part wp = whichpart::nearest();\n'
    '        if (wp != whichpart::MAG && wp != whichpart::NONE) { LOGI("%s reload: the hand is nearer the %s (for its size): that takes it, not the magazine", TAG, whichpart::name(wp)); return; }')
sub("src/reload.cpp", '#include "rack.h"\n', '#include "rack.h"\n#include "whichpart.h"\n')
sub("src/rack.cpp",
    "const bool want = lg && !reload::hand_on_mag() && (!reload::hand_near_mag() || bolt_wants_left()) && (!g_from_grip || from_zone);",
    "// 2026-11-23 (whichpart.h): the magazine and the front grip keep the hand when their middle is nearer for its size\n"
    "        const whichpart::Part wp = whichpart::nearest();\n"
    "        const bool want = lg && !reload::hand_on_mag() && wp != whichpart::MAG && wp != whichpart::GRIP && (!g_from_grip || from_zone);")
sub("src/rack.cpp", "bool bolt_wants_left(float mag_dist_m) {",
    "bool part_reach(float& d, float& r) {\n"
    "    if (!RELOAD_ON || !rackable() || g_joint == nullptr || g_hand_on || g_right) return false;\n"
    "    r = joint_grab_m();\n"
    "    if (near_joint(d)) { if (g_near_left) r = zones::radius(zones::SLIDE_LEFT); return true; }   // (a pistol's left-side sphere answers with its own reach)\n"
    "    return true;   // d is set whenever the joint and the hand could be read; outside the zone it is simply > r\n"
    "}\n"
    "bool grip_reach(float& d, float& r) {\n"
    "    const int s = bridge::S_ZONES + (int)zones::GRIP * 5;\n"
    "    const float x = bridge::view((bridge::Slot)(s + 0)), y = bridge::view((bridge::Slot)(s + 1)), z = bridge::view((bridge::Slot)(s + 2)),\n"
    "                rr = bridge::view((bridge::Slot)(s + 3)), on = bridge::view((bridge::Slot)(s + 4));\n"
    "    if (!bridge::has(x) || !bridge::has(rr) || !bridge::has(on) || on < 0.5f || rr <= 0.0f) return false;\n"
    "    Vec3 lp, c;\n"
    "    if (!bridge::room_to_world(bridge::hand_pos(bridge::LEFT), lp)) return false;\n"
    "    c.x = x; c.y = y; c.z = z;\n"
    "    d = dist(c, lp);\n"
    "    r = rr;\n"
    "    return true;\n"
    "}\n"
    "bool due_now() { return rackable() && (g_needed || g_bstate != 0 || g_turn > 0.0f); }\n"
    "bool long_gun() { return g_w != nullptr && g_w->shape != weapons::Shape::PISTOL; }\n"
    "bool bolt_wants_left(float mag_dist_m) {")
sub("src/rack.cpp", '#include "reload.h"\n', '#include "reload.h"\n#include "whichpart.h"\n')
