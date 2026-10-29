// gunreport.cpp -- see gunreport.h
#include "gunreport.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "settings.h"

#include <windows.h>

#include <cmath>
#include <cstdio>
#include <ctime>
#include <filesystem>
#include <string>

namespace vn::gunreport {

using namespace vn::settings;
using namespace vn::joints;

namespace {
float g_log_t = -100.0f;
bool g_have_last = false;
Vec3 g_last_in_hand{};           // the gun root in the hand's frame at the last line
std::string g_last_weapon;
FILE* g_file = nullptr;
bool g_file_tried = false;

float len(Vec3 v) { return std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z); }

// the IK's three joints by hash: 0 the upper arm, 1 the forearm, 2 the hand (app.AnimIK2Bone's <HashJointN>k__BackingField).
// The Motion's joint poses are in the PLAYER'S frame (first flat run: the hand read 55 m from the gun = the player's
// distance from the world origin), so they are turned into world poses with the player transform
bool ik_joint(MO* ik, int n, Vec3& p, Quat& q) {
    const char* names[] = {"<HashJoint0>k__BackingField", "<HashJoint1>k__BackingField", "<HashJoint2>k__BackingField"};
    auto* h = field_ptr<uint32_t>(ik, names[n]);
    Vec3 lp, pp;
    Quat lq, pq;
    const auto& s = player::now();
    if (h == nullptr || !player::motion_joint_hash(*h, lp, lq) || s.tf == nullptr || !player::get_pose(s.tf, pp, pq)) return false;
    pq = qnorm(pq);
    p = pp + rotate(pq, lp);
    q = qnorm(qmul(pq, lq));
    return true;
}

void open_file() {
    if (g_file_tried) return;
    g_file_tried = true;
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto dir = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "gunreports";
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    std::time_t t = std::time(nullptr);
    std::tm tm{};
    localtime_s(&tm, &t);
    wchar_t name[64]{};
    wcsftime(name, 64, L"gunreport-%Y-%m-%d-%H%M.txt", &tm);
    if (_wfopen_s(&g_file, (dir / name).c_str(), L"ab") != 0) g_file = nullptr;
    if (g_file != nullptr) LOGI("%s gunreport: this launch's lines also go to reframework/data/visceral_re8/gunreports/%ls", TAG, name);
}

void emit(const char* line) {
    LOGI("%s gunreport: %s", TAG, line);
    open_file();
    if (g_file == nullptr) return;
    std::time_t t = std::time(nullptr);
    std::tm tm{};
    localtime_s(&tm, &t);
    char stamp[32]{};
    std::strftime(stamp, 32, "%H:%M:%S", &tm);
    std::fprintf(g_file, "%s %s\n", stamp, line);
    std::fflush(g_file);
}
} // namespace

void frame() {
    if (!GUNREPORT_ON) return;
    const auto& s = player::now();
    if (s.weapon_tf == nullptr || s.ik_right == nullptr) { g_have_last = false; return; }
    if (s.weapon_id != g_last_weapon) { g_last_weapon = s.weapon_id; g_have_last = false; }

    // the gun in the hand's own frame: the one number that should be the same every launch
    Vec3 hp, wp;
    Quat hq, wq;
    const bool hand_ok = ik_joint(s.ik_right, 2, hp, hq);
    const bool gun_ok = player::get_pose(s.weapon_tf, wp, wq);
    Vec3 in_hand{};
    if (hand_ok && gun_ok) in_hand = rotate(qinv(qnorm(hq)), wp - hp);

    const float t = now_s();
    bool due = t - g_log_t > GUNREPORT_PERIOD_S;
    // a move of the gun in the hand brings a line at once, but never more than one a second (the first run wrote one a frame)
    if (!due && g_have_last && hand_ok && gun_ok && t - g_log_t > GUNREPORT_CHANGE_MIN_GAP_S && len(in_hand - g_last_in_hand) > GUNREPORT_CHANGE_M) due = true;
    if (!due) return;
    g_log_t = t;
    if (hand_ok && gun_ok) { g_have_last = true; g_last_in_hand = in_hand; }

    // praydog's target for the hand, and the arm's reach toward it
    Vec3 tp, j0, j1;
    Quat tq, q0, q1;
    MO* target = field_obj(s.ik_right, "Target");
    const bool target_ok = target != nullptr && player::get_pose(target, tp, tq);
    const bool arm_ok = ik_joint(s.ik_right, 0, j0, q0) && ik_joint(s.ik_right, 1, j1, q1) && hand_ok;
    const float arm_len = arm_ok ? len(j1 - j0) + len(hp - j1) : -1.0f;
    const float reach = (arm_ok && target_ok) ? len(tp - j0) : -1.0f;

    char line[640];
    int n = std::snprintf(line, sizeof line, "%s | aim %d hands %d reload %d left-docked %d | ", s.weapon_id.empty() ? "(no id)" : s.weapon_id.c_str(),
                          bridge::flag(bridge::S_AIMING) ? 1 : 0, bridge::flag(bridge::S_CAN_USE_HANDS) ? 1 : 0,
                          bridge::flag(bridge::S_IS_RELOADING) ? 1 : 0, bridge::flag(bridge::S_GRIPPING_WEAPON) ? 1 : 0);
    if (target_ok && hand_ok) n += std::snprintf(line + n, sizeof line - n, "target->hand %.1f cm (hand %.1f cm %s the target) | ", len(hp - tp) * 100, std::fabs(hp.y - tp.y) * 100, hp.y < tp.y ? "BELOW" : "above");
    else n += std::snprintf(line + n, sizeof line - n, "target->hand ? | ");
    if (hand_ok && gun_ok) n += std::snprintf(line + n, sizeof line - n, "hand->gun root %.1f cm, in the hand's frame %.1f %.1f %.1f cm (gun %.1f cm %s the hand) | ",
                                              len(wp - hp) * 100, in_hand.x * 100, in_hand.y * 100, in_hand.z * 100, std::fabs(wp.y - hp.y) * 100, wp.y < hp.y ? "BELOW" : "above");
    else n += std::snprintf(line + n, sizeof line - n, "hand->gun ? | ");
    if (reach >= 0) n += std::snprintf(line + n, sizeof line - n, "reach: shoulder->target %.1f cm, arm %.1f cm%s", reach * 100, arm_len * 100, reach > arm_len ? " OUT OF REACH" : "");
    else n += std::snprintf(line + n, sizeof line - n, "reach: ? (arm %.1f)", arm_len * 100);
    if (bridge::flag(bridge::S_HANDS_W_OK) && target_ok) {
        const Vec3 pr{bridge::view(bridge::S_RHAND_W), bridge::view((bridge::Slot)(bridge::S_RHAND_W + 1)), bridge::view((bridge::Slot)(bridge::S_RHAND_W + 2))};
        n += std::snprintf(line + n, sizeof line - n, " | praydog's hand pos vs the IK target %.1f cm", len(pr - tp) * 100);
    }
    emit(line);
}

} // namespace vn::gunreport
