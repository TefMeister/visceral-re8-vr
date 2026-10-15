// recoil.cpp -- see recoil.h. Port of Andyalpa's re8_vr_recoil.lua (Hands Off pack, dev-archive/original-lua/), kept
// function for function; each block names the Lua function it stands for. Differences, all [inferred-static]:
//   - time: a steady clock instead of via.Application.get_UpTimeSecond (the Lua's own fallback was os.clock)
//   - the frame number is the plugin's own (UpdateBehavior pre), not re.get_frame_count
//   - the ammo-delta bookkeeping (m_recoil_last_ammo_count) is left out: the Lua computed it and never used it
//   - a joint index below 0 from the animation is treated as "not found" instead of being passed on
//   - the hooks can run off the game thread, so the state sits behind one lock (the Lua had REFramework's)
// The two globals the Lua published (__vr_recoil_ik_patching, __vr_recoil_has_active) are not published: no file of
// the pack reads them.
#include "recoil.h"
#include "bridge.h"
#include "common.h"
#include "json_mini.h"
#include "player.h"
#include "settings.h"

#include <windows.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <map>
#include <mutex>
#include <random>
#include <set>
#include <string>

namespace vn::recoil {

using namespace vn::settings;

namespace {

constexpr float PI_HALF = 1.57079632679f;

// ---- the weapon tables (top of re8_vr_recoil.lua) ------------------------------------------------------------------
struct Profile { const char* weight; float one_kick, one_spring, one_auto, one_sustain; };   // "two" is 1,1,1,1 for all
const std::map<std::string, float> TYPE_INTENSITY = {
    {"handgun", 1.22f}, {"revolver", 1.38f}, {"smg", 1.75f}, {"rifle", 1.48f}, {"shotgun", 2.55f}, {"magnum", 2.90f},
    {"launcher", 2.45f}, {"flamethrower", 1.52f}, {"electric", 1.68f}, {"rpg", 3.90f}, {"minigun", 3.20f}};
const std::map<std::string, Profile> GRIP_PROFILE = {
    {"handgun", {"light", 1.08f, 1.10f, 1.00f, 1.00f}},  {"revolver", {"light", 1.14f, 1.15f, 1.00f, 1.00f}},
    {"smg", {"light", 1.10f, 1.12f, 1.55f, 1.18f}},      {"rifle", {"medium", 1.18f, 1.20f, 1.25f, 1.10f}},
    {"shotgun", {"heavy", 1.22f, 1.48f, 1.00f, 1.05f}},  {"magnum", {"heavy", 1.26f, 1.40f, 1.00f, 1.00f}},
    {"launcher", {"heavy", 1.20f, 1.35f, 1.00f, 1.00f}}, {"flamethrower", {"medium", 1.12f, 1.14f, 1.35f, 1.15f}},
    {"electric", {"medium", 1.14f, 1.16f, 1.20f, 1.08f}}, {"rpg", {"heavy", 1.30f, 1.38f, 1.00f, 1.00f}},
    {"minigun", {"heavy", 1.15f, 1.22f, 1.65f, 1.25f}}};
const std::set<std::string> NO_RECOIL_IDS = {"ri3022_Inventory", "ri3044_Inventory"};
const std::set<std::string> AUTO_RECOIL_IDS = {"ri3049_Inventory", "ri3125_Inventory", "ri3129_Inventory"};
// id -> type (names live in the menu Lua, which draws them)
const std::map<std::string, std::string> CATALOG_TYPE = {
    {"ri3008_Inventory", "magnum"},  {"ri3021_Inventory", "shotgun"}, {"ri3023_Inventory", "launcher"},
    {"ri3036_Inventory", "shotgun"}, {"ri3040_Inventory", "handgun"}, {"ri3042_Inventory", "rifle"},
    {"ri3046_Inventory", "handgun"}, {"ri3047_Inventory", "handgun"}, {"ri3048_Inventory", "shotgun"},
    {"ri3049_Inventory", "rifle"},   {"ri3050_Inventory", "magnum"},  {"ri3115_Inventory", "handgun"},
    {"ri3116_Inventory", "magnum"},  {"ri3122_Inventory", "handgun"}, {"ri3124_Inventory", "handgun"},
    {"ri3125_Inventory", "rifle"},   {"ri3135_Inventory", "handgun"}, {"ri3147_Inventory", "shotgun"},
    {"ri3081_Inventory", "handgun"}, {"ri3082_Inventory", "handgun"}, {"ri3083_Inventory", "handgun"},
    {"ri3084_Inventory", "shotgun"}, {"ri3085_Inventory", "shotgun"}, {"ri3086_Inventory", "shotgun"},
    {"ri3087_Inventory", "rifle"},   {"ri3129_Inventory", "rifle"},   {"ri3130_Inventory", "handgun"}};

// ---- CFG: the saved file's keys and Andyalpa's defaults ------------------------------------------------------------
struct Cfg {
    bool enabled = true, use_native_recoil = false, suppress_camera_recoil = false, apply_yaw_rotation = true;
    float intensity = 2.0f, attack_duration = 0.005f, spring_stiffness = 50.0f, spring_damping = 5.0f;
    float sustained_damping = 10.0f, spring_settle_mult = 4.5f, sustained_window = 0.125f, substep_dt = 0.008f;
    float position_intensity = 0.006f, position_up_ratio = 1.0f, position_back_ratio = 0.0f;
    float rotation_intensity = 0.01f, wrist_pitch_sign = -1.0f, yaw_intensity = 0.171f, wrist_yaw_sign = 1.0f;
    float horizontal_spread = 0.0f, vertical_spread = 0.0f, randomness = 0.347f, mult_exponent = 0.1f;
    float stack_cap = 2.0f, auto_scale = 0.25f, two_hand_scale = 0.55f, one_hand_light = 1.18f, one_hand_heavy = 1.90f;
    std::map<std::string, float> weapons;   // canonical id -> intensity (1..4), only for ids that have recoil
};

std::mutex g_mx;
Cfg g_cfg;
std::atomic<int> g_frame{0};
std::mt19937 g_rng{std::random_device{}()};
std::atomic<int> g_kicks{0}, g_patches{0};
bool g_installed_fire = false, g_installed_ik = false, g_installed_cam = false;

#ifdef VN_RECOIL_TEST   // tools/recoil_test: the same shots through this file and through Andyalpa's Lua, side by side
double vn_test_clock();
float vn_test_random();
float rnd() { return vn_test_random(); }
double now_s() { return vn_test_clock(); }
#else
float rnd() { return std::uniform_real_distribution<float>(0.0f, 1.0f)(g_rng); }
double now_s() {   // seconds since load, as a double: a float clock loses the frame step after an hour of play
    static const auto t0 = std::chrono::steady_clock::now();
    return std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
}
#endif

// ---- weapon helpers (canonicalize_weapon_id ... get_per_weapon_intensity) ------------------------------------------
bool known(const std::string& id) { return CATALOG_TYPE.count(id) || NO_RECOIL_IDS.count(id) || AUTO_RECOIL_IDS.count(id); }
std::string canonical(const std::string& id) {
    if (id.empty() || known(id)) return id;
    const std::string inv = id + "_Inventory";
    return known(inv) ? inv : id;
}
float clamp_intensity(float v) { return std::clamp(v, REC_WEAPON_INTENSITY_MIN, REC_WEAPON_INTENSITY_MAX); }
// resolve_weapon_type: catalog, else the weapon's own short/long answer; "" = none
std::string weapon_type(const std::string& id, MO* weapon) {
    auto it = CATALOG_TYPE.find(canonical(id));
    if (it != CATALOG_TYPE.end()) return it->second;
    bool b = false;
    if (weapon != nullptr && player::try_bool(weapon, "isShortWeapon", b) && b) return "handgun";
    if (weapon != nullptr && player::try_bool(weapon, "isLongWeapon", b) && b) return "rifle";
    return "";
}
bool supported(const std::string& raw_id, MO* weapon) {
    const std::string id = canonical(raw_id);
    if (id.empty() || NO_RECOIL_IDS.count(id)) return false;
    return TYPE_INTENSITY.count(weapon_type(id, weapon)) > 0;
}
float per_weapon_intensity(const std::string& raw_id, MO* weapon) {
    const std::string id = canonical(raw_id);
    if (id.empty()) return 1.0f;
    if (!supported(id, weapon)) return 0.0f;
    auto it = g_cfg.weapons.find(id);
    if (it != g_cfg.weapons.end()) return it->second;
    // default_weapon_entry is built without the weapon, so only catalogued types have a default; else 1.0
    auto t = TYPE_INTENSITY.find(weapon_type(id, nullptr));
    return t != TYPE_INTENSITY.end() ? t->second : 1.0f;
}

// ---- settings file (load_cfg_from_disk; the menu Lua writes it) ----------------------------------------------------
std::wstring cfg_path() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring p(exe);
    p = p.substr(0, p.find_last_of(L"\\/") + 1);
    return p + L"reframework\\data\\re8_vr\\re8_vr_recoil.json";
}
void load_cfg() {
    json::Value v;
    if (!json::load_file(cfg_path(), v) || v.kind != json::Value::OBJ) return;
    Cfg c;   // defaults, then every key of the right type from the file (the Lua kept a key only when its type matched)
    auto b = [&](const char* k, bool& out) { if (auto* x = v.get(k); x && x->kind == json::Value::BOOL) out = x->b; };
    auto f = [&](const char* k, float& out) { if (auto* x = v.get(k); x && x->kind == json::Value::NUM) out = (float)x->n; };
    b("enabled", c.enabled); b("use_native_recoil", c.use_native_recoil);
    b("suppress_camera_recoil", c.suppress_camera_recoil); b("apply_yaw_rotation", c.apply_yaw_rotation);
    f("intensity", c.intensity); f("attack_duration", c.attack_duration); f("spring_stiffness", c.spring_stiffness);
    f("spring_damping", c.spring_damping); f("sustained_damping", c.sustained_damping);
    f("spring_settle_mult", c.spring_settle_mult); f("sustained_window", c.sustained_window); f("substep_dt", c.substep_dt);
    f("position_intensity", c.position_intensity); f("position_up_ratio", c.position_up_ratio);
    f("position_back_ratio", c.position_back_ratio); f("rotation_intensity", c.rotation_intensity);
    f("wrist_pitch_sign", c.wrist_pitch_sign); f("yaw_intensity", c.yaw_intensity); f("wrist_yaw_sign", c.wrist_yaw_sign);
    f("horizontal_spread", c.horizontal_spread); f("vertical_spread", c.vertical_spread); f("randomness", c.randomness);
    f("mult_exponent", c.mult_exponent); f("stack_cap", c.stack_cap); f("auto_scale", c.auto_scale);
    f("two_hand_scale", c.two_hand_scale); f("one_hand_light", c.one_hand_light); f("one_hand_heavy", c.one_hand_heavy);
    if (auto* w = v.get("weapons"); w && w->kind == json::Value::OBJ) {
        for (auto& [raw, entry] : w->obj) {   // import_weapons_into_cfg / normalize_weapon_entry
            const std::string id = canonical(raw);
            if (!supported(id, nullptr)) continue;
            float inten = TYPE_INTENSITY.at(weapon_type(id, nullptr));   // a non-table entry = the default
            if (entry.kind == json::Value::OBJ) {
                if (auto* t = entry.get("type"); t && t->kind == json::Value::STR && t->s == "utility") continue;
                if (auto* in = entry.get("intensity"); in && in->kind == json::Value::NUM) inten = clamp_intensity((float)in->n);
                else if (in && in->kind == json::Value::STR) inten = clamp_intensity((float)std::atof(in->s.c_str()));
            }
            c.weapons[id] = inten;
        }
    }
    g_cfg = c;
    LOGI("%s recoil: settings read (on %d, intensity %.2f, %d weapons)", TAG, (int)c.enabled, c.intensity, (int)c.weapons.size());
}
void check_cfg_file() {
    static FILETIME last{};
    static bool first = true;
    WIN32_FILE_ATTRIBUTE_DATA a{};
    if (!GetFileAttributesExW(cfg_path().c_str(), GetFileExInfoStandard, &a)) { first = false; return; }
    if (!first && CompareFileTime(&a.ftLastWriteTime, &last) == 0) return;
    first = false;
    last = a.ftLastWriteTime;
    load_cfg();
}

// ---- state (m_recoil, m_attack, m_recoil_fadeout, frame_* tables) --------------------------------------------------
struct Spring { float pos_y = 0, pos_z = 0, vel_y = 0, vel_z = 0, pitch = 0, vel_pitch = 0, yaw = 0, vel_yaw = 0; };
struct Attack { bool active = false; float t = 0, pos_y = 0, pos_z = 0, pitch = 0, yaw = 0; };
struct Fade { bool active = false; float t = 0, duration = REC_FADEOUT_S, pitch = 0, yaw = 0, pos_y = 0, pos_z = 0; };
struct Offsets { int frame = -1; float pitch = 0, yaw = 0, pos_y = 0, pos_z = 0; };
struct Grip { bool two_hand = false; std::string wtype = "handgun"; std::string weight = "light";
              float global_kick = 1, kick = 1, spring = 1, autom = 1, sustain = 1; };
struct Pose { Vec3 p{}; Quat q{0, 0, 0, 1}; bool ok = false; };
struct FrameIk { Pose rh_pre, lh_pre; MO* lh_ik = nullptr; int grip_frame = -1; Vec3 grip_pos{}; Quat grip_rot{0, 0, 0, 1}; };
struct Apply { bool two_handed = false, has_recoil = false; };
struct Equipped { int frame = -1; bool ok = false; MO* weapon = nullptr; std::string id; };

Spring m_spring;
Attack m_attack;
Fade m_fade;
Offsets m_frame_off;
Grip m_grip;
FrameIk m_fik;
Apply m_apply;
Equipped m_eq;
int m_pending = 0;
double m_last_shot_t = 0, m_last_t = 0;
bool m_active = false;
int m_last_physics_frame = -1, m_ik_physics_sync_frame = -1, m_ik_sync_frame = -1;
struct { int frame = -1; bool idle_after_first = false; } m_pass;
bool m_fire_had_ammo = false;

int frame_id() { return g_frame.load(); }
bool flag(int bit) {   // not attached = no flags (view() then reads NO_VALUE, whose bits mean nothing)
    const float v = bridge::view(bridge::S_RECOIL_FLAGS);
    return bridge::has(v) && ((int)v & bit) != 0;
}

// ---- gates (lua_recoil_active, vr_active, is_two_handed ...) --------------------------------------------------------
bool recoil_on() { return !bridge::flag(bridge::S_MASTER_OFF) && g_cfg.enabled && !g_cfg.use_native_recoil; }
bool vr_active() {
    return recoil_on() && bridge::live() && bridge::flag(bridge::S_CAN_USE_HANDS);
}
bool left_grip() { return bridge::held(bridge::S_LGRIP); }
bool in_zone() { return bridge::flag(bridge::S_IN_HOLSTER_ZONE) || bridge::flag(bridge::S_IN_FLASHLIGHT_ZONE); }
bool two_hand_recoil() { return left_grip() && !in_zone(); }   // is_two_hand_recoil_active
bool hands_supporting() {   // hands_are_supporting_weapon: the controllers (the Lua's vrmod:get_position fallback)
    const Vec3 l = bridge::view_vec3(bridge::S_LPOS), r = bridge::view_vec3(bridge::S_RPOS);
    if (!bridge::has(l.x) || !bridge::has(r.x)) return false;
    return dist(l, r) <= REC_SUPPORT_HAND_M;
}
bool is_two_handed() {
    if (bridge::flag(bridge::S_IS_RELOADING)) return true;
    if (in_zone() || !left_grip()) return false;
    return hands_supporting() || bridge::flag(bridge::S_AIMING);
}
bool weapon_grip_active() { return two_hand_recoil() || bridge::flag(bridge::S_GRIPPING_WEAPON) || is_two_handed(); }
bool support_follows_weapon() {
    if (flag(bridge::RF_BLOCK_LEFT_IK)) return false;
    if (bridge::flag(bridge::S_IS_RELOADING)) return true;
    return left_grip() && weapon_grip_active();
}

const Equipped& equipped() {   // get_equipped_recoil_state, once per frame
    const int f = frame_id();
    if (m_eq.frame != f) {
        const auto& s = player::now();
        m_eq.frame = f;
        m_eq.weapon = s.weapon;
        m_eq.id = canonical(s.weapon_id);
        m_eq.ok = s.weapon != nullptr && supported(m_eq.id, s.weapon);
    }
    return m_eq;
}

// ---- the spring (cancel_recoil_state ... update_recoil) -----------------------------------------------------------
void cancel_state() {
    m_spring = Spring{};
    m_attack = Attack{};
    m_active = false;
    m_last_t = 0;
    m_fade.active = false;
    m_fade.t = 0;
}
void effective(float& pitch, float& yaw, float& py, float& pz) {   // get_effective_recoil_offsets
    if (m_fade.active) {
        const float blend = 1.0f - std::min(1.0f, m_fade.t / m_fade.duration);
        pitch = m_fade.pitch * blend; yaw = m_fade.yaw * blend; py = m_fade.pos_y * blend; pz = m_fade.pos_z * blend;
        return;
    }
    if (m_frame_off.frame == frame_id()) { pitch = m_frame_off.pitch; yaw = m_frame_off.yaw; py = m_frame_off.pos_y; pz = m_frame_off.pos_z; return; }
    pitch = m_spring.pitch; yaw = m_spring.yaw; py = m_spring.pos_y; pz = m_spring.pos_z;
}
void capture_frame_offsets() {
    float p, y, a, b;
    effective(p, y, a, b);
    m_frame_off = {frame_id(), p, y, a, b};
}
void begin_fadeout() {
    if (m_fade.active) return;
    m_fade.pitch = m_spring.pitch; m_fade.yaw = m_spring.yaw; m_fade.pos_y = m_spring.pos_y; m_fade.pos_z = m_spring.pos_z;
    const float rot = std::fabs(m_fade.pitch) + std::fabs(m_fade.yaw), pos = std::fabs(m_fade.pos_y) + std::fabs(m_fade.pos_z);
    if (rot < REC_ZERO && pos < REC_ZERO) { m_active = false; return; }   // already at rest: end the cycle cleanly
    m_fade.active = true;
    m_fade.t = 0;
    m_fade.duration = REC_FADEOUT_S;
    m_spring = Spring{};
    m_attack.active = false;
    m_active = true;
}
void refresh_offsets() {   // refresh_frame_recoil_offsets
    if (m_fade.active || m_attack.active) { m_apply.has_recoil = true; return; }
    const float pos = std::fabs(m_spring.pos_y) + std::fabs(m_spring.pos_z), rot = std::fabs(m_spring.pitch) + std::fabs(m_spring.yaw);
    if (pos < REC_ZERO && rot < REC_ZERO) { m_apply.has_recoil = false; return; }
    m_apply.has_recoil = true;
    if (!g_cfg.apply_yaw_rotation) { m_spring.yaw = 0; m_spring.vel_yaw = 0; }
}
float one_hand_kick(const std::string& weight) {
    if (weight == "heavy") return g_cfg.one_hand_heavy;
    if (weight == "medium") return g_cfg.one_hand_light + (g_cfg.one_hand_heavy - g_cfg.one_hand_light) * REC_MEDIUM_BLEND;
    return g_cfg.one_hand_light;
}
const Grip& update_grip(const std::string& id, MO* weapon) {   // update_recoil_grip_state
    std::string t = weapon_type(id, weapon);
    if (t.empty()) t = "handgun";
    auto it = GRIP_PROFILE.find(t);
    const Profile& p = it != GRIP_PROFILE.end() ? it->second : GRIP_PROFILE.at("handgun");
    const bool two = two_hand_recoil();
    m_grip.two_hand = two;
    m_grip.wtype = t;
    m_grip.weight = p.weight;
    m_grip.kick = two ? 1.0f : p.one_kick;
    m_grip.spring = two ? 1.0f : p.one_spring;
    m_grip.autom = two ? 1.0f : p.one_auto;
    m_grip.sustain = two ? 1.0f : p.one_sustain;
    m_grip.global_kick = two ? g_cfg.two_hand_scale : one_hand_kick(m_grip.weight);
    return m_grip;
}
void kick(MO* weapon, const std::string& id) {   // apply_recoil_kickback
    if (!vr_active()) return;
    const float base = per_weapon_intensity(id, weapon);
    if (base <= 0) return;
    const float wmult = base * g_cfg.intensity;
    if (wmult <= 0) return;
    const Grip& grip = update_grip(id, weapon);
    const float random_factor = 1.0f + (rnd() - 0.5f) * g_cfg.randomness;
    const float ex = std::clamp(g_cfg.mult_exponent, REC_EXPONENT_MIN, REC_EXPONENT_MAX);
    float total = std::pow(wmult, ex) * random_factor;
    const float grip_kick = grip.global_kick * grip.kick;
    if (grip_kick > 0) total *= grip_kick;
    if (AUTO_RECOIL_IDS.count(canonical(id))) total *= std::max(REC_AUTO_SCALE_MIN, g_cfg.auto_scale) * grip.autom;
    if (total <= 0) return;
    const float up = std::max(0.0f, g_cfg.position_up_ratio), back = std::max(0.0f, g_cfg.position_back_ratio);
    const float pos_peak = g_cfg.position_intensity * total;
    float pitch_peak = g_cfg.rotation_intensity * total;
    if (g_cfg.vertical_spread > 0) pitch_peak += (rnd() - 0.5f) * g_cfg.vertical_spread * total;
    float yaw_peak = 0;
    if (g_cfg.apply_yaw_rotation) {
        yaw_peak = g_cfg.yaw_intensity * total;
        if (g_cfg.horizontal_spread > 0) yaw_peak += (rnd() - 0.5f) * 2.0f * g_cfg.horizontal_spread * total;
    }
    m_attack.pos_y += pos_peak * up;
    m_attack.pos_z += -pos_peak * back;
    m_attack.pitch += pitch_peak;
    m_attack.yaw += yaw_peak;
    if (g_cfg.stack_cap > 0) {
        const float cap_pos = g_cfg.position_intensity * g_cfg.stack_cap, cap_rot = g_cfg.rotation_intensity * g_cfg.stack_cap;
        const float cap_yaw = std::max(g_cfg.yaw_intensity, g_cfg.horizontal_spread) * g_cfg.stack_cap;
        m_attack.pos_y = std::min(m_attack.pos_y, cap_pos * up);
        m_attack.pos_z = std::max(m_attack.pos_z, -cap_pos * back);
        m_attack.pitch = std::min(m_attack.pitch, cap_rot);
        m_attack.yaw = std::clamp(m_attack.yaw, -cap_yaw, cap_yaw);
    }
    m_attack.t = 0;
    m_attack.active = true;
    m_active = true;
    const double t = now_s();
    if (m_last_t == 0) m_last_t = t;
    m_last_shot_t = t;
    const int n = g_kicks.fetch_add(1) + 1;
    if (n <= 5 || n % 100 == 0)
        LOGI("%s recoil: kick #%d %s (%s, %s), pitch %.4f yaw %.4f lift %.4f", TAG, n, id.c_str(), grip.wtype.c_str(),
             grip.two_hand ? "two hands" : "one hand", m_attack.pitch, m_attack.yaw, m_attack.pos_y);
}
void spring_step(float& pos, float& vel, float k, float c, float settle_mult, float sub, const SpringChannel& ch) {
    float c_eff = c;
    const float a = std::fabs(pos);
    if (a < ch.settle_start) c_eff = c * (1.0f + (1.0f - a / ch.settle_start) * (settle_mult - 1.0f));
    vel += (-k * pos - c_eff * vel) * sub;
    pos += vel * sub;
    if (std::fabs(pos) < ch.snap_pos && std::fabs(vel) < ch.snap_vel) { pos = 0; vel = 0; }
}
void update_spring(float dt) {   // update_recoil
    dt = std::min(dt, REC_DT_MAX_S);
    if (m_fade.active && dt > 0) {
        m_fade.t += dt;
        if (m_fade.t >= m_fade.duration) cancel_state();
        return;
    }
    if (!m_active && !m_attack.active) return;
    const double t = now_s();
    if (m_last_t > 0) dt = std::min((float)(t - m_last_t), REC_DT_MAX_S);
    m_last_t = t;
    const float attack = std::max(g_cfg.attack_duration, REC_ATTACK_MIN_S);
    const auto& e = equipped();
    const Grip& grip = update_grip(e.id, e.weapon);
    const float k = g_cfg.spring_stiffness * grip.spring;
    const float c_base = g_cfg.spring_damping * grip.sustain, c_sus = g_cfg.sustained_damping * grip.sustain;
    const float window = std::max(g_cfg.sustained_window, REC_SUSTAIN_WINDOW_MIN_S);
    if (m_attack.active && dt > 0) {
        m_attack.t += dt;
        if (m_attack.t >= attack) {
            m_spring = Spring{};
            m_spring.pos_y = m_attack.pos_y; m_spring.pos_z = m_attack.pos_z; m_spring.pitch = m_attack.pitch; m_spring.yaw = m_attack.yaw;
            m_attack = Attack{};
        } else {
            const float s = std::sin((m_attack.t / attack) * PI_HALF);
            m_spring = Spring{};
            m_spring.pos_y = m_attack.pos_y * s; m_spring.pos_z = m_attack.pos_z * s;
            m_spring.pitch = m_attack.pitch * s; m_spring.yaw = m_attack.yaw * s;
        }
    }
    if (!m_attack.active && dt > 0) {
        float c = c_base;
        if (m_last_shot_t > 0) {
            const float since = (float)(t - m_last_shot_t);
            if (since < window) c = c + (c_sus - c) * (1.0f - since / window);
        }
        const float settle = std::max(REC_SETTLE_MULT_MIN, g_cfg.spring_settle_mult);
        const int steps = std::max(1, (int)std::floor(dt / g_cfg.substep_dt));
        const float sub = dt / steps;
        for (int i = 0; i < steps; ++i) {
            spring_step(m_spring.pos_y, m_spring.vel_y, k, c, settle, sub, REC_CH_POS);
            spring_step(m_spring.pos_z, m_spring.vel_z, k, c, settle, sub, REC_CH_POS);
            spring_step(m_spring.pitch, m_spring.vel_pitch, k, c, settle, sub, REC_CH_PITCH);
            spring_step(m_spring.yaw, m_spring.vel_yaw, k, c, settle, sub, REC_CH_YAW);
        }
        const float pos = std::fabs(m_spring.pos_y) + std::fabs(m_spring.pos_z), rot = std::fabs(m_spring.pitch) + std::fabs(m_spring.yaw);
        const float vel = std::fabs(m_spring.vel_y) + std::fabs(m_spring.vel_z) + std::fabs(m_spring.vel_pitch) + std::fabs(m_spring.vel_yaw);
        if (pos < REC_DONE_POS && rot < REC_DONE_ROT && vel < REC_DONE_VEL) begin_fadeout();
    }
}
void process_physics() {   // process_recoil_physics, once per frame
    const int f = frame_id();
    if (f == m_last_physics_frame) return;
    m_last_physics_frame = f;
    const auto& e = equipped();
    if (!vr_active() || !e.ok) { m_pending = 0; m_apply = Apply{}; return; }
    update_grip(e.id, e.weapon);
    const bool two = is_two_handed();
    const int n = std::min(m_pending, REC_KICKS_PER_FRAME_MAX);
    m_pending = 0;
    for (int i = 0; i < n; ++i) kick(e.weapon, e.id);
    update_spring(m_last_t > 0 ? std::min((float)(now_s() - m_last_t), REC_DT_MAX_S) : REC_DT_FIRST_S);
    m_apply.two_handed = two;
    refresh_offsets();
    capture_frame_offsets();
}

// ---- the IK patch (get_wrist_recoil_transform ... patch_ik_hand_target) ---------------------------------------------
Quat axis_angle(float angle, Vec3 axis) { const float h = angle * 0.5f, s = std::sin(h); return qnorm({axis.x * s, axis.y * s, axis.z * s, std::cos(h)}); }
float sign_of(float v) { return v >= 0 ? 1.0f : -1.0f; }
Pose recoiled(const Pose& in) {   // build_recoiled_hand_matrix (get_wrist_recoil_transform at scale 1)
    float pitch, yaw, py, pz;
    effective(pitch, yaw, py, pz);
    pitch *= sign_of(g_cfg.wrist_pitch_sign);
    yaw *= sign_of(g_cfg.wrist_yaw_sign);
    const Quat local = qnorm(qmul(axis_angle(pitch, {1, 0, 0}), axis_angle(yaw, {0, 1, 0})));
    const Quat rot = qnorm(qmul(in.q, local));
    const Vec3 off = rotate(rot, {0, py * std::max(0.0f, g_cfg.position_up_ratio), pz});
    return {in.p + off, rot, true};
}
void offset_of(const Pose& lh, const Pose& rh, Vec3& pos_rel, Quat& rot_rel) {   // compute_hand_offset_relative_to_weapon
    const Quat inv = qinv(rh.q);
    pos_rel = rotate(inv, lh.p - rh.p);
    rot_rel = qnorm(qmul(inv, lh.q));
}
Pose follow(const Pose& rh_post, Vec3 pos_rel, Quat rot_rel) {   // build_support_hand_matrix_from_weapon
    return {rh_post.p + rotate(rh_post.q, pos_rel), qnorm(qmul(rh_post.q, rot_rel)), true};
}
Pose reconstruct(const Pose& lh, Vec3 pos_rel, Quat rot_rel) {   // reconstruct_weapon_hand_matrix_from_support
    const Quat rq = qnorm(qmul(lh.q, qinv(rot_rel)));
    return {lh.p - rotate(rq, pos_rel), rq, true};
}
Pose motion_pose(const char* joint) { Pose p; p.ok = player::motion_joint(joint, p.p, p.q); return p; }
bool skeleton_grip(Vec3& pos_rel, Quat& rot_rel) {   // get_skeleton_grip_offset_relative_to_weapon
    if (m_fik.grip_frame == frame_id()) { pos_rel = m_fik.grip_pos; rot_rel = m_fik.grip_rot; return true; }
    const Pose l = motion_pose("l_arm_wrist"), r = motion_pose("r_arm_wrist");
    if (!l.ok || !r.ok) return false;
    offset_of(l, r, pos_rel, rot_rel);
    m_fik.grip_pos = pos_rel; m_fik.grip_rot = rot_rel; m_fik.grip_frame = frame_id();
    return true;
}
MO* target_of(MO* ik) { return field_obj(ik, "Target"); }
Pose read_target(MO* ik) { Pose p; p.ok = player::get_pose(target_of(ik), p.p, p.q); return p; }
bool write_target(MO* ik, const Pose& p) {
    if (!p.ok) return false;
    g_patches.fetch_add(1);
    return player::set_pose(target_of(ik), p.p, p.q);
}
bool patch_support(MO* lh_ik, const Pose& lh_pre) {   // patch_support_hand_ik_target + get_weapon_hand_pre_for_support
    Pose rh_pre;
    Vec3 pos_rel{};
    Quat rot_rel{0, 0, 0, 1};
    if (m_fik.rh_pre.ok) { rh_pre = m_fik.rh_pre; offset_of(lh_pre, rh_pre, pos_rel, rot_rel); }
    else if (Pose r = motion_pose("r_arm_wrist"); r.ok) { rh_pre = r; offset_of(lh_pre, rh_pre, pos_rel, rot_rel); }
    else if (skeleton_grip(pos_rel, rot_rel)) rh_pre = reconstruct(lh_pre, pos_rel, rot_rel);
    else return write_target(lh_ik, recoiled(lh_pre));
    return write_target(lh_ik, follow(recoiled(rh_pre), pos_rel, rot_rel));
}
void patch(MO* ik, bool right) {   // patch_ik_hand_target
    const Pose target = read_target(ik);
    if (!target.ok) return;
    if (right) {
        m_fik.rh_pre = target;
        const Pose rh_post = recoiled(target);
        if (m_fik.lh_pre.ok && m_fik.lh_ik != nullptr) {
            Vec3 pr; Quat rr;
            offset_of(m_fik.lh_pre, target, pr, rr);
            write_target(m_fik.lh_ik, follow(rh_post, pr, rr));
        }
        write_target(ik, rh_post);
        return;
    }
    if (support_follows_weapon()) {
        m_fik.lh_pre = target;
        m_fik.lh_ik = ik;
        patch_support(ik, target);
        return;
    }
    write_target(ik, recoiled(target));
}
void flush_pending() {   // flush_pending_recoil_before_ik
    if (m_pending > 0) {
        const int n = std::min(m_pending, REC_KICKS_PER_FRAME_MAX);
        m_pending = 0;
        const auto& s = player::now();
        for (int i = 0; i < n; ++i) kick(s.weapon, canonical(s.weapon_id));
        // seed this frame's offsets with the attack peak so every remaining IK pass this frame sees the same kick
        m_frame_off = {frame_id(), m_attack.pitch, m_attack.yaw, m_attack.pos_y, m_attack.pos_z};
        m_apply.has_recoil = true;
        return;
    }
    refresh_offsets();
}

int pre_ik_calc(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    if (argc < 2) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    auto* ik = (MO*)argv[1];
    std::lock_guard lk(g_mx);
    if (!vr_active()) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    const auto& s = player::now();
    const bool right = ik == s.ik_right;
    if (ik == nullptr || (!right && ik != s.ik_left)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;   // not a player hand
    if (!equipped().ok) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    const int f = frame_id();
    if (f == m_pass.frame && m_pass.idle_after_first && m_pending == 0) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    if (f != m_ik_sync_frame) {
        m_ik_sync_frame = f;
        m_pass.frame = f;
        m_pass.idle_after_first = false;
        if (f != m_ik_physics_sync_frame) { m_ik_physics_sync_frame = f; m_fik = FrameIk{}; process_physics(); }   // sync_recoil_for_ik
        else refresh_offsets();
        flush_pending();
    }
    if (!m_apply.has_recoil) { m_pass.idle_after_first = true; return REFRAMEWORK_HOOK_CALL_ORIGINAL; }
    if (!right && !(m_apply.two_handed || weapon_grip_active())) return REFRAMEWORK_HOOK_CALL_ORIGINAL;   // should_apply_recoil_to_ik_hand
    patch(ik, right);
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

// ---- the shot (on_pre_request_fire / on_post_request_fire, hooked on WeaponGunCore.shoot) ---------------------------
int chamber_count() {   // get_chamber_bullet_count
    auto* gun = player::now().gun;
    auto* m = gun ? find_method_deep(gun->get_type_definition(), "getBulletNum") : nullptr;
    return m ? m->call<int>(API::get()->get_vm_context(), (void*)gun) : -1;
}
bool cancel_after_fire() {   // should_cancel_recoil_after_fire
    if (flag(bridge::RF_BLOCK_FIRE_EMPTY)) return true;
    if (!flag(bridge::RF_MANUAL_RELOAD)) return false;
    if (flag(bridge::RF_MAG_DROPPED) || flag(bridge::RF_AMMO_DROPPED)) return true;
    return chamber_count() == 0;
}
bool block_queue() { return cancel_after_fire() || flag(bridge::RF_NEEDS_PUMP) || flag(bridge::RF_NEEDS_RACK); }
int has_loaded_ammo(MO* gun) {   // weapon_gun_has_loaded_ammo: 1 yes, 0 no, -1 unknown
    bool b = false;
    if (player::try_bool(gun, "get_isLoadNumInfinity", b) && b) return 1;
    if (player::try_bool(gun, "get_isMagazineEmpty", b)) return b ? 0 : 1;
    if (auto* m = find_method_deep(gun->get_type_definition(), "getBulletNum"))
        return m->call<int>(API::get()->get_vm_context(), (void*)gun) > 0 ? 1 : 0;
    if (player::try_bool(gun, "get_isLoadNumUnderOne", b)) return b ? 0 : 1;
    return -1;
}
int pre_shoot(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    std::lock_guard lk(g_mx);
    m_fire_had_ammo = false;
    if (argc < 2 || argv[1] == nullptr) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    auto* gun = (MO*)argv[1];
    const auto& s = player::now();
    if (gun != s.weapon && (s.gun == nullptr || gun != s.gun)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;   // is_player_weapon_gun
    m_fire_had_ammo = has_loaded_ammo(gun) != 0;
    if (m_fire_had_ammo && recoil_on() && !block_queue() && m_pending < REC_PENDING_MAX) ++m_pending;   // add_pending_recoil_shot
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}
void post_shoot(void**, REFrameworkTypeDefinitionHandle, unsigned long long) {
    std::lock_guard lk(g_mx);
    // a final live round reads empty after shoot returns: keep that shot's kick, cancel only a call that started empty
    if (!m_fire_had_ammo && cancel_after_fire()) { cancel_state(); m_pending = 0; }
    m_fire_had_ammo = false;
}

// ---- camera shake (install_camera_recoil_hooks) --------------------------------------------------------------------
int pre_camera_shake(int, void**, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    std::lock_guard lk(g_mx);
    return vr_active() && g_cfg.suppress_camera_recoil ? REFRAMEWORK_HOOK_SKIP_ORIGINAL : REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

void try_install() {
    if (!recoil_on()) return;   // the Lua installed its hooks only while recoil was on
    auto* tdb = API::get()->tdb();
    if (!g_installed_fire) {
        g_installed_fire = true;
        auto* m = tdb->find_method("app.WeaponGunCore", "shoot");
        if (m != nullptr) { m->add_hook(pre_shoot, post_shoot, false); LOGI("%s recoil: hooked app.WeaponGunCore.shoot", TAG); }
        else LOGW("%s recoil: app.WeaponGunCore.shoot NOT FOUND, no kicks", TAG);
    }
    if (!g_installed_ik) {
        g_installed_ik = true;
        auto* m = tdb->find_method("app.AnimIK2Bone", "calc");
        if (m != nullptr) { m->add_hook(pre_ik_calc, nullptr, false); LOGI("%s recoil: hooked app.AnimIK2Bone.calc", TAG); }
        else LOGW("%s recoil: app.AnimIK2Bone.calc NOT FOUND, the hands will not move", TAG);
    }
    if (g_cfg.suppress_camera_recoil && !g_installed_cam) {
        g_installed_cam = true;
        auto* m = tdb->find_method("app.PlayerCamera", "updateCameraShakeValue");
        if (m != nullptr) { m->add_hook(pre_camera_shake, nullptr, false); LOGI("%s recoil: hooked app.PlayerCamera.updateCameraShakeValue", TAG); }
        else LOGW("%s recoil: camera shake method NOT FOUND", TAG);
    }
}
} // namespace

void install() {
    std::lock_guard lk(g_mx);
    load_cfg();
    try_install();
}

void frame() {
    g_frame.fetch_add(1);
    std::lock_guard lk(g_mx);
    if (frame_id() % REC_CFG_CHECK_FRAMES == 0) check_cfg_file();
    try_install();   // the Lua re-checked each frame: turning recoil on later installs the hooks then
}

void physics_point() {
    std::lock_guard lk(g_mx);
    process_physics();
}

} // namespace vn::recoil
