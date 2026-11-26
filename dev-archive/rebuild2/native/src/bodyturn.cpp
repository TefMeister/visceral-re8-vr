// bodyturn.cpp -- see bodyturn.h
#include "bodyturn.h"

#include "base.h"
#include "bridge.h"
#include "paths.h"
#include "switches.h"

#include <algorithm>
#include <cstring>
#include <fstream>

namespace vr8::bodyturn {

namespace {
// ---- the named numbers (Tefa's words of 2026-11-26; the rates are b178's, worn there) -----------------------------
constexpr float PI = 3.14159265358979f;
constexpr float DEG = PI / 180.0f;
// Worn 2026-11-26 12:3x with a free zone (35 degrees free, slow to 60, fast past it): "working", then Tefa: "body
// ... must smoothly turn to the direction of the hmd with just a bit of lag, that's what makes it natural i think"
// and, asked which: "B i think" (always, standing too, no free zone anywhere). So: the body closes the gap to the
// head all the time, so that a gap is down to about a third after LAG_S.
// Worn 12:4x: then Tefa: "i think there has to be a little dead zone to head movement, like 10 degrees maybe and
// then the body turns all the way to where the hmd is pointing". So: nothing inside DEAD_DEG; past it a turn
// starts and runs (with the same small lag, never slower than MIN_RATE_DEG_S) until the body is within
// SETTLE_DEG of the head.
// Tuned in play the same day (bodyturn.txt): lag 0.18 s ("it feels good"), dead zone 25 degrees ("this is really good now").
constexpr float LAG_S = 0.18f;             // the "bit of lag"; bodyturn.txt in the data folder overrides it, live
constexpr float DEAD_DEG = 25.0f;          // the head may look this far off the body; bodyturn.txt's 2nd number
constexpr float DEAD_MAX_DEG = 90.0f;
constexpr float SETTLE_DEG = 1.0f;         // a turn ends this close to the head
constexpr float MIN_RATE_DEG_S = 25.0f;    // a turn never crawls: it finishes
constexpr float LAG_MIN_S = 0.02f, LAG_MAX_S = 3.0f;
constexpr float LAG_FILE_EVERY_S = 2.0f;   // how often bodyturn.txt is looked at (so the lag can be tuned in play)
constexpr float FRESH_S = 0.25f;           // the script's numbers older than this: the game's own answer stands
constexpr float REPORT_EVERY_S = 5.0f;     // one line this often while the head is off the body

bool g_have_body = false;
float g_body = 0.0f;            // the body's yaw, radians, in the camera controller's measure
float g_last_base = 0.0f;       // the view's yaw with the headset's own turn taken out
float g_last_stamp = -1.0f;     // the script's counter when its yaws were last new
float g_fresh_at = -10.0f;      // when the body's direction was last worked out
float g_last_time = -1.0f;
float g_last_report = 0.0f;
unsigned long long g_answers = 0;
bool g_hook_tried = false, g_hooked = false;

float g_lag = LAG_S;
float g_dead = DEAD_DEG;
bool g_turning = false;
float g_head_off = 0.0f;       // head - body after this frame's step, radians
float g_lag_read_at = -LAG_FILE_EVERY_S;

// reframework/data/visceral_re8/bodyturn.txt: the lag in seconds, then the dead zone in degrees (both optional).
// No file = LAG_S and DEAD_DEG.
void read_lag(float now) {
    if (now - g_lag_read_at < LAG_FILE_EVERY_S) return;
    g_lag_read_at = now;
    float lag = LAG_S;
    std::ifstream f(paths::data(L"bodyturn.txt"));
    float v = 0.0f;
    if (f >> v && std::isfinite(v)) lag = std::clamp(v, LAG_MIN_S, LAG_MAX_S);
    float dead = DEAD_DEG;
    if (f >> v && std::isfinite(v)) dead = std::clamp(v, 0.0f, DEAD_MAX_DEG);
    if (lag != g_lag || dead != g_dead)
        LOGI("%s body turn: the lag is %.2f s and the dead zone %.0f degrees now", TAG, lag, dead);
    g_lag = lag;
    g_dead = dead;
}

float wrap(float a) {
    while (a > PI) a -= 2.0f * PI;
    while (a < -PI) a += 2.0f * PI;
    return a;
}

int pre_destination_angle(int, void**, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

// the game asked which way the body should face: the answer is a float, in degrees
void post_destination_angle(void** ret_val, REFrameworkTypeDefinitionHandle, unsigned long long) {
    if (ret_val == nullptr || !g_have_body || now_s() - g_fresh_at > FRESH_S) return;
    const float degrees = g_body / DEG;
    uint32_t bits = 0;
    std::memcpy(&bits, &degrees, sizeof bits);
    *ret_val = (void*)(uintptr_t)bits;
    ++g_answers;
}

void place_hook() {
    if (g_hook_tried) return;
    g_hook_tried = true;
    auto* method = API::get()->tdb()->find_method("app.PlayerMovement", "destinationAngle");
    if (method == nullptr) {
        LOGW("%s body turn: app.PlayerMovement.destinationAngle was not found; the body is left to the game", TAG);
        return;
    }
    method->add_hook(pre_destination_angle, post_destination_angle, false);
    g_hooked = true;
    LOGI("%s body turn: the game's \"which way should the body face\" question is answered here now", TAG);
}

void stand_down() {
    g_have_body = false;
    bridge::write(bridge::S_MOVE_TURN, 0.0f);
}
} // namespace

float head_off() { return g_have_body ? g_head_off : 0.0f; }

void frame() {
    place_hook();
    if (!g_hooked) return;
    if (!bridge::live() || !bridge::flag(bridge::S_TURN_OK)) { stand_down(); return; }

    const float now = now_s();
    const float stamp = bridge::read(bridge::S_TURN_STAMP);
    if (stamp == g_last_stamp) {                       // the script's camera step did not run this frame
        if (now - g_fresh_at > FRESH_S) stand_down();
        return;
    }
    g_last_stamp = stamp;
    const float dt = g_last_time < 0.0f ? 0.011f : std::clamp(now - g_last_time, 0.0005f, 0.1f);
    g_last_time = now;

    const float head = bridge::read(bridge::S_HEAD_YAW);
    const float base = bridge::read(bridge::S_BASE_YAW);
    if (!std::isfinite(head) || !std::isfinite(base)) { stand_down(); return; }
    if (!g_have_body) {
        g_body = head;
        g_have_body = true;
        g_turning = false;
        LOGI("%s body turn: started (the body faces the head)", TAG);
    } else {
        g_body = wrap(g_body + wrap(base - g_last_base));     // the stick or a re-centre turned the view
    }
    g_last_base = base;

    const float off = wrap(head - g_body);
    const float off_deg = std::fabs(off) / DEG;
    read_lag(now);
    if (!g_turning && off_deg > g_dead) g_turning = true;
    if (g_turning) {
        const float step = std::min(std::fabs(off), std::max(std::fabs(off) * (1.0f - std::exp(-dt / g_lag)),
                                                             MIN_RATE_DEG_S * DEG * dt));
        g_body = wrap(g_body + (off < 0.0f ? -step : step));
        if (std::fabs(wrap(head - g_body)) < SETTLE_DEG * DEG) g_turning = false;
    }
    g_fresh_at = now;

    // the walk: the stick turned by (head - body), so stick forward walks where the head looks
    float move_turn = wrap(head - g_body);
    g_head_off = move_turn;
    if (switches::off("bodyturn-walk")) move_turn = 0.0f;
    if (switches::off("bodyturn-walk-flip")) move_turn = -move_turn;
    bridge::write(bridge::S_MOVE_TURN, move_turn);

    if (off_deg > 5.0f && now - g_last_report >= REPORT_EVERY_S) {
        g_last_report = now;
        LOGI("%s body turn: head %.0f deg off the body (head %.0f, body %.0f), %llu answers given", TAG,
             wrap(head - g_body) / DEG, head / DEG, g_body / DEG, g_answers);
    }
}

} // namespace vr8::bodyturn
