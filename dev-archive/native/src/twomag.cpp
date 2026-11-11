// twomag.cpp -- see twomag.h
#include "twomag.h"
#include "bridge.h"
#include "player.h"
#include "settings.h"

#include <cmath>

namespace vn::twomag {

using namespace vn::settings;

namespace {
Has g_has = Has::NONE;
int g_old_rounds = 0;
} // namespace

Has has() { return g_has; }

void take_spare() {
    g_has = Has::SPARE;
    LOGI("%s twomag: a spare magazine in the left hand, the gun's still seated (carried %d): LG held to the gun's magazine docks, right B releases it", TAG, player::reserve());
}

void swap(int old_rounds) {
    g_has = Has::OLD;
    g_old_rounds = old_rounds < 0 ? 0 : old_rounds;
    LOGI("%s twomag: the spare goes into the gun; the old magazine (%d round(s)) stays in the hand until LG is let go", TAG, g_old_rounds);
}

void clear(const char* why) {
    if (g_has == Has::NONE) return;
    LOGI("%s twomag: %s gone from the hand (%s)", TAG, g_has == Has::SPARE ? "the spare" : "the old magazine", why);
    g_has = Has::NONE;
    g_old_rounds = 0;
}

int rounds() {
    if (g_has == Has::OLD) return g_old_rounds;
    const int cap = player::capacity();
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
