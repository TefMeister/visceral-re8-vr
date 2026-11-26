// doorsounds.cpp -- see doorsounds.h
#include "doorsounds.h"

#include "base.h"
#include "paths.h"

#include <atomic>
#include <cctype>
#include <cstring>
#include <fstream>
#include <string>

namespace vr8::doorsounds {

namespace {
// ---- the ten kinds: name and name hash (app.DoorSeTriggerType's <Name>Hash constants, read from the exe) ---------
constexpr int KINDS = 10;
constexpr int UNKNOWN = KINDS;               // a sound whose kind is none of the ten (counted, never muted)
struct KindInfo { const char* name; uint32_t hash; bool muted_by_default; };
const KindInfo KIND[KINDS] = {
    {"Locked", 3401490761u, false},
    {"CreakSlow", 1884312664u, false},
    {"CreakStop", 3741696246u, false},
    {"OpenKnob", 3881480549u, true},         // [hypothesis, by name] the "door is now partly open" sound
    {"OpenLock", 3567993302u, false},
    {"OpenSlow", 165766960u, false},
    {"CloseCreakShort", 2057132247u, false},
    {"CloseCreakLong", 2638778551u, false},
    {"Close", 1212689092u, false},
    {"CloseSoft", 3119021430u, false},
};
constexpr float LIST_EVERY_S = 2.0f;         // how often doorsounds.txt is looked at
constexpr float STATICS_EVERY_S = 1.0f;      // how often the game's ten Value objects are looked for until found
constexpr int HASH_AT = 0x14;                // app.DoorSeTriggerType.Value: a class; V at +0x10, H (the hash) at +0x14
constexpr int MAX_LINES = 400;               // log lines of this part per run

// ---- shared with the hooks (rule 8: plain numbers only) --------------------------------------------------------
std::atomic<bool> g_mute[KINDS + 1];
std::atomic<void*> g_value_object[KINDS];    // the game's own Value objects, for the "by object" form
std::atomic<unsigned> g_played[KINDS + 1], g_skipped[KINDS + 1];

// ---- main thread only ------------------------------------------------------------------------------------------
bool g_hook_tried = false;
int g_values_known = 0;
float g_statics_at = -STATICS_EVERY_S, g_list_at = -LIST_EVERY_S;
unsigned g_told_played[KINDS + 1]{}, g_told_skipped[KINDS + 1]{};
std::string g_list_text = "\x01";            // what the file held last time (a value no file can hold)
int g_lines = 0;

int kind_of_hash(uint32_t hash) {
    for (int k = 0; k < KINDS; ++k)
        if (KIND[k].hash == hash) return k;
    return UNKNOWN;
}

int count(int kind) {
    if (g_mute[kind].load(std::memory_order_relaxed)) {
        g_skipped[kind].fetch_add(1, std::memory_order_relaxed);
        return REFRAMEWORK_HOOK_SKIP_ORIGINAL;
    }
    g_played[kind].fetch_add(1, std::memory_order_relaxed);
    return REFRAMEWORK_HOOK_CALL_ORIGINAL;
}

// CallSE(app.DoorSeTriggerType.Value): argv = context, the door, the Value object. The object is only COMPARED
// with the ten addresses found on the main thread, never read here.
int pre_call_se_object(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    if (argc < 3 || argv == nullptr) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    int kind = UNKNOWN;
    for (int k = 0; k < KINDS; ++k)
        if (argv[2] != nullptr && argv[2] == g_value_object[k].load(std::memory_order_relaxed)) { kind = k; break; }
    return count(kind);
}

// CallSE(System.UInt32): the third argument IS the name hash
int pre_call_se_hash(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    if (argc < 3 || argv == nullptr) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    return count(kind_of_hash((uint32_t)(uintptr_t)argv[2]));
}

void post_nothing(void**, REFrameworkTypeDefinitionHandle, unsigned long long) {}

void place_hooks() {
    if (g_hook_tried) return;
    g_hook_tried = true;
    for (int k = 0; k <= KINDS; ++k) g_mute[k] = k < KINDS && KIND[k].muted_by_default;
    auto* tdb = API::get()->tdb();
    auto* by_object = tdb->find_method("app.DoorBehavior", "CallSE(app.DoorSeTriggerType.Value)");
    auto* by_hash = tdb->find_method("app.DoorBehavior", "CallSE(System.UInt32)");
    if (by_object != nullptr) by_object->add_hook(pre_call_se_object, post_nothing, false);
    if (by_hash != nullptr) by_hash->add_hook(pre_call_se_hash, post_nothing, false);
    LOGI("%s door sounds: the door's sound call is watched (by object: %s, by number: %s)", TAG,
         by_object != nullptr ? "yes" : "NOT FOUND", by_hash != nullptr ? "yes" : "NOT FOUND");
}

// the game's ten Value objects (static fields of app.DoorSeTriggerType); each is checked by its own hash before
// its address is trusted
void find_value_objects(float now) {
    if (g_values_known == KINDS || now - g_statics_at < STATICS_EVERY_S) return;
    g_statics_at = now;
    auto* type = API::get()->tdb()->find_type("app.DoorSeTriggerType");
    if (type == nullptr) return;
    int known = 0;
    for (int k = 0; k < KINDS; ++k) {
        if (g_value_object[k].load() != nullptr) { ++known; continue; }
        auto* field = type->find_field(KIND[k].name);
        auto** slot = field != nullptr ? (MO**)field->get_data_raw(nullptr, false) : nullptr;
        if (slot == nullptr || !is_managed(*slot)) continue;
        uint32_t hash = 0;
        std::memcpy(&hash, (const char*)*slot + HASH_AT, sizeof hash);
        if (hash != KIND[k].hash) {
            if (g_lines++ < MAX_LINES)
                LOGW("%s door sounds: the game's %s object holds %u, %u was expected; that kind is left unknown", TAG,
                     KIND[k].name, hash, KIND[k].hash);
            continue;
        }
        g_value_object[k] = *slot;
        ++known;
    }
    if (known != g_values_known && known == KINDS) LOGI("%s door sounds: all ten kinds are known by their objects", TAG);
    g_values_known = known;
}

void read_list(float now) {
    if (now - g_list_at < LIST_EVERY_S) return;
    g_list_at = now;
    std::ifstream f(paths::data(L"doorsounds.txt"));
    const bool have_file = f.good();
    std::string text((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    if (!have_file) text = "\x02";
    if (text == g_list_text) return;
    g_list_text = text;
    std::string muted;
    for (int k = 0; k < KINDS; ++k) {
        bool mute = KIND[k].muted_by_default;
        if (have_file) {
            // a whole word of the file: "Close" must not be found inside "CloseSoft"
            mute = false;
            const std::string name = KIND[k].name;
            for (size_t at = text.find(name); at != std::string::npos; at = text.find(name, at + 1)) {
                const bool starts = at == 0 || !std::isalnum((unsigned char)text[at - 1]);
                const size_t end = at + name.size();
                const bool ends = end >= text.size() || !std::isalnum((unsigned char)text[end]);
                if (starts && ends) { mute = true; break; }
            }
        }
        g_mute[k] = mute;
        if (mute) muted += std::string(KIND[k].name) + " ";
    }
    LOGI("%s door sounds: muted now (%s): %s", TAG, have_file ? "doorsounds.txt" : "the built-in list",
         muted.empty() ? "none" : muted.c_str());
}

void tell() {
    for (int k = 0; k <= KINDS; ++k) {
        const unsigned played = g_played[k].load(std::memory_order_relaxed);
        const unsigned skipped = g_skipped[k].load(std::memory_order_relaxed);
        const char* name = k < KINDS ? KIND[k].name : "a kind not on the list";
        if (played != g_told_played[k] && g_lines++ < MAX_LINES)
            LOGI("%s door sound: %s (played; %u so far)", TAG, name, played);
        if (skipped != g_told_skipped[k] && g_lines++ < MAX_LINES)
            LOGI("%s door sound: %s (MUTED; %u so far)", TAG, name, skipped);
        g_told_played[k] = played;
        g_told_skipped[k] = skipped;
    }
}
} // namespace

void frame() {
    place_hooks();
    const float now = now_s();
    find_value_objects(now);
    read_list(now);
    tell();
}

} // namespace vr8::doorsounds
