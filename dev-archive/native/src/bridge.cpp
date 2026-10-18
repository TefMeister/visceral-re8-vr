// bridge.cpp -- see bridge.h. The array's element offset is not assumed: it is found by the sentinel.
//
// The mailbox. RE2 hands the array over through a game method we hook (app.ropeway.RagdollControlZoneManager.
// set_AccessMutex); Village's method names have never been dumped on our side, so the plugin picks one itself on the
// first game frame: the first app.* "set_" method (sorted by name) that takes one System.Object and has real code.
// It writes the choice to reframework/data/visceral_re8/mailbox.json, which the bridge Lua reads before each
// hand-over. The original method never runs with our array (SKIP_ORIGINAL); every other call passes straight through.
// `[hypothesis]` until the first flat launch logs "BRIDGE ATTACHED".
#include "bridge.h"

#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <filesystem>

#include "settings.h"

namespace vn::bridge {

namespace {
MO* g_arr = nullptr;
uint32_t g_elem_off = 0;          // measured from the sentinel
float g_now[S_COUNT]{}, g_prev[S_COUNT]{};

float* elems() { return (float*)((char*)g_arr + g_elem_off); }

bool measure(MO* a) {
    const auto* b = (const uint8_t*)a;
    for (uint32_t off = 0x10 + S_SENTINEL * 4; off <= 0x200; off += 4) {
        if (*(const float*)(b + off) == SENTINEL) {
            g_elem_off = off - S_SENTINEL * 4;
            LOGI("%s bridge array: elements at +0x%x (found by the sentinel)", TAG, g_elem_off);
            return true;
        }
    }
    return false;
}

int pre_mailbox(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    for (int i = 0; i < argc && i < 6; ++i) {
        auto* o = (MO*)argv[i];
        if (!is_managed(o) || type_name(o) != "System.Single[]") continue;
        if (g_arr == o) return REFRAMEWORK_HOOK_SKIP_ORIGINAL;      // a repeat hand-over: still swallow it
        if (!measure(o)) continue;
        o->add_ref();
        g_arr = o;
        elems()[S_ACK] = 1.0f;
        LOGI("%s BRIDGE ATTACHED: controller readings are live", TAG);
        return REFRAMEWORK_HOOK_SKIP_ORIGINAL;                       // never run the game's setter with our array
    }
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

bool takes_one_object(API::Method* m) {
    if (m == nullptr || m->get_num_params() != 1 || m->get_function_raw() == nullptr) return false;
    const auto params = m->get_params();
    if (params.size() != 1 || params[0].t == nullptr) return false;
    return ((API::TypeDefinition*)params[0].t)->get_full_name() == "System.Object";
}

std::filesystem::path data_dir() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8";
}

void write_choice(const std::string& type, const std::string& method) {
    std::error_code ec;
    const auto dir = data_dir();
    std::filesystem::create_directories(dir, ec);
    FILE* f = nullptr;
    if (_wfopen_s(&f, (dir / "mailbox.json").c_str(), L"wb") != 0 || f == nullptr) { LOGE("%s could not write mailbox.json: the bridge Lua will not find the plugin", TAG); return; }
    std::fprintf(f, "{\n    \"type\": \"%s\",\n    \"method\": \"%s\"\n}\n", type.c_str(), method.c_str());
    std::fclose(f);
}
} // namespace

void install() {
    auto* tdb = API::get()->tdb();
    std::vector<std::pair<std::string, API::Method*>> found;
    const uint32_t n = tdb->get_num_types();
    for (uint32_t i = 0; i < n; ++i) {
        auto* td = tdb->get_type(i);
        if (td == nullptr) continue;
        const auto full = td->get_full_name();
        if (full.rfind("app.", 0) != 0) continue;
        for (auto* m : td->get_methods()) {
            const char* name = m != nullptr ? m->get_name() : nullptr;
            if (name == nullptr || std::string_view(name).rfind("set_", 0) != 0) continue;
            if (m->get_declaring_type() != td || !takes_one_object(m)) continue;
            found.emplace_back(full + "." + name, m);
        }
    }
    if (found.empty()) { LOGE("%s no mailbox method in this game: no controller readings, no rumble from the plugin", TAG); return; }
    std::sort(found.begin(), found.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
    for (size_t i = 0; i < found.size() && i < settings::MAILBOX_LOG_COUNT; ++i) LOGI("%s mailbox candidate %zu: %s", TAG, i, found[i].first.c_str());
    auto* m = found.front().second;
    m->add_hook(pre_mailbox, nullptr, false);
    write_choice(m->get_declaring_type()->get_full_name(), m->get_name());
    LOGI("%s bridge mailbox hook in: %s (%zu candidates)", TAG, found.front().first.c_str(), found.size());
}

bool live() { return g_arr != nullptr && elems()[S_SENTINEL] == SENTINEL && elems()[S_HMD] > 0.5f; }

void frame_begin() {
    for (int i = 0; i < S_COUNT; ++i) g_prev[i] = g_now[i];
    if (live()) for (int i = 0; i < S_COUNT; ++i) g_now[i] = elems()[i];
    else for (float& v : g_now) v = 0.0f;
}

bool held(Slot s) { return g_now[s] > 0.5f; }
bool pressed(Slot s) { return g_now[s] > 0.5f && g_prev[s] <= 0.5f; }

void rumble(Hand h, float amplitude, float seconds, float hz) {
    if (!live() || amplitude <= 0.0f || seconds <= 0.0f) return;
    float* e = elems() + (h == LEFT ? S_RUMBLE_L_AMP : S_RUMBLE_R_AMP);
    e[0] = std::max(e[0], amplitude);
    e[1] = std::max(e[1], seconds);
    e[2] = hz;
}

float view(Slot s) { return g_arr != nullptr ? elems()[s] : NO_VALUE; }
Vec3 view_vec3(Slot s) { if (g_arr == nullptr) return {NO_VALUE, 0, 0}; const float* e = elems(); return {e[s], e[s + 1], e[s + 2]}; }
bool flag(Slot s) { return g_arr != nullptr && elems()[s] > 0.5f; }
void put(Slot s, float v) { if (g_arr != nullptr) elems()[s] = v; }

Quat view_quat(Slot s) { if (g_arr == nullptr) return {NO_VALUE, 0, 0, 1}; const float* e = elems(); return qnorm({e[s], e[s + 1], e[s + 2], e[s + 3]}); }
Vec3 hand_pos(Hand h) { const int s = h == LEFT ? S_LPOS : S_RPOS; return {g_now[s], g_now[s + 1], g_now[s + 2]}; }
Vec3 hmd_pos() { return {g_now[S_HMD_POS], g_now[S_HMD_POS + 1], g_now[S_HMD_POS + 2]}; }
Quat hmd_rot() { return qnorm({g_now[S_HMD_ROT], g_now[S_HMD_ROT + 1], g_now[S_HMD_ROT + 2], g_now[S_HMD_ROT + 3]}); }

// the camera is the headset placed in the world: world_from_room = camera rotation * inverse(headset rotation)
namespace {
bool world_from_room(Quat& w, Vec3& cam) {
    if (!live()) return false;
    const Quat c = qnorm({g_now[S_CAM_ROT], g_now[S_CAM_ROT + 1], g_now[S_CAM_ROT + 2], g_now[S_CAM_ROT + 3]});
    w = qnorm(qmul(c, qinv(hmd_rot())));
    cam = {g_now[S_CAM_POS], g_now[S_CAM_POS + 1], g_now[S_CAM_POS + 2]};
    return std::isfinite(w.w) && std::isfinite(cam.x);
}
} // namespace
bool room_to_world(Vec3 room, Vec3& world) {
    Quat w; Vec3 cam;
    if (!world_from_room(w, cam)) return false;
    world = cam + rotate(w, room - hmd_pos());
    return true;
}
bool world_to_room(Vec3 world, Vec3& room) {
    Quat w; Vec3 cam;
    if (!world_from_room(w, cam)) return false;
    room = hmd_pos() + rotate(qinv(w), world - cam);
    return true;
}
bool world_dir_to_room(Vec3 dir, Vec3& room_dir) {
    Quat w; Vec3 cam;
    if (!world_from_room(w, cam)) return false;
    room_dir = rotate(qinv(w), dir);
    return true;
}
bool room_rot_to_world(Quat q, Quat& out) {
    Quat w; Vec3 cam;
    if (!world_from_room(w, cam)) return false;
    out = qnorm(qmul(w, q));
    return true;
}
bool room_dir_to_world(Vec3 dir, Vec3& world_dir) {
    Quat w; Vec3 cam;
    if (!world_from_room(w, cam)) return false;
    world_dir = rotate(w, dir);
    return true;
}

} // namespace vn::bridge
