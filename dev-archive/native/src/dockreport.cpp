// dockreport.cpp -- see dockreport.h
#include "dockreport.h"
#include "bridge.h"
#include "gate.h"
#include "joints.h"
#include "player.h"
#include "rack.h"
#include "rack_right.h"
#include "zones.h"

#include <windows.h>

#include <cmath>
#include <cstdio>
#include <filesystem>
#include <share.h>

namespace vn::dockreport {

using namespace joints;

namespace {
constexpr float SETTLE_S = 0.4f;    // the hold's eases (dockpose, the IK) settle before the first number counts
constexpr float EVERY_S = 0.5f;     // the file gets a line this often while docked

int g_spot = -1;
float g_since = 0.0f, g_last_line = -10.0f;
bool g_told = false;
MO* g_tf = nullptr;
MO* g_hand = nullptr;
MO* g_mid = nullptr;
MO* g_rhand = nullptr;   // 2026-11-08: the who-moved-it line
MO* g_lupper = nullptr;
FILE* g_file = nullptr;

// the left hand's spot (bridge S_LEFT_SPOT, pairs.cpp) -> the zone it was taken in; -1 = not a part we measure
int zone_of(int spot) {
    switch (spot) {
    case 3: return zones::PART;
    case 8: return zones::SLIDE_LEFT;
    case 4: return zones::MAG;
    case 5: return zones::HANDLE;
    case 6: return zones::DRUM;
    case 7: return zones::INSERT;
    default: return -1;
    }
}
const char* zone_name(int k) {
    switch (k) {
    case zones::PART: return "part (slide / pump / bolt)"; case zones::SLIDE_LEFT: return "slide from the left";
    case zones::MAG: return "magazine";  case zones::HANDLE: return "handle"; case zones::DRUM: return "drum";
    case zones::INSERT: return "breech";  case zones::GRIP: return "front grip"; default: return "?";
    }
}
int first_slot(int k) { return k < zones::HANDLE ? bridge::S_ZONES + k * 5 : bridge::S_ZONES2 + (k - zones::HANDLE) * 5; }
bool zone_center(int k, Vec3& c) {
    const int s = k == zones::SLIDE_LEFT ? (int)bridge::S_ZONE_SLIDE_LEFT : first_slot(k);
    c = {bridge::view((bridge::Slot)s), bridge::view((bridge::Slot)(s + 1)), bridge::view((bridge::Slot)(s + 2))};
    const float r = bridge::view((bridge::Slot)(s + 3)), on = bridge::view((bridge::Slot)(s + 4));
    // 2026-11-05: a zone not published this gun (the slide-left sphere on a pump gun) keeps old numbers in its slots: skip it
    return r > 0.0f && on > 0.5f && std::fabs(c.x) + std::fabs(c.y) + std::fabs(c.z) > 1e-4f && std::fabs(c.x) < 1e6f;
}

// yaw (about the gun's up), pitch (about its right), roll (about its forward), degrees, of the hand's turn in the gun's frame
void ypr(Quat q, float& y, float& p, float& r) {
    const float k = 57.2957795f;
    const Vec3 f = rotate(q, Vec3{0, 0, 1}), u = rotate(q, Vec3{0, 1, 0});
    y = std::atan2(f.x, f.z) * k;
    p = std::asin(std::fmax(-1.0f, std::fmin(1.0f, -f.y))) * k;
    r = std::atan2(-u.x, u.y) * k;
}

void open_file() {
    if (g_file != nullptr) return;
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const auto p = std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8" / "dock_report.tsv";
    g_file = _wfsopen(p.c_str(), L"wb", _SH_DENYNO);   // readable by the sweep while the game writes it
    if (g_file != nullptr) {
        std::fprintf(g_file, "t\tgun\tspot\tzone\tgap_cm\tright_cm\tup_cm\tfwd_cm\thand_yaw\thand_pitch\thand_roll\n");
        std::fflush(g_file);
    }
}
// 2026-11-08 (Tefa, the LEMI slide: "hand lands way off the gun ... just a minute ago it was landing on the gun"; twice the palm
// went from 6-10 cm to 20-33 cm off, high and back, and stayed; hand smoothing ruled out): at each take, WHO put the hand there.
//   ours->target  our slide code's left target vs the IK target now (someone moved the target after us)
//   target->wrist the IK target vs the drawn wrist (the arm did not get there)
//   ours->part    our target vs the drawn part (we aimed off: our anchor, the right hand's target, is not where the gun is drawn)
//   R target->wrist  the right hand's IK target vs its drawn wrist (the gun drawn away from where its hand should be)
//   reach         shoulder -> target vs the arm's length
void who_moved_it(const Vec3& at, const Quat& gq, const Vec3& hp) {
    const auto& s = player::now();
    if (g_rhand == nullptr) g_rhand = joint_by_name(g_tf, L"R_Hand");
    if (g_lupper == nullptr) g_lupper = joint_by_name(g_tf, L"L_UpperArm");
    auto cm = [](Vec3 v) { return std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z) * 100.0f; };
    char buf[600];
    int n = std::snprintf(buf, sizeof buf, "%s dockreport: who moved it:", TAG);
    Vec3 ours{}, lt{}, rt{}, rh{}, sh{};
    Quat q{};
    float age = 0.0f;
    const bool have_ours = rack::last_target(ours, age);
    const bool have_lt = s.ik_left != nullptr && player::get_pose(field_obj(s.ik_left, "Target"), lt, q);
    if (have_ours && have_lt) {
        const Vec3 d = rotate(qinv(gq), lt - ours) * 100.0f;
        n += std::snprintf(buf + n, sizeof buf - n, " ours->target %.1f cm (r %+.1f u %+.1f f %+.1f, ours %.0f ms old);", cm(lt - ours), d.x, d.y, d.z, age * 1000.0f);
    } else n += std::snprintf(buf + n, sizeof buf - n, " ours->target ? (ours %d, target %d);", have_ours ? 1 : 0, have_lt ? 1 : 0);
    if (have_lt) {
        const Vec3 d = rotate(qinv(gq), hp - lt) * 100.0f;
        n += std::snprintf(buf + n, sizeof buf - n, " target->wrist %.1f cm (r %+.1f u %+.1f f %+.1f);", cm(hp - lt), d.x, d.y, d.z);
    }
    if (have_ours) {
        const Vec3 d = rotate(qinv(gq), ours - at) * 100.0f;
        n += std::snprintf(buf + n, sizeof buf - n, " ours->part %.1f cm (r %+.1f u %+.1f f %+.1f);", cm(ours - at), d.x, d.y, d.z);
    }
    if (s.ik_right != nullptr && g_rhand != nullptr && player::get_pose(field_obj(s.ik_right, "Target"), rt, q) && get_v3(JOINT, g_rhand, "get_Position", rh)) {
        const Vec3 d = rotate(qinv(gq), rh - rt) * 100.0f;
        n += std::snprintf(buf + n, sizeof buf - n, " R target->wrist %.1f cm (r %+.1f u %+.1f f %+.1f);", cm(rh - rt), d.x, d.y, d.z);
    }
    if (have_lt && g_lupper != nullptr && get_v3(JOINT, g_lupper, "get_Position", sh))
        n += std::snprintf(buf + n, sizeof buf - n, " reach: shoulder->target %.1f cm, shoulder->wrist %.1f cm", cm(lt - sh), cm(hp - sh));
    LOGI("%s", buf);
}
} // namespace

