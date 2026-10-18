// reload.cpp -- see reload.h. The state machine is Visceral RE7's / RE2's (same states and timings). Joint space as in
// RE2: the magazine joint's LOCAL pose is written, after the gun's own animation, and never read back the same frame.
#include "reload.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "settings.h"
#include "weapons.h"

#include <algorithm>
#include <string>

namespace vn::reload {

using namespace joints;
using namespace vn::settings;
using weapons::Reload;

namespace {
enum class St { SEATED, SLIDE_OUT, FALL, OUT, IN_HAND, HAND_FALL, INSERT };
const char* st_name(St s) {
    switch (s) {
    case St::SEATED: return "seated";       case St::SLIDE_OUT: return "sliding out"; case St::FALL: return "falling";
    case St::OUT: return "out";             case St::IN_HAND: return "in the left hand";
    case St::HAND_FALL: return "dropped from the hand"; case St::INSERT: return "going in";
    }
    return "?";
}

St g_st = St::SEATED;
const weapons::Weapon* g_w = nullptr;
std::string g_id;                 // canonical
MO* g_gun = nullptr;              // this frame's objects (valid for the frame only)
MO* g_wtf = nullptr;
MO* g_joint = nullptr;            // the magazine joint, when found
MO* g_hand = nullptr;             // the player's left hand joint
float g_t0 = 0.0f;
Vec3 g_rest_pos{}, g_rest_scale{1, 1, 1};
Quat g_rest_rot{0, 0, 0, 1};
Vec3 g_fall_from{};
Quat g_fall_rot{0, 0, 0, 1};
bool g_scale_restore = false;
float g_last_grab = -10.0f, g_last_dock = -10.0f;
bool g_pouch_ours = false;        // inside our own pouch spot (used when Andyalpa's ammo spot never reports)

int g_mag_rounds = 0;             // rounds that left with the magazine
bool g_dry = false;               // the gun was empty when its magazine came out
int g_stash = 0;                  // rounds waiting for a rack / pump
MO* g_drop_gun = nullptr;
bool g_round_in_hand = false;
float g_closest = 99.0f;          // the nearest the held magazine / round came to where it goes in (logged on let-go)
thread_local bool t_blocked = false;

void set_state(St s, const char* why) {
    LOGI("%s reload: %s magazine %s -> %s (%s)", TAG, g_id.c_str(), st_name(g_st), st_name(s), why);
    g_st = s;
    g_t0 = now_s();
}

bool pose_lock() { return bridge::flag(bridge::S_POSE_LOCK); }
bool in_play() { return bridge::live() && bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE); }
Vec3 mag_out_pos() { return g_rest_pos - Vec3{0, RELOAD_MAG_DROP_M, 0}; }

Quat quat_from_ypr(float yaw, float pitch, float roll) {   // yaw about Z, then pitch about Y, then roll about X (degrees)
    const float d = 3.14159265f / 360.0f;
    const Quat qz{0, 0, std::sin(yaw * d), std::cos(yaw * d)};
    const Quat qy{0, std::sin(pitch * d), 0, std::cos(pitch * d)};
    const Quat qx{std::sin(roll * d), 0, 0, std::cos(roll * d)};
    return qnorm(qmul(qmul(qz, qy), qx));
}

// ---- the frame's objects -------------------------------------------------------------------------------------------
void resolve_frame() {
    const auto& s = player::now();
    g_gun = s.gun;
    g_wtf = s.weapon_tf;
    g_joint = (MAG_JOINT_ANIMATE && g_w != nullptr && g_w->reload == Reload::MAG && g_wtf) ? joint_by_name(g_wtf, L"_04") : nullptr;
    g_hand = nullptr;
    for (const wchar_t* n : {L"l_arm_wrist", L"L_Hand", L"l_hand"}) {
        if ((g_hand = joint_by_name(s.tf, n)) != nullptr) {
            static const wchar_t* logged = nullptr;
            if (logged != n) { logged = n; LOGI("%s reload: the left hand joint is %ls", TAG, n); }
            break;
        }
    }
}

bool to_weapon_local(Vec3 world, Quat wrot_in, Vec3& lpos, Quat& lrot) {
    Vec3 wp;
    Quat wr;
    if (!get_v3(XFORM, g_wtf, "get_Position", wp) || !get_q(XFORM, g_wtf, "get_Rotation", wr)) return false;
    const Quat inv = qinv(qnorm(wr));
    lpos = rotate(inv, world - wp);
    lrot = qnorm(qmul(inv, wrot_in));
    return true;
}
bool from_weapon_local(Vec3 lpos, Quat lrot, Vec3& world, Quat& wrot) {
    Vec3 wp;
    Quat wr;
    if (!get_v3(XFORM, g_wtf, "get_Position", wp) || !get_q(XFORM, g_wtf, "get_Rotation", wr)) return false;
    world = wp + rotate(qnorm(wr), lpos);
    wrot = qnorm(qmul(qnorm(wr), lrot));
    return true;
}

bool held_pose(Vec3& pos, Quat& rot) {   // the magazine in the left hand: the hand joint plus the hold
    Vec3 hp;
    Quat hr;
    if (!get_v3(JOINT, g_hand, "get_Position", hp) || !get_q(JOINT, g_hand, "get_Rotation", hr)) return false;
    hr = qnorm(hr);
    pos = hp + rotate(hr, Vec3{MAG_HOLD[0], MAG_HOLD[1], MAG_HOLD[2]});
    rot = qnorm(qmul(hr, quat_from_ypr(MAG_HOLD[3], MAG_HOLD[4], MAG_HOLD[5])));
    return true;
}

// ---- where things go in, in the room: at the gun hand (pistols) or ahead of it along the barrel (long guns) ----------
float dock_dist() {
    const Vec3 l = bridge::hand_pos(bridge::LEFT), r = bridge::hand_pos(bridge::RIGHT);
    if (g_w->shape == weapons::Shape::PISTOL) return dist(l, r);
    const Vec3 fwd = rotate(bridge::view_quat(bridge::S_RROT), Vec3{0, 0, -1});   // OpenXR: a controller points along -Z
    return dist(l, r + fwd * DOCK_LONG_AHEAD_M);
}
float dock_need() { return g_w->shape == weapons::Shape::PISTOL ? DOCK_PISTOL_M : DOCK_LONG_M; }

// ---- ammo ------------------------------------------------------------------------------------------------------------
void set_loaded_on(MO* gun, int n) {   // a gun no longer in hand (put away mid-reload)
    auto* w = call_ptr(gun, "get_work");
    if (auto* m = w ? find_method_deep(w->get_type_definition(), "set_includeStackSize(System.Int32)") : nullptr)
        m->call<void>(API::get()->get_vm_context(), (void*)w, (int32_t)std::max(0, n));
}

// a new magazine: the dropped one's rounds back, then the game's own reload tops it up from the carried ammo
void fill_magazine() {
    player::set_loaded(g_mag_rounds);
    const int took = player::game_reload(-1);
    const int total = player::loaded();
    g_mag_rounds = 0;
    g_drop_gun = nullptr;
    if (g_dry && total > 0 && g_w->rack) {
        g_stash = total;
        player::set_loaded(0);
        rack::need("a magazine into an empty gun");
    }
    LOGI("%s reload: %s new magazine: %d rounds (%d from the carried ammo, capacity %d)%s", TAG, g_id.c_str(), total, took, player::capacity(),
         g_stash > 0 ? ", waiting for a rack" : "");
    g_dry = false;
}

void insert_round() {
    const int cap = player::capacity(), have = player::loaded() + g_stash;
    if (cap > 0 && have >= cap) { LOGI("%s reload: %s is full (%d)", TAG, g_id.c_str(), have); return; }
    const bool empty = player::loaded() == 0 || g_stash > 0;
    if (player::game_reload(1) < 1) { LOGI("%s reload: no round went in (none carried?)", TAG); return; }
    if (g_w->pump && empty) {   // shells into an empty pump gun wait for the pump
        g_stash += player::loaded();
        player::set_loaded(0);
        rack::need("shells into an empty pump gun");
    }
    LOGI("%s reload: %s round in: loaded %d, waiting for the pump %d, carried %d", TAG, g_id.c_str(), player::loaded(), g_stash, player::reserve());
}

// the gun's own magazine switch (WeaponGunCore.switchMagazineDisp / resetMagazineDisp, found in the type list):
// the magazine disappears from the gun while it is out, whichever part it is
void mag_part_shown(bool show);
void magazine_shown(bool show) {
    mag_part_shown(show);
    if (show) call_ptr(g_gun, "resetMagazineDisp");
    else if (auto* m = g_gun ? find_method_deep(g_gun->get_type_definition(), "switchMagazineDisp(System.Boolean)") : nullptr)
        m->call<void>(API::get()->get_vm_context(), (void*)g_gun, false);
}

// unknown carried ammo (-1) = try anyway: the game's own reload then decides (and logs before / after)
bool supply() { const int r = player::reserve(); return player::unlimited() || r != 0 || g_mag_rounds > 0; }

// the magazine as the gun's mesh part (WeaponGunCore.NormalMagazinePartsNo, ...Customized when customizeMagazine):
// hidden after the gun's animation while it is out (switchMagazineDisp alone showed nothing in the headset, 2026-10-18)
int mag_part() {
    if (g_gun == nullptr) return -1;
    bool custom = false;
    player::try_bool(g_gun, "get_customizeMagazine", custom);
    const int* p = field_ptr<int>(g_gun, custom ? "NormalMagazinePartsNoCustomized" : "NormalMagazinePartsNo");
    return p != nullptr ? *p : -1;
}
void mag_part_shown(bool show) {
    const int part = mag_part();
    auto* go = call_ptr(g_gun, "get_GameObject");
    auto* mesh = component(go, "via.render.Mesh");
    auto* m = player::overload(mesh, "setPartsEnable", 2);
    static MO* told = nullptr;
    if (told != g_gun) {   // once per gun: what the hide can and cannot reach
        told = g_gun;
        LOGI("%s reload: magazine part %d, gun object %s, mesh %s, setPartsEnable %s", TAG, part, go ? read_string(call_ptr(go, "get_Name")).c_str() : "none",
             mesh ? type_name(mesh).c_str() : "NOT FOUND", m ? "found" : "NOT FOUND");
    }
    if (m == nullptr || part < 0) return;
    m->call<void>(API::get()->get_vm_context(), (void*)mesh, (uint64_t)part, show);
}
void hide_mag_part() { mag_part_shown(false); }

// ---- the joint writes (only when the magazine joint was found) -------------------------------------------------------
void write_local(Vec3 p, Quat q) {
    set_any(JOINT, g_joint, "set_LocalPosition", &p);
    set_any(JOINT, g_joint, "set_LocalRotation", &q);
}
void write_world(Vec3 p, Quat q) {
    set_any(JOINT, g_joint, "set_Position", &p);
    set_any(JOINT, g_joint, "set_Rotation", &q);
}
void write_scale(Vec3 s) { set_any(JOINT, g_joint, "set_LocalScale", &s); }

void pose_joint() {
    if (g_joint == nullptr || g_w == nullptr) return;
    const float t = now_s() - g_t0;
    switch (g_st) {
    case St::SEATED:
        if (g_scale_restore) { write_scale(g_rest_scale); g_scale_restore = false; }
        return;
    case St::SLIDE_OUT:
        write_local(lerp(g_rest_pos, mag_out_pos(), ease(t / RELOAD_SLIDE_SEC)), g_rest_rot);
        return;
    case St::FALL:
    case St::HAND_FALL: {
        const float u = std::fmin(1.0f, t / RELOAD_FALL_SEC);
        write_world(g_fall_from - Vec3{0, RELOAD_FALL_M * u * u, 0}, g_fall_rot);
        return;
    }
    case St::OUT:
        write_scale(Vec3{0, 0, 0});
        write_local(g_rest_pos, g_rest_rot);
        return;
    case St::IN_HAND: {
        Vec3 wp, lp;
        Quat wr, lr;
        if (!held_pose(wp, wr) || !to_weapon_local(wp, wr, lp, lr)) return;
        write_scale(g_rest_scale);
        write_local(lp, lr);
        return;
    }
    case St::INSERT:
        write_scale(g_rest_scale);
        write_local(lerp(mag_out_pos(), g_rest_pos, ease(t / RELOAD_INSERT_SEC)), g_rest_rot);
        return;
    }
}

void hand_checks() {
    if (pose_lock() || g_w == nullptr) return;
    const bool mag = g_w->reload == Reload::MAG && g_st == St::IN_HAND;
    if (!mag && !g_round_in_hand) return;
    if (!bridge::held(bridge::S_LGRIP)) {
        LOGI("%s reload: let go; it came within %.3f m of where it goes in (needs %.2f)", TAG, g_closest, dock_need());
        g_closest = 99.0f;
        if (g_round_in_hand) { g_round_in_hand = false; LOGI("%s reload: round let go", TAG); return; }
        Quat wr;
        if (!held_pose(g_fall_from, wr)) g_fall_from = Vec3{0, 0, 0};
        g_fall_rot = wr;
        set_state(g_joint != nullptr ? St::HAND_FALL : St::OUT, "left grip let go");
        return;
    }
    const float d = dock_dist(), now = now_s();
    g_closest = std::fmin(g_closest, d);
    if (d > dock_need() || now - g_last_dock < RELOAD_DOCK_COOLDOWN_SEC) return;
    g_last_dock = now;
    bridge::rumble(bridge::LEFT, RELOAD_INSERT_BUZZ_AMP, RELOAD_INSERT_BUZZ_SEC, RELOAD_BUZZ_HZ);
    if (mag) {
        set_state(St::INSERT, "brought to the gun");
        magazine_shown(true);
        LOGI("%s reload: insert at %.3f m (need %.2f)", TAG, d, dock_need());
    } else {
        g_round_in_hand = false;
        insert_round();
    }
}

void put_back_on_swap(const char* why) {
    if (g_round_in_hand) { g_round_in_hand = false; LOGI("%s reload: round put back (%s)", TAG, why); }
    MO* old = g_drop_gun != nullptr ? g_drop_gun : g_gun;
    if (g_stash > 0 && is_managed(old)) { set_loaded_on(old, g_stash); LOGI("%s reload: %s: %d rounds that waited for a rack put in (%s)", TAG, g_id.c_str(), g_stash, why); }
    g_stash = 0;
    if (g_st == St::SEATED) return;
    if (is_managed(g_drop_gun)) set_loaded_on(g_drop_gun, g_mag_rounds);
    if (g_joint != nullptr) write_scale(g_rest_scale);
    if (is_managed(g_drop_gun)) call_ptr(g_drop_gun, "resetMagazineDisp");
    mag_part_shown(true);   // g_gun is still the old gun here
    LOGI("%s reload: %s magazine put back as it was (%s): %d rounds", TAG, g_id.c_str(), why, g_mag_rounds);
    g_mag_rounds = 0;
    g_drop_gun = nullptr;
    g_dry = false;
    g_st = St::SEATED;
}

void begin_drop() {
    const int n = player::loaded();
    if (n < 0) { LOGW("%s reload: %s: no loaded-ammo call found, no drop (see type_probe.txt)", TAG, g_id.c_str()); return; }
    g_mag_rounds = n;
    g_dry = n == 0;
    g_drop_gun = g_gun;
    if (!player::set_loaded(0)) { LOGW("%s reload: %s: no way to empty the gun found, no drop (see type_probe.txt)", TAG, g_id.c_str()); g_drop_gun = nullptr; return; }
    Vec3 p, s;
    Quat q;
    if (g_joint != nullptr && get_v3(JOINT, g_joint, "get_LocalPosition", p) && get_q(JOINT, g_joint, "get_LocalRotation", q)) {
        if (!get_v3(JOINT, g_joint, "get_LocalScale", s) || s.x < 0.01f) s = Vec3{1, 1, 1};
        g_rest_pos = p;
        g_rest_rot = qnorm(q);
        g_rest_scale = s;
        set_state(St::SLIDE_OUT, "right B");
    } else {
        set_state(St::OUT, "right B");
    }
    magazine_shown(false);
    LOGI("%s reload: drop with %d rounds in it, %d carried", TAG, g_mag_rounds, player::reserve());
}

void log_joints() {
    auto* joints = call_ptr(g_wtf, "get_Joints");
    int n = call_direct<int>(joints, "get_Length", 0);
    const bool list = n <= 0;   // Andyalpa's RE7 scan used get_Count / get_Item (2026-10-18: get_Length gave nothing)
    if (list) n = call_direct<int>(joints, "get_Count", 0);
    LOGI("%s joints of %s: %d (%s), magazine mesh part %d, gun transform %s", TAG, g_id.c_str(), n, joints ? type_name(joints).c_str() : "no list",
         mag_part(), g_wtf ? "found" : "NOT FOUND");
    if (n <= 0) {   // backup: ask for the usual numbered joint names one by one
        for (int k = 0; k <= 20; ++k) {
            wchar_t nm[8];
            swprintf(nm, 8, L"_%02d", k);
            auto* j = joint_by_name(g_wtf, nm);
            Vec3 p{};
            if (j != nullptr && get_v3(JOINT, j, "get_LocalPosition", p)) LOGI("%s joint %s %ls local %.3f %.3f %.3f", TAG, g_id.c_str(), nm, p.x, p.y, p.z);
        }
    }
    for (int i = 0; i < n && i < JOINT_LOG_MAX; ++i) {
        auto* j = list ? call_ptr(joints, "get_Item", {(void*)(intptr_t)i}) : call_ptr(joints, "GetValue(System.Int32)", {(void*)(intptr_t)i});
        Vec3 p{};
        get_v3(JOINT, j, "get_LocalPosition", p);
        LOGI("%s joint %s[%d] %s local %.3f %.3f %.3f", TAG, g_id.c_str(), i, read_string(call_ptr(j, "get_Name")).c_str(), p.x, p.y, p.z);
    }
}

void pouch_grab() {
    if (!managed_now() || !in_play()) return;
    const float now = now_s();
    if (now - g_last_grab < RELOAD_GRAB_COOLDOWN_SEC) return;
    g_last_grab = now;
    if (g_w->reload == Reload::ROUND) {
        if (g_round_in_hand) return;
        const int cap = player::capacity();
        if (!supply() || (cap > 0 && player::loaded() + g_stash >= cap)) {
            LOGI("%s reload: nothing to take (carried %d, loaded %d of %d)", TAG, player::reserve(), player::loaded() + g_stash, cap);
            bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
            return;
        }
        g_round_in_hand = true;
        bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
        LOGI("%s reload: a round in the left hand (carried %d)", TAG, player::reserve());
        return;
    }
    if (g_st != St::OUT) return;
    if (!supply()) {
        LOGI("%s reload: the ammo spot is empty (no rounds carried, none in the dropped magazine)", TAG);
        bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
        return;
    }
    set_state(St::IN_HAND, "taken from the ammo spot");
    bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
}

void track_pouch() {   // our own spot, beside Andyalpa's (his reports through the bridge)
    Vec3 f = rotate(bridge::hmd_rot(), Vec3{0, 0, -1});
    f.y = 0;
    const float len = std::sqrt(f.x * f.x + f.z * f.z);
    f = len < 1e-4f ? Vec3{0, 0, -1} : f * (1.0f / len);
    const Vec3 right{-f.z, 0, f.x};
    const Vec3 spot = bridge::hmd_pos() + right * LEFT_HIP_POUCH[0] + Vec3{0, LEFT_HIP_POUCH[1], 0} + f * LEFT_HIP_POUCH[2];
    const float d = dist(bridge::hand_pos(bridge::LEFT), spot);
    if (!g_pouch_ours && d < POUCH_ENTER_M) g_pouch_ours = true;
    else if (g_pouch_ours && d > POUCH_LEAVE_M) g_pouch_ours = false;
}

// ---- the game's own reload request, off for our guns (names tried; the probe file lists the real ones) --------------
int pre_reload_request(int, void**, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    t_blocked = managed_now();
    if (!t_blocked) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    static int n = 0;
    if (++n <= 5 || n % 2000 == 0) LOGI("%s reload: the game's reload skipped (#%d; the game asks every frame)", TAG, n);
    return REFRAMEWORK_HOOK_SKIP_ORIGINAL;
}
void post_reload_request(void** ret, REFrameworkTypeDefinitionHandle, unsigned long long) {
    if (t_blocked && ret != nullptr) *ret = nullptr;
    t_blocked = false;
}
} // namespace

