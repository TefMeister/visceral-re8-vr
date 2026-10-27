// pairs.cpp -- see pairs.h
#include "pairs.h"
#include "bridge.h"
#include "joints.h"
#include "json_mini.h"
#include "player.h"
#include "breech.h"
#include "rack.h"
#include "reload.h"
#include "settings.h"
#include "weapons.h"
#include "zones.h"

#include <windows.h>

#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

namespace vn::pairs {

using namespace joints;
using namespace vn::settings;

namespace {
struct Pair { int n = 0; std::string name, gun; Vec3 a{0, 0, 0}, l{0, 0, 0}; float r = PAIR_ACT_R_DEFAULT_M; };
std::vector<Pair> g_pairs;
int g_show = 0;                    // the pair drawn on the gun (0 = none)
int g_active = -1;                 // index into g_pairs of the pair holding the left hand, -1 = none
// 2026-10-27 (Tefa: the parts every gun needs): built-in docks beside the numbered pairs, each a zone on the gun (zones.h)
// where LG puts the left hand and keeps it while LG is held, and where LT does that part's job (breech.cpp)
struct Dock { zones::Key key; const char* name; float spot; };
const Dock DOCKS[] = {{zones::HANDLE, "handle", 5.0f}, {zones::DRUM, "drum", 6.0f}, {zones::INSERT, "insert point", 7.0f}};
constexpr int NDOCKS = (int)(sizeof(DOCKS) / sizeof(DOCKS[0]));
int g_dock = -1;                   // index into DOCKS of the dock holding the left hand, -1 = none
Vec3 g_dock_c[NDOCKS]{};           // this frame's dock centres (world) and whether each is on this gun
float g_dock_r[NDOCKS]{};
bool g_dock_on[NDOCKS]{};
Quat g_turn{0, 0, 0, 1};           // the hand's turn in the gun hand's frame, kept from the moment of the take
float g_check_t = -10.0f;
std::filesystem::file_time_type g_mtime{};

std::filesystem::path file_path() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "pairs.json";
}

void refresh() {   // at most once a second: re-read pairs.json when it changed
    const float t = now_s();
    if (t - g_check_t < PAIR_FILE_CHECK_S) return;
    g_check_t = t;
    std::error_code ec;
    const auto p = file_path();
    const auto mt = std::filesystem::last_write_time(p, ec);
    if (ec) { if (!g_pairs.empty()) { g_pairs.clear(); g_active = -1; LOGI("%s pairs: pairs.json gone: no pairs", TAG); } return; }
    if (mt == g_mtime) return;
    g_mtime = mt;
    json::Value v;
    if (!json::load_file(p.wstring(), v) || v.kind != json::Value::OBJ) return;   // caught mid-write: the next check reads it
    std::vector<Pair> next;
    if (const auto* arr = v.get("pairs"); arr != nullptr && arr->kind == json::Value::ARR) {
        for (const auto& e : arr->arr) {
            if (e.kind != json::Value::OBJ) continue;
            auto num = [&](const char* k, float d) { const auto* x = e.get(k); return x != nullptr && x->kind == json::Value::NUM ? (float)x->n : d; };
            auto str = [&](const char* k) { const auto* x = e.get(k); return x != nullptr && x->kind == json::Value::STR ? x->s : std::string(); };
            Pair q;
            q.n = (int)num("n", 0.0f);
            q.name = str("name");
            q.gun = str("gun");
            q.a = Vec3{num("ax", 0.0f), num("ay", 0.0f), num("az", 0.0f)};
            q.r = num("ar", PAIR_ACT_R_DEFAULT_M);
            q.l = Vec3{num("lx", 0.0f), num("ly", 0.0f), num("lz", 0.0f)};
            if (q.n > 0 && q.r > 0.0f) next.push_back(q);
        }
    }
    const auto* s = v.get("show");
    g_show = s != nullptr && s->kind == json::Value::NUM ? (int)s->n : 0;
    g_pairs = next;
    g_active = -1;   // a pair being edited is let go; the left grip takes it again
    LOGI("%s pairs: pairs.json read: %d pair(s), shown: %d", TAG, (int)g_pairs.size(), g_show);
}

int gun_now() { return (int)(bridge::view(bridge::S_WEAPON_NUM) + 0.5f); }
// which docks the gun in hand has: a handle on every handgun, a drum on the revolvers, an insert point on the GM 79
bool dock_applies(zones::Key k) {
    const weapons::Weapon* w = weapons::find(weapons::canonical(player::now().weapon_id));
    if (w == nullptr) return false;
    switch (k) {
    case zones::HANDLE: return w->shape == weapons::Shape::PISTOL && w->reload != weapons::Reload::NONE;
    case zones::DRUM: return w->breech == weapons::Breech::CYLINDER;
    case zones::INSERT: return w->breech == weapons::Breech::BREAK;
    default: return false;
    }
}

bool for_gun(const Pair& p, int gun) { return p.gun.empty() || p.gun == "any" || std::atoi(p.gun.c_str()) == gun; }

void put5(int slot, const Vec3& c, float r, float on) {
    bridge::put((bridge::Slot)(slot + 0), c.x);
    bridge::put((bridge::Slot)(slot + 1), c.y);
    bridge::put((bridge::Slot)(slot + 2), c.z);
    bridge::put((bridge::Slot)(slot + 3), r);
    bridge::put((bridge::Slot)(slot + 4), on);
}
void hide() {
    bridge::put((bridge::Slot)(bridge::S_PAIR_ACT + 4), 0.0f);
    bridge::put((bridge::Slot)(bridge::S_PAIR_LAND + 4), 0.0f);
}
} // namespace

