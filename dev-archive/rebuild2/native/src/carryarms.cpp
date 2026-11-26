// carryarms.cpp -- see carryarms.h
#include "carryarms.h"

#include "base.h"
#include "bridge.h"
#include "jointwriter.h"
#include "paths.h"
#include "ready.h"

#include <algorithm>
#include <fstream>

namespace vr8::carryarms {

namespace {
// ---- the named numbers ------------------------------------------------------------------------------------------
constexpr float REST_STILL_S = 1.0f;        // the player stood still this long before the rest pose may be read
constexpr float STILL_STEP_M = 0.002f;      // the player moved less than this in a frame: standing still
constexpr int REST_QUIET_FRAMES = 30;       // ... and the arm joints did not turn for this many frames
constexpr float QUIET_DOT = 0.99999f;       // two rotations this alike count as "did not turn" (about 0.5 degrees)
constexpr float EASE_S = 0.30f;             // the hold comes in and goes out over this long
constexpr int ARM_JOINTS = 8;

// From the shoulder down, both sides: where the measured travel starts (carryarms.h).
const wchar_t* const JOINT_NAMES[ARM_JOINTS] = {
    L"L_Shoulder", L"L_UpperArm", L"L_Forearm", L"L_Hand", L"R_Shoulder", L"R_UpperArm", L"R_Forearm", L"R_Hand",
};

struct State {
    MO* joints[ARM_JOINTS]{};
    Quat rest[ARM_JOINTS]{};
    Quat last[ARM_JOINTS]{};
    bool joints_found = false;
    bool joints_missing_told = false;
    bool have_last = false;
    bool have_rest = false;
    bool tried_file = false;
    bool from_file = false;           // the rest pose in use came from the kept file
    int quiet_frames = 0;
    float weight = 0.0f;               // 0 = the motion's own arms, 1 = the rest pose
    bool holding = false;              // for the log
    Vec3 last_position{};
    bool have_position = false;
    float still_since = -1.0f;
    float last_time = -1.0f;
};
State g;
unsigned g_generation = 0;

float dot(const Quat& a, const Quat& b) { return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w; }

// the short way round from a to b, t in 0..1 (normalised lerp: the two poses are a few degrees apart)
Quat blend(const Quat& a, Quat b, float t) {
    if (dot(a, b) < 0.0f) b = {-b.x, -b.y, -b.z, -b.w};
    Quat q{a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t};
    const float len = std::sqrt(dot(q, q));
    if (len < 1e-6f) return b;
    return {q.x / len, q.y / len, q.z / len, q.w / len};
}

bool find_joints(MO* transform) {
    if (g.joints_found) return true;
    int missing = 0;
    for (int i = 0; i < ARM_JOINTS; ++i) {
        g.joints[i] = jointwriter::joint_by_name(transform, JOINT_NAMES[i]);
        if (g.joints[i] == nullptr) ++missing;
    }
    if (missing != 0) {
        if (!g.joints_missing_told) {
            g.joints_missing_told = true;
            LOGW("%s carry arms: %d of %d arm joints were not found; the arms are left to the game", TAG, missing,
                 ARM_JOINTS);
        }
        return false;
    }
    return g.joints_found = true;
}

float still_for(MO* transform, float now) {
    static Call get_position("via.Transform", "get_Position", 0);
    Vec3 position{};
    if (!get_position.value(transform, &position, sizeof position)) { g.still_since = -1.0f; return 0.0f; }
    const bool moved = !g.have_position || length(position - g.last_position) > STILL_STEP_M;
    g.last_position = position;
    g.have_position = true;
    if (moved) { g.still_since = -1.0f; return 0.0f; }
    if (g.still_since < 0.0f) g.still_since = now;
    return now - g.still_since;
}

// The rest pose is kept in the data folder once it has been read (worn 2026-11-26 14:06: Tefa walked off with Rose
// without ever standing still, the pose was never read and "bobbing is back when carrying Rose"). A kept pose is
// used from the first frame of a carry; standing still reads it anew and writes the file again.
constexpr const wchar_t* REST_FILE = L"carryarms-rest.txt";

void keep_rest() {
    std::ofstream f(paths::data(REST_FILE));
    for (int i = 0; i < ARM_JOINTS; ++i)
        f << g.rest[i].x << " " << g.rest[i].y << " " << g.rest[i].z << " " << g.rest[i].w << "\n";
}

bool load_rest() {
    std::ifstream f(paths::data(REST_FILE));
    Quat pose[ARM_JOINTS];
    for (int i = 0; i < ARM_JOINTS; ++i) {
        if (!(f >> pose[i].x >> pose[i].y >> pose[i].z >> pose[i].w)) return false;
        const float len = dot(pose[i], pose[i]);
        if (!std::isfinite(len) || len < 0.98f || len > 1.02f) return false;      // not a rotation: a damaged file
    }
    for (int i = 0; i < ARM_JOINTS; ++i) g.rest[i] = pose[i];
    return true;
}

void set_holding(bool holding, const char* why) {
    if (g.holding == holding) return;
    g.holding = holding;
    LOGI("%s carry arms: %s (%s)", TAG, holding ? "held steady" : "left to the game", why);
}
} // namespace

void pose() {
    const auto& player = ready::now();
    if (player.generation != g_generation) {
        g_generation = player.generation;
        g = State{};
    }
    if (player.transform == nullptr) return;

    const float now = now_s();
    const float dt = g.last_time < 0.0f ? 0.0f : std::clamp(now - g.last_time, 0.0f, 0.1f);
    g.last_time = now;

    const bool carrying = bridge::live() && bridge::flag(bridge::S_GAME_ARMS);
    const bool cutscene = bridge::flag(bridge::S_CUTSCENE);
    if (!carrying) {
        // the carry is over (the crib): the controllers have the arms back at once, nothing to ease
        set_holding(false, "nothing is carried");
        g.weight = 0.0f;
        g.have_last = false;
        g.quiet_frames = 0;
        return;
    }
    if (!find_joints(player.transform)) return;

    // the motion's own pose this frame (our write of the last frame is gone: the motion wrote the joints anew)
    Quat current[ARM_JOINTS];
    for (int i = 0; i < ARM_JOINTS; ++i)
        if (!jointwriter::read_local_rotation(g.joints[i], current[i])) return;

    const float still_s = still_for(player.transform, now);
    if (!g.have_rest && !g.tried_file) {
        g.tried_file = true;
        if (load_rest()) {
            g.have_rest = g.from_file = true;
            LOGI("%s carry arms: the rest pose kept from an earlier carry is used", TAG);
        }
    }
    if (!g.have_rest || g.from_file) {
        bool quiet = g.have_last && !cutscene;
        if (quiet)
            for (int i = 0; i < ARM_JOINTS; ++i)
                if (std::fabs(dot(current[i], g.last[i])) < QUIET_DOT) { quiet = false; break; }
        g.quiet_frames = quiet ? g.quiet_frames + 1 : 0;
        for (int i = 0; i < ARM_JOINTS; ++i) g.last[i] = current[i];
        g.have_last = true;
        const bool ready_to_read = still_s >= REST_STILL_S && g.quiet_frames >= REST_QUIET_FRAMES;
        if (!ready_to_read && !g.have_rest) return;
        // with a kept pose in use, a fresh one is only read while the hold is not on yet (weight 0): once the arms
        // are held, what is read back is no longer the motion's own pose alone
        if (ready_to_read && (!g.from_file || g.weight <= 0.0f)) {
        for (int i = 0; i < ARM_JOINTS; ++i) g.rest[i] = current[i];
        g.have_rest = true;
        g.from_file = false;
        keep_rest();
        LOGI("%s carry arms: the rest pose is read (stood still %.1f s, the arms quiet for %d frames)", TAG, still_s,
             g.quiet_frames);
        }
    }

    const float step = EASE_S > 0.0f ? dt / EASE_S : 1.0f;
    g.weight = std::clamp(g.weight + (cutscene ? -step : step), 0.0f, 1.0f);
    set_holding(!cutscene, cutscene ? "a cutscene plays the arms" : "Rose is carried");
    if (g.weight <= 0.0f) return;
    for (int i = 0; i < ARM_JOINTS; ++i)
        jointwriter::ask_local_rotation(jointwriter::Owner::CarryArms, g.joints[i],
                                        blend(current[i], g.rest[i], g.weight));
}

} // namespace vr8::carryarms
