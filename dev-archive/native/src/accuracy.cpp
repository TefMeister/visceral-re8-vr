// accuracy.cpp -- see accuracy.h
#include "accuracy.h"
#include "bridge.h"
#include "joints.h"
#include "player.h"
#include "reload.h"
#include "settings.h"
#include "weapons.h"

#include <windows.h>

#include <atomic>
#include <cmath>
#include <random>

namespace vn::accuracy {

using namespace joints;
using namespace vn::settings;

namespace {
enum Hold { ONE = 0, MAG = 1, BOTH = 2 };
enum Move { RUN = 0, WALK = 1, STILL = 2 };
const char* HOLD_NAME[3] = {"one hand", "the left hand on the gun with a magazine in it", "both hands on the gun"};
const char* MOVE_NAME[3] = {"running", "walking", "standing still"};

// this frame's answer, written on the game thread in frame(), read by the bullet hooks (the same thread, later in the frame)
std::atomic<int> g_hold{ONE}, g_move{STILL};
std::atomic<float> g_speed{0.0f};
std::atomic<bool> g_on{false};        // a magazine-fed handgun in hand, in VR, in play
std::atomic<void*> g_gun{nullptr}, g_weapon{nullptr};

// the ray of the bullet being made, from createBullet to createBulletImple (the same thread, one after the other)
thread_local bool t_ray_ok = false;
thread_local Vec3 t_ray_dir{};
thread_local void* t_ray_this = nullptr;

std::mt19937 g_rng{std::random_device{}()};
float rnd() { return std::uniform_real_distribution<float>(0.0f, 1.0f)(g_rng); }

// Reads through pointers the game hands a hook: structured exceptions only, no C++ objects inside (the scope plugin's lesson:
// validate the DATA; a wrong guess about an argument must cost a skipped shot, never the game)
#pragma warning(push)
#pragma warning(disable : 4530)
bool safe_read_vec3(const void* p, Vec3* out) {
    if (p == nullptr) return false;
    __try { *out = *(const Vec3*)p; return true; } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}
bool safe_read_quat(const void* p, Quat* out) {
    if (p == nullptr) return false;
    __try { *out = *(const Quat*)p; return true; } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}
bool safe_write_quat(void* p, const Quat& q) {
    if (p == nullptr) return false;
    __try { *(Quat*)p = q; return true; } __except (EXCEPTION_EXECUTE_HANDLER) { return false; }
}
#pragma warning(pop)

bool unit_quat(const Quat& q) {
    const float l2 = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w;
    return l2 == l2 && std::fabs(l2 - 1.0f) < 0.02f;
}
float angle_deg(const Quat& a, const Quat& b) {
    const float d = std::fabs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w);
    return 2.0f * std::acos(d > 1.0f ? 1.0f : d) * 57.29578f;
}
// the shortest turn that takes +Z onto unit d: the engine's own clean bullet rotation (scope dossier 9bl, matched on every shot)
bool clean_from_dir(const Vec3& d, Quat* out) {
    const float w = 1.0f + d.z;
    if (w < 1e-4f) return false;
    *out = qnorm(Quat{-d.y, d.x, 0.0f, w});
    return true;
}

bool ours(void* self) { return g_on.load() && self != nullptr && (self == g_gun.load() || self == g_weapon.load()); }

int pre_create_bullet(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    t_ray_ok = false;
    if (argv == nullptr || argc < 3 || !ours(argv[1])) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    Vec3 d{};   // argv[2] is the via.Ray: its origin is a padded vec3, the direction sits at +16 (scope dossier, 18 of 18 shots)
    if (!safe_read_vec3((const uint8_t*)argv[2] + 16, &d)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    const float l = std::sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
    if (!(l > 0.5f && l < 1.5f)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    t_ray_dir = d * (1.0f / l);
    t_ray_this = argv[1];
    t_ray_ok = true;
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

int pre_create_bullet_imple(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    static int n = 0;
    const bool have = t_ray_ok && argv != nullptr && argc >= 4 && argv[1] == t_ray_this;
    t_ray_ok = false;
    if (!have || !ours(argv[1])) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    Quat was{}, clean{};
    if (!safe_read_quat(argv[3], &was) || !unit_quat(was) || !clean_from_dir(t_ray_dir, &clean)) {
        if (++n <= 10) LOGW("%s accuracy: shot NOT touched: the bullet's rotation did not read as a rotation", TAG);
        return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    }
    const int hold = g_hold.load(), move = g_move.load();
    const float pct = ACC_PCT[hold][move];
    const float cone = (1.0f - pct * 0.01f) * ACC_CONE_DEG;
    // a point picked evenly inside the cone: turned about a random axis across the bullet's own forward (+Z)
    const float theta = cone * std::sqrt(rnd()), phi = rnd() * 6.2831853f;
    const float h = theta * 0.5f / 57.29578f, s = std::sin(h);
    const Quat off{std::cos(phi) * s, std::sin(phi) * s, 0.0f, std::cos(h)};
    const Quat out = qnorm(qmul(clean, off));
    const bool wrote = safe_write_quat(argv[3], out);
    ++n;
    if (n <= 40 || n % 25 == 0)
        LOGI("%s accuracy: shot #%d: %s, %s (%.2f m/s): %.0f%%, up to %.2f deg; this bullet %.2f deg off the aim (the game's own was %.2f)%s", TAG, n,
             HOLD_NAME[hold], MOVE_NAME[move], g_speed.load(), pct, cone, angle_deg(out, clean), angle_deg(was, clean), wrote ? "" : ": WRITE FAILED");
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

// how fast the player's body moves over the ground (the stick's walking and running; the room's own steps ride on top)
bool g_have_last = false;
Vec3 g_last{};
float g_last_t = 0.0f, g_smooth = 0.0f;
} // namespace

void install() {
    if (!ACC_ON) return;
    auto* td = API::get()->tdb()->find_type("app.WeaponGunCore");
    auto* cb = td != nullptr ? td->find_method("createBullet") : nullptr;
    auto* cbi = td != nullptr ? td->find_method("createBulletImple") : nullptr;
    if (cb == nullptr || cbi == nullptr) { LOGW("%s accuracy: createBullet / createBulletImple NOT FOUND: handguns keep the game's own scatter", TAG); return; }
    cb->add_hook(pre_create_bullet, nullptr, false);
    cbi->add_hook(pre_create_bullet_imple, nullptr, false);
    LOGI("%s accuracy: hooked app.WeaponGunCore.createBullet / createBulletImple (magazine handguns: accuracy by hold and movement)", TAG);
}

void frame() {
    if (!ACC_ON) return;
    const auto& s = player::now();
    // the speed, always (so its numbers can be read on the flat screen too)
    Vec3 p{};
    const float now = now_s();
    if (s.tf != nullptr && get_v3(XFORM, s.tf, "get_Position", p)) {
        const float dt = now - g_last_t;
        if (g_have_last && dt > 0.001f && dt < 0.25f) {
            const float dx = p.x - g_last.x, dz = p.z - g_last.z;
            const float v = std::sqrt(dx * dx + dz * dz) / dt;
            const float k = std::fmin(1.0f, dt / ACC_SPEED_SMOOTH_S);
            g_smooth += ((v < ACC_SPEED_MAX_MPS ? v : g_smooth) - g_smooth) * k;   // a teleport (a load, a cutscene cut) is not a speed
        } else if (dt >= 0.25f) {
            g_smooth = 0.0f;
        }
        g_last = p; g_last_t = now; g_have_last = true;
    } else {
        g_have_last = false; g_smooth = 0.0f;
    }
    const int move = g_smooth >= ACC_RUN_MPS ? RUN : g_smooth >= ACC_WALK_MPS ? WALK : STILL;
    const auto* w = weapons::find(weapons::canonical(s.weapon_id));
    const bool handgun = w != nullptr && w->reload == weapons::Reload::MAG && w->shape == weapons::Shape::PISTOL;
    const bool at_gun = handgun && reload::left_at_gun();
    const int hold = !at_gun ? ONE : reload::mag_in_hand() ? MAG : BOTH;
    static int told_hold = -1, told_move = -1;
    static float told_t = -10.0f;
    if (handgun && (hold != told_hold || move != told_move) && now - told_t > 0.5f) {
        told_hold = hold; told_move = move; told_t = now;
        LOGI("%s accuracy: %s, %s (%.2f m/s): %.0f%%", TAG, HOLD_NAME[hold], MOVE_NAME[move], g_smooth, ACC_PCT[hold][move]);
    }
    g_hold = hold; g_move = move; g_speed = g_smooth;
    g_gun = (void*)s.gun; g_weapon = (void*)s.weapon;
    g_on = handgun && bridge::live() && s.gun != nullptr;
}

} // namespace vn::accuracy
