// fingers.cpp -- see fingers.h
#include "fingers.h"

#include "base.h"
#include "bridge.h"
#include "jointwriter.h"
#include "ready.h"

namespace vr8::fingers {

namespace {
// ---- the named numbers ------------------------------------------------------------------------------------------
constexpr float REST_STILL_S = 1.0f;       // stood still this long before the rest pose is read
constexpr float STILL_STEP_M = 0.002f;     // the player moved less than this in a frame: standing still
constexpr int FINGER_JOINTS = 15;          // per hand
enum Hand : int { LEFT = 0, RIGHT = 1, HANDS = 2 };
const char* const HAND_NAME[HANDS] = {"left", "right"};

// The player's finger joints (pl1000), the names b178's fingers.cpp used and Hand Poser shows.
const wchar_t* const JOINT_NAMES[HANDS][FINGER_JOINTS] = {
    {L"L_IndexF1", L"L_IndexF2", L"L_IndexF3", L"L_MiddleF1", L"L_MiddleF2", L"L_MiddleF3", L"L_RingF1", L"L_RingF2",
     L"L_RingF3", L"L_PinkyF1", L"L_PinkyF2", L"L_PinkyF3", L"L_Thumb1", L"L_Thumb2", L"L_Thumb3"},
    {L"R_IndexF1", L"R_IndexF2", L"R_IndexF3", L"R_MiddleF1", L"R_MiddleF2", L"R_MiddleF3", L"R_RingF1", L"R_RingF2",
     L"R_RingF3", L"R_PinkyF1", L"R_PinkyF2", L"R_PinkyF3", L"R_Thumb1", L"R_Thumb2", L"R_Thumb3"},
};

struct HandState {
    MO* joints[FINGER_JOINTS]{};
    Quat rest[FINGER_JOINTS]{};
    bool joints_found = false;
    bool joints_missing_told = false;
    bool have_rest = false;
    bool holding = false;          // for the log: one line when the hold starts and one when it stops
};
HandState g_hand[HANDS];
unsigned g_generation = 0;
Vec3 g_last_position{};
bool g_have_position = false;
float g_still_since = -1.0f;       // when the player last started standing still; < 0 = moving

void forget_everything() {
    for (auto& hand : g_hand) hand = HandState{};
    g_have_position = false;
    g_still_since = -1.0f;
}

bool find_joints(Hand side, MO* transform) {
    auto& hand = g_hand[side];
    if (hand.joints_found) return true;
    int missing = 0;
    for (int i = 0; i < FINGER_JOINTS; ++i) {
        hand.joints[i] = jointwriter::joint_by_name(transform, JOINT_NAMES[side][i]);
        if (hand.joints[i] == nullptr) ++missing;
    }
    if (missing != 0) {
        if (!hand.joints_missing_told) {
            hand.joints_missing_told = true;
            LOGW("%s fingers: %d of %d %s finger joints were not found; that hand is left to the game", TAG, missing,
                 FINGER_JOINTS, HAND_NAME[side]);
        }
        return false;
    }
    return hand.joints_found = true;
}

bool read_rest(Hand side) {
    auto& hand = g_hand[side];
    for (int i = 0; i < FINGER_JOINTS; ++i)
        if (!jointwriter::read_local_rotation(hand.joints[i], hand.rest[i])) return false;
    hand.have_rest = true;
    LOGI("%s fingers: the %s hand's rest pose is read (stood still %.1f s)", TAG, HAND_NAME[side], REST_STILL_S);
    return true;
}

void set_holding(Hand side, bool holding, const char* why) {
    auto& hand = g_hand[side];
    if (hand.holding == holding) return;
    hand.holding = holding;
    LOGI("%s fingers: %s hand %s (%s)", TAG, HAND_NAME[side], holding ? "held still" : "left to the game", why);
}

// seconds the player has been standing still; 0 while moving
float still_for(MO* transform) {
    static Call get_position("via.Transform", "get_Position", 0);
    Vec3 position{};
    if (!get_position.value(transform, &position, sizeof position)) { g_still_since = -1.0f; return 0.0f; }
    const bool moved = !g_have_position || length(position - g_last_position) > STILL_STEP_M;
    g_last_position = position;
    g_have_position = true;
    const float now = now_s();
    if (moved) { g_still_since = -1.0f; return 0.0f; }
    if (g_still_since < 0.0f) g_still_since = now;
    return now - g_still_since;
}
} // namespace

void pose() {
    const auto& player = ready::now();
    if (player.generation != g_generation) {
        g_generation = player.generation;
        forget_everything();
    }
    if (player.transform == nullptr) return;

    const float still_s = still_for(player.transform);
    const char* stand_down = nullptr;
    if (!player.hands_are_players) stand_down = "a cutscene, a resting controller, or no bridge";
    else if (bridge::flag(bridge::S_GAME_ARMS)) stand_down = "the game's own arms";

    for (int s = 0; s < HANDS; ++s) {
        const Hand side = (Hand)s;
        const char* why = stand_down;
        if (why == nullptr && side == RIGHT && bridge::flag(bridge::S_WEAPON)) why = "a weapon in the hand";
        if (why != nullptr) { set_holding(side, false, why); continue; }
        if (!find_joints(side, player.transform)) continue;
        auto& hand = g_hand[side];
        if (!hand.have_rest) {
            if (still_s < REST_STILL_S || !read_rest(side)) continue;
        }
        for (int i = 0; i < FINGER_JOINTS; ++i)
            jointwriter::ask_local_rotation(jointwriter::Owner::FingersRest, hand.joints[i], hand.rest[i]);
        set_holding(side, true, "the hand is empty");
    }
}

} // namespace vr8::fingers
