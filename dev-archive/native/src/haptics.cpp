// haptics.cpp -- see haptics.h. Line references are to dev-archive/original-lua/autorun/re8_vr_haptics.lua and
// re8_vr.lua (Andyalpa's Hands Off pack, received 2026-10-15).
#include "haptics.h"

#include <algorithm>
#include <chrono>
#include <cstdint>

#include "bridge.h"
#include "settings.h"

namespace vn::haptics {

using namespace settings;
using bridge::Hand;

namespace {

struct Cfg {
    bool enabled = HAP_DEF_ENABLED;
    bool gate_left = HAP_DEF_GATE_LEFT;
    float scale = HAP_DEF_SCALE;
    bool auto_pulse = HAP_DEF_AUTO_PULSE;
    float on_s = HAP_DEF_ON_S, off_s = HAP_DEF_OFF_S, max_dur = HAP_DEF_MAX_DUR;
};

struct State {
    int64_t frame = 0;
    int64_t shoot_frame = -1;          // last frame a game rumble order came in (shoot_rumble_frame)
    bool two_handed = false;
    bool sticky = false;               // two_hand_prox.sticky
    double tick_t = 0.0;               // auto_pulse_last_tick_t
    bool tick_left = false, tick_right = false;   // auto_pulse_tick_sides
    bool announced = false;
} g;

double now_s() {
    using namespace std::chrono;
    return duration<double>(steady_clock::now().time_since_epoch()).count();
}

Cfg cfg() {
    Cfg c;
    if (!bridge::flag(bridge::S_HAP_SENT)) return c;
    c.enabled = bridge::flag(bridge::S_HAP_ON);
    c.gate_left = bridge::flag(bridge::S_HAP_GATE_LEFT);
    c.scale = bridge::view(bridge::S_HAP_SCALE);
    c.auto_pulse = bridge::flag(bridge::S_HAP_AUTO_PULSE);
    c.on_s = bridge::view(bridge::S_HAP_ON_S);
    c.off_s = bridge::view(bridge::S_HAP_OFF_S);
    c.max_dur = bridge::view(bridge::S_HAP_MAX_DUR);
    return c;
}

bool weapon_auto() { return bridge::flag(bridge::S_WEAPON_AUTO); }   // refresh_weapon_kind: both name lists are empty

// read_left_grip (Lua 396): the left grip axis wins, then the right grip axis vetoes, then the digital and other signals
bool left_grip() {
    const float la = bridge::view(bridge::S_LGRIP_AXIS);
    const float ra = bridge::view(bridge::S_RGRIP_AXIS);
    if (la >= HAP_GRIP_AXIS_ON) return true;
    if (ra >= HAP_GRIP_AXIS_ON) return false;
    if (bridge::flag(bridge::S_LGRIP)) return true;
    return bridge::flag(bridge::S_LGRIP_OTHER) && !bridge::flag(bridge::S_RGRIP);
}

// hands_world_distance (Lua 441): the game's hands first, the controllers in the room as the fallback
float hands_distance() {
    if (bridge::flag(bridge::S_HANDS_W_OK)) {
        const float d = dist(bridge::view_vec3(bridge::S_LHAND_W), bridge::view_vec3(bridge::S_RHAND_W));
        if (d < HAP_FAR_DISTANCE) return d;
    }
    const Vec3 l = bridge::view_vec3(bridge::S_LPOS), r = bridge::view_vec3(bridge::S_RPOS);
    if (!bridge::has(l.x) || !bridge::has(r.x)) return HAP_NO_DISTANCE;
    return dist(l, r);
}

// is_two_handed_support (Lua 458)
bool two_handed_support(bool grip) {
    if (bridge::flag(bridge::S_IN_HOLSTER_ZONE) || bridge::flag(bridge::S_IN_FLASHLIGHT_ZONE) || !bridge::flag(bridge::S_RE8VR)) {
        g.sticky = false;
        return false;
    }
    if (bridge::flag(bridge::S_GRIPPING_WEAPON)) { g.sticky = true; return true; }
    if (!grip) { g.sticky = false; return false; }
    const float d = hands_distance();
    if (d <= HAP_TWO_HAND_ENTER_M) { g.sticky = true; return true; }
    if (g.sticky && d <= HAP_TWO_HAND_EXIT_M) return true;
    g.sticky = false;
    return false;
}

void update_two_hand() { g.two_handed = two_handed_support(left_grip()); }

// auto_pulse_allows (Lua 283): one tick per period, each hand once per tick (an L+R pair)
bool auto_pulse_allows(Hand side, const Cfg& c) {
    if (!c.auto_pulse || !weapon_auto()) return true;
    const float period = std::max(c.on_s, HAP_PULSE_ON_MIN_S) + std::max(c.off_s, HAP_PULSE_OFF_MIN_S);
    const double t = now_s();
    if (g.tick_t <= 0.0 || t - g.tick_t >= period) {
        g.tick_t = t;
        g.tick_left = side == bridge::LEFT;
        g.tick_right = side == bridge::RIGHT;
        return true;
    }
    bool& mine = side == bridge::LEFT ? g.tick_left : g.tick_right;
    if (mine) return false;
    if (g.tick_left || g.tick_right) { mine = true; return true; }
    return false;
}

// haptic_trigger (Lua 526): one forward from praydog's code, filtered
void send(Hand side, float seconds, float amp, const Cfg& c, bool shooting) {
    if (!c.enabled || bridge::flag(bridge::S_MASTER_OFF)) { bridge::rumble(side, amp, seconds, HAP_PAD_HZ); return; }
    if (side == bridge::LEFT && c.gate_left && shooting && !g.two_handed) return;
    if (shooting) {
        if (!auto_pulse_allows(side, c)) return;
        amp = std::clamp(amp * c.scale, 0.0f, HAP_AMP_MAX);
        if (weapon_auto() && c.auto_pulse) seconds = std::clamp(c.max_dur, HAP_PULSE_DUR_MIN_S, HAP_PULSE_DUR_MAX_S);
    }
    bridge::rumble(side, amp, seconds, HAP_PAD_HZ);
}

// false when the controllers are not in use (praydog: `if not vrmod:is_using_controllers() then return`).
// The Lua decided "shooting" per forward: a frequency-1 forward outside the grab zones, or any forward within two frames
// of an order its own hook had seen. Every forward here comes from an order, so that is: outside the zones, or recent.
bool begin_order(bool& shooting) {
    if (!bridge::live()) return false;
    update_two_hand();                                       // Andyalpa's pre-hook refreshed it on every order too
    const bool in_zone = bridge::flag(bridge::S_IN_HOLSTER_ZONE) || bridge::flag(bridge::S_IN_FLASHLIGHT_ZONE);
    const bool recent = g.shoot_frame >= 0 && g.frame - g.shoot_frame <= HAP_SHOOT_CONTEXT_FRAMES;
    g.shoot_frame = g.frame;
    shooting = !in_zone || recent;
    return true;
}

// re8_vr.lua re8_on_pre_order_vibration (Lua 2135): OrderVibration(app.VibrationTask)
int pre_order_task(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    if (argc < 3 || !bridge::flag(bridge::S_NATIVE_HAPTICS)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    if (!GAME_RUMBLE_TO_CONTROLLERS) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    auto* task = (MO*)argv[2];
    if (!is_managed(task)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    const float* lp = field_ptr<float>(task, "MotorPower_0");
    const float* rp = field_ptr<float>(task, "MotorPower_1");
    const float* sec = field_ptr<float>(task, "TimeSecond");
    if (lp == nullptr || rp == nullptr || sec == nullptr) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    bool shooting = false;
    if (!begin_order(shooting)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    const Cfg c = cfg();
    if (*lp > 0.0f) send(bridge::LEFT, *sec, *lp, c, shooting);
    else if (bridge::flag(bridge::S_GRIPPING_WEAPON)) send(bridge::LEFT, *sec, *rp, c, shooting);   // left docked: it feels the right motor
    if (*rp > 0.0f) send(bridge::RIGHT, *sec, *rp, c, shooting);
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;                    // the game's own pad rumble always runs
}

// re8_vr.lua re8_on_pre_order_vibration2 (Lua 2169): OrderVibration(Single seconds, Single power, ...). The floats sit in
// the argument slots as raw bits, the way the Lua's sdk.to_float(args[3]) / args[4] read them (args[1] = the VM context).
int pre_order_floats(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    if (argc < 4 || !bridge::flag(bridge::S_NATIVE_HAPTICS)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    if (!GAME_RUMBLE_TO_CONTROLLERS) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    const float seconds = *(const float*)&argv[2];
    const float power = *(const float*)&argv[3];
    bool shooting = false;
    if (power <= 0.0f || !begin_order(shooting)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;   // praydog's power-0 right forward did nothing
    const Cfg c = cfg();
    send(bridge::LEFT, seconds, power, c, shooting);
    send(bridge::RIGHT, seconds, power, c, shooting);        // praydog: both hands, the same power
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

int g_hooks = 0;

} // namespace

void install() {
    auto* td = API::get()->tdb()->find_type("app.HIDVibrationManager");
    if (td == nullptr) { LOGE("%s haptics: app.HIDVibrationManager not found, praydog's rumble stays on", TAG); return; }
    if (auto* m = td->find_method("OrderVibration(app.VibrationTask)")) { m->add_hook(pre_order_task, nullptr, false); ++g_hooks; }
    if (auto* m = td->find_method("OrderVibration(System.Single, System.Single, System.Single, System.Boolean, System.Int32, System.Boolean, System.Single, System.Single, via.GameObject, System.Single, System.Single)")) {
        m->add_hook(pre_order_floats, nullptr, false);
        ++g_hooks;
    }
    LOGI("%s haptics: %d of 2 OrderVibration hooks in", TAG, g_hooks);
}

void frame() {
    ++g.frame;
    if (g_hooks == 2) bridge::put(bridge::S_NATIVE_HAPTICS, 1.0f);   // both forwards are ours: re8_vr.lua's stand down
    if (!g.announced && bridge::flag(bridge::S_NATIVE_HAPTICS)) {
        g.announced = true;
        LOGI("%s haptics: the plugin forwards the game's rumble now", TAG);
    }
    if (g.frame % HAP_TWO_HAND_EVERY_FRAMES == 0 && bridge::live()) update_two_hand();
    if (g.shoot_frame >= 0 && g.frame - g.shoot_frame > HAP_SHOOT_CONTEXT_FRAMES) {   // on_frame (Lua 698)
        g.shoot_frame = -1;
        g.tick_t = 0.0;
        g.tick_left = g.tick_right = false;
    }
}

} // namespace vn::haptics
