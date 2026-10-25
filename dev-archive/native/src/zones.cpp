// zones.cpp -- see zones.h
#include "zones.h"
#include "bridge.h"
#include "json_mini.h"
#include "player.h"
#include "settings.h"

#include <windows.h>
#include <cstring>
#include <map>
#include <string>

namespace vn::zones {

using namespace vn::settings;

namespace {
struct Entry { bool has_off = false, has_r = false; Vec3 off{0, 0, 0}; float r = 0.0f; };
std::map<std::string, std::map<std::string, Entry>> g_file;   // "default" / "<gun number>" -> zone key -> numbers
float g_seq_seen = -1.0f;
bool g_loaded = false;

std::wstring path() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring p(exe);
    p = p.substr(0, p.find_last_of(L"\\/") + 1);
    return p + L"reframework\\data\\visceral_re8\\zones.json";
}

void load() {
    g_file.clear();
    g_loaded = true;
    json::Value v;
    if (!json::load_file(path(), v) || v.kind != json::Value::OBJ) { LOGI("%s zones: no zones.json yet: the built-in zones are in force", TAG); return; }
    int n = 0;
    for (const auto& [gun, zs] : v.obj) {
        if (zs.kind != json::Value::OBJ) continue;
        for (const auto& [key, z] : zs.obj) {
            if (z.kind != json::Value::OBJ) continue;
            Entry e;
            auto num = [&](const char* k, float& out) { if (auto* x = z.get(k); x && x->kind == json::Value::NUM) { out = (float)x->n; return true; } return false; };
            const bool ox = num("x", e.off.x), oy = num("y", e.off.y), oz = num("z", e.off.z);
            e.has_off = ox || oy || oz;
            e.has_r = num("r", e.r);
            g_file[gun][key] = e;
            ++n;
        }
    }
    LOGI("%s zones: zones.json read: %d zone(s) set over %zu gun group(s)", TAG, n, g_file.size());
}

const char* key_name(Key k, const char* part) {
    switch (k) {
    case MAG: return "mag";
    case WELL: return "well";
    case PART: return part != nullptr ? part : "slide";
    default: return "hand";
    }
}
Zone builtin(Key k, const char* part) {
    Zone z;
    switch (k) {
    case MAG: z.r = MAG_GRAB_M; break;
    case WELL: z.r = DOCK_ITEM_M; break;
    case PART: z.r = (part != nullptr && std::strcmp(part, "bolt") == 0) ? RACK_BOLT_GRAB_M : RACK_JOINT_GRAB_M; break;
    default: z.r = ZONE_HAND_MARK_M; break;
    }
    return z;
}
void apply(Zone& z, const std::map<std::string, Entry>* group, const char* key) {
    if (group == nullptr) return;
    auto it = group->find(key);
    if (it == group->end()) return;
    if (it->second.has_off) z.off = it->second.off;
    if (it->second.has_r && it->second.r > 0.0f) z.r = it->second.r;
}
const std::map<std::string, Entry>* group(const std::string& name) {
    auto it = g_file.find(name);
    return it == g_file.end() ? nullptr : &it->second;
}
} // namespace

void frame() {
    if (!g_loaded) load();
    const float seq = bridge::view(bridge::S_ZONE_SEQ);
    if (seq != bridge::NO_VALUE && seq != g_seq_seen) { g_seq_seen = seq; if (seq > 0.0f) load(); }
}

Zone get(Key k, const char* part) {
    Zone z = builtin(k, part);
    const char* key = key_name(k, part);
    apply(z, group("default"), key);
    const float num = bridge::view(bridge::S_WEAPON_NUM);
    if (num != bridge::NO_VALUE && num > 0.5f) apply(z, group(std::to_string((int)(num + 0.5f))), key);
    return z;
}
float radius(Key k, const char* part) { return get(k, part).r; }

bool gun_rot(Quat& q) {
    Vec3 p;
    const auto& s = player::now();
    return s.weapon_tf != nullptr && player::get_pose(s.weapon_tf, p, q);
}

Vec3 center(Key k, const Vec3& anchor, const char* part) {
    const Zone z = get(k, part);
    if (z.off.x == 0.0f && z.off.y == 0.0f && z.off.z == 0.0f) return anchor;
    Quat q;
    if (!gun_rot(q)) return anchor;
    return anchor + rotate(qnorm(q), z.off);
}

void publish(Key k, const Vec3& c, float r, float on) {
    const int s = bridge::S_ZONES + (int)k * 5;
    bridge::put((bridge::Slot)(s + 0), c.x);
    bridge::put((bridge::Slot)(s + 1), c.y);
    bridge::put((bridge::Slot)(s + 2), c.z);
    bridge::put((bridge::Slot)(s + 3), r);
    bridge::put((bridge::Slot)(s + 4), on);
}
void clear(Key k) { bridge::put((bridge::Slot)(bridge::S_ZONES + (int)k * 5 + 4), 0.0f); }

} // namespace vn::zones