bool managed_now() { return RELOAD_ON && g_w != nullptr && g_w->reload != Reload::NONE && g_gun != nullptr && bridge::live(); }
bool mag_out() { return managed_now() && g_w->reload == Reload::MAG && g_st != St::SEATED; }
bool session_active() { return mag_out() || g_round_in_hand; }
bool mag_in_hand() { return managed_now() && g_w->reload == Reload::MAG && (g_st == St::IN_HAND || g_st == St::INSERT); }
bool round_in_hand() { return managed_now() && g_round_in_hand; }
bool in_pouch() { return bridge::flag(bridge::S_IN_AMMO_ZONE) || g_pouch_ours; }

void on_racked() {
    if (g_stash <= 0) return;
    player::set_loaded(player::loaded() + g_stash);
    LOGI("%s reload: %s racked: %d rounds go in", TAG, g_id.c_str(), g_stash);
    g_stash = 0;
}

void install() {
    auto* tdb = API::get()->tdb();
    int n = 0;
    for (const char* t : {"app.PlayerGun", "app.PlayerGunFPS", "app.PlayerGunPl2001", "app.PlayerGunPl2001FPS", "app.WeaponGunCore"}) {
        auto* td = tdb->find_type(t);
        if (td == nullptr) continue;
        for (const char* name : {"tryReload", "requestReload"}) {
            auto* m = td->find_method(name);
            if (m == nullptr || m->get_declaring_type() != td) continue;
            m->add_hook(pre_reload_request, post_reload_request, false);
            ++n;
            LOGI("%s reload: hooked %s.%s (the game's own reload, skipped for our guns)", TAG, t, name);
        }
    }
    if (n == 0) LOGW("%s reload: no tryReload / requestReload found: the game's own reload stays on (see type_probe.txt)", TAG);
}

