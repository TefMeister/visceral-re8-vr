// turn.cpp -- the body turns like RE2's, through the game's own body-follow rule (2026-10-29, Fable).
//
// Tefa: "please work on Ethan's body to turn like it does more naturally in RE2, we did get that sort of working
// already but it broke a ton of things". The 10-24/25 attempt (body.cpp) turned the DRAWN joints: the arms hung off
// turned shoulders, the body swung into the view, a mess. The game itself has the thing we want:
//
//   app.PlayerMovement (the player's movement part) turns the player's transform toward the camera's yaw with its own
//   rule: updateAngle() / calcAngleDiff() / destinationAngle(), the turn starting once the camera is further off the
//   body than the STATIC TurnStartThreshold (and AutoTurnStartThreshold / AutoTurnSec for the standing auto-turn),
//   at a speed from TurnAccelSec / AngleFollowRate / getTurnSpeed(), capped by MaxAngleDiff; processTurn() plays the
//   turn-in-place animation, so the feet move with it [inferred-static 2026-10-29, from the type's members].
//   In VR praydog's script hands the game the HEADSET'S yaw as the camera's (the camera controller's Rotation, every
//   frame), so this rule is what makes the body "one chunk with the head" today: the threshold is small and the follow
//   fast [hypothesis until the values are read live].
//
// So, the lever: leave the joints alone, and give the game's rule Tefa's numbers (2026-10-25: "body rotate on standing
// still after hmd has moved either right 60 degrees or left 60 degrees ... when walking it's 45 degrees and when running
// 30") and a slower turn. The statics are written every frame for the state of the moment (stand / walk / run), the
// originals remembered and put back when the box is unticked. The camera stays the headset's: nothing here touches
// the view or the transform. [compile-verified] at most until it has run.

#include "turn.h"
#include "body.h"
#include "bridge.h"
#include "player.h"
#include "settings.h"
#include "joints.h"

#include <cmath>
#include <cstring>

