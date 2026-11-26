// sleephands.cpp -- see sleephands.h
#include "sleephands.h"

#include "base.h"
#include "bridge.h"
#include "jointwriter.h"
#include "ready.h"

namespace vr8::sleephands {

namespace {
// ---- the named numbers ------------------------------------------------------------------------------------------
constexpr int ARM_JOINTS = 4;              // per side, from the shoulder down
enum Side : int { LEFT = 0, RIGHT = 1, SIDES = 2 };
const char* const SIDE_NAME[SIDES] = {"left", "right"};
const bridge::Slot ASLEEP_SLOT[SIDES] = {bridge::S_LEFT_ASLEEP, bridge::S_RIGHT_ASLEEP};
const wchar_t* const JOINT_NAMES[SIDES][ARM_JOINTS] = {
    {L"L_Shoulder", L"L_UpperArm", L"L_Forearm", L"L_Hand"},
    {L"R_Shoulder", L"R_UpperArm", L"R_Forearm", L"R_Hand"},
};

struct Arm {
    MO* joints[ARM_JOINTS]{};
    Quat kept[ARM_JOINTS]{};
    bool joints_found = false;
    bool joints_missing_told = false;
    bool have_kept = false;
    bool holding = false;          // for the log
};
Arm g_arm[SIDES];
unsigned g_generation = 0;

bool find_joints(Side side, MO* transform) {
    auto& arm = g_arm[side];
    if (arm.joints_found) return true;
    int missing = 0;
    for (int i = 0; i < ARM_JOINTS; ++i) {
        arm.joints[i] = jointwriter::joint_by_name(transform, JOINT_NAMES[side][i]);
        if (arm.joints[i] == nullptr) ++missing;
    }
    if (missing != 0) {
        if (!arm.joints_missing_told) {
            arm.joints_missing_told = true;
            LOGW("%s sleeping hands: %d of %d %s arm joints were not found; that arm is left as it is", TAG, missing,
                 ARM_JOINTS, SIDE_NAME[side]);
        }
        return false;
    }
    return arm.joints_found = true;
}

void set_holding(Side side, bool holding) {
    auto& arm = g_arm[side];
    if (arm.holding == holding) return;
    arm.holding = holding;
    LOGI("%s sleeping hands: the %s arm %s", TAG, SIDE_NAME[side],
         holding ? "is held where it was (its controller reports nothing)" : "is the controller's again");
}
} // namespace

void pose() {
    const auto& player = ready::now();
    if (player.generation != g_generation) {
        g_generation = player.generation;
        for (auto& arm : g_arm) arm = Arm{};
    }
    if (player.transform == nullptr) return;
    // only while the hands are the player's: a cutscene or the game's own arms pose them, and nothing is kept
    // from those (a pose remembered there must not be held afterwards)
    if (!player.hands_are_players || bridge::flag(bridge::S_GAME_ARMS)) {
        for (int s = 0; s < SIDES; ++s) {
            set_holding((Side)s, false);
            g_arm[s].have_kept = false;
        }
        return;
    }
    for (int s = 0; s < SIDES; ++s) {
        const Side side = (Side)s;
        if (!find_joints(side, player.transform)) continue;
        auto& arm = g_arm[side];
        if (!bridge::flag(ASLEEP_SLOT[side])) {
            Quat now[ARM_JOINTS];
            bool ok = true;
            for (int i = 0; i < ARM_JOINTS && ok; ++i) ok = jointwriter::read_local_rotation(arm.joints[i], now[i]);
            if (ok) {
                for (int i = 0; i < ARM_JOINTS; ++i) arm.kept[i] = now[i];
                arm.have_kept = true;
            }
            set_holding(side, false);
            continue;
        }
        if (!arm.have_kept) continue;
        for (int i = 0; i < ARM_JOINTS; ++i)
            jointwriter::ask_local_rotation(jointwriter::Owner::SleepHands, arm.joints[i], arm.kept[i]);
        set_holding(side, true);
    }
}

} // namespace vr8::sleephands
