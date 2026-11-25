// jointwriter.cpp -- see jointwriter.h
#include "jointwriter.h"

#include <algorithm>
#include <set>
#include <unordered_map>
#include <utility>
#include <vector>

namespace vr8::jointwriter {

namespace {
constexpr float REPORT_EVERY_S = 60.0f;      // one line a minute: how many joints were written, how many refused

struct Ask {
    Owner owner;
    MO* joint;
    Quat rotation;
};
std::vector<Ask> g_asks;
unsigned long long g_written = 0, g_refused = 0;
float g_last_report = 0.0f;

Call& set_local_rotation() { static Call c("via.Joint", "set_LocalRotation", 1); return c; }
Call& get_local_rotation() { static Call c("via.Joint", "get_LocalRotation", 0); return c; }
Call& get_joint_by_name() { static Call c("via.Transform", "getJointByName", 1); return c; }
} // namespace

const char* owner_name(Owner owner) {
    switch (owner) {
    case Owner::FingersRest: return "fingers-rest";
    default: return "?";
    }
}

void ask_local_rotation(Owner owner, MO* joint, const Quat& rotation) {
    if (joint == nullptr) return;
    g_asks.push_back({owner, joint, rotation});
}

bool read_local_rotation(MO* joint, Quat& out) {
    if (!get_local_rotation().value(joint, &out, sizeof out)) return false;
    return std::isfinite(out.x) && std::isfinite(out.y) && std::isfinite(out.z) && std::isfinite(out.w);
}

MO* joint_by_name(MO* transform, const wchar_t* name) {
    auto* text = managed_string(name);
    if (transform == nullptr || text == nullptr) return nullptr;
    return get_joint_by_name().ptr(transform, {(void*)text});
}

void flush() {
    std::stable_sort(g_asks.begin(), g_asks.end(),
                     [](const Ask& a, const Ask& b) { return (int)a.owner < (int)b.owner; });
    std::unordered_map<MO*, Owner> taken;
    static std::set<std::pair<int, int>> told;   // (first owner, refused owner): one log line per pair, ever
    for (const auto& ask : g_asks) {
        auto [it, fresh] = taken.emplace(ask.joint, ask.owner);
        if (!fresh) {
            ++g_refused;
            if (told.insert({(int)it->second, (int)ask.owner}).second)
                LOGW("%s joint writer: %s asked for a joint %s already has this frame; refused", TAG,
                     owner_name(ask.owner), owner_name(it->second));
            continue;
        }
        if (set_local_rotation().set_value(ask.joint, &ask.rotation)) ++g_written;
    }
    g_asks.clear();

    const float now = now_s();
    if (now - g_last_report >= REPORT_EVERY_S) {
        if (g_written != 0 || g_refused != 0)
            LOGI("%s joint writer: %llu written, %llu refused in the last minute", TAG, g_written, g_refused);
        g_written = g_refused = 0;
        g_last_report = now;
    }
}

} // namespace vr8::jointwriter
