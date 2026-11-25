// twomag.cpp -- see twomag.h
#include "twomag.h"
#include "bridge.h"
#include "player.h"
#include "settings.h"

#include <cmath>
#include <string>

namespace vn::twomag {

using namespace vn::settings;

namespace {
Has g_has = Has::NONE;
int g_old_rounds = 0;
int g_spare_rounds = -1;   // b163: the one behind, while two are in the hand: -1 = a fresh pouch magazine (looks full)
bool g_ready = false;      // b163: LT swapped them since the two came together
} // namespace

Has has() { return g_has; }

void take_spare() {
    g_has = Has::SPARE;
    g_spare_rounds = -1;
    g_ready = false;
    LOGI("%s twomag: a spare magazine in the left hand, the gun's still seated (carried %d): LG held to the gun's magazine docks, right B releases it", TAG, player::reserve());
}

void swap(int old_rounds) {
    g_has = Has::OLD;
    g_old_rounds = old_rounds < 0 ? 0 : old_rounds;
    LOGI("%s twomag: the spare goes into the gun; the old magazine (%d round(s)) stays in the hand until LG is let go", TAG, g_old_rounds);
}

int exchange(int front_rounds) {
    const int back = g_spare_rounds;
    g_spare_rounds = front_rounds;
    g_ready = true;
    LOGI("%s twomag: LT: the two swapped round in the palm; the front one (%s) goes in at the well, the one behind has %s", TAG,
         back < 0 ? "fresh from the pouch" : (std::to_string(back) + " round(s)").c_str(),
         front_rounds < 0 ? "a fresh one's" : (std::to_string(front_rounds) + " round(s)").c_str());
    return back;
}
bool ready() { return g_has == Has::SPARE && g_ready; }
bool behind_is_old() { return g_has == Has::SPARE && g_spare_rounds >= 0; }
void went_in() {
    if (g_has != Has::SPARE) return;
    const int cap = player::capacity();
    g_old_rounds = g_spare_rounds >= 0 ? g_spare_rounds : (cap > 0 ? cap : 1);
    g_has = Has::OLD;
    g_spare_rounds = -1;
    g_ready = false;
    LOGI("%s twomag: the front one goes in; the other (%d round(s)) stays in the palm until LG is let go", TAG, g_old_rounds);
}
void again() {
    if (g_has != Has::OLD) return;
    g_has = Has::SPARE;
    g_spare_rounds = g_old_rounds;
    g_ready = false;
    LOGI("%s twomag: the gun's magazine out into the hand, the old one (%d round(s)) still in the palm: two in the hand again, LT swaps them", TAG, g_spare_rounds);
}

void clear(const char* why) {
    if (g_has == Has::NONE) return;
    LOGI("%s twomag: %s gone from the hand (%s)", TAG, g_has == Has::SPARE ? "the spare" : "the old magazine", why);
    g_has = Has::NONE;
    g_old_rounds = 0;
    g_spare_rounds = -1;
    g_ready = false;
}

int rounds() {
    if (g_has == Has::OLD) return g_old_rounds;
    const int cap = player::capacity();
    if (g_has == Has::SPARE && g_spare_rounds >= 0) return g_spare_rounds;   // b163: one that was in the gun looks as full as it is
    return g_has == Has::SPARE ? (cap > 0 ? cap : 1) : 0;
}

void publish(Vec3 p, Quat q) {
    if (g_has == Has::NONE) return;
    using namespace bridge;
    const float v[7] = {p.x, p.y, p.z, q.x, q.y, q.z, q.w};
    for (int i = 0; i < 7; ++i) put(static_cast<Slot>(S_MAG2_POS + i), v[i]);
    put(S_MAG2_ROLE, g_has == Has::SPARE ? 1.0f : 2.0f);
    put(S_MAG2_ROUNDS, static_cast<float>(rounds()));
    put(S_MAG2_ON, view(S_FRAME) + 1.0f);   // last: the stamp says the numbers above are this frame's
}

bool drawn_pose(Vec3& p, Quat& q) {
    using namespace bridge;
    const float stamp = view(S_MAG2_DRAWN_ON);
    // (a frame stamp, not a small room number: bridge::has() calls anything over 499 "no value", which was every stamp after 6 s)
    if (!live() || stamp < 0.5f || std::fabs(stamp - 1.0f - view(S_FRAME)) > TWOMAG_DRAWN_STALE_FRAMES) return false;
    p = view_vec3(S_MAG2_DRAWN_POS);
    q = view_quat(S_MAG2_DRAWN_ROT);
    return true;
}

} // namespace vn::twomag