void frame() {
    refresh();
    const auto& s = player::now();
    Vec3 rp{0, 0, 0};
    Quat rq{0, 0, 0, 1}, gq{0, 0, 0, 1};
    const bool ok = bridge::live() && s.weapon != nullptr && player::get_pose(field_obj(s.ik_right, "Target"), rp, rq) && zones::gun_rot(gq);
    gq = qnorm(gq);
    rq = qnorm(rq);
    auto world = [&](const Vec3& off) { return rp + rotate(gq, off); };
    const int gun = gun_now();
    const bool lg = bridge::held(bridge::S_LGRIP);
    const bool play = bridge::flag(bridge::S_CAN_USE_HANDS) && !bridge::flag(bridge::S_CUTSCENE);

    // the built-in docks: where each sits this frame, drawn on the gun when it is one of this gun's parts
    for (int i = 0; i < NDOCKS; ++i) {
        const zones::Zone z = zones::get(DOCKS[i].key);
        g_dock_on[i] = ok && dock_applies(DOCKS[i].key);
        g_dock_c[i] = world(z.off);
        g_dock_r[i] = z.r;
        if (g_dock_on[i]) zones::publish(DOCKS[i].key, g_dock_c[i], g_dock_r[i]);
        else zones::clear(DOCKS[i].key);
    }
    if (g_dock >= 0 && (!ok || !lg || !play || !g_dock_on[g_dock])) {
        LOGI("%s pairs: the left hand leaves the %s (%s)", TAG, DOCKS[g_dock].name, !lg ? "LG let go" : "the gun or the scene changed");
        if (DOCKS[g_dock].key == zones::DRUM) breech::drum_undock();
        g_dock = -1;
    }
    // 2026-10-27: rounds in the hand for a revolver, LG held, brought to the drum: the hand docks there (no fresh LG needed)
    if (g_dock < 0 && g_active < 0 && ok && play && lg && reload::rounds_in_hand() > 0) {
        Vec3 lp;
        for (int i = 0; i < NDOCKS; ++i) {
            if (DOCKS[i].key != zones::DRUM || !g_dock_on[i] || !bridge::room_to_world(bridge::hand_pos(bridge::LEFT), lp) || dist(g_dock_c[i], lp) > g_dock_r[i]) continue;
            g_dock = i;
            Vec3 hp;
            Quat hq;
            g_turn = player::get_pose(field_obj(s.ik_left, "Target"), hp, hq) ? qnorm(qmul(qinv(rq), qnorm(hq))) : Quat{0, 0, 0, 1};
            bridge::rumble(bridge::LEFT, PAIR_BUZZ_AMP, PAIR_BUZZ_SEC, PAIR_BUZZ_HZ);
            LOGI("%s pairs: rounds in hand at the drum: the left hand docks there (LT puts each in)", TAG);
            breech::drum_taken();
        }
    }
    if (g_dock >= 0) {   // the part's job: the drum each frame (LT taps, LT held drags), the GM 79's insert point on LT
        if (DOCKS[g_dock].key == zones::DRUM) breech::drum_dock_frame(bridge::pressed(bridge::S_LTRIG), bridge::held(bridge::S_LTRIG));
        else if (DOCKS[g_dock].key == zones::INSERT && bridge::pressed(bridge::S_LTRIG)) breech::insert_lt();
    }
    if (g_active >= 0 && (!ok || !lg || !play || g_active >= (int)g_pairs.size() || !for_gun(g_pairs[g_active], gun))) {
        LOGI("%s pairs: pair %d let go (%s)", TAG, g_active < (int)g_pairs.size() ? g_pairs[g_active].n : 0, !lg ? "LG let go" : "the gun or the scene changed");
        g_active = -1;
    }
    // a fresh LG inside an activation sphere; the slide / pump / bolt and the magazine come first (their own zones)
    if (g_active < 0 && g_dock < 0 && ok && play && bridge::pressed(bridge::S_LGRIP) && !rack::active() && !reload::hand_on_mag() && !reload::session_active()) {
        Vec3 lp;
        if (bridge::room_to_world(bridge::hand_pos(bridge::LEFT), lp)) {
            for (int i = 0; i < NDOCKS && !reload::round_in_hand(); ++i) {   // a round in hand goes into the gun, not onto a dock
                if (!g_dock_on[i] || dist(g_dock_c[i], lp) > g_dock_r[i]) continue;
                g_dock = i;
                Vec3 hp;
                Quat hq;
                g_turn = player::get_pose(field_obj(s.ik_left, "Target"), hp, hq) ? qnorm(qmul(qinv(rq), qnorm(hq))) : Quat{0, 0, 0, 1};
                bridge::rumble(bridge::LEFT, PAIR_BUZZ_AMP, PAIR_BUZZ_SEC, PAIR_BUZZ_HZ);
                LOGI("%s pairs: LG at the %s: the left hand docks there", TAG, DOCKS[i].name);
                if (DOCKS[i].key == zones::DRUM) breech::drum_taken();
                break;
            }
            for (int i = 0; i < (int)g_pairs.size() && g_dock < 0; ++i) {
                const Pair& p = g_pairs[i];
                if (!for_gun(p, gun) || dist(world(p.a), lp) > p.r) continue;
                g_active = i;
                Vec3 hp;
                Quat hq;   // the hand keeps the turn it had, relative to the gun hand
                g_turn = player::get_pose(field_obj(s.ik_left, "Target"), hp, hq) ? qnorm(qmul(qinv(rq), qnorm(hq))) : Quat{0, 0, 0, 1};
                bridge::rumble(bridge::LEFT, PAIR_BUZZ_AMP, PAIR_BUZZ_SEC, PAIR_BUZZ_HZ);
                LOGI("%s pairs: pair %d \"%s\" taken: the left hand goes to its landing spot", TAG, p.n, p.name.c_str());
                break;
            }
        }
    }
    bridge::put(bridge::S_PAIR_ACTIVE, g_active >= 0 ? (float)g_pairs[g_active].n : 0.0f);

    // 2026-10-26 (Tefa: "automatic saving for hand poses on different land spots and different start grab spots"): where the
    // left hand is, so Hand Poser keeps one pose per gun AND spot. A landing spot while a pair holds the hand, the slide /
    // pump / bolt, the magazine, or an activation sphere the hand is inside without having taken it.
    float spot = 0.0f;
    if (g_dock >= 0) spot = DOCKS[g_dock].spot;
    else if (g_active >= 0) spot = 1000.0f + (float)g_pairs[g_active].n;
    else if (rack::active()) spot = rack::slide_from_left() ? 8.0f : 3.0f;   // 2026-10-28: a pistol's slide from the left
    else if (reload::hand_on_mag()) spot = 4.0f;
    else if (ok && play) {
        Vec3 lp;
        if (bridge::room_to_world(bridge::hand_pos(bridge::LEFT), lp))
            for (const auto& p : g_pairs)
                if (for_gun(p, gun) && dist(world(p.a), lp) <= p.r) { spot = 2000.0f + (float)p.n; break; }
    }
    bridge::put(bridge::S_LEFT_SPOT, spot);

    // the pair picked in the Grab Zones window, drawn on the gun: the activation sphere and the landing dot
    const Pair* shown = nullptr;
    for (const auto& p : g_pairs) if (p.n == g_show && for_gun(p, gun)) { shown = &p; break; }
    if (!ok || shown == nullptr) { hide(); return; }
    put5(bridge::S_PAIR_ACT, world(shown->a), shown->r, 1.0f);
    put5(bridge::S_PAIR_LAND, world(shown->l), PAIR_LAND_DOT_M, 1.0f);
}

bool active() { return g_active >= 0 || g_dock >= 0; }

bool part_center(zones::Key k, Vec3& c, float& r) {
    for (int i = 0; i < NDOCKS; ++i) if (DOCKS[i].key == k && g_dock_on[i]) { c = g_dock_c[i]; r = g_dock_r[i]; return true; }
    return false;
}

bool landing(const Vec3& rp, const Quat& rq, Vec3& rel, Quat& qrel) {
    if (g_dock >= 0) {   // a built-in dock: the hand sits on the part's centre, with the turn it had at the take
        rel = rotate(qinv(qnorm(rq)), g_dock_c[g_dock] - rp);
        qrel = g_turn;
        return true;
    }
    if (g_active < 0 || g_active >= (int)g_pairs.size()) return false;
    Quat gq;
    if (!zones::gun_rot(gq)) return false;
    const Vec3 w = rp + rotate(qnorm(gq), g_pairs[g_active].l);
    rel = rotate(qinv(qnorm(rq)), w - rp);
    qrel = g_turn;
    return true;
}

} // namespace vn::pairs
