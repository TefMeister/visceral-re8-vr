// ready.cpp -- see ready.h
#include "ready.h"

#include "bridge.h"

namespace vr8::ready {

namespace {
Snapshot g_now;
MO* g_last_player = nullptr;
unsigned g_generation = 0;
} // namespace

void refresh() {
    Snapshot s;
    auto* props = API::get()->get_managed_singleton("app.PropsManager");
    s.player = field_obj(props, "<Player>k__BackingField");
    if (s.player != g_last_player) {
        g_last_player = s.player;
        ++g_generation;
        LOGI("%s ready: the player is %s (generation %u)", TAG, s.player != nullptr ? "here" : "gone", g_generation);
    }
    s.generation = g_generation;
    if (s.player != nullptr) {
        static Call get_transform("via.GameObject", "get_Transform", 0);
        s.transform = get_transform.ptr(s.player);
    }
    s.hands_are_players = s.transform != nullptr && bridge::live() && bridge::flag(bridge::S_ACTIVE) &&
                          !bridge::flag(bridge::S_CUTSCENE) && bridge::flag(bridge::S_CAN_USE_HANDS);
    g_now = s;
}

const Snapshot& now() { return g_now; }

} // namespace vr8::ready
