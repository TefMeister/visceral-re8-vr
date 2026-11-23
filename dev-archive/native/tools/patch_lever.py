"""patch_lever.py -- one-off (2026-11-23): the GM 79's latch part (`Lever`) turns with the thumb's flick (breech.cpp, settings.h)."""
import io, os, sys
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

def sub(path, old, new):
    s = io.open(path, encoding="utf-8", newline="").read()
    if "\r\n" in s: old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
    if new in s: print("already:", path); return
    if old not in s: sys.exit("NOT FOUND in %s: %r" % (path, old[:70]))
    io.open(path, "w", encoding="utf-8", newline="").write(s.replace(old, new, 1)); print("patched:", path)

sub("src/settings.h", "constexpr float BREAK_SHUT_PART = 0.06f;",
    "constexpr float BREAK_LATCH_DEG = 28.0f;           // 2026-11-23: the latch part (the gun's `Lever` joint) turns this far when flicked open\n"
    "constexpr float BREAK_LATCH_AXIS[3] = {0.0f, 1.0f, 0.0f};   // ... about this axis of its own (set by eye from the six views)\n"
    "constexpr float BREAK_LATCH_TURN_SEC = 0.08f;      // ... in this long\n"
    "constexpr float BREAK_SHUT_PART = 0.06f;")
sub("src/breech.cpp", "void pose_point() {\n",
    "// 2026-11-23 (the 360 view's list: \"its `Lever` joint turning with the flick\"): the GM 79's latch part itself turns when the thumb\n"
    "// flicks it open and back when the latch shuts (it stood still while the thumb flicked beside it)\n"
    "void lever_point() {\n"
    "    static MO* tf = nullptr;\n"
    "    static MO* lever = nullptr;\n"
    "    static Quat rest{0, 0, 0, 1};\n"
    "    static bool ok = false;\n"
    "    static float k = 0.0f, last = -1.0f;\n"
    "    const auto& s = player::now();\n"
    "    if (s.weapon_tf != tf) {\n"
    "        tf = s.weapon_tf; k = 0.0f;\n"
    "        lever = tf != nullptr ? joints::joint_by_name(tf, L\"Lever\") : nullptr;\n"
    "        ok = lever != nullptr && joints::get_q(joints::JOINT, lever, \"get_LocalRotation\", rest);\n"
    "        LOGI(\"%s breech: %s latch part (Lever) %s\", TAG, g_id.c_str(), ok ? \"found: it turns with the flick\" : \"NOT found: the latch does not move\");\n"
    "    }\n"
    "    const float now = now_s(), dt = last < 0.0f ? 0.0f : std::fmin(0.1f, now - last);\n"
    "    last = now;\n"
    "    const float step = BREAK_LATCH_TURN_SEC > 0.0f ? dt / BREAK_LATCH_TURN_SEC : 1.0f;\n"
    "    k = g_latch ? std::fmin(1.0f, k + step) : std::fmax(0.0f, k - step);\n"
    "    if (!ok || k <= 0.0f) return;\n"
    "    const float h = BREAK_LATCH_DEG * k * 3.14159265f / 360.0f, sh = std::sin(h);\n"
    "    Quat q = qnorm(qmul(rest, Quat{BREAK_LATCH_AXIS[0] * sh, BREAK_LATCH_AXIS[1] * sh, BREAK_LATCH_AXIS[2] * sh, std::cos(h)}));\n"
    "    joints::set_any(joints::JOINT, lever, \"set_LocalRotation\", &q);\n"
    "}\n"
    "\n"
    "void pose_point() {\n")
sub("src/breech.cpp",
    "    if (!here() || (g_w->breech != Breech::BREAK && !lid)) return;\n    const auto& s = player::now();\n",
    "    if (!here() || (g_w->breech != Breech::BREAK && !lid)) return;\n    if (!lid) lever_point();\n    const auto& s = player::now();\n")