namespace vn::turn {

using namespace vn::settings;
using namespace vn::joints;

namespace {
constexpr float DEG = 3.14159265f / 180.0f;

struct Static { const char* name; API::Field* f = nullptr; float original = 0.0f; bool have = false; };
Static g_s[] = {{"TurnStartThreshold"}, {"AutoTurnStartThreshold"}, {"AutoTurnSec"}, {"TurnAccelSec"}, {"MaxAngleDiff"}};
constexpr int S_TURN_START = 0, S_AUTO_START = 1, S_AUTO_SEC = 2, S_ACCEL_SEC = 3, S_MAX_DIFF = 4;
bool g_looked = false, g_any = false, g_written = false;
API::TypeDefinition* g_td = nullptr;
API::Method* g_follow_rate_get = nullptr;
MO* g_move = nullptr;             // the player's app.PlayerMovement
float g_log_t = -10.0f;
const char* g_mode = "off";
bool g_was_active = false;

float* slot(Static& s) { return s.f != nullptr ? (float*)s.f->get_data_raw(nullptr, true) : nullptr; }

void look() {
    if (g_looked) return;
    g_looked = true;
    g_td = API::get()->tdb()->find_type("app.PlayerMovement");
    if (g_td == nullptr) { LOGI("%s turn: app.PlayerMovement not in the type database", TAG); return; }
    for (auto& s : g_s) {
        s.f = g_td->find_field(s.name);
        float* p = slot(s);
        s.have = p != nullptr;
        if (s.have) s.original = *p;
    }
    g_any = g_s[S_TURN_START].have;
    LOGI("%s turn: the game's own body-follow settings: TurnStartThreshold %s, AutoTurnStartThreshold %s, AutoTurnSec %s, TurnAccelSec %s, MaxAngleDiff %s",
         TAG, g_s[0].have ? std::to_string(g_s[0].original).c_str() : "?", g_s[1].have ? std::to_string(g_s[1].original).c_str() : "?",
         g_s[2].have ? std::to_string(g_s[2].original).c_str() : "?", g_s[3].have ? std::to_string(g_s[3].original).c_str() : "?",
         g_s[4].have ? std::to_string(g_s[4].original).c_str() : "?");
}

MO* movement() {
    const auto& s = player::now();
    if (s.go == nullptr) return nullptr;
    if (g_move != nullptr && is_managed(g_move)) return g_move;
    // getComponent(System.Type) wants the exact class: the player's movement part is a per-character subclass
    // (2026-10-29 flat run: the base name found nothing); Ethan is Pl1001, Chris Pl2001, the others for the DLC
    for (const char* t : {"app.PlayerMovementPl1001", "app.PlayerMovementPl2001", "app.PlayerMovementPl3000", "app.PlayerMovementPl4000", "app.PlayerMovementPl6000", "app.PlayerMovement"}) {
        g_move = (MO*)component(s.go, t);
        if (g_move != nullptr) { LOGI("%s turn: the player's movement part found as %s", TAG, t); break; }
    }
    static bool told_none = false;
    if (g_move == nullptr && !told_none) { told_none = true; LOGI("%s turn: no app.PlayerMovement* component on the player (the state stays 'stand')", TAG); }
    return g_move;
}

void write(float start_deg, float auto_deg, float auto_sec, float accel_sec) {
    if (float* p = slot(g_s[S_TURN_START])) *p = start_deg;
    if (float* p = slot(g_s[S_AUTO_START])) *p = auto_deg;
    if (float* p = slot(g_s[S_AUTO_SEC])) *p = auto_sec;
    if (float* p = slot(g_s[S_ACCEL_SEC])) *p = accel_sec;
    g_written = true;
}

void restore() {
    if (!g_written) return;
    for (auto& s : g_s) if (float* p = slot(s)) *p = s.original;
    g_written = false;
    LOGI("%s turn: the game's own turn settings put back", TAG);
}
} // namespace

bool active() { return TURN_GAME_ON && g_any && (TURN_FORCE_ON || bridge::flag(bridge::S_BODY_TURN)); }

void frame() {
    if (!TURN_GAME_ON) return;
    look();
    if (!g_any) return;
    const bool on = active() && (bridge::live() || TURN_FORCE_ON);   // the forced desk test runs flat too (the bridge speaks only with a headset)
    if (on != g_was_active) {
        g_was_active = on;
        LOGI("%s turn: %s", TAG, on ? "ON: the game's body-follow rule gets Tefa's deadzone and a slow turn" : "off");
        if (!on) restore();
    }
    if (!on) return;
    MO* mv = movement();
    // the state of the moment, from the game's own flags when the movement part is there
    bool sprint = false, moving = false;
    if (mv != nullptr) {
        sprint = call_direct<bool>(mv, "get_isSprint", false);
        moving = call_direct<bool>(mv, "get_isMove", false);
    }
    float dead = TURN_STAND_DEG;
    if (sprint) { g_mode = "run"; dead = TURN_RUN_DEG; }
    else if (moving) { g_mode = "walk"; dead = TURN_WALK_DEG; }
    else g_mode = "stand";
    write(dead, dead, TURN_SEC, TURN_ACCEL_SEC);

    const float t = now_s();
    if (t - g_log_t > 1.0f) {
        g_log_t = t;
        float follow = -1.0f;
        if (mv != nullptr) follow = call_direct<float>(mv, "get_AngleFollowSec", -1.0f);
        // the body's facing and the camera's, so the lag can be read off the log (the game's forward is +Z)
        float body_yaw = -999.0f, cam_yaw = -999.0f;
        const auto& snap = player::now();
        Vec3 pp; Quat pq;
        if (snap.tf != nullptr && player::get_pose(snap.tf, pp, pq)) body_yaw = yaw_of(rotate(pq, Vec3{0, 0, 1})) / DEG;
        if (mv != nullptr) { Quat cq; if (get_q(JOINT, mv, "get_CameraRotation", cq)) cam_yaw = yaw_of(rotate(cq, Vec3{0, 0, 1})) / DEG; }
        LOGI("%s turn: mode %s, deadzone %.0f deg, turn %.2f s (accel %.2f), AngleFollowSec %.3f, threshold reads %.1f; body yaw %.0f, camera yaw %.0f (off by %.0f)", TAG, g_mode, dead,
             TURN_SEC, TURN_ACCEL_SEC, follow, slot(g_s[S_TURN_START]) ? *slot(g_s[S_TURN_START]) : -1.0f, body_yaw, cam_yaw,
             (body_yaw > -900 && cam_yaw > -900) ? wrap_pi((cam_yaw - body_yaw) * DEG) / DEG : -999.0f);
    }
}

} // namespace vn::turn
