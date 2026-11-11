// reload_throw.cpp -- the thrown magazine, handed to the Lua (2026-11-05, Tefa: "throwing away a used mag, the ammo count
// should not change if it is even partially full as that messes with game's systems and changes the actual game, but for
// show, and that sound would also play from where it lands").
//
// The magazine that drops today is the gun's own "Magazine" joint, so it can never lie on the floor while the next one is
// in the gun: it falls RELOAD_FALL_SEC and is hidden. Here, the moment it leaves (let go of, or out of the magwell), its
// pose and the hand's speed go to visceral_re8_magthrow.lua over the bridge (S_MAGTHROW_*). The Lua makes a copy of the
// gun's mesh showing only the magazine part, flies it, lands it on the floor and plays the sound there. When the Lua says
// it has the copy (S_MAGTHROW_ACK), the joint's fall is cut short (reload.cpp) so the two are never seen together.
// The ammo is untouched here: the dropped magazine's rounds already stay counted (reload.cpp, 2026-10-25).
#include "reload_internal.h"
#include "reload.h"
#include "bridge.h"
#include "joints.h"
#include "settings.h"

#include <cmath>

namespace vn::reload::detail {

using namespace vn::settings;
using joints::now_s;

namespace {
struct Sample { float t; Vec3 p; };
Sample g_hist[THROW_SAMPLES];
int g_hist_n = 0;
float g_seq = 0.0f;   // the last SEQ handed over
} // namespace

void throw_sample(Vec3 p) {   // every frame the magazine is in the hand: where it is
    if (g_hist_n == THROW_SAMPLES) {
        for (int i = 1; i < THROW_SAMPLES; ++i) g_hist[i - 1] = g_hist[i];
        --g_hist_n;
    }
    g_hist[g_hist_n++] = Sample{now_s(), p};
}

// the speed over the last THROW_WINDOW_SEC (oldest sample still inside it to the newest), capped
static Vec3 throw_velocity() {
    if (g_hist_n < 2) return Vec3{0, 0, 0};
    const Sample& last = g_hist[g_hist_n - 1];
    int k = g_hist_n - 2;
    while (k > 0 && last.t - g_hist[k - 1].t <= THROW_WINDOW_SEC) --k;
    const float dt = last.t - g_hist[k].t;
    if (dt <= 0.001f) return Vec3{0, 0, 0};
    Vec3 v = (last.p - g_hist[k].p) * (1.0f / dt);
    const float sp = std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (sp > THROW_MAX_SPEED) v = v * (THROW_MAX_SPEED / sp);
    return v;
}

void throw_hand_over(Vec3 mag_pos, Quat mag_rot, bool from_hand, int rounds_look) {
    const int part = mag_part();
    const Vec3 v = from_hand ? throw_velocity() : Vec3{0, 0, 0};
    g_hist_n = 0;
    // the copy is the whole gun mesh at rest, so its root goes where the gun's root would be with the magazine seated
    // where the magazine is now: root = magazine * inverse(the magazine's seated pose in the gun)
    const Quat rr = qnorm(qmul(qnorm(mag_rot), qinv(qnorm(g_rest_rot))));
    const Vec3 rp = mag_pos - rotate(rr, g_rest_pos);
    using namespace bridge;
    put(S_MAGTHROW_ROOT_POS, rp.x); put(static_cast<Slot>(S_MAGTHROW_ROOT_POS + 1), rp.y); put(static_cast<Slot>(S_MAGTHROW_ROOT_POS + 2), rp.z);
    put(S_MAGTHROW_ROOT_ROT, rr.x); put(static_cast<Slot>(S_MAGTHROW_ROOT_ROT + 1), rr.y);
    put(static_cast<Slot>(S_MAGTHROW_ROOT_ROT + 2), rr.z); put(static_cast<Slot>(S_MAGTHROW_ROOT_ROT + 3), rr.w);
    put(S_MAGTHROW_PIVOT, mag_pos.x); put(static_cast<Slot>(S_MAGTHROW_PIVOT + 1), mag_pos.y); put(static_cast<Slot>(S_MAGTHROW_PIVOT + 2), mag_pos.z);
    put(S_MAGTHROW_VEL, v.x); put(static_cast<Slot>(S_MAGTHROW_VEL + 1), v.y); put(static_cast<Slot>(S_MAGTHROW_VEL + 2), v.z);
    put(S_MAGTHROW_PART, static_cast<float>(part));
    // 2026-11-05 (magdisp.cpp): the copy shows its rounds parts only when the magazine holds any (its OWN count, not the gun's)
    const int rounds = rounds_look >= 0 ? rounds_look : reload::mag_rounds_out();
    put(S_MAGTHROW_ROUNDS, static_cast<float>(rounds >= 0 ? rounds : g_mag_rounds));
    g_seq += 1.0f;
    put(S_MAGTHROW_SEQ, g_seq);   // last: the Lua reads the numbers above once this changes
    LOGI("%s reload: magazine handed to the throw copy #%.0f (%s, part %d, speed %.2f m/s)", TAG, g_seq,
         from_hand ? "let go of" : "out of the magwell", part, std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z));
}

bool throw_taken() { return g_seq > 0.0f && bridge::view(bridge::S_MAGTHROW_ACK) == g_seq; }

} // namespace vn::reload::detail
