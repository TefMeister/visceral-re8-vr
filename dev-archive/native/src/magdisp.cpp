// magdisp.cpp -- see magdisp.h
#include "magdisp.h"
#include "bridge.h"
#include "common.h"
#include "player.h"
#include "reload.h"
#include "reload_internal.h"
#include "settings.h"

#include <algorithm>
#include <vector>

namespace vn::magdisp {

using namespace vn::settings;
using reload::detail::g_gun;
using reload::detail::g_wtf;

namespace {
constexpr int VANISH_SLOTS = 8;   // bridge S_MAGTHROW_VANISH .. +7

struct Facts {                    // what this gun says about its magazine's look (read once per gun)
    MO* gun = nullptr;
    bool vanish_on = false;       // IsEnableVanishEmptyPartsDisp
    std::vector<int> vanish;      // switchVanishEmptyPartsDisp: the parts hidden when the magazine is empty (the rounds)
    int second = -1;              // SecondMagazinePartsNo (Customized when customizeMagazine)
    bool second_vanish_empty = false, second_vanish_noempty = false;
    bool any() const { return (vanish_on && !vanish.empty()) || (second >= 0 && (second_vanish_empty || second_vanish_noempty)); }
};
Facts g_f;
int g_applied = -2;               // the look written while out: 1 full, 0 empty; -1 = none (seated); -2 = never
int g_seen_loaded = -99;          // the gun's own count last logged (the game's own switching, learned live)

bool bfield(MO* o, const char* name) { const bool* p = field_ptr<bool>(o, name); return p != nullptr && *p; }
int ifield(MO* o, const char* name) { const int* p = field_ptr<int>(o, name); return p != nullptr ? *p : -1; }

void read_facts() {
    g_f = Facts{};
    g_f.gun = g_gun;
    if (!is_managed(g_gun)) return;
    bool custom = false;
    player::try_bool(g_gun, "get_customizeMagazine", custom);
    g_f.vanish_on = bfield(g_gun, "IsEnableVanishEmptyPartsDisp");
    g_f.second = ifield(g_gun, custom ? "SecondMagazinePartsNoCustomized" : "SecondMagazinePartsNo");
    g_f.second_vanish_empty = bfield(g_gun, "IsSecondVanishEmpty");
    g_f.second_vanish_noempty = bfield(g_gun, "IsSecondVanishNoEmpty");
    if (MO* list = field_obj(g_gun, "switchVanishEmptyPartsDisp")) {
        const int n = call_direct<int>(list, "get_Count", 0);
        for (int i = 0; i < n && i < 64; ++i) g_f.vanish.push_back((int)call_direct<uint32_t>(list, "get_Item", 0u, (int32_t)i));
    }
    std::string parts;
    for (int p : g_f.vanish) parts += (parts.empty() ? "" : " ") + std::to_string(p);
    LOGI("%s magdisp: %s: rounds parts that vanish when empty [%s] (%s), second magazine part %d (vanishes when %s), magazine part %d",
         TAG, reload::detail::g_id.c_str(), parts.c_str(), g_f.vanish_on ? "on" : "OFF", g_f.second,
         g_f.second_vanish_empty ? "empty" : g_f.second_vanish_noempty ? "not empty" : "never", reload::detail::mag_part());
    // the thrown copy's share of the facts (visceral_re8_magthrow.lua reads them with the hand-over)
    using namespace bridge;
    put(S_MAGTHROW_SECOND, g_f.second < 0 ? -1.0f : (float)(g_f.second + (g_f.second_vanish_empty ? 1000 : g_f.second_vanish_noempty ? 2000 : 0)));
    for (int i = 0; i < VANISH_SLOTS; ++i)
        put(static_cast<Slot>(S_MAGTHROW_VANISH + i), (g_f.vanish_on && i < (int)g_f.vanish.size()) ? (float)g_f.vanish[i] : -1.0f);
}

MO* gun_mesh() {
    auto* go = is_managed(g_wtf) ? call_ptr(g_wtf, "get_GameObject") : nullptr;
    return go != nullptr ? component(go, "via.render.Mesh") : nullptr;
}

void set_part(MO* mesh, API::Method* m, int part, bool on) {
    if (m == nullptr || part < 0) return;
    m->call<void>(API::get()->get_vm_context(), (void*)mesh, (uint64_t)part, on);
}

std::string pattern(MO* mesh) {   // the parts' on/off as the game has them now, for the log
    std::string s;
    auto bit = [&](int p) { return p < 0 ? std::string("-") : (call_direct<bool>(mesh, "getPartsEnable", false, (uint64_t)p) ? "1" : "0"); };
    s += "magazine " + bit(reload::detail::mag_part()) + ", second " + bit(g_f.second) + ", rounds";
    for (int p : g_f.vanish) s += " " + bit(p);
    return s;
}

// the look for `rounds` in the magazine: the rounds parts on when it holds any; the second part by the gun's own rule
void write_look(MO* mesh, API::Method* m, bool full) {
    if (g_f.vanish_on) for (int p : g_f.vanish) set_part(mesh, m, p, full);
    if (g_f.second >= 0) {
        if (g_f.second_vanish_empty) set_part(mesh, m, g_f.second, full);
        else if (g_f.second_vanish_noempty) set_part(mesh, m, g_f.second, !full);
    }
}
} // namespace

void point() {
    if (!MAGDISP_ON) return;
    if (!is_managed(g_gun)) { g_f = Facts{}; g_applied = -2; return; }
    if (g_f.gun != g_gun) { read_facts(); g_applied = -2; g_seen_loaded = -99; }
    if (!g_f.any()) return;
    MO* mesh = gun_mesh();
    if (mesh == nullptr) return;
    auto* m = player::overload(mesh, "setPartsEnable", 2);
    const int rounds = reload::mag_rounds_out();
    if (rounds < 0) {   // seated: the game's own look. Once, on the way back in, its own switch is run so the parts match the gun again
        if (g_applied >= 0) {
            call_ptr(g_gun, "execSwitchVanishEmptyPartsDisp");
            LOGI("%s magdisp: %s magazine back in: the game's own look again (%s)", TAG, reload::detail::g_id.c_str(), pattern(mesh).c_str());
        }
        g_applied = -1;
        // learning the game's own switching, live: the parts' pattern at every change of the gun's count (first find, 2026-10-31 row)
        const int n = player::loaded();
        if (n != g_seen_loaded && n >= 0 && n <= 2) {
            g_seen_loaded = n;
            LOGI("%s magdisp: %s the game's own look with %d loaded: %s", TAG, reload::detail::g_id.c_str(), n, pattern(mesh).c_str());
        }
        return;
    }
    const int want = rounds > 0 ? 1 : 0;
    if (want != g_applied) {
        LOGI("%s magdisp: %s magazine out with %d round(s): shown %s (before: %s)", TAG, reload::detail::g_id.c_str(), rounds,
             want ? "FULL" : "EMPTY", pattern(mesh).c_str());
        g_applied = want;
    }
    write_look(mesh, m, want == 1);   // every point: the game's own switch may run between them
}

} // namespace vn::magdisp