void render_point() {
    const auto& s = player::now();
    const int raw = (int)(bridge::view(bridge::S_LEFT_SPOT) + 0.5f);
    int key = zone_of(raw);
    int spot = raw;
    if (key < 0 && raw == 0 && bridge::flag(bridge::S_GRIPPING_WEAPON)) { key = zones::GRIP; spot = 50; }   // two-handed on the front
    const float t = now_s();
    if (spot != g_spot) { g_spot = spot; g_since = t; g_told = false; }
    if (key < 0 || s.tf == nullptr || s.gun == nullptr) return;
    if (t - g_since < SETTLE_S) return;
    if (s.tf != g_tf) { g_tf = s.tf; g_hand = g_mid = g_rhand = g_lupper = nullptr; }
    if (g_hand == nullptr) g_hand = joint_by_name(g_tf, L"L_Hand");
    if (g_mid == nullptr) g_mid = joint_by_name(g_tf, L"L_MiddleF1");
    Vec3 hp, mp, c;
    Quat hq, gq;
    if (g_hand == nullptr || g_mid == nullptr || !get_v3(JOINT, g_hand, "get_Position", hp) || !get_v3(JOINT, g_mid, "get_Position", mp) ||
        !get_q(JOINT, g_hand, "get_Rotation", hq) || !zone_center(key, c))
        return;
    if (!(gate::gun_rot(gq) || rack_right::gun_rot(gq) || zones::gun_rot(gq))) return;
    gq = qnorm(gq);
    const Vec3 palm = (hp + mp) * 0.5f;
    // 2026-11-04: from the PART, not the zone's centre: Tefa's zones.json moves a zone to where the controller grabs comfortably
    // (the LEMI's magazine zone sits 9 cm to its right), which is not where the drawn hand belongs
    const char* part = key == zones::PART ? rack::part_name() : nullptr;
    const Vec3 at = c - rotate(gq, zones::file_offset((zones::Key)key, part));
    const Vec3 gap = rotate(qinv(gq), palm - at) * 100.0f;   // cm, the gun's own axes
    float y, p, r;
    ypr(qnorm(qmul(qinv(gq), qnorm(hq))), y, p, r);
    const int gun = (int)(bridge::view(bridge::S_WEAPON_NUM) + 0.5f);
    const float d = std::sqrt(gap.x * gap.x + gap.y * gap.y + gap.z * gap.z);
    if (!g_told) {
        g_told = true;
        LOGI("%s dockreport: gun %d, the %s: the palm sits %.1f cm from the part (right %+.1f, up %+.1f, forward %+.1f cm, the gun's "
             "axes); the hand turned yaw %.0f pitch %.0f roll %.0f deg in the gun's frame", TAG, gun, zone_name(key), d, gap.x, gap.y, gap.z, y, p, r);
        who_moved_it(at, gq, hp);
    }
    if (t - g_last_line >= EVERY_S) {
        g_last_line = t;
        open_file();
        if (g_file != nullptr) {
            std::fprintf(g_file, "%.2f\t%d\t%d\t%s\t%.1f\t%.1f\t%.1f\t%.1f\t%.0f\t%.0f\t%.0f\n", t, gun, spot, zone_name(key), d, gap.x, gap.y, gap.z, y, p, r);
            std::fflush(g_file);
        }
    }
}

} // namespace vn::dockreport
