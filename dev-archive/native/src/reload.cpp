// reload.cpp -- see reload.h. The state machine is the RE7 RELOADED mod's / Visceral RE2's (same states and timings). Joint space as in
// RE2: the magazine joint's LOCAL pose is written, after the gun's own animation, and never read back the same frame.
#include "reload.h"
#include "shellclip.h"
#include "shells.h"
#include "reload_internal.h"
#include "bridge.h"
#include "ghosthand.h"
#include "joints.h"
#include "player.h"
#include "breech.h"
#include "gate.h"
#include "pairs.h"
#include "rack.h"
#include "rack_right.h"
#include "settings.h"
#include "weapons.h"
#include "zones.h"

#include <algorithm>
#include <string>

namespace vn::reload {

using namespace joints;
using namespace vn::settings;
using weapons::Reload;

using namespace detail;   // the state shared with reload_pose.cpp and its pose helpers (reload_internal.h)

// the state, shared with reload_pose.cpp (declared in reload_internal.h)
namespace detail {
St g_st = St::SEATED;
const weapons::Weapon* g_w = nullptr;
std::string g_id;                 // canonical
MO* g_gun = nullptr;              // this frame's objects (valid for the frame only)
MO* g_wtf = nullptr;
MO* g_joint = nullptr;            // the magazine joint, when found
// 2026-10-24 (Tefa: "when ejecting the mag, only the bottom slab of the mag drops out, not the whole magazine"): the LEMI
// also has "Magazine_second"; it is carried along with "Magazine", keeping where it sat against it at the drop
MO* g_joint2 = nullptr;
MO* g_hand = nullptr;             // the player's left hand joint
float g_t0 = 0.0f;
Vec3 g_rest_pos{}, g_rest_scale{1, 1, 1};
Quat g_rest_rot{0, 0, 0, 1};
Vec3 g_fall_from{};
Quat g_fall_rot{0, 0, 0, 1};
bool g_scale_restore = false;
bool g_round_in_hand = false;
MO* g_shell = nullptr;            // the gun's own shell joint ("Bullet"), carried in the left hand for single-round guns
Vec3 g_shell_rest{};
Quat g_shell_rest_rot{0, 0, 0, 1};
bool g_shell_have_rest = false;
int g_pocket = 0;                 // 2026-10-27: rounds taken out of the gun by hand (the GM 79), loaded again before the carried ammo
int g_rounds_n = 0;               // 2026-10-27: a revolver's rounds in the left hand (one grab = the free chambers); 1 for other guns
int g_mag_rounds = 0;             // rounds that left with the magazine   // (moved into detail 2026-11-05: magdisp reads them)
bool g_same_mag = false;          // 2026-10-31: the magazine in the hand is the one pulled from this gun: it goes back with its own rounds
} // namespace detail

namespace {
const char* st_name(St s) {
    switch (s) {
    case St::SEATED: return "seated";       case St::SLIDE_OUT: return "sliding out"; case St::FALL: return "falling";
    case St::OUT: return "out";             case St::IN_HAND: return "in the left hand";
    case St::HAND_FALL: return "dropped from the hand"; case St::INSERT: return "going in";
    case St::RAIL: return "in the grip, moved by the hand";
    }
    return "?";
}

bool g_hand_on_mag = false;       // seated with LG still held since the insert (the hand stays on the magazine)
float g_last_grab = -10.0f, g_last_dock = -10.0f;
bool g_pouch_ours = false;        // inside our own pouch spot (used when Andyalpa's ammo spot never reports)

int g_chamber = 0;                // 2026-10-31: the round kept in the chamber while the magazine is out (CHAMBER_ROUND)
bool g_lt_to_seat = false;        // a magazine pulled out by hand: it goes back in only on a fresh LT press at the well (Tefa 2026-10-25)
bool g_dry = false;               // the gun was empty when its magazine came out
int g_stash = 0;                  // rounds waiting for a rack / pump
MO* g_drop_gun = nullptr;
float g_closest = 99.0f;          // the nearest the held magazine / round came to where it goes in (logged on let-go)
thread_local bool t_blocked = false;

void set_state(St s, const char* why) {
    LOGI("%s reload: %s magazine %s -> %s (%s)", TAG, g_id.c_str(), st_name(g_st), st_name(s), why);
    g_st = s;
    g_t0 = now_s();
}

bool pose_lock() { return bridge::flag(bridge::S_POSE_LOCK); }
bool in_play() { return bridge::live() && bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE); }
bool pistol_mag() { return g_w != nullptr && g_w->reload == Reload::MAG && g_w->shape == weapons::Shape::PISTOL; }

// ---- the frame's objects -------------------------------------------------------------------------------------------
void resolve_frame() {
    const auto& s = player::now();
    g_gun = s.gun;
    g_wtf = s.weapon_tf;
    g_joint = (MAG_JOINT_ANIMATE && g_w != nullptr && g_w->reload == Reload::MAG && g_wtf) ? joint_by_name(g_wtf, L"Magazine") : nullptr;   // Village names its gun joints (headset log 2026-10-18)
    g_joint2 = (g_joint != nullptr && !bridge::experiment(bridge::EX_MAG_NO_SECOND)) ? joint_by_name(g_wtf, L"Magazine_second") : nullptr;
    // the round carried in the hand: the M1897's "Bullet"; others from the 2026-10-24 gun survey: W870
    // ShotgunCartridge_FK_0, Handcannon Bullet00, Wolfsbane Five_Bullet00 (in the cylinder), GM 79 Ammo01 (in the carrier)
    g_shell = nullptr;
    if (g_w != nullptr && g_w->reload == Reload::ROUND && g_wtf)
        for (const wchar_t* n : {L"Bullet", L"ShotgunCartridge_FK_0", L"Bullet00", L"Five_Bullet00", L"Ammo01"})
            if ((g_shell = joint_by_name(g_wtf, n)) != nullptr) break;
    if (g_shell != nullptr && !g_shell_have_rest && !g_round_in_hand &&
        get_v3(JOINT, g_shell, "get_LocalPosition", g_shell_rest) && get_q(JOINT, g_shell, "get_LocalRotation", g_shell_rest_rot))
        g_shell_have_rest = true;
    g_hand = nullptr;
    for (const wchar_t* n : {L"l_arm_wrist", L"L_Hand", L"l_hand"}) {
        if ((g_hand = joint_by_name(s.tf, n)) != nullptr) {
            static const wchar_t* logged = nullptr;
            if (logged != n) { logged = n; LOGI("%s reload: the left hand joint is %ls", TAG, n); }
            break;
        }
    }
}


// ---- where things go in, in the room: at the gun hand (pistols) or ahead of it along the barrel (long guns) ----------
// 2026-10-18 headset run: the point "0.20 m ahead along the barrel" from the controller's turn landed 0.4-0.9 m from
// Tefa's hand, so long guns now use the plain distance between the two controllers too, with a wider reach
// long guns (Tefa 2026-10-19: 10 cm): from the magazine / shell in the hand to its place on the gun (the magazine's seat,
// the shell joint's rest), both in the world; pistols keep the controller distance, which works
// 2026-10-19 headset run: computed from the joint's local numbers and the gun object, the spot came out 0.35 / 0.60 m
// away from where Tefa brought the magazine / shell. Now it is measured: the magazine joint's (or the shell joint's) own
// world position, taken while it still sits in the gun, kept relative to the right hand target, which carries the gun.
bool g_port_ok = false;
Vec3 g_port_rel{};
bool rh_target(Vec3& p, Quat& q) { return player::get_pose(field_obj(player::now().ik_right, "Target"), p, q); }
void capture_port(MO* joint) {
    Vec3 jp{}, rp{};
    Quat rq{0, 0, 0, 1};
    g_port_ok = joint != nullptr && get_v3(JOINT, joint, "get_Position", jp) && rh_target(rp, rq);
    if (g_port_ok) g_port_rel = rotate(qinv(rq), jp - rp);
}
bool port_world(Vec3& out) {
    Vec3 rp;
    Quat rq;
    if (!g_port_ok || !rh_target(rp, rq)) return false;
    out = rp + rotate(rq, g_port_rel);
    return true;
}
float dock_dist() {
    Vec3 port, item;
    Quat q;
    Vec3 ic;
    float ir;   // 2026-10-27: the GM 79's grenade goes in at its INSERT point (Grab Zones moves it)
    if (g_w->breech == weapons::Breech::BREAK && pairs::part_center(zones::INSERT, ic, ir)) {
        Vec3 lp;
        if (held_pose(item, q)) return dist(item, ic);
        if (bridge::room_to_world(bridge::hand_pos(bridge::LEFT), lp)) return dist(lp, ic);
    }
    // 2026-10-30 (Tefa: "sphere still did not show at the bottom of the mag chamber to tune how far the mag goes in from"):
    // a handgun's magazine goes in at its WELL too, as a long gun's does, once the well is known (measured while a magazine
    // sat in it); until then the old rule, the two controllers within DOCK_PISTOL_M
    if ((g_w->shape == weapons::Shape::LONG || g_w->reload == Reload::MAG) && port_world(port) && held_pose(item, q)) return dist(item, zones::center(zones::WELL, port));
    return dist(bridge::hand_pos(bridge::LEFT), bridge::hand_pos(bridge::RIGHT));
}
float dock_need() {
    Vec3 port, ic;
    float ir;
    if (g_w->breech == weapons::Breech::BREAK && pairs::part_center(zones::INSERT, ic, ir)) return ir;
    if (g_w->shape == weapons::Shape::LONG) return port_world(port) ? zones::radius(zones::WELL) : DOCK_LONG_M;
    if (g_w->reload == Reload::MAG && port_world(port)) return zones::radius(zones::WELL);   // 2026-10-30: the handgun's well
    return DOCK_PISTOL_M;
}
// 2026-10-18 headset run: a shell went in 0.6 s after the grab, still at the hip (a long gun held low is within reach of
// it). Now the left controller must also be in front of the body and up at gun height.
bool at_gun_height() {
    const Vec3 h = bridge::hmd_pos(), l = bridge::hand_pos(bridge::LEFT);
    Vec3 f = rotate(bridge::hmd_rot(), Vec3{0, 0, -1});
    f.y = 0;
    const float len = std::sqrt(f.x * f.x + f.z * f.z);
    f = len < 1e-4f ? Vec3{0, 0, -1} : f * (1.0f / len);
    const Vec3 d = l - h;
    return d.x * f.x + d.z * f.z >= DOCK_IN_FRONT_M && d.y >= -DOCK_BELOW_HEAD_M;
}

// ---- ammo ------------------------------------------------------------------------------------------------------------
// the game's HUD does not notice our ammo writes (Tefa: the count only changed after the next shot): fire the gun's own
// ReloadHandler (WeaponGunCore, a System.Action) the way a finished reload would
void tell_hud() {
    bridge::put(bridge::S_HUD_PING, bridge::view(bridge::S_HUD_PING) + 1.0f);   // the Lua side refreshes the game's display
    auto* h = field_obj(g_gun, "ReloadHandler");
    if (h == nullptr) return;
    auto* m = player::overload(h, "Invoke", 0);
    if (m != nullptr) m->call<void>(API::get()->get_vm_context(), (void*)h);
}

void set_loaded_on(MO* gun, int n) {   // a gun no longer in hand (put away mid-reload)
    auto* w = call_ptr(gun, "get_work");
    if (auto* m = is_managed(w) ? find_method_deep(w->get_type_definition(), "set_includeStackSize(System.Int32)") : nullptr)
        m->call<void>(API::get()->get_vm_context(), (void*)w, (int32_t)std::max(0, n));
}

// a new magazine: the dropped one's rounds back, then the game's own reload tops it up from the carried ammo
void fill_magazine() {
    const int in_chamber = g_chamber > 0 ? std::max(0, player::loaded()) : 0;   // still there unless it was fired meanwhile
    g_chamber = 0;
    if (CHAMBER_ROUND && g_w != nullptr && g_w->rack && !g_w->pump && in_chamber == 0) g_dry = true;   // fired dry meanwhile (or never had one): rack
    player::set_loaded(g_mag_rounds + in_chamber);
    // 2026-10-31 (Tefa, "real gun"): the same magazine back in holds just its own rounds; only a fresh one from the pouch is
    // filled from the carried ammo (a 7-round magazine out = 1 chambered + 6; one shot with it in the hand; back in = 6, rack)
    const int took = g_same_mag ? 0 : player::game_reload(-1);
    g_same_mag = false;
    const int total = player::loaded();
    g_mag_rounds = 0;
    g_drop_gun = nullptr;
    if (g_dry && total > 0 && g_w->rack) rack::need("a magazine into an empty gun");   // the trigger waits for the rack
    shellclip::play(g_id, "mag_in");   // 2026-11-04: the game's own finger movement for the magazine going home (shellclip.h)
    tell_hud();
    LOGI("%s reload: %s new magazine: %d rounds (%d from the carried ammo, capacity %d)%s", TAG, g_id.c_str(), total, took, player::capacity(),
         g_stash > 0 ? ", waiting for a rack" : "");
    g_dry = false;
}

bool insert_round(int clip_hands = shellclip::BOTH) {
    const int cap = player::capacity(), have = player::loaded() + g_stash;
    if (cap > 0 && have >= cap) { LOGI("%s reload: %s is full (%d)", TAG, g_id.c_str(), have); return false; }
    const bool empty = player::loaded() == 0 || g_stash > 0;
    if (g_pocket > 0 && player::loaded() >= 0 && player::set_loaded(player::loaded() + 1)) {
        --g_pocket;   // one taken out by hand goes back first (it never left the carried ammo's count)
    } else if (player::game_reload(1) < 1) { LOGI("%s reload: no round went in (none carried?)", TAG); return false; }
    bridge::sfx(bridge::SFX_SHELL_IN);
    shellclip::play(g_id, "round_in", clip_hands);   // 2026-11-02: the game's own finger movement for a round going in (shellclip.h)
    if (g_w->pump && empty) rack::need("shells into an empty pump gun");   // the trigger waits for the pump
    tell_hud();
    LOGI("%s reload: %s round in: loaded %d, waiting for the pump %d, carried %d", TAG, g_id.c_str(), player::loaded(), g_stash, player::reserve());
    return true;
}

// unknown carried ammo (-1) = try anyway: the game's own reload then decides (and logs before / after)
bool supply() { const int r = player::reserve(); return player::unlimited() || r != 0 || g_mag_rounds > 0 || g_pocket > 0; }

void rail_enter(float u, const char* why);   // THE GRIP'S RAIL, below
void hand_checks() {
    if (pose_lock() || g_w == nullptr) return;
    const bool mag = g_w->reload == Reload::MAG && g_st == St::IN_HAND;
    if (!mag && !g_round_in_hand) return;
    if (mag) { Vec3 sp; Quat sq; if (held_pose(sp, sq)) throw_sample(sp); }   // the throw's speed (reload_throw.cpp)
    if (!bridge::held(bridge::S_LGRIP)) {
        LOGI("%s reload: let go; it came within %.3f m of where it goes in (needs %.2f)", TAG, g_closest, dock_need());
        ghosthand::value(g_round_in_hand ? "shell_closest_m" : "mag_closest_m", g_closest);
        ghosthand::event(g_round_in_hand ? "shell" : "mag", "fail");
        g_closest = 99.0f;
        if (g_round_in_hand) { g_round_in_hand = false; g_rounds_n = 0; shell_home(); LOGI("%s reload: round(s) let go: back in the pouch", TAG); return; }
        Quat wr;
        if (!held_pose(g_fall_from, wr)) g_fall_from = Vec3{0, 0, 0};
        g_fall_rot = wr;
        if (g_joint != nullptr) throw_hand_over(g_fall_from, g_fall_rot, true);
        set_state(g_joint != nullptr ? St::HAND_FALL : St::OUT, "left grip let go");
        return;
    }
    if (g_round_in_hand && (g_w->breech == weapons::Breech::CYLINDER || shells::port_gun())) return;   // docked on the drum / the shell port (2026-11-02), LT puts each in
    const float d = dock_dist(), now = now_s();
    g_closest = std::fmin(g_closest, d);
    if (d <= dock_need() && !at_gun_height()) {   // close enough, but not in front at gun height: say so once per hold
        static float told = -10.0f;
        if (now - told > 2.0f) { told = now; LOGI("%s reload: at the gun (%.3f m) but not in front of you at gun height", TAG, d); }
        return;
    }
    if (d > dock_need() || now - g_last_dock < RELOAD_DOCK_COOLDOWN_SEC) return;
    // 2026-10-30: a handgun's magazine goes in with LG and LT held and a push PISTOL_INSERT_PUSH of the way in (Tefa)
    if (mag && pistol_mag() && g_lt_to_seat) {   // 2026-10-31: only the same magazine going back in; a pouch one seats by itself
        static float told = -10.0f;
        const bool lt = bridge::held(bridge::S_LTRIG), deep = d <= dock_need() * (1.0f - PISTOL_INSERT_PUSH);
        if (MAG_RAIL_ON && lt) { rail_enter(1.0f, "LT held at the well: onto the grip's line"); return; }
        if (!lt || !deep) {
            if (now - told > 2.0f) { told = now; LOGI("%s reload: the magazine is at the well (%.3f m of %.2f): %s", TAG, d, dock_need(), !lt ? "hold LT and push it in" : "push it further in"); }
            return;
        }
        g_lt_to_seat = false;   // the held LT is the seat press here
    }
    // 03:21 and 03:53 (the log: "insert at 0.001 m", later "insert at 0.126 m", the frame after every pull-out: the magazine seated
    // itself again at once). Tefa 2026-10-25: "LT must be pressed again for it to go back in". So a magazine pulled out by hand
    // sits at the well until a fresh LT press (not the pull-out's own, hence the short wait); one from the pouch seats by itself
    if (mag && g_lt_to_seat && INSERT_NEEDS_LT && !pistol_mag()) {
        static float told = -10.0f;
        if (now - g_t0 < INSERT_LT_MIN_SEC) return;
        if (!bridge::pressed(bridge::S_LTRIG)) {
            if (now - told > 2.0f) { told = now; LOGI("%s reload: the magazine is at the well (%.3f m): press LT to seat it", TAG, d); }
            return;
        }
        LOGI("%s reload: LT pressed at the well: the magazine goes in", TAG);
        g_lt_to_seat = false;
    }
    g_last_dock = now;
    bridge::rumble(bridge::LEFT, RELOAD_INSERT_BUZZ_AMP, RELOAD_INSERT_BUZZ_SEC, RELOAD_BUZZ_HZ);
    if (mag) {
        set_state(St::INSERT, "brought to the gun");
        bridge::sfx(bridge::SFX_MAG_IN);
        ghosthand::value("mag_closest_m", d);
        ghosthand::event("mag", "done");
        magazine_shown(true);
        LOGI("%s reload: insert at %.3f m (need %.2f)", TAG, d, dock_need());
    } else {
        if (breech::spent()) {   // 2026-10-27: the GM 79's spent case comes out first (LG + LT at the insert point)
            static float told_spent = -10.0f;
            if (now - told_spent > 2.0f) {   // 2026-11-02: no refusal buzz: the hand docks here and LT swaps them (breech.cpp)
                told_spent = now;
                LOGI("%s reload: the spent case is still in: LT here swaps it for the round in the hand", TAG);
            }
            return;
        }
        g_round_in_hand = false;
        shell_home();
        ghosthand::value("shell_closest_m", d);
        ghosthand::event("shell", "done");
        insert_round();
    }
}

void put_back_on_swap(const char* why) {
    if (g_round_in_hand) { g_round_in_hand = false; shell_home(); LOGI("%s reload: round put back (%s)", TAG, why); }
    g_shell_have_rest = false;
    g_shell_scale_ok = false;   // 2026-10-31: another gun, another shell joint
    MO* old = g_drop_gun != nullptr ? g_drop_gun : g_gun;
    if (g_stash > 0 && is_managed(old)) { set_loaded_on(old, g_stash); LOGI("%s reload: %s: %d rounds that waited for a rack put in (%s)", TAG, g_id.c_str(), g_stash, why); }
    g_stash = 0;
    g_hand_on_mag = false;
    if (g_st == St::SEATED) return;
    if (is_managed(g_drop_gun)) set_loaded_on(g_drop_gun, g_mag_rounds + g_chamber);
    g_chamber = 0;
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
    // 2026-10-31: a slide / bolt gun that is not empty keeps one round in the chamber (the slide stays forward)
    g_chamber = (CHAMBER_ROUND && n > 0 && g_w != nullptr && g_w->rack && !g_w->pump) ? 1 : 0;
    g_mag_rounds = n - g_chamber;
    g_dry = n == 0;
    g_drop_gun = g_gun;
    g_same_mag = false;   // dropped to the floor: the next one comes from the pouch
    if (!player::set_loaded(g_chamber)) { LOGW("%s reload: %s: no way to empty the gun found, no drop (see type_probe.txt)", TAG, g_id.c_str()); g_drop_gun = nullptr; return; }
    bridge::sfx(bridge::SFX_MAG_OUT);
    tell_hud();   // 2026-10-31 (Tefa: the rifle's counter was only right again after a shot): show what is left in the gun now
    Vec3 p, s;
    Quat q;
    if (g_joint != nullptr && get_v3(JOINT, g_joint, "get_LocalPosition", p) && get_q(JOINT, g_joint, "get_LocalRotation", q)) {
        if (!get_v3(JOINT, g_joint, "get_LocalScale", s) || s.x < 0.01f) s = Vec3{1, 1, 1};
        g_rest_pos = p;
        g_rest_rot = qnorm(q);
        g_rest_scale = s;
        capture_port(g_joint);
        capture_second();
        set_state(St::SLIDE_OUT, "right B");
    } else {
        set_state(St::OUT, "right B");
    }
    // 2026-10-24: the gun's own magazine display stays on while the magazine slides, falls and is carried (switching it
    // off here is the suspect for "only the bottom slab drops"); the menu's experiment puts the old way back
    if (g_joint == nullptr || bridge::experiment(bridge::EX_MAG_HIDE_AT_DROP)) magazine_shown(false);
    log_parts();
    LOGI("%s reload: drop with %d rounds in it, %d carried", TAG, g_mag_rounds, player::reserve());
}

// ---- HANDS-ON MAGAZINE (2026-10-25, Tefa: "to reload the rifle, i have to put my left hand on the mag, press LT to release
// it, then i can throw it on the ground and non-spent bullets will still be in my inventory, then put a new mag in and
// continue. so B only ejects the mag on pistols"): with the magazine seated, LG pressed with the left controller within
// MAG_GRAB_M of it puts the hand on it (the seated-magazine hold the insert already uses); LT then pulls it out straight into
// the hand (the state the pouch hands a fresh one in), with the eject's bookkeeping: its rounds leave the gun and stay
// counted, the rest pose is kept for the next seat. Letting go drops it as any carried magazine; the pouch then gives a new
// one; a pulled-out magazine can also go straight back in.
bool g_magrel_ok = false;
Vec3 g_magrel_rest{}, g_magrel_out{};
Quat g_magrel_rot{0, 0, 0, 1};
// ---- THE GRIP'S RAIL (b096, 2026-11-09, Tefa: "is there a way to make handgun magazines move only up and down in the grip
// shaft until taken out, right now the mag just comes out the side of the handle when i hold LG and press B"): a released
// handgun magazine is not the hand's yet. It moves only along the grip's own line (seat -> mag_out_pos), as far as the left
// controller has moved along that line since it went on, and the drawn hand stays on it. Past the bottom it is free in the
// hand (IN_HAND); pushed back to the top it seats; LG let go and it slides out and falls. The same magazine brought back to
// the well with LT held goes on at the bottom and is pushed up the same way. The line is measured in the right hand's
// target frame, which carries the gun (g_magrel_*), so it does not lag the gun the way the gun's own transform would.
bool g_rail_ok = false;
float g_rail_u0 = 0.0f, g_rail_u = 0.0f, g_rail_max = 0.0f;
Vec3 g_rail_c0{};                 // the left controller where the rail began, in the right hand target's frame
bool rail_ctrl(Vec3& rel) {       // the left controller in the right hand target's frame
    Vec3 rp, cp;
    Quat rq;
    if (!rh_target(rp, rq) || !bridge::room_to_world(bridge::hand_pos(bridge::LEFT), cp)) return false;
    rel = rotate(qinv(qnorm(rq)), cp - rp);
    return true;
}
float rail_len(Vec3& axis) {      // the grip's line, top to bottom, and its length
    const Vec3 d = g_magrel_out - g_magrel_rest;
    const float n = std::sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
    axis = n > 1e-4f ? d * (1.0f / n) : Vec3{0, -1, 0};
    return n;
}
void rail_enter(float u, const char* why) {
    g_rail_ok = g_magrel_ok && rail_ctrl(g_rail_c0);
    g_rail_u0 = g_rail_u = u;
    g_rail_max = 0.0f;
    g_hand_on_mag = false;
    set_state(St::RAIL, why);
    if (!g_rail_ok) LOGW("%s reload: %s: the grip's line is not measured yet: the magazine goes straight into the hand", TAG, g_id.c_str());
    if (u > 0.5f) { bridge::rumble(bridge::LEFT, RELOAD_INSERT_BUZZ_AMP, RELOAD_INSERT_BUZZ_SEC, RELOAD_BUZZ_HZ); bridge::sfx(bridge::SFX_MAG_IN); }
}
void rail_frame() {
    const float now = now_s();
    if (!g_rail_ok) { set_state(St::IN_HAND, "no rail: into the hand"); g_last_dock = now; return; }
    if (!bridge::held(bridge::S_LGRIP)) {   // let go in the grip: it slides the rest of the way out and falls
        LOGI("%s reload: LG let go with the magazine %.0f%% down the grip: it slides out", TAG, g_rail_u * 100.0f);
        set_state(St::SLIDE_OUT, "let go in the grip");
        g_t0 = now - g_rail_u * RELOAD_SLIDE_SEC;
        return;
    }
    Vec3 c, axis;
    const float len = rail_len(axis);
    if (!rail_ctrl(c) || len < 0.01f) return;
    const Vec3 d = c - g_rail_c0;
    const float raw = g_rail_u0 + (d.x * axis.x + d.y * axis.y + d.z * axis.z) / len;
    g_rail_u = raw < 0.0f ? 0.0f : raw > 1.0f ? 1.0f : raw;
    g_rail_max = std::fmax(g_rail_max, std::fabs(raw - g_rail_u0));
    if (raw >= 1.0f + (g_rail_u0 > 0.5f ? MAG_RAIL_LEAVE_EXTRA : 0.0f)) {   // out of the bottom: the hand's now
        g_last_dock = now;   // no snapping straight back on at the well
        set_state(St::IN_HAND, "out of the bottom of the grip");
        return;
    }
    if (raw <= MAG_RAIL_SEAT_U && g_rail_max >= MAG_RAIL_MOVED) {   // pushed home
        g_last_dock = now;
        bridge::rumble(bridge::LEFT, RELOAD_INSERT_BUZZ_AMP, RELOAD_INSERT_BUZZ_SEC, RELOAD_BUZZ_HZ);
        ghosthand::event("mag", "done");
        LOGI("%s reload: the magazine pushed up the grip: seated", TAG);
        set_state(St::INSERT, "pushed home along the grip");
        g_t0 = now - RELOAD_INSERT_SEC;   // already there: INSERT seats it at once (fill_magazine; the hand stays on with LG)
    }
}
bool mag_world(Vec3& p, Quat& q);   // below
void pull_out() {
    const int n = player::loaded();
    if (n < 0) { LOGW("%s reload: %s: no loaded-ammo call found, the magazine stays", TAG, g_id.c_str()); return; }
    // 2026-10-31: a slide / bolt gun that is not empty keeps one round in the chamber (the slide stays forward)
    g_chamber = (CHAMBER_ROUND && n > 0 && g_w != nullptr && g_w->rack && !g_w->pump) ? 1 : 0;
    g_mag_rounds = n - g_chamber;
    g_dry = n == 0;
    g_drop_gun = g_gun;
    if (!player::set_loaded(g_chamber)) { LOGW("%s reload: %s: no way to empty the gun found, the magazine stays", TAG, g_id.c_str()); g_drop_gun = nullptr; return; }
    bridge::sfx(bridge::SFX_MAG_OUT);
    tell_hud();   // 2026-10-31 (Tefa: the rifle's counter was only right again after a shot): show what is left in the gun now
    Vec3 p, s;
    Quat q;
    if (get_v3(JOINT, g_joint, "get_LocalPosition", p) && get_q(JOINT, g_joint, "get_LocalRotation", q)) {
        if (!get_v3(JOINT, g_joint, "get_LocalScale", s) || s.x < 0.01f) s = Vec3{1, 1, 1};
        g_rest_pos = p;
        g_rest_rot = qnorm(q);
        g_rest_scale = s;
        capture_port(g_joint);
        capture_second();
    }
    g_hand_on_mag = false;   // the hand carries it now (mag_in_hand) rather than resting on a seated one
    g_lt_to_seat = true;     // it goes back in only on a fresh LT press at the well (hand_checks)
    g_same_mag = true;
    shellclip::play(g_id, "mag_out");   // 2026-11-04: the game's own finger movement for the magazine coming out (shellclip.h)
    if (MAG_RAIL_ON && pistol_mag()) rail_enter(0.0f, "released (B): it moves only along the grip until it is out");
    else set_state(St::IN_HAND, pistol_mag() ? "released (B) into the left hand" : "pulled out by hand (LT)");
    ghosthand::event("mag", "start");
    bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
    log_parts();
    LOGI("%s reload: %s magazine pulled out by hand with %d rounds in it, %d carried", TAG, g_id.c_str(), g_mag_rounds, player::reserve());
}
// 2026-11-07 (Tefa: "when ejecting the mag on Lemi, holding LG and pressing B to eject, clip falls on the ground. only when i was
// holding LG and pressed LT once, after that LG + B landed the mag in my hand"): the grab was decided only at the LG press, within
// the zone (6 cm); the log had the hand 11 cm off at the press, so B dropped it. Now right B with LG held (not on the front grip,
// no rack) catches it when the hand is within RELOAD_B_CATCH_SCALE of the zone
bool b_catch_near() {
    // (b078 also refused while the game's two-handed grip held the left hand: on a handgun that IS the hand by the magazine, so it
    // never caught; Tefa 00:1x: "lemi still drops the mag with just LG held")
    if (!pistol_mag() || !bridge::held(bridge::S_LGRIP) || rack::active()) return false;
    Vec3 mp, cp;
    Quat mq;
    if (!mag_world(mp, mq) || !bridge::room_to_world(bridge::hand_pos(bridge::LEFT), cp)) return false;
    const float d = dist(zones::center(zones::MAG, mp), cp), need = zones::radius(zones::MAG) * RELOAD_B_CATCH_SCALE;
    LOGI("%s reload: right B with LG held: the hand %.3f m from the magazine (catches within %.2f)", TAG, d, need);
    return d <= need;
}
void grab_frame() {
    if (!in_play() || g_st != St::SEATED || g_joint == nullptr || rack::active() || pose_lock()) return;
    if (!g_hand_on_mag) {
        if (!bridge::pressed(bridge::S_LGRIP)) return;   // on the press only: an LG already held for the grip or the pump never grabs the magazine
        // 03:06 (the rifle: no grab, the hand went to the bolt or the grip): the controller sits ~15 cm behind the drawn hand,
        // so the hand's own place (the left IK target, where it was drawn last frame) is measured, and every press is logged
        const auto& s = player::now();
        Vec3 mp, cp;
        Quat mq, cq;
        // 2026-11-04 (Tefa: "real hand please"): the real hand (the controller) again, like every other grab, so the sphere and
        // the grab agree; the 03:06 switch to the drawn hand made a hand inside the sphere miss the magazine
        (void)s; (void)cq;
        if (!mag_world(mp, mq) || !bridge::room_to_world(bridge::hand_pos(bridge::LEFT), cp)) return;
        const float d = dist(zones::center(zones::MAG, mp), cp), need = zones::radius(zones::MAG);   // the zone (zones.json) over MAG_GRAB_M
        LOGI("%s reload: LG pressed with the magazine seated: the hand %.3f m from it (grabs within %.2f)", TAG, d, need);
        if (d > need) return;
        if (rack::bolt_wants_left()) { LOGI("%s reload: the hand is near the bolt too and a rack is due: the bolt takes it, not the magazine", TAG); return; }
        g_hand_on_mag = true;
        bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
        LOGI("%s reload: the left hand on the seated magazine (%.3f m from it): %s", TAG, d, pistol_mag() ? "right B releases it into the hand" : "LT pulls it out");
        return;
    }
    // 2026-10-30 (Tefa, first wear: "it has to be just LG held and the mag just slides out after pressing B with hand on the
    // mag. LT only needed to put it back in"): on a handgun right B, with the left hand holding the magazine, releases it into
    // the hand; long guns: LT (Tefa: "rifles and long guns with mag in the middle of the gun only need LG + LT")
    if (pistol_mag() ? bridge::pressed(bridge::S_RB) : bridge::pressed(bridge::S_LTRIG)) pull_out();
}

void pouch_grab() {
    if (!managed_now() || !in_play()) return;
    const float now = now_s();
    if (now - g_last_grab < RELOAD_GRAB_COOLDOWN_SEC) return;
    g_last_grab = now;
    if (gate::here()) return;   // 2026-11-01 (Tefa): the Wolfsbane's rounds come from the pouch by the RIGHT hand (gate.cpp)
    if (g_w->reload == Reload::ROUND) {
        if (g_round_in_hand) return;
        if (!breech::loading_allowed()) {   // 2026-10-19: a revolver / the GM 79 takes rounds only while it is open
            LOGI("%s reload: %s is closed: open it first (revolver: LG + LT on the drum and drag it out; GM 79: a flick down, right B, or LT on the front grip)", TAG, g_id.c_str());
            bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
            return;
        }
        const int cap = player::capacity();
        if (g_w->breech == weapons::Breech::CYLINDER) {   // 2026-10-27: one grab = what the free chambers need
            const int free = breech::free_chambers(), carried = player::unlimited() ? free : std::max(0, player::reserve()) + g_pocket;
            const int n = std::min(free, carried);
            if (n <= 0) {
                LOGI("%s reload: nothing to take for the drum (%d free, %d spent casing(s) in it: tip it muzzle-up; carried %d)", TAG, free, breech::spent_casings(), carried);
                bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
                return;
            }
            capture_port(g_shell);
            g_round_in_hand = true;
            g_rounds_n = n;
            ghosthand::event("shell", "start");
            bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
            LOGI("%s reload: %d round(s) in the left hand for the drum (carried %d)", TAG, n, player::reserve());
            return;
        }
        if (!supply() || (cap > 0 && player::loaded() + g_stash >= cap)) {
            LOGI("%s reload: nothing to take (carried %d, loaded %d of %d)", TAG, player::reserve(), player::loaded() + g_stash, cap);
            bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
            return;
        }
        capture_port(g_shell);
        g_round_in_hand = true;
        g_rounds_n = shells::port_gun() ? shells::grab_count(player::unlimited() ? -1 : std::max(0, player::reserve()) + g_pocket, cap > 0 ? cap - player::loaded() - g_stash : -1) : 1;   // 2026-11-02: two shells (shells.h)
        ghosthand::event("shell", "start");
        bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
        LOGI("%s reload: %d round(s) in the left hand (carried %d)", TAG, g_rounds_n, player::reserve());
        return;
    }
    if (g_st != St::OUT) return;
    if (!supply()) {
        LOGI("%s reload: the ammo spot is empty (no rounds carried, none in the dropped magazine)", TAG);
        bridge::rumble(bridge::LEFT, RELOAD_DENY_BUZZ_AMP, RELOAD_DENY_BUZZ_SEC, RELOAD_BUZZ_HZ);
        return;
    }
    // from the pouch: a long gun's magazine goes in only on an LT press at the well, as a pulled-out one (Tefa 2026-10-30: "a mag
    // is only inserted with LG held, Mag in the activation area and LT pressed once"); a handgun's needs LT held and a push
    // 2026-10-31 (Tefa): "taking a new mag from the pouch still requires LT to be pressed and that should be removed, only the
    // requirement to press LT when i need to re-insert the same mag i just took out": a pouch magazine seats at the well by itself
    g_lt_to_seat = false;
    g_same_mag = false;   // a fresh one: filled from the carried ammo when it goes in
    set_state(St::IN_HAND, "taken from the ammo spot");
    ghosthand::event("mag", "start");
    bridge::rumble(bridge::LEFT, RELOAD_GRAB_BUZZ_AMP, RELOAD_GRAB_BUZZ_SEC, RELOAD_BUZZ_HZ);
}

Vec3 pouch_spot() {   // our own left-hip spot, from the headset (RE2's numbers)
    Vec3 f = rotate(bridge::hmd_rot(), Vec3{0, 0, -1});
    f.y = 0;
    const float len = std::sqrt(f.x * f.x + f.z * f.z);
    f = len < 1e-4f ? Vec3{0, 0, -1} : f * (1.0f / len);
    const Vec3 right{-f.z, 0, f.x};
    return bridge::hmd_pos() + right * LEFT_HIP_POUCH[0] + Vec3{0, LEFT_HIP_POUCH[1], 0} + f * LEFT_HIP_POUCH[2];
}
void track_pouch() {   // our own spot, beside Andyalpa's (his reports through the bridge)
    const float d = dist(bridge::hand_pos(bridge::LEFT), pouch_spot());
    if (!g_pouch_ours && d < POUCH_ENTER_M) g_pouch_ours = true;
    else if (g_pouch_ours && d > POUCH_LEAVE_M) g_pouch_ours = false;
}

// ---- the game's own reload request, off for our guns (names tried; the probe file lists the real ones) --------------
// Tefa 2026-10-19: "shotgun shows 5 shells in the gun, but when i fire the ammo counter drops to zero" -- the rounds were
// held back until the pump. Now they stay in the gun and PlayerGun.tryAttack is refused until the rack / pump is done.
thread_local bool t_attack_blocked = false;
int pre_try_attack(int, void**, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    t_attack_blocked = managed_now() && (rack::needed() || breech::blocks_fire() || rack_right::active() || gate::hammer_down() || gate::holding());   // (2026-11-01: not with the right hand on the bolt)
    if (!t_attack_blocked) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    static int n = 0;
    if (++n <= 5 || n % 500 == 0) LOGI("%s reload: trigger refused until %s (#%d)", TAG, breech::blocks_fire() ? "it is closed" : g_w->pump ? "the pump" : "the rack", n);
    return REFRAMEWORK_HOOK_SKIP_ORIGINAL;
}
void post_try_attack(void** ret, REFrameworkTypeDefinitionHandle, unsigned long long) {
    if (t_attack_blocked && ret != nullptr) *ret = nullptr;   // "did not attack"
    t_attack_blocked = false;
}

int pre_reload_request(int, void**, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    t_blocked = managed_now() && !bridge::experiment(bridge::EX_GAME_RELOAD);   // 2026-10-24: let through once to learn its sounds
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
namespace detail { float rail_u() { return g_rail_u; } }   // b096: for pose_joint (reload_pose.cpp)

bool managed_now() { return RELOAD_ON && g_w != nullptr && g_w->reload != Reload::NONE && g_gun != nullptr && bridge::live(); }
bool mag_out() { return managed_now() && g_w->reload == Reload::MAG && g_st != St::SEATED; }
bool session_active() { return mag_out() || g_round_in_hand; }
bool mag_in_hand() { return managed_now() && g_w->reload == Reload::MAG && (g_st == St::IN_HAND || g_st == St::INSERT); }
bool round_in_hand() { return managed_now() && g_round_in_hand; }
float pouch_dist(bridge::Hand h) { return dist(bridge::hand_pos(h), pouch_spot()); }
bool in_pouch() { return bridge::flag(bridge::S_IN_AMMO_ZONE) || g_pouch_ours; }



void on_racked() {
    if (g_stash <= 0) return;
    player::set_loaded(player::loaded() + g_stash);
    tell_hud();
    LOGI("%s reload: %s racked: %d rounds go in", TAG, g_id.c_str(), g_stash);
    g_stash = 0;
}

// While the left hand carries a magazine / round, the VR layer's two-handed grip must not pull it onto the gun: whenever
// it is NOT gripping, the hand's place relative to the left controller (in the world) is remembered; while it grips and
// the hand carries something, the hand is put back there before the arm is solved.
namespace {
bool g_free_ok = false;
Vec3 g_free_pos{};
Quat g_free_rot{0, 0, 0, 1};

// 2026-10-24 (Tefa: "can we make the hand stay on the bottom of the mag and follow it fully until it's in the gun, so the LG
// needs to be released to use your left hand again, and letting go of LG before the click sound plays ... just drops the
// mag"): from the insert until LG is let go, the left hand is drawn holding the magazine where it is (going in, then seated).
// The IK target is the wrist and its turn differs from the hand joint's by a fixed amount: measured after the solves.
bool g_tq_ok = false;
Quat g_tq_off{0, 0, 0, 1};        // hand joint = IK target * this
// 2026-10-24 (Tefa: "the hand after inserting a mag moves to a spot and stays there, while the gun can be moved around it
// freely"): the gun's transform read before the arm is solved is where the game's animation holds it, not where the VR hand
// puts it. So the magazine's seat and its out spot are measured after the solves (render_point) relative to the right hand's
// IK target, which carries the gun, and placed from that target at the next solve (the way the slide is, rack.cpp)
// (g_magrel_ok / g_magrel_rest / g_magrel_out / g_magrel_rot: declared above THE GRIP'S RAIL, which uses them)
void measure_mag_rel() {
    Vec3 rp, a, b;
    Quat rq, qa, qb;
    if (g_joint == nullptr || !rh_target(rp, rq) || !from_weapon_local(g_rest_pos, g_rest_rot, a, qa) || !from_weapon_local(mag_out_pos(), g_rest_rot, b, qb)) return;
    const Quat inv = qinv(qnorm(rq));
    g_magrel_rest = rotate(inv, a - rp);
    g_magrel_out = rotate(inv, b - rp);
    g_magrel_rot = qnorm(qmul(inv, qa));
    g_magrel_ok = true;
}
bool mag_world(Vec3& p, Quat& q) {
    Vec3 rp;
    Quat rq;
    if (g_joint == nullptr || !g_magrel_ok || !rh_target(rp, rq)) return false;
    const Vec3 rel = g_st == St::INSERT ? lerp(g_magrel_out, g_magrel_rest, ease((now_s() - g_t0) / RELOAD_INSERT_SEC))
                   : g_st == St::RAIL ? lerp(g_magrel_rest, g_magrel_out, rail_u())
                   : g_st == St::SEATED ? g_magrel_rest : Vec3{0, 0, 0};
    if (g_st != St::INSERT && g_st != St::SEATED && g_st != St::RAIL) return false;
    p = rp + rotate(qnorm(rq), rel);
    q = qnorm(qmul(qnorm(rq), g_magrel_rot));
    return true;
}
bool hand_on_mag_pose(Vec3& tp, Quat& tq) {   // where the IK target goes so the hand joint holds the magazine (held_pose undone)
    Vec3 mp;
    Quat mq;
    if (!mag_world(mp, mq)) return false;
    const Quat hold = quat_from_ypr(MAG_HOLD[3], MAG_HOLD[4], MAG_HOLD[5]);
    const Quat hq = qnorm(qmul(qnorm(mq), qinv(hold)));
    tp = mp - rotate(hq, Vec3{MAG_HOLD[0], MAG_HOLD[1], MAG_HOLD[2]});
    tq = g_tq_ok ? qnorm(qmul(hq, qinv(g_tq_off))) : hq;
    return true;
}
void measure_target_turn() {
    const auto& s = player::now();
    Vec3 hp, tp;
    Quat hq, tq;
    if (g_hand == nullptr || s.ik_left == nullptr || !get_v3(JOINT, g_hand, "get_Position", hp) || !get_q(JOINT, g_hand, "get_Rotation", hq) ||
        !player::get_pose(field_obj(s.ik_left, "Target"), tp, tq) || dist(hp, tp) > RELOAD_TARGET_REACH_M)
        return;
    const Quat off = qnorm(qmul(qinv(qnorm(tq)), qnorm(hq)));
    if (!g_tq_ok) LOGI("%s reload: the hand joint's turn from its IK target measured (%.3f %.3f %.3f %.3f)", TAG, off.x, off.y, off.z, off.w);
    g_tq_off = off;
    g_tq_ok = true;
}
// 2026-10-30 (Tefa: "when game animation takes over, it is safe to let go of LG and LT and already move left hand to the
// slide, but the mag insert animation still shows the hand on the mag until the animation ends"): once the insert has begun,
// letting go no longer drops the magazine; the hand is drawn on it until it is seated (hand_on_mag), then is free
void mag_hand_frame() {   // UpdateBehavior: let go after the seat frees the hand
    if (pose_lock() || g_w == nullptr || g_w->reload != Reload::MAG) { g_hand_on_mag = false; return; }
    const bool lg = bridge::held(bridge::S_LGRIP);
    if (g_hand_on_mag && (!lg || g_st != St::SEATED)) {
        g_hand_on_mag = false;
        LOGI("%s reload: LG let go: the left hand leaves the magazine", TAG);
    }
}
} // namespace
bool hand_near_mag() {
    if (!managed_now() || g_w->reload != Reload::MAG || g_joint == nullptr || g_st != St::SEATED) return false;
    const auto& s = player::now();
    Vec3 mp, cp;
    Quat mq, cq;
    (void)s; (void)cq;
    if (!mag_world(mp, mq) || !bridge::room_to_world(bridge::hand_pos(bridge::LEFT), cp)) return false;   // the real hand (2026-11-04)
    return dist(zones::center(zones::MAG, mp), cp) <= zones::radius(zones::MAG);
}
// the zones the menu draws (zones.h): the magazine grab and the well, every frame; the well is measured while the magazine
// sits in it, so it is known before the first pull-out too
// 2026-10-31 (Tefa: "there is no shell insertion activation zone at all"): a pump shotgun's shells go in at the same WELL
// zone (dock_dist / dock_need, long guns), measured at the shell joint, but it was only published for magazine guns, and the
// port was only measured when a round was taken. Now the port is measured every frame while the shell sits home in the gun,
// and published as the WELL ("on" 2 = a round in the left hand on its way in), so Grip Zones shows and sizes it.
bool shell_port_gun() { return g_w != nullptr && g_w->reload == Reload::ROUND && g_w->shape == weapons::Shape::LONG && g_w->breech == weapons::Breech::NONE; }
void publish_shell_port() {
    Vec3 lp{}, port;
    if (g_shell != nullptr && !g_round_in_hand && g_shell_have_rest && get_v3(JOINT, g_shell, "get_LocalPosition", lp) && dist(lp, g_shell_rest) < 0.002f)
        capture_port(g_shell);
    if (port_world(port)) zones::publish(zones::WELL, zones::center(zones::WELL, port), zones::radius(zones::WELL), g_round_in_hand ? 2.0f : 1.0f);
    else zones::clear(zones::WELL);
}
void publish_zones() {
    if (managed_now() && shell_port_gun()) { zones::clear(zones::MAG); publish_shell_port(); return; }
    if (!managed_now() || g_w->reload != Reload::MAG) { zones::clear(zones::MAG); zones::clear(zones::WELL); return; }
    Vec3 mp, port;
    Quat mq;
    if (g_st == St::SEATED && g_joint != nullptr) capture_port(g_joint);
    if (g_st == St::SEATED && mag_world(mp, mq)) zones::publish(zones::MAG, zones::center(zones::MAG, mp), zones::radius(zones::MAG));
    else zones::clear(zones::MAG);
    // every magazine gun's well (handguns too since 2026-10-30); "on" 2 = a magazine is in the left hand on its way in, so the
    // zones script shows the well's ball then
    if (port_world(port)) zones::publish(zones::WELL, zones::center(zones::WELL, port), zones::radius(zones::WELL), mag_in_hand() ? 2.0f : 1.0f);
    else zones::clear(zones::WELL);
}
bool hand_on_mag() { return managed_now() && g_w->reload == Reload::MAG && g_joint != nullptr && (g_st == St::INSERT || g_st == St::RAIL || g_hand_on_mag); }

void on_ik(MO* ik) {
    const auto& s = player::now();
    if (ik != s.ik_left || !bridge::live()) return;
    if (hand_on_mag()) {
        Vec3 tp;
        Quat tq;
        if (hand_on_mag_pose(tp, tq)) { player::set_pose(field_obj(ik, "Target"), tp, tq); return; }
    }
    Vec3 cp;
    Quat cq;
    if (!bridge::room_to_world(bridge::hand_pos(bridge::LEFT), cp) || !bridge::room_rot_to_world(bridge::view_quat(bridge::S_LROT), cq)) return;
    auto* tf = field_obj(ik, "Target");
    Vec3 tp;
    Quat tq;
    if (!bridge::flag(bridge::S_GRIPPING_WEAPON)) {
        if (player::get_pose(tf, tp, tq)) {
            const Quat inv = qinv(cq);
            g_free_pos = rotate(inv, tp - cp);
            g_free_rot = qnorm(qmul(inv, tq));
            g_free_ok = true;
        }
        return;
    }
    if (!g_free_ok || !(mag_in_hand() || round_in_hand())) return;
    player::set_pose(tf, cp + rotate(cq, g_free_pos), qnorm(qmul(cq, g_free_rot)));
}

void install() {
    auto* tdb = API::get()->tdb();
    int n = 0;
    for (const char* t : {"app.PlayerGun", "app.PlayerGunFPS", "app.PlayerGunPl2001", "app.PlayerGunPl2001FPS", "app.WeaponGunCore"}) {
        auto* td = tdb->find_type(t);
        if (td == nullptr) continue;
        if (auto* a = td->find_method("tryAttack"); a != nullptr && a->get_declaring_type() == td) {
            a->add_hook(pre_try_attack, post_try_attack, false);
            LOGI("%s reload: hooked %s.tryAttack (no shot while a rack / pump is due)", TAG, t);
        }
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

// b098 (2026-11-09, Tefa, screenshots 11:46: "when i launch the game and first grab the Lemi grip, my hand is away ... when i
// do LG+B eject and put the mag back in, it's fine"): the magazine's seat (g_rest_*) was read only when a magazine first came
// out, so until then the hand docked on a blank default (log dockreport: forward +2.4 cm, yaw 19 against -2.3 cm, yaw 0 after
// an eject). It is now read from the seated magazine shortly after each gun comes out.
namespace {
bool g_rest_need = false;
float g_rest_need_t = 0.0f;
void read_rest(const char* why) {
    Vec3 p, sc;
    Quat q;
    if (g_joint == nullptr || !get_v3(JOINT, g_joint, "get_LocalPosition", p) || !get_q(JOINT, g_joint, "get_LocalRotation", q)) return;
    if (!get_v3(JOINT, g_joint, "get_LocalScale", sc) || sc.x < 0.01f) sc = Vec3{1, 1, 1};
    g_rest_pos = p;
    g_rest_rot = qnorm(q);
    g_rest_scale = sc;
    g_rest_need = false;
    LOGI("%s reload: %s magazine seat read (%s): local %.3f %.3f %.3f, turn %.3f %.3f %.3f %.3f", TAG, g_id.c_str(), why, p.x, p.y, p.z, g_rest_rot.x, g_rest_rot.y, g_rest_rot.z, g_rest_rot.w);
}
} // namespace

void frame() {
    if (!RELOAD_ON) return;
    const std::string id = weapons::canonical(player::now().weapon_id);
    if (id != g_id) {
        put_back_on_swap(id.empty() ? "weapon put away" : "weapon changed");
        g_rest_need = MAG_SEAT_READ_ON;
        g_rest_need_t = now_s();
        g_id = id;
        g_w = weapons::find(id);
        resolve_frame();
        if (!id.empty()) {
            LOGI("%s weapon: %s (%s)%s, magazine joint %s", TAG, id.c_str(), weapons::name(id), g_w == nullptr ? "" :
                 g_w->reload == Reload::MAG ? ": manual magazine" : g_w->reload == Reload::ROUND ? ": single rounds" : ": no reload",
                 g_joint != nullptr ? "found" : "not found");
            static std::string seen;
            if (seen.find("|" + id + "|") == std::string::npos) { seen += "|" + id + "|"; log_joints(); log_parts(); }
            player::probe_types();
        }
    }
    resolve_frame();
    track_pouch();
    // 2026-10-24 (Tefa: "left hand on the mag does seem to fight the game at first, as it starts throwing the gun and hands
    // around"): the grip script took the two-handed grip with LG held at the gun and steered the gun at the hand
    bridge::put(bridge::S_GRIP_VETO, (hand_on_mag() || gate::owns_left()) ? 1.0f : 0.0f);   // (2026-11-01: or the Wolfsbane held, gate.cpp)
    if (g_w == nullptr || g_gun == nullptr) return;

    if (g_w->reload == Reload::MAG) {
        const float t = now_s() - g_t0;
        switch (g_st) {
        case St::SLIDE_OUT:
            if (t >= RELOAD_SLIDE_SEC) {
                if (!from_weapon_local(mag_out_pos(), g_rest_rot, g_fall_from, g_fall_rot)) g_fall_from = Vec3{0, 0, 0};
                throw_hand_over(g_fall_from, g_fall_rot, false);
                set_state(St::FALL, "out of the magwell");
            }
            break;
        case St::FALL:
        case St::HAND_FALL:
            if (throw_taken()) set_state(St::OUT, "the thrown copy took over");
            else if (t >= RELOAD_FALL_SEC) set_state(St::OUT, "on the floor");
            break;
        case St::RAIL:
            rail_frame();
            break;
        case St::INSERT:
            if (t >= RELOAD_INSERT_SEC) {
                set_state(St::SEATED, "seated");
                g_scale_restore = true;
                magazine_shown(true);
                fill_magazine();
                g_hand_on_mag = bridge::held(bridge::S_LGRIP) && g_joint != nullptr;
            }
            break;
        default:
            break;
        }
        mag_hand_frame();
        grab_frame();
        // B ejects only on pistols (Tefa 2026-10-25); a gun whose magazine joint is unknown keeps B, having no hand path. With the
        // left hand on the magazine B releases it into the hand instead (grab_frame, 2026-10-30)
        if (in_play() && bridge::pressed(bridge::S_RB) && g_st == St::SEATED && !rack::active() && !g_hand_on_mag && (g_w->shape == weapons::Shape::PISTOL || g_joint == nullptr)) {
            if (g_joint != nullptr && b_catch_near()) { g_hand_on_mag = true; pull_out(); }   // 2026-11-07: into the held hand
            else begin_drop();
        }
    }
    if (in_pouch() && bridge::pressed(bridge::S_LGRIP)) pouch_grab();
}

void late_point() {
    if (!managed_now()) return;
    if (g_rest_need && g_w->reload == Reload::MAG && g_st == St::SEATED && (now_s() - g_rest_need_t >= MAG_SEAT_READ_SEC || g_hand_on_mag))
        read_rest(g_hand_on_mag ? "the hand took it first" : "the gun is out");
    pose_shell();
    if (g_w->reload == Reload::MAG) pose_joint();
    if (mag_out() && (g_st == St::OUT || g_joint == nullptr)) hide_mag_part();
}

// the hand checks run here, after the arm has been solved: at LateUpdateBehavior the hand joint still stood where the
// animation had it, so the measured distance jumped between runs (0.11-0.14 m, then 0.35-0.42 m; 2026-10-19)
void render_point() {
    if (!hand_on_mag()) measure_target_turn();   // only while the hand is the controller's (or the grip's), not ours
    if (managed_now() && g_w->reload == Reload::MAG) measure_mag_rel();
    publish_zones();
    if (managed_now()) { hand_checks(); pose_shell(); }
    if (managed_now() && g_w->reload == Reload::MAG) pose_joint();
    if (mag_out() && (g_st == St::OUT || g_joint == nullptr)) hide_mag_part();
}

bool load_round() { return managed_now() && insert_round(); }
int rounds_in_hand() { return g_round_in_hand ? std::max(1, g_rounds_n) : 0; }
bool insert_from_hand() {
    if (!g_round_in_hand || !managed_now()) return false;
    if (!insert_round()) return false;
    if (--g_rounds_n <= 0) { g_rounds_n = 0; g_round_in_hand = false; shell_home(); ghosthand::event("shell", "done"); }
    return true;
}
bool insert_direct_possible() { return !g_round_in_hand && managed_now() && player::reserve() != 0 && supply(); }
bool insert_direct() {   // gate.cpp, RT at the cover: the right hand pushes it in, so only the clip's right half plays (2026-11-06)
    if (g_round_in_hand || !managed_now() || !supply()) return false;
    return insert_round(shellclip::RIGHT);
}
void grab_from_pouch() { g_last_grab = -10.0f; pouch_grab(); }   // 2026-11-02: breech.cpp, LG held into the pouch
bool port_center(Vec3& out) { return port_world(out); }       // 2026-11-02: pairs.cpp, the shell port dock
void pocket_round() { ++g_pocket; LOGI("%s reload: a round back with the carried ammo (%d taken out by hand)", TAG, g_pocket); }

} // namespace vn::reload