void frame() {
    if (!RELOAD_ON) return;
    const std::string id = weapons::canonical(player::now().weapon_id);
    if (id != g_id) {
        put_back_on_swap(id.empty() ? "weapon put away" : "weapon changed");
        g_id = id;
        g_w = weapons::find(id);
        resolve_frame();
        if (!id.empty()) {
            LOGI("%s weapon: %s (%s)%s, magazine part %s", TAG, id.c_str(), weapons::name(id), g_w == nullptr ? "" :
                 g_w->reload == Reload::MAG ? ": manual magazine" : g_w->reload == Reload::ROUND ? ": single rounds" : ": no reload",
                 g_joint != nullptr ? "_04 found" : "not found");
            static std::string seen;
            if (seen.find("|" + id + "|") == std::string::npos) { seen += "|" + id + "|"; log_joints(); }
            player::probe_types();
        }
    }
    resolve_frame();
    track_pouch();
    if (g_w == nullptr || g_gun == nullptr) return;

    if (g_w->reload == Reload::MAG) {
        const float t = now_s() - g_t0;
        switch (g_st) {
        case St::SLIDE_OUT:
            if (t >= RELOAD_SLIDE_SEC) {
                if (!from_weapon_local(mag_out_pos(), g_rest_rot, g_fall_from, g_fall_rot)) g_fall_from = Vec3{0, 0, 0};
                set_state(St::FALL, "out of the magwell");
            }
            break;
        case St::FALL:
        case St::HAND_FALL:
            if (t >= RELOAD_FALL_SEC) set_state(St::OUT, "on the floor");
            break;
        case St::INSERT:
            if (t >= RELOAD_INSERT_SEC) {
                set_state(St::SEATED, "seated");
                g_scale_restore = true;
                magazine_shown(true);
                fill_magazine();
            }
            break;
        default:
            break;
        }
        if (in_play() && bridge::pressed(bridge::S_RB) && g_st == St::SEATED && !rack::active()) begin_drop();
    }
    if (in_pouch() && bridge::pressed(bridge::S_LGRIP)) pouch_grab();
}

void late_point() {
    if (!managed_now()) return;
    hand_checks();
    if (g_w->reload == Reload::MAG) pose_joint();
    if (mag_out() && g_st != St::INSERT) hide_mag_part();
}

void render_point() {
    if (managed_now() && g_w->reload == Reload::MAG) pose_joint();
    if (mag_out() && g_st != St::INSERT) hide_mag_part();
}

} // namespace vn::reload
