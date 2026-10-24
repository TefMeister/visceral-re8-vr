// nodock.cpp -- see nodock.h
#include "nodock.h"
#include "bridge.h"
#include "common.h"
#include "player.h"
#include "rack.h"
#include "reload.h"
#include "settings.h"

#include <atomic>

namespace vn::nodock {

using namespace vn::settings;

thread_local bool t_self_read = false;

namespace {
thread_local bool t_fake = false;
bool g_on = false;
bool g_was_on = false;
std::atomic<int> g_faked{0};
float g_log_t = -10.0f;

int g_seen = 0;
int pre(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    t_fake = false;
    // 01:50 (the log: "0 asks answered" while the game docked every frame): the motion-object check never matched, so it is
    // gone; the left hand IK's joint hash alone names the call. The first calls are logged to show what arrives
    const auto& s = player::now();
    auto* lh = s.ik_left != nullptr ? field_ptr<uint32_t>(s.ik_left, "<HashJoint2>k__BackingField") : nullptr;
    const uint32_t hash = argc >= 3 ? (uint32_t)(uintptr_t)argv[2] : 0;
    if (g_seen < 8) {
        ++g_seen;
        LOGI("%s nodock: ask #%d: argc %d, this %p (player motion %p), hash %u (left hand %u), on %d, self %d", TAG, g_seen, argc, argc >= 2 ? argv[1] : nullptr,
             (void*)s.motion, hash, lh ? *lh : 0, g_on ? 1 : 0, t_self_read ? 1 : 0);
    }
    if (!g_on || t_self_read || argc < 3 || lh == nullptr || hash != *lh) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    t_fake = true;
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

void post(void** ret_val, REFrameworkTypeDefinitionHandle, unsigned long long) {
    if (!t_fake) return;
    t_fake = false;
    *ret_val = (void*)(uintptr_t)NODOCK_FAKE_JOINT;
    ++g_faked;
}
} // namespace

bool on() { return g_on; }

void frame() {
    const auto& s = player::now();
    g_on = NODOCK_ON && bridge::live() && s.weapon != nullptr && !bridge::held(bridge::S_LGRIP) && !rack::active() &&
           !reload::mag_in_hand() && !reload::round_in_hand();
    if (g_on != g_was_on) {
        g_was_on = g_on;
        LOGI("%s nodock: the game's own left-hand dock is %s (%d asks answered with the root joint so far)", TAG, g_on ? "OFF (LG up)" : "allowed (LG held, or no gun)", g_faked.load());
    }
}

void install() {
    auto* m = API::get()->tdb()->find_method("via.motion.Motion", "getJointIndexByNameHash");
    if (m == nullptr) { LOGW("%s nodock: via.motion.Motion.getJointIndexByNameHash NOT FOUND: the game's dock stays", TAG); return; }
    m->add_hook(pre, post, false);
    LOGI("%s nodock: hooked via.motion.Motion.getJointIndexByNameHash (the game's dock is off while LG is up)", TAG);
}

} // namespace vn::nodock
